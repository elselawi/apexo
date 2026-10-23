<#
.SYNOPSIS
    Builds or verifies the MSIX package that carries both Windows activation
    contracts.

.DESCRIPTION
    The `msix` tool regenerates AppxManifest.xml on every `msix:build`, and
    `msix:create` is build+pack, so a manifest patch only survives between
    `msix:build` and `msix:pack`. This script runs that order, checks every
    step, and verifies the package it produced in this very run.

    In local mode, `--sign-msix false` is deliberate: without it the msix tool
    replaces the configured publisher with the subject of its bundled test
    certificate, which changes the package family name the notification AUMID
    depends on. Release signing is a separate concern.

    What a green run proves: the manifest declares the expected identity,
    dependency and both activation contracts, and the package extracts with that
    manifest inside. It does NOT prove that the package installs, that Windows
    registers the activators, or that WNS delivers a notification.

.PARAMETER SkipBuild
    Reuse the existing build folder. The manifest must exist and be newer than
    the packaged executable, otherwise the script refuses to continue.

.PARAMETER SkipPack
    Verify an existing .msix without building, generating or patching anything.
    The package must already exist at the configured output path. This branch is
    read-only with respect to the package and its inputs; it reports that reuse
    explicitly because it does not prove the package corresponds to the current
    sources.

.PARAMETER SkipFlutterBuild
    Do not run `flutter build windows` first, but still regenerate and patch the
    package manifest. Use this after `shorebird release` so the Shorebird build
    output is packaged without being rebuilt by the local Flutter SDK.

.PARAMETER Store
    Produce a Microsoft Store submission package: pass `--store` to `msix`
    instead of signing a local package. The configured identity and publisher
    are still verified before packing.

.PARAMETER KeepExtract
    Leave the extracted package under build/ for inspection.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/patch_msix_manifest.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/patch_msix_manifest.ps1 -SkipPack
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$SkipPack,
    [switch]$SkipFlutterBuild,
    [switch]$Store,
    [switch]$KeepExtract,
    [ValidateSet('Release', 'Debug')]
    [string]$Mode = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'
$identityPath = Join-Path $repoRoot 'lib/services/notifications/windows_notification_identity.dart'
$patchTool = Join-Path $repoRoot 'tools/patch_push_manifest.dart'
$runStart = Get-Date
$extractDir = $null
$locationPushed = $false

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-External {
    param(
        [string]$Description,
        [string]$FilePath,
        [string[]]$Arguments
    )
    Write-Step $Description
    Write-Host "    $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }
    if ($exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode."
    }
}

function Get-MsixConfigValue {
    param([string]$Key)
    $pattern = '^\s+' + [regex]::Escape($Key) + ':\s*(.+?)\s*$'
    $inBlock = $false
    foreach ($line in Get-Content -LiteralPath $pubspecPath) {
        if (-not $inBlock) {
            if ($line -match '^msix_config:\s*$') { $inBlock = $true }
            continue
        }
        if ($line -match '^\S') { break }
        if ($line -match $pattern) {
            return $matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Get-PubspecName {
    foreach ($line in Get-Content -LiteralPath $pubspecPath) {
        if ($line -match '^name:\s*(\S+)') { return $matches[1].Trim('"').Trim("'") }
    }
    return $null
}

function Get-AumidHash {
    $text = Get-Content -LiteralPath $identityPath -Raw
    $match = [regex]::Match($text, 'appUserModelId\s*=\s*"([^"]+)"')
    if (-not $match.Success) {
        throw "'$identityPath' has no appUserModelId."
    }
    $family = ($match.Groups[1].Value -split '!')[0]
    $parts = $family.Split('_')
    return $parts[$parts.Count - 1]
}

# The msix tool selects build/windows/<architecture>/runner when it exists and
# falls back to the legacy build/windows/runner otherwise. Resolve the same way,
# then verify the chosen folder actually exists.
function Resolve-BuildFolder {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Architecture,
        [Parameter(Mandatory = $true)][string]$BuildMode
    )
    $archRunner = Join-Path $Root "build/windows/$Architecture/runner"
    if (Test-Path -LiteralPath $archRunner -PathType Container) {
        return Join-Path $archRunner $BuildMode
    }
    if ($Architecture -ne 'x64') {
        throw "cannot find the $Architecture build folder at '$archRunner'; Flutter must build that target before packaging."
    }
    return Join-Path $Root "build/windows/runner/$BuildMode"
}

function Resolve-MsixPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$BuildFolder,
        [string]$ConfiguredOutputPath,
        [Parameter(Mandatory = $true)][string]$OutputName
    )
    if ([string]::IsNullOrWhiteSpace($ConfiguredOutputPath)) {
        $outputFolder = $BuildFolder
    }
    elseif ([System.IO.Path]::IsPathRooted($ConfiguredOutputPath)) {
        $outputFolder = $ConfiguredOutputPath
    }
    else {
        $outputFolder = Join-Path $Root $ConfiguredOutputPath
    }
    return Join-Path $outputFolder "$OutputName.msix"
}

try {
    Push-Location -LiteralPath $repoRoot
    $locationPushed = $true

    Write-Host "Apexo MSIX packaging ($Mode)" -ForegroundColor Green
    Write-Host "repository: $repoRoot"

    foreach ($required in @($pubspecPath, $identityPath, $patchTool)) {
        if (-not (Test-Path -LiteralPath $required)) {
            throw "expected '$required' in the repository; is '$repoRoot' a checkout of Apexo?"
        }
    }

    $appName = Get-PubspecName
    if ([string]::IsNullOrWhiteSpace($appName)) { throw "pubspec.yaml has no 'name'." }

    $architecture = Get-MsixConfigValue -Key 'architecture'
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = 'x64' }
    if (@('x64', 'arm64') -notcontains $architecture) {
        throw "msix_config.architecture is '$architecture'; this script supports x64 and arm64."
    }
    $architecture = $architecture.ToLowerInvariant()

    $identityName = Get-MsixConfigValue -Key 'identity_name'
    if ([string]::IsNullOrWhiteSpace($identityName)) { throw 'pubspec.yaml has no msix_config.identity_name.' }
    $publisher = Get-MsixConfigValue -Key 'publisher'
    if ([string]::IsNullOrWhiteSpace($publisher)) { throw 'pubspec.yaml has no msix_config.publisher.' }

    $outputName = Get-MsixConfigValue -Key 'output_name'
    if ([string]::IsNullOrWhiteSpace($outputName)) { $outputName = $appName }
    $outputPath = Get-MsixConfigValue -Key 'output_path'

    # Flutter's Windows build has no architecture flag: it builds the host
    # architecture. Refuse to advertise an architecture the build cannot
    # produce rather than silently packaging a different target.
    $hostArchitecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }
    if ($architecture -ne $hostArchitecture) {
        throw "msix_config.architecture is '$architecture' but this host is '$hostArchitecture'. Flutter builds Windows for the host architecture; run this on a $architecture host or set the configuration to '$hostArchitecture'."
    }

    if ($SkipPack) {
        # Read-only reuse: do not build, regenerate, patch, delete or compare
        # against a manifest this branch never creates. When the package lives
        # outside the default output folder, the build folder is irrelevant.
        if ([string]::IsNullOrWhiteSpace($outputPath)) {
            $buildFolder = Resolve-BuildFolder -Root $repoRoot -Architecture $architecture -BuildMode $Mode
        }
        else {
            $buildFolder = $repoRoot
        }
        $msixPath = Resolve-MsixPath -Root $repoRoot -BuildFolder $buildFolder `
            -ConfiguredOutputPath $outputPath -OutputName $outputName
        if (-not (Test-Path -LiteralPath $msixPath -PathType Leaf)) {
            throw "-SkipPack was given but '$msixPath' does not exist."
        }

        Write-Step 'Package being verified (read-only reuse)'
        Write-Host "    path   : $msixPath"
    }
    else {
        $buildFolder = $null
        if (-not $SkipBuild) {
            if (-not $SkipFlutterBuild) {
                $flutterMode = if ($Mode -eq 'Debug') { '--debug' } else { '--release' }
                Invoke-External -Description 'Building the Windows app' `
                    -FilePath 'flutter' -Arguments @(
                        'build', 'windows', $flutterMode
                    )
            }

            $buildArguments = @(
                'run', 'msix:build'
            )
            if ($Store) {
                $buildArguments += '--store'
            }
            else {
                $buildArguments += @('--sign-msix', 'false')
            }
            $buildArguments += @('--architecture', $architecture)
            if ($Mode -eq 'Debug') { $buildArguments += '--debug' }
            Invoke-External -Description 'Generating the package manifest' `
                -FilePath 'dart' -Arguments $buildArguments
        }
        else {
            Write-Step 'Reusing the existing build folder'
        }

        # Select the folder after Flutter/msix generation; a clean checkout has
        # no architecture-specific directory until then.
        $buildFolder = Resolve-BuildFolder -Root $repoRoot -Architecture $architecture -BuildMode $Mode
        if (-not (Test-Path -LiteralPath $buildFolder -PathType Container)) {
            throw "the build folder '$buildFolder' does not exist; run without -SkipBuild."
        }
        $manifestPath = Join-Path $buildFolder 'AppxManifest.xml'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            throw "no AppxManifest.xml at '$manifestPath'; run without -SkipBuild."
        }

        $manifestText = Get-Content -LiteralPath $manifestPath -Raw
        $executableMatch = [regex]::Match($manifestText, '<Application\b[^>]*\bExecutable="([^"]+)"')
        if (-not $executableMatch.Success) {
            throw "'$manifestPath' has no <Application Executable=...>."
        }
        $executablePath = Join-Path $buildFolder $executableMatch.Groups[1].Value
        if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
            throw "'$executablePath' does not exist; run 'flutter build windows' first."
        }

        if ($SkipBuild -and
            (Get-Item -LiteralPath $manifestPath).LastWriteTimeUtc -lt (Get-Item -LiteralPath $executablePath).LastWriteTimeUtc) {
            throw "'$manifestPath' is older than '$executablePath', so it does not describe this build. Re-run without -SkipBuild."
        }

        Invoke-External -Description 'Patching the manifest (runtime dependency + push activation)' `
            -FilePath 'dart' -Arguments @('run', $patchTool, $manifestPath)
        Invoke-External -Description 'Verifying the patched manifest' `
            -FilePath 'dart' -Arguments @('run', $patchTool, $manifestPath, '--verify')

        $msixPath = Resolve-MsixPath -Root $repoRoot -BuildFolder $buildFolder `
            -ConfiguredOutputPath $outputPath -OutputName $outputName
        # msix:pack deletes AppxManifest.xml after packing, so remember its time now.
        $manifestTime = (Get-Item -LiteralPath $manifestPath).LastWriteTime

        $packArguments = @(
            'run', 'msix:pack'
        )
        if ($Store) {
            $packArguments += '--store'
        }
        else {
            $packArguments += @('--sign-msix', 'false')
        }
        $packArguments += @('--architecture', $architecture)
        if ($Mode -eq 'Debug') { $packArguments += '--debug' }
        Invoke-External -Description 'Packing the MSIX' -FilePath 'dart' -Arguments $packArguments

        if (-not (Test-Path -LiteralPath $msixPath -PathType Leaf)) {
            throw "msix:pack reported success but '$msixPath' does not exist."
        }
        $msixTime = (Get-Item -LiteralPath $msixPath).LastWriteTime
        if ($msixTime -lt $runStart) {
            throw "'$msixPath' was not produced by this run (older than the run start); delete it and try again."
        }
        if ($msixTime -lt $manifestTime) {
            throw "'$msixPath' is older than the patched manifest, so it does not contain this manifest."
        }

        Write-Step 'Package produced by this run'
        Write-Host "    path   : $msixPath"
    }

    $msix = Get-Item -LiteralPath $msixPath
    Write-Host "    size   : $($msix.Length) bytes"
    Write-Host "    sha256 : $((Get-FileHash -LiteralPath $msixPath -Algorithm SHA256).Hash)"

    $extractDir = Join-Path $repoRoot ("build/msix-verify-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    Write-Step 'Extracting the package'
    # Expand-Archive only accepts .zip on Windows PowerShell; a .msix is a zip.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($msixPath, $extractDir)
    $packagedManifest = Join-Path $extractDir 'AppxManifest.xml'
    if (-not (Test-Path -LiteralPath $packagedManifest -PathType Leaf)) {
        throw 'the package contains no AppxManifest.xml.'
    }

    Invoke-External -Description 'Verifying the packaged manifest' `
        -FilePath 'dart' -Arguments @('run', $patchTool, $packagedManifest, '--verify')

    Write-Step 'Observed package family name'
    $installed = @()
    try {
        $installed = @(Get-AppxPackage -Name $identityName -ErrorAction SilentlyContinue)
    }
    catch {
        Write-Host '    could not query the package database; treating the PFN as unconfirmed.' -ForegroundColor Yellow
    }

    $matching = @($installed | Where-Object { $_.Publisher -eq $publisher })
    if ($installed.Count -eq 0) {
        Write-Host "    PFN not confirmed - no installed package named '$identityName'." -ForegroundColor Yellow
    }
    elseif ($matching.Count -eq 0) {
        Write-Host "    PFN not confirmed - no installed package named '$identityName' has publisher '$publisher'." -ForegroundColor Yellow
    }
    else {
        $selected = $matching |
            Sort-Object -Property `
                @{ Expression = { try { [version]$_.Version } catch { [version]'0.0.0.0' } }; Descending = $true },
                @{ Expression = { if ($_.Architecture -eq 'X64') { 0 } else { 1 } }; Descending = $false } |
            Select-Object -First 1
        $hashes = @($matching | ForEach-Object {
                $parts = $_.PackageFullName -split '__'
                if ($parts.Count -ge 2) { $parts[$parts.Count - 1] } else { '' }
            } | Sort-Object -Unique)
        Write-Host "    selected : $($selected.PackageFullName)"
        if ($hashes.Count -gt 1) {
            throw "installed packages with publisher '$publisher' resolve to different family names ($($hashes -join ', ')); the AUMID cannot be trusted."
        }
        if ($hashes[0] -ne (Get-AumidHash)) {
            throw "the installed package resolves to family hash '$($hashes[0])' but the AUMID expects '$(Get-AumidHash)'."
        }
        Write-Host "    PFN confirmed from the installed package: $($selected.PackageFamilyName)" -ForegroundColor Green
    }

    Write-Host ''
    if ($SkipPack) {
        Write-Host 'Verification complete: existing package reused; no build, patch, or pack was performed.' -ForegroundColor Green
    }
    elseif ($SkipBuild) {
        Write-Host 'Package complete: existing build and manifest reused; patched, packed, and verified.' -ForegroundColor Green
    }
    elseif ($SkipFlutterBuild) {
        Write-Host 'Package complete: existing Flutter build reused (-SkipFlutterBuild); patched, packed, and verified.' -ForegroundColor Green
    }
    else {
        Write-Host 'Package complete: built, patched, packed, and verified.' -ForegroundColor Green
    }
    Write-Host "MSIX: $msixPath" -ForegroundColor Green
    Write-Verbose 'Manifest consistency and packaging integrity only; installed-app WNS delivery is a separate acceptance step.'
}
finally {
    try {
        if ($null -ne $extractDir -and (Test-Path -LiteralPath $extractDir)) {
            if ($KeepExtract) {
                Write-Host "extracted package kept at $extractDir"
            }
            else {
                try { Remove-Item -LiteralPath $extractDir -Recurse -Force }
                catch { Write-Warning "could not remove '$extractDir': $_" }
            }
        }
    }
    finally {
        if ($locationPushed) { Pop-Location }
    }
}

# Restores the native packages the Windows runner needs (Windows App SDK 1.7).
#
# The Flutter Windows build is a plain CMake/MSBuild project, so NuGet restore is
# not automatic. This script is idempotent and validates what is already on disk:
# a package pass is not enough if its extracted content is incomplete or its
# nuspec version no longer matches packages.config. `-ExcludeVersion` gives stable
# folder names the CMake build can rely on.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File windows/restore_windows_packages.ps1
#   powershell -ExecutionPolicy Bypass -File windows/restore_windows_packages.ps1 -Force
#
# The folder windows/packages is git-ignored on purpose: it is a build artifact.

[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$windowsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $windowsDir 'packages.config'
$packagesDir = Join-Path $windowsDir 'packages'

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Missing $configPath; cannot restore the Windows native packages."
}

[xml]$config = Get-Content -LiteralPath $configPath -Raw
$expected = @()
foreach ($package in $config.packages.package) {
    $expected += [pscustomobject]@{
        Id      = [string]$package.id
        Version = [string]$package.version
        Path    = Join-Path $packagesDir ([string]$package.id)
    }
}
if ($expected.Count -eq 0) {
    throw "$configPath contains no packages."
}

function Read-NuspecIdentity {
    param(
        [Parameter(Mandatory = $true)][xml]$Document,
        [Parameter(Mandatory = $true)][string]$Source
    )
    $metadata = $Document.SelectSingleNode(
        "/*[local-name()='package']/*[local-name()='metadata']")
    if ($null -eq $metadata) {
        throw "$Source has no package metadata."
    }
    $idNode = $metadata.SelectSingleNode("*[local-name()='id']")
    $versionNode = $metadata.SelectSingleNode("*[local-name()='version']")
    if ($null -eq $idNode -or $null -eq $versionNode) {
        throw "$Source has no package identity or version."
    }
    $id = $idNode.InnerText.Trim()
    $version = $versionNode.InnerText.Trim()
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($version)) {
        throw "$Source has an empty package identity or version."
    }
    return [pscustomobject]@{ Id = $id; Version = $version }
}

function Read-PackageIdentity {
    param([Parameter(Mandatory = $true)][string]$PackagePath)

    $root = (Resolve-Path -LiteralPath $PackagePath).Path
    $nuspecs = @(Get-ChildItem -LiteralPath $root -Filter '*.nuspec' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -eq $root })
    if ($nuspecs.Count -gt 1) {
        throw "$PackagePath contains more than one root nuspec; cannot identify the package."
    }
    if ($nuspecs.Count -eq 1) {
        [xml]$document = Get-Content -LiteralPath $nuspecs[0].FullName -Raw
        return Read-NuspecIdentity -Document $document -Source $nuspecs[0].FullName
    }

    $nupkgs = @(Get-ChildItem -LiteralPath $root -Filter '*.nupkg' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -eq $root })
    if ($nupkgs.Count -ne 1) {
        throw "$PackagePath has no single root nuspec or nupkg to identify it."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($nupkgs[0].FullName)
    try {
        $entries = @($archive.Entries | Where-Object {
                $_.FullName -notmatch '/' -and $_.FullName -like '*.nuspec'
            })
        if ($entries.Count -ne 1) {
            throw "$($nupkgs[0].FullName) has no single root nuspec."
        }
        $reader = New-Object System.IO.StreamReader($entries[0].Open())
        try {
            [xml]$document = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
        return Read-NuspecIdentity -Document $document -Source $nupkgs[0].FullName
    }
    finally {
        $archive.Dispose()
    }
}

function Test-NativePackage {
    param([Parameter(Mandatory = $true)]$Package)

    if (-not (Test-Path -LiteralPath $Package.Path -PathType Container)) {
        return $false
    }
    try {
        $identity = Read-PackageIdentity -PackagePath $Package.Path
    }
    catch {
        Write-Verbose "Could not read $($Package.Path): $_"
        return $false
    }
    if (-not [string]::Equals($identity.Id, $Package.Id, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Verbose "Expected $($Package.Id), found $($identity.Id) at $($Package.Path)."
        return $false
    }
    if ($identity.Version -ne $Package.Version) {
        Write-Verbose "Expected $($Package.Id) $($Package.Version), found $($identity.Version)."
        return $false
    }

    # These are the package-relative files the current CMake/manifest work
    # actually consumes. A directory name alone proves neither version nor
    # completeness.
    $required = @()
    switch ($Package.Id) {
        'Microsoft.Windows.CppWinRT' {
            $required = @('bin/cppwinrt.exe')
        }
        'Microsoft.WindowsAppSDK' {
            $required = @(
                'lib/uap10.0/Microsoft.Windows.PushNotifications.winmd',
                'lib/uap10.0/Microsoft.Windows.AppLifecycle.winmd',
                'WindowsAppSDK-VersionInfo.json'
            )
        }
        'Microsoft.Windows.ImplementationLibrary' {
            $required = @('include/wil/resource.h')
        }
        'Microsoft.Windows.SDK.BuildTools' {
            $required = @('bin')
            $toolVersions = @(Get-ChildItem -LiteralPath (Join-Path $Package.Path 'bin') -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64') -PathType Container })
            if ($toolVersions.Count -eq 0) {
                Write-Verbose "$($Package.Id) has no bin/<version>/x64 tools directory."
                return $false
            }
        }
    }
    foreach ($relative in $required) {
        $candidate = Join-Path $Package.Path $relative
        if (-not (Test-Path -LiteralPath $candidate)) {
            Write-Verbose "$($Package.Id) is missing $relative."
            return $false
        }
    }
    return $true
}

$invalid = @($expected | Where-Object { $Force -or -not (Test-NativePackage -Package $_) })
if ($invalid.Count -eq 0) {
    Write-Host 'Windows native packages are present, correctly versioned and complete.'
    exit 0
}

# Resolve NuGet before deleting anything, so a machine without NuGet is left
# exactly as it was.
$command = Get-Command nuget.exe -CommandType Application -ErrorAction SilentlyContinue
if ($null -ne $command) {
    $nugetPath = @($command)[0].Path
}
elseif (Test-Path -LiteralPath 'C:\tools\nuget.exe' -PathType Leaf) {
    $nugetPath = 'C:\tools\nuget.exe'
}
else {
    throw 'nuget.exe was not found on PATH or at C:\tools\nuget.exe. Install NuGet (https://www.nuget.org/downloads) or put it on PATH, then re-run this script.'
}

New-Item -ItemType Directory -Path $packagesDir -Force | Out-Null
$packagesRoot = [System.IO.Path]::GetFullPath($packagesDir).TrimEnd('\') + '\'

foreach ($package in $invalid) {
    $target = [System.IO.Path]::GetFullPath($package.Path)
    if (-not $target.StartsWith($packagesRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove '$target': it is outside $packagesDir."
    }
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }

    Write-Host "Restoring $($package.Id) $($package.Version)"
    & $nugetPath install $package.Id `
        -Version $package.Version `
        -OutputDirectory $packagesDir `
        -ExcludeVersion `
        -NonInteractive `
        -ForceEnglishOutput
    if ($LASTEXITCODE -ne 0) {
        throw "nuget install for $($package.Id) failed with exit code $LASTEXITCODE. Check the network/feed and re-run."
    }
}

$stillInvalid = @($expected | Where-Object { -not (Test-NativePackage -Package $_) })
if ($stillInvalid.Count -ne 0) {
    $names = ($stillInvalid | ForEach-Object { "$($_.Id) $($_.Version)" }) -join ', '
    throw "Restore did not produce valid packages: $names. Check the feed and re-run."
}

Write-Host "Windows native packages restored and validated in $packagesDir."

# Find Dart files nothing imports, and (with -Apply) delete them.
#
# A file is reported when no `import`, `export`, `part` or mention of its name
# appears anywhere else in the scanned trees. Two things are deliberately not
# treated as references, because they would hide real orphans:
#
#   * a reference from a file that is itself orphaned (reported too, so the two
#     are visible together — delete the roots first and re-run);
#   * a mention inside a comment: only directives and bare names count.
#
# Entry points and generated files are never reported: `lib/main.dart` is what
# the platform runs, and `*.g.dart` / `*.freezed.dart` belong to a generator.
#
# Usage:
#   pwsh -File tools/find_orphan_files.ps1
#   pwsh -File tools/find_orphan_files.ps1 -Paths lib
#   pwsh -File tools/find_orphan_files.ps1 -Apply       # delete the findings
param(
    [string[]]$Paths = @('lib', 'test', 'integration_test', 'test_driver', 'tools'),
    # Run by path — `dart run lib/services/localization/verify.dart` — so nothing
    # imports them by design. Everything under `tools/` is in this list too.
    [string[]]$EntryPoints = @(
        'lib\main.dart',
        'lib\services\localization\verify.dart',
        'integration_test\integration.dart',
        'integration_test\watch.dart'
    ),
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

# Files the toolchain reaches without an import.
$neverOrphan = @($EntryPoints)

$files = foreach ($path in $Paths) {
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -Recurse -File -Filter *.dart
    }
}
$files = @($files)

$contents = @{}
foreach ($file in $files) {
    $contents[$file.FullName] = [System.IO.File]::ReadAllText($file.FullName)
}

$orphans = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    $relative = $file.FullName.Replace((Get-Location).Path + '\', '')
    if ($neverOrphan -contains $relative) { continue }
    if ($relative.StartsWith('tools\')) { continue }
    if ($file.Name -like '*.g.dart' -or $file.Name -like '*.freezed.dart') { continue }
    if ($file.Name -like '*_test.dart' -or $file.Name -eq 'test_utils.dart') { continue }

    # The two names another file can reach this one by.
    $packageUri = 'package:apexo/' +
    ($relative.Substring('lib\'.Length) -replace '\\', '/')
    # A relative import names the file without its directory, and a conditional
    # import puts the platform-specific one behind an `if (...)`: so every
    # directive is examined, and the path before the name is allowed to have any
    # prefix (`groups/`, `../`, or nothing).
    $quoted = [regex]::Escape($file.Name)
    $directivePattern = "['""][^'""]*$quoted['""]"

    $referenced = $false
    foreach ($other in $files) {
        if ($other.FullName -eq $file.FullName) { continue }
        $text = $contents[$other.FullName]

        if ($text.Contains($packageUri)) { $referenced = $true; break }

        $found = $false
        $statement = ''
        foreach ($line in ($text -split "`n")) {
            if ($statement -eq '') {
                $trimmed = $line.TrimStart()
                if (-not ($trimmed.StartsWith('import ') -or
                        $trimmed.StartsWith('export ') -or
                        $trimmed.StartsWith('part '))) { continue }
                $statement = $line
            } else {
                # A conditional import can wrap onto the next line, which is
                # where the platform-specific name usually is.
                $statement += $line
            }
            if (-not $statement.Contains(';')) { continue }
            if ([regex]::IsMatch($statement, $directivePattern)) { $found = $true; break }
            $statement = ''
        }
        if ($found) { $referenced = $true; break }
    }
    if ($referenced) { continue }

    $orphans.Add([pscustomobject]@{
            File  = $relative
            Lines = ($contents[$file.FullName] -split "`n").Count
        })
}

Write-Host "Scanned $($files.Count) files under: $($Paths -join ', ')"
Write-Host "ORPHANED FILES: $($orphans.Count)`n"
$orphans | Sort-Object Lines -Descending | Format-Table File, Lines -AutoSize

if (-not $Apply) {
    Write-Host 'Report only. Re-run with -Apply to delete them.'
    return
}

foreach ($orphan in $orphans) {
    Remove-Item -LiteralPath (Join-Path (Get-Location) $orphan.File)
    Write-Host "removed $($orphan.File)"
}

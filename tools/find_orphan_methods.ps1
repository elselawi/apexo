# Find method declarations nothing refers to, and (with -Apply) delete them.
#
# How it decides, and why it is this blunt: a method is reported when its name
# appears **exactly once** across every scanned tree — that one time being the
# declaration. That is the only signal available without type resolution, so it
# is deliberately conservative in one direction and blind in another:
#
#   * a name that appears twice may well be a real call, so it is left alone;
#   * a name reached only through `dynamic` cannot be seen at all, so its method
#     is invisible here rather than wrongly deleted.
#
# Framework hooks are called by the framework, not by Dart code, so they appear
# once and are excluded by name below.
#
# Usage:
#   pwsh -File tools/find_orphan_methods.ps1
#   pwsh -File tools/find_orphan_methods.ps1 -Paths lib
#   pwsh -File tools/find_orphan_methods.ps1 -Apply      # delete the findings
param(
    [string[]]$Paths = @('lib', 'test', 'integration_test'),
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

# Called by the framework, not by Dart code in this repository.
$frameworkHooks = @(
    'main', 'build', 'createState', 'createElement', 'createRenderObject',
    'updateRenderObject', 'initState', 'dispose', 'deactivate', 'reassemble',
    'didChangeDependencies', 'didUpdateWidget', 'debugFillProperties',
    'debugDescribeChildren', 'shouldRebuild', 'shouldRepaint', 'paint',
    'performLayout', 'toString', 'hashCode', 'noSuchMethod', 'compareTo',
    'operator', 'State', 'createState'
)

# A statement can look exactly like a declaration — `await pumpEventQueue();` is
# `type name(` to a regex, and `pumpEventQueue` comes from `flutter_test`, so
# nothing here declares it and the name appears once. The first word of the
# "return type" is what gives it away.
$statementKeywords = @(
    'await', 'return', 'unawaited', 'yield', 'throw', 'assert', 'print',
    'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue',
    'final', 'var', 'const', 'late', 'super', 'this', 'await'
)

# A declaration is a line that starts with a return type and then a name and an
# open paren. Calls rarely look like that, and the ones that do (a named
# constructor) have no return type, so they are not matched.
$declarationPattern = '^(?<indent>\s{2,})(?<type>(?:static\s+|final\s+|external\s+)*[A-Za-z_][\w<>,\.\?\[\]\s]*?)\s+(?<name>[a-z_]\w*)\s*\('

$files = foreach ($path in $Paths) {
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -Recurse -File -Filter *.dart
    }
}
$files = @($files)

# Every identifier in the repository, counted once.
$counts = [System.Collections.Generic.Dictionary[string, int]]::new()
$contents = @{}
foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $contents[$file.FullName] = $text
    foreach ($match in [regex]::Matches($text, '\b[A-Za-z_]\w*\b')) {
        $name = $match.Value
        if ($counts.ContainsKey($name)) { $counts[$name]++ } else { $counts[$name] = 1 }
    }
}

$orphans = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    $lines = $contents[$file.FullName] -split "`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*//') { continue }
        $match = [regex]::Match($line, $declarationPattern)
        if (-not $match.Success) { continue }

        $name = $match.Groups['name'].Value
        if ($frameworkHooks -contains $name) { continue }

        # A call whose arguments wrapped onto the next line reads exactly like a
        # declaration: `patient.birth, inInclusiveRange(...)` is `type name(` to
        # a regex. A real return type has no operator, dot, comma or bracket in
        # it, and a declaration's line never ends in a comma.
        if ($match.Groups['type'].Value -match '[=,\.\(\[\]]') { continue }
        if ($line.TrimEnd().EndsWith(',')) { continue }
        $firstWord = ($match.Groups['type'].Value.Trim() -split '\s+')[0]
        if ($statementKeywords -contains $firstWord) { continue }

        if ($counts[$name] -ne 1) { continue }

        # An override is the framework's to call through a supertype.
        if ($i -gt 0 -and $lines[$i - 1].Trim() -eq '@override') { continue }

        $orphans.Add([pscustomobject]@{
                File = $file.FullName.Replace((Get-Location).Path + '\', '')
                Line = $i + 1
                Name = $name
            })
    }
}

Write-Host "Scanned $($files.Count) files under: $($Paths -join ', ')"
Write-Host "ORPHANED METHODS: $($orphans.Count)`n"
$orphans | ForEach-Object { Write-Host ($_.File + ":" + $_.Line + "  ->  " + $_.Name) }

if (-not $Apply) {
    Write-Host 'Report only. Re-run with -Apply to delete them.'
    return
}

# Delete from the bottom of each file up, so earlier lines keep their numbers.
$byFile = $orphans | Group-Object File
foreach ($group in $byFile) {
    $path = Join-Path (Get-Location) $group.Name
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]($contents[$path] -split "`n"))

    $starts = @($group.Group | Sort-Object Line -Descending | ForEach-Object { $_.Line })

    foreach ($start in $starts) {
        $index = $start - 1
        # Take the doc comment and annotations above it with it.
        $from = $index
        while ($from -gt 0) {
            $above = $lines[$from - 1].Trim()
            if ($above.StartsWith('///') -or $above.StartsWith('//') -or
                $above.StartsWith('@')) {
                $from--
            } else {
                break
            }
        }

        # The body ends where the declaration's braces close. An abstract or
        # arrow body ends at its own `;` instead. Braces are counted from zero
        # on the declaration's own text.
        $end = $index
        $depth = 0
        $opened = $false
        for ($i = $index; $i -lt $lines.Count; $i++) {
            foreach ($ch in $lines[$i].ToCharArray()) {
                if ($ch -eq '{') { $depth++; $opened = $true }
                elseif ($ch -eq '}') { $depth-- }
            }
            $end = $i
            if ($opened -and $depth -le 0) { break }
            if (-not $opened -and $lines[$i].TrimEnd().EndsWith(';')) { break }
        }

        $lines.RemoveRange($from, $end - $from + 1)
        Write-Host "removed $($group.Name):$start  ($($end - $from + 1) lines)"
    }

    [System.IO.File]::WriteAllText($path, ($lines -join "`n"))
}

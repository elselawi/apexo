# Summarise `flutter analyze` output into counts by rule and by directory.
# Usage:  pwsh -File tools/lint_report.ps1  [path-to-analyze.txt]
param(
    [string]$Path = "analyze.txt"
)

$pattern = '^\s*(?<sev>error|warning|info)\s+-\s+(?<msg>.*?)\s+-\s+(?<loc>.+?):(?<line>\d+):(?<col>\d+)\s+-\s+(?<rule>\S+)\s*$'

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($line in (Get-Content -LiteralPath $Path)) {
    if ($line -match $pattern) {
        $loc = $matches['loc'] -replace '\\', '/'
        $rows.Add([pscustomobject]@{
                Severity = $matches['sev']
                Rule     = $matches['rule']
                File     = $loc
                Line     = [int]$matches['line']
                Message  = $matches['msg']
            })
    }
}

Write-Host "TOTAL: $($rows.Count)"

Write-Host "`n=== BY SEVERITY ==="
$rows | Group-Object Severity | Sort-Object Count -Descending |
Format-Table Count, Name -AutoSize

Write-Host "`n=== BY RULE ==="
$rows | Group-Object Rule | Sort-Object Count -Descending |
Format-Table Count, Name -AutoSize

Write-Host "`n=== BY TOP-LEVEL DIRECTORY ==="
$rows | ForEach-Object {
    $parts = $_.File -split '/'
    if ($parts.Count -gt 1) { $parts[0] } else { '(root)' }
} | Group-Object | Sort-Object Count -Descending |
Format-Table Count, Name -AutoSize

Write-Host "`n=== RULE x DIRECTORY (rule, dir, count) ==="
$rows | Group-Object Rule | Sort-Object Count -Descending | ForEach-Object {
    $rule = $_.Name
    $_.Group | ForEach-Object {
        $parts = $_.File -split '/'
        if ($parts.Count -gt 1) { $parts[0] } else { '(root)' }
    } | Group-Object | Sort-Object Count -Descending | Select-Object -First 6 | ForEach-Object {
        "{0,-45} {1,-16} {2}" -f $rule, $_.Name, $_.Count
    }
}

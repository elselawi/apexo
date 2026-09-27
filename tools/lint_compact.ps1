# One issue per line: <sev> <file>:<line>:<col> [<rule>] <message>
# Usage:  pwsh -File tools/lint_compact.ps1 argument_type_not_assignable,invalid_assignment
param(
    [Parameter(Position = 0)][string]$Rule,
    [string]$Path = "analyze.txt",
    [int]$Limit = 0
)

$pattern = '^\s*(?<sev>error|warning|info)\s+-\s+(?<msg>.*?)\s+-\s+(?<loc>.+?):(?<line>\d+):(?<col>\d+)\s+-\s+(?<rule>\S+)\s*$'
$wanted = if ($Rule) { $Rule -split ',' | ForEach-Object { $_.Trim() } } else { $null }

$rows = foreach ($line in (Get-Content -LiteralPath $Path)) {
    if ($line -match $pattern) {
        if (-not $wanted -or ($wanted -contains $matches['rule'])) {
            [pscustomobject]@{
                Rule    = $matches['rule']
                Sev     = $matches['sev']
                File    = ($matches['loc'] -replace '\\', '/')
                Line    = [int]$matches['line']
                Col     = [int]$matches['col']
                Message = $matches['msg']
            }
        }
    }
}

if ($Limit -gt 0) { $rows = $rows | Select-Object -First $Limit }

$rows | ForEach-Object {
    "{0} {1}:{2}:{3} [{4}] {5}" -f $_.Sev, $_.File, $_.Line, $_.Col, $_.Rule, $_.Message
}
Write-Host "TOTAL: $(($rows | Measure-Object).Count)"

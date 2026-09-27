# List every occurrence of one or more lint rules from a saved `flutter analyze` log.
# Usage:  pwsh -File tools/lint_by_rule.ps1 discarded_futures
#         pwsh -File tools/lint_by_rule.ps1 avoid_dynamic_calls,strict_raw_type -Path analyze.txt
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Rule,

    [string]$Path = "analyze.txt",

    [switch]$WithMessage,

    [int]$Limit = 0
)

$wanted = $Rule -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$pattern = '^\s*(?<sev>error|warning|info)\s+-\s+(?<msg>.*?)\s+-\s+(?<loc>.+?):(?<line>\d+):(?<col>\d+)\s+-\s+(?<rule>\S+)\s*$'

$rows = foreach ($line in (Get-Content -LiteralPath $Path)) {
    if ($line -match $pattern -and $wanted -contains $matches['rule']) {
        [pscustomobject]@{
            Rule    = $matches['rule']
            File    = $matches['loc'] -replace '\\', '/'
            Line    = [int]$matches['line']
            Col     = [int]$matches['col']
            Message = $matches['msg']
        }
    }
}

if ($Limit -gt 0) { $rows = $rows | Select-Object -First $Limit }

if ($WithMessage) {
    $rows | Format-Table File, Line, Col, Message -AutoSize -Wrap
}
else {
    $rows | Group-Object File | Sort-Object Count -Descending |
    Format-Table Count, Name -AutoSize
    Write-Host "TOTAL: $(($rows | Measure-Object).Count)"
}

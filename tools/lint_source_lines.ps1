# For each occurrence of a lint rule, print the trimmed source line and group by it.
# This reveals repeated patterns, so one review can cover hundreds of hits.
# Usage:  pwsh -File tools/lint_source_lines.ps1 discarded_futures,unawaited_futures
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Rule,

    [string]$Path = "analyze.txt"
)

$wanted = $Rule -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$pattern = '^\s*(?<sev>error|warning|info)\s+-\s+(?<msg>.*?)\s+-\s+(?<loc>.+?):(?<line>\d+):(?<col>\d+)\s+-\s+(?<rule>\S+)\s*$'

$cache = @{}
$rows = foreach ($line in (Get-Content -LiteralPath $Path)) {
    if ($line -match $pattern -and $wanted -contains $matches['rule']) {
        $file = $matches['loc']
        $lineNo = [int]$matches['line']
        if (-not $cache.ContainsKey($file)) {
            $cache[$file] = if (Test-Path -LiteralPath $file) {
                @(Get-Content -LiteralPath $file)
            }
            else { @() }
        }
        $content = $cache[$file]
        $text = if ($lineNo -le $content.Count) { $content[$lineNo - 1].Trim() } else { '<unreadable>' }
        [pscustomobject]@{
            Text = $text
            File = $file -replace '\\', '/'
            Line = $lineNo
        }
    }
}

$rows | Group-Object Text | Sort-Object Count -Descending | ForEach-Object {
    "{0,4}x  {1}" -f $_.Count, $_.Name
    $_.Group | Select-Object -First 2 | ForEach-Object { "         {0}:{1}" -f $_.File, $_.Line }
}
Write-Host "`nDISTINCT PATTERNS: $(($rows | Group-Object Text | Measure-Object).Count)  OCCURRENCES: $(($rows | Measure-Object).Count)"

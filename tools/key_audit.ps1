# Which widget keys does the e2e suite wait for that the app never attaches?
#
#   pwsh -File tools/key_audit.ps1
#
# The suite addresses the app through `lib/widget_keys.dart`, and a key that is
# *declared* but attached to nothing is the worst kind of failure: `Fixtures.openRoute`
# taps the nav item (which lands), then waits 60s for a screen key that can never
# appear, and the report reads "the screen never opened". That is what 52 keys looked
# like on 2026-09-28, after `af8e771` rolled the localpocket migration back and
# `ef3a3fd` restored this suite against the older UI (see integration_test/todo.md's
# opening note, and §0.2 for the list).
#
# Two questions, answered in order:
#   1. every `WK.<name>` declared in lib/widget_keys.dart and never mentioned in lib/
#   2. of those, the ones integration_test/ actually uses — those are the blockers
param()

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $names = @()
    foreach ($line in (Get-Content lib/widget_keys.dart)) {
        # `static Key name(...)` (a factory for a computed key) and
        # `static [const] <type> name = Key(...)`.
        if ($line -match 'static\s+(?:const\s+)?Key\s+(\w+)\s*\(') { $names += $matches[1] }
        elseif ($line -match 'static\s+(?:const\s+)?\w+\s+(\w+)\s*=\s*Key\(') { $names += $matches[1] }
    }
    $names = $names | Sort-Object -Unique

    $libText = (Get-ChildItem lib -Recurse -File -Filter *.dart |
        Where-Object { $_.Name -ne 'widget_keys.dart' } |
        ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"

    $unattached = @()
    foreach ($n in $names) {
        if ($libText -notmatch "WK\.$n\b") { $unattached += $n }
    }

    $e2eText = (Get-ChildItem integration_test -Recurse -File -Filter *.dart |
        ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"

    $blocking = @()
    foreach ($n in $unattached) {
        if ($e2eText -match "WK\.$n\b") { $blocking += $n }
    }

    Write-Host "declared: $($names.Count)  attached to nothing in lib/: $($unattached.Count)"
    Write-Host ""
    Write-Host "ATTACHED TO NOTHING AND USED BY THE SUITE ($($blocking.Count)):"
    Write-Host ($blocking -join ', ')
    Write-Host ""

    $rest = $unattached | Where-Object { $blocking -notcontains $_ }
    Write-Host "attached to nothing and unused by the suite (dead handles): $($rest -join ', ')"

    if ($blocking.Count -gt 0) { exit 1 }
}
finally { Pop-Location }

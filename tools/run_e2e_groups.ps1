# Run several e2e groups, one `flutter test` process each, and report each group's summary.
#
#   pwsh -File tools/run_e2e_groups.ps1 -Groups login,patients,calendar
#
# Why a loop rather than one `flutter test` for everything: a group is selected by the
# `E2E_GROUP` define (`tools/run_e2e.ps1 -Group <name>`), so one process per group is the
# only way to *isolate* a group — and isolation is what makes a red count say which group it
# belongs to. `pwsh -File tools/run_e2e.ps1` with no `-Group` runs them all in one process,
# in registration order, and is the cheaper way to cover everything.
#
# Each group's full output is teed to `tmp/run_<group>.log`, which is the file to read when a
# group fails (`Select-String` for `[E]`, `Test failed`, `All tests passed!`).
#
# Unrelated app, tester and build processes are left alone. If an interrupted
# earlier run holds native assets open, stop that run's specific process IDs
# before starting this script.
#
# Note that `firebase_core`'s CMake decides whether to download the Firebase C++ SDK with
# `if(NOT EXISTS <zip>)` — existence, not size. A truncated zip therefore makes it skip the
# download and fail to extract, and an existing-but-empty `extracted/` makes it skip extraction
# and fail later with `get_target_property() called with non-existent target "firebase_app"`.
# If you see either, delete `build/windows/x64/firebase_cpp_sdk_windows_*.zip` **and**
# `build/windows/x64/extracted` (the real archive is ~913 MB) and let it download again.
param(
    [Parameter(Mandatory = $true)]
    [string]$Groups,

    # Passed through to `tools/run_e2e.ps1` (e.g. -Device macos).
    [string]$Device = '',

    # Keep going after a group fails (the default), or stop at the first red group.
    [switch]$StopOnFailure
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
    $names = $Groups -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if (-not $names) { Write-Host 'Nothing to run: -Groups is empty.'; exit 1 }
    $available = Get-ChildItem (Join-Path $repoRoot 'integration_test\groups') -Filter '*.dart' |
        Select-Object -ExpandProperty BaseName
    foreach ($name in $names) {
        if ($available -notcontains $name) { throw "Unknown E2E group: $name" }
    }
    $failed = $false;
    if (-not (Test-Path tmp)) { New-Item -ItemType Directory -Path tmp | Out-Null }

    $summary = @()
    foreach ($group in $names) {
        $log = "tmp/run_$group.log"
        # Both this script and `run_e2e.ps1 -Group <name>` write `tmp/run_<group>.log`, so a
        # leftover file can be days older than the run you think you are reading. Remove it
        # first: that way the file's absence says "this group did not produce output" and its
        # presence is always this run's.
        Remove-Item -Force $log -ErrorAction SilentlyContinue
        $runnerArgs = @('-File', 'tools/run_e2e.ps1', '-Group', $group)
        if ($Device) { $runnerArgs += @('-Device', $Device) }
        pwsh @runnerArgs 2>&1 | Tee-Object -FilePath $log | Out-Null
        $groupExitCode = $LASTEXITCODE
        if ($groupExitCode -ne 0) { $failed = $true }

        Write-Host ""
        Write-Host "=== $group ===" -ForegroundColor Cyan
        $lines = Get-Content $log |
            Select-String -Pattern 'All tests passed|All tests skipped|Some tests failed|\[E\]' |
            Select-Object -Last 8
        $lines | ForEach-Object { Write-Host $_.Line }

        # The group's own summary line is the last one that names a result.
        $result = (Get-Content $log |
            Select-String -Pattern 'All tests passed|All tests skipped|Some tests failed' |
            Select-Object -Last 1)
        $stamp = (Get-Item $log -ErrorAction SilentlyContinue).LastWriteTime.ToString('HH:mm:ss')
        $summary += [pscustomobject]@{
            Group  = $group
            Result = if ($result) { ($result.Line -replace '^\d\d:\d\d ', '') } else { 'NO RESULT LINE — check the log' }
            Log    = "$log @ $stamp"
        }
        if ($StopOnFailure -and $groupExitCode -ne 0) { break }
    }

    Write-Host ""
    Write-Host "==== summary ====" -ForegroundColor Cyan
    $summary | Format-Table -AutoSize | Out-String | Write-Host
    if ($failed) { exit 1 }
    exit 0
}
finally {
    Pop-Location
}

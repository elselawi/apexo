# Run the end-to-end integration test on a native window or in a browser.
#
#   pwsh -File tools/run_e2e.ps1                    # native (Windows desktop)
#   pwsh -File tools/run_e2e.ps1 -Target web       # Chrome, through chromedriver
#   pwsh -File tools/run_e2e.ps1 -Group login      # just that group, in isolation
#   pwsh -File tools/run_e2e.ps1 -Group "04:"      # any other string = a test-name filter
#   pwsh -File tools/run_e2e.ps1 -Device macos     # any device `flutter test` accepts
#   pwsh -File tools/run_e2e.ps1 -Target web -Headless
#   pwsh -File tools/run_e2e.ps1 -Entry integration_test/e2e_test.dart -Target web -WebHeaders
#
# A *group name* is selected through the `E2E_GROUP` define, which registers only
# that group — the mechanism a web run uses. Anything else is Flutter's own
# `--plain-name` (see integration_test/readme.md).
#
# Web runs need chromedriver listening on port 4444. This script starts one if
# it is on PATH, waits for the port, and stops only the process it started.
param(
    [ValidateSet('native', 'web')]
    [string]$Target = 'native',

    # The integration test file to run. Defaults to the full e2e suite; a
    # narrower integration_test entry can run much faster on web, where
    # `flutter drive` cannot filter individual tests inside one file.
    [string]$Entry = 'integration_test/e2e_test.dart',

    [string]$Group = '',
    [string]$Device = '',
    [string]$ChromeBinary = '',
    [switch]$Headless,

    # Serve the web build with the cross-origin isolation headers the web
    # database needs (OPFS + a dedicated worker). Flutter's dev server does not
    # set them, so a plain `-Target web` run of anything that opens the
    # database reports an unopenable database instead of testing it.
    [switch]$WebHeaders
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$entryPoint = $Entry
$entryPath = Join-Path $repoRoot $entryPoint

if (-not (Test-Path -LiteralPath $entryPath)) {
    throw "Entry '$Entry' does not exist. Use a path under integration_test\\."
}

# The group names `e2e_test.dart` registers.
#
# A group name is selected through the `E2E_GROUP` define the suite reads, which
# registers *only* that group. Flutter's `--plain-name` cannot isolate a group:
# it is a substring match on the test's full name, so `-Group notes` also ran
# `patient_panel 04: the patient's notes save and reload` — a test that needs the
# records the groups before `patient_panel` create, and therefore failed. The
# register order is the run order: a group's tests depend on what the groups
# before it left behind, so a group has to be run in isolation or as part of the
# whole suite, never as a name filter.
#
# The whole `e2e_test.dart` registers, as of 2026-10-09 (29 groups).
$groupNames = @(
    'login', 'patients', 'calendar', 'appointments', 'patient_panel',
    'tooth_chart', 'patient_portal', 'accessibility', 'upgrade', 'labworks',
    'expenses', 'dashboard', 'notes', 'attachments',
    'insights', 'deleted_items', 'accounts', 'settings_general',
    'settings_services', 'ai_services', 'sync_offline', 'backups',
    'notifications', 'multi_clinic', 'lifecycle_platform', 'localization_rtl',
    'errors_and_recovery', 'perf_budgets', 'dicom'
)
if ($Target -eq 'web' -and $Group -and $groupNames -notcontains $Group) {
    throw "Web runs require an E2E group name; test-name filters are not supported."
}

$filterArgs = @()
$groupDefine = @()
if ($Group) {
    if ($groupNames -contains $Group) {
        $groupDefine = @("--dart-define=E2E_GROUP=$Group")
    }
    else {
        # A test-name filter (e.g. "04:"), which `flutter test` does support.
        $filterArgs = @('--plain-name', $Group)
    }
}

if ($Group -eq 'login 12:') {
    $groupDefine += '--dart-define=E2E_ISOLATED_FIRST_LAUNCH=true'
}

$exitCode = 1

# The suite gets its credentials as dart-defines, because a web run cannot read
# test/secret.dart at all (a web build only compiles integration_test/ and lib/).
# They come from that file here, so it stays the one place they are kept.
$secretFile = Join-Path $repoRoot 'test/secret.dart'
$secrets = @{}
if (Test-Path -LiteralPath $secretFile) {
    foreach ($line in Get-Content -LiteralPath $secretFile) {
        if ($line -match "^\s*const\s+(testPBServer|testPBEmail|testPBPassword)\s*=\s*'([^']*)'") {
            $secrets[$matches[1]] = $matches[2]
        }
    }
}
foreach ($key in 'testPBServer', 'testPBEmail', 'testPBPassword') {
    if (-not $secrets.ContainsKey($key)) {
        Write-Host "Could not read $key from test/secret.dart." -ForegroundColor Red
        Write-Host "Copy test/secret.dart.example to test/secret.dart and fill it in."
        exit 1
    }
}
$credentialDefines = @(
    "--dart-define=PB_SERVER=$($secrets['testPBServer'])",
    "--dart-define=PB_EMAIL=$($secrets['testPBEmail'])",
    "--dart-define=PB_PASSWORD=$($secrets['testPBPassword'])"
)

# The password is a real argument, but it does not belong in a console scrollback
# or a CI log, so the echo below masks it.
function Show-Command {
    param([string[]]$Arguments)
    $shown = $Arguments -replace '^--dart-define=PB_PASSWORD=.*$', '--dart-define=PB_PASSWORD=***'
    Write-Host "==> flutter $($shown -join ' ')" -ForegroundColor Cyan
}

function Test-PortOpen {
    param([int]$Port)
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $client.Connect('127.0.0.1', $Port)
        $client.Close()
        return $true
    }
    catch {
        return $false
    }
}

Push-Location $repoRoot
$driverProcess = $null
try {
    if ($Target -eq 'native') {
        # Without -d, `flutter test` silently picks the first connected device —
        # on a machine with a phone plugged in that is the phone, not the desktop.
        $arguments = @('test', $entryPoint, '-d', $(if ($Device) { $Device } else { 'windows' }))
        # A per-test ceiling. Integration tests have no timeout of their own, so a
        # test that hangs (a frame that never draws, a platform channel that never
        # answers) otherwise blocks the whole run — one run sat for 53 minutes in
        # `appointments 08` before it was killed, with nothing to go on. This turns
        # that into a normal failure with a stack trace. It has to stay above the
        # 5-minute wait `E2E.signIn` allows for a cold first login.
        $arguments += @('--timeout', '6m', '--fail-fast')
        $arguments += $filterArgs
        $arguments += $groupDefine
        $arguments += $credentialDefines
        Show-Command $arguments
        & flutter @arguments
        $exitCode = $LASTEXITCODE
    }
    else {
        if ($Group) {
            # `--plain-name` belongs to `flutter test`; `flutter drive` rejects it,
            # so the group is selected through the define `e2e_test.dart` reads.
            # Individual test names still cannot be filtered on web.
            $credentialDefines += "--dart-define=E2E_GROUP=$Group"
        }
        if (-not (Test-PortOpen -Port 4444)) {
            $chromedriver = (Get-Command chromedriver -ErrorAction SilentlyContinue).Source
            if (-not $chromedriver) {
                Write-Host "chromedriver is not on PATH and nothing is listening on port 4444." -ForegroundColor Red
                Write-Host ""
                Write-Host "Install it with (Node is required):"
                Write-Host "  npx @puppeteer/browsers install chromedriver@stable"
                Write-Host "then put the folder it prints on PATH."
                Write-Host "Details: integration_test/readme.md"
            }
            else {
                Write-Host "==> starting $chromedriver --port=4444" -ForegroundColor Cyan
                $driverProcess = Start-Process -FilePath $chromedriver -ArgumentList '--port=4444' -PassThru -WindowStyle Hidden
                for ($i = 0; $i -lt 40 -and -not (Test-PortOpen -Port 4444); $i++) {
                    Start-Sleep -Milliseconds 250
                }
            }
        }

        if (Test-PortOpen -Port 4444) {
            $arguments = @(
                'drive',
                '--driver=test_driver/integration_test.dart',
                "--target=$entryPoint",
                # `-d chrome` hangs here: the tool passes `no-launch-chrome`
                # (the driver opens the browser), then waits for a debug-service
                # connection from a browser nobody launched yet. With
                # `-d web-server` the chromedriver session opens the browser at
                # the served URL and the app connects.
                '-d', 'web-server'
            )
            $arguments += $credentialDefines
            if ($WebHeaders) {
                # Chromium only enables OPFS-backed shared-memory SQLite in a
                # cross-origin isolated document.
                $arguments += '--web-header=Cross-Origin-Opener-Policy=same-origin'
                $arguments += '--web-header=Cross-Origin-Embedder-Policy=require-corp'
            }
            if ($ChromeBinary) { $arguments += "--chrome-binary=$ChromeBinary" }
            if ($Headless) { $arguments += '--headless' }
            Show-Command $arguments
            & flutter @arguments
            $exitCode = $LASTEXITCODE
        }
    }
}
finally {
    if ($driverProcess -and -not $driverProcess.HasExited) {
        Write-Host "==> stopping chromedriver (pid $($driverProcess.Id))" -ForegroundColor Cyan
        Stop-Process -Id $driverProcess.Id -Force
    }
    Pop-Location
}

exit $exitCode

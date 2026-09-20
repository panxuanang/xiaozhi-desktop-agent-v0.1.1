$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Root = Split-Path -Parent $PSScriptRoot
$Installer = Join-Path $Root 'dist\XiaoZhiSetup.exe'
$TempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$SmokeRoot = Join-Path $TempRoot 'xiaozhi-installer-smoke'

function Remove-TreeWithRetry {
    param([Parameter(Mandatory = $true)][string]$Path, [int]$Attempts = 5)
    if (-not (Test-Path $Path)) { return }
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            return
        }
        catch {
            if ($i -eq $Attempts) { throw }
            Start-Sleep -Seconds $i
        }
    }
}

if (-not (Test-Path $Installer)) { throw "Installer missing: $Installer" }
if ((Get-Item $Installer).Length -lt 10MB) { throw 'Installer is unexpectedly small; packaging likely failed' }

Remove-TreeWithRetry -Path $SmokeRoot
New-Item -ItemType Directory -Force -Path $SmokeRoot | Out-Null

Write-Host '========== Silent-install smoke test ==========' -ForegroundColor Cyan
$dirArg = '/DIR="' + $SmokeRoot + '"'
$logArg = '/LOG="' + (Join-Path $SmokeRoot 'setup-smoke.log') + '"'
$proc = Start-Process -FilePath $Installer -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/TASKS="!startup"', $dirArg, $logArg
) -PassThru -Wait
if ($proc.ExitCode -ne 0) { throw "Installer smoke install failed with exit code $($proc.ExitCode)" }

$Python = Join-Path $SmokeRoot 'runtime\python.exe'
$SelfCheck = Join-Path $SmokeRoot 'diagnostics\selfcheck.py'
$AppMain = Join-Path $SmokeRoot 'app\main.py'
foreach ($item in @($Python, $SelfCheck, $AppMain)) {
    if (-not (Test-Path $item)) { throw "Installed file missing: $item" }
}

$env:PYTHONPATH = Join-Path $SmokeRoot 'app\src'
& $Python -c "import requests, Crypto, win32crypt, win32com.client, deepseek_harness; from xiaozhi_agent.runtime import XiaoZhiRuntime; print('INSTALLED_RUNTIME_IMPORTS_OK')"
if ($LASTEXITCODE -ne 0) { throw "Installed runtime import check failed: $LASTEXITCODE" }
& $Python $SelfCheck
if ($LASTEXITCODE -ne 0) { throw "Installed self-check failed: $LASTEXITCODE" }

Write-Host 'INSTALLER_SMOKE_OK' -ForegroundColor Green

# Best-effort uninstall/cleanup. This is after the smoke test has already passed.
$Uninstaller = Join-Path $SmokeRoot 'unins000.exe'
if (Test-Path $Uninstaller) {
    try {
        Start-Process -FilePath $Uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait | Out-Null
    }
    catch {
        Write-Warning "Smoke-test uninstall cleanup failed: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
  Builds the single-file distributable: <repo>\dist\OracleAI-Setup.exe.

.DESCRIPTION
  End-to-end, reproducible packaging of Oracle AI into one installer:
    1. Compile the CLI/MCP binary (oracle_ai.exe).
    2. Build Oracle Studio (release).
    3. Build the setup wizard (release).
    4. Assemble the wizard's payload:  app\oracle_ai.exe + app\studio\  (offline
       program bundle the wizard copies to %LOCALAPPDATA%\Programs on install).
    5. Verify the offline database payload (PostgreSQL + pgvector zips) is present.
    6. Compile the Inno Setup script -> dist\OracleAI-Setup.exe.

  The PostgreSQL/pgvector zips are large (~315 MB) and are NOT rebuilt here —
  drop them once into the Release\payload folder (the wizard also downloads them
  on demand if missing). Pass -SkipBuild to only re-run the Inno packaging.

.PARAMETER SkipBuild
  Skip steps 1-3 (reuse existing release builds) and just (re)assemble + package.
#>
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$setupDir = Split-Path -Parent $PSScriptRoot          # apps\oracle_setup
$repo     = (Resolve-Path (Join-Path $setupDir '..\..')).Path
$rel      = Join-Path $setupDir 'build\windows\x64\runner\Release'
$studioRel = Join-Path $repo 'apps\oracle_studio\build\windows\x64\runner\Release'

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }

if (-not $SkipBuild) {
  Step 'Compiling CLI (oracle_ai.exe)'
  New-Item -ItemType Directory -Force (Join-Path $repo 'packages\oracle_server\build') | Out-Null
  & dart compile exe (Join-Path $repo 'packages\oracle_server\bin\oracle_ai.dart') `
      -o (Join-Path $repo 'packages\oracle_server\build\oracle_ai.exe')

  Step 'Building Oracle Studio (release)'
  Push-Location (Join-Path $repo 'apps\oracle_studio'); & flutter build windows --release; Pop-Location

  Step 'Building setup wizard (release)'
  Push-Location $setupDir; & flutter build windows --release; Pop-Location
}

Step 'Assembling program payload (app\)'
$app = Join-Path $rel 'app'
New-Item -ItemType Directory -Force $app | Out-Null
Copy-Item (Join-Path $repo 'packages\oracle_server\build\oracle_ai.exe') (Join-Path $app 'oracle_ai.exe') -Force
$appStudio = Join-Path $app 'studio'
if (Test-Path $appStudio) { Remove-Item $appStudio -Recurse -Force }
New-Item -ItemType Directory -Force $appStudio | Out-Null
Copy-Item (Join-Path $studioRel '*') $appStudio -Recurse -Force

Step 'Verifying offline database payload (payload\)'
$payload = Join-Path $rel 'payload'
$zips = @(Get-ChildItem $payload -Filter *.zip -ErrorAction SilentlyContinue)
if ($zips.Count -lt 2) {
  Write-Warning "Expected the PostgreSQL + pgvector zips in $payload (found $($zips.Count))."
  Write-Warning 'The installer will be ONLINE-only (the wizard downloads them at install time).'
}

Step 'Locating ISCC (Inno Setup compiler)'
$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'ISCC.exe not found. Install Inno Setup 6 (winget install JRSoftware.InnoSetup).' }

Step 'Compiling installer'
New-Item -ItemType Directory -Force (Join-Path $repo 'dist') | Out-Null
& $iscc (Join-Path $PSScriptRoot 'oracle_ai_setup.iss')

$out = Join-Path $repo 'dist\OracleAI-Setup.exe'
if (Test-Path $out) {
  $mb = [math]::Round((Get-Item $out).Length / 1MB)
  Write-Host "OK: $out ($mb MB)" -ForegroundColor Green
} else {
  throw 'Inno Setup did not produce dist\OracleAI-Setup.exe'
}

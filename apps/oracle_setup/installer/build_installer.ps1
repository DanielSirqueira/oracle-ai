<#
.SYNOPSIS
  One command to build EVERYTHING and produce the installer: dist\OracleAI-Setup.exe.

.DESCRIPTION
  Fully reproducible from a clean clone — no manual steps, no pre-staged files:

    1. Download the offline database payload (PostgreSQL 17 + pgvector zips) if
       it isn't already in the payload folder. (~315 MB, once — then cached.)
    2. Compile the CLI/MCP binary (oracle_ai.exe).
    3. Build Oracle Studio (Flutter release).
    4. Build the setup wizard (Flutter release).
    5. Assemble the program bundle the wizard installs: app\oracle_ai.exe + app\studio\.
    6. Compile the Inno Setup script -> dist\OracleAI-Setup.exe.

  Prerequisites: Flutter (with Windows desktop) + Dart on PATH, and Inno Setup 6
  (winget install JRSoftware.InnoSetup). Everything else is fetched/built here.

.PARAMETER SkipBuild
  Reuse the existing Flutter/Dart release builds; only (re)assemble + package.
  Use after a full build when you just tweaked the .iss or the payload.

.PARAMETER SkipPayload
  Don't touch the payload folder (assume the zips are already there).

.PARAMETER Online
  Build an ONLINE installer: leave the DB payload OUT (smaller file ~77 MB); the
  wizard downloads PostgreSQL + pgvector at install time instead.

.EXAMPLE
  pwsh apps/oracle_setup/installer/build_installer.ps1
    Full build from scratch -> dist\OracleAI-Setup.exe (offline, ~342 MB).

.EXAMPLE
  pwsh apps/oracle_setup/installer/build_installer.ps1 -SkipBuild
    Re-package quickly reusing the last build.

.EXAMPLE
  pwsh apps/oracle_setup/installer/build_installer.ps1 -Online
    Smaller installer that downloads the database at install time.
#>
param(
  [switch]$SkipBuild,
  [switch]$SkipPayload,
  [switch]$Online
)

$ErrorActionPreference = 'Stop'
$setupDir  = Split-Path -Parent $PSScriptRoot          # apps\oracle_setup
$repo      = (Resolve-Path (Join-Path $setupDir '..\..')).Path
$rel       = Join-Path $setupDir 'build\windows\x64\runner\Release'
$studioRel = Join-Path $repo 'apps\oracle_studio\build\windows\x64\runner\Release'

# Offline database payload — same URLs the wizard uses (SetupState._pgUrl / _pgvectorUrl).
$PG_URL  = 'https://get.enterprisedb.com/postgresql/postgresql-17.6-1-windows-x64-binaries.zip'
$PG_ZIP  = 'postgresql-17.6-1-windows-x64-binaries.zip'
$VEC_URL = 'https://github.com/andreiramani/pgvector_pgsql_windows/releases/download/0.8.3_17.6/vector.v0.8.3-pg17.zip'
$VEC_ZIP = 'vector.v0.8.3-pg17.zip'

function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }

function Get-Payload($url, $name, $dir) {
  $target = Join-Path $dir $name
  if (Test-Path $target) { Write-Host "  cached: $name"; return }
  New-Item -ItemType Directory -Force $dir | Out-Null
  $part = "$target.part"
  if (Test-Path $part) { Remove-Item $part -Force }
  Write-Host "  downloading: $name (large — once)"
  $oldPref = $ProgressPreference
  $ProgressPreference = 'SilentlyContinue'   # IWR is glacially slow with the progress bar
  try {
    try {
      Start-BitsTransfer -Source $url -Destination $part -ErrorAction Stop
    } catch {
      Invoke-WebRequest -Uri $url -OutFile $part -MaximumRedirection 8
    }
    Move-Item $part $target -Force
    Write-Host "  saved: $name"
  } finally {
    $ProgressPreference = $oldPref
  }
}

# ── 1. database payload ──
$payload = Join-Path $rel 'payload'
if ($Online) {
  Step 'Online installer — leaving the DB payload OUT'
  if (Test-Path $payload) { Remove-Item (Join-Path $payload '*') -Force -Recurse -ErrorAction SilentlyContinue }
} elseif ($SkipPayload) {
  Step 'Skipping payload (using what is already in payload\)'
} else {
  Step 'Preparing offline database payload (download if missing)'
  Get-Payload $PG_URL  $PG_ZIP  $payload
  Get-Payload $VEC_URL $VEC_ZIP $payload
}

# ── 2-4. build ──
if (-not $SkipBuild) {
  Step 'Compiling CLI (oracle_ai.exe)'
  New-Item -ItemType Directory -Force (Join-Path $repo 'packages\oracle_server\build') | Out-Null
  & dart compile exe (Join-Path $repo 'packages\oracle_server\bin\oracle_ai.dart') `
      -o (Join-Path $repo 'packages\oracle_server\build\oracle_ai.exe')

  Step 'Building Oracle Studio (release)'
  Push-Location (Join-Path $repo 'apps\oracle_studio'); try { & flutter build windows --release } finally { Pop-Location }

  Step 'Building setup wizard (release)'
  Push-Location $setupDir; try { & flutter build windows --release } finally { Pop-Location }
}

# ── 5. assemble program bundle ──
Step 'Assembling program bundle (app\)'
$app = Join-Path $rel 'app'
New-Item -ItemType Directory -Force $app | Out-Null
Copy-Item (Join-Path $repo 'packages\oracle_server\build\oracle_ai.exe') (Join-Path $app 'oracle_ai.exe') -Force
$appStudio = Join-Path $app 'studio'
if (Test-Path $appStudio) { Remove-Item $appStudio -Recurse -Force }
New-Item -ItemType Directory -Force $appStudio | Out-Null
Copy-Item (Join-Path $studioRel '*') $appStudio -Recurse -Force

# ── 6. package ──
Step 'Locating ISCC (Inno Setup 6 compiler)'
$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
  throw 'ISCC.exe not found. Install Inno Setup 6:  winget install JRSoftware.InnoSetup'
}

Step 'Compiling installer'
New-Item -ItemType Directory -Force (Join-Path $repo 'dist') | Out-Null
& $iscc (Join-Path $PSScriptRoot 'oracle_ai_setup.iss')

$out = Join-Path $repo 'dist\OracleAI-Setup.exe'
if (-not (Test-Path $out)) { throw 'Inno Setup did not produce dist\OracleAI-Setup.exe' }
$mb = [math]::Round((Get-Item $out).Length / 1MB)
Write-Host "OK: $out ($mb MB)" -ForegroundColor Green

; Oracle AI — single-file distributable installer (Inno Setup 6).
;
; This wraps the branded Flutter setup wizard PLUS the offline
; PostgreSQL + pgvector payload into ONE self-contained OracleAI-Setup.exe.
;
; It is a THIN LAUNCHER, not a second installer: on run it unpacks the bundle
; into a temp folder, launches the wizard (oracle_setup.exe) — which performs
; the real per-user install (copies the program to %LOCALAPPDATA%\Programs,
; provisions the database, writes the encrypted .env, creates the Start Menu /
; Desktop shortcuts and the Add-Remove-Programs entry), waits for it to finish,
; then removes the temp folder automatically. The wizard stays the single
; source of truth for what "installing" means; Inno only ships it as one file.
;
; Build:  ISCC.exe oracle_ai_setup.iss   (or use build_installer.ps1)
; Output: <repo>\dist\OracleAI-Setup.exe

#define AppName "Oracle AI"
#define AppVersion "0.1.0-beta"
#define AppPublisher "Daniel Sirqueira"
#define ReleaseDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{A1E2C3D4-5F6A-4B7C-8D9E-0F1A2B3C4D5E}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
; Per-user, no admin — matches the wizard's install philosophy.
PrivilegesRequired=lowest
; We only need a scratch unpack area; the wizard owns the real install dir.
CreateAppDir=no
Uninstallable=no
OutputDir=..\..\..\dist
; Define ONLINE (ISCC /DONLINE) to build the smaller installer that downloads the
; database at install time; otherwise the PostgreSQL payload is bundled (offline).
#ifdef ONLINE
OutputBaseFilename=OracleAI-Setup-online
#else
OutputBaseFilename=OracleAI-Setup
#endif
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardStyle=modern
; The payload is already zip-compressed, so recompressing gains almost nothing
; and costs minutes — keep solid off and mark the zips nocompression below.
Compression=lzma2/normal
SolidCompression=no
; No pages of our own — the Flutter wizard is the UI. Inno just shows a brief
; extraction progress and hands off.
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes

[Files]
#ifndef ONLINE
; Already-compressed PostgreSQL / pgvector zips — don't recompress. (Offline only;
; the ONLINE build omits these and the wizard downloads them at install time.)
Source: "{#ReleaseDir}\payload\*"; DestDir: "{tmp}\OracleAISetup\payload"; \
    Flags: recursesubdirs ignoreversion nocompression
#endif
; The wizard runtime + the app bundle (CLI + Studio) — these compress well. The
; payload folder is excluded here so it is never double-bundled (or bundled at all
; in the ONLINE build).
Source: "{#ReleaseDir}\*"; DestDir: "{tmp}\OracleAISetup"; Excludes: "payload\*"; \
    Flags: recursesubdirs ignoreversion

[Run]
; Launch the wizard and WAIT: while it runs Inno stays alive so the unpacked
; files survive; when the wizard exits (the user clicks "Concluir"), Inno
; resumes and auto-cleans {tmp}.
Filename: "{tmp}\OracleAISetup\oracle_setup.exe"; \
    WorkingDir: "{tmp}\OracleAISetup"; Flags: waituntilterminated

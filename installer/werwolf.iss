; Inno-Setup-Skript für den Windows-Installer von "Werwolf: Blutmond".
; Wird von .github/workflows/windows.yml aufgerufen:
;   ISCC.exe /DMyAppVersion=1.0.0 installer\werwolf.iss

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppName "Werwolf: Blutmond"
#define MyAppDir "Werwolf Blutmond"
#define MyAppExe "werwolf.exe"

[Setup]
AppId={{8C1F7B2E-3D4A-4E59-9B6C-5A2D7E1F0C93}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Blutmond
DefaultDirName={autopf}\{#MyAppDir}
DefaultGroupName={#MyAppDir}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=Werwolf-Blutmond-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
MinVersion=10.0.17763

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppDir}"; Filename: "{app}\{#MyAppExe}"
Name: "{group}\{cm:UninstallProgram,{#MyAppDir}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppDir}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppDir}}"; Flags: nowait postinstall skipifsilent

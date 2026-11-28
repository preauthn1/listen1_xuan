; Inno Setup script for the Flutter Windows bundle.
; BUILD_DIR, INSTALLER_OUTPUT_DIR, INSTALLER_NAME and APP_VERSION are
; supplied by the GitHub Actions job through the process environment.

#define MyAppName "listen1_xuan"
#define MyAppVersion GetEnv("APP_VERSION")
#define MyAppPublisher "HBWuChang"
#define MyAppURL "https://github.com/HBWuChang/listen1_xuan"
#define MyAppExeName "listen1_xuan.exe"
#define BuildDir GetEnv("BUILD_DIR")
#define InstallerOutputDir GetEnv("INSTALLER_OUTPUT_DIR")
#define InstallerName GetEnv("INSTALLER_NAME")

[Setup]
AppId={{FEE5E46C-B97D-4D00-9DEF-C5AD957614E3}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#InstallerOutputDir}
OutputBaseFilename={#InstallerName}
SetupIconFile={#BuildDir}\assets\images\app_icon.ico
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

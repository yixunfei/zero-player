#define ProductName "Zero Player"
#ifndef ProductVersion
  #error ProductVersion must be supplied by package_release.ps1
#endif
#ifndef ReleaseRoot
  #error ReleaseRoot must be supplied by package_release.ps1
#endif
#define ProjectRoot AddBackslash(SourcePath) + ".."

[Setup]
AppId={{34D6BE26-96C5-45CB-A3CA-970EB61D73D1}
AppName={#ProductName}
AppVersion={#ProductVersion}
DefaultDirName={localappdata}\Programs\Zero Player
DefaultGroupName=Zero Player
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
LicenseFile={#ProjectRoot}\LICENSE
OutputDir={#ReleaseRoot}
OutputBaseFilename=zero-player-{#ProductVersion}-windows-x64-setup
SetupIconFile={#ProjectRoot}\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\zero_player.exe
CloseApplications=yes

[Files]
Source: "{#ReleaseRoot}\windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Icons]
Name: "{group}\Zero Player"; Filename: "{app}\zero_player.exe"
Name: "{autodesktop}\Zero Player"; Filename: "{app}\zero_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\zero_player.exe"; Description: "Launch Zero Player"; Flags: nowait postinstall skipifsilent

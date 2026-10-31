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
ChangesAssociations=yes

[Files]
Source: "{#ReleaseRoot}\windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

Name: "videoassociation"; Description: "将 Zero Player 添加到常见视频格式的打开方式（默认播放器由 Windows 设置选择）"; Flags: unchecked

[Registry]
Root: HKCU; Subkey: "Software\Classes\ZeroPlayer.Video"; ValueType: string; ValueName: ""; ValueData: "Zero Player 视频"; Tasks: videoassociation; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ZeroPlayer.Video\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\zero_player.exe,0"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\Classes\ZeroPlayer.Video\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\zero_player.exe"" ""%1"""; Tasks: videoassociation
Root: HKCU; Subkey: "Software\Classes\.mp4\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.mkv\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.avi\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.mov\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.wmv\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.flv\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.webm\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.m4v\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.ts\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.m2ts\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.mpg\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.mpeg\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.3gp\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.ogv\OpenWithProgids"; ValueType: string; ValueName: "ZeroPlayer.Video"; ValueData: ""; Tasks: videoassociation; Flags: uninsdeletevalue

Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Zero Player"; Tasks: videoassociation; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "本地与在线视频播放器"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "Zero Player"; ValueData: "Software\ZeroPlayer\Capabilities"; Tasks: videoassociation; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mp4"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mkv"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".avi"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mov"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".wmv"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".flv"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".webm"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".m4v"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".ts"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".m2ts"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mpg"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mpeg"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".3gp"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation
Root: HKCU; Subkey: "Software\ZeroPlayer\Capabilities\FileAssociations"; ValueType: string; ValueName: ".ogv"; ValueData: "ZeroPlayer.Video"; Tasks: videoassociation

[Icons]
Name: "{group}\Zero Player"; Filename: "{app}\zero_player.exe"
Name: "{autodesktop}\Zero Player"; Filename: "{app}\zero_player.exe"; Tasks: desktopicon

[Run]
Filename: "{win}\explorer.exe"; Parameters: "ms-settings:defaultapps"; Description: "选择 Zero Player 作为默认视频播放器"; Tasks: videoassociation; Flags: postinstall nowait skipifsilent unchecked
Filename: "{app}\zero_player.exe"; Description: "Launch Zero Player"; Flags: nowait postinstall skipifsilent

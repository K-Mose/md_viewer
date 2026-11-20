#define MyAppName "MD Viewer"
#define MyAppVersion "1.0.0"
#define MyAppExeName "md_viewer.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{여기에-GUID-생성해서-넣기}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=..\dist
OutputBaseFilename=md_viewer_setup_{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕화면 바로가기 만들기"; Flags: unchecked
Name: "assocmd"; Description: ".md 파일을 MD Viewer로 열기"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; .md 파일 연결 (선택한 경우에만)
Root: HKA; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: string; ValueName: "MDViewer.md"; ValueData: ""; Flags: uninsdeletevalue; Tasks: assocmd
Root: HKA; Subkey: "Software\Classes\MDViewer.md"; ValueType: string; ValueName: ""; ValueData: "Markdown 문서"; Flags: uninsdeletekey; Tasks: assocmd
Root: HKA; Subkey: "Software\Classes\MDViewer.md\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"; Tasks: assocmd
Root: HKA; Subkey: "Software\Classes\MDViewer.md\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: assocmd

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "MD Viewer 실행"; Flags: nowait postinstall skipifsilent
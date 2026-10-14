; VTT installer script for Inno Setup 6.
; 관리자 권한 PC에서 iscc.exe vtt.iss 로 컴파일하면 VTT-Setup-0.1.0.exe 생성.
; (현재 개발 PC는 관리자 권한이 없어 포터블 zip으로 배포 중)

#define MyAppName "VTT"
#define MyAppVersion "0.1.0"
#define MyAppExeName "vtt_app.exe"

[Setup]
AppId={{A3B1C2D4-E5F6-47A8-B9C0-D1E2F3A4B5C6}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\VTT
OutputDir=.
OutputBaseFilename=VTT-Setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
WizardStyle=modern

[Files]
Source: "..\vtt_app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "setup-models.ps1"; DestDir: "{app}"
Source: "README-INSTALL.md"; DestDir: "{app}"; Flags: isreadme

[Icons]
Name: "{autoprograms}\VTT"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\VTT"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "바탕화면에 바로가기 만들기"; Flags: unchecked

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\setup-models.ps1"""; Description: "AI 모델 받기 (Ollama 필요, 약 8GB 다운로드)"; Flags: postinstall runascurrentuser skipifsilent
Filename: "{app}\{#MyAppExeName}"; Description: "VTT 실행"; Flags: postinstall nowait runascurrentuser skipifsilent

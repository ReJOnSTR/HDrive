; HDrive Windows (WinUI 3) Inno Setup Kurulum Senaryosu
#define MyAppName "HDrive"
#define MyAppVersion "1.3.3"
#define MyAppPublisher "ReJOnSTR"
#define MyAppURL "https://github.com/ReJOnSTR/HDrive"
#define MyAppExeName "HDrive.exe"

[Setup]
AppId={{C4D5F8A2-3B7E-4F2A-8C1D-9E3F8A7B6C5D}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=Output
OutputBaseFilename=HDrive-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=app.ico

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "HDriveWin\publish_x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "WindowsAppRuntimeInstall-x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autoprograms}\{#MyAppName} (Sorun Giderme)"; Filename: "{app}\HDrive-Hata-Goster.bat"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /passive /norestart"; StatusMsg: "Visual C++ 2015-2022 Runtime kuruluyor..."; Check: VCRedistNeedsInstall; Flags: waituntilterminated
Filename: "{tmp}\WindowsAppRuntimeInstall-x64.exe"; Parameters: "--quiet"; StatusMsg: "Windows App SDK 1.5 Runtime kuruluyor..."; Check: WinAppRuntimeExistsInTmp; Flags: waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[Code]
function WinAppRuntimeExistsInTmp: Boolean;
begin
  Result := FileExists(ExpandConstant('{tmp}\WindowsAppRuntimeInstall-x64.exe'));
end;

function VCRedistNeedsInstall: Boolean;
var
  Installed: Cardinal;
begin
  if not FileExists(ExpandConstant('{tmp}\vc_redist.x64.exe')) then
  begin
    Result := False;
    Exit;
  end;
  if RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) and (Installed = 1) then
  begin
    Result := False;
  end
  else
  begin
    Result := True;
  end;
end;

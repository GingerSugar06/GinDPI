; GinDPI kurulum sihirbazı (Inno Setup 6). tools\package.ps1 tarafından derlenir.
#define AppName "GinDPI"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{B6D1F0A4-5C1E-4C7B-9E0B-6B1D5E7A2F11}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=GinDPI
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\gindpi.exe
OutputDir=..\dist
OutputBaseFilename=GinDPI-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=no

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Masaüstü kısayolu oluştur"; GroupDescription: "Ek görevler:"
Name: "autostart"; Description: "Windows ile birlikte başlat (tepsiye küçülerek)"; GroupDescription: "Ek görevler:"

[Files]
Source: "..\dist\GinDPI\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\gindpi.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\gindpi.exe"; Tasks: desktopicon

[Run]
; Yönetici gerektiren uygulama Run anahtarıyla sessiz açılamaz: en yüksek yetkili zamanlanmış görev.
; Görevin tanımı uygulamanın kendisinde (pilde de çalışır, süre sınırı yok).
Filename: "{app}\gindpi.exe"; Parameters: "--startup-on"; Flags: runhidden waituntilterminated; Tasks: autostart
Filename: "{app}\gindpi.exe"; Description: "{#AppName}'ı şimdi başlat"; Flags: shellexec nowait postinstall skipifsilent

[UninstallRun]
; Windows'a yazdığımız her şeyi (PAC, DNS kuralı, zamanlanmış görev) geri al.
Filename: "{app}\gindpi.exe"; Parameters: "--cleanup"; Flags: runhidden waituntilterminated; RunOnceId: "GinDPICleanup"

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\GinDPI"

[Code]
procedure StopRunning();
var
  rc: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM gindpi.exe', '', SW_HIDE, ewWaitUntilTerminated, rc);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopRunning();
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  { Çalışan motor varsa önce temiz kapat: DNS kuralı ve PAC'ı kendisi geri almaz, --cleanup alır. }
  StopRunning();
  Result := True;
end;

; Instalador Windows do GMN BOOK OFFLINE (Inno Setup 6).
; Compilar: iscc /DAppVersion=1.0.0 /DSourceDir=<pasta Release> installer\windows\gmn_book.iss
;
; - Instala por usuario (sem exigir administrador) em %LOCALAPPDATA%\Programs\GMN BOOK,
;   ou em Arquivos de Programas se executado como administrador.
; - Os DADOS ficam em %APPDATA%\GMN BOOK\GMN BOOK\data e NAO sao apagados
;   ao atualizar ou desinstalar o aplicativo.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\releases\windows"
#endif

[Setup]
AppId={{8C2B4F1E-6A3D-4E7B-9F21-5B0D7C3A9E44}
AppName=GMN BOOK
AppVersion={#AppVersion}
AppVerName=GMN BOOK {#AppVersion}
AppPublisher=GMN BOOK
DefaultDirName={autopf}\GMN BOOK
DefaultGroupName=GMN BOOK
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=GMN-BOOK-Setup-{#AppVersion}-x64
SetupIconFile=..\..\assets\brand\app_icon.ico
UninstallDisplayIcon={app}\gmn_book.exe
UninstallDisplayName=GMN BOOK
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
MinVersion=10.0

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Atalhos:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\GMN BOOK"; Filename: "{app}\gmn_book.exe"
Name: "{group}\Desinstalar GMN BOOK"; Filename: "{uninstallexe}"
Name: "{autodesktop}\GMN BOOK"; Filename: "{app}\gmn_book.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\gmn_book.exe"; Description: "Abrir o GMN BOOK"; Flags: nowait postinstall skipifsilent

[Messages]
brazilianportuguese.FinishedLabel=O GMN BOOK foi instalado. Seus dados ficam salvos neste computador e são mantidos ao atualizar o aplicativo. Faça backups regularmente pelo menu "Backup e restauração".

; WonderFlix: installer per utente (nessun UAC).
; Compilazione (dalla root del repository, dopo la build release):
;   ISCC.exe /DAppVersion=X.Y.Z installer\wonderflix.iss
; Risultato: dist\WonderFlix-Setup-X.Y.Z.exe

#ifndef AppVersion
  #error Passa la versione: ISCC.exe /DAppVersion=X.Y.Z installer\wonderflix.iss
#endif

#define AppName "WonderFlix"
#define AppExe "wonderflix.exe"
; Stesso mutex di windows\runner\main.cpp (una sola istanza).
#define AppMutex "Local\WonderFlix.SingleInstance"
; Stesso AppUserModelID di windows\runner\main.cpp.
#define AppUserModelId "it.wonderflix.WonderFlix"

[Setup]
; Non cambiare mai AppId: identifica l'installazione per aggiornamenti e
; disinstallazione.
AppId={{04C266E9-CC09-4851-91D0-CD9EFEC2D109}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=WonderFlix-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; L'attesa della chiusura dell'app è in [Code]. Niente AppMutex: in modalità
; silenziosa il suo messaggio risponderebbe "Annulla".
CloseApplications=no
; Una sola installazione alla volta (doppio clic su "Riavvia ora"): in
; modalità silenziosa la seconda si chiude da sola.
SetupMutex=WonderFlixSetup
; A fine installazione avvisa Windows che le icone sono cambiate: senza, la
; barra delle applicazioni può mostrare l'icona della versione precedente.
ChangesAssociations=yes

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
italian.CloseWonderFlix=WonderFlix è aperto. Chiudilo e premi Riprova.
english.CloseWonderFlix=WonderFlix is running. Close it and press Retry.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; Aggiornamento: via i file della versione precedente.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppUserModelId}"
; Aggiornamento silenzioso: il collegamento sul Desktop si ricrea solo se c'è
; ancora (l'utente può averlo tolto).
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppUserModelId}"; Tasks: desktopicon; Check: DesktopIconWanted

[Run]
; Installazione normale: casella "Avvia WonderFlix" alla fine.
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; Aggiornamento dall'app (silenzioso): riapre l'app.
Filename: "{app}\{#AppExe}"; Flags: nowait skipifnotsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
const
  WaitStepMs = 500;
  WaitSteps = 60; { 30 secondi }

var
  { InitializeSetup ha dato il via libera (l'app era chiusa). }
  SetupStarted: Boolean;
  { L'app era già installata prima della copia dei file. }
  IsUpgrade: Boolean;
  { Installazione completata. }
  InstallDone: Boolean;

function InstalledExe(): String;
begin
  Result := ExpandConstant('{localappdata}\Programs\{#AppName}\{#AppExe}');
end;

function AppRunning(): Boolean;
begin
  Result := CheckForMutexes('{#AppMutex}');
end;

{ Aggiornamento silenzioso: l'app avvia l'installer e poi si chiude, quindi
  si aspetta fino a 30 secondi. Installazione normale: si chiede di chiuderla. }
function InitializeSetup(): Boolean;
var
  I: Integer;
begin
  if WizardSilent() then
  begin
    I := 0;
    while AppRunning() and (I < WaitSteps) do
    begin
      Sleep(WaitStepMs);
      I := I + 1;
    end;
    Result := not AppRunning();
    if not Result then
      Log('WonderFlix è ancora aperto: installazione annullata.');
    SetupStarted := Result;
    Exit;
  end;
  while AppRunning() do
    if MsgBox(CustomMessage('CloseWonderFlix'), mbError, MB_RETRYCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  Result := True;
  SetupStarted := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  { Prima della copia dei file: dopo, l'exe esiste sempre. }
  if CurStep = ssInstall then
    IsUpgrade := FileExists(InstalledExe());
  if CurStep = ssDone then
    InstallDone := True;
end;

{ Collegamento sul Desktop: sempre alla prima installazione e in quella
  normale (casella scelta dall'utente); nell'aggiornamento silenzioso solo se
  c'è ancora. }
function DesktopIconWanted(): Boolean;
begin
  Result := (not IsUpgrade) or (not WizardSilent()) or
    FileExists(ExpandConstant('{autodesktop}\{#AppName}.lnk'));
end;

{ Aggiornamento silenzioso non completato dopo la chiusura dell'app: la si
  riapre (versione precedente, ripristinata dal rollback). Se InitializeSetup
  ha rinunciato l'app è ancora aperta: niente da fare. }
procedure DeinitializeSetup();
var
  ResultCode: Integer;
begin
  if WizardSilent() and SetupStarted and (not InstallDone) and
    FileExists(InstalledExe()) then
  begin
    Log('Installazione non completata: riapertura di WonderFlix.');
    Exec(InstalledExe(), '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
  end;
end;

function InitializeUninstall(): Boolean;
begin
  while AppRunning() do
    if SuppressibleMsgBox(CustomMessage('CloseWonderFlix'), mbError, MB_RETRYCANCEL, IDCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  Result := True;
end;

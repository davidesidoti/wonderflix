# WonderFlix — Piano 17b: profili "Chi guarda?"

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte K2 della Spec K, senza le immagini. Ci sono:
- **più profili** salvati sul PC, ognuno con il suo token e il suo DeviceId;
- la **migrazione** della sessione di oggi nel primo profilo;
- la schermata **"Chi guarda?"** (`/profiles`) con "Aggiungi profilo" e "Gestisci profili";
- l'**accesso** per un profilo nuovo o per uno scaduto ("Accedi di nuovo");
- **Cambia profilo**, **Aggiungi profilo** ed **Esci** nel menu dell'avatar e nelle Impostazioni;
- le **preferenze del profilo**.

Le immagini del profilo, `UserAvatar` e la release sono nel piano 17c. Qui gli avatar sono l'iniziale, come oggi.

**Spec:** `docs/superpowers/specs/2026-10-07-wonderflix-saghe-profili-design.md` (§2.2, §4, §5, §6, §9, §11, §12, §13, §15).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 9):
1. **Niente parametri nell'indirizzo del login.** La spec dice `/login?add=1` e `/login?user=<userId>`. Qui la modalità del login sta nello stato della sessione: `SessionSignedOut(adding: true)` per un profilo nuovo, `SessionSignedOut(expired: true, reloginUserId: …)` per "Accedi di nuovo". Il router porta già ogni `SignedOut` su `/login`, e lo stesso stato serve anche per un 401 durante la sessione (il profilo scaduto rifà l'accesso).
2. **Un 401 durante la sessione:** il profilo si segna come scaduto e si apre l'accesso per quel profilo (nome già scritto, stesso DeviceId). "Annulla" c'è se ci sono altri profili.
3. **Il profilo scaduto resta segnato** nel file dei profili (`expired: true`): "Chi guarda?" lo mostra attenuato anche dopo un riavvio, senza una richiesta.
4. **I profili per l'interfaccia** stanno in `profilesProvider` (`ProfilesState`: i profili e quello attivo). Lo aggiorna `SessionController` a ogni cambio, così le schermate e le preferenze non creano il controller della sessione (che vuole il client HTTP).
5. **Il DeviceId dell'accesso** lo prepara la schermata di accesso quando si apre (`SessionController.prepareLogin`): Quick Connect lo usa già per `Initiate`, prima dell'approvazione. Il profilo salva il DeviceId con cui ha ottenuto il token.
6. **Lingua "di Windows" in un profilo:** si salva una stringa vuota nella chiave del profilo; senza valore varrebbe la lingua del PC (§9.6). Senza profilo la chiave si toglie, come oggi.
7. **Massimo 5 profili:** oltre al pulsante nascosto, `AuthService` rifiuta un sesto profilo con `ProfileLimitException` (annulla subito il token appena ottenuto). Il login mostra "Massimo 5 profili".
8. **Conferma generica:** `showAdminConfirmDialog` diventa un uso di `showWfConfirmDialog` (`lib/ui/wf_confirm_dialog.dart`), che serve anche a "Rimuovi" e al cambio di profilo durante un party.
9. **Il client per un profilo non attivo** (annullare il token di un profilo tolto, 17c: la sua immagine) è `JellyfinHttp.withCredentials`: stesse impostazioni e stesso adattatore, credenziali sue, nessun `onUnauthorized`.
10. **Dalle review dei gruppi** (il codice dei task sotto è quello di partenza: dove differisce, vale questa lista, e la spec è già allineata):
    - **Dati:**
      - `ProfileStore.read()` non lancia mai. Se il salvataggio del profilo migrato fallisce, il profilo vale in memoria e `wonderflix.session` resta: la migrazione si rifà al prossimo avvio solo se nessun salvataggio riesce. Se fallisce la cancellazione della chiave vecchia, va solo un avviso nel registro.
      - Il client di `JellyfinHttp.withCredentials` usa in prestito l'adattatore del principale (`_BorrowedAdapter`): chiuderlo non chiude il client principale.
      - `profilesKeyFor` sta in `lib/core/device/dev_profile.dart`, accanto a `sessionKeyFor`.
      - I dati stanno in `%AppData%\it.wonderflix\WonderFlix\flutter_secure_storage.dat` (file cifrato con DPAPI), come scritto in `docs/RELEASING.md`.
    - **Sessione:**
      - **La decisione 2 cambia: ogni accesso ha un DeviceId nuovo, anche "Accedi di nuovo".** `prepareLogin()` non prende un utente (`prepareLogin(userId:)` non c'è). Il profilo che rifà l'accesso è scaduto, quindi il suo dispositivo sul server non c'è già più. Riusarne il DeviceId lo farebbe condividere a un altro utente (il nome si può cambiare, e Quick Connect lo approva chiunque), e annullare il token vecchio sullo stesso DeviceId potrebbe chiudere la sessione nuova. Due profili salvati non hanno mai lo stesso DeviceId (se succedesse, un avviso nel registro).
      - Il DeviceId e una "generazione" si leggono prima della richiesta di accesso: il token è legato al DeviceId con cui è stato chiesto.
      - Un accesso che finisce dopo "Annulla" o dopo l'apertura di un altro profilo (superato) si salva ma non si apre. Se quell'utente ha già un profilo valido, resta quello e il token nuovo si annulla.
      - Stesso utente: il token vecchio si annulla dopo il salvataggio, senza aspettare, con il suo DeviceId.
      - Un errore di scrittura dello storage non rompe la sessione: i profili si aggiornano in memoria e l'errore va nel registro.
      - `JellyfinHttp.token` si legge e basta: token e DeviceId cambiano solo con `setCredentials`, sempre insieme.
      - `profilesProvider` si ripubblica dopo ogni salvataggio (`AuthService.onProfilesChanged`).
      - "Rimuovi" toglie subito il profilo e annulla il suo token in background (errori ignorati). Togliere un profilo mentre si è dentro un altro lascia la sessione. Il 401 della richiesta di uscita si ignora. "Annulla" toglie le credenziali preparate. "Esci" cambia schermata prima di cancellare le preferenze.
      - Chi chiama `AuthService.openProfile` non sovrappone due aperture: "Chi guarda?" blocca i clic mentre un profilo si apre.
      - Lingua senza nessun profilo: la chiave `locale` del PC (quella di prima della 0.11.0), altrimenti quella di Windows.
      - Le preferenze di un profilo tolto si cancellano con `ProfilePreferences.forget` (non `removeProfile`).
    - **Interfaccia:**
      - Il cambio è `changeProfile(context, ref, {addProfile})` (`lib/features/profiles/profile_switch.dart`), non `switchProfile`. In un party "Aggiungi profilo" chiede la conferma con le parole "Aggiungi profilo". Un cambio confermato si fa anche se la schermata che l'ha chiesto sparisce durante l'uscita dal party (al massimo 3 s), ma solo se la sessione è ancora dello stesso utente.
      - "Chi guarda?":
        - logo da 140 px e spazi più stretti, così sta nella finestra più piccola (1024×640); entrata uno dopo l'altro come nel login;
        - il fuoco parte dalla card dell'ultimo profilo usato (o dalla prima), e Invio la apre; Esc esce da "Gestisci profili";
        - mentre un profilo si apre, il suo avatar ha un velo scuro con uno spinner chiaro, e gli altri clic non fanno niente;
        - per lo screen reader le card sono pulsanti con il nome (un profilo scaduto ha il suggerimento "Accedi di nuovo");
        - testi nuovi `profilesRemoveNamed` ("Rimuovi {name}", tooltip del pulsante Rimuovi) e `profilesUnnamed` ("Profilo", per un profilo il cui nome non si è mai letto).
      - Login: un nome salvato vuoto non si scrive nel campo.
      - Gli avatar restano le iniziali: il piano 17c mette `UserAvatar` al posto dell'iniziale di "Chi guarda?" e del `CircleAvatar` del menu dell'avatar.
    - **Dalla review finale:**
      - Quick Connect si ferma del tutto quando si smette di ascoltarlo ("Annulla", un'altra scheda): `QuickConnectFlow.run` usa uno `StreamController` con `onCancel`, e prima di ogni attesa o richiesta guarda se è stato cancellato. Niente più controlli, `Initiate` o `completeQuickConnect` con le credenziali del profilo aperto dopo.
      - Server giù aprendo un profilo da "Chi guarda?": `SessionUnreachable(retryUserId:)`, e "Riprova" (anche quello automatico) riapre quel profilo invece di `restore()`.
      - Togliere l'ultimo profilo cambia lo stato prima di cancellare le preferenze, come "Esci": nessun "Chi guarda?" vuoto.
      - Password e Quick Connect insieme: **vince il primo accesso che finisce** (l'accesso riuscito fa crescere la generazione); l'altro è superato, e le credenziali non cambiano sotto una sessione aperta.
      - Una lettura dello storage che lancia non fa perdere i profili salvati: `ProfileStore.write` dà l'elenco salvato davvero; dopo una lettura non riuscita rilegge prima, e se non riesce non salva, altrimenti tiene anche i profili che mancano (al massimo 5, vincono i nuovi). Solo dati rovinati si sovrascrivono. Vale anche per la sessione di prima (il lettore della 0.10 lancia invece di cancellarla).
      - Dopo un salvataggio non riuscito, `restore()` tiene i profili in memoria e riprova a salvarli invece di rileggere lo storage.
      - I 401 attesi (aprire un profilo scaduto, annullare un token già scaduto) vanno nel registro come info (`quietStatuses`, anche in `AuthApi.logout`).
      - Della sessione di prima resta solo il lettore (`SecureSessionStore.read` e `clear`), per la migrazione 0.10 → 0.11.

**Architecture:**
- **Dati:**
  - `StoredProfile`, `ProfileBook` e `SecureProfileStore` (con la migrazione) in `lib/core/storage/profile_store.dart`;
  - `JellyfinHttp.setCredentials` e `withCredentials`, `ClientInfo.copyWith`.
- **Sessione:**
  - `AuthService` lavora sui profili;
  - `SessionController` ha lo stato nuovo `SessionChoosingProfile` e i metodi per scegliere, aggiungere, cambiare e togliere i profili;
  - `profilesProvider` porta i profili all'interfaccia.
- **Preferenze:** `ProfilePreferences` e `profilePreferencesProvider`, usati da lingua, modalità del party, Discord e tre scelte del player.
- **Interfaccia:**
  - `ProfilesScreen`;
  - login con "Annulla" e il nome già scritto;
  - `switchProfile` (uscita dal party con conferma);
  - menu dell'avatar e Impostazioni.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3, go_router 18, flutter_secure_storage 11, uuid, clock, mocktail, lucide_icons_flutter.

**Worktree:** `.claude/worktrees/piano-17b`, branch `feat/piano-17b`. **Base:** `main` con questo piano. **Test a inizio piano:** 2196 Flutter e 390 plugin (a fine piano 17a). Il plugin non cambia in questo piano.

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git del repository (hash_developer), già configurata.
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `Stop-Process -Name …`, `pkill`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** PowerShell su Windows.
  - In ogni comando che usa `flutter`, `dart` o `git`, prima rinfresca il PATH (la shell dello strumento ha un PATH vecchio):
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-17b`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(app): …"`. Un messaggio su più righe va in un file e si usa `git commit -F <file>`.
- **Prima di ogni commit:** `flutter analyze` senza problemi e `flutter test` tutto verde (la suite intera).
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; `clock.now()`, mai `DateTime.now()`.
- **Spinner e `pumpAndSettle`:** un `CircularProgressIndicator` senza valore non si ferma mai, quindi `pumpAndSettle` va in timeout. Mentre c'è uno spinner, usa `pump()` o `pump(durata)`.
- **Provider:** nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`. I container dei test hanno `retry: (_, _) => null`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-08 sul codice di `main` (`32e6104`), in sola lettura.

**Sessione di oggi**
- `lib/core/storage/session_store.dart`:
  - `StoredSession{userId, accessToken}` e `SecureSessionStore([FlutterSecureStorage? storage, String? storageKey])` con `read()`, `write()`, `clear()` e la chiave `SecureSessionStore.key = 'wonderflix.session'`;
  - una lettura che fallisce o un valore rovinato danno `null`, e il valore si cancella.
  - Il commento dice "Gestore credenziali di Windows": **è sbagliato**. Su Windows `flutter_secure_storage_windows` 4.2.2 salva tutte le chiavi in un file JSON cifrato con DPAPI (`flutter_secure_storage.dat` nella cartella dei dati dell'app). Lo stesso errore c'è in `lib/core/device/dev_profile.dart` (`sessionKeyFor`) e in `docs/RELEASING.md` (riga 57).
- **`AuthService`** (`lib/features/auth/auth_service.dart`):
  - lavora su `JellyfinHttp`, `AuthApi` e `SessionStore`;
  - i risultati del ripristino sono `RestoredSession(user)`, `NoStoredSession`, `StoredSessionExpired`, `RestoreServerUnreachable`;
  - i metodi sono `restore`, `currentUser`, `loginWithPassword`, `completeQuickConnect`, `logout`, `clearLocalSession`.
- **`SessionController`** (`lib/features/auth/session_controller.dart`):
  - ha gli stati `SessionStarting`, `SessionSignedOut({expired})`, `SessionUnreachable`, `SessionSignedIn(user)`;
  - `build()` guarda `jellyfinHttpProvider` e imposta `http.onUnauthorized`;
  - `refreshUser()` è deduplicato.
- **Provider** (`lib/app/providers.dart`):
  - `clientInfoProvider` (sovrascritto in `main.dart` con il DeviceId dell'installazione: `device_id` delle preferenze, o un v5 per l'istanza di sviluppo);
  - `sessionStoreProvider`, `jellyfinHttpProvider`, `authApiProvider`, `authServiceProvider`.
- **`JellyfinHttp`** (`lib/core/jellyfin/jellyfin_http.dart`):
  - tiene `_clientInfo` `final` e un `token` modificabile;
  - `authorizationHeader` si costruisce a ogni richiesta (il WebSocket lo legge quando si connette);
  - `_send` chiama `onUnauthorized` per un 401 di una richiesta fatta con il token attuale.
- **`ClientInfo`** (`lib/core/jellyfin/client_info.dart`): `client`, `device`, `deviceId`, `version`. `buildAuthorizationHeader(info, token:)`.
- **`AuthApi.logout()`:** `POST /Sessions/Logout` con le credenziali del client.
- **Quick Connect** (`quick_connect_flow.dart`): `quickConnectEnabled` → `initiateQuickConnect` → `quickConnectState` → `AuthService.completeQuickConnect(secret)`. `QuickConnectPanel` lo fa partire in `initState`.
- **Router** (`lib/app/router.dart`):
  - `_entryRoutes = {'/splash', '/login', '/unreachable'}`;
  - `sessionRedirect` fa uno `switch` esaustivo su `SessionState`: è l'unico `switch` di questo tipo in `lib/`, quindi con uno stato nuovo va aggiornato solo lui;
  - le rotte d'ingresso usano `entryPage(context, state, child)`.
- **Login** (`login_screen.dart`, `password_login_form.dart`):
  - `LoginScreen` è un `ConsumerWidget`; mostra "Sessione scaduta" con `SessionSignedOut.expired`;
  - le schede Password e Quick Connect compaiono solo se il server lo permette;
  - `PasswordLoginForm` ha il nome utente vuoto con `autofocus` e i tasti `login-username`, `login-password`, `login-submit`.
- **Menu dell'avatar:** `_UserMenu` in `lib/app/app_shell.dart` (~riga 345):
  - le voci sono `settings`, `admin` (solo per gli admin) e `logout`;
  - l'avatar è un `CircleAvatar` dorato con l'iniziale.
- **Impostazioni → Account** (`settings_screen.dart`, ~riga 116): "Accesso come {name}" e il pulsante Esci (`WfButton.secondary`).
- **Watch party:**
  - `watchPartySessionProvider` (`lib/features/watch_party/watch_party_session.dart`);
  - `WatchPartyState.phase` (`none`, `joining`, `inGroup`);
  - `leave()` riporta subito lo stato a `none` e poi manda la richiesta al server, ignorandone gli errori;
  - il canale del party si chiude da solo quando si esce dal gruppo.
- **Preferenze** (`SharedPreferences` via `sharedPreferencesProvider`):
  - `LocaleController` (`locale`; `null` toglie la chiave);
  - `PartyModePreference` (`party.lastMode`);
  - `DiscordSettingsController` (`discord.enabled`, `discord.showTitle`, `discord.showPoster`);
  - `PlayerSettingsController` (`player.quality`, `player.hardwareDecoding`, `player.subtitleScale`, `player.autoSkipIntro`, `player.autoplayNext`).

  Tutti guardano `sharedPreferencesProvider` in `build`. `settings_test.dart` controlla che `LocaleController.set(null)` tolga la chiave `locale`.
- **Conferma:** `showAdminConfirmDialog(context, title:, message:, confirmLabel:)` (`lib/features/admin/admin_confirm_dialog.dart`) usa `showWfDialog` e `l.adminCancel`.
- **`describeError`** (`lib/app/error_text.dart`): uno `switch` sui tipi d'errore, con `_ => l.errorGeneric`.
- **`jellyfinIdKey(id)`** (`lib/core/jellyfin/json_fields.dart`): l'id senza trattini e in minuscolo.
- **Test:**
  - `FakeSessionController` (`test/support/fake_session_controller.dart`) ha `set(state)` e i contatori; lo usano 75 file di test;
  - `MemorySessionStore` (`test/support/memory_session_store.dart`) lo usano solo `auth_service_test.dart`;
  - `auth_service_test.dart` e `session_controller_test.dart` usano mocktail (`MockAuthApi`, `MockAuthService`);
  - `FlutterSecureStorage.setMockInitialValues({...})` simula lo storage;
  - `SharedPreferences.setMockInitialValues({...})` e `getInstance()` simulano le preferenze;
  - in un `FakeSessionController` non c'è il client HTTP: un metodo che non è sovrascritto e chiama `AuthService` lancia, quindi i metodi nuovi vanno sovrascritti nel fake.
- **ARB:**
  - le chiavi nuove vanno in fondo, prima della `}` finale (aggiungi la virgola alla riga prima);
  - ogni area ha il suo "Annulla" (`adminCancel`, `requestsCancel`…);
  - ci sono già `sessionExpired`, `menuLogout` ("Esci"), `settingsAccount`, `settingsSignedInAs`.

---

## Gruppo A — dati

### Task 1: i testi

**Files:**
- Modify: `l10n/app_it.arb`
- Modify: `l10n/app_en.arb`
- Create: `test/app/l10n_plan17b_test.dart`

- [ ] **Step 1: il test**

Crea `test/app/l10n_plan17b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 17b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.profilesTitle, 'Chi guarda?');
    expect(it.profilesAdd, 'Aggiungi profilo');
    expect(it.profilesManage, 'Gestisci profili');
    expect(it.profilesDone, 'Fine');
    expect(it.profilesSignInAgain, 'Accedi di nuovo');
    expect(it.profilesRemove, 'Rimuovi');
    expect(it.profilesRemoveTitle('Luigi'), 'Rimuovere Luigi da questo PC?');
    expect(it.profilesRemoveBody, 'Per usarlo di nuovo servirà l\'accesso.');
    expect(it.profilesLimit, 'Massimo 5 profili');
    expect(it.profilesCancel, 'Annulla');
    expect(it.profilesSwitch, 'Cambia profilo');
    expect(it.profilesSwitchLeavesParty, 'Uscirai dal watch party.');
    expect(en.profilesTitle, 'Who\'s watching?');
    expect(en.profilesRemoveTitle('Luigi'), 'Remove Luigi from this PC?');
    expect(en.profilesSwitch, 'Switch profile');

    // Ogni testo del piano c'è in tutte e due le lingue.
    for (final l in [it, en]) {
      expect([
        l.profilesTitle,
        l.profilesAdd,
        l.profilesManage,
        l.profilesDone,
        l.profilesSignInAgain,
        l.profilesRemove,
        l.profilesRemoveBody,
        l.profilesLimit,
        l.profilesCancel,
        l.profilesSwitch,
        l.profilesSwitchLeavesParty,
      ], everyElement(isNotEmpty));
    }
  });
}
```

- [ ] **Step 2: il test non compila**

Run: `flutter test test/app/l10n_plan17b_test.dart`
Expected: errore di compilazione (`profilesTitle` non esiste).

- [ ] **Step 3: le chiavi**

In `l10n/app_it.arb`, in fondo (aggiungi la virgola alla riga prima):

```json
  "profilesTitle": "Chi guarda?",
  "profilesAdd": "Aggiungi profilo",
  "profilesManage": "Gestisci profili",
  "profilesDone": "Fine",
  "profilesSignInAgain": "Accedi di nuovo",
  "profilesRemove": "Rimuovi",
  "profilesRemoveTitle": "Rimuovere {name} da questo PC?",
  "@profilesRemoveTitle": {"placeholders": {"name": {"type": "String"}}},
  "profilesRemoveBody": "Per usarlo di nuovo servirà l'accesso.",
  "profilesLimit": "Massimo 5 profili",
  "profilesCancel": "Annulla",
  "profilesSwitch": "Cambia profilo",
  "profilesSwitchLeavesParty": "Uscirai dal watch party."
```

In `l10n/app_en.arb`, in fondo (aggiungi la virgola alla riga prima):

```json
  "profilesTitle": "Who's watching?",
  "profilesAdd": "Add profile",
  "profilesManage": "Manage profiles",
  "profilesDone": "Done",
  "profilesSignInAgain": "Sign in again",
  "profilesRemove": "Remove",
  "profilesRemoveTitle": "Remove {name} from this PC?",
  "profilesRemoveBody": "You'll need to sign in again to use it.",
  "profilesLimit": "Up to 5 profiles",
  "profilesCancel": "Cancel",
  "profilesSwitch": "Switch profile",
  "profilesSwitchLeavesParty": "You'll leave the watch party."
```

Run: `flutter gen-l10n`

- [ ] **Step 4: il test passa**

Run: `flutter test test/app/l10n_plan17b_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add l10n test/app/l10n_plan17b_test.dart
git commit -m "feat(app): add the texts for profiles"
```

### Task 2: i profili salvati e la migrazione

**Files:**
- Create: `lib/core/storage/profile_store.dart`
- Modify: `lib/core/storage/session_store.dart`
- Modify: `lib/core/device/dev_profile.dart`
- Modify: `lib/app/error_text.dart`
- Modify: `docs/RELEASING.md`
- Create: `test/core/storage/profile_store_test.dart`
- Modify: `test/core/storage/session_store_test.dart` (solo un commento)
- Modify: `test/app/error_text_test.dart`

- [ ] **Step 1: i test**

Crea `test/core/storage/profile_store_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/device/dev_profile.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/core/storage/session_store.dart';

/// Storage finto che fallisce in lettura.
class _ThrowingReadStorage extends FlutterSecureStorage {
  const _ThrowingReadStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw PlatformException(code: 'boom');
  }
}

StoredProfile profile(String userId,
        {String name = 'Mario', bool expired = false, String? imageTag}) =>
    StoredProfile(
      userId: userId,
      name: name,
      accessToken: 'tok-$userId',
      deviceId: 'dev-$userId',
      imageTag: imageTag,
      lastUsedAt: DateTime.utc(2026, 10, 8, 20),
      expired: expired,
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  SecureProfileStore store() =>
      SecureProfileStore(legacyDeviceId: 'dev-installazione');

  group('ProfileBook', () {
    test('upsert sostituisce lo stesso utente al suo posto e aggiunge gli altri',
        () {
      final book = const ProfileBook()
          .upsert(profile('u1'))
          .upsert(profile('u2', name: 'Luigi'))
          .upsert(profile('U1', name: 'Mario Rossi'));
      expect(book.profiles.map((p) => p.name), ['Mario Rossi', 'Luigi']);
      expect(book.byId('u1')!.name, 'Mario Rossi');
    });

    test('remove toglie anche l\'ultimo usato', () {
      final book = const ProfileBook()
          .upsert(profile('u1'))
          .upsert(profile('u2'))
          .withLast('u2');
      expect(book.remove('u2').lastUserId, isNull);
      expect(book.remove('u1').lastUserId, 'u2');
      expect(book.remove('u1').profiles.single.userId, 'u2');
    });

    test('byId confronta senza trattini e maiuscole; isFull a 5', () {
      var book = const ProfileBook()
          .upsert(profile('ab8240c5-0000-0000-0000-00000000000a'));
      expect(book.byId('AB8240C500000000000000000000000A'), isNotNull);
      for (var i = 0; i < 4; i++) {
        book = book.upsert(profile('u$i'));
      }
      expect(book.profiles, hasLength(ProfileBook.maxProfiles));
      expect(book.isFull, isTrue);
    });

    test('fromJson: scarta i profili rotti e i doppioni, al massimo 5', () {
      final book = ProfileBook.fromJson({
        'version': 1,
        'profiles': [
          profile('u1').toJson(),
          {'userId': 'senza-token'},
          'non un oggetto',
          profile('U1', name: 'Doppione').toJson(),
          for (var i = 2; i <= 7; i++) profile('u$i').toJson(),
        ],
        'lastUserId': 'u9',
      });
      expect(book.profiles.map((p) => p.userId), ['u1', 'u2', 'u3', 'u4', 'u5']);
      expect(book.profiles.first.name, 'Mario');
      // Un ultimo usato che non c'è più non vale.
      expect(book.lastUserId, isNull);
    });
  });

  test('senza niente salvato: nessun profilo', () async {
    expect((await store().read()).profiles, isEmpty);
  });

  test('scrive e rilegge profili, ultimo usato, immagine e scadenza', () async {
    final written = const ProfileBook()
        .upsert(profile('u1', imageTag: 'img1'))
        .upsert(profile('u2', name: 'Luigi', expired: true))
        .withLast('u1');
    await store().write(written);

    final read = await store().read();
    expect(read.lastUserId, 'u1');
    final mario = read.byId('u1')!;
    expect(mario.accessToken, 'tok-u1');
    expect(mario.deviceId, 'dev-u1');
    expect(mario.imageTag, 'img1');
    expect(mario.lastUsedAt, DateTime.utc(2026, 10, 8, 20));
    expect(mario.expired, isFalse);
    expect(read.byId('u2')!.expired, isTrue);
  });

  test('migrazione: la sessione di prima diventa il primo profilo', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureSessionStore.key:
          jsonEncode({'userId': 'u1', 'accessToken': 'tok-vecchio'}),
    });

    final book = await store().read();

    final migrated = book.profiles.single;
    expect(migrated.userId, 'u1');
    expect(migrated.accessToken, 'tok-vecchio');
    // Il DeviceId di prima: il token resta valido.
    expect(migrated.deviceId, 'dev-installazione');
    // Il nome si legge al primo /Users/Me.
    expect(migrated.name, '');
    expect(book.lastUserId, 'u1');
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: SecureSessionStore.key), isNull);
    expect(await storage.read(key: SecureProfileStore.defaultKey), isNotNull);
    // Una seconda lettura non migra di nuovo.
    expect((await store().read()).profiles.single.accessToken, 'tok-vecchio');
  });

  test('profili illeggibili: nessun profilo, nessuna eccezione', () async {
    FlutterSecureStorage.setMockInitialValues(
        {SecureProfileStore.defaultKey: 'non-json'});
    expect((await store().read()).profiles, isEmpty);
  });

  test('uno storage che fallisce in lettura: nessun profilo', () async {
    final failing = SecureProfileStore(
        storage: const _ThrowingReadStorage(), legacyDeviceId: 'dev');
    expect((await failing.read()).profiles, isEmpty);
  });

  test('istanza di sviluppo: chiavi separate', () async {
    final dev = SecureProfileStore(
        key: profilesKeyFor('b'),
        legacyKey: sessionKeyFor('b'),
        legacyDeviceId: 'dev-b');
    expect(profilesKeyFor(null), SecureProfileStore.defaultKey);
    expect(profilesKeyFor('b'), 'wonderflix.profiles.b');
    await store().write(const ProfileBook().upsert(profile('u1')));
    await dev.write(const ProfileBook().upsert(profile('u2')));
    expect((await store().read()).profiles.single.userId, 'u1');
    expect((await dev.read()).profiles.single.userId, 'u2');
  });
}
```

In `test/app/error_text_test.dart` (ha già `l` in cima a `main`) aggiungi un test e l'import `package:wonderflix/core/storage/profile_store.dart`:

```dart
  test('un profilo in più del massimo', () {
    expect(describeError(l, const ProfileLimitException()), 'Massimo 5 profili');
  });
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/core/storage/profile_store_test.dart test/app/error_text_test.dart`
Expected: errori di compilazione (`profile_store.dart` non esiste).

- [ ] **Step 3: il codice**

Crea `lib/core/storage/profile_store.dart`:

```dart
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';

import '../jellyfin/json_fields.dart';
import 'session_store.dart';

final _log = Logger('profiles');

const Object _keep = Object();

bool _sameUser(String a, String b) => jellyfinIdKey(a) == jellyfinIdKey(b);

/// Un profilo salvato su questo PC (spec K §9.1): un account Jellyfin con il
/// suo token e il suo DeviceId.
class StoredProfile {
  const StoredProfile({
    required this.userId,
    required this.name,
    required this.accessToken,
    required this.deviceId,
    this.imageTag,
    this.lastUsedAt,
    this.expired = false,
  });

  /// `null` senza id, token o DeviceId: il profilo non si può usare.
  static StoredProfile? fromJson(Map<String, dynamic> json) {
    final userId = jsonString(json, 'userId');
    final accessToken = jsonString(json, 'accessToken');
    final deviceId = jsonString(json, 'deviceId');
    if (userId == null || accessToken == null || deviceId == null) return null;
    return StoredProfile(
      userId: userId,
      name: jsonString(json, 'name') ?? '',
      accessToken: accessToken,
      deviceId: deviceId,
      imageTag: jsonString(json, 'imageTag'),
      lastUsedAt: jsonDate(json, 'lastUsedAt'),
      expired: json['expired'] == true,
    );
  }

  final String userId;

  /// Nome dell'utente Jellyfin; vuoto finché non si legge (profilo migrato).
  final String name;
  final String accessToken;

  /// Il DeviceId con cui si è ottenuto il token.
  final String deviceId;

  /// Tag dell'immagine dell'utente (spec K §10); `null` senza immagine.
  final String? imageTag;
  final DateTime? lastUsedAt;

  /// Il server ha rifiutato il token (401): serve un nuovo accesso.
  final bool expired;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'accessToken': accessToken,
        'deviceId': deviceId,
        'imageTag': ?imageTag,
        'lastUsedAt': ?lastUsedAt?.toUtc().toIso8601String(),
        if (expired) 'expired': true,
      };

  StoredProfile copyWith({
    String? name,
    String? accessToken,
    String? deviceId,
    Object? imageTag = _keep,
    DateTime? lastUsedAt,
    bool? expired,
  }) =>
      StoredProfile(
        userId: userId,
        name: name ?? this.name,
        accessToken: accessToken ?? this.accessToken,
        deviceId: deviceId ?? this.deviceId,
        imageTag: identical(imageTag, _keep) ? this.imageTag : imageTag as String?,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        expired: expired ?? this.expired,
      );
}

/// I profili salvati su questo PC e l'ultimo usato (spec K §9.1). Immutabile:
/// ogni modifica dà un elenco nuovo.
class ProfileBook {
  const ProfileBook({this.profiles = const [], this.lastUserId});

  /// Profili al massimo su un PC (spec K §4).
  static const maxProfiles = 5;

  /// Versione del formato salvato.
  static const _version = 1;

  /// Tollerante: salta i profili senza id, token o DeviceId e i doppioni, ne
  /// tiene al massimo [maxProfiles]; un ultimo usato che non c'è più non vale.
  factory ProfileBook.fromJson(Map<String, dynamic> json) {
    final profiles = <StoredProfile>[];
    for (final raw in json['profiles'] is List ? json['profiles'] as List : const []) {
      final map = jsonMap(raw);
      final profile = map == null ? null : StoredProfile.fromJson(map);
      if (profile == null ||
          profiles.any((p) => _sameUser(p.userId, profile.userId))) {
        continue;
      }
      if (profiles.length < maxProfiles) profiles.add(profile);
    }
    final last = jsonString(json, 'lastUserId');
    return ProfileBook(
      profiles: List.unmodifiable(profiles),
      lastUserId: last != null && profiles.any((p) => _sameUser(p.userId, last))
          ? last
          : null,
    );
  }

  /// Nell'ordine in cui sono stati aggiunti.
  final List<StoredProfile> profiles;

  /// L'ultimo profilo aperto (la lingua di "Chi guarda?", spec K §9.4).
  final String? lastUserId;

  bool get isEmpty => profiles.isEmpty;

  /// Nessun profilo in più: "Aggiungi profilo" non c'è.
  bool get isFull => profiles.length >= maxProfiles;

  StoredProfile? byId(String userId) {
    for (final profile in profiles) {
      if (_sameUser(profile.userId, userId)) return profile;
    }
    return null;
  }

  /// [profile] al posto di quello dello stesso utente, o in fondo.
  ProfileBook upsert(StoredProfile profile) {
    final next = profiles.toList();
    final index = next.indexWhere((p) => _sameUser(p.userId, profile.userId));
    if (index >= 0) {
      next[index] = profile;
    } else {
      next.add(profile);
    }
    return ProfileBook(profiles: List.unmodifiable(next), lastUserId: lastUserId);
  }

  ProfileBook remove(String userId) => ProfileBook(
        profiles: List.unmodifiable(
            profiles.where((p) => !_sameUser(p.userId, userId))),
        lastUserId: lastUserId != null && _sameUser(lastUserId!, userId)
            ? null
            : lastUserId,
      );

  ProfileBook withLast(String userId) =>
      ProfileBook(profiles: profiles, lastUserId: userId);

  Map<String, dynamic> toJson() => {
        'version': _version,
        'profiles': [for (final profile in profiles) profile.toJson()],
        'lastUserId': ?lastUserId,
      };
}

/// Un profilo in più del massimo (spec K §4).
class ProfileLimitException implements Exception {
  const ProfileLimitException();

  @override
  String toString() => 'ProfileLimitException';
}

/// Dove stanno i profili (spec K §9.1).
abstract interface class ProfileStore {
  /// I profili salvati; vuoto se non ce ne sono o se non si leggono.
  Future<ProfileBook> read();

  Future<void> write(ProfileBook book);
}

/// I profili in `flutter_secure_storage`: su Windows un file JSON cifrato con
/// DPAPI (`flutter_secure_storage.dat` nella cartella dei dati dell'app).
class SecureProfileStore implements ProfileStore {
  SecureProfileStore({
    FlutterSecureStorage? storage,
    this.key = defaultKey,
    this.legacyKey = SecureSessionStore.key,
    required this.legacyDeviceId,
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const defaultKey = 'wonderflix.profiles';

  final FlutterSecureStorage _storage;
  final String key;

  /// La sessione unica delle versioni prima della 0.11.0.
  final String legacyKey;

  /// Il DeviceId di quella sessione (`device_id` delle preferenze, o quello
  /// dell'istanza di sviluppo).
  final String legacyDeviceId;

  @override
  Future<ProfileBook> read() async {
    final String? raw;
    try {
      raw = await _storage.read(key: key);
    } on Object catch (error) {
      _log.warning('profili non letti: ${error.runtimeType}');
      return const ProfileBook();
    }
    if (raw == null) return _migrate();
    try {
      return ProfileBook.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error) {
      // Come una sessione illeggibile: si rifà l'accesso (spec K §9.1).
      _log.warning('profili illeggibili: ${error.runtimeType}');
      return const ProfileBook();
    }
  }

  /// Prima della 0.11.0 c'era una sessione sola: diventa il primo profilo,
  /// con il DeviceId di allora, così il token resta valido (spec K §9.1).
  Future<ProfileBook> _migrate() async {
    final legacy = SecureSessionStore(_storage, legacyKey);
    final session = await legacy.read();
    if (session == null) return const ProfileBook();
    final book = ProfileBook(
      profiles: List.unmodifiable([
        StoredProfile(
          userId: session.userId,
          name: '',
          accessToken: session.accessToken,
          deviceId: legacyDeviceId,
        ),
      ]),
      lastUserId: session.userId,
    );
    await write(book);
    await legacy.clear();
    _log.info('sessione di prima portata nei profili');
    return book;
  }

  @override
  Future<void> write(ProfileBook book) =>
      _storage.write(key: key, value: jsonEncode(book.toJson()));
}
```

Nota: `SecureSessionStore.read()` cancella la chiave se la lettura fallisce o il valore è rovinato: in quel caso la migrazione non trova niente e si rifà l'accesso, come oggi.

In `lib/core/storage/session_store.dart`, il commento di `SecureSessionStore`:

```dart
/// La sessione unica delle versioni prima della 0.11.0, in
/// `flutter_secure_storage` (su Windows un file JSON cifrato con DPAPI). Dalla
/// 0.11.0 serve solo alla migrazione nei profili (`SecureProfileStore`).
```

In `lib/core/device/dev_profile.dart`:
- l'import `../storage/profile_store.dart`;
- il commento di `sessionKeyFor`:

```dart
/// Chiave della sessione di prima della 0.11.0 (migrazione nei profili).
```

- dopo `sessionKeyFor`:

```dart

/// Chiave dei profili (spec K §9.1); l'istanza di sviluppo ha la sua.
String profilesKeyFor(String? profile) => profile == null
    ? SecureProfileStore.defaultKey
    : '${SecureProfileStore.defaultKey}.$profile';
```

In `test/core/storage/session_store_test.dart`, il commento di `_ThrowingReadStorage` diventa "Storage finto che fallisce in lettura." (il Gestore credenziali non c'entra).

In `lib/app/error_text.dart`:
- l'import `import '../core/storage/profile_store.dart';`;
- nello `switch`, prima di `_ => l.errorGeneric,`:

```dart
      ProfileLimitException() => l.profilesLimit,
```

In `docs/RELEASING.md` (riga 57) sostituisci "credenziali nel Gestore credenziali di Windows" con "profili e token in `flutter_secure_storage.dat`, un file cifrato con DPAPI nella cartella dei dati dell'app".

- [ ] **Step 4: i test passano**

Run: `flutter test test/core/storage test/app/error_text_test.dart`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test docs/RELEASING.md
git commit -m "feat(app): store profiles and migrate the old session"
```

### Task 3: credenziali del profilo nel client HTTP

**Files:**
- Modify: `lib/core/jellyfin/client_info.dart`
- Modify: `lib/core/jellyfin/jellyfin_http.dart`
- Modify: `test/core/jellyfin/client_info_test.dart`
- Modify: `test/core/jellyfin/jellyfin_http_test.dart`

- [ ] **Step 1: i test**

In `test/core/jellyfin/client_info_test.dart` (ha già `info` in cima a `main`, con DeviceId `dev-1`), in fondo a `main`:

```dart
  test('copyWith cambia solo il DeviceId', () {
    final copy = info.copyWith(deviceId: 'dev-2');
    expect(copy.deviceId, 'dev-2');
    expect(copy.client, info.client);
    expect(copy.device, info.device);
    expect(copy.version, info.version);
    expect(info.copyWith().deviceId, 'dev-1');
  });
```

In `test/core/jellyfin/jellyfin_http_test.dart` (ha già gli import di `fake_adapter.dart`, `test_data.dart` e `api_exception.dart`), in fondo a `main`:

```dart
  group('credenziali del profilo (spec K §9.2)', () {
    test('token e DeviceId vanno nell\'intestazione insieme', () async {
      final adapter = FakeAdapter((_) => const FakeResponse(200, {}));
      final http = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
      expect(http.deviceId, 'dev-test');

      http.setCredentials(token: 'tok-1', deviceId: 'dev-1');
      await http.get('/Users/Me');
      final header = adapter.requests.last.headers['Authorization'] as String;
      expect(header, contains('DeviceId="dev-1"'));
      expect(header, contains('Token="tok-1"'));
      expect(http.deviceId, 'dev-1');

      http.setCredentials(token: null, deviceId: null);
      await http.get('/System/Info/Public');
      final reset = adapter.requests.last.headers['Authorization'] as String;
      expect(reset, contains('DeviceId="dev-test"'));
      expect(reset, isNot(contains('Token=')));
    });

    test('withCredentials: un altro profilo, lo stesso server', () async {
      final adapter = FakeAdapter((_) => const FakeResponse(401));
      final http = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter)
        ..setCredentials(token: 'tok-attivo', deviceId: 'dev-attivo');
      var unauthorized = 0;
      http.onUnauthorized = () => unauthorized++;

      final other = http.withCredentials(token: 'tok-2', deviceId: 'dev-2');
      await expectLater(
          other.post('/Sessions/Logout'), throwsA(isA<UnauthorizedException>()));

      final header = adapter.requests.single.headers['Authorization'] as String;
      expect(header, contains('Token="tok-2"'));
      expect(header, contains('DeviceId="dev-2"'));
      expect(adapter.requests.single.uri.toString(),
          startsWith(testServerUrl.toString()));
      // Le credenziali attive restano, e il 401 di un altro profilo non fa
      // uscire nessuno.
      expect(http.token, 'tok-attivo');
      expect(http.deviceId, 'dev-attivo');
      expect(unauthorized, 0);
    });
  });
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/core/jellyfin/client_info_test.dart test/core/jellyfin/jellyfin_http_test.dart`
Expected: errori di compilazione (`copyWith`, `setCredentials`, `withCredentials`, `deviceId`).

- [ ] **Step 3: il codice**

In `lib/core/jellyfin/client_info.dart`, nella classe `ClientInfo`:

```dart
  /// Lo stesso client con il DeviceId di un profilo (spec K §9.2).
  ClientInfo copyWith({String? deviceId}) => ClientInfo(
        client: client,
        device: device,
        deviceId: deviceId ?? this.deviceId,
        version: version,
      );
```

In `lib/core/jellyfin/jellyfin_http.dart`:
- il costruttore tiene anche l'indirizzo, per `withCredentials`:

```dart
  })  : _baseUrl = baseUrl,
        _clientInfo = clientInfo,
        dio = Dio(BaseOptions(
```

  e tra i campi, dopo `final Dio dio;`: `final Uri _baseUrl;`
- dopo `String? token;`:

```dart

  /// DeviceId del profilo attivo (spec K §9.2); `null`: quello
  /// dell'installazione (`ClientInfo.deviceId`).
  String? _deviceId;

  /// Il DeviceId che va nelle richieste.
  String get deviceId => _deviceId ?? _clientInfo.deviceId;

  /// Token e DeviceId del profilo attivo cambiano insieme (spec K §9.2). Con
  /// `null` si torna a nessun token e al DeviceId dell'installazione.
  void setCredentials({required String? token, required String? deviceId}) {
    this.token = token;
    _deviceId = deviceId;
  }

  /// Un client per le chiamate di un profilo non attivo (spec K §9.2): stesso
  /// server e stesso adattatore, le credenziali di quel profilo. Non tocca
  /// quelle di questo client e non segnala i 401 (nessun `onUnauthorized`).
  JellyfinHttp withCredentials(
          {required String token, required String deviceId}) =>
      JellyfinHttp(
        baseUrl: _baseUrl,
        clientInfo: _clientInfo,
        adapter: dio.httpClientAdapter,
      )..setCredentials(token: token, deviceId: deviceId);
```

- `authorizationHeader`:

```dart
  String get authorizationHeader => buildAuthorizationHeader(
      _clientInfo.copyWith(deviceId: deviceId),
      token: token);
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/core/jellyfin`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): switch token and device id together in the http client"
```

## Gruppo B — sessione

### Task 4: sessione con i profili

**Files:**
- Create: `lib/features/auth/profiles_state.dart`
- Modify: `lib/features/auth/auth_service.dart`
- Modify: `lib/features/auth/session_controller.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/app/router.dart`
- Create: `test/support/profile_fakes.dart`
- Delete: `test/support/memory_session_store.dart`
- Modify: `test/support/fake_session_controller.dart`
- Modify (riscrittura): `test/features/auth/auth_service_test.dart`
- Modify (riscrittura): `test/features/auth/session_controller_test.dart`
- Modify: `test/app/router_test.dart`

- [ ] **Step 1: il supporto ai test**

Crea `test/support/profile_fakes.dart`:

```dart
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';

/// `ProfileStore` in memoria.
class MemoryProfileStore implements ProfileStore {
  MemoryProfileStore([this.book = const ProfileBook()]);

  ProfileBook book;
  int writes = 0;

  @override
  Future<ProfileBook> read() async => book;

  @override
  Future<void> write(ProfileBook book) async {
    writes++;
    this.book = book;
  }
}

/// Un profilo di prova: token `tok-<id>` e DeviceId `dev-<id>` se non dati.
StoredProfile testProfile({
  String userId = 'u1',
  String name = 'Mario',
  String? token,
  String? deviceId,
  String? imageTag,
  bool expired = false,
}) =>
    StoredProfile(
      userId: userId,
      name: name,
      accessToken: token ?? 'tok-$userId',
      deviceId: deviceId ?? 'dev-$userId',
      imageTag: imageTag,
      expired: expired,
    );

/// I profili per l'interfaccia, fissi.
class FixedProfiles extends ProfilesController {
  FixedProfiles(this.initial);

  final ProfilesState initial;

  @override
  ProfilesState build() => initial;
}
```

Cancella `test/support/memory_session_store.dart` (lo usava solo `auth_service_test.dart`).

- [ ] **Step 2: i test di `AuthService`**

Riscrivi `test/features/auth/auth_service_test.dart`:

```dart
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/auth_service.dart';

import '../../support/fake_adapter.dart';
import '../../support/profile_fakes.dart';
import '../../support/test_data.dart';

class MockAuthApi extends Mock implements AuthApi {}

void main() {
  late MockAuthApi api;
  late MockAuthApi revokeApi;
  late JellyfinHttp http;
  late MemoryProfileStore store;
  late AuthService service;

  /// Le credenziali dei client passati ad `apiFor`: i token annullati.
  late List<(String?, String)> revoked;
  late int newDeviceIds;

  final mario = testProfile(userId: 'u1', name: 'Mario');
  final luigi = testProfile(userId: 'u2', name: 'Luigi');
  final now = DateTime.utc(2026, 10, 8, 20);

  ProfileBook bookOf(List<StoredProfile> profiles) =>
      profiles.fold(const ProfileBook(), (book, p) => book.upsert(p));

  setUp(() {
    api = MockAuthApi();
    revokeApi = MockAuthApi();
    when(() => revokeApi.logout()).thenAnswer((_) async {});
    revoked = [];
    newDeviceIds = 0;
    http = JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo);
    store = MemoryProfileStore();
    service = AuthService(
      http: http,
      api: api,
      store: store,
      apiFor: (client) {
        revoked.add((client.token, client.deviceId));
        return revokeApi;
      },
      newDeviceId: () => 'dev-nuovo-${++newDeviceIds}',
    );
  });

  group('restore', () {
    test('nessun profilo: NoStoredSession, nessuna chiamata', () async {
      expect(await service.restore(), isA<NoStoredSession>());
      verifyNever(() => api.getMe());
    });

    test('un profilo valido: le sue credenziali, nome e immagine aggiornati',
        () async {
      store.book = bookOf([mario.copyWith(name: '')]);
      when(() => api.getMe()).thenAnswer((_) async =>
          const JellyfinUser(id: 'u1', name: 'Mario', primaryImageTag: 'img1'));

      final result = await withClock(Clock.fixed(now), service.restore);

      expect((result as RestoredSession).user.name, 'Mario');
      expect(http.token, 'tok-u1');
      expect(http.deviceId, 'dev-u1');
      expect(service.activeUserId, 'u1');
      final saved = store.book.byId('u1')!;
      expect(saved.name, 'Mario');
      expect(saved.imageTag, 'img1');
      expect(saved.lastUsedAt, now);
      expect(store.book.lastUserId, 'u1');
      expect(service.book.byId('u1')!.name, 'Mario');
    });

    test('un profilo scaduto (401): segnato, credenziali tolte', () async {
      store.book = bookOf([mario]);
      when(() => api.getMe()).thenThrow(const UnauthorizedException());

      final result = await service.restore();

      expect((result as StoredSessionExpired).userId, 'u1');
      expect(store.book.byId('u1')!.expired, isTrue);
      expect(http.token, isNull);
      expect(http.deviceId, 'dev-test');
      expect(service.activeUserId, isNull);
    });

    test('un profilo e server giù: irraggiungibile, profilo intatto', () async {
      store.book = bookOf([mario]);
      when(() => api.getMe()).thenThrow(const ServerUnreachableException());

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(store.book.byId('u1')!.expired, isFalse);
      expect(http.token, isNull);
    });

    test('errore 500: come irraggiungibile, profilo intatto', () async {
      store.book = bookOf([mario]);
      when(() => api.getMe()).thenThrow(const ServerErrorException(500));

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(store.book.byId('u1')!.accessToken, 'tok-u1');
    });

    test('due profili: si sceglie, nessuna chiamata', () async {
      store.book = bookOf([mario, luigi]);
      expect(await service.restore(), isA<ChooseProfile>());
      verifyNever(() => api.getMe());
      expect(service.book.profiles, hasLength(2));
    });
  });

  group('openProfile', () {
    setUp(() async {
      store.book = bookOf([mario, luigi]);
      await service.restore();
    });

    test('apre il profilo scelto con le sue credenziali', () async {
      when(() => api.getMe()).thenAnswer(
          (_) async => const JellyfinUser(id: 'u2', name: 'Luigi'));

      final result = await service.openProfile('u2');

      expect((result as RestoredSession).user.id, 'u2');
      expect(http.token, 'tok-u2');
      expect(http.deviceId, 'dev-u2');
      expect(store.book.lastUserId, 'u2');
    });

    test('un profilo che non c\'è: di nuovo la scelta', () async {
      expect(await service.openProfile('u9'), isA<ChooseProfile>());
      verifyNever(() => api.getMe());
    });
  });

  group('accesso', () {
    test('prepareLogin: DeviceId nuovo, o quello del profilo che rifà l\'accesso',
        () async {
      store.book = bookOf([mario, luigi]);
      await service.restore();

      service.prepareLogin();
      expect(http.deviceId, 'dev-nuovo-1');
      expect(http.token, isNull);

      service.prepareLogin(userId: 'u2');
      expect(http.deviceId, 'dev-u2');
    });

    test('password: profilo nuovo con il DeviceId dell\'accesso', () async {
      service.prepareLogin();
      when(() => api.authenticateByName('mario', 'pw')).thenAnswer((_) async =>
          const AuthResult(user: testUser, accessToken: 'tok-nuovo'));

      final user = await withClock(
          Clock.fixed(now), () => service.loginWithPassword('  mario ', 'pw'));

      expect(user.id, 'u1');
      final saved = store.book.byId('u1')!;
      expect(saved.accessToken, 'tok-nuovo');
      expect(saved.deviceId, 'dev-nuovo-1');
      expect(saved.name, 'Mario');
      expect(saved.lastUsedAt, now);
      expect(store.book.lastUserId, 'u1');
      expect(http.token, 'tok-nuovo');
      expect(http.deviceId, 'dev-nuovo-1');
      expect(service.activeUserId, 'u1');
      expect(revoked, isEmpty);
    });

    test('stesso utente: un solo profilo, token vecchio annullato', () async {
      store.book = bookOf([mario, luigi]);
      await service.restore();
      service.prepareLogin();
      when(() => api.authenticateByName(any(), any())).thenAnswer((_) async =>
          const AuthResult(user: testUser, accessToken: 'tok-nuovo'));

      await service.loginWithPassword('mario', 'pw');

      expect(store.book.profiles.map((p) => p.userId), ['u1', 'u2']);
      expect(store.book.byId('u1')!.accessToken, 'tok-nuovo');
      // Il token vecchio, con le sue credenziali.
      expect(revoked, [('tok-u1', 'dev-u1')]);
      verify(() => revokeApi.logout()).called(1);
    });

    test('sesto profilo: rifiutato, token nuovo annullato, niente salvato',
        () async {
      store.book = bookOf([
        for (var i = 1; i <= ProfileBook.maxProfiles; i++)
          testProfile(userId: 'u$i'),
      ]);
      await service.restore();
      service.prepareLogin();
      final writes = store.writes;
      when(() => api.authenticateByName(any(), any())).thenAnswer((_) async =>
          const AuthResult(
              user: JellyfinUser(id: 'u9', name: 'Toad'),
              accessToken: 'tok-u9'));

      await expectLater(service.loginWithPassword('toad', 'pw'),
          throwsA(isA<ProfileLimitException>()));

      expect(store.writes, writes);
      expect(store.book.byId('u9'), isNull);
      expect(revoked, [('tok-u9', 'dev-nuovo-1')]);
      expect(service.activeUserId, isNull);
    });

    test('errore del server: niente salvato', () async {
      service.prepareLogin();
      when(() => api.authenticateByName(any(), any()))
          .thenThrow(const UnauthorizedException());

      await expectLater(service.loginWithPassword('mario', 'x'),
          throwsA(isA<UnauthorizedException>()));
      expect(store.book.isEmpty, isTrue);
      expect(store.writes, 0);
    });

    test('Quick Connect: come la password', () async {
      service.prepareLogin();
      when(() => api.authenticateWithQuickConnect('s1')).thenAnswer(
          (_) async => const AuthResult(user: testUser, accessToken: 'tok-qc'));

      await service.completeQuickConnect('s1');

      expect(store.book.byId('u1')!.accessToken, 'tok-qc');
      expect(store.book.byId('u1')!.deviceId, 'dev-nuovo-1');
      expect(http.token, 'tok-qc');
    });
  });

  group('uscita', () {
    Future<void> openMario() async {
      store.book = bookOf([mario, luigi]);
      await service.restore();
      when(() => api.getMe()).thenAnswer((_) async => testUser);
      await service.openProfile('u1');
    }

    test('logout: token annullato, profilo tolto, id restituito', () async {
      await openMario();
      when(() => api.logout()).thenAnswer((_) async {});

      expect(await service.logout(), 'u1');

      verify(() => api.logout()).called(1);
      expect(store.book.byId('u1'), isNull);
      expect(store.book.byId('u2'), isNotNull);
      expect(http.token, isNull);
      expect(service.activeUserId, isNull);
    });

    test('logout con il server giù: il profilo si toglie lo stesso', () async {
      await openMario();
      when(() => api.logout()).thenThrow(const ServerUnreachableException());

      expect(await service.logout(), 'u1');
      expect(store.book.byId('u1'), isNull);
    });

    test('logout senza profilo attivo: niente', () async {
      expect(await service.logout(), isNull);
      verifyNever(() => api.logout());
    });

    test('removeProfile di un altro profilo: con le sue credenziali', () async {
      await openMario();

      await service.removeProfile('u2');

      expect(revoked, [('tok-u2', 'dev-u2')]);
      expect(store.book.byId('u2'), isNull);
      // Le credenziali attive restano.
      expect(http.token, 'tok-u1');
      expect(service.activeUserId, 'u1');
    });

    test('removeProfile del profilo attivo: come logout', () async {
      await openMario();
      when(() => api.logout()).thenAnswer((_) async {});

      await service.removeProfile('u1');

      verify(() => api.logout()).called(1);
      expect(store.book.byId('u1'), isNull);
      expect(http.token, isNull);
    });

    test('removeProfile con il server giù: il profilo si toglie lo stesso',
        () async {
      await openMario();
      when(() => revokeApi.logout())
          .thenThrow(const ServerUnreachableException());

      await service.removeProfile('u2');
      expect(store.book.byId('u2'), isNull);
    });

    test('deactivate: credenziali tolte, token salvato', () async {
      await openMario();

      service.deactivate();

      expect(http.token, isNull);
      expect(http.deviceId, 'dev-test');
      expect(service.activeUserId, isNull);
      expect(store.book.byId('u1')!.accessToken, 'tok-u1');
    });

    test('markActiveExpired: il profilo attivo è scaduto', () async {
      await openMario();

      await service.markActiveExpired();

      expect(store.book.byId('u1')!.expired, isTrue);
      expect(http.token, isNull);
      expect(service.activeUserId, isNull);
    });

    test('updateActiveProfile: nome e immagine, solo se cambiano', () async {
      await openMario();
      final writes = store.writes;

      await service.updateActiveProfile(testUser);
      expect(store.writes, writes);

      await service.updateActiveProfile(const JellyfinUser(
          id: 'u1', name: 'Mario Rossi', primaryImageTag: 'img2'));
      expect(store.book.byId('u1')!.name, 'Mario Rossi');
      expect(store.book.byId('u1')!.imageTag, 'img2');

      // Un altro utente non tocca il profilo attivo.
      await service.updateActiveProfile(
          const JellyfinUser(id: 'u2', name: 'Altro'));
      expect(store.book.byId('u2')!.name, 'Luigi');
    });
  });

  test('currentUser rilegge /Users/Me', () async {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);
    when(() => api.getMe(quietStatuses: any(named: 'quietStatuses')))
        .thenAnswer((_) async => admin);

    expect((await service.currentUser()).isAdministrator, isTrue);
    // Durante un riavvio i 502/503/504 sono attesi: nel log come info.
    verify(() => api.getMe(quietStatuses: const {502, 503, 504})).called(1);
  });

  group('log durante un riavvio (AuthApi vero)', () {
    late FakeAdapter adapter;
    late List<LogRecord> records;

    setUp(() {
      records = [];
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      addTearDown(() => Logger.root.level = previousLevel);
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      adapter = FakeAdapter((_) => const FakeResponse(503));
    });

    AuthService realService(MemoryProfileStore store) {
      final realHttp = JellyfinHttp(
          baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter);
      return AuthService(http: realHttp, api: AuthApi(realHttp), store: store);
    }

    List<(Level, String)> httpLog() => [
          for (final record in records)
            if (record.loggerName == 'http') (record.level, record.message),
        ];

    test('currentUser: 502, 503 e 504 come info, un 500 come avviso',
        () async {
      final service = realService(MemoryProfileStore());
      for (final status in [502, 503, 504, 500]) {
        adapter.handler = (_) => FakeResponse(status);
        await expectLater(
            service.currentUser(), throwsA(isA<ServerErrorException>()));
      }

      expect(httpLog(), [
        (Level.INFO, 'GET /Users/Me: 502'),
        (Level.INFO, 'GET /Users/Me: 503'),
        (Level.INFO, 'GET /Users/Me: 504'),
        (Level.WARNING, 'GET /Users/Me: 500'),
      ]);
    });

    test('il ripristino resta com\'era: un 503 è un avviso', () async {
      final service = realService(MemoryProfileStore(bookOf([mario])));

      expect(await service.restore(), isA<RestoreServerUnreachable>());
      expect(httpLog(), [(Level.WARNING, 'GET /Users/Me: 503')]);
    });
  });
}
```

- [ ] **Step 3: i test del controller e del router**

Riscrivi `test/features/auth/session_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/auth_service.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/profile_fakes.dart';
import '../../support/test_data.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService auth;
  late JellyfinHttp http;
  late ProviderContainer container;

  final twoProfiles = const ProfileBook()
      .upsert(testProfile(userId: 'u1'))
      .upsert(testProfile(userId: 'u2', name: 'Luigi'));

  SessionController controller() =>
      container.read(sessionControllerProvider.notifier);
  SessionState state() => container.read(sessionControllerProvider);
  ProfilesState profiles() => container.read(profilesProvider);

  setUpAll(() => registerFallbackValue(testUser));

  setUp(() {
    auth = MockAuthService();
    when(() => auth.book).thenReturn(const ProfileBook());
    when(() => auth.activeUserId).thenReturn(null);
    when(() => auth.updateActiveProfile(any())).thenAnswer((_) async {});
    when(() => auth.markActiveExpired()).thenAnswer((_) async {});
    http = JellyfinHttp(baseUrl: testServerUrl, clientInfo: testClientInfo);
    container = ProviderContainer.test(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        jellyfinHttpProvider.overrideWithValue(http),
      ],
      retry: (_, _) => null,
    );
  });

  test('parte in SessionStarting', () {
    expect(state(), isA<SessionStarting>());
  });

  group('restore', () {
    test('sessione valida → SignedIn, e i profili per l\'interfaccia', () async {
      when(() => auth.restore())
          .thenAnswer((_) async => const RestoredSession(testUser));
      when(() => auth.book).thenReturn(twoProfiles);
      when(() => auth.activeUserId).thenReturn('u1');

      await controller().restore();

      expect(state(), isA<SessionSignedIn>());
      expect(profiles().book, same(twoProfiles));
      expect(profiles().activeUserId, 'u1');
    });

    test('nessun profilo → SignedOut', () async {
      when(() => auth.restore()).thenAnswer((_) async => const NoStoredSession());
      await controller().restore();
      expect(state(),
          isA<SessionSignedOut>().having((s) => s.expired, 'expired', false));
    });

    test('profilo scaduto → accesso per quel profilo', () async {
      when(() => auth.restore())
          .thenAnswer((_) async => const StoredSessionExpired('u1'));
      await controller().restore();
      expect(
          state(),
          isA<SessionSignedOut>()
              .having((s) => s.expired, 'expired', true)
              .having((s) => s.reloginUserId, 'reloginUserId', 'u1'));
    });

    test('più profili → "Chi guarda?"', () async {
      when(() => auth.restore()).thenAnswer((_) async => const ChooseProfile());
      await controller().restore();
      expect(state(), isA<SessionChoosingProfile>());
    });

    test('server giù → Unreachable', () async {
      when(() => auth.restore())
          .thenAnswer((_) async => const RestoreServerUnreachable());
      await controller().restore();
      expect(state(), isA<SessionUnreachable>());
    });

    test('errore inatteso → Unreachable', () async {
      when(() => auth.restore()).thenThrow(StateError('boom'));
      await controller().restore();
      expect(state(), isA<SessionUnreachable>());
    });
  });

  group('openProfile', () {
    test('riuscito → SignedIn', () async {
      when(() => auth.openProfile('u2')).thenAnswer((_) async =>
          const RestoredSession(JellyfinUser(id: 'u2', name: 'Luigi')));
      await controller().openProfile('u2');
      expect((state() as SessionSignedIn).user.id, 'u2');
    });

    test('scaduto → accesso per quel profilo', () async {
      when(() => auth.openProfile('u2'))
          .thenAnswer((_) async => const StoredSessionExpired('u2'));
      await controller().openProfile('u2');
      expect((state() as SessionSignedOut).reloginUserId, 'u2');
    });

    test('errore inatteso → Unreachable', () async {
      when(() => auth.openProfile('u2')).thenThrow(StateError('boom'));
      await controller().openProfile('u2');
      expect(state(), isA<SessionUnreachable>());
    });
  });

  test('login riuscito → SignedIn; errore propagato e stato invariato',
      () async {
    when(() => auth.restore()).thenAnswer((_) async => const NoStoredSession());
    await controller().restore();

    when(() => auth.loginWithPassword('mario', 'bad'))
        .thenThrow(const UnauthorizedException());
    await expectLater(controller().loginWithPassword('mario', 'bad'),
        throwsA(isA<UnauthorizedException>()));
    expect(state(), isA<SessionSignedOut>());

    when(() => auth.loginWithPassword('mario', 'ok'))
        .thenAnswer((_) async => testUser);
    await controller().loginWithPassword('mario', 'ok');
    expect(state(), isA<SessionSignedIn>());
  });

  test('quickConnectApproved → SignedIn', () {
    controller().quickConnectApproved(testUser);
    expect(state(), isA<SessionSignedIn>());
  });

  group('cambi di profilo', () {
    test('prepareLogin passa il profilo che rifà l\'accesso', () {
      controller().prepareLogin();
      verify(() => auth.prepareLogin()).called(1);

      controller().relogin('u2');
      controller().prepareLogin();
      verify(() => auth.prepareLogin(userId: 'u2')).called(1);
    });

    test('switchProfile: credenziali tolte, "Chi guarda?"', () {
      when(() => auth.book).thenReturn(twoProfiles);
      controller().quickConnectApproved(testUser);

      controller().switchProfile();

      verify(() => auth.deactivate()).called(1);
      expect(state(), isA<SessionChoosingProfile>());
    });

    test('addProfile: accesso per un profilo nuovo', () {
      controller().quickConnectApproved(testUser);

      controller().addProfile();

      verify(() => auth.deactivate()).called(1);
      expect((state() as SessionSignedOut).adding, isTrue);
    });

    test('relogin: accesso per quel profilo, con l\'avviso', () {
      controller().relogin('u2');
      final signedOut = state() as SessionSignedOut;
      expect(signedOut.reloginUserId, 'u2');
      expect(signedOut.expired, isTrue);
    });

    test('cancelLogin: "Chi guarda?" se ci sono profili, altrimenti accesso',
        () {
      controller().addProfile();
      when(() => auth.book).thenReturn(twoProfiles);
      controller().cancelLogin();
      expect(state(), isA<SessionChoosingProfile>());

      when(() => auth.book).thenReturn(const ProfileBook());
      controller().cancelLogin();
      expect(state(), isA<SessionSignedOut>());
    });

    test('logout: "Chi guarda?" se restano profili', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      when(() => auth.book)
          .thenReturn(const ProfileBook().upsert(testProfile(userId: 'u2')));
      controller().quickConnectApproved(testUser);

      await controller().logout();

      verify(() => auth.logout()).called(1);
      expect(state(), isA<SessionChoosingProfile>());
    });

    test('logout dell\'ultimo profilo: accesso', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      controller().quickConnectApproved(testUser);

      await controller().logout();

      expect(state(), isA<SessionSignedOut>());
    });

    test('removeProfile da "Chi guarda?": resta la scelta finché ci sono profili',
        () async {
      when(() => auth.removeProfile('u2')).thenAnswer((_) async {});
      when(() => auth.book)
          .thenReturn(const ProfileBook().upsert(testProfile(userId: 'u1')));

      await controller().removeProfile('u2');

      verify(() => auth.removeProfile('u2')).called(1);
      expect(state(), isA<SessionChoosingProfile>());
      expect(profiles().book.profiles.single.userId, 'u1');
    });
  });

  test('un 401 durante la sessione: accesso per quel profilo, scaduto',
      () async {
    controller().quickConnectApproved(testUser);

    http.onUnauthorized!.call();

    expect(
        state(),
        isA<SessionSignedOut>()
            .having((s) => s.expired, 'expired', true)
            .having((s) => s.reloginUserId, 'reloginUserId', 'u1'));
    verify(() => auth.markActiveExpired()).called(1);
  });

  test('un 401 della richiesta di uscita: si esce e basta', () async {
    when(() => auth.logout()).thenAnswer((_) async {
      // Il token era già scaduto: il server risponde 401 al logout.
      http.onUnauthorized!.call();
      return 'u1';
    });
    controller().quickConnectApproved(testUser);

    await controller().logout();

    verifyNever(() => auth.markActiveExpired());
    expect(state(),
        isA<SessionSignedOut>().having((s) => s.reloginUserId, 'relogin', null));
  });

  group('refreshUser', () {
    const admin = JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true);

    Future<void> signIn() async {
      when(() => auth.restore())
          .thenAnswer((_) async => const RestoredSession(admin));
      await controller().restore();
    }

    test('rilegge l\'utente, lo mette nella sessione e nel profilo', () async {
      await signIn();
      when(() => auth.currentUser()).thenAnswer((_) async => testUser);

      await controller().refreshUser();

      expect((state() as SessionSignedIn).user.isAdministrator, isFalse);
      verify(() => auth.updateActiveProfile(testUser)).called(1);
    });

    test('errore: la sessione resta com\'è', () async {
      await signIn();
      when(() => auth.currentUser())
          .thenThrow(const ServerUnreachableException());

      await controller().refreshUser();

      expect((state() as SessionSignedIn).user.isAdministrator, isTrue);
    });

    test('senza sessione non chiede nulla', () async {
      await controller().refreshUser();
      verifyNever(() => auth.currentUser());
    });

    test('un utente diverso nel frattempo: il risultato non si applica',
        () async {
      await signIn();
      final answer = Completer<JellyfinUser>();
      when(() => auth.currentUser()).thenAnswer((_) => answer.future);

      final refreshing = controller().refreshUser();
      const other = JellyfinUser(id: 'u2', name: 'Luigi');
      controller().quickConnectApproved(other);
      answer.complete(testUser);
      await refreshing;

      expect((state() as SessionSignedIn).user, same(other));
    });

    test('uscito nel frattempo: il risultato non si applica', () async {
      await signIn();
      final answer = Completer<JellyfinUser>();
      when(() => auth.currentUser()).thenAnswer((_) => answer.future);
      when(() => auth.logout()).thenAnswer((_) async => 'u1');

      final refreshing = controller().refreshUser();
      await controller().logout();
      answer.complete(testUser);
      await refreshing;

      expect(state(), isA<SessionSignedOut>());
    });

    test('utente invariato: nessun nuovo stato', () async {
      await signIn();
      final before = state();
      when(() => auth.currentUser()).thenAnswer((_) async => JellyfinUser(
          id: admin.id, name: admin.name, isAdministrator: true));

      await controller().refreshUser();

      expect(state(), same(before));
      verifyNever(() => auth.updateActiveProfile(any()));
    });

    test('più richieste insieme: una sola lettura, poi di nuovo', () async {
      await signIn();
      final answer = Completer<JellyfinUser>();
      when(() => auth.currentUser()).thenAnswer((_) => answer.future);

      final first = controller().refreshUser();
      final second = controller().refreshUser();
      expect(second, same(first));
      answer.complete(testUser);
      await Future.wait([first, second]);

      verify(() => auth.currentUser()).called(1);
      expect((state() as SessionSignedIn).user.isAdministrator, isFalse);

      when(() => auth.currentUser()).thenAnswer((_) async => admin);
      await controller().refreshUser();
      verify(() => auth.currentUser()).called(1);
      expect((state() as SessionSignedIn).user.isAdministrator, isTrue);
    });
  });
}
```

In `test/app/router_test.dart` aggiungi:

```dart
  test('più profili: "Chi guarda?", con il login per aggiungerne uno', () {
    expect(sessionRedirect(const SessionChoosingProfile(), '/home'),
        '/profiles');
    expect(sessionRedirect(const SessionChoosingProfile(), '/profiles'),
        isNull);
    expect(sessionRedirect(const SessionSignedOut(adding: true), '/profiles'),
        '/login');
    // Scelto un profilo si va alla Home.
    expect(sessionRedirect(signedIn, '/profiles'), '/home');
  });
```

- [ ] **Step 4: i test non compilano**

Run: `flutter test test/features/auth test/app/router_test.dart`
Expected: errori di compilazione (`profiles_state.dart`, `ChooseProfile`, `SessionChoosingProfile`, i metodi nuovi non esistono).

- [ ] **Step 5: lo stato dei profili e il servizio**

Crea `lib/features/auth/profiles_state.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/profile_store.dart';

/// I profili del PC e quello attivo, per l'interfaccia e le preferenze (spec
/// K §9). Li aggiorna `SessionController` a ogni cambio: chi li legge non
/// crea il controller della sessione.
class ProfilesState {
  const ProfilesState({this.book = const ProfileBook(), this.activeUserId});

  final ProfileBook book;

  /// Il profilo aperto; `null` in "Chi guarda?" e nell'accesso.
  final String? activeUserId;

  /// Il profilo di cui valgono le preferenze (spec K §9.6): quello aperto,
  /// altrimenti l'ultimo usato (la lingua di "Chi guarda?", spec K §9.4).
  String? get preferenceUserId => activeUserId ?? book.lastUserId;
}

class ProfilesController extends Notifier<ProfilesState> {
  @override
  ProfilesState build() => const ProfilesState();

  void set(ProfilesState next) => state = next;
}

final profilesProvider =
    NotifierProvider<ProfilesController, ProfilesState>(ProfilesController.new);
```

Riscrivi `lib/features/auth/auth_service.dart`:

```dart
import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/auth_api.dart';
import '../../core/jellyfin/auth_models.dart';
import '../../core/jellyfin/jellyfin_http.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/storage/profile_store.dart';

final _log = Logger('auth');

sealed class RestoreResult {
  const RestoreResult();
}

final class RestoredSession extends RestoreResult {
  const RestoredSession(this.user);
  final JellyfinUser user;
}

final class NoStoredSession extends RestoreResult {
  const NoStoredSession();
}

/// Il server ha rifiutato il token del profilo [userId] (401).
final class StoredSessionExpired extends RestoreResult {
  const StoredSessionExpired(this.userId);
  final String userId;
}

final class RestoreServerUnreachable extends RestoreResult {
  const RestoreServerUnreachable();
}

/// Più profili salvati: si sceglie in "Chi guarda?" (spec K §9.3).
final class ChooseProfile extends RestoreResult {
  const ChooseProfile();
}

/// Profili, accesso e uscita (spec K §9). Nessuna dipendenza da Flutter.
class AuthService {
  AuthService({
    required JellyfinHttp http,
    required AuthApi api,
    required ProfileStore store,
    AuthApi Function(JellyfinHttp http)? apiFor,
    String Function()? newDeviceId,
  })  : _http = http,
        _api = api,
        _store = store,
        _apiFor = apiFor ?? AuthApi.new,
        _newDeviceId = newDeviceId ?? (() => const Uuid().v4());

  final JellyfinHttp _http;
  final AuthApi _api;
  final ProfileStore _store;

  /// Le chiamate con le credenziali di un profilo non attivo.
  final AuthApi Function(JellyfinHttp http) _apiFor;
  final String Function() _newDeviceId;

  ProfileBook _book = const ProfileBook();
  String? _activeUserId;

  /// I profili come li conosce il servizio: letti da `restore`, aggiornati a
  /// ogni modifica.
  ProfileBook get book => _book;

  /// Il profilo aperto; `null` in "Chi guarda?" e nell'accesso.
  String? get activeUserId => _activeUserId;

  Future<RestoreResult> restore() async {
    _deactivate();
    _book = await _store.read();
    return switch (_book.profiles.length) {
      0 => const NoStoredSession(),
      1 => await openProfile(_book.profiles.single.userId),
      _ => const ChooseProfile(),
    };
  }

  /// Apre il profilo [userId] (spec K §9.4): le sue credenziali nel client,
  /// poi `/Users/Me`. Riuscito: nome e immagine aggiornati, ultimo usato.
  /// 401: il profilo è scaduto. Altri errori: server irraggiungibile.
  Future<RestoreResult> openProfile(String userId) async {
    final profile = _book.byId(userId);
    if (profile == null) {
      return _book.isEmpty ? const NoStoredSession() : const ChooseProfile();
    }
    _http.setCredentials(
        token: profile.accessToken, deviceId: profile.deviceId);
    try {
      final user = await _api.getMe();
      _activeUserId = profile.userId;
      await _save(_book
          .upsert(profile.copyWith(
            name: user.name,
            imageTag: user.primaryImageTag,
            lastUsedAt: clock.now(),
            expired: false,
          ))
          .withLast(profile.userId));
      return RestoredSession(user);
    } on UnauthorizedException {
      _deactivate();
      await _save(_book.upsert(profile.copyWith(expired: true)));
      return StoredSessionExpired(profile.userId);
    } on ApiException {
      _deactivate();
      return const RestoreServerUnreachable();
    }
  }

  /// L'utente della sessione riletto dal server (`/Users/Me`), per esempio
  /// dopo un 403 di una chiamata da admin (spec J §12). Lancia
  /// [ApiException]. Durante un riavvio di Jellyfin la pagina Amministrazione
  /// la chiama ancora: i 502/503/504 vanno nel log come info.
  Future<JellyfinUser> currentUser() =>
      _api.getMe(quietStatuses: restartGatewayStatuses);

  /// Prepara un accesso (spec K §9.2): nessun token, il DeviceId del profilo
  /// [userId] se rifà l'accesso, altrimenti uno nuovo.
  void prepareLogin({String? userId}) {
    _activeUserId = null;
    final existing = userId == null ? null : _book.byId(userId);
    _http.setCredentials(
        token: null, deviceId: existing?.deviceId ?? _newDeviceId());
  }

  /// Lancia [ApiException], o [ProfileLimitException] per un sesto profilo.
  Future<JellyfinUser> loginWithPassword(
      String username, String password) async {
    final result = await _api.authenticateByName(username.trim(), password);
    await _adopt(result);
    return result.user;
  }

  Future<JellyfinUser> completeQuickConnect(String secret) async {
    final result = await _api.authenticateWithQuickConnect(secret);
    await _adopt(result);
    return result.user;
  }

  /// Esce dal profilo aperto (spec K §9.5): annulla il token e toglie il
  /// profilo dal PC. Dà l'id del profilo tolto (`null` senza profilo aperto).
  Future<String?> logout() async {
    final userId = _activeUserId;
    if (userId == null) {
      _deactivate();
      return null;
    }
    try {
      await _api.logout();
    } on ApiException catch (error) {
      // Il token resta solo sul server: qui si dimentica comunque.
      _log.info('token non annullato: ${error.runtimeType}');
    }
    _deactivate();
    await _save(_book.remove(userId));
    return userId;
  }

  /// Toglie il profilo [userId] dal PC (spec K §9.4), con il suo token
  /// annullato sul server (con le sue credenziali; gli errori si ignorano).
  Future<void> removeProfile(String userId) async {
    final active = _activeUserId;
    if (active != null && jellyfinIdKey(active) == jellyfinIdKey(userId)) {
      await logout();
      return;
    }
    final profile = _book.byId(userId);
    if (profile == null) return;
    await _revoke(profile.accessToken, profile.deviceId);
    await _save(_book.remove(userId));
  }

  /// Cambio di profilo (spec K §9.7): le credenziali spariscono dal client;
  /// il token resta valido e salvato.
  void deactivate() => _deactivate();

  /// Un 401 durante la sessione: il profilo aperto è scaduto.
  Future<void> markActiveExpired() async {
    final userId = _activeUserId;
    _deactivate();
    final profile = userId == null ? null : _book.byId(userId);
    if (profile != null) {
      await _save(_book.upsert(profile.copyWith(expired: true)));
    }
  }

  /// L'utente riletto (spec J §12): nome e immagine nel profilo aperto, solo
  /// se cambiano.
  Future<void> updateActiveProfile(JellyfinUser user) async {
    final active = _activeUserId;
    final profile = active == null ? null : _book.byId(active);
    if (profile == null ||
        jellyfinIdKey(profile.userId) != jellyfinIdKey(user.id)) {
      return;
    }
    if (profile.name == user.name && profile.imageTag == user.primaryImageTag) {
      return;
    }
    await _save(_book.upsert(
        profile.copyWith(name: user.name, imageTag: user.primaryImageTag)));
  }

  /// Un accesso riuscito (spec K §9.2): il profilo prende il token e il
  /// DeviceId con cui l'ha ottenuto. Lo stesso utente già salvato non fa un
  /// doppione, e il suo token vecchio si annulla.
  Future<void> _adopt(AuthResult result) async {
    final user = result.user;
    final deviceId = _http.deviceId;
    final existing = _book.byId(user.id);
    if (existing == null && _book.isFull) {
      await _revoke(result.accessToken, deviceId);
      throw const ProfileLimitException();
    }
    if (existing != null && existing.accessToken != result.accessToken) {
      await _revoke(existing.accessToken, existing.deviceId);
    }
    _http.setCredentials(token: result.accessToken, deviceId: deviceId);
    _activeUserId = user.id;
    await _save(_book
        .upsert(StoredProfile(
          userId: user.id,
          name: user.name,
          accessToken: result.accessToken,
          deviceId: deviceId,
          imageTag: user.primaryImageTag,
          lastUsedAt: clock.now(),
        ))
        .withLast(user.id));
  }

  /// Annulla un token sul server con le sue credenziali; gli errori si
  /// ignorano (il token resta solo lì).
  Future<void> _revoke(String token, String deviceId) async {
    try {
      await _apiFor(_http.withCredentials(token: token, deviceId: deviceId))
          .logout();
    } on ApiException catch (error) {
      _log.info('token non annullato: ${error.runtimeType}');
    }
  }

  void _deactivate() {
    _http.setCredentials(token: null, deviceId: null);
    _activeUserId = null;
  }

  Future<void> _save(ProfileBook book) async {
    _book = book;
    await _store.write(book);
  }
}
```

In `lib/app/providers.dart`:
- togli `sessionStoreProvider` e l'import di `session_store.dart`;
- aggiungi l'import di `../core/storage/profile_store.dart`;
- prima di `jellyfinHttpProvider`:

```dart
/// I profili salvati (spec K §9.1). Il DeviceId dell'installazione è quello
/// della sessione di prima, che la migrazione porta nel primo profilo.
final profileStoreProvider = Provider<ProfileStore>((ref) {
  final devInstance = devProfile();
  return SecureProfileStore(
    key: profilesKeyFor(devInstance),
    legacyKey: sessionKeyFor(devInstance),
    legacyDeviceId: ref.watch(clientInfoProvider).deviceId,
  );
});
```

- in `authServiceProvider`, `store: ref.watch(profileStoreProvider),`.

- [ ] **Step 6: il controller e il router**

Riscrivi `lib/features/auth/session_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/auth_models.dart';
import 'auth_service.dart';
import 'profiles_state.dart';

final _log = Logger('session');

sealed class SessionState {
  const SessionState();
}

/// Ripristino della sessione in corso (schermata di avvio).
final class SessionStarting extends SessionState {
  const SessionStarting();
}

/// Schermata di accesso (spec K §9.3).
final class SessionSignedOut extends SessionState {
  const SessionSignedOut(
      {this.expired = false, this.reloginUserId, this.adding = false});

  /// `true` se il token del profilo non vale più: l'avviso "Sessione scaduta".
  final bool expired;

  /// Il profilo che rifà l'accesso ("Accedi di nuovo", spec K §9.4): il suo
  /// nome già scritto e il suo DeviceId.
  final String? reloginUserId;

  /// Si aggiunge un profilo (spec K §9.5).
  final bool adding;
}

final class SessionUnreachable extends SessionState {
  const SessionUnreachable();
}

/// "Chi guarda?" (spec K §9.3): più profili salvati, nessuno aperto.
final class SessionChoosingProfile extends SessionState {
  const SessionChoosingProfile();
}

final class SessionSignedIn extends SessionState {
  const SessionSignedIn(this.user);
  final JellyfinUser user;
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final http = ref.watch(jellyfinHttpProvider);
    http.onUnauthorized = _onUnauthorized;
    ref.onDispose(() => http.onUnauthorized = null);
    return const SessionStarting();
  }

  AuthService get _auth => ref.read(authServiceProvider);

  Future<void> restore() async {
    try {
      _apply(_stateFor(await _auth.restore()));
    } on Object {
      // Difesa in profondità: nessun errore imprevisto deve bloccare l'avvio
      // sulla schermata di splash.
      _apply(const SessionUnreachable());
    }
  }

  /// Apre un profilo da "Chi guarda?" (spec K §9.4). Un errore imprevisto
  /// vale come server irraggiungibile.
  Future<void> openProfile(String userId) async {
    try {
      _apply(_stateFor(await _auth.openProfile(userId)));
    } on Object {
      _apply(const SessionUnreachable());
    }
  }

  /// Lancia [ApiException] o `ProfileLimitException`: la UI mostra il
  /// messaggio.
  Future<void> loginWithPassword(String username, String password) async {
    final user = await _auth.loginWithPassword(username, password);
    _apply(SessionSignedIn(user));
  }

  void quickConnectApproved(JellyfinUser user) => _apply(SessionSignedIn(user));

  /// La schermata di accesso si apre (spec K §9.2): il client prende il
  /// DeviceId del profilo che rifà l'accesso, o uno nuovo. Quick Connect lo
  /// usa già per la richiesta del codice.
  void prepareLogin() {
    final current = state;
    _auth.prepareLogin(
        userId: current is SessionSignedOut ? current.reloginUserId : null);
  }

  /// Cambio di profilo (spec K §9.7): le credenziali spariscono, il token
  /// resta salvato, e tutto quello che dipende dall'utente si azzera come
  /// all'uscita. Chi chiama esce prima dal watch party.
  void switchProfile() {
    _auth.deactivate();
    _apply(_afterLeaving());
  }

  /// "Aggiungi profilo" (spec K §9.5): come un cambio, poi l'accesso.
  void addProfile() {
    _auth.deactivate();
    _apply(const SessionSignedOut(adding: true));
  }

  /// "Accedi di nuovo" su un profilo scaduto (spec K §9.4).
  void relogin(String userId) {
    _auth.deactivate();
    _apply(SessionSignedOut(expired: true, reloginUserId: userId));
  }

  /// "Annulla" nell'accesso: di nuovo "Chi guarda?" (spec K §9.3).
  void cancelLogin() => _apply(_afterLeaving());

  /// Un'uscita in corso: il 401 della sua richiesta (token già scaduto) non
  /// apre l'accesso del profilo che si sta togliendo.
  bool _leaving = false;

  /// "Esci" (spec K §9.5): il profilo aperto si toglie dal PC.
  Future<void> logout() async {
    _leaving = true;
    try {
      await _auth.logout();
    } finally {
      _leaving = false;
    }
    _apply(_afterLeaving());
  }

  /// "Rimuovi" in "Gestisci profili" (spec K §9.4).
  Future<void> removeProfile(String userId) async {
    _leaving = true;
    try {
      await _auth.removeProfile(userId);
    } finally {
      _leaving = false;
    }
    _apply(_afterLeaving());
  }

  /// La rilettura dell'utente in corso, se c'è.
  Future<void>? _refreshing;

  /// Rilegge l'utente (spec J §12): per esempio i permessi da admin dopo un
  /// 403. Senza sessione non fa nulla. Chi la chiede mentre una è in corso
  /// riceve la stessa (più schede che prendono un 403 insieme fanno una sola
  /// lettura).
  Future<void> refreshUser() =>
      _refreshing ??= _refreshUser().whenComplete(() => _refreshing = null);

  /// Un errore lascia la sessione com'è (un 401 passa già da
  /// [_onUnauthorized]). Il risultato vale solo se la sessione è ancora
  /// quella dello stesso utente (un'uscita o un altro accesso, nel
  /// frattempo, lo scartano) e solo se qualcosa è cambiato: senza un nuovo
  /// stato il router e la shell non si ricostruiscono. Il profilo prende il
  /// nome e l'immagine nuovi.
  Future<void> _refreshUser() async {
    final before = state;
    if (before is! SessionSignedIn) return;
    try {
      final user = await _auth.currentUser();
      final now = state;
      if (now is! SessionSignedIn || now.user.id != before.user.id) return;
      if (now.user == user) return;
      _apply(SessionSignedIn(user));
      await _updateProfile(user);
    } on ApiException {
      // La sessione resta quella di prima.
    }
  }

  Future<void> _updateProfile(JellyfinUser user) async {
    try {
      await _auth.updateActiveProfile(user);
      _publishProfiles();
    } on Object catch (error) {
      _log.warning('profilo non aggiornato: ${error.runtimeType}');
    }
  }

  /// Un 401 durante la sessione: il profilo è scaduto e rifà l'accesso.
  void _onUnauthorized() {
    final current = state;
    if (current is! SessionSignedIn || _leaving) return;
    unawaited(_auth.markActiveExpired().then((_) => _publishProfiles(),
        onError: (Object error) =>
            _log.warning('profilo non segnato: ${error.runtimeType}')));
    _apply(SessionSignedOut(expired: true, reloginUserId: current.user.id));
  }

  /// Dove si va lasciando un profilo: "Chi guarda?" se ne restano,
  /// altrimenti l'accesso.
  SessionState _afterLeaving() => _auth.book.isEmpty
      ? const SessionSignedOut()
      : const SessionChoosingProfile();

  SessionState _stateFor(RestoreResult result) => switch (result) {
        RestoredSession(:final user) => SessionSignedIn(user),
        NoStoredSession() => const SessionSignedOut(),
        StoredSessionExpired(:final userId) =>
          SessionSignedOut(expired: true, reloginUserId: userId),
        RestoreServerUnreachable() => const SessionUnreachable(),
        ChooseProfile() => const SessionChoosingProfile(),
      };

  void _apply(SessionState next) {
    state = next;
    _publishProfiles();
  }

  void _publishProfiles() {
    if (!ref.mounted) return;
    ref.read(profilesProvider.notifier).set(ProfilesState(
        book: _auth.book, activeUserId: _auth.activeUserId));
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
```

In `lib/app/router.dart`:

```dart
const _entryRoutes = {'/splash', '/login', '/unreachable', '/profiles'};
```

e nello `switch` di `sessionRedirect`, dopo `SessionUnreachable() => goTo('/unreachable'),`:

```dart
    SessionChoosingProfile() => goTo('/profiles'),
```

La rotta `/profiles` si aggiunge nel Task 6, con la schermata: fino ad allora il router non ci porta mai, perché nessuno stato `SessionChoosingProfile` nasce senza almeno due profili.

- [ ] **Step 7: il fake della sessione**

Riscrivi `test/support/fake_session_controller.dart`:

```dart
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

class FakeSessionController extends SessionController {
  FakeSessionController(this.initial, {this.loginError});

  final SessionState initial;
  final Object? loginError;

  int restoreCalls = 0;
  int logoutCalls = 0;
  final loginAttempts = <(String, String)>[];
  JellyfinUser? approvedUser;
  int refreshUserCalls = 0;

  /// L'utente che [refreshUser] mette nella sessione; `null`: la sessione
  /// resta com'è.
  JellyfinUser? refreshedUser;

  int prepareLoginCalls = 0;
  int switchCalls = 0;
  int addProfileCalls = 0;
  int cancelLoginCalls = 0;
  final openedProfiles = <String>[];
  final reloginProfiles = <String>[];
  final removedProfiles = <String>[];

  @override
  SessionState build() => initial;

  /// Cambia lo stato della sessione, come un login o un logout.
  void set(SessionState next) => state = next;

  @override
  Future<void> restore() async {
    restoreCalls++;
  }

  @override
  Future<void> openProfile(String userId) async => openedProfiles.add(userId);

  @override
  Future<void> loginWithPassword(String username, String password) async {
    loginAttempts.add((username, password));
    final error = loginError;
    if (error != null) throw error;
    state = SessionSignedIn(JellyfinUser(id: 'u1', name: username));
  }

  @override
  void quickConnectApproved(JellyfinUser user) {
    approvedUser = user;
    state = SessionSignedIn(user);
  }

  @override
  void prepareLogin() => prepareLoginCalls++;

  @override
  void switchProfile() {
    switchCalls++;
    state = const SessionChoosingProfile();
  }

  @override
  void addProfile() {
    addProfileCalls++;
    state = const SessionSignedOut(adding: true);
  }

  @override
  void relogin(String userId) {
    reloginProfiles.add(userId);
    state = SessionSignedOut(expired: true, reloginUserId: userId);
  }

  @override
  void cancelLogin() {
    cancelLoginCalls++;
    state = const SessionChoosingProfile();
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const SessionSignedOut();
  }

  @override
  Future<void> removeProfile(String userId) async =>
      removedProfiles.add(userId);

  @override
  Future<void> refreshUser() async {
    refreshUserCalls++;
    final user = refreshedUser;
    if (user != null) state = SessionSignedIn(user);
  }
}
```

- [ ] **Step 8: i test passano**

Run: `flutter test test/features/auth test/app/router_test.dart test/core`
Expected: PASS. Poi la suite intera: altri test che usavano `StoredSessionExpired()` senza argomenti, `NoStoredSession` o `MemorySessionStore` vanno adattati in modo minimo (cerca con `Select-String`).

- [ ] **Step 9: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): keep several profiles in the session"
```

### Task 5: preferenze del profilo

**Files:**
- Create: `lib/features/profiles/profile_preferences.dart`
- Modify: `lib/features/settings/locale_controller.dart`
- Modify: `lib/features/watch_party/party_mode_preference.dart`
- Modify: `lib/features/discord/discord_settings.dart`
- Modify: `lib/features/player/player_settings.dart`
- Modify: `lib/features/auth/session_controller.dart`
- Create: `test/features/profiles/profile_preferences_test.dart`
- Modify: `test/features/auth/session_controller_test.dart`

- [ ] **Step 1: i test**

Crea `test/features/profiles/profile_preferences_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/core/syncplay/party_mode.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/discord/discord_settings.dart';
import 'package:wonderflix/features/player/player_settings.dart';
import 'package:wonderflix/features/profiles/profile_preferences.dart';
import 'package:wonderflix/features/settings/locale_controller.dart';
import 'package:wonderflix/features/watch_party/party_mode_preference.dart';

import '../../support/profile_fakes.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // Le preferenze di oggi, del PC: valgono come partenza per i profili.
      'locale': 'it',
      'player.subtitleScale': 1.0,
      'player.quality': 'mbps8',
      'discord.enabled': false,
    });
    prefs = await SharedPreferences.getInstance();
  });

  group('ProfilePreferences', () {
    test('senza profilo: le chiavi del PC', () async {
      final own = ProfilePreferences(prefs, null);
      expect(own.getString('locale'), 'it');
      await own.setString('locale', 'en');
      expect(prefs.getString('locale'), 'en');
      await own.clearString('locale');
      expect(prefs.containsKey('locale'), isFalse);
    });

    test('con un profilo: la sua chiave, altrimenti quella del PC', () async {
      final mario = ProfilePreferences(prefs, 'AB-CD');
      expect(mario.getString('locale'), 'it');
      await mario.setString('locale', 'en');
      expect(prefs.getString('profile.abcd.locale'), 'en');
      expect(prefs.getString('locale'), 'it');
      expect(mario.getString('locale'), 'en');
      expect(mario.getDouble('player.subtitleScale'), 1.0);
      await mario.setBool('discord.enabled', true);
      expect(mario.getBool('discord.enabled'), isTrue);
      expect(prefs.getBool('discord.enabled'), isFalse);
    });

    test('clearString in un profilo: vuoto, non la chiave del PC', () async {
      final mario = ProfilePreferences(prefs, 'u1');
      await mario.clearString('locale');
      expect(mario.getString('locale'), '');
    });

    test('removeProfile cancella solo le chiavi di quel profilo', () async {
      await ProfilePreferences(prefs, 'u1').setString('locale', 'en');
      await ProfilePreferences(prefs, 'u2').setString('locale', 'it');

      await ProfilePreferences.removeProfile(prefs, 'U-1');

      expect(prefs.containsKey('profile.u1.locale'), isFalse);
      expect(prefs.getString('profile.u2.locale'), 'it');
      expect(prefs.getString('locale'), 'it');
    });
  });

  group('i controller seguono il profilo', () {
    late FixedProfiles profiles;

    ProviderContainer container(ProfilesState initial) {
      profiles = FixedProfiles(initial);
      return ProviderContainer.test(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          profilesProvider.overrideWith(() => profiles),
        ],
        retry: (_, _) => null,
      );
    }

    final book = const ProfileBook()
        .upsert(testProfile(userId: 'u1'))
        .upsert(testProfile(userId: 'u2'))
        .withLast('u2');

    test('lingua: del profilo aperto, poi dell\'ultimo usato', () async {
      final c = container(ProfilesState(book: book, activeUserId: 'u1'));
      expect(c.read(localeProvider), const Locale('it'));
      await c.read(localeProvider.notifier).set(const Locale('en'));
      expect(c.read(localeProvider), const Locale('en'));

      // Nessun profilo aperto: vale l'ultimo usato (u2), che parte dal PC.
      profiles.set(ProfilesState(book: book));
      expect(c.read(localeProvider), const Locale('it'));

      // "Lingua di Windows" in un profilo non torna a quella del PC.
      profiles.set(ProfilesState(book: book, activeUserId: 'u1'));
      await c.read(localeProvider.notifier).set(null);
      expect(c.read(localeProvider), isNull);
    });

    test('player: sottotitoli del profilo, qualità del PC', () async {
      final c = container(ProfilesState(book: book, activeUserId: 'u1'));
      final controller = c.read(playerSettingsProvider.notifier);
      await controller.update(c.read(playerSettingsProvider)
          .copyWith(subtitleScale: 0.6, quality: StreamQuality.mbps4));

      expect(prefs.getDouble('profile.u1.player.subtitleScale'), 0.6);
      expect(prefs.getString('player.quality'), 'mbps4');
      expect(prefs.containsKey('profile.u1.player.quality'), isFalse);

      profiles.set(ProfilesState(book: book, activeUserId: 'u2'));
      final other = c.read(playerSettingsProvider);
      expect(other.subtitleScale, 1.0);
      expect(other.quality, StreamQuality.mbps4);
    });

    test('Discord e modalità del party: del profilo', () async {
      final c = container(ProfilesState(book: book, activeUserId: 'u1'));
      await c.read(discordSettingsProvider.notifier).update(
          c.read(discordSettingsProvider).copyWith(enabled: true));
      await c.read(partyModePreferenceProvider.notifier).set(PartyMode.private);

      profiles.set(ProfilesState(book: book, activeUserId: 'u2'));
      expect(c.read(discordSettingsProvider).enabled, isFalse);
      expect(c.read(partyModePreferenceProvider), PartyMode.public);

      profiles.set(ProfilesState(book: book, activeUserId: 'u1'));
      expect(c.read(discordSettingsProvider).enabled, isTrue);
      expect(c.read(partyModePreferenceProvider), PartyMode.private);
    });
  });
}
```

`FixedProfiles` eredita `set` da `ProfilesController`: il test cambia profilo così.

In `test/features/auth/session_controller_test.dart`:
- gli import `package:shared_preferences/shared_preferences.dart` e `package:wonderflix/features/profiles/profile_preferences.dart`;
- in `setUp`, prima di creare il container:

```dart
    SharedPreferences.setMockInitialValues({
      'profile.u1.locale': 'en',
      'profile.u2.locale': 'it',
    });
    prefs = await SharedPreferences.getInstance();
```

  (rendi `setUp` `async`, dichiara `late SharedPreferences prefs;`, e aggiungi `sharedPreferencesProvider.overrideWithValue(prefs)` agli override);
- nel gruppo `cambi di profilo` aggiungi:

```dart
    test('logout e rimozione cancellano le preferenze del profilo', () async {
      when(() => auth.logout()).thenAnswer((_) async => 'u1');
      when(() => auth.removeProfile('u2')).thenAnswer((_) async {});
      controller().quickConnectApproved(testUser);

      await controller().logout();
      expect(prefs.containsKey('profile.u1.locale'), isFalse);
      expect(prefs.getString('profile.u2.locale'), 'it');

      await controller().removeProfile('u2');
      expect(prefs.containsKey('profile.u2.locale'), isFalse);
    });
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/profiles test/features/auth`
Expected: errori di compilazione (`profile_preferences.dart` non esiste).

- [ ] **Step 3: il codice**

Crea `lib/features/profiles/profile_preferences.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/providers.dart';
import '../../core/jellyfin/json_fields.dart';
import '../auth/profiles_state.dart';

/// Prefisso delle preferenze di un profilo (spec K §9.6).
String profilePreferencesPrefix(String userId) =>
    'profile.${jellyfinIdKey(userId)}.';

/// Le preferenze del profilo (spec K §9.6): lingua, modalità del party,
/// Discord, dimensione dei sottotitoli, salto dell'intro, episodio
/// successivo. Si legge la chiave del profilo e, se manca, quella del PC (il
/// valore di partenza); si scrive sempre nel profilo. Senza profilo valgono
/// le chiavi del PC, come prima della 0.11.0.
class ProfilePreferences {
  const ProfilePreferences(this._prefs, this.userId);

  final SharedPreferences _prefs;

  /// Il profilo; `null`: le preferenze del PC.
  final String? userId;

  String _key(String key) {
    final id = userId;
    return id == null ? key : '${profilePreferencesPrefix(id)}$key';
  }

  String? getString(String key) =>
      (userId == null ? null : _prefs.getString(_key(key))) ??
      _prefs.getString(key);

  bool? getBool(String key) =>
      (userId == null ? null : _prefs.getBool(_key(key))) ??
      _prefs.getBool(key);

  double? getDouble(String key) =>
      (userId == null ? null : _prefs.getDouble(_key(key))) ??
      _prefs.getDouble(key);

  Future<bool> setString(String key, String value) =>
      _prefs.setString(_key(key), value);

  Future<bool> setBool(String key, bool value) =>
      _prefs.setBool(_key(key), value);

  Future<bool> setDouble(String key, double value) =>
      _prefs.setDouble(_key(key), value);

  /// Nessun valore. In un profilo resta una stringa vuota: senza valore
  /// varrebbe quella del PC.
  Future<bool> clearString(String key) =>
      userId == null ? _prefs.remove(key) : _prefs.setString(_key(key), '');

  /// Cancella le preferenze di [userId] (profilo tolto dal PC, spec K §9.6).
  static Future<void> removeProfile(
      SharedPreferences prefs, String userId) async {
    final prefix = profilePreferencesPrefix(userId);
    for (final key in prefs.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      await prefs.remove(key);
    }
  }
}

/// Le preferenze del profilo aperto, o dell'ultimo usato (spec K §9.6): chi le
/// guarda rilegge i valori a ogni cambio di profilo.
final profilePreferencesProvider = Provider<ProfilePreferences>((ref) =>
    ProfilePreferences(ref.watch(sharedPreferencesProvider),
        ref.watch(profilesProvider.select((p) => p.preferenceUserId))));
```

In `lib/features/settings/locale_controller.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profiles/profile_preferences.dart';

/// Lingua scelta dall'utente; `null` = lingua di Windows. È una preferenza
/// del profilo (spec K §9.6).
class LocaleController extends Notifier<Locale?> {
  static const _key = 'locale';

  @override
  Locale? build() {
    final code = ref.watch(profilePreferencesProvider).getString(_key);
    // Vuoto: la lingua di Windows scelta in un profilo.
    return code == null || code.isEmpty ? null : Locale(code);
  }

  Future<void> set(Locale? locale) async {
    final prefs = ref.read(profilePreferencesProvider);
    if (locale == null) {
      await prefs.clearString(_key);
    } else {
      await prefs.setString(_key, locale.languageCode);
    }
    state = locale;
  }
}

final localeProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);
```

In `lib/features/watch_party/party_mode_preference.dart`: al posto di `sharedPreferencesProvider` usa `profilePreferencesProvider` (import `../profiles/profile_preferences.dart`, togli quello di `providers.dart` se non serve più), con `getString`/`setString`; nel commento della classe aggiungi "Preferenza del profilo (spec K §9.6)."

In `lib/features/discord/discord_settings.dart`: lo stesso con `getBool`/`setBool`; il commento di `DiscordSettings` diventa "Preferenze della Rich Presence di Discord, del profilo (spec K §9.6)."

In `lib/features/player/player_settings.dart`, `PlayerSettingsController`:

```dart
  @override
  PlayerSettings build() {
    // Qualità e decodifica sono del PC; il resto è del profilo (spec K §9.6).
    final prefs = ref.watch(sharedPreferencesProvider);
    final profile = ref.watch(profilePreferencesProvider);
    const defaults = PlayerSettings();
    final scale = profile.getDouble(_subtitleScale);
    return PlayerSettings(
      quality: StreamQuality.values.asNameMap()[prefs.getString(_quality)] ??
          defaults.quality,
      hardwareDecoding:
          prefs.getBool(_hardwareDecoding) ?? defaults.hardwareDecoding,
      subtitleScale: scale != null && subtitleScaleOptions.contains(scale)
          ? scale
          : defaults.subtitleScale,
      autoSkipIntro: profile.getBool(_autoSkipIntro) ?? defaults.autoSkipIntro,
      autoplayNext: profile.getBool(_autoplayNext) ?? defaults.autoplayNext,
    );
  }

  Future<void> update(PlayerSettings next) async {
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    final profile = ref.read(profilePreferencesProvider);
    await Future.wait([
      prefs.setString(_quality, next.quality.name),
      prefs.setBool(_hardwareDecoding, next.hardwareDecoding),
      profile.setDouble(_subtitleScale, next.subtitleScale),
      profile.setBool(_autoSkipIntro, next.autoSkipIntro),
      profile.setBool(_autoplayNext, next.autoplayNext),
    ]);
  }
```

e il commento di `PlayerSettings`: "Preferenze del player: qualità e decodifica del PC, il resto del profilo (spec K §9.6)." (import `../profiles/profile_preferences.dart`).

In `lib/features/auth/session_controller.dart`:
- l'import `../profiles/profile_preferences.dart`;
- `logout` e `removeProfile`:

```dart
  /// "Esci" (spec K §9.5): il profilo aperto si toglie dal PC, con le sue
  /// preferenze.
  Future<void> logout() async {
    _leaving = true;
    final String? removed;
    try {
      removed = await _auth.logout();
    } finally {
      _leaving = false;
    }
    if (removed != null) await _forgetPreferences(removed);
    _apply(_afterLeaving());
  }

  /// "Rimuovi" in "Gestisci profili" (spec K §9.4), con le preferenze.
  Future<void> removeProfile(String userId) async {
    _leaving = true;
    try {
      await _auth.removeProfile(userId);
    } finally {
      _leaving = false;
    }
    await _forgetPreferences(userId);
    _apply(_afterLeaving());
  }

  Future<void> _forgetPreferences(String userId) async {
    try {
      await ProfilePreferences.removeProfile(
          ref.read(sharedPreferencesProvider), userId);
    } on Object catch (error) {
      _log.warning('preferenze del profilo non cancellate: '
          '${error.runtimeType}');
    }
  }
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/profiles test/features/auth test/features/settings test/features/discord test/features/player test/features/watch_party`
Expected: PASS (i test di oggi, senza profili, leggono e scrivono le chiavi del PC come prima).

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): keep personal preferences per profile"
```

## Gruppo C — interfaccia

### Task 6: "Chi guarda?"

**Files:**
- Create: `lib/ui/wf_confirm_dialog.dart`
- Modify: `lib/features/admin/admin_confirm_dialog.dart`
- Create: `lib/features/profiles/profiles_screen.dart`
- Modify: `lib/app/router.dart`
- Create: `test/features/profiles/profiles_screen_test.dart`

- [ ] **Step 1: i test**

Crea `test/features/profiles/profiles_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/profiles/profiles_screen.dart';

import '../../support/fake_session_controller.dart';
import '../../support/profile_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeSessionController session;

  Future<void> pumpProfiles(WidgetTester tester, List<StoredProfile> list) async {
    session = FakeSessionController(const SessionChoosingProfile());
    final book = list.fold(const ProfileBook(), (b, p) => b.upsert(p));
    await pumpApp(tester, const ProfilesScreen(), overrides: [
      sessionControllerProvider.overrideWith(() => session),
      profilesProvider
          .overrideWith(() => FixedProfiles(ProfilesState(book: book))),
    ]);
    await tester.pump();
  }

  final mario = testProfile(userId: 'u1', name: 'Mario');
  final luigi = testProfile(userId: 'u2', name: 'Luigi');

  testWidgets('titolo, profili e "Aggiungi profilo"', (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    expect(find.text('Chi guarda?'), findsOneWidget);
    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Luigi'), findsOneWidget);
    expect(find.text('Aggiungi profilo'), findsOneWidget);
    expect(find.text('Gestisci profili'), findsOneWidget);
  });

  testWidgets('clic su un profilo: lo apre', (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    await tester.tap(find.text('Luigi'));
    await tester.pump();
    expect(session.openedProfiles, ['u2']);
  });

  testWidgets('profilo scaduto: "Accedi di nuovo", e il clic rifà l\'accesso',
      (tester) async {
    await pumpProfiles(
        tester, [mario, testProfile(userId: 'u2', name: 'Luigi', expired: true)]);
    expect(find.text('Accedi di nuovo'), findsOneWidget);
    await tester.tap(find.text('Luigi'));
    await tester.pump();
    expect(session.reloginProfiles, ['u2']);
    expect(session.openedProfiles, isEmpty);
  });

  testWidgets('"Aggiungi profilo": il login per un profilo nuovo',
      (tester) async {
    await pumpProfiles(tester, [mario]);
    await tester.tap(find.text('Aggiungi profilo'));
    await tester.pump();
    expect(session.addProfileCalls, 1);
  });

  testWidgets('con 5 profili "Aggiungi profilo" non c\'è', (tester) async {
    await pumpProfiles(tester, [
      for (var i = 1; i <= ProfileBook.maxProfiles; i++)
        testProfile(userId: 'u$i', name: 'P$i'),
    ]);
    expect(find.text('Aggiungi profilo'), findsNothing);
  });

  testWidgets('"Gestisci profili": Rimuovi con conferma', (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    await tester.tap(find.text('Gestisci profili'));
    await tester.pump();
    expect(find.text('Fine'), findsOneWidget);
    // In modifica il clic non apre il profilo.
    await tester.tap(find.text('Mario'));
    await tester.pump();
    expect(session.openedProfiles, isEmpty);

    await tester.tap(find.byKey(const ValueKey('profile-remove-u2')));
    await tester.pumpAndSettle();
    expect(find.text('Rimuovere Luigi da questo PC?'), findsOneWidget);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(session.removedProfiles, isEmpty);

    await tester.tap(find.byKey(const ValueKey('profile-remove-u2')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Rimuovi'));
    await tester.pumpAndSettle();
    expect(session.removedProfiles, ['u2']);
  });

  testWidgets('tastiera: Tab porta al primo profilo, Invio lo apre',
      (tester) async {
    await pumpProfiles(tester, [mario, luigi]);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(session.openedProfiles, ['u1']);
  });
}
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/profiles/profiles_screen_test.dart`
Expected: errore di compilazione (`profiles_screen.dart` non esiste).

- [ ] **Step 3: la conferma, la schermata, la rotta**

Crea `lib/ui/wf_confirm_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import 'wf_dialog.dart';

/// Una conferma: titolo, messaggio, [cancelLabel] e il pulsante
/// [confirmLabel]. `true` solo con la conferma.
Future<bool> showWfConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final confirmed = await showWfDialog<bool>(
    context,
    semanticLabel: title,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Text(message),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelLabel),
            ),
            const SizedBox(width: 12),
            FilledButton(
              // Il tema fa i FilledButton larghi all'infinito: in una Row
              // servono larghi quanto il testo.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
```

Riscrivi `lib/features/admin/admin_confirm_dialog.dart` come uso della conferma generica:

```dart
import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_confirm_dialog.dart';

/// Una conferma della pagina Amministrazione: titolo, messaggio, "Annulla"
/// e il pulsante [confirmLabel]. `true` solo con la conferma.
Future<bool> showAdminConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) =>
    showWfConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: AppLocalizations.of(context).adminCancel,
    );
```

Crea `lib/features/profiles/profiles_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/storage/profile_store.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_confirm_dialog.dart';
import '../auth/profiles_state.dart';
import '../auth/session_controller.dart';

/// Diametro dell'avatar di un profilo in "Chi guarda?" (spec K §9.4).
const profileAvatarSize = 120.0;

/// Larghezza di una card di "Chi guarda?".
const _cardWidth = 150.0;

/// Opacità dell'avatar di un profilo scaduto.
const _expiredOpacity = 0.45;

/// "Chi guarda?" (spec K §9.4): i profili del PC, "Aggiungi profilo" e
/// "Gestisci profili". La lingua è quella dell'ultimo profilo usato.
class ProfilesScreen extends ConsumerStatefulWidget {
  const ProfilesScreen({super.key});

  @override
  ConsumerState<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends ConsumerState<ProfilesScreen> {
  bool _managing = false;

  /// Il profilo che si sta aprendo: intanto gli altri clic non fanno niente.
  String? _opening;

  SessionController get _session =>
      ref.read(sessionControllerProvider.notifier);

  Future<void> _open(StoredProfile profile) async {
    if (_opening != null) return;
    if (profile.expired) {
      _session.relogin(profile.userId);
      return;
    }
    setState(() => _opening = profile.userId);
    try {
      await _session.openProfile(profile.userId);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _remove(StoredProfile profile) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showWfConfirmDialog(
      context,
      title: l.profilesRemoveTitle(profile.name),
      message: l.profilesRemoveBody,
      confirmLabel: l.profilesRemove,
      cancelLabel: l.profilesCancel,
    );
    if (!confirmed || !mounted) return;
    await _session.removeProfile(profile.userId);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final book = ref.watch(profilesProvider.select((p) => p.book));
    final idle = _opening == null;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/brand/logo.png', width: 200),
              const SizedBox(height: 32),
              Text(l.profilesTitle, style: WfText.display(48)),
              const SizedBox(height: 32),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  for (final profile in book.profiles)
                    _ProfileCard(
                      key: ValueKey('profile-${profile.userId}'),
                      profile: profile,
                      managing: _managing,
                      opening: _opening == profile.userId,
                      onOpen: idle && !_managing
                          ? () => unawaited(_open(profile))
                          : null,
                      onRemove: () => unawaited(_remove(profile)),
                    ),
                  if (!book.isFull && !_managing)
                    _AddProfileCard(onTap: idle ? _session.addProfile : null),
                ],
              ),
              const SizedBox(height: 32),
              if (!book.isEmpty)
                WfButton.secondary(
                  label: _managing ? l.profilesDone : l.profilesManage,
                  icon: _managing ? LucideIcons.check : LucideIcons.pencil,
                  onPressed: idle
                      ? () => setState(() => _managing = !_managing)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Un profilo: avatar (iniziale) e nome. Si apre con il clic o con Invio.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    super.key,
    required this.profile,
    required this.managing,
    required this.opening,
    required this.onOpen,
    required this.onRemove,
  });

  final StoredProfile profile;
  final bool managing;
  final bool opening;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: _cardWidth,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        focusColor: WfColors.gold.withValues(alpha: 0.18),
        hoverColor: WfColors.gold.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: profile.expired ? _expiredOpacity : 1,
                    child: _InitialAvatar(name: profile.name),
                  ),
                  if (opening)
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  if (managing)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        key: ValueKey('profile-remove-${profile.userId}'),
                        tooltip: l.profilesRemove,
                        style: IconButton.styleFrom(
                            backgroundColor: WfColors.surfaceHigh),
                        onPressed: onRemove,
                        icon: const Icon(LucideIcons.trash2,
                            color: WfColors.cream),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              if (profile.expired)
                Text(l.profilesSignInAgain,
                    style:
                        const TextStyle(color: WfColors.gold, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'iniziale del nome su un cerchio dorato (il piano 17c la sostituisce con
/// l'immagine dell'utente).
class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: profileAvatarSize / 2,
        backgroundColor: WfColors.gold,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(
                color: WfColors.bg,
                fontSize: profileAvatarSize * 0.4,
                fontWeight: FontWeight.w700)),
      );
}

/// "Aggiungi profilo": un cerchio con il più.
class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _cardWidth,
      child: InkWell(
        key: const ValueKey('profile-add'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        focusColor: WfColors.gold.withValues(alpha: 0.18),
        hoverColor: WfColors.gold.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: profileAvatarSize,
                height: profileAvatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: WfColors.border, width: 2),
                ),
                child: const Icon(LucideIcons.plus,
                    size: 40, color: WfColors.creamMuted),
              ),
              const SizedBox(height: 12),
              Text(AppLocalizations.of(context).profilesAdd,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WfColors.creamMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
```

In `lib/app/router.dart`:
- l'import `../features/profiles/profiles_screen.dart`;
- dopo la rotta `/unreachable`:

```dart
      GoRoute(
          path: '/profiles',
          pageBuilder: (context, state) =>
              entryPage(context, state, const ProfilesScreen())),
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/profiles test/features/admin`
Expected: PASS (i test della pagina Amministrazione usano la conferma come prima).

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): add the Who is watching screen"
```

### Task 7: accesso per un profilo nuovo o scaduto

**Files:**
- Modify: `lib/features/auth/login_screen.dart`
- Modify: `lib/features/auth/password_login_form.dart`
- Modify: `test/features/auth/login_screen_test.dart`

- [ ] **Step 1: i test**

In `test/features/auth/login_screen_test.dart`:
- gli import:

```dart
import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';

import '../../support/profile_fakes.dart';
```

- `pumpLogin` riceve anche i profili:

```dart
  Future<FakeSessionController> pumpLogin(
    WidgetTester tester, {
    SessionState initial = const SessionSignedOut(),
    Object? loginError,
    bool quickConnect = false,
    MotionLevel motion = MotionLevel.reduced,
    List<StoredProfile> profiles = const [],
  }) async {
    final fake = FakeSessionController(initial, loginError: loginError);
    final book = profiles.fold(const ProfileBook(), (b, p) => b.upsert(p));
    await pumpApp(tester, const LoginScreen(), motion: motion, overrides: [
      sessionControllerProvider.overrideWith(() => fake),
      quickConnectEnabledProvider.overrideWith((ref) async => quickConnect),
      profilesProvider
          .overrideWith(() => FixedProfiles(ProfilesState(book: book))),
    ]);
    await tester.pump();
    return fake;
  }
```

- in fondo a `main`:

```dart
  testWidgets('aprendo il login si prepara l\'accesso', (tester) async {
    final fake = await pumpLogin(tester);
    expect(fake.prepareLoginCalls, 1);
    // Senza profili: niente "Annulla".
    expect(find.byKey(const Key('login-cancel')), findsNothing);
  });

  testWidgets('aggiungere un profilo: "Annulla" torna a "Chi guarda?"',
      (tester) async {
    final fake = await pumpLogin(tester,
        initial: const SessionSignedOut(adding: true),
        profiles: [testProfile(userId: 'u1')]);
    await tester.tap(find.byKey(const Key('login-cancel')));
    await tester.pump();
    expect(fake.cancelLoginCalls, 1);
  });

  testWidgets('accedi di nuovo: nome già scritto, avviso, "Annulla"',
      (tester) async {
    await pumpLogin(tester,
        initial: const SessionSignedOut(expired: true, reloginUserId: 'u2'),
        profiles: [
          testProfile(userId: 'u1'),
          testProfile(userId: 'u2', name: 'Luigi', expired: true),
        ]);
    expect(find.text('Sessione scaduta, accedi di nuovo.'), findsOneWidget);
    final username = tester.widget<TextField>(
        find.byKey(const Key('login-username')));
    expect(username.controller!.text, 'Luigi');
    expect(find.byKey(const Key('login-cancel')), findsOneWidget);
  });

  testWidgets('accedi di nuovo con un solo profilo: niente "Annulla"',
      (tester) async {
    await pumpLogin(tester,
        initial: const SessionSignedOut(expired: true, reloginUserId: 'u1'),
        profiles: [testProfile(userId: 'u1', expired: true)]);
    expect(find.byKey(const Key('login-cancel')), findsNothing);
  });

  testWidgets('sesto profilo: "Massimo 5 profili"', (tester) async {
    await pumpLogin(tester, loginError: const ProfileLimitException());
    await tester.enterText(find.byKey(const Key('login-username')), 'toad');
    await tester.enterText(find.byKey(const Key('login-password')), 'x');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Massimo 5 profili'), findsOneWidget);
  });
```

- [ ] **Step 2: i test non passano**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: i test nuovi falliscono (nessuna chiamata a `prepareLogin`, nessun "Annulla", nome vuoto).

- [ ] **Step 3: il codice**

In `lib/features/auth/password_login_form.dart`:

```dart
class PasswordLoginForm extends ConsumerStatefulWidget {
  const PasswordLoginForm({super.key, this.initialUsername});

  /// Il nome già scritto ("Accedi di nuovo", spec K §9.3): il fuoco va alla
  /// password.
  final String? initialUsername;

  @override
  ConsumerState<PasswordLoginForm> createState() => _PasswordLoginFormState();
}

class _PasswordLoginFormState extends ConsumerState<PasswordLoginForm> {
  late final _username = TextEditingController(text: widget.initialUsername);
  final _password = TextEditingController();
```

e nei due `TextField`: `autofocus: widget.initialUsername == null,` per il nome e `autofocus: widget.initialUsername != null,` per la password.

Riscrivi `LoginScreen` in `lib/features/auth/login_screen.dart` come `ConsumerStatefulWidget`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/staggered_entrance.dart';
import 'auth_providers.dart';
import 'password_login_form.dart';
import 'profiles_state.dart';
import 'quick_connect_panel.dart';
import 'session_controller.dart';

/// Accesso (spec K §9.3): il primo, un profilo nuovo ("Aggiungi profilo") o
/// uno scaduto ("Accedi di nuovo", con il nome già scritto).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  @override
  void initState() {
    super.initState();
    // Prima dei figli: Quick Connect chiede il codice con il DeviceId del
    // profilo (spec K §9.2).
    ref.read(sessionControllerProvider.notifier).prepareLogin();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    final quickConnectAsync = ref.watch(quickConnectEnabledProvider);
    final book = ref.watch(profilesProvider.select((p) => p.book));
    final signedOut = session is SessionSignedOut ? session : null;
    final expired = signedOut?.expired ?? false;
    final reloginId = signedOut?.reloginUserId;
    final reloginName = reloginId == null ? null : book.byId(reloginId)?.name;
    // "Annulla" torna a "Chi guarda?": solo se c'è un altro profilo da
    // scegliere.
    final canCancel = ((signedOut?.adding ?? false) && !book.isEmpty) ||
        (reloginId != null && book.profiles.length > 1);
    final form = PasswordLoginForm(initialUsername: reloginName);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          // Il logo, poi il pannello (spec C §11.3).
          child: StaggerGroup(
            count: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StaggerItem(
                  index: 0,
                  child: Image.asset('assets/brand/logo.png', width: 280),
                ),
                const SizedBox(width: 56),
                StaggerItem(
                  index: 1,
                  child: Container(
                    width: 380,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: WfColors.surface,
                      border: Border.all(color: WfColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (expired) ...[
                          ErrorBanner(l.sessionExpired),
                          const SizedBox(height: 12),
                        ],
                        if (quickConnectAsync.isLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                            ),
                          )
                        else if (quickConnectAsync.value ?? false)
                          DefaultTabController(
                            length: 2,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TabBar(
                                  isScrollable: true,
                                  tabAlignment: TabAlignment.start,
                                  tabs: [
                                    Tab(text: l.loginTabPassword),
                                    Tab(text: l.loginTabQuickConnect),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 300,
                                  child: TabBarView(children: [
                                    form,
                                    const QuickConnectPanel(),
                                  ]),
                                ),
                              ],
                            ),
                          )
                        else
                          form,
                        if (canCancel) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            key: const Key('login-cancel'),
                            onPressed: ref
                                .read(sessionControllerProvider.notifier)
                                .cancelLogin,
                            child: Text(l.profilesCancel),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/auth`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): sign in for a new or expired profile"
```

### Task 8: Cambia profilo, menu e Impostazioni

**Files:**
- Create: `lib/features/profiles/profile_switch.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Create: `test/features/profiles/profile_switch_test.dart`
- Modify: `test/app/app_shell_test.dart`
- Modify: `test/features/settings/settings_test.dart`

- [ ] **Step 1: i test**

Crea `test/features/profiles/profile_switch_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/profiles/profile_switch.dart';
import 'package:wonderflix/features/watch_party/watch_party_session.dart';

import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

/// Un watch party fisso: [leave] aspetta [gate], se c'è.
class _Party extends WatchPartySession {
  _Party({required this.inGroup, this.gate});

  final bool inGroup;
  final Completer<void>? gate;
  int leaveCalls = 0;

  @override
  WatchPartyState build() => WatchPartyState(
      phase: inGroup ? WatchPartyPhase.inGroup : WatchPartyPhase.none);

  @override
  Future<void> leave() async {
    leaveCalls++;
    await gate?.future;
    state = const WatchPartyState();
  }
}

void main() {
  late FakeSessionController session;
  late _Party party;

  Future<void> pumpButton(WidgetTester tester,
      {bool inGroup = false, Completer<void>? gate, bool add = false}) async {
    session = FakeSessionController(const SessionSignedIn(testUser));
    party = _Party(inGroup: inGroup, gate: gate);
    await pumpApp(
      tester,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () =>
                unawaited(switchProfile(context, ref, addProfile: add)),
            child: const Text('vai'),
          ),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(() => session),
        watchPartySessionProvider.overrideWith(() => party),
      ],
    );
  }

  testWidgets('senza party: si cambia subito', (tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('vai'));
    await tester.pump();
    expect(session.switchCalls, 1);
    expect(party.leaveCalls, 0);
  });

  testWidgets('"Aggiungi profilo": lo stesso cambio, poi l\'accesso',
      (tester) async {
    await pumpButton(tester, add: true);
    await tester.tap(find.text('vai'));
    await tester.pump();
    expect(session.addProfileCalls, 1);
    expect(session.switchCalls, 0);
  });

  testWidgets('in un party: conferma, poi uscita e cambio', (tester) async {
    await pumpButton(tester, inGroup: true);
    await tester.tap(find.text('vai'));
    await tester.pumpAndSettle();
    expect(find.text('Uscirai dal watch party.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Cambia profilo'));
    await tester.pumpAndSettle();
    expect(party.leaveCalls, 1);
    expect(session.switchCalls, 1);
  });

  testWidgets('in un party, "Annulla": niente', (tester) async {
    await pumpButton(tester, inGroup: true);
    await tester.tap(find.text('vai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(party.leaveCalls, 0);
    expect(session.switchCalls, 0);
  });

  testWidgets('uscita lenta: dopo 3 s si cambia lo stesso', (tester) async {
    final gate = Completer<void>();
    await pumpButton(tester, inGroup: true, gate: gate);
    await tester.tap(find.text('vai'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cambia profilo'));
    await tester.pump();
    expect(session.switchCalls, 0);

    await tester.pump(partyLeaveTimeout);
    await tester.pump();
    expect(session.switchCalls, 1);
    gate.complete();
  });
}
```

`WatchPartySession` ha il costruttore senza argomenti e i suoi campi si inizializzano da soli: `_Party` ridefinisce solo `build` e `leave`.

In `test/app/app_shell_test.dart`, in fondo a `main` (gli import `profiles_state.dart`, `profile_store.dart` e `../support/profile_fakes.dart`):

```dart
  testWidgets('menu: Cambia profilo e Aggiungi profilo', (tester) async {
    final fake = FakeSessionController(const SessionSignedIn(testUser));
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        sessionControllerProvider.overrideWith(() => fake),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
      ],
    );

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Aggiungi profilo'), findsOneWidget);
    await tester.tap(find.text('Cambia profilo'));
    await tester.pumpAndSettle();
    expect(fake.switchCalls, 1);
  });

  testWidgets('menu con 5 profili: niente "Aggiungi profilo"', (tester) async {
    var book = const ProfileBook();
    for (var i = 1; i <= ProfileBook.maxProfiles; i++) {
      book = book.upsert(testProfile(userId: 'u$i'));
    }
    await pumpApp(
      tester,
      const AppShell(location: '/home', child: SizedBox()),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        watchPartyDirectoryProvider.overrideWith(FakeWatchPartyDirectory.new),
        syncPlayApiProvider.overrideWithValue(FakeSyncPlayApi()),
        watchPartyEventsProvider.overrideWithValue(const Stream.empty()),
        profilesProvider.overrideWith(() =>
            FixedProfiles(ProfilesState(book: book, activeUserId: 'u1'))),
      ],
    );

    await tester.tap(find.byKey(const Key('user-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Cambia profilo'), findsOneWidget);
    expect(find.text('Aggiungi profilo'), findsNothing);
  });
```

In `test/features/settings/settings_test.dart`, nel test `schermata: utente, lingua, versione, esci`:
- tra gli override, `watchPartyEventsProvider.overrideWithValue(const Stream.empty())` (import `package:wonderflix/features/watch_party/watch_party_providers.dart`): "Cambia profilo" legge il watch party, che senza override si collegherebbe agli eventi del server;
- prima del tap su "Esci":

```dart
    await tester.tap(find.text('Cambia profilo'));
    await tester.pump();
    expect(session.switchCalls, 1);
    // Il fake è passato a "Chi guarda?": di nuovo dentro, per provare Esci.
    session.set(const SessionSignedIn(testUser));
    await tester.pump();
```

- [ ] **Step 2: i test non compilano**

Run: `flutter test test/features/profiles/profile_switch_test.dart test/app/app_shell_test.dart test/features/settings/settings_test.dart`
Expected: errore di compilazione (`profile_switch.dart` non esiste).

- [ ] **Step 3: il codice**

Crea `lib/features/profiles/profile_switch.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_confirm_dialog.dart';
import '../auth/session_controller.dart';
import '../watch_party/watch_party_session.dart';

final _log = Logger('profiles');

/// Quanto si aspetta l'uscita dal watch party prima di cambiare profilo
/// comunque (spec K §9.7): il gruppo lo pulisce poi Jellyfin.
const partyLeaveTimeout = Duration(seconds: 3);

/// Cambia profilo, o ne aggiunge uno con [addProfile] (spec K §9.5, §9.7). In
/// un watch party chiede conferma ed esce dal gruppo: il token del profilo
/// non si annulla, quindi il party non si chiuderebbe da solo.
Future<void> switchProfile(BuildContext context, WidgetRef ref,
    {bool addProfile = false}) async {
  if (ref.read(watchPartySessionProvider).phase != WatchPartyPhase.none) {
    final l = AppLocalizations.of(context);
    final confirmed = await showWfConfirmDialog(
      context,
      title: l.profilesSwitch,
      message: l.profilesSwitchLeavesParty,
      confirmLabel: l.profilesSwitch,
      cancelLabel: l.profilesCancel,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(watchPartySessionProvider.notifier)
          .leave()
          .timeout(partyLeaveTimeout);
    } on TimeoutException {
      _log.info('uscita dal watch party lenta: si cambia profilo lo stesso');
    }
    if (!context.mounted) return;
  }
  final session = ref.read(sessionControllerProvider.notifier);
  if (addProfile) {
    session.addProfile();
  } else {
    session.switchProfile();
  }
}
```

In `lib/app/app_shell.dart`, `_UserMenu`:
- gli import `../features/auth/profiles_state.dart` e `../features/profiles/profile_switch.dart`;
- in `build`, dopo `final initial = …;`:

```dart
    final canAddProfile =
        !ref.watch(profilesProvider.select((p) => p.book.isFull));
```

- in `onSelected`, prima di `case 'logout':`:

```dart
          case 'switch':
            unawaited(switchProfile(context, ref));
          case 'add':
            unawaited(switchProfile(context, ref, addProfile: true));
```

- in `itemBuilder`, prima della voce `logout`:

```dart
        PopupMenuItem(
          value: 'switch',
          child: Row(
            children: [
              const Icon(LucideIcons.users, size: 18, color: WfColors.cream),
              const SizedBox(width: 12),
              Text(l.profilesSwitch),
            ],
          ),
        ),
        // Al massimo 5 profili (spec K §9.5).
        if (canAddProfile)
          PopupMenuItem(
            value: 'add',
            child: Row(
              children: [
                const Icon(LucideIcons.userPlus,
                    size: 18, color: WfColors.cream),
                const SizedBox(width: 12),
                Text(l.profilesAdd),
              ],
            ),
          ),
```

In `lib/features/settings/settings_screen.dart` (import `../profiles/profile_switch.dart`), nella sezione Account, al posto dell'`Align` con il pulsante Esci:

```dart
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  WfButton.secondary(
                    label: l.profilesSwitch,
                    icon: LucideIcons.users,
                    onPressed: () => unawaited(switchProfile(context, ref)),
                  ),
                  WfButton.secondary(
                    label: l.menuLogout,
                    icon: LucideIcons.logOut,
                    onPressed: () => unawaited(
                        ref.read(sessionControllerProvider.notifier).logout()),
                  ),
                ],
              ),
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/profiles test/app test/features/settings`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib test
git commit -m "feat(app): switch and add profiles from the menu and settings"
```

## Gruppo D — chiusura

### Task 9: allineamento della spec e build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-wonderflix-saghe-profili-design.md`

- [ ] **Step 1: la spec**

Nella spec:
- **Stato:** "approvato; piano 17a realizzato (`…17a-saghe.md`), piano 17b realizzato (`docs/superpowers/plans/2026-10-08-wonderflix-17b-profili.md`), piano 17c da scrivere".
- **§6:** i file veri di K2: `lib/core/storage/profile_store.dart` (`StoredProfile`, `ProfileBook`, `SecureProfileStore`, `ProfileLimitException`, `profilesKeyFor`), `lib/features/auth/profiles_state.dart`, `lib/features/profiles/profiles_screen.dart`, `profile_preferences.dart`, `profile_switch.dart`, `lib/ui/wf_confirm_dialog.dart`.
- **§9.1:** il profilo salva anche `expired` (resta attenuato dopo un riavvio); il formato e la tolleranza (profili senza id, token o DeviceId saltati; doppioni e oltre 5 scartati).
- **§9.2:** `JellyfinHttp.setCredentials` e `withCredentials`; il DeviceId dell'accesso lo prepara la schermata di accesso quando si apre (`prepareLogin`), e Quick Connect lo usa già per il codice; un sesto profilo è rifiutato da `AuthService` (`ProfileLimitException`, token appena ottenuto annullato).
- **§9.3:** niente `/login?add=1` e `/login?user=…`: la modalità sta in `SessionSignedOut(adding:, reloginUserId:, expired:)`; un 401 durante la sessione segna il profilo scaduto e apre l'accesso per quel profilo, con "Annulla" se ci sono altri profili.
- **§9.4:** in 17b l'avatar è l'iniziale; "Modifica immagine" arriva nel 17c.
- **§9.5:** in 17b Impostazioni → Account ha Cambia profilo ed Esci; avatar grande e "Cambia immagine" nel 17c.
- **§9.6:** la lingua "di Windows" in un profilo si salva come stringa vuota; senza profilo la chiave si toglie come prima. Le preferenze arrivano ai controller da `profilePreferencesProvider`, che segue `profilesProvider`.
- **§9.7:** la conferma usa `showWfConfirmDialog`; `partyLeaveTimeout` = 3 s.
- **§13:** i test di K2 che esistono davvero.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

- [ ] **Step 2: build**

Copia `config/wonderflix.json` dal checkout principale nel worktree (`config/`), se non c'è. Poi:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

Expected: `√ Built build\windows\x64\runner\Release\wonderflix.exe`. Non lanciare l'app.

- [ ] **Step 3: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add docs
git commit -m "docs: align the sagas and profiles spec with plan 17b"
```

### Task 10: prova a mano (orchestratore e utente)

L'utente, con la build del Task 9:
1. **Aggiornamento dalla 0.10.0** senza rifare l'accesso. La sessione di oggi diventa il primo profilo: si entra diretti, con il nome giusto nel menu.
2. **Aggiungere un secondo profilo** con password, poi un terzo con Quick Connect. Si entra con il profilo nuovo; nel menu c'è "Cambia profilo".
3. **Riavviare l'app:** compare "Chi guarda?" nella lingua dell'ultimo profilo usato.
4. **Preferenze:** cambiare la lingua o la dimensione dei sottotitoli in un profilo; nell'altro profilo restano quelle di prima.
5. **Cambio di profilo durante un watch party,** con la seconda istanza (`WONDERFLIX_PROFILE=b`) nel party: conferma, uscita dal gruppo e "Chi guarda?". L'altra istanza vede il membro uscire.
6. **Gestisci profili → Rimuovi** su un profilo: sparisce, e il suo token non vale più (nella scheda Sessioni dell'admin non compare più).
7. **Esci** dal menu: il profilo si toglie, e si va a "Chi guarda?" o all'accesso.
8. **Scheda Sessioni dell'admin:** due profili aperti in due momenti compaiono come due dispositivi diversi.

Con l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`).

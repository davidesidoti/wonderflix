# Revisione finale, fase 7: prima dell'app — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le schermate prima della Home (Chi guarda?, immagine del profilo, accesso, Quick Connect, server irraggiungibile, splash, aggiornamento) come dice la spec §9: testi per piattaforma, "Ciao", tre casi del server con la catena di lampade e il conto alla rovescia.

**Architecture:** Un provider nuovo `deviceKindProvider` (PC, browser, telefono, TV) per i testi che nominano il dispositivo. Il motivo dell'irraggiungibile nasce dall'eccezione che `AuthService.openProfile` riceve già (`ServerUnreachableException` / `ServerErrorException.statusCode`) e viaggia in `RestoreServerUnreachable` → `SessionUnreachable`. Il resto è UI nei file che ci sono.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, lucide_icons_flutter, mocktail, flutter_test.

**Spec:** `docs/superpowers/specs/2026-11-16-revisione-finale-ui-design.md` §9 (tutta), §3.1, §3.5, §10, §12 "Accesso". Bozza: `docs/superpowers/specs/2026-11-16-revisione-finale-bozze/accesso.html`.

## Global Constraints

- Lavoro nel worktree `.claude/worktrees/revisione-finale`, branch `revisione-finale-ui`. Comandi da `app/`. In Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Il worktree ha bisogno di `config/wonderflix.json` copiato da `C:\Users\sidot\Documents\Github\wonderflix\app\config\` e di `flutter pub get` e `flutter gen-l10n` prima di `analyze`/`test`.
- La fase 1 è già fatta: `loginSubmit` = "Accedi", campi del recupero password in `TvTextFieldFrame` senza autofocus, `WfDialogHeader`/`WfDialogFooter`, `showWfConfirmDialog` col piede comune, `showWfDialog(compactTitle:, footer:)`. Non rifarli.
- Nessun colore nuovo: solo `WfColors` (`bg`, `surface`, `surfaceHigh`, `border`, `gold`, `cream`, `creamMuted`, `error`, `online`). Titoli con `WfText.display(n)`. Numeri che cambiano con `FontFeature.tabularFigures()`.
- Testi in `l10n/app_it.arb` e `l10n/app_en.arb` (l'inglese è la traduzione equivalente), raccolti per area; plurali e generi con ICU. Le chiavi che nessuno usa più si tolgono, e con loro le righe dei test `test/app/l10n_plan*_test.dart` che le citano.
- Fuori dalla TV il comportamento TV non cambia, e viceversa. Layout del telefono = `compact && !tv`.
- Focus in TV: quello di tutta la TV, cioè `TvFocusable` (`ui/tv_focusable.dart`) per le carte e il tema dei pulsanti per i `WfButton`. Niente velo oro `focusColor` in TV.
- `dart format` solo sulle righe toccate.
- Commit: messaggio in italiano, nessun trailer `Co-Authored-By`, mai le parole `closes`/`fixes`/`resolves`. Messaggi su più righe con `git commit -F <file>` (file senza BOM).
- Mai chiudere processi per nome immagine (`taskkill /IM`, `pkill`).
- Nessun cambio al plugin né a Jellyfin.
- Indicatori indeterminati e spinner non si fermano mai nei widget test: `pump` espliciti, niente `pumpAndSettle` sullo splash, sull'irraggiungibile e sul download.

## Review Focus

- **"Cambia profilo" nello splash mentre `/Users/Me` è ancora in volo:** quando la risposta arriva dopo, il profilo non si riapre da solo e "Chi guarda?" resta. Test in Task 8 (controller e servizio).
- **Un nuovo tentativo che cambia il motivo** (da offline a "si sta avviando") mentre la schermata è aperta: titolo e lampade cambiano, "In attesa da N min" non riparte da zero. Test in Task 7.
- **Nomi lunghi** in Chi guarda? a 390 px e in "Ciao, {nome}" nel pannello di 380: ellissi, nessun overflow. Test in Task 1 e Task 4.
- **Fire Stick, Gestisci profili con 5 profili a 960×540:** "Modifica" e "Rimuovi" di ogni carta raggiungibili col D-pad, la riga del limite e "Fine" stanno nello schermo. Test in Task 2.
- **TV, accesso con "Non sei tu?" e le etichette nuove:** Su/Giù attraversano ancora i campi in cornice fino ad "Accedi" senza aprire la tastiera. Test in Task 4.

---

### Task 1: Il dispositivo nei testi, e la pagina Chi guarda?

**Files:**
- Create: `app/lib/core/platform/device_kind.dart`
- Modify: `app/test/support/pump_app.dart` (`_baseOverrides`), `app/lib/features/profiles/profiles_screen.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/core/platform/device_kind_test.dart` (nuovo), `app/test/features/profiles/profiles_screen_test.dart`, `app/test/app/l10n_plan17b_test.dart`

**Interfaces:**
- Produces:
  - `enum DeviceKind { pc, browser, phone, tv }`
  - `DeviceKind deviceKindFor({required bool tv, required bool web, required TargetPlatform platform})`: `tv` → tv; `web` → browser; `TargetPlatform.android` → phone; il resto → pc.
  - `final deviceKindProvider = Provider<DeviceKind>((ref) => deviceKindFor(tv: ref.watch(androidTvProvider), web: kIsWeb, platform: defaultTargetPlatform));`
  - I messaggi ICU ricevono `kind.name` come `device` (String, `select`).
- `pump_app.dart`: se gli `overrides` non hanno `deviceKindProvider`, aggiungi `deviceKindProvider.overrideWithValue(tv ? DeviceKind.tv : DeviceKind.pc)` (nei test `defaultTargetPlatform` è android: senza questo ogni test direbbe "telefono").

Chiavi (it):
- `profilesRemoveTitle(name, device)`: `"Rimuovere {name} {device, select, tv{da questa TV} browser{da questo browser} phone{da questo telefono} other{da questo PC}}?"`
- `profilesCount(count, max, device)`: `"{count} {count, plural, =1{profilo} other{profili}} su {max} {device, select, tv{su questa TV} browser{su questo browser} phone{su questo telefono} other{su questo PC}}"`
- `profilesFull(max, device)`: `"{max} profili {device, select, tv{su questa TV} browser{su questo browser} phone{su questo telefono} other{su questo PC}}: rimuovine uno per aggiungerne un altro."`
- `profilesLimit` resta (lo usa `describeError` per `ProfileLimitException`).

Pagina (spec §9.1):
- Misure per forma, in un record privato scelto in `build`: desktop logo 140, titolo `display(56)`, avatar 132, carta 150; telefono (`compact && !tv`) logo 96, titolo `display(40)`, avatar 96, carta 140, spazio tra le carte 16 (due colonne a 390); TV logo 96, titolo `display(44)`, avatar 100, carta 128. `profileAvatarSize` diventa la misura desktop (132); il test del velo misura l'avatar di quella forma.
- Sotto le carte, prima di "Gestisci profili": se `!book.isFull`, `profilesCount(n, ProfileBook.maxProfiles, device)` in `creamMuted` 12,5; se `book.isFull`, al posto del "+" una riga `profilesFull(...)` con icona `LucideIcons.info` oro 17, fondo `surface`, bordo `border`, angoli 8 (bozza `.limit`). Vale anche in "Gestisci profili".
- La conferma di rimozione usa `profilesRemoveTitle(nome, device)`.
- Se con le misure nuove il test esistente "finestra più piccola: tutto visibile, senza scorrere" (1008×600) non passa, riduci logo e spazi del desktop, non avatar e titolo.

- [ ] **Step 1: Test che falliscono**

```dart
test('il dispositivo dalla piattaforma', () {
  expect(deviceKindFor(tv: true, web: false, platform: TargetPlatform.android), DeviceKind.tv);
  expect(deviceKindFor(tv: false, web: true, platform: TargetPlatform.iOS), DeviceKind.browser);
  expect(deviceKindFor(tv: false, web: false, platform: TargetPlatform.android), DeviceKind.phone);
  expect(deviceKindFor(tv: false, web: false, platform: TargetPlatform.windows), DeviceKind.pc);
});
test('i testi nominano il dispositivo', () {
  final it = lookupAppLocalizations(const Locale('it'));
  expect(it.profilesRemoveTitle('Luigi', 'pc'), 'Rimuovere Luigi da questo PC?');
  expect(it.profilesRemoveTitle('Luigi', 'tv'), 'Rimuovere Luigi da questa TV?');
  expect(it.profilesRemoveTitle('Luigi', 'browser'), 'Rimuovere Luigi da questo browser?');
  expect(it.profilesRemoveTitle('Luigi', 'phone'), 'Rimuovere Luigi da questo telefono?');
  expect(it.profilesCount(4, 5, 'pc'), '4 profili su 5 su questo PC');
  expect(it.profilesCount(1, 5, 'tv'), '1 profilo su 5 su questa TV');
  expect(it.profilesFull(5, 'tv'), '5 profili su questa TV: rimuovine uno per aggiungerne un altro.');
});
testWidgets('sotto le carte il conto dei profili', (t) async {
  await pumpProfiles(t, [mario, luigi]);
  expect(find.text('2 profili su 5 su questo PC'), findsOneWidget);
});
testWidgets('con 5 profili il "+" lascia il posto al limite', (t) async {
  // 5 profili P1..P5: 'Aggiungi profilo' findsNothing,
  // find.text('5 profili su questo PC: rimuovine uno per aggiungerne un altro.') findsOneWidget,
  // e il conto 'su 5' findsNothing.
});
testWidgets('nel browser la rimozione dice "da questo browser"', (t) async {
  // overrides: [deviceKindProvider.overrideWithValue(DeviceKind.browser)];
  // Gestisci profili → Rimuovi di Luigi → 'Rimuovere Luigi da questo browser?'
});
testWidgets('telefono: due carte per riga, avatar 96, nomi lunghi con ellissi', (t) async {
  // Size(390, 780), 4 profili, il primo col nome 'Bartolomeo Massimiliano Ferdinando':
  // dy delle prime due carte uguale, la terza più in basso con dx uguale alla prima;
  // getSize dell'avatar del primo == Size.square(96); t.takeException() isNull.
});
```

- [ ] **Step 2:** `flutter test test/core/platform/device_kind_test.dart test/features/profiles/profiles_screen_test.dart test/app/l10n_plan17b_test.dart` → FAIL.
- [ ] **Step 3:** crea `device_kind.dart`, l'override in `pump_app.dart`, le chiavi (it/en, `flutter gen-l10n`), misure, conto e limite in `profiles_screen.dart`. Aggiorna `l10n_plan17b_test.dart` alla firma nuova di `profilesRemoveTitle`.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/features/profiles test/app` → PASS.
- [ ] **Step 5: Commit** `feat(app): Chi guarda? con il conto dei profili e i testi del dispositivo`

### Task 2: Gestisci profili con pulsanti scritti, e il focus della TV

**Files:**
- Modify: `app/lib/features/profiles/profiles_screen.dart` (`_ProfileCard`, `_AddProfileCard`, titolo), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/profiles/profiles_screen_test.dart`, `app/test/app/l10n_plan17b_test.dart`, `app/test/app/l10n_plan17c_test.dart`

**Interfaces:**
- Consumes: `TvFocusable({child, onActivate, autofocus, borderRadius})`.
- Chiavi: nuova `profilesEdit` "Modifica"; `profilesRemove` "Rimuovi" resta; via `profilesRemoveNamed` e `profilesEditImage` se non le usa più nessuno.

Regole:
- In gestione il titolo è `l.profilesManage` ("Gestisci profili") al posto di "Chi guarda?".
- Gli avatar si spengono come quelli scaduti (opacità `_expiredOpacity`) e sotto il nome ogni carta ha, in colonna e larghi quanto la carta, `WfButton.secondary(small: true)` "Modifica" (`LucideIcons.pencil`, key `profile-image-<id>`, spento per un profilo scaduto, apre `showAvatarDialog`) e "Rimuovi" (`LucideIcons.trash2`, key `profile-remove-<id>`). Le due `IconButton` sugli angoli spariscono.
- In TV il logo non c'è in gestione (5 carte con due pulsanti non starebbero in 540).
- TV: la carta (e "Aggiungi profilo") sta in `TvFocusable(autofocus: …, onActivate: onOpen, borderRadius: 12)`; l'`InkWell` dentro ha `canRequestFocus: !tv`, `autofocus: !tv && autofocus` e nessun `focusColor` in TV. In gestione `onOpen` è `null`: la carta non prende il focus, i pulsanti sì. Fuori dalla TV tutto come oggi.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('Gestisci profili: titolo, Modifica e Rimuovi scritti', (t) async {
  await pumpProfiles(t, [mario, testProfile(userId: 'u2', name: 'Luigi', expired: true)]);
  await t.tap(find.text('Gestisci profili'));
  await t.pump();
  expect(find.text('Chi guarda?'), findsNothing);
  expect(find.text('Gestisci profili'), findsOneWidget); // il titolo; il pulsante dice "Fine"
  expect(find.widgetWithText(WfButton, 'Modifica'), findsNWidgets(2));
  expect(find.widgetWithText(WfButton, 'Rimuovi'), findsNWidgets(2));
  expect(t.widget<WfButton>(find.byKey(const ValueKey('profile-image-u2'))).onPressed, isNull);
  expect(find.byType(IconButton), findsNothing);
});
testWidgets('TV: la carta col focus ha il bordo della TV', (t) async {
  await pumpProfiles(t, [mario, luigi], tv: true, surfaceSize: const Size(960, 540));
  expect(find.ancestor(of: find.text('Mario'), matching: find.byType(TvFocusable)), findsOneWidget);
  expect(find.ancestor(of: find.text('Aggiungi profilo'), matching: find.byType(TvFocusable)), findsOneWidget);
  // l'InkWell della carta di Mario: canRequestFocus false, focusColor null
});
testWidgets('TV, Gestisci profili: il D-pad passa da Modifica a Rimuovi e alla carta dopo', (t) async {
  // tv, 960×540, [mario, luigi]: tap 'Gestisci profili'; focus su 'profile-image-u1';
  // arrowDown → focus su 'profile-remove-u1'; arrowRight → focus su un pulsante di u2.
});
testWidgets('TV, Gestisci profili con 5 profili: tutto nello schermo', (t) async {
  // tv, 960×540, 5 profili: tap 'Gestisci profili'; nessuna eccezione;
  // getRect(find.text('Fine')).bottom <= 540; la riga del limite c'è; il logo no.
});
```

Aggiorna i test che usano `tester.widget<IconButton>(…profile-image…)` (→ `WfButton`) e la conferma "Rimuovi": cerca il pulsante dentro la finestra (`find.descendant(of: find.byType(Dialog), …)`), perché ora anche le carte dicono "Rimuovi".

- [ ] **Step 2:** `flutter test test/features/profiles/profiles_screen_test.dart` → FAIL.
- [ ] **Step 3:** implementa; togli le chiavi non usate (it/en, test l10n); `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/profiles test/app test/features/tv_focus_borders_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat(app): Gestisci profili con Modifica e Rimuovi scritti, focus della TV sulle carte`

### Task 3: Immagine del profilo

**Files:**
- Modify: `app/lib/features/profiles/avatar_dialog.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/profiles/avatar_dialog_test.dart`, `app/test/app/l10n_plan17c_test.dart`

**Interfaces:**
- Consumes: `deviceKindProvider` (Task 1).
- Chiavi: `profileImageTitle(name)` "Immagine di {name}" (anche `semanticLabel` di `showWfDialog`); `profileImageFromPc` diventa `profileImageFromDevice(device)` `"{device, select, phone{Dal telefono} browser{Carica immagine} other{Dal PC}}"`; `profileImageRemove` "Togli immagine".

Regole (spec §9.1):
- Testa: a sinistra l'immagine attuale (`UserAvatar` 64) e sotto, solo se `imageTag != null`, un `TextButton` "Togli immagine" (key `avatar-remove`, spento durante un caricamento, fa `_save(() async => null)`); a destra il titolo `WfText.display(32)`.
- Schede: "Avatar" e quella del file col nome del dispositivo. La scheda "Rimuovi" e `_removeTab`/`_previewSize` spariscono (`TabController(length: 2)`).
- TV (`ref.read(deviceKindProvider) == DeviceKind.tv`, letto in `initState`): niente scheda del file e niente `TabBar`, solo la galleria; `showAvatarDialog` passa `fullPageWhenCompact: !FormFactor.of(context).tv`.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('il titolo nomina il profilo; due schede; "Togli immagine" sotto l\'immagine', (t) async {
  await openDialog(t, imageTag: 'tag1');
  expect(find.text('Immagine di Mario'), findsOneWidget);
  expect(find.text('Avatar'), findsOneWidget);
  expect(find.text('Dal PC'), findsOneWidget);
  expect(find.text('Rimuovi'), findsNothing);
  expect(t.getTopLeft(find.byKey(const Key('avatar-remove'))).dy,
      greaterThan(t.getBottomLeft(find.byType(UserAvatar).first).dy));
});
testWidgets('senza immagine "Togli immagine" non c\'è', (t) async { /* imageTag: null */ });
testWidgets('"Togli immagine" toglie l\'immagine', (t) async {
  // tap avatar-remove → session.profileImageCalls == [('u1', null)]
});
testWidgets('telefono: "Dal telefono"; browser: "Carica immagine"', (t) async {
  // overrides deviceKindProvider phone / browser
});
testWidgets('TV: solo la galleria, in una finestra', (t) async {
  // tv: true, Size(960, 540): find.byType(TabBar) findsNothing, 'Dal PC' findsNothing,
  // find.byKey(ValueKey('gallery-0')) findsOneWidget, find.byType(Dialog) findsOneWidget
});
```

I test "Rimuovi: spento senza immagine" / "Rimuovi: con un'immagine la toglie" diventano i due casi di "Togli immagine" qui sopra.

- [ ] **Step 2:** `flutter test test/features/profiles/avatar_dialog_test.dart` → FAIL.
- [ ] **Step 3:** implementa; chiavi it/en; `flutter gen-l10n`; aggiorna `l10n_plan17c_test.dart`.
- [ ] **Step 4:** `flutter test test/features/profiles test/app` → PASS.
- [ ] **Step 5: Commit** `feat(app): immagine del profilo col nome, l'immagine attuale e Togli immagine`

### Task 4: Accesso: titolo, Ciao, campi

**Files:**
- Modify: `app/lib/features/auth/login_screen.dart`, `app/lib/features/auth/password_login_form.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/auth/login_screen_test.dart`

**Interfaces:**
- Produces: `PasswordLoginForm({Key? key, String? initialUsername, ValueChanged<String>? onForgotPassword, VoidCallback? onNotYou})`: con `onNotYou` accanto all'etichetta "Nome utente" c'è il link "Non sei tu?" (key `login-not-you`).
- Chiavi nuove: `loginTitle` "Accedi a WonderFlix", `loginWelcomeBack(name)` "Ciao, {name}", `loginNotYou` "Non sei tu?", `loginShowPassword` "Mostra la password", `loginHidePassword` "Nascondi la password". Cambia `sessionExpired` → "La sessione è scaduta, capita dopo un po' di tempo. Accedi di nuovo per rientrare."

Regole (spec §9.2):
- In cima al pannello (non nel recupero): con `expired` e un nome salvato del profilo `reloginUserId`, una riga con `UserAvatar` 52 e "Ciao, {nome}" (`WfText.display(34)`, una riga, ellissi); altrimenti "Accedi a WonderFlix" senza avatar.
- Sessione scaduta: al posto di `ErrorBanner`, un avviso neutro (fondo `surfaceHigh`, bordo `border`, angoli 8, `LucideIcons.clock` 16 crema, testo `creamMuted` 13).
- "Non sei tu?" (solo nel caso "Ciao"): stato `_notYou = true` → titolo "Accedi a WonderFlix", niente avatar né avviso, modulo ricreato vuoto (`key: ValueKey(_notYou)`, `initialUsername: null`): fuori dalla TV il fuoco va al nome.
- Campi: etichetta sopra (`loginUsername`/`loginPassword`, `creamMuted` 12,5 w600), niente `hintText`; i due campi in un `AutofillGroup`, `autofillHints: [AutofillHints.username]` e `[AutofillHints.password]`; fuori dalla TV `suffixIcon` occhio (`LucideIcons.eye`/`eyeOff`, key `login-password-eye`, tooltip "Mostra la password"/"Nascondi la password") che alterna `obscureText`. In TV niente occhio (il campo è in cornice).
- Pannello: niente `SizedBox(height: 300)` con `TabBarView`; anche sul desktop la scheda è l'`IndexedStack` che oggi usa lo stretto (`login_screen.dart:209-234`): cresce col contenuto e il nome scritto resta.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('primo accesso: "Accedi a WonderFlix", etichette, autofill', (t) async {
  await pumpLogin(t);
  expect(find.text('Accedi a WonderFlix'), findsOneWidget);
  expect(find.text('Nome utente'), findsOneWidget);
  final user = t.widget<TextField>(find.byKey(const Key('login-username')));
  final pass = t.widget<TextField>(find.byKey(const Key('login-password')));
  expect(user.decoration!.hintText, isNull);
  expect(user.autofillHints, [AutofillHints.username]);
  expect(pass.autofillHints, [AutofillHints.password]);
  expect(find.ancestor(of: find.byKey(const Key('login-username')),
      matching: find.byType(AutofillGroup)), findsOneWidget);
});
testWidgets('l\'occhio mostra e nasconde la password', (t) async {
  // tap login-password-eye → obscureText false, tooltip 'Nascondi la password'; di nuovo → true
});
testWidgets('sessione scaduta: Ciao, avatar, avviso neutro', (t) async {
  await pumpLogin(t,
      initial: const SessionSignedOut(expired: true, reloginUserId: 'u2'),
      profiles: [testProfile(userId: 'u1'), testProfile(userId: 'u2', name: 'Luigi', expired: true)]);
  expect(find.text('Ciao, Luigi'), findsOneWidget);
  expect(find.byType(UserAvatar), findsOneWidget);
  expect(find.text('La sessione è scaduta, capita dopo un po\' di tempo. Accedi di nuovo per rientrare.'), findsOneWidget);
  expect(find.byType(ErrorBanner), findsNothing);
  expect(find.byIcon(LucideIcons.clock), findsOneWidget);
});
testWidgets('"Non sei tu?" svuota il nome e torna al titolo generico', (t) async {
  // come sopra; tap login-not-you → 'Accedi a WonderFlix', 'Ciao, Luigi' findsNothing,
  // controller del nome vuoto, fuoco sul nome, avviso sparito
});
testWidgets('nome lunghissimo nel Ciao: una riga, nessun overflow', (t) async {
  // nome di 60 caratteri → t.takeException() isNull
});
testWidgets('desktop con Quick Connect: niente altezza fissa', (t) async {
  await pumpLogin(t, quickConnect: true);
  expect(find.byType(TabBarView), findsNothing);
  expect(find.byType(IndexedStack), findsOneWidget);
});
testWidgets('TV, Ciao: Giù attraversa i campi fino ad Accedi senza tastiera', (t) async {
  // tv, 960×540, relogin di Luigi, scheda Password: dal focus su 'Non sei tu?'
  // arrowDown ripetuto → il focus passa dalle cornici (find.byType(TvTextFieldFrame))
  // al pulsante 'Accedi'; nessun EditableText ha mai il focus; nessun occhio.
});
```

Aggiorna i due test che cercano 'Sessione scaduta, accedi di nuovo.'.

- [ ] **Step 2:** `flutter test test/features/auth/login_screen_test.dart` → FAIL.
- [ ] **Step 3:** implementa; chiavi it/en; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/auth` → PASS.
- [ ] **Step 5: Commit** `feat(app): accesso con titolo, Ciao e campi con etichetta e occhio`

### Task 5: Quick Connect

**Files:**
- Modify: `app/lib/features/auth/quick_connect_panel.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/auth/quick_connect_panel_test.dart`

**Interfaces:**
- Consumes: `appConfigProvider` (`supportUrl`), `FormFactor.of(context).tv`, chiavi esistenti `menuSettings` ("Impostazioni"), `settingsAccount` ("Account"), `settingsQuickConnect` ("Autorizza un dispositivo", il nome vero della voce in `account_settings_section.dart:72`), `authorizeDeviceSubmit` ("Autorizza").
- Chiavi: `quickConnectYourCode` "Il tuo codice" (senza i due punti); nuove `quickConnectStepOpen(path)` "Su un dispositivo già collegato apri {path}.", `quickConnectStepCode(button)` "Scrivi il codice e premi {button}.", `quickConnectNoDevice` "Non hai un altro dispositivo collegato?", `quickConnectAskAdmin` "Chiedi all'admin di autorizzarti"; via `quickConnectHelp`.

Regole (spec §9.2):
- Codice `WfText.display(68, color: WfColors.gold)` con `letterSpacing: 6` e `fontFeatures: [FontFeature.tabularFigures()]`.
- Sotto l'attesa, dopo un filo `border`, due righe numerate: un cerchio 24 con bordo oro e la cifra oro (Inter 12 w600), poi il testo crema 14. Il `path` è `'${l.menuSettings} › ${l.settingsAccount} › ${l.settingsQuickConnect}'`, il `button` è `l.authorizeDeviceSubmit`.
- In fondo: fuori dalla TV, con `supportUrl`, "Non hai un altro dispositivo collegato?" e il `TextButton` "Scrivi all'admin" (`loginContactAdmin`, `launchUrl`); in TV solo il testo "Chiedi all'admin di autorizzarti", niente link. Lo stesso in TV nel modulo password e nel recupero: dove oggi c'è il link "Scrivi all'admin", in TV c'è il testo "Chiedi all'admin".

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('codice grande e tabellare, due passi col nome vero della voce', (t) async {
  // runner.current.add(QcWaiting('482913')); pump
  expect(find.text('Il tuo codice'), findsOneWidget);
  final code = t.widget<Text>(find.text('482 913'));
  expect(code.style!.fontSize, 68);
  expect(code.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
  expect(find.text('Su un dispositivo già collegato apri Impostazioni › Account › Autorizza un dispositivo.'), findsOneWidget);
  expect(find.text('Scrivi il codice e premi Autorizza.'), findsOneWidget);
  expect(find.text('1'), findsOneWidget);
  expect(find.text('2'), findsOneWidget);
  expect(find.widgetWithText(TextButton, 'Scrivi all\'admin'), findsOneWidget);
});
testWidgets('TV: chiedere all\'admin è un testo, non un link', (t) async {
  // tv: true: find.text('Chiedi all\'admin di autorizzarti') findsOneWidget,
  // find.text('Scrivi all\'admin') findsNothing
});
```

- [ ] **Step 2:** `flutter test test/features/auth/quick_connect_panel_test.dart` → FAIL.
- [ ] **Step 3:** implementa; chiavi; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/auth` → PASS.
- [ ] **Step 5: Commit** `feat(app): Quick Connect col codice grande e i passi con i nomi veri`

### Task 6: Perché il server non si raggiunge

**Files:**
- Modify: `app/lib/features/auth/auth_service.dart` (`RestoreServerUnreachable`, `openProfile`), `app/lib/features/auth/session_controller.dart` (`SessionUnreachable`, `_stateFor`)
- Test: `app/test/features/auth/auth_service_test.dart`, `app/test/features/auth/session_controller_test.dart`

**Interfaces:**
- Produces (in `auth_service.dart`, senza Flutter):
  - `enum UnreachableReason { offline, starting, notResponding }`
  - `UnreachableReason unreachableReasonOf(ApiException error)`: `ServerUnreachableException` (connessione, timeout, certificato) → `offline`; `ServerErrorException(503)` → `starting`; ogni altro errore (502, 504, 500, 403, `null`) → `notResponding`.
  - `RestoreServerUnreachable([this.reason = UnreachableReason.notResponding])`, campo `final UnreachableReason reason`.
  - `SessionUnreachable({this.retryUserId, this.reason = UnreachableReason.notResponding})`, campo `final UnreachableReason reason`.
- `openProfile`: `on ApiException catch (error)` → `RestoreServerUnreachable(unreachableReasonOf(error))`. `_stateFor` passa `reason` a `SessionUnreachable`. I `catch (Object)` del controller (`restore`, `openProfile`) restano col valore predefinito.

- [ ] **Step 1: Test che falliscono**

```dart
test('il motivo dal tipo di errore', () {
  expect(unreachableReasonOf(const ServerUnreachableException()), UnreachableReason.offline);
  expect(unreachableReasonOf(const ServerErrorException(503)), UnreachableReason.starting);
  expect(unreachableReasonOf(const ServerErrorException(502)), UnreachableReason.notResponding);
  expect(unreachableReasonOf(const ServerErrorException(504)), UnreachableReason.notResponding);
  expect(unreachableReasonOf(const ForbiddenException()), UnreachableReason.notResponding);
});
test('un 503 aprendo il profilo: il server si sta avviando', () async {
  // getMe lancia ServerErrorException(503) →
  // (await service.restore() as RestoreServerUnreachable).reason == UnreachableReason.starting
});
test('il controller porta il motivo nella sessione', () async {
  // auth.restore() → RestoreServerUnreachable(UnreachableReason.offline) →
  // (controller.state as SessionUnreachable).reason == UnreachableReason.offline
});
```

- [ ] **Step 2:** `flutter test test/features/auth/auth_service_test.dart test/features/auth/session_controller_test.dart` → FAIL.
- [ ] **Step 3:** implementa.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/app/router_test.dart test/features/startup` → PASS.
- [ ] **Step 5: Commit** `feat(app): la sessione sa se il server è offline, in avvio o fermo`

### Task 7: Schermata del server irraggiungibile

**Files:**
- Modify: `app/lib/features/startup/unreachable_screen.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/startup/unreachable_screen_test.dart`

**Interfaces:**
- Consumes: `SessionUnreachable.reason` (Task 6); `WfLamp({state, label, size})` e `LampState` da `features/admin/admin_kit.dart`; `WfMotion.of(context).isReduced`; `FormFactor.of(context)`.
- Chiavi nuove (via `unreachableTitle` e `unreachableBody`):
  - `unreachableOfflineTitle` "Sei offline", `unreachableOfflineBody` "Non riesco a raggiungere il server. Controlla il Wi-Fi o i dati mobili: riprovo da solo.", `unreachableOfflineHint` "Se la rete funziona, il server potrebbe essere spento: avvisa l'admin."
  - `unreachableStartingTitle` "Il server si sta avviando", `unreachableStartingBody` "Dopo un riavvio può volerci anche mezz'ora. Non devi fare niente: appena è pronto entri da solo."
  - `unreachableDownTitle` "Il server non risponde", `unreachableDownBody` "Non devi fare niente: appena risponde entri da solo."
  - `unreachableLampConnection` "La tua connessione", `unreachableLampServer` "Server"
  - `unreachableRetryIn(seconds)` "Riprovo tra {seconds} s", `unreachableRetrying` "Riprovo…", `unreachableWaiting(minutes)` "In attesa da {minutes} min", `unreachableRetryNow` "Riprova ora"

Regole (spec §9.3):
- In cima la catena: due pastiglie (alte 32, fondo `surface`, bordo `border`, angoli 16) con `WfLamp` e il nome, unite da una linea `border` 1,5 larga 64 (28 sul telefono). Lampade: offline → `broken`, `off`; starting e notResponding → `ok`, `attention`. Keys `lamp-connection`, `lamp-server` sui `WfLamp`.
- Titolo `WfText.display(68)` (48 sul telefono), centrato; corpo `creamMuted` 15 centrato, largo al massimo 52 caratteri (~520); per offline sotto anche il suggerimento in 12,5.
- Conto: un `Timer.periodic` di 1 s al posto di quello di 15 s. A ogni battito `_waited++`; se non si sta riprovando `_left--`, e a 0 parte `_retry()`. `_retry()` (anche dal pulsante) rimette `_left = 15` alla fine del tentativo. Testo "Riprovo tra N s" (o "Riprovo…" durante il tentativo) con cifre tabellari; a destra, da 120 s in poi, "In attesa da {_waited ~/ 60} min". `_waited` non si azzera mai finché la schermata resta.
- Linea oro (key `retry-line`) alta 3, larga 360 (tutta la larghezza sul telefono), che si riempie in 15 s: valore `1 - _left / 15` animato per 1 s tra un battito e l'altro (`TweenAnimationBuilder`). Con movimento ridotto la linea non c'è.
- Pulsanti: `WfButton.primary` "Riprova ora" (`LucideIcons.refreshCw`, `autofocus: tv`, spento durante il tentativo) e, come oggi solo con `retryUserId`, `WfButton.secondary` "Cambia profilo". Desktop e TV in riga (larghi almeno 170); telefono in colonna a tutta larghezza, alti 46.
- Telefono: `SingleChildScrollView` con padding orizzontale 16, tutto centrato.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('nessuna risposta: Sei offline, prima lampada rossa e seconda spenta', (t) async {
  await pumpUnreachable(t, const SessionUnreachable(reason: UnreachableReason.offline));
  expect(find.text('Sei offline'), findsOneWidget);
  expect(lamp(t, 'lamp-connection'), LampState.broken);
  expect(lamp(t, 'lamp-server'), LampState.off);
});
testWidgets('503: il server si sta avviando, con la mezz\'ora', (t) async {
  // 'Il server si sta avviando', find.textContaining('mezz\'ora') findsOneWidget, lampade ok/attention
});
testWidgets('502/504: il server non risponde, senza la mezz\'ora', (t) async {
  // reason notResponding: 'Il server non risponde', textContaining('mezz\'ora') findsNothing, ok/attention
});
testWidgets('il conto scende e riprova a 0', (t) async {
  // 'Riprovo tra 15 s'; pump(3 s) → 'Riprovo tra 12 s'; pump(12 s) + pump() → restoreCalls 1
});
testWidgets('"Riprova ora" fa ripartire il conto', (t) async {
  // pump(10 s); tap 'Riprova ora'; pump() → restoreCalls 1, 'Riprovo tra 15 s';
  // pump(10 s) → restoreCalls 1; pump(5 s) + pump() → restoreCalls 2
});
testWidgets('attese lunghe: In attesa da N min, anche se il motivo cambia', (t) async {
  // pump(119 s): textContaining('In attesa da') findsNothing; pump(1 s): 'In attesa da 2 min';
  // fake.set(SessionUnreachable(reason: starting)); pump → titolo nuovo, 'In attesa da 2 min' resta
});
testWidgets('TV: "Riprova ora" ha il focus', (t) async {
  // tv, 960×540: Focus.of(element di 'Riprova ora').hasFocus
});
testWidgets('telefono: pulsanti a tutta larghezza, testo centrato, niente overflow', (t) async {
  // 390×780, retryUserId 'u2': getSize('Riprova ora' WfButton).width == 358; stesso per 'Cambia profilo';
  // Text del titolo textAlign center; takeException isNull
});
testWidgets('movimento ridotto: niente linea; completo: la linea c\'è', (t) async { /* key retry-line */ });
```

`pumpUnreachable` e `lamp` sono helper locali (`FakeSessionController` + `tester.widget<WfLamp>(find.byKey(Key(k))).state`). Aggiorna i test esistenti: 'WonderFlix non è raggiungibile' → 'Il server non risponde', `find.text('Riprova')` → 'Riprova ora'.

- [ ] **Step 2:** `flutter test test/features/startup/unreachable_screen_test.dart` → FAIL.
- [ ] **Step 3:** implementa; chiavi; `flutter gen-l10n`.
- [ ] **Step 4:** stesso comando → PASS.
- [ ] **Step 5: Commit** `feat(app): server irraggiungibile con le lampade, il motivo e il conto alla rovescia`

### Task 8: Splash che si blocca

**Files:**
- Modify: `app/lib/features/startup/splash_screen.dart`, `app/lib/features/auth/auth_service.dart` (`restore`, `openProfile`), `app/lib/features/auth/session_controller.dart` (`restore`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/startup/splash_screen_test.dart`, `app/test/features/auth/auth_service_test.dart`, `app/test/features/auth/session_controller_test.dart`

**Interfaces:**
- Produces: `const splashSlowAfter = Duration(seconds: 10);` in `splash_screen.dart`; `SplashScreen` diventa `ConsumerStatefulWidget`.
- Chiavi: `splashOpening(name)` "Apro il profilo di {name}…", `splashOpeningUnnamed` "Apro il profilo…"; il pulsante riusa `profilesSwitch` ("Cambia profilo").

Regole (spec §9.3, ultima riga):
- `AuthService.restore`: dopo `_book = await _store.read()` (e nel ramo `_unsaved`) chiama `onProfilesChanged?.call()`, così lo splash conosce il profilo prima di `/Users/Me`.
- `AuthService.openProfile`: prende `final generation = _generation` subito dopo `_generation++`; dopo l'`await` di `getMe` (riuscito o con errore), se `generation != _generation` non tocca `_activeUserId` né lo storage e restituisce `_book.isEmpty ? const NoStoredSession() : const ChooseProfile()`.
- `SessionController.restore`: `final before = state;` e applica il risultato solo se `identical(state, before)`; altrimenti lo scarta (l'utente ha già scelto altro).
- Splash: un `Timer(splashSlowAfter)` mette `_slow = true`. Con `_slow` e almeno un profilo nel `profilesProvider`, sotto lo spinner: `splashOpening(nome)` del profilo `book.lastUserId` o dell'unico (senza nome `splashOpeningUnnamed`), in `creamMuted` 14, e `WfButton.secondary` "Cambia profilo" (`LucideIcons.users`, `autofocus: true` perché in TV nient'altro ha il focus) che chiama `backToProfiles()`. Il riflesso e lo spinner restano.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('dopo 10 s: il profilo che si apre e "Cambia profilo"', (t) async {
  // FakeSessionController(SessionStarting()), profilesProvider con Mario
  // pump(9 s): 'Apro il profilo di Mario…' findsNothing; pump(1 s): findsOneWidget;
  // tap 'Cambia profilo' → fake.backToProfilesCalls == 1
});
testWidgets('senza profili niente testo né pulsante', (t) async { /* book vuoto, pump(11 s) */ });
test('restore fa conoscere i profili prima di /Users/Me', () async {
  // onProfilesChanged contato; getMe da un Completer mai completato;
  // unawaited(service.restore()); await pumpEventQueue(); chiamate >= 1, book con Mario
});
test('un\'apertura superata da deactivate non apre il profilo', () async {
  // getMe da un Completer; final result = service.restore(); service.deactivate();
  // completa con l'utente → await result isA<ChooseProfile>(), service.activeUserId isNull
});
test('Cambia profilo durante restore: il risultato tardivo non riapre', () async {
  // MockAuthService: restore() → Completer; unawaited(controller.restore());
  // controller.backToProfiles(); completa con RestoredSession(user);
  // await pumpEventQueue(); controller.state isA<SessionChoosingProfile>()
});
```

- [ ] **Step 2:** `flutter test test/features/startup/splash_screen_test.dart test/features/auth` → FAIL.
- [ ] **Step 3:** implementa; chiavi; `flutter gen-l10n`.
- [ ] **Step 4:** stessi test → PASS; `flutter test test/app/router_test.dart test/features/auth/session_integration_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat(app): lo splash bloccato dice cosa apre e lascia cambiare profilo`

### Task 9: Aggiornamento

**Files:**
- Modify: `app/lib/features/update/update_banner.dart`, `app/lib/features/update/mandatory_update_screen.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/update/update_banner_test.dart` (nuovo), `app/test/features/update/update_gate_test.dart`

**Interfaces:**
- Consumes: `testRelease()` e `FakeUpdateController` (`test/support/update_fakes.dart`).
- Chiave nuova: `updateDownloadingStarted` "Download in corso…".

Regole (spec §9.4):
- Banner: un `LayoutBuilder` sulla larghezza del banner; sotto 640, due righe: icona e titolo sopra, sotto una riga con "Novità" a sinistra (se ci sono note), poi `Spacer`, "Più tardi" e "Riavvia ora" (l'unico `WfButton.primary`). Da 640 in su la riga unica di oggi.
- Schermata obbligatoria: titolo `l.updateRequiredTitle` senza `.toUpperCase()`. Con `progress == null || progress == 0` barra indeterminata (`value: null`) e "Download in corso…"; con un valore > 0 `updateDownloading(percentuale)`.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('sotto 640 il banner va su due righe', (t) async {
  await pumpApp(t, Scaffold(body: Align(alignment: Alignment.bottomCenter,
      child: UpdateBanner(release: testRelease(), onRestart: () {}, onLater: () {}))),
      surfaceSize: const Size(480, 800));
  final title = find.text('Aggiornamento pronto: WonderFlix 0.2.0');
  expect(t.getTopLeft(find.text('Riavvia ora')).dy, greaterThan(t.getBottomLeft(title).dy));
  expect(t.getTopLeft(find.text('Novità')).dx, lessThan(t.getTopLeft(find.text('Più tardi')).dx));
  expect(find.byWidgetPredicate((w) => w is WfButton && w.label == 'Riavvia ora'), findsOneWidget);
});
testWidgets('da 640 in su una riga sola', (t) async {
  // Size(1280, 800): (getCenter('Riavvia ora').dy - getCenter(title).dy).abs() < 12
});
```

In `update_gate_test.dart`: 'AGGIORNAMENTO NECESSARIO' → 'Aggiornamento necessario'; un caso nuovo con `progress: 0` → `find.text('Download in corso…')` findsOneWidget, `textContaining('%')` findsNothing, `LinearProgressIndicator.value` null (solo `pump`); 0,4 resta 'Download in corso… 40%'.

- [ ] **Step 2:** `flutter test test/features/update` → FAIL.
- [ ] **Step 3:** implementa; chiave; `flutter gen-l10n`.
- [ ] **Step 4:** stesso comando → PASS.
- [ ] **Step 5: Commit** `feat(app): banner dell'aggiornamento su due righe e download senza 0%`

### Task 10: Checklist e verifica completa

**Files:**
- Modify: `docs/RELEASING.md`

- [ ] **Step 1:** nella checklist della 0.42.0 aggiungi: `- [ ] Revisione finale, fase 7, prima dell'app (app 0.42.0): Chi guarda? con "N profili su 5 su questo PC" e la riga del limite a 5; Gestisci profili con Modifica e Rimuovi scritti; "Rimuovere X da questo PC?"; Immagine di X con Togli immagine e "Dal PC"; accesso "Accedi a WonderFlix", sessione scaduta con "Ciao", avviso grigio e "Non sei tu?", occhio della password e compilazione del gestore di password; Quick Connect col codice grande e i due passi; server irraggiungibile offline (rete staccata) con le lampade, il conto e "Riprova ora" che lo fa ripartire; TV: focus sulle carte, Modifica/Rimuovi col telecomando, immagine senza "Dal PC", "Chiedi all'admin di autorizzarti", focus su "Riprova ora".`
- [ ] **Step 2: Verifica completa:** `flutter gen-l10n`, `flutter analyze` (nessun problema nuovo), `flutter test` (tutti verdi; i flaky noti si rilanciano una volta). `grep -rn "quickConnectHelp\|unreachableTitle\|unreachableBody\|profilesRemoveNamed\|profilesEditImage" lib test l10n` → niente.
- [ ] **Step 3: Commit** `docs: checklist della revisione di Chi guarda?, accesso e server`

## Prova a mano (dopo la review finale)

Release Windows dal worktree (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`, poi `Start-Process build\windows\x64\runner\Release\wonderflix.exe`):
- Chi guarda?: il conto sotto le carte; Gestisci profili (titolo, avatar spenti, Modifica/Rimuovi); la conferma "da questo PC" (annulla); Modifica → "Immagine di …" con l'immagine attuale, "Dal PC", "Togli immagine" solo con un'immagine.
- Accesso: "Aggiungi profilo" → "Accedi a WonderFlix", etichette, occhio, scheda Quick Connect che non taglia niente; il codice e i due passi; "Annulla".
- Server: staccare la rete e aprire un profilo → "Sei offline", lampada rossa, "Riprovo tra 15 s" che scende, "Riprova ora" che fa ripartire il conto; riattaccare → si entra da soli. Il 503 e il 502/504 restano ai test (niente riavvio di Jellyfin apposta), salvo un riavvio già previsto, con i controlli di CLAUDE.md.
- Finestra sotto 640 px: il banner dell'aggiornamento si vede solo con una release più nuova; resta ai test.

Fire Stick (APK e installazione come da CLAUDE.md; login solo con Quick Connect): Chi guarda? col bordo della TV sulla carta, Gestisci profili col D-pad su Modifica e Rimuovi, Modifica → solo la galleria in una finestra; avatar → "Aggiungi account" → Quick Connect con "Chiedi all'admin di autorizzarti"; scheda Password: Giù attraversa i campi senza tastiera.

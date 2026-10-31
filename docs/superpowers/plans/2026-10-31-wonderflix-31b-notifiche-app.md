# WonderFlix — Piano 31b: notifiche push, app 0.26.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte app della Spec V nell'app 0.26.0:
- le voci nuove nella cassetta;
- la sezione Notifiche nelle impostazioni, con i tipi e l'attivazione del dispositivo sul web;
- il service worker che mostra le push e apre la rotta giusta;
- le notifiche di Windows mentre l'app è aperta.

Si appoggia al plugin 1.17.0 del piano 31a: **si fa dopo il 31a**.

**Architecture:**
- **Dati:** `NotificationsApi` parla con gli endpoint del 31a. `inbox_models.dart` impara i 10 tipi nuovi.
- **Testi e rotte:** `notification_text.dart` dà titolo, testo e rotta di ogni voce, con gli stessi testi del plugin. Lo usano le righe nuove della cassetta e le notifiche di Windows.
- **Web:** `web/push_sw.js` riceve la push e apre la rotta. `lib/core/push/web_push.dart` ha due implementazioni con import condizionale, come `lib/app/platform_startup.dart`: browser e stub. `DevicePushController` tiene lo stato del dispositivo.
- **Windows:** `InboxToaster` ascolta le voci arrivate con `InboxChangedEvent` e le mostra con `local_notifier`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x (niente nomi di Riverpod 2), go_router, `package:web` / `dart:js_interop`, `local_notifier` (nuovo, solo Windows).

**Spec:** `docs/superpowers/specs/2026-10-31-wonderflix-notifiche-push-design.md`, §4.1–§4.6 e §5. JSON e testi: piano `docs/superpowers/plans/2026-10-31-wonderflix-31a-notifiche-plugin.md`, "Global Constraints" e Task 3.

## Global Constraints

- Versione dell'app **0.26.0**. Commit in italiano, senza `closes`/`fixes`/`resolves` e senza trailer `Co-Authored-By`.
- Non uccidere mai processi per nome dell'immagine (`taskkill /IM`, `pkill`).
- **Controlli (da `app/`):** `flutter gen-l10n`, `flutter analyze`, `flutter test`.
- **Build di release Windows:** `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.
- **Build web:** `flutter build web --wasm --base-href /wonderflix/ --pwa-strategy=none --dart-define-from-file=config/wonderflix.json` (per il sito di prova `--base-href /wonderflix-prova/`; in Git Bash con `MSYS_NO_PATHCONV=1`).
- **Flutter non registra un suo service worker:** `flutter_bootstrap.js` chiama `_flutter.loader.load()` senza `serviceWorkerSettings`. `push_sw.js` è l'unico service worker e il suo scope è la cartella del sito.
- **JSON, tipi, rotte e testi** sono quelli del piano 31a. I testi della cassetta e di Windows sono **identici** a quelli della tabella del Task 3 del 31a, in `app_it.arb` e `app_en.arb`.
- **Disponibilità della funzione:** tutto quello che parla con gli endpoint delle notifiche è attivo solo se `Info.Features` contiene `push`, come le altre funzioni del plugin.
- **Nessuna notifica per le voci vecchie:** all'avvio, al cambio di profilo e alla riconnessione del WebSocket non partono notifiche di Windows.

## Review Focus

1. **iPhone con il sito in una scheda di Safari o Chrome**, non dalla Home: la sezione dice di aggiungere il sito alla Home, senza un pulsante che fallisce in silenzio. Test nel Task 4.
2. **Permesso negato da iOS o dal browser:** lo stato "permesso negato" spiega come riattivarlo e il pulsante non riprova a vuoto. Test nel Task 4.
3. **Uscita da un profilo con le notifiche attive:** il `DELETE` parte **prima** del logout, finché il token vale. Gli errori del `DELETE` non bloccano l'uscita. Test nel Task 4.
4. **App Windows che si riconnette dopo un'ora offline:** le voci arrivate nel frattempo non fanno partire una raffica di notifiche. Test nel Task 5.
5. **Plugin vecchio, senza `push`:** la sezione Notifiche non compare e nessuna chiamata va agli endpoint nuovi. Test nel Task 3.

---

### Task 1: Modelli, API e testi

**Files:**
- Create: `lib/core/social/notifications_api.dart`, `lib/core/social/notifications_models.dart`, `lib/features/inbox/notification_text.dart`
- Modify: `lib/core/social/inbox_models.dart` (10 classi `final` nuove e il loro ramo nello `switch` di `parse`), `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `test/core/social/notifications_api_test.dart`, `test/core/social/inbox_models_test.dart`, `test/features/inbox/notification_text_test.dart`

**Interfaces:**
- Produces:
  - `class NotificationTypePref { final String type; final bool enabled; }`;
  - `class NotificationsInfo { final String vapidPublicKey; final List<NotificationTypePref> types; }`;
  - `NotificationsApi`:
    - `Future<NotificationsInfo> get()`;
    - `Future<void> setEnabled(String type, bool enabled)`;
    - `Future<void> subscribe({required String endpoint, required String p256dh, required String auth, required String language})`;
    - `Future<void> unsubscribe(String endpoint)`.

    Stesso schema di `PluginAdminApi` / `SocialApi`.
  - Voci nuove: `RequestApprovedEntry` e `RequestDeclinedEntry` (campi di `RequestAvailableEntry`), `DownloadNeedsYouEntry(title, reason)`, `DownloadStalledEntry(title)`, `LightenBlockedEntry(title)`, `SpaceOperationFailedEntry`, `DiskAlmostFullEntry(percent)`, `RecoveryStartedEntry(userName)`, `RecoveryBlockedEntry(userName?, everyone)`, `RestartPendingEntry`. Ognuna ha `alertKey` se il JSON lo porta.
  - `class NotificationText { final String title; final String body; final String route; }`.
  - `NotificationText notificationTextOf(InboxEntry entry, AppLocalizations l)`: vale per **tutti** i 20 tipi, con i testi e le rotte del 31a.

- [ ] **Step 1: test che falliscono**
  - **Parse:** un JSON per ogni tipo nuovo dà la classe giusta. Un tipo sconosciuto continua a dare quello che dà oggi.
  - **API:**
    - `get` legge `VapidPublicKey` e `Types` nell'ordine;
    - `setEnabled` fa `PUT …/Notifications/Types/DiskAlmostFull` con `{"Enabled":false}`;
    - `subscribe` manda i quattro campi;
    - `unsubscribe` fa `DELETE` con `{"Endpoint":…}`.
  - **Testi** (it e en):
    - `DownloadNeedsYouEntry(title:'Severance S02', reason:'GrabRefused')` → `Download da sistemare` / `Severance S02 — grab rifiutato` / `/admin?tab=downloads`;
    - `RequestAvailableEntry` senza `itemId` → rotta `/requests`;
    - `RecoveryBlockedEntry(everyone:true)` → `Troppi tentativi: bloccato per tutti`.
- [ ] **Step 2:** `flutter test` sui tre file. Expected: FAIL.
- [ ] **Step 3: implementa.** Chiavi arb con prefisso `notif…`. `{…}` diventano placeholder.
- [ ] **Step 4:** `flutter gen-l10n` e i test. Expected: PASS.
- [ ] **Step 5: commit** `feat(app): modelli, API e testi delle notifiche`.

### Task 2: Le voci nuove nella cassetta

**Files:**
- Create: `lib/features/inbox/inbox_alert_rows.dart`
- Modify: `lib/features/inbox/inbox_panel.dart` (lo switch delle righe), `lib/features/inbox/inbox_request_rows.dart` (Approved/Declined come Available)
- Test: `test/features/inbox/inbox_alert_rows_test.dart`

**Interfaces:**
- Consumes: `notificationTextOf` (Task 1).

- [ ] **Step 1: test che falliscono**
  - ogni tipo nuovo mostra il titolo e il testo di `notificationTextOf`;
  - un tocco porta a `route` con `context.go`;
  - nel layout stretto (`FormFactor.compact`) il testo va a capo senza overflow, con larghezza 360;
  - `RequestApprovedEntry` mostra la locandina come `RequestAvailable`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa** riusando la riga generica della cassetta (icona, testo, ora con `inbox_time.dart`). Icone Lucide:

  | Voci | Icona |
  |---|---|
  | download | `download` |
  | spazio | `hardDrive` |
  | recupero | `shieldAlert` |
  | riavvio | `rotateCw` |
- [ ] **Step 4:** PASS.
- [ ] **Step 5: commit** `feat(app): voci admin e richieste accettate o rifiutate nella cassetta`.

### Task 3: Sezione Notifiche, i tipi

**Files:**
- Create: `lib/features/settings/notifications_settings_section.dart`, `lib/features/settings/notification_prefs_controller.dart`
- Modify: `lib/features/settings/settings_screen.dart` (sezione dopo Account), arb
- Test: `test/features/settings/notifications_settings_section_test.dart`

**Interfaces:**
- Consumes: `NotificationsApi` (Task 1).
- Produces:
  - `notificationPrefsProvider`: `AsyncNotifier<NotificationsInfo>`;
  - `Future<bool> setEnabled(String type, bool enabled)`, ottimista. Se fallisce torna indietro e restituisce false, come `shareActivityProvider`;
  - `bool isEnabled(String type)`: vero finché le preferenze non sono caricate o il tipo non è nella lista.
  
  Il Task 4 aggiunge il blocco del dispositivo in cima alla sezione. Il Task 5 legge `isEnabled(type)`.

- [ ] **Step 1: test che falliscono**
  - si vedono solo i tipi che arrivano da `GET`, con le etichette dell'arb (tabella sotto);
  - un interruttore spento manda `setEnabled(…, false)`;
  - un errore lo rimette acceso e mostra il messaggio d'errore già usato da `ShareActivitySetting`;
  - senza `push` in `Features` la sezione non c'è.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.** Etichette, in tre gruppi: "Per te", "Richieste da approvare", "Admin". Si vede un gruppo solo se ha tipi.

  | Tipo | it | en |
  |---|---|---|
  | Invite | Inviti ai watch party | Watch party invites |
  | Announcement | Annunci | Announcements |
  | NewTitles | Nuovi titoli | New titles |
  | RequestAvailable | Richieste disponibili | Available requests |
  | RequestApproved | Richieste accettate | Approved requests |
  | RequestDeclined | Richieste rifiutate | Declined requests |
  | ContactReminder | Promemoria del contatto | Contact reminder |
  | Recommendation | Consigli degli amici | Friend recommendations |
  | MatchInvite | Inviti al match | Match invites |
  | ReportResolved | Segnalazioni chiuse | Closed reports |
  | RequestPending | Richieste da approvare | Requests to approve |
  | ReportPending | Segnalazioni nuove | New reports |
  | DownloadNeedsYou | Download da sistemare | Downloads that need you |
  | DownloadStalled | Download fermi | Stalled downloads |
  | LightenBlocked | Alleggerisci bloccati | Blocked lightens |
  | SpaceOperationFailed | Pulizie fallite | Failed cleanups |
  | DiskAlmostFull | Disco quasi pieno | Disk almost full |
  | RecoveryStarted | Recupero password avviato | Password recovery started |
  | RecoveryBlocked | Recupero password bloccato | Password recovery blocked |
  | RestartPending | Riavvio di Jellyfin | Jellyfin restart |
- [ ] **Step 4:** PASS.
- [ ] **Step 5: commit** `feat(app): preferenze delle notifiche`.

### Task 4: Web push, il dispositivo

**Files:**
- Create:
  - `web/push_sw.js`;
  - `lib/core/push/web_push.dart` (export condizionale), `web_push_web.dart`, `web_push_io.dart`;
  - `lib/features/settings/device_push_controller.dart`, `lib/features/settings/device_push_tile.dart`.
- Modify:
  - `lib/features/settings/notifications_settings_section.dart`;
  - `lib/features/auth/session_controller.dart` (`logout`, `removeProfile`);
  - `lib/features/settings/locale_controller.dart` (al cambio di lingua);
  - `deploy/wonderflix.conf`, `deploy/wonderflix-prova.conf`: `push_sw\.js` nella regex dei file `no-cache`;
  - arb.
- Test: `test/features/settings/device_push_controller_test.dart`, `test/features/settings/device_push_tile_test.dart`

**Interfaces:**
- Produces:
  - `enum PushAvailability { unsupported, needsHomeScreen, denied, ready, active }`;
  - `abstract interface class WebPush`:
    - `Future<PushAvailability> availability()`;
    - `Future<PushKeys?> subscribe(String vapidPublicKey)`: chiede il permesso, registra `push_sw.js` e iscrive, con `userVisibleOnly: true`. Restituisce null se il permesso è negato;
    - `Future<void> unsubscribeBrowser()`.
    
    `class PushKeys { endpoint, p256dh, auth }`. Lo stub `io` dice sempre `unsupported`.
  - `devicePushProvider`: `AsyncNotifier<PushAvailability>`, con `activate()`, `deactivate()` e `Future<void> forgetUser(String userId)`.
    - L'endpoint si salva in `shared_preferences` con chiave `push.endpoint.<userId>`.
    - `deactivate` e `forgetUser` fanno il `DELETE` sul plugin e tolgono la chiave. Non chiamano `unsubscribeBrowser`, perché un altro profilo può usare lo stesso endpoint (decisione 5 del 31a). `unsubscribeBrowser` si chiama solo se nessuna chiave `push.endpoint.*` resta.

- [ ] **Step 1: test che falliscono** (`WebPush` finto)
  - **Stati del riquadro:**

    | Stato | Cosa mostra |
    |---|---|
    | `unsupported` | `Le notifiche non sono disponibili in questo browser` |
    | `needsHomeScreen` | `Per ricevere le notifiche aggiungi WonderFlix alla schermata Home e aprilo da lì` |
    | `denied` | `Notifiche bloccate: riattivale dalle impostazioni del telefono o del browser` |
    | `ready` | pulsante `Attiva notifiche su questo dispositivo` |
    | `active` | `Notifiche attive su questo dispositivo` + pulsante `Disattiva` |

    In inglese: "Notifications aren't available in this browser", "To get notifications, add WonderFlix to your Home Screen and open it from there", "Notifications are blocked: turn them back on in your phone or browser settings", "Turn on notifications on this device", "Notifications are on for this device", "Turn off".
  - `activate`: `subscribe` → `NotificationsApi.subscribe` con la lingua dell'app → stato `active`. Con `subscribe` che restituisce null → `denied`, senza chiamate al plugin.
  - Al cambio di lingua con stato `active` parte di nuovo `subscribe` sul plugin con la lingua nuova.
  - `logout` chiama `forgetUser` **prima** di `_auth.logout()`. Con il `DELETE` che lancia, il logout avviene lo stesso.
  - Il riquadro non c'è sull'app Windows (`unsupported` dallo stub `io`, senza testo).
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.**
  - `web_push_web.dart`:
    - registra con `navigator.serviceWorker.register('push_sw.js')`, relativo al `<base href>`;
    - converte la chiave con `Uint8Array` da base64url;
    - legge le chiavi con `getKey('p256dh')` / `getKey('auth')` in base64url;
    - `needsHomeScreen` quando c'è `navigator.standalone` (iOS) ed è falso, oppure quando manca `PushManager` su iOS;
    - `denied` da `Notification.permission`;
    - `active` se c'è un'iscrizione del browser **e** la chiave del profilo.
    
    `requestPermission` parte direttamente dall'`onPressed` del pulsante, senza `await` prima. Se il Task 1 del 31a ha detto che il tocco Flutter non basta, usa un `<button>` HTML vero sopra il pulsante, con `HtmlElementView`, solo per questo passo.
  - `push_sw.js`:
    - `push` → `self.registration.showNotification(title, {body, tag, data: {route}})`, **sempre**, anche se il JSON è rotto: titolo `WonderFlix`;
    - `notificationclick` → chiude la notifica. Se una finestra con lo scope è aperta: `focus()` e `navigate(scope + '#' + route)`. Altrimenti `clients.openWindow(scope + '#' + route)`.
- [ ] **Step 4:** PASS, poi `flutter analyze`.
- [ ] **Step 5: commit** `feat(app): notifiche push sul web`.

### Task 5: Notifiche di Windows

**Files:**
- Create: `lib/features/inbox/inbox_toaster.dart`, `lib/features/inbox/windows_toasts.dart` (export condizionale, `_io`/`_web`)
- Modify:
  - `pubspec.yaml` (`local_notifier: ^0.1.6`);
  - `lib/features/inbox/inbox_controller.dart`: le voci arrivate con `InboxChangedEvent`;
  - `lib/app/platform_startup_io.dart`: `localNotifier.setup(appName: 'WonderFlix', shortcutPolicy: ShortcutPolicy.requireCreate)`;
  - la shell, dove si avvia `InboxToaster`.
- Test: `test/features/inbox/inbox_toaster_test.dart`

**Interfaces:**
- Consumes: `notificationTextOf`, `notificationPrefsProvider.isEnabled`.
- Produces:
  - `InboxController` espone `Stream<InboxEntry> arrivals`: le voci con `seq` più alto del massimo visto, **solo** per i ricaricamenti causati da `InboxChangedEvent`. Il primo caricamento, il cambio di profilo e i ricaricamenti alla riconnessione aggiornano soltanto il massimo;
  - `abstract interface class Toasts { void show(String title, String body, void Function() onClick); }`, con lo stub web che non fa niente.

- [ ] **Step 1: test che falliscono**
  - `arrival_afterInboxChanged_toasts`;
  - `firstLoad_noToast`;
  - `reconnectReload_noToast`, anche con 5 voci nuove;
  - `disabledType_noToast`;
  - `click_focusesWindowAndGoesToRoute`: `windowManager.show()` + `focus()` e `router.go(route)`;
  - `web_noToasts`.
- [ ] **Step 2:** FAIL.
- [ ] **Step 3: implementa.** Prima di scegliere `ShortcutPolicy`, controlla che la notifica compaia anche con l'app installata dall'installer Inno Setup (`installer/wonderflix.iss`) e lanciata dalla sua scorciatoia.
- [ ] **Step 4:** PASS, poi la build di release Windows di "Global Constraints".
- [ ] **Step 5: commit** `feat(app): notifiche di Windows dalla cassetta`.

### Task 6: Versione, checklist e prova sul sito di prova

**Files:**
- Modify: `pubspec.yaml` (0.26.0), `docs/RELEASING.md` (le prove a mano della spec §5), la spec (stato "realizzata con i piani 31a e 31b")

- [ ] **Step 1:** versione 0.26.0. Poi `flutter gen-l10n`, `flutter analyze` e `flutter test`. Expected: tutto verde.
- [ ] **Step 2: sito di prova.**
  1. Build web con `--base-href /wonderflix-prova/` e pubblicazione con tar-over-ssh, come in `docs/RELEASING.md`.
  2. Copia `deploy/wonderflix-prova.conf` sul seedbox e riavvia nginx con `app-nginx restart`, dopo il controllo della sintassi (`/usr/sbin/nginx -t -p $HOME/.apps/nginx/ -c nginx.conf`).
  3. `curl -sI https://hashvps.proton.usbx.me/wonderflix-prova/push_sw.js`. Expected: 200 con `Cache-Control: no-cache`.
- [ ] **Step 3: prova a mano dell'utente** con la checklist della spec §5: iPhone dalla Home, Chrome/Edge sul PC, app Windows. Va fatta con il plugin 1.17.0 del 31a sul seedbox. Si unisce a `main` solo dopo il suo ok.
- [ ] **Step 4: commit** `chore(app): versione 0.26.0 con le notifiche push`.

# WonderFlix TV 3: autorizzare Quick Connect da WonderFlix

Requisito: design TV (`docs/superpowers/specs/2026-11-07-wonderflix-tv-design.md`, "Accesso e account", "Conferma dei codici su PC e web"), idea 16 in `docs/IDEE.md`. Branch `feat/tv-quick-connect-authorize`.

Oggi la TV mostra un codice Quick Connect e il suggerimento "Da telefono o browser già collegati a WonderFlix apri Impostazioni → Quick Connect", ma il codice si conferma solo da jellyfin-web. Questo piano aggiunge la conferma in WonderFlix (PC, web, telefono).

## Decisioni

1. **Dove:** Impostazioni → Account, un pulsante "Quick Connect" (icona `LucideIcons.monitorSmartphone` o simile) accanto a "Cambia password", solo con un utente aperto. Coerente col testo che la TV già mostra. Sulla TV la sezione Account è nascosta: lì il pulsante non c'è.
2. **Finestra** "Autorizza un dispositivo" sul modello di `ChangePasswordDialog` (`showWfDialog`, `ErrorBanner`, `PopScope` mentre è in volo): un testo breve ("Scrivi il codice mostrato dall'altro dispositivo"), un campo codice (tastiera numerica, spazi tolti), Annulla / Autorizza. Riuscito: si chiude e Impostazioni mostra uno SnackBar "Dispositivo autorizzato".
3. **API:** `AuthApi.authorizeQuickConnect(String code)` → `POST /QuickConnect/Authorize?code=…` (Jellyfin 10.11, utente della sessione; risponde `true`).
4. **Errori:**
   - codice vuoto: errore sul campo, nessuna richiesta;
   - 404 (`NotFoundException`): codice sbagliato o scaduto, errore sul campo; `quietStatuses: {404}` (esito atteso);
   - Quick Connect spento sul server: Jellyfin risponde **401** ("Quick connect is disabled"), che in `JellyfinHttp` farebbe scadere la sessione (`onUnauthorized`). Quindi prima di autorizzare si chiama `quickConnectEnabled()`: se `false`, banner con `quickConnectDisabled` e nessuna `Authorize`. Resta una finestra di millisecondi se l'admin lo spegne in mezzo: accettata;
   - 502/503/504 come in `ChangePasswordDialog` ("non raggiungibile"), il resto con `describeError`.
5. Testi nuovi in `app/l10n/app_it.arb` e `app_en.arb` (poi `flutter gen-l10n`).

## Passi

1. `AuthApi.authorizeQuickConnect` + test in `test/core/jellyfin/` (percorso, query `code`, metodo POST) sul modello dei test esistenti di `AuthApi`.
2. `features/account/authorize_device_dialog.dart` (`showAuthorizeDeviceDialog(context) → Future<bool>`) + test widget: codice vuoto, riuscito (pop true), 404 → errore sul campo, Quick Connect spento → banner e nessuna Authorize.
3. Pulsante in `AccountSettingsSection` + SnackBar; aggiornare `test/features/settings/account_settings_section_test.dart` (il pulsante apre la finestra).
4. `docs/RELEASING.md`: riga di checklist manuale "Quick Connect: codice generato sulla TV confermato da Impostazioni → Account su Windows/web; codice sbagliato; Quick Connect spento". Nessun bump di versione in questo branch (lo fa il rilascio). Idea 16 in `docs/IDEE.md`: segnarla fatta come le altre idee fatte.
5. `flutter gen-l10n`, `flutter analyze`, `flutter test`.

## Prova a mano

Fire Stick: login → scheda Quick Connect → codice. Build Windows release: Impostazioni → Account → Quick Connect → codice → la TV entra. Poi un codice inventato (errore sul campo).

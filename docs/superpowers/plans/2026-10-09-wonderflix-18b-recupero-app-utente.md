# WonderFlix — Piano 18b: recupero e cambio della password nell'app (lato utente)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte dell'utente della Spec L nell'app:
- **Impostazioni → Account**, ora in cima: "Cambia password" e i **contatti per il recupero** (Discord ed email), con la password attuale per collegare, sostituire e scollegare;
- **"Password dimenticata?"** nell'accesso: il codice ai contatti collegati, la password nuova e l'accesso con quella;
- **la voce della cassetta** "Proteggi il tuo account";
- `AccountApi`, `AuthApi.changePassword`, `SocialFeatures.account`, `redact.dart`, i testi.

Niente release: l'app 0.12.0 esce con il plugin 1.6.0 alla fine del 18c.

**Spec:** `docs/superpowers/specs/2026-10-09-wonderflix-recupero-password-design.md` (§7.6, §8, §9.1–§9.4, §10, §11, §12).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 10):
1. **Il recupero è una seconda vista di `LoginScreen`, non la rotta `/login/recover`.** `sessionRedirect` manda chi non è dentro a `/login` e basta (una rotta in più andrebbe tolta dal redirect e provata nel router), e con Quick Connect il modulo sta in una scheda alta 300 px: il recupero prende tutto il pannello. "Torna all'accesso" (freccia) riporta al modulo con il nome scritto.
2. **Il promemoria della cassetta apre `/settings`**, senza `?section=account`: la sezione Account è la prima della pagina.
3. **La password attuale resta nella finestra di collegamento fra i due passi** (nello `State`, fino alla chiusura): "Rimanda il codice" rifà `Start`, che la vuole di nuovo. Ogni rinvio conta un controllo della password e un invio dell'ora (nota del 18a).
4. **I testi del 429** dicono "più tardi" (i limiti arrivano a un giorno, nota del 18a): "Troppe richieste: riprova più tardi" per collegamento, scollegamento e primo passo del recupero; "Troppi tentativi: riprova più tardi o contatta l'amministratore" per il secondo passo (nel piano di partenza era "riprova tra un'ora": falso con un limite giornaliero, vedi la "Revisione finale" nella 13). Al posto di "Aspetta un momento prima di riprovare" (§9.2, §9.3, §10).
5. **`AccountApi` usa il client principale** (`jellyfinHttpProvider`): nell'accesso `prepareLogin` ha già tolto il token, quindi `Recovery/*` partono senza. È il "client senza sessione" di §9.1.
6. **`AccountFailure`** (errori tipizzati di §9.1):
   - 404 → `unavailable` (plugin vecchio);
   - i `Code` di §7.6 → il loro valore (`channelOff`, `invalidTarget`, `memberNotFound`, `wrongPassword`, `dmClosed`, `sendFailed`, `invalidCode`, `weakPassword`), 429 → `rateLimited`;
   - ogni altro 400, 401, 403 e 409, anche senza `Code` (`Invalid`, `NotAllowed`, il 400 di ASP.NET per un JSON rotto) → `invalid`;
   - 500 → `serverError` (dalla review del Gruppo A): in `Recovery/Complete` vuol dire che il codice è già usato (§11) e diventa "Cambio non riuscito: chiedi un nuovo codice";
   - 502, 503 e 504 senza il loro `Code` (nginx durante un riavvio), rete, forma inattesa → `network`: "WonderFlix non è raggiungibile. Controlla la connessione." (nei contatti e nei due passi del recupero). Nel secondo passo conta di più, perché il codice può essere ancora buono e chiederne un altro costa uno dei limiti di `Start`.
7. **`startLink` non restituisce `ExpiresAt`** e `AccountContacts` non ha `VerifiedAt`: l'app non li mostra. Il conto dei 60 s di "Rimanda" è dell'app.
8. **"Scollega" c'è anche su un canale spento**, se il contatto c'è (i contatti restano, §11): l'utente può toglierlo. "Collega"/"Cambia" solo con il canale acceso.
9. **Testi in più** rispetto a §10: il suggerimento sotto la password attuale ("Lascia vuoto se l'account non ha una password"), quello sotto il nome Discord, "Nome utente Discord non valido", "Non è stato possibile leggere i contatti", "Contatto collegato" / "Contatto scollegato", "Torna all'accesso", "Scrivi il nome utente", "Cambio non riuscito: chiedi un nuovo codice", "Password cambiata: accedi con quella nuova." (dalla review del Gruppo C), "Annulla", "Collega {canale}", il testo della finestra di scollegamento.
10. **`changePassword(userId, {currentPassword, newPassword})`:** senza `currentPassword` è l'"Imposta password" dell'admin del 18c. Qui si usa solo con.
11. **`redact.dart`:** i nuovi nomi entrano nella regola del JSON (come `Pw`), non nella forma a mappa.
12. **Il promemoria vero si prova al rilascio (18c).** Sul server i promemoria restano spenti (`ContactReminderDays` = 0, §15): qui la voce della cassetta la coprono i test.
13. **Dalle review dei gruppi** (il codice dei task sotto è quello di partenza: dove differisce, vale questa lista):
    - **Gruppo A:**
      - `changePassword` usa l'elemento null-aware `'CurrentPw': ?currentPassword` (lint `use_null_aware_elements`);
      - `AccountFailure.serverError` per il 500 (decisione 6); i Task 6 e 8 sotto sono già aggiornati;
      - `AccountContactsController.reload` tiene il `Ref` di partenza: se a metà rilettura cambia l'utente, i contatti vecchi non si scrivono. Test in più: la rilettura senza spinner, la funzione `account` che si accende con il provider aperto, il cambio di utente;
      - `FakeAccountApi`: `gate` blocca solo le chiamate che cambiano qualcosa, `contactsGate` la lettura dei contatti (un `gate` su `contacts()` lascerebbe lo spinner e `pumpAndSettle` andrebbe in timeout). Il Task 6 ha un test del doppio clic con `gate`;
      - `redact.dart`: test che un `"Code"` numerico e la forma a mappa `{code: 4000}` (i frame di Discord IPC) restano com'erano;
      - Jellyfin risponde 403 a `POST /Users/Password` anche a un utente senza `EnableUserPreferenceAccess`: l'app direbbe "Password attuale sbagliata". Raro, accettato;
      - per il 18c: sulla propria riga Jellyfin chiede `CurrentPw` anche a un admin ("Imposta password" senza va escluso lì); `NotAllowed`, `NoContacts` e `UnknownUser` vorranno valori loro in `AccountFailure`.
    - **Gruppo B** (il Task 8 sotto è già aggiornato):
      - `pumpAndSettle` in due test del cambio password: dio con l'adapter finto vuole che il tempo avanzi;
      - `Align(centerLeft)` attorno ad `AccountContactsBlock`: dentro una `Column` `stretch` il `maxWidth` non valeva. Test della larghezza;
      - `errorMaxLines` e `helperMaxLines` (costanti `accountErrorMaxLines`, `accountHelperMaxLines` in `account_texts.dart`) nei campi delle finestre e del recupero: l'errore "Non ti trovo nel server Discord" usciva troncato;
      - `PopScope(canPop: !_busy)` e "Annulla" spento nelle tre finestre durante la richiesta, come `request_seasons.dart`: prima Esc chiudeva la finestra e la password cambiava senza l'avviso;
      - `ResendCodeButton.onResend` può essere `null` (spento mentre un'altra richiesta è in volo) e ha un `try/finally`; il conto riparte dopo un invio riuscito o dopo un 429, non dopo un altro errore;
      - collegamento: `wrongPassword` al rinvio riporta al primo passo, con l'errore sotto la password e il fuoco sulla password (testo selezionato); i pulsanti delle righe dicono il canale allo screen reader;
      - recupero (Task 8, già aggiornato): "Torna all'accesso" è spento durante una richiesta; se l'accesso fallisce dopo un cambio riuscito, "Cambia password" riprova solo l'accesso (`_changedTo`), perché il codice è già usato (poi cambiato dal Gruppo C: vista "password cambiata" con "ACCEDI").
    - **Gruppo C:**
      - `inboxEntryFromJson` usa l'elemento null-aware `?AccountChannel.fromWire(raw)` (lint `use_null_aware_elements`);
      - recupero, stato "password cambiata": se l'accesso fallisce dopo un cambio riuscito, il secondo passo mostra solo "Password cambiata: accedi con quella nuova." (testo nuovo `recoveryChanged`), l'errore dell'accesso e "ACCEDI", che riprova l'accesso con la password già cambiata. Niente campi né "Rimanda": prima una password riscritta lì veniva ignorata in silenzio;
      - nella vista "password cambiata" "ACCEDI" riceve il fuoco a fine accesso (`_signInFocus` con `addPostFrameCallback`: un `autofocus` non basta, perché il pulsante nasce spento durante l'accesso). Test "accesso lento dopo il cambio" (commit `13fc473`);
      - `mounted` dopo `completeRecovery`;
      - "Password dimenticata?" spento mentre un accesso è in volo;
      - test in più: il link senza `supportUrl`, `weakPassword` dal server, `network` al primo passo;
      - nei finti dei test: `FakeSessionController.loginGate` tiene l'accesso in volo; `pumpApp` non aggiunge `testAppConfig` se gli `overrides` hanno già un `appConfigProvider` (il test senza `supportUrl`: due override dello stesso provider farebbero lanciare il container);
      - accettato: se si è già in Impostazioni, il clic sul promemoria lascia la pagina dov'è (decisione 2, niente `?section=account`).
    - **Revisione finale** (prima della prova a mano; il corpo dei task sopra ha ancora il testo di partenza):
      - il fuoco dopo un errore sotto un campo, come in `LinkContactDialog` (`17e9faf`): Invio nell'ultimo campo toglie il fuoco al campo, e quando l'errore arrivava bisognava cliccare di nuovo. Ora `unlink_contact_dialog.dart` (`wrongPassword`), `change_password_dialog.dart` (403, sulla password attuale) e `recovery_panel.dart` (`invalidCode`, sul codice) danno fuoco e testo selezionato al campo, e così `link_contact_dialog.dart` per tutti i suoi campi: il nome o l'email (`invalidTarget`, `memberNotFound`), la password (`wrongPassword`, già così) e il codice (`invalidCode`). Lo fa l'helper `focusAndSelectAfterFrame` (`lib/features/account/field_focus.dart`). Un test per ognuno, con l'Invio vero (`receiveAction(done)`) e `expectFocusedAndSelected` (`test/support/field_focus.dart`);
      - dopo un "Rimanda il codice" riuscito il campo del codice si svuota, nel collegamento e nel recupero: il codice nuovo sostituisce il vecchio sul server, e "Conferma" dava un "Codice non valido o scaduto" che confondeva. Dopo un 429 o un altro errore nessun codice è partito e quello scritto resta (un test per entrambi i casi, in tutti e due i posti);
      - il cambio password con 502, 503 o 504 (nginx durante un riavvio) dice "WonderFlix non è raggiungibile. Controlla la connessione.", come i contatti, e non "Qualcosa è andato storto" (`restartGatewayStatuses`, un `switch` con guardia nel `catch`: in Dart non esiste `catch … when`);
      - test di sicurezza: le chiamate del recupero partono senza token (l'header `Authorization` non ha `Token=`) dopo `setCredentials(token: null, …)`, come fa `prepareLogin`. Il test passava già: protegge una proprietà che vale;
      - `recoveryTooMany` è "Troppi tentativi: riprova più tardi o contatta l'amministratore" (en "Too many attempts: try again later or contact the admin"): "riprova tra un'ora" era falso quando scatta un limite giornaliero (decisione 4);
      - accettato: un 429 al primo passo del recupero lascia al primo passo, anche se un codice chiesto poco prima è in arrivo (spec §11);
      - accettato: gli stili ripetuti (`_mutedStyle` del recupero, il titolo delle finestre) restano com'erano, uno per file;
      - accettato: nel cambio password e nel recupero gli errori controllati dall'app ("Almeno 6 caratteri", "Le password non coincidono", il codice vuoto) e il `weakPassword` del server non rimettono il fuoco sul campo; nel collegamento sì, perché passano tutti da `_show`.

**Architecture:**
- **Dati** (`lib/core/social/`): `account_models.dart` (`AccountChannel`, `AccountContacts`, `accountMinPasswordLength`), `account_api.dart` (`AccountApi`, `AccountFailure`, `AccountException`); `AuthApi.changePassword`; `PluginFeatures.account` e `SocialFeatures.account`; `ContactReminderEntry` in `inbox_models.dart`.
- **Account** (`lib/features/account/`):
  - `account_providers.dart`: `accountApiProvider`, `accountAvailableProvider`, `AccountContactsController` / `accountContactsProvider`;
  - `account_texts.dart`: nomi dei canali e testi degli errori;
  - `resend_code_button.dart`: "Rimanda il codice" a tempo;
  - `change_password_dialog.dart`, `link_contact_dialog.dart`, `unlink_contact_dialog.dart`: le finestre;
  - `account_contacts_block.dart`: le righe dei contatti.
- **Impostazioni:** `lib/features/settings/account_settings_section.dart` (il contenuto di oggi della sezione Account, più password e contatti), in cima a `SettingsScreen`.
- **Accesso:** `lib/features/auth/recovery_panel.dart`; `LoginScreen` lo mostra al posto del modulo; `PasswordLoginForm.onForgotPassword`.
- **Cassetta:** `lib/features/inbox/inbox_account_row.dart`; due righe in `inbox_panel.dart`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.3.2, go_router, dio, lucide_icons_flutter 3.1.20, url_launcher.

**Worktree:** `.claude/worktrees/piano-18b`, branch `feat/piano-18b`. **Base:** `main` con questo piano. **Test a inizio piano:** 2463 Flutter (fine del 17c; l'orchestratore lo conferma nel worktree) e 748 plugin (il plugin qui non cambia).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-18b`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
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
- **Spinner e `pumpAndSettle`:** un `CircularProgressIndicator` senza valore non si ferma mai, quindi `pumpAndSettle` va in timeout. Mentre c'è un indicatore (per esempio i contatti in caricamento), usa `pump()`. "Rimanda il codice" ha un timer di un secondo che finisce da solo: `pumpAndSettle` lì funziona.
- **Provider:** nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`. I container dei test hanno `retry: (_, _) => null`.
- **Segreti:** password e codici non vanno mai nei log né in `toString`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **Plugin 1.6.0 (già sul server, build di prova 1.6.0.0).** Base `WonderFlixWatchParty/Account`, JSON in PascalCase, errori `{Code}` (§7.6):
  - `GET Contacts` → `{Channels: {Discord: bool, Email: bool}, Discord: {Name, VerifiedAt}?, Email: {Address, VerifiedAt}?}` (`Protocol/AccountDtos.cs`);
  - `POST Contacts/{Discord|Email}/Start {Target, Password, Language}` → 202 `{ExpiresAt}`;
  - `POST Contacts/{canale}/Confirm {Code}` → 200 come `GET Contacts`;
  - `POST Contacts/{canale}/Unlink {Password}` → 204;
  - `POST Recovery/Start {Username, Language}` → 202 sempre (anonimo);
  - `POST Recovery/Complete {Username, Code, NewPassword, Language}` → 204 (anonimo);
  - stati: `ChannelOff` 503, `RateLimited` 429, `DmClosed` 409, `SendFailed` 502, `WrongPassword` e `NotAllowed` 403, tutti gli altri 400. Il plugin non risponde mai 404.
- **`Code` va come stringa JSON:** un numero fa rispondere ad ASP.NET un 400 senza `{Code}` (ProblemDetails), e lo zero iniziale conta.
- **La voce della cassetta** (`Hub/InboxService.AddContactReminderAsync`, `Protocol/InboxDtos.cs`): `{Type: "ContactReminder", Id, Seq, CreatedAt, Read, Channels: ["Discord", "Email"]}`, con i canali configurati.
- **Jellyfin 10.11.9, `POST /Users/Password?userId=`** (`UserController.UpdateUserPassword`): corpo `{CurrentPw, NewPw}`. Per la propria password controlla sempre `CurrentPw` (vuota per un account senza password) e risponde 403 se è sbagliata. Poi chiude le altre sessioni dell'utente e tiene quella della richiesta (`RevokeUserTokens(user.Id, currentToken)`). 204 se riesce.
- **Il 403 non chiude la sessione:** `JellyfinHttp` chiama `onUnauthorized` solo per un 401.
- **Accesso:**
  - `sessionRedirect` (`lib/app/router.dart`) manda `SessionSignedOut` a `/login`;
  - `LoginScreen.initState` chiama `prepareLogin`, che toglie il token dal client (`AuthService.prepareLogin`), quindi `accountApiProvider` parte senza;
  - `AuthService.loginWithPassword` toglie gli spazi dal nome;
  - con Quick Connect acceso il modulo sta in una `TabBarView` alta 300 px.
- **Cassetta:**
  - l'unico `switch` sui tipi di voce è in `lib/features/inbox/inbox_panel.dart` (icona e contenuto), esaustivo sulla classe sigillata `InboxEntry`: una voce nuova va aggiunta lì nello stesso commit;
  - `InboxRequestIcon` (`inbox_request_rows.dart`) è l'icona tonda generica.
- **Impostazioni:** `test/features/settings/settings_test.dart` monta `SettingsScreen` 8 volte senza `socialAvailabilityProvider` finto. La sezione Account legge `accountAvailableProvider`: in quei test va sostituito con `false` (Task 7).
- **Test:**
  - `FakeAdapter` (`test/support/fake_adapter.dart`) registra le richieste (`RequestOptions`) e risponde con `FakeResponse(status, body)`;
  - `pumpApp` (`test/support/pump_app.dart`) monta in italiano (`languageCode` `it`), con `testAppConfig` che ha `supportUrl`;
  - `FakeSessionController.loginWithPassword` registra `(nome, password)` in `loginAttempts`;
  - `testUser` = `JellyfinUser(id: 'u1', name: 'Mario')`.
- **Icone verificate in `lucide_icons_flutter` 3.1.20:** `keyRound`, `shieldCheck`, `messageCircle`, `mail`, `arrowLeft`.
- **ARB:** oggi `app_it.arb` e `app_en.arb` hanno le stesse 564 chiavi.
- **Riverpod:** `AsyncNotifier` con `AsyncNotifierProvider.autoDispose`, come `LanguagePreferencesController` (`lib/features/settings/language_preferences.dart`).

---

## Gruppo A — dati

### Task 1: i testi

**Files:**
- Modify: `l10n/app_it.arb`
- Modify: `l10n/app_en.arb`
- Create: `test/app/l10n_plan18b_test.dart`

- [ ] **Step 1: il test**

Crea `test/app/l10n_plan18b_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 18b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.settingsChangePassword, 'Cambia password');
    expect(it.accountWrongPassword, 'Password attuale sbagliata');
    expect(it.accountPasswordChanged,
        'Password cambiata. Gli altri dispositivi dovranno rientrare.');
    expect(it.accountLinked('garg'), 'Collegato: garg');
    expect(it.accountLinkTitle('Discord'), 'Collega Discord');
    expect(it.accountUnlinkTitle('Email'), 'Scollegare Email?');
    expect(it.accountCodeSentEmail('a@example.com'),
        'Ti abbiamo mandato un codice a a@example.com');
    expect(it.accountResendIn(42), 'Rimanda tra 42 s');
    expect(it.accountErrorRateLimited, 'Troppe richieste: riprova più tardi');
    expect(it.recoveryCodeSent,
        "Se l'account esiste e ha un contatto collegato, ti abbiamo mandato "
        'un codice su Discord o per email.');
    expect(it.recoveryTooMany,
        "Troppi tentativi: riprova tra un'ora o contatta l'amministratore");
    expect(it.inboxContactReminderTitle, 'Proteggi il tuo account');
    expect(en.settingsChangePassword, 'Change password');
    expect(en.accountResendIn(42), 'Resend in 42 s');
    expect(en.inboxContactReminderTitle, 'Protect your account');
  });

  test('app_it.arb e app_en.arb hanno le stesse chiavi', () {
    Set<String> keys(String path) => {
          for (final key
              in (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)
                  .keys)
            if (!key.startsWith('@')) key,
        };
    expect(keys('l10n/app_en.arb'), keys('l10n/app_it.arb'));
  });
}
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/app/l10n_plan18b_test.dart`
Expected: FAIL in compilazione (`settingsChangePassword` non esiste). Il secondo test da solo passerebbe.

- [ ] **Step 3: italiano**

In `l10n/app_it.arb`, dopo l'ultima voce (`"@profileImageGalleryItem": …`, aggiungi la virgola in fondo a quella riga), prima della `}` finale:

```json
  "settingsChangePassword": "Cambia password",
  "accountCurrentPassword": "Password attuale",
  "accountNoPasswordHint": "Lascia vuoto se l'account non ha una password",
  "accountNewPassword": "Nuova password",
  "accountConfirmPassword": "Conferma la password",
  "accountPasswordTooShort": "Almeno 6 caratteri",
  "accountPasswordsDiffer": "Le password non coincidono",
  "accountWrongPassword": "Password attuale sbagliata",
  "accountPasswordChanged": "Password cambiata. Gli altri dispositivi dovranno rientrare.",
  "accountCancel": "Annulla",
  "accountContactsTitle": "Contatti per il recupero",
  "accountContactsHint": "Servono per recuperare la password se la dimentichi.",
  "accountContactsAdminHint": "Gli admin non possono usare il recupero automatico.",
  "accountContactsError": "Non è stato possibile leggere i contatti",
  "accountChannelDiscord": "Discord",
  "accountChannelEmail": "Email",
  "accountNotLinked": "Non collegato",
  "accountLinked": "Collegato: {name}",
  "@accountLinked": {"placeholders": {"name": {"type": "String"}}},
  "accountChannelOff": "Non disponibile su questo server",
  "accountLink": "Collega",
  "accountChange": "Cambia",
  "accountUnlink": "Scollega",
  "accountLinkTitle": "Collega {channel}",
  "@accountLinkTitle": {"placeholders": {"channel": {"type": "String"}}},
  "accountUnlinkTitle": "Scollegare {channel}?",
  "@accountUnlinkTitle": {"placeholders": {"channel": {"type": "String"}}},
  "accountUnlinkBody": "Non potrai più usarlo per recuperare la password. Scrivi la password attuale per confermare.",
  "accountDiscordName": "Nome utente Discord",
  "accountDiscordNameHint": "Il nome utente, non il nome visualizzato",
  "accountSendCode": "Invia codice",
  "accountCodeSentDiscord": "Ti abbiamo mandato un codice su Discord",
  "accountCodeSentEmail": "Ti abbiamo mandato un codice a {email}",
  "@accountCodeSentEmail": {"placeholders": {"email": {"type": "String"}}},
  "accountCode": "Codice",
  "accountConfirm": "Conferma",
  "accountResendCode": "Rimanda il codice",
  "accountResendIn": "Rimanda tra {seconds} s",
  "@accountResendIn": {"placeholders": {"seconds": {"type": "int"}}},
  "accountLinkedDone": "Contatto collegato",
  "accountUnlinkedDone": "Contatto scollegato",
  "accountErrorMemberNotFound": "Non ti trovo nel server Discord: usa il nome utente (non il nome visualizzato) e controlla di essere nel server",
  "accountErrorDmClosed": "Il bot non riesce a scriverti: in Discord abilita i messaggi diretti dai membri del server",
  "accountErrorInvalidEmail": "Email non valida",
  "accountErrorInvalidDiscordName": "Nome utente Discord non valido",
  "accountErrorSendFailed": "Invio non riuscito, riprova più tardi",
  "accountErrorRateLimited": "Troppe richieste: riprova più tardi",
  "accountErrorInvalidCode": "Codice non valido o scaduto",
  "recoveryTitle": "Recupera la password",
  "recoveryBack": "Torna all'accesso",
  "recoveryNameNeeded": "Scrivi il nome utente",
  "recoveryCodeSent": "Se l'account esiste e ha un contatto collegato, ti abbiamo mandato un codice su Discord o per email.",
  "recoveryNoContact": "Nessun contatto collegato?",
  "recoveryUnavailable": "Il recupero automatico non è disponibile su questo server: contatta l'amministratore",
  "recoveryTooMany": "Troppi tentativi: riprova tra un'ora o contatta l'amministratore",
  "recoveryFailed": "Cambio non riuscito: chiedi un nuovo codice",
  "inboxContactReminderTitle": "Proteggi il tuo account",
  "inboxContactReminderBoth": "Collega Discord o la tua email per recuperare la password se la dimentichi.",
  "inboxContactReminderDiscord": "Collega Discord per recuperare la password se la dimentichi.",
  "inboxContactReminderEmail": "Collega la tua email per recuperare la password se la dimentichi."
```

- [ ] **Step 4: inglese**

In `l10n/app_en.arb`, dopo l'ultima voce (`"profileImageGalleryItem": …`, aggiungi la virgola), prima della `}` finale:

```json
  "settingsChangePassword": "Change password",
  "accountCurrentPassword": "Current password",
  "accountNoPasswordHint": "Leave empty if the account has no password",
  "accountNewPassword": "New password",
  "accountConfirmPassword": "Confirm the password",
  "accountPasswordTooShort": "At least 6 characters",
  "accountPasswordsDiffer": "The passwords don't match",
  "accountWrongPassword": "Wrong current password",
  "accountPasswordChanged": "Password changed. Other devices will need to sign in again.",
  "accountCancel": "Cancel",
  "accountContactsTitle": "Recovery contacts",
  "accountContactsHint": "They let you recover your password if you forget it.",
  "accountContactsAdminHint": "Admins can't use automatic recovery.",
  "accountContactsError": "Couldn't load your contacts",
  "accountChannelDiscord": "Discord",
  "accountChannelEmail": "Email",
  "accountNotLinked": "Not linked",
  "accountLinked": "Linked: {name}",
  "accountChannelOff": "Not available on this server",
  "accountLink": "Link",
  "accountChange": "Change",
  "accountUnlink": "Unlink",
  "accountLinkTitle": "Link {channel}",
  "accountUnlinkTitle": "Unlink {channel}?",
  "accountUnlinkBody": "You won't be able to use it to recover your password. Enter your current password to confirm.",
  "accountDiscordName": "Discord username",
  "accountDiscordNameHint": "Your username, not your display name",
  "accountSendCode": "Send code",
  "accountCodeSentDiscord": "We sent you a code on Discord",
  "accountCodeSentEmail": "We sent a code to {email}",
  "accountCode": "Code",
  "accountConfirm": "Confirm",
  "accountResendCode": "Resend the code",
  "accountResendIn": "Resend in {seconds} s",
  "accountLinkedDone": "Contact linked",
  "accountUnlinkedDone": "Contact unlinked",
  "accountErrorMemberNotFound": "You're not in the Discord server: use your username (not your display name) and check that you joined the server",
  "accountErrorDmClosed": "The bot can't message you: in Discord, allow direct messages from server members",
  "accountErrorInvalidEmail": "Invalid email",
  "accountErrorInvalidDiscordName": "Invalid Discord username",
  "accountErrorSendFailed": "Sending failed, try again later",
  "accountErrorRateLimited": "Too many requests: try again later",
  "accountErrorInvalidCode": "Invalid or expired code",
  "recoveryTitle": "Recover your password",
  "recoveryBack": "Back to sign in",
  "recoveryNameNeeded": "Enter your username",
  "recoveryCodeSent": "If the account exists and has a linked contact, we sent you a code on Discord or by email.",
  "recoveryNoContact": "No linked contact?",
  "recoveryUnavailable": "Automatic recovery isn't available on this server: contact the admin",
  "recoveryTooMany": "Too many attempts: try again in an hour or contact the admin",
  "recoveryFailed": "Change failed: ask for a new code",
  "inboxContactReminderTitle": "Protect your account",
  "inboxContactReminderBoth": "Link Discord or your email to recover your password if you forget it.",
  "inboxContactReminderDiscord": "Link Discord to recover your password if you forget it.",
  "inboxContactReminderEmail": "Link your email to recover your password if you forget it."
```

- [ ] **Step 5: genera e prova**

```powershell
flutter gen-l10n
flutter test test/app/l10n_plan18b_test.dart
```

Expected: PASS (2 test).

- [ ] **Step 6: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add l10n test/app/l10n_plan18b_test.dart
git commit -m "feat(app): texts for password recovery and recovery contacts"
```

### Task 2: `AccountApi` e i modelli

**Files:**
- Create: `lib/core/social/account_models.dart`
- Create: `lib/core/social/account_api.dart`
- Create: `test/core/social/account_api_test.dart`

- [ ] **Step 1: il test**

Crea `test/core/social/account_api_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late AccountApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = AccountApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  Matcher fails(AccountFailure failure) => throwsA(isA<AccountException>()
      .having((e) => e.failure, 'failure', failure));

  test('contatti: canali del server e contatti verificati', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Channels': {'Discord': true, 'Email': false},
          'Discord': {'Name': 'garg', 'VerifiedAt': '2026-10-09T10:00:00+00:00'},
          'Email': null,
        });

    final contacts = await api.contacts();

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Account/Contacts');
    expect(contacts.isAvailable(AccountChannel.discord), isTrue);
    expect(contacts.isAvailable(AccountChannel.email), isFalse);
    expect(contacts.contactOf(AccountChannel.discord), 'garg');
    expect(contacts.contactOf(AccountChannel.email), isNull);
  });

  test('collegamento: Start con destinatario, password e lingua', () async {
    adapter.handler = (_) =>
        const FakeResponse(202, {'ExpiresAt': '2026-10-09T10:10:00+00:00'});

    await api.startLink(AccountChannel.email,
        target: 'a@example.com', password: 'vecchia', language: 'it');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path,
        '/WonderFlixWatchParty/Account/Contacts/Email/Start');
    expect(request.data,
        {'Target': 'a@example.com', 'Password': 'vecchia', 'Language': 'it'});
  });

  test('collegamento: Confirm manda il codice come stringa', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Channels': {'Discord': true, 'Email': true},
          'Email': {
            'Address': 'a@example.com',
            'VerifiedAt': '2026-10-09T10:00:00+00:00',
          },
        });

    final contacts = await api.confirmLink(AccountChannel.email, '012345');

    final request = adapter.requests.single;
    expect(request.path,
        '/WonderFlixWatchParty/Account/Contacts/Email/Confirm');
    // Una stringa: lo zero iniziale conta, e con un numero il plugin
    // risponderebbe 400 senza Code (spec L §7.6).
    expect(request.data, {'Code': '012345'});
    expect(contacts.contactOf(AccountChannel.email), 'a@example.com');
  });

  test('scollegamento: POST con la password, anche vuota', () async {
    await api.unlink(AccountChannel.discord, password: '');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path,
        '/WonderFlixWatchParty/Account/Contacts/Discord/Unlink');
    expect(request.data, {'Password': ''});
  });

  test('recupero: Start e Complete', () async {
    adapter.handler = (options) =>
        FakeResponse(options.path.endsWith('/Start') ? 202 : 204);

    await api.startRecovery(username: 'garg', language: 'en');
    await api.completeRecovery(
        username: 'garg',
        code: '000123',
        newPassword: 'nuova123',
        language: 'en');

    expect(adapter.requests[0].path,
        '/WonderFlixWatchParty/Account/Recovery/Start');
    expect(adapter.requests[0].data, {'Username': 'garg', 'Language': 'en'});
    expect(adapter.requests[1].path,
        '/WonderFlixWatchParty/Account/Recovery/Complete');
    expect(adapter.requests[1].data, {
      'Username': 'garg',
      'Code': '000123',
      'NewPassword': 'nuova123',
      'Language': 'en',
    });
  });

  test('errori: i Code del plugin e gli altri stati', () async {
    final cases = <(int, Object?, AccountFailure)>[
      (404, null, AccountFailure.unavailable),
      (503, {'Code': 'ChannelOff'}, AccountFailure.channelOff),
      (400, {'Code': 'InvalidTarget'}, AccountFailure.invalidTarget),
      (400, {'Code': 'MemberNotFound'}, AccountFailure.memberNotFound),
      (403, {'Code': 'WrongPassword'}, AccountFailure.wrongPassword),
      (409, {'Code': 'DmClosed'}, AccountFailure.dmClosed),
      (502, {'Code': 'SendFailed'}, AccountFailure.sendFailed),
      (400, {'Code': 'InvalidCode'}, AccountFailure.invalidCode),
      (400, {'Code': 'WeakPassword'}, AccountFailure.weakPassword),
      (429, {'Code': 'RateLimited'}, AccountFailure.rateLimited),
      (429, null, AccountFailure.rateLimited),
      (400, {'Code': 'Invalid'}, AccountFailure.invalid),
      (403, {'Code': 'NotAllowed'}, AccountFailure.invalid),
      // Il 400 di ASP.NET per un JSON rotto: niente Code.
      (400, {'title': 'One or more validation errors occurred.'},
          AccountFailure.invalid),
      (401, null, AccountFailure.invalid),
      // Recovery/Complete dopo un errore di Jellyfin: il codice è già usato.
      (500, null, AccountFailure.serverError),
      // nginx mentre Jellyfin si riavvia: senza il Code non è il plugin.
      (502, null, AccountFailure.network),
      (503, null, AccountFailure.network),
    ];
    for (final (status, body, failure) in cases) {
      adapter.handler = (_) => FakeResponse(status, body);
      await expectLater(api.unlink(AccountChannel.email, password: 'x'),
          fails(failure),
          reason: '$status $body');
    }
  });

  test('rete assente e risposta di forma inattesa', () async {
    adapter.handler = (_) => throw const SocketException('giù');
    await expectLater(api.contacts(), fails(AccountFailure.network));

    adapter.handler = (_) => const FakeResponse(200, ['non una mappa']);
    await expectLater(api.contacts(), fails(AccountFailure.network));

    adapter.handler = (_) => const FakeResponse(200, {'Channels': 'no'});
    await expectLater(api.contacts(), fails(AccountFailure.network));
  });

  test('esiti previsti nel log come info, il resto come avviso', () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    for (final status in [400, 403, 404, 409, 429, 502, 503, 500]) {
      adapter.handler = (_) => FakeResponse(status);
      await expectLater(api.contacts(), throwsA(isA<AccountException>()));
    }

    expect([
      for (final record in records)
        if (record.loggerName == 'http') record.level,
    ], [...List.filled(7, Level.INFO), Level.WARNING]);
  });
}
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/core/social/account_api_test.dart`
Expected: FAIL in compilazione (`account_api.dart` non esiste).

- [ ] **Step 3: i modelli**

Crea `lib/core/social/account_models.dart`:

```dart
/// I canali dei contatti per il recupero (spec L §7.6): il nome è quello
/// delle rotte del plugin e delle voci della cassetta.
enum AccountChannel {
  discord('Discord'),
  email('Email');

  const AccountChannel(this.wire);

  final String wire;

  /// `null` per un canale che l'app non conosce.
  static AccountChannel? fromWire(Object? value) {
    for (final channel in values) {
      if (channel.wire == value) return channel;
    }
    return null;
  }
}

/// La password nuova più corta che l'app accetta (spec L §8): il plugin
/// vuole lo stesso minimo nel recupero.
const accountMinPasswordLength = 6;

/// Risposta di `GET Account/Contacts` e di `Confirm` (spec L §7.6): i canali
/// configurati sul server e i contatti verificati dell'utente.
class AccountContacts {
  const AccountContacts({
    this.discordAvailable = false,
    this.emailAvailable = false,
    this.discordName,
    this.email,
  });

  factory AccountContacts.fromJson(Map<String, dynamic> json) {
    final channels = json['Channels'] as Map<String, dynamic>? ?? const {};
    final discord = json['Discord'] as Map<String, dynamic>?;
    final email = json['Email'] as Map<String, dynamic>?;
    return AccountContacts(
      discordAvailable: channels['Discord'] == true,
      emailAvailable: channels['Email'] == true,
      discordName: discord?['Name'] as String?,
      email: email?['Address'] as String?,
    );
  }

  final bool discordAvailable;
  final bool emailAvailable;

  /// Il nome utente Discord collegato; `null` se non c'è.
  final String? discordName;

  /// L'email collegata, intera; `null` se non c'è.
  final String? email;

  /// Il canale è configurato sul server.
  bool isAvailable(AccountChannel channel) => switch (channel) {
        AccountChannel.discord => discordAvailable,
        AccountChannel.email => emailAvailable,
      };

  /// Il contatto collegato su [channel]; `null` se non c'è.
  String? contactOf(AccountChannel channel) => switch (channel) {
        AccountChannel.discord => discordName,
        AccountChannel.email => email,
      };
}
```

- [ ] **Step 4: il client**

Crea `lib/core/social/account_api.dart`:

```dart
import 'package:logging/logging.dart';

import '../jellyfin/api_exception.dart';
import '../jellyfin/jellyfin_http.dart';
import 'account_models.dart';

final _log = Logger('account');

/// Perché una chiamata dell'account non è riuscita (spec L §7.6).
enum AccountFailure {
  /// 404: plugin assente o vecchio (il plugin non risponde mai 404 di suo).
  unavailable,

  /// 503 `ChannelOff`: il canale non è configurato sul server.
  channelOff,

  /// 400 `InvalidTarget`: non sembra un nome utente Discord o un'email.
  invalidTarget,

  /// 400 `MemberNotFound`: nessun membro del server Discord con quel nome.
  memberNotFound,

  /// 403 `WrongPassword`: la password attuale è sbagliata. Non è un 401: la
  /// sessione resta aperta.
  wrongPassword,

  /// 409 `DmClosed`: il bot non può scrivere all'utente.
  dmClosed,

  /// 502 `SendFailed`: Discord o il server di posta non hanno preso il
  /// messaggio.
  sendFailed,

  /// 400 `InvalidCode`: codice sbagliato, scaduto o già usato.
  invalidCode,

  /// 400 `WeakPassword`: la password nuova è fuori dai limiti.
  weakPassword,

  /// 429: troppe richieste o troppi tentativi.
  rateLimited,

  /// 500: errore del server. In `Recovery/Complete` vuol dire che il codice
  /// è già usato (spec L §11).
  serverError,

  /// Un altro 400, 401, 403 o 409, anche senza `Code` (`Invalid`,
  /// `NotAllowed`, il 400 di ASP.NET per un JSON rotto).
  invalid,

  /// Rete, 502/503/504 senza il loro `Code` (nginx durante un riavvio) o
  /// risposta di forma inattesa.
  network,
}

class AccountException implements Exception {
  const AccountException(this.failure);

  final AccountFailure failure;

  @override
  String toString() => 'AccountException(${failure.name})';
}

/// Contatti per il recupero e recupero della password, nel plugin (spec L
/// §7.6). Lancia solo [AccountException]. Le chiamate di `Recovery/*` non
/// vogliono un token: nell'accesso il client non ne ha.
class AccountApi {
  AccountApi(this._http);

  static const _base = '/WonderFlixWatchParty/Account';

  /// Esiti previsti (password sbagliata, codice scaduto, limiti, canale
  /// spento, invio non riuscito, plugin vecchio): nel log come info, non
  /// tra gli "Ultimi errori" della diagnostica.
  static const _quiet = {400, 403, 404, 409, 429, 502, 503};

  final JellyfinHttp _http;

  /// I canali del server e i contatti verificati dell'utente.
  Future<AccountContacts> contacts() => _call(() async =>
      AccountContacts.fromJson(asJsonMap(
          await _http.get('$_base/Contacts', quietStatuses: _quiet))));

  /// Manda il codice a [target] (nome utente Discord o email) per
  /// collegarlo. [password] è la password attuale dell'account, vuota se
  /// non ne ha una.
  Future<void> startLink(AccountChannel channel,
          {required String target,
          required String password,
          required String language}) =>
      _call(() => _http.post('$_base/Contacts/${channel.wire}/Start',
          body: {'Target': target, 'Password': password, 'Language': language},
          quietStatuses: _quiet));

  /// Conferma il collegamento con il codice ricevuto: i contatti di adesso.
  /// Il codice va come stringa (lo zero iniziale conta).
  Future<AccountContacts> confirmLink(AccountChannel channel, String code) =>
      _call(() async => AccountContacts.fromJson(asJsonMap(await _http.post(
          '$_base/Contacts/${channel.wire}/Confirm',
          body: {'Code': code},
          quietStatuses: _quiet))));

  /// Scollega il contatto di [channel] (204 anche se non c'era). È un
  /// `POST`: la password non deve stare nell'indirizzo.
  Future<void> unlink(AccountChannel channel, {required String password}) =>
      _call(() => _http.post('$_base/Contacts/${channel.wire}/Unlink',
          body: {'Password': password}, quietStatuses: _quiet));

  /// Chiede il codice di recupero per [username]. Il plugin risponde 202
  /// che l'account esista o no.
  Future<void> startRecovery(
          {required String username, required String language}) =>
      _call(() => _http.post('$_base/Recovery/Start',
          body: {'Username': username, 'Language': language},
          quietStatuses: _quiet));

  /// Cambia la password con il codice di recupero. [language] è la lingua
  /// dell'avviso "password cambiata".
  Future<void> completeRecovery(
          {required String username,
          required String code,
          required String newPassword,
          required String language}) =>
      _call(() => _http.post('$_base/Recovery/Complete',
          body: {
            'Username': username,
            'Code': code,
            'NewPassword': newPassword,
            'Language': language,
          },
          quietStatuses: _quiet));

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on NotFoundException {
      throw const AccountException(AccountFailure.unavailable);
    } on UnauthorizedException {
      throw const AccountException(AccountFailure.invalid);
    } on ForbiddenException catch (error) {
      throw AccountException(_code(error.body) == 'WrongPassword'
          ? AccountFailure.wrongPassword
          : AccountFailure.invalid);
    } on ServerErrorException catch (error) {
      throw AccountException(switch ((error.statusCode, _code(error.body))) {
        (400, 'InvalidTarget') => AccountFailure.invalidTarget,
        (400, 'MemberNotFound') => AccountFailure.memberNotFound,
        (400, 'InvalidCode') => AccountFailure.invalidCode,
        (400, 'WeakPassword') => AccountFailure.weakPassword,
        (409, 'DmClosed') => AccountFailure.dmClosed,
        (400 || 409, _) => AccountFailure.invalid,
        (429, _) => AccountFailure.rateLimited,
        (502, 'SendFailed') => AccountFailure.sendFailed,
        (503, 'ChannelOff') => AccountFailure.channelOff,
        (500, _) => AccountFailure.serverError,
        _ => AccountFailure.network,
      });
    } on ApiException {
      throw const AccountException(AccountFailure.network);
    } on Object catch (error) {
      // Solo il tipo: il messaggio può citare la risposta.
      _log.info('risposta dell\'account non valida: ${error.runtimeType}');
      throw const AccountException(AccountFailure.network);
    }
  }

  static String? _code(Object? body) {
    if (body is! Map) return null;
    final code = body['Code'];
    return code is String ? code : null;
  }
}
```

- [ ] **Step 5: il test passa**

Run: `flutter test test/core/social/account_api_test.dart`
Expected: PASS (8 test).

- [ ] **Step 6: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/core/social/account_models.dart lib/core/social/account_api.dart test/core/social/account_api_test.dart
git commit -m "feat(app): account API for recovery contacts and password recovery"
```

### Task 3: `changePassword`, `redact.dart` e la funzione `account`

**Files:**
- Modify: `lib/core/jellyfin/auth_api.dart`
- Modify: `lib/core/logging/redact.dart`
- Modify: `lib/core/social/social_models.dart`
- Modify: `lib/features/social/social_providers.dart`
- Test: `test/core/jellyfin/auth_api_test.dart`, `test/core/logging/redact_test.dart`, `test/features/social/social_providers_test.dart`

- [ ] **Step 1: i test**

In fondo a `test/core/jellyfin/auth_api_test.dart`, dentro `main`:

```dart
  test('changePassword: POST /Users/Password con la password attuale',
      () async {
    await api.changePassword('u1',
        currentPassword: 'vecchia', newPassword: 'nuova123');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Users/Password');
    expect(request.queryParameters, {'userId': 'u1'});
    expect(request.data, {'CurrentPw': 'vecchia', 'NewPw': 'nuova123'});
  });

  test("changePassword senza la password attuale (l'admin, piano 18c)",
      () async {
    await api.changePassword('u2', newPassword: 'nuova123');
    expect(adapter.requests.single.data, {'NewPw': 'nuova123'});
  });

  test('changePassword: 403 con la password sbagliata, nel log come info',
      () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    adapter.handler = (_) => const FakeResponse(403);

    await expectLater(
        api.changePassword('u1', currentPassword: 'x', newPassword: 'nuova123'),
        throwsA(isA<ForbiddenException>()));

    expect(records.where((r) => r.loggerName == 'http').single.level,
        Level.INFO);
  });
```

In fondo a `test/core/logging/redact_test.dart`, dentro `main`:

```dart
  test('corpi del recupero e dei contatti (spec L §8)', () {
    expect(
        redactSecrets('{"Username":"garg","Code":"012345",'
            '"NewPassword":"nuova","CurrentPw":"a","NewPw":"b",'
            '"Target":"a@example.com","Password":"c","Language":"it"}'),
        '{"Username":"garg","Code":"***","NewPassword":"***",'
        '"CurrentPw":"***","NewPw":"***","Target":"***","Password":"***",'
        '"Language":"it"}');
  });
```

In `test/features/social/social_providers_test.dart`, dopo il test `'Info con gli avatar: funzione avatars, anche senza watch party'`:

```dart
  test('Info con i contatti: funzione account, anche senza watch party',
      () async {
    api.install(features: const {PluginFeatures.account});
    final c = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(account: true));
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/jellyfin/auth_api_test.dart test/core/logging/redact_test.dart test/features/social/social_providers_test.dart`
Expected: FAIL in compilazione (`changePassword`, `PluginFeatures.account`, `SocialFeatures(account:)` non esistono).

- [ ] **Step 3: `changePassword`**

In `lib/core/jellyfin/auth_api.dart`, dopo `logout`:

```dart
  /// Cambia la password di [userId] (spec L §9.1). Per la propria Jellyfin
  /// vuole quella attuale ([currentPassword], vuota per un account senza) e
  /// risponde 403 se è sbagliata; poi chiude le altre sessioni dell'utente
  /// e tiene questa. Senza [currentPassword]: l'admin che la imposta a un
  /// altro utente (piano 18c).
  Future<void> changePassword(String userId,
      {String? currentPassword, required String newPassword}) async {
    await _http.post('/Users/Password',
        query: {'userId': userId},
        body: {
          if (currentPassword != null) 'CurrentPw': currentPassword,
          'NewPw': newPassword,
        },
        // La password sbagliata è un esito atteso.
        quietStatuses: const {403});
  }
```

- [ ] **Step 4: `redact.dart`**

In `lib/core/logging/redact.dart` sostituisci la regola del JSON:

```dart
  // JSON: "AccessToken": "…", "Pw": "…", "Password": "…", "Token": "…"
  (
    RegExp(r'"(AccessToken|Pw|Password|Token)"\s*:\s*"(?:[^"\\]|\\.)*"',
        caseSensitive: false),
    (m) => '"${m[1]}":"***"',
  ),
```

con:

```dart
  // JSON: "AccessToken": "…", "Pw": "…", "Password": "…", "Token": "…", e
  // i corpi del recupero e dei contatti (spec L §8): il codice, le
  // password, il contatto (un nome Discord o un'email).
  (
    RegExp(
        r'"(AccessToken|Pw|Password|Token|CurrentPw|NewPw|NewPassword|Code|Target)"\s*:\s*"(?:[^"\\]|\\.)*"',
        caseSensitive: false),
    (m) => '"${m[1]}":"***"',
  ),
```

- [ ] **Step 5: la funzione `account`**

In `lib/core/social/social_models.dart`, in `PluginFeatures` dopo `avatars`:

```dart
  /// I contatti per il recupero della password (spec L §7.8).
  static const account = 'account';
```

In `lib/features/social/social_providers.dart`, in `SocialFeatures`:
- nel costruttore, dopo `this.avatars = false,`: `this.account = false,`;
- dopo il campo `avatars`:

```dart
  /// I contatti per il recupero della password (spec L §9.1): non dipendono
  /// dai watch party.
  final bool account;
```

- in `operator ==`, dopo `other.avatars == avatars &&`: `other.account == account &&`;
- `hashCode`:

```dart
  @override
  int get hashCode => Object.hash(
      friends, parties, inbox, requests, collections, avatars, account, known);
```

- `toString`:

```dart
  @override
  String toString() => 'SocialFeatures(friends: $friends, parties: $parties, '
      'inbox: $inbox, requests: $requests, collections: $collections, '
      'avatars: $avatars, account: $account, known: $known)';
```

In `SocialAvailability.refresh`, nel `_apply(SocialFeatures(…))` dopo `avatars: …`:

```dart
        account: info.features.contains(PluginFeatures.account),
```

Nel commento della classe `SocialAvailability`, dove elenca cosa vale anche senza watch party ("e così le richieste con Seerr, spec I §8.2, e le saghe, spec K §8.1"), aggiungi "e i contatti per il recupero, spec L §9.1".

- [ ] **Step 6: i test passano**

Run: `flutter test test/core/jellyfin/auth_api_test.dart test/core/logging/redact_test.dart test/features/social/social_providers_test.dart`
Expected: PASS.

- [ ] **Step 7: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/core/jellyfin/auth_api.dart lib/core/logging/redact.dart lib/core/social/social_models.dart lib/features/social/social_providers.dart test/core/jellyfin/auth_api_test.dart test/core/logging/redact_test.dart test/features/social/social_providers_test.dart
git commit -m "feat(app): password change, account feature, recovery bodies out of the logs"
```

### Task 4: i provider e i finti

**Files:**
- Create: `lib/features/account/account_providers.dart`
- Create: `test/support/account_fakes.dart`
- Create: `test/features/account/account_providers_test.dart`

- [ ] **Step 1: il finto**

Crea `test/support/account_fakes.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/account/account_providers.dart';

/// `AccountApi` senza rete: registra le chiamate e risponde con i campi. Un
/// `…Failure` diverso da `null` fa lanciare quel metodo.
class FakeAccountApi implements AccountApi {
  AccountContacts contactsResult =
      const AccountContacts(discordAvailable: true, emailAvailable: true);
  AccountFailure? contactsFailure;
  int contactsCalls = 0;

  final startLinkCalls = <({
    AccountChannel channel,
    String target,
    String password,
    String language,
  })>[];
  AccountFailure? startLinkFailure;

  final confirmCalls = <(AccountChannel, String)>[];
  AccountFailure? confirmFailure;

  /// I contatti dati da [confirmLink]; `null`: [contactsResult].
  AccountContacts? confirmResult;

  final unlinkCalls = <(AccountChannel, String)>[];
  AccountFailure? unlinkFailure;

  final recoveryStarts = <(String, String)>[];
  AccountFailure? startRecoveryFailure;

  final recoveryCompletes = <({
    String username,
    String code,
    String newPassword,
    String language,
  })>[];
  AccountFailure? completeRecoveryFailure;

  /// Se c'è, ogni chiamata aspetta che si completi (lo stato "in corso").
  Completer<void>? gate;

  Future<void> _answer(AccountFailure? failure) async {
    await gate?.future;
    if (failure != null) throw AccountException(failure);
  }

  @override
  Future<AccountContacts> contacts() async {
    contactsCalls++;
    await _answer(contactsFailure);
    return contactsResult;
  }

  @override
  Future<void> startLink(AccountChannel channel,
      {required String target,
      required String password,
      required String language}) async {
    startLinkCalls.add((
      channel: channel,
      target: target,
      password: password,
      language: language,
    ));
    await _answer(startLinkFailure);
  }

  @override
  Future<AccountContacts> confirmLink(
      AccountChannel channel, String code) async {
    confirmCalls.add((channel, code));
    await _answer(confirmFailure);
    return confirmResult ?? contactsResult;
  }

  @override
  Future<void> unlink(AccountChannel channel,
      {required String password}) async {
    unlinkCalls.add((channel, password));
    await _answer(unlinkFailure);
  }

  @override
  Future<void> startRecovery(
      {required String username, required String language}) async {
    recoveryStarts.add((username, language));
    await _answer(startRecoveryFailure);
  }

  @override
  Future<void> completeRecovery(
      {required String username,
      required String code,
      required String newPassword,
      required String language}) async {
    recoveryCompletes.add((
      username: username,
      code: code,
      newPassword: newPassword,
      language: language,
    ));
    await _answer(completeRecoveryFailure);
  }
}

/// I provider dell'account in un widget test: [api] al posto del plugin e
/// la funzione `account` accesa o spenta, senza chiedere `Info`.
List<Override> accountTestOverrides(FakeAccountApi api,
        {bool available = true}) =>
    [
      accountApiProvider.overrideWithValue(api),
      accountAvailableProvider.overrideWithValue(available),
    ];
```

- [ ] **Step 2: il test**

Crea `test/features/account/account_providers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/account/account_providers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/account_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  ProviderContainer container(
    FakeAccountApi api, {
    bool available = true,
    SessionState session = const SessionSignedIn(testUser),
  }) {
    final c = ProviderContainer.test(
      overrides: [
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(session)),
        accountApiProvider.overrideWithValue(api),
        accountAvailableProvider.overrideWithValue(available),
      ],
      retry: (_, _) => null,
    );
    c.listen(accountContactsProvider, (_, _) {});
    return c;
  }

  test('senza la funzione account: niente contatti e nessuna chiamata',
      () async {
    final api = FakeAccountApi();
    final c = container(api, available: false);
    expect(await c.read(accountContactsProvider.future), isNull);
    expect(api.contactsCalls, 0);
  });

  test('senza un utente aperto: nessuna chiamata', () async {
    final api = FakeAccountApi();
    final c = container(api, session: const SessionSignedOut());
    expect(await c.read(accountContactsProvider.future), isNull);
    expect(api.contactsCalls, 0);
  });

  test('legge i contatti; replace li sostituisce, reload li rilegge',
      () async {
    final api = FakeAccountApi()
      ..contactsResult =
          const AccountContacts(discordAvailable: true, discordName: 'garg');
    final c = container(api);

    final contacts = await c.read(accountContactsProvider.future);
    expect(contacts!.contactOf(AccountChannel.discord), 'garg');

    c.read(accountContactsProvider.notifier).replace(
        const AccountContacts(emailAvailable: true, email: 'a@example.com'));
    expect(c.read(accountContactsProvider).value!.email, 'a@example.com');

    api.contactsResult = const AccountContacts(discordAvailable: true);
    await c.read(accountContactsProvider.notifier).reload();
    expect(c.read(accountContactsProvider).value!.discordName, isNull);
    expect(api.contactsCalls, 2);
  });

  test('un errore della lettura resta nello stato', () async {
    final api = FakeAccountApi()..contactsFailure = AccountFailure.network;
    final c = container(api);
    await expectLater(c.read(accountContactsProvider.future),
        throwsA(isA<AccountException>()));
    expect(c.read(accountContactsProvider).hasError, isTrue);
  });

  test('accountAvailableProvider segue la funzione account', () {
    final c = ProviderContainer.test(overrides: [
      socialAvailabilityProvider.overrideWith(
          () => FakeSocialAvailability(const SocialFeatures(account: true))),
    ]);
    expect(c.read(accountAvailableProvider), isTrue);
  });
}
```

- [ ] **Step 3: il test fallisce**

Run: `flutter test test/features/account/account_providers_test.dart`
Expected: FAIL in compilazione (`account_providers.dart` non esiste).

- [ ] **Step 4: i provider**

Crea `lib/features/account/account_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/social/account_api.dart';
import '../../core/social/account_models.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';

/// Sul client principale: nell'accesso non ha token (`prepareLogin`), e
/// così partono le chiamate del recupero.
final accountApiProvider =
    Provider<AccountApi>((ref) => AccountApi(ref.watch(jellyfinHttpProvider)));

/// Il plugin ha i contatti per il recupero (spec L §9.1). Senza, Impostazioni
/// → Account ha solo il cambio della password.
final accountAvailableProvider = Provider<bool>((ref) =>
    ref.watch(socialAvailabilityProvider.select((f) => f.account)));

/// I contatti dell'utente aperto; `null` senza la funzione `account` o
/// senza un utente. Si rileggono ogni volta che la sezione torna a vedersi
/// (`autoDispose`) e a ogni cambio di profilo.
class AccountContactsController extends AsyncNotifier<AccountContacts?> {
  @override
  Future<AccountContacts?> build() async {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    if (userId == null || !ref.watch(accountAvailableProvider)) return null;
    return ref.watch(accountApiProvider).contacts();
  }

  /// I contatti dati da `Confirm`, senza rileggerli.
  void replace(AccountContacts contacts) => state = AsyncData(contacts);

  /// Di nuovo dal plugin (dopo uno scollegamento). Intanto restano quelli
  /// di prima, senza spinner.
  Future<void> reload() async {
    final result = await AsyncValue.guard(
        () => ref.read(accountApiProvider).contacts());
    if (ref.mounted) state = result;
  }
}

final accountContactsProvider = AsyncNotifierProvider.autoDispose<
    AccountContactsController, AccountContacts?>(AccountContactsController.new);
```

- [ ] **Step 5: il test passa**

Run: `flutter test test/features/account/account_providers_test.dart`
Expected: PASS (5 test).

- [ ] **Step 6: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/account/account_providers.dart test/support/account_fakes.dart test/features/account/account_providers_test.dart
git commit -m "feat(app): account providers and recovery contacts controller"
```

---

## Gruppo B — Impostazioni → Account

### Task 5: "Rimanda il codice" e il cambio della password

**Files:**
- Create: `lib/features/account/resend_code_button.dart`
- Create: `lib/features/account/change_password_dialog.dart`
- Create: `test/features/account/resend_code_button_test.dart`
- Create: `test/features/account/change_password_dialog_test.dart`

- [ ] **Step 1: i test**

Crea `test/features/account/resend_code_button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/account/resend_code_button.dart';

import '../../support/pump_app.dart';

void main() {
  testWidgets('attivo dopo 60 s; riparte solo dopo un invio riuscito',
      (tester) async {
    var calls = 0;
    var sent = true;
    await pumpApp(
        tester,
        Scaffold(
            body: ResendCodeButton(onResend: () async {
          calls++;
          return sent;
        })));

    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();
    expect(calls, 0);

    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Rimanda tra 1 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Rimanda il codice'), findsOneWidget);

    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);

    // Un invio non riuscito non fa ripartire il conto.
    await tester.pump(ResendCodeButton.delay);
    sent = false;
    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Rimanda il codice'), findsOneWidget);
  });
}
```

Crea `test/features/account/change_password_dialog_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/features/account/change_password_dialog.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  Future<bool>? result;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    result = null;
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showChangePasswordDialog(context),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
            baseUrl: testServerUrl,
            clientInfo: testClientInfo,
            adapter: adapter))),
      ],
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester,
      {String current = '', required String next, String? confirm}) async {
    await tester.enterText(
        find.byKey(const Key('change-password-current')), current);
    await tester.enterText(find.byKey(const Key('change-password-new')), next);
    await tester.enterText(
        find.byKey(const Key('change-password-confirm')), confirm ?? next);
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pump();
  }

  testWidgets('password corta e conferma diversa: errori, nessuna chiamata',
      (tester) async {
    await open(tester);

    await fill(tester, next: 'abc');
    expect(find.text('Almeno 6 caratteri'), findsOneWidget);

    await fill(tester, next: 'nuova123', confirm: 'nuova124');
    expect(find.text('Le password non coincidono'), findsOneWidget);
    expect(find.text('Almeno 6 caratteri'), findsNothing);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('password attuale sbagliata: errore sotto il campo',
      (tester) async {
    adapter.handler = (_) => const FakeResponse(403);
    await open(tester);

    await fill(tester, current: 'sbagliata', next: 'nuova123');
    await tester.pump();

    expect(find.text('Password attuale sbagliata'), findsOneWidget);
    expect(find.byKey(const Key('change-password-submit')), findsOneWidget);
  });

  testWidgets('riuscito: manda le password e chiude con true', (tester) async {
    await open(tester);

    await fill(tester, current: 'vecchia', next: 'nuova123');
    await tester.pumpAndSettle();

    final request = adapter.requests.single;
    expect(request.path, '/Users/Password');
    expect(request.queryParameters, {'userId': 'u1'});
    expect(request.data, {'CurrentPw': 'vecchia', 'NewPw': 'nuova123'});
    expect(await result, isTrue);
    expect(find.byKey(const Key('change-password-submit')), findsNothing);
  });

  testWidgets('account senza password: la password attuale va vuota',
      (tester) async {
    await open(tester);

    await fill(tester, next: 'nuova123');
    await tester.pumpAndSettle();

    expect(adapter.requests.single.data, {'CurrentPw': '', 'NewPw': 'nuova123'});
  });

  testWidgets('server irraggiungibile: avviso sopra i campi', (tester) async {
    adapter.handler = (_) => throw const SocketException('giù');
    await open(tester);

    await fill(tester, current: 'vecchia', next: 'nuova123');
    await tester.pump();

    expect(find.text('WonderFlix non è raggiungibile. Controlla la connessione.'),
        findsOneWidget);
  });

  testWidgets('Annulla chiude con false', (tester) async {
    await open(tester);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/account/resend_code_button_test.dart test/features/account/change_password_dialog_test.dart`
Expected: FAIL in compilazione.

- [ ] **Step 3: "Rimanda il codice"**

Crea `lib/features/account/resend_code_button.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// "Rimanda il codice" (spec L §9.2, §9.3): attivo [delay] dopo l'ultimo
/// invio. Il conto parte quando il pulsante compare, cioè appena il codice
/// è partito, e riparte dopo un rinvio riuscito.
class ResendCodeButton extends StatefulWidget {
  const ResendCodeButton({super.key, required this.onResend});

  /// Come il limite del plugin: un codice al minuto.
  static const delay = Duration(seconds: 60);

  /// Rimanda il codice; `true` se è partito.
  final Future<bool> Function() onResend;

  @override
  State<ResendCodeButton> createState() => _ResendCodeButtonState();
}

class _ResendCodeButtonState extends State<ResendCodeButton> {
  /// Ogni quanto scende il conto.
  static const _tick = Duration(seconds: 1);

  Timer? _timer;
  int _secondsLeft = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    _secondsLeft = ResendCodeButton.delay.inSeconds;
    _timer = Timer.periodic(_tick, (timer) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    final sent = await widget.onResend();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (sent) _restart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final waiting = _secondsLeft > 0;
    return TextButton(
      key: const Key('resend-code'),
      onPressed: waiting || _busy ? null : () => unawaited(_resend()),
      child: Text(
          waiting ? l.accountResendIn(_secondsLeft) : l.accountResendCode),
    );
  }
}
```

- [ ] **Step 4: la finestra**

Crea `lib/features/account/change_password_dialog.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';

/// Cambia la password dell'utente aperto (spec L §9.2). `true` se è
/// cambiata.
Future<bool> showChangePasswordDialog(BuildContext context) async =>
    await showWfDialog<bool>(
      context,
      semanticLabel: AppLocalizations.of(context).settingsChangePassword,
      builder: (_) => const ChangePasswordDialog(),
    ) ??
    false;

/// Password attuale (vuota per un account senza), nuova e conferma.
/// Jellyfin chiude le altre sessioni dell'utente e tiene questa: il profilo
/// di questo PC resta dentro.
class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _currentError;
  String? _newError;
  String? _confirmError;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider);
    if (session is! SessionSignedIn) return;
    final password = _new.text;
    setState(() {
      _currentError = null;
      _error = null;
      _newError = password.length < accountMinPasswordLength
          ? l.accountPasswordTooShort
          : null;
      _confirmError = _newError == null && _confirm.text != password
          ? l.accountPasswordsDiffer
          : null;
    });
    if (_newError != null || _confirmError != null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authApiProvider).changePassword(session.user.id,
          currentPassword: _current.text, newPassword: password);
      if (mounted) Navigator.of(context).pop(true);
    } on ForbiddenException {
      if (mounted) setState(() => _currentError = l.accountWrongPassword);
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeError(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.settingsChangePassword,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('change-password-current'),
          controller: _current,
          autofocus: true,
          obscureText: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.accountCurrentPassword,
            helperText: l.accountNoPasswordHint,
            errorText: _currentError,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('change-password-new'),
          controller: _new,
          obscureText: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
              labelText: l.accountNewPassword, errorText: _newError),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('change-password-confirm'),
          controller: _confirm,
          obscureText: true,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
              labelText: l.accountConfirmPassword, errorText: _confirmError),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.accountCancel),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const Key('change-password-submit'),
              // Il tema fa i FilledButton larghi all'infinito: in una Row
              // servono larghi quanto il testo.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: Text(l.settingsChangePassword),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/account/resend_code_button_test.dart test/features/account/change_password_dialog_test.dart`
Expected: PASS (7 test).

- [ ] **Step 6: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/account/resend_code_button.dart lib/features/account/change_password_dialog.dart test/features/account/resend_code_button_test.dart test/features/account/change_password_dialog_test.dart
git commit -m "feat(app): change password dialog and timed resend button"
```

### Task 6: collegare e scollegare un contatto

**Files:**
- Create: `lib/features/account/account_texts.dart`
- Create: `lib/features/account/link_contact_dialog.dart`
- Create: `lib/features/account/unlink_contact_dialog.dart`
- Create: `test/features/account/link_contact_dialog_test.dart`
- Create: `test/features/account/unlink_contact_dialog_test.dart`

- [ ] **Step 1: i test**

Crea `test/features/account/link_contact_dialog_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/account/link_contact_dialog.dart';

import '../../support/account_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAccountApi api;
  AccountContacts? linked;
  var closed = false;

  setUp(() {
    api = FakeAccountApi();
    linked = null;
    closed = false;
  });

  Future<void> open(WidgetTester tester, AccountChannel channel) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              linked = await showLinkContactDialog(context, channel);
              closed = true;
            },
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: accountTestOverrides(api),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('link-submit')));
    await tester.pump();
  }

  testWidgets('Discord: nome e password, poi il codice e i contatti nuovi',
      (tester) async {
    api.confirmResult = const AccountContacts(
        discordAvailable: true, emailAvailable: true, discordName: 'garg');
    await open(tester, AccountChannel.discord);
    expect(find.text('Collega Discord'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('link-target')), '  garg ');
    await tester.enterText(find.byKey(const Key('link-password')), 'segreta');
    await submit(tester);

    expect(api.startLinkCalls.single, (
      channel: AccountChannel.discord,
      target: 'garg',
      password: 'segreta',
      language: 'it',
    ));
    expect(find.text('Ti abbiamo mandato un codice su Discord'), findsOneWidget);
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
    expect(find.byKey(const Key('link-password')), findsNothing);

    await tester.enterText(find.byKey(const Key('link-code')), ' 012345 ');
    await submit(tester);
    await tester.pumpAndSettle();

    expect(api.confirmCalls.single, (AccountChannel.discord, '012345'));
    expect(closed, isTrue);
    expect(linked!.discordName, 'garg');
  });

  testWidgets('primo passo: gli errori sotto il campo giusto o sopra',
      (tester) async {
    await open(tester, AccountChannel.discord);

    // Nome vuoto: nessuna chiamata.
    await submit(tester);
    expect(find.text('Nome utente Discord non valido'), findsOneWidget);
    expect(api.startLinkCalls, isEmpty);

    await tester.enterText(find.byKey(const Key('link-target')), 'garg');
    api.startLinkFailure = AccountFailure.memberNotFound;
    await submit(tester);
    expect(find.textContaining('Non ti trovo nel server Discord'),
        findsOneWidget);

    api.startLinkFailure = AccountFailure.wrongPassword;
    await submit(tester);
    expect(find.text('Password attuale sbagliata'), findsOneWidget);
    expect(find.textContaining('Non ti trovo'), findsNothing);

    api.startLinkFailure = AccountFailure.dmClosed;
    await submit(tester);
    expect(find.textContaining('Il bot non riesce a scriverti'),
        findsOneWidget);

    api.startLinkFailure = AccountFailure.rateLimited;
    await submit(tester);
    expect(find.text('Troppe richieste: riprova più tardi'), findsOneWidget);

    api.startLinkFailure = AccountFailure.channelOff;
    await submit(tester);
    expect(find.text('Non disponibile su questo server'), findsOneWidget);

    expect(find.byKey(const Key('link-code')), findsNothing);
  });

  testWidgets('email: codice sbagliato, Rimanda con la stessa password',
      (tester) async {
    await open(tester, AccountChannel.email);
    await tester.enterText(
        find.byKey(const Key('link-target')), 'a@example.com');
    await tester.enterText(find.byKey(const Key('link-password')), 'segreta');
    await submit(tester);
    expect(find.text('Ti abbiamo mandato un codice a a@example.com'),
        findsOneWidget);

    api.confirmFailure = AccountFailure.invalidCode;
    await tester.enterText(find.byKey(const Key('link-code')), '111111');
    await submit(tester);
    expect(find.text('Codice non valido o scaduto'), findsOneWidget);
    expect(closed, isFalse);

    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.byKey(const Key('resend-code')));
    await tester.pump();

    expect(api.startLinkCalls, hasLength(2));
    expect(api.startLinkCalls.last.target, 'a@example.com');
    expect(api.startLinkCalls.last.password, 'segreta');
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
  });

  testWidgets('mentre il codice parte, un secondo clic non fa niente',
      (tester) async {
    api.gate = Completer<void>();
    await open(tester, AccountChannel.discord);
    await tester.enterText(find.byKey(const Key('link-target')), 'garg');
    await submit(tester);
    await submit(tester);
    expect(api.startLinkCalls, hasLength(1));

    api.gate!.complete();
    await tester.pump();
    expect(find.byKey(const Key('link-code')), findsOneWidget);
  });

  testWidgets('email non valida dal plugin: sotto il campo', (tester) async {
    api.startLinkFailure = AccountFailure.invalidTarget;
    await open(tester, AccountChannel.email);
    await tester.enterText(find.byKey(const Key('link-target')), 'non-email');
    await submit(tester);
    expect(find.text('Email non valida'), findsOneWidget);
  });

  testWidgets('Annulla chiude senza contatti', (tester) async {
    await open(tester, AccountChannel.email);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(linked, isNull);
  });
}
```

Crea `test/features/account/unlink_contact_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/account/unlink_contact_dialog.dart';

import '../../support/account_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAccountApi api;
  bool? unlinked;

  setUp(() {
    api = FakeAccountApi();
    unlinked = null;
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => unlinked =
                await showUnlinkContactDialog(context, AccountChannel.email),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: accountTestOverrides(api),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String password) async {
    await tester.enterText(find.byKey(const Key('unlink-password')), password);
    await tester.tap(find.byKey(const Key('unlink-submit')));
    await tester.pump();
  }

  testWidgets('password sbagliata resta aperta; giusta scollega',
      (tester) async {
    await open(tester);
    expect(find.text('Scollegare Email?'), findsOneWidget);

    api.unlinkFailure = AccountFailure.wrongPassword;
    await submit(tester, 'x');
    expect(find.text('Password attuale sbagliata'), findsOneWidget);
    expect(unlinked, isNull);

    api.unlinkFailure = null;
    await submit(tester, 'segreta');
    await tester.pumpAndSettle();
    expect(api.unlinkCalls.last, (AccountChannel.email, 'segreta'));
    expect(unlinked, isTrue);
  });

  testWidgets('troppi controlli: avviso sopra il campo', (tester) async {
    api.unlinkFailure = AccountFailure.rateLimited;
    await open(tester);
    await submit(tester, 'segreta');
    expect(find.text('Troppe richieste: riprova più tardi'), findsOneWidget);
  });

  testWidgets('Annulla: false', (tester) async {
    await open(tester);
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();
    expect(unlinked, isFalse);
    expect(api.unlinkCalls, isEmpty);
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/account/link_contact_dialog_test.dart test/features/account/unlink_contact_dialog_test.dart`
Expected: FAIL in compilazione.

- [ ] **Step 3: i testi**

Crea `lib/features/account/account_texts.dart`:

```dart
import '../../core/social/account_api.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Il nome del canale nei testi: "Discord", "Email".
String accountChannelName(AppLocalizations l, AccountChannel channel) =>
    switch (channel) {
      AccountChannel.discord => l.accountChannelDiscord,
      AccountChannel.email => l.accountChannelEmail,
    };

/// Il testo di un errore dei contatti (spec L §9.2, §10). Il 429 dice "più
/// tardi": i limiti arrivano a un giorno.
String accountFailureText(
        AppLocalizations l, AccountFailure failure, AccountChannel channel) =>
    switch (failure) {
      AccountFailure.unavailable ||
      AccountFailure.channelOff =>
        l.accountChannelOff,
      AccountFailure.invalidTarget => switch (channel) {
          AccountChannel.discord => l.accountErrorInvalidDiscordName,
          AccountChannel.email => l.accountErrorInvalidEmail,
        },
      AccountFailure.memberNotFound => l.accountErrorMemberNotFound,
      AccountFailure.wrongPassword => l.accountWrongPassword,
      AccountFailure.dmClosed => l.accountErrorDmClosed,
      AccountFailure.sendFailed => l.accountErrorSendFailed,
      AccountFailure.invalidCode => l.accountErrorInvalidCode,
      AccountFailure.rateLimited => l.accountErrorRateLimited,
      AccountFailure.weakPassword => l.accountPasswordTooShort,
      AccountFailure.network => l.errorServerUnreachable,
      AccountFailure.invalid || AccountFailure.serverError => l.errorGeneric,
    };
```

- [ ] **Step 4: la finestra di collegamento**

Crea `lib/features/account/link_contact_dialog.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/account_api.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import 'account_providers.dart';
import 'account_texts.dart';
import 'resend_code_button.dart';

/// Collega (o sostituisce) il contatto di [channel] (spec L §9.2): i
/// contatti dopo la conferma, `null` se la finestra si chiude prima.
Future<AccountContacts?> showLinkContactDialog(
    BuildContext context, AccountChannel channel) {
  final l = AppLocalizations.of(context);
  return showWfDialog<AccountContacts>(
    context,
    semanticLabel: l.accountLinkTitle(accountChannelName(l, channel)),
    builder: (_) => LinkContactDialog(channel: channel),
  );
}

/// Due passi: il contatto con la password attuale, poi il codice. La
/// password resta in questa finestra fino alla chiusura: "Rimanda il
/// codice" rifà `Start`, che la vuole di nuovo.
class LinkContactDialog extends ConsumerStatefulWidget {
  const LinkContactDialog({super.key, required this.channel});

  final AccountChannel channel;

  @override
  ConsumerState<LinkContactDialog> createState() => _LinkContactDialogState();
}

class _LinkContactDialogState extends ConsumerState<LinkContactDialog> {
  final _target = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  /// Il contatto a cui è partito il codice; `null` al primo passo.
  String? _sentTo;
  bool _busy = false;
  String? _targetError;
  String? _passwordError;
  String? _codeError;
  String? _error;

  AccountChannel get _channel => widget.channel;

  @override
  void dispose() {
    _target.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _clearErrors() {
    _targetError = _passwordError = _codeError = _error = null;
  }

  /// Mostra [failure] sotto il campo che lo riguarda, se è sullo schermo;
  /// altrimenti sopra i campi.
  void _show(AccountFailure failure) {
    final text =
        accountFailureText(AppLocalizations.of(context), failure, _channel);
    final firstStep = _sentTo == null;
    setState(() {
      switch (failure) {
        case AccountFailure.invalidTarget || AccountFailure.memberNotFound
            when firstStep:
          _targetError = text;
        case AccountFailure.wrongPassword when firstStep:
          _passwordError = text;
        case AccountFailure.invalidCode when !firstStep:
          _codeError = text;
        case _:
          _error = text;
      }
    });
  }

  /// Manda il codice a [target]. `true` se è partito.
  Future<bool> _send(String target) async {
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _busy = true;
      _clearErrors();
    });
    try {
      await ref.read(accountApiProvider).startLink(_channel,
          target: target, password: _password.text, language: language);
      return true;
    } on AccountException catch (error) {
      if (mounted) _show(error.failure);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    final target = _target.text.trim();
    if (target.isEmpty) {
      _show(AccountFailure.invalidTarget);
      return;
    }
    if (await _send(target) && mounted) setState(() => _sentTo = target);
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      _show(AccountFailure.invalidCode);
      return;
    }
    setState(() {
      _busy = true;
      _clearErrors();
    });
    try {
      final contacts =
          await ref.read(accountApiProvider).confirmLink(_channel, code);
      if (mounted) Navigator.of(context).pop(contacts);
    } on AccountException catch (error) {
      if (mounted) _show(error.failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sentTo = _sentTo;
    final discord = _channel == AccountChannel.discord;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.accountLinkTitle(accountChannelName(l, _channel)),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        if (sentTo == null) ...[
          TextField(
            key: const Key('link-target'),
            controller: _target,
            autofocus: true,
            textInputAction: TextInputAction.next,
            keyboardType:
                discord ? TextInputType.text : TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: discord ? l.accountDiscordName : l.accountChannelEmail,
              helperText: discord ? l.accountDiscordNameHint : null,
              errorText: _targetError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('link-password'),
            controller: _password,
            obscureText: true,
            onSubmitted: (_) => unawaited(_start()),
            decoration: InputDecoration(
              labelText: l.accountCurrentPassword,
              helperText: l.accountNoPasswordHint,
              errorText: _passwordError,
            ),
          ),
        ] else ...[
          Text(discord
              ? l.accountCodeSentDiscord
              : l.accountCodeSentEmail(sentTo)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('link-code'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => unawaited(_confirm()),
            decoration:
                InputDecoration(labelText: l.accountCode, errorText: _codeError),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: ResendCodeButton(onResend: () => _send(sentTo)),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.accountCancel),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const Key('link-submit'),
              // Il tema fa i FilledButton larghi all'infinito: in una Row
              // servono larghi quanto il testo.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy
                  ? null
                  : () => unawaited(sentTo == null ? _start() : _confirm()),
              child: Text(sentTo == null ? l.accountSendCode : l.accountConfirm),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: la finestra di scollegamento**

Crea `lib/features/account/unlink_contact_dialog.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/account_api.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import 'account_providers.dart';
import 'account_texts.dart';

/// Scollega il contatto di [channel] dopo la password attuale (spec L
/// §9.2). `true` se scollegato.
Future<bool> showUnlinkContactDialog(
    BuildContext context, AccountChannel channel) async {
  final l = AppLocalizations.of(context);
  return await showWfDialog<bool>(
        context,
        semanticLabel: l.accountUnlinkTitle(accountChannelName(l, channel)),
        builder: (_) => UnlinkContactDialog(channel: channel),
      ) ??
      false;
}

class UnlinkContactDialog extends ConsumerStatefulWidget {
  const UnlinkContactDialog({super.key, required this.channel});

  final AccountChannel channel;

  @override
  ConsumerState<UnlinkContactDialog> createState() =>
      _UnlinkContactDialogState();
}

class _UnlinkContactDialogState extends ConsumerState<UnlinkContactDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _passwordError = _error = null;
    });
    try {
      await ref
          .read(accountApiProvider)
          .unlink(widget.channel, password: _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on AccountException catch (error) {
      if (!mounted) return;
      final text = accountFailureText(l, error.failure, widget.channel);
      setState(() {
        if (error.failure == AccountFailure.wrongPassword) {
          _passwordError = text;
        } else {
          _error = text;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.accountUnlinkTitle(accountChannelName(l, widget.channel)),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Text(l.accountUnlinkBody),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('unlink-password'),
          controller: _password,
          autofocus: true,
          obscureText: true,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
            labelText: l.accountCurrentPassword,
            helperText: l.accountNoPasswordHint,
            errorText: _passwordError,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.accountCancel),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const Key('unlink-submit'),
              // Il tema fa i FilledButton larghi all'infinito: in una Row
              // servono larghi quanto il testo.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: Text(l.accountUnlink),
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: i test passano**

Run: `flutter test test/features/account/link_contact_dialog_test.dart test/features/account/unlink_contact_dialog_test.dart`
Expected: PASS (9 test).

- [ ] **Step 7: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/account/account_texts.dart lib/features/account/link_contact_dialog.dart lib/features/account/unlink_contact_dialog.dart test/features/account/link_contact_dialog_test.dart test/features/account/unlink_contact_dialog_test.dart
git commit -m "feat(app): link and unlink a recovery contact with the current password"
```

### Task 7: la sezione Account, in cima

**Files:**
- Create: `lib/features/account/account_contacts_block.dart`
- Create: `lib/features/settings/account_settings_section.dart`
- Modify: `lib/features/settings/settings_screen.dart`
- Create: `test/features/settings/account_settings_section_test.dart`
- Modify: `test/features/settings/settings_test.dart`

- [ ] **Step 1: il test**

Crea `test/features/settings/account_settings_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/account_settings_section.dart';

import '../../support/account_fakes.dart';
import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAccountApi api;

  setUp(() => api = FakeAccountApi());

  Future<void> pumpSection(
    WidgetTester tester, {
    bool available = true,
    JellyfinUser user = testUser,
    List<Override> extra = const [],
  }) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: SingleChildScrollView(child: AccountSettingsSection())),
      overrides: [
        sessionControllerProvider
            .overrideWith(() => FakeSessionController(SessionSignedIn(user))),
        ...accountTestOverrides(api, available: available),
        ...extra,
      ],
    );
    // I contatti arrivano.
    await tester.pump();
  }

  testWidgets('senza la funzione account: il cambio password, niente contatti',
      (tester) async {
    await pumpSection(tester, available: false);

    expect(find.text('Cambia password'), findsOneWidget);
    expect(find.text('Accesso come Mario'), findsOneWidget);
    expect(find.text('Contatti per il recupero'), findsNothing);
    expect(api.contactsCalls, 0);
  });

  testWidgets('righe: collegato, canale spento, il testo sotto',
      (tester) async {
    api.contactsResult = const AccountContacts(
        discordAvailable: true, emailAvailable: false, discordName: 'garg');
    await pumpSection(tester);

    expect(find.text('Contatti per il recupero'), findsOneWidget);
    expect(find.text('Collegato: garg'), findsOneWidget);
    expect(find.text('Non disponibile su questo server'), findsOneWidget);
    expect(find.text('Cambia'), findsOneWidget);
    expect(find.byKey(const Key('account-unlink-Discord')), findsOneWidget);
    expect(find.byKey(const Key('account-link-Email')), findsNothing);
    expect(find.byKey(const Key('account-unlink-Email')), findsNothing);
    expect(find.text('Servono per recuperare la password se la dimentichi.'),
        findsOneWidget);
  });

  testWidgets('canale spento con il contatto: si può scollegare',
      (tester) async {
    api.contactsResult = const AccountContacts(
        discordAvailable: true, email: 'a@example.com');
    await pumpSection(tester);

    expect(find.text('Non disponibile su questo server'), findsOneWidget);
    expect(find.byKey(const Key('account-link-Email')), findsNothing);
    expect(find.byKey(const Key('account-unlink-Email')), findsOneWidget);
  });

  testWidgets('admin: anche la frase sul recupero automatico', (tester) async {
    await pumpSection(tester,
        user: const JellyfinUser(
            id: 'u1', name: 'Mario', isAdministrator: true));

    expect(
        find.text('Servono per recuperare la password se la dimentichi. '
            'Gli admin non possono usare il recupero automatico.'),
        findsOneWidget);
  });

  testWidgets('Collega: la finestra, poi la riga collegata', (tester) async {
    api.confirmResult = const AccountContacts(
        discordAvailable: true, emailAvailable: true, email: 'a@example.com');
    await pumpSection(tester);
    expect(find.text('Non collegato'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('account-link-Email')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('link-target')), 'a@example.com');
    await tester.tap(find.byKey(const Key('link-submit')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('link-code')), '123456');
    await tester.tap(find.byKey(const Key('link-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Collegato: a@example.com'), findsOneWidget);
    expect(find.text('Contatto collegato'), findsOneWidget);
    // I contatti nuovi vengono da Confirm, senza rileggerli.
    expect(api.contactsCalls, 1);
  });

  testWidgets('Scollega: la password, poi i contatti riletti', (tester) async {
    api.contactsResult = const AccountContacts(
        discordAvailable: true, emailAvailable: true, discordName: 'garg');
    await pumpSection(tester);

    await tester.tap(find.byKey(const Key('account-unlink-Discord')));
    await tester.pumpAndSettle();
    api.contactsResult =
        const AccountContacts(discordAvailable: true, emailAvailable: true);
    await tester.enterText(find.byKey(const Key('unlink-password')), 'segreta');
    await tester.tap(find.byKey(const Key('unlink-submit')));
    await tester.pumpAndSettle();

    expect(api.unlinkCalls.single, (AccountChannel.discord, 'segreta'));
    expect(find.text('Contatto scollegato'), findsOneWidget);
    expect(find.text('Non collegato'), findsNWidgets(2));
    expect(api.contactsCalls, 2);
  });

  testWidgets('contatti non letti: messaggio e Riprova', (tester) async {
    api.contactsFailure = AccountFailure.network;
    await pumpSection(tester);
    expect(find.text('Non è stato possibile leggere i contatti'),
        findsOneWidget);

    api.contactsFailure = null;
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Non collegato'), findsNWidgets(2));
  });

  testWidgets('Cambia password: avviso dopo il cambio', (tester) async {
    final adapter = FakeAdapter((_) => const FakeResponse(204));
    await pumpSection(tester, available: false, extra: [
      authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
          baseUrl: testServerUrl,
          clientInfo: testClientInfo,
          adapter: adapter))),
    ]);

    await tester.tap(find.byKey(const Key('settings-change-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('change-password-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('change-password-confirm')), 'nuova123');
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();

    expect(
        find.text('Password cambiata. Gli altri dispositivi dovranno rientrare.'),
        findsOneWidget);
  });
}
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/features/settings/account_settings_section_test.dart`
Expected: FAIL in compilazione.

- [ ] **Step 3: le righe dei contatti**

Crea `lib/features/account/account_contacts_block.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'account_providers.dart';
import 'account_texts.dart';
import 'link_contact_dialog.dart';
import 'unlink_contact_dialog.dart';

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 12.5);

/// Larghezza massima delle righe: su uno schermo largo le azioni restano
/// vicine al contatto.
const _rowsMaxWidth = 640.0;

/// Larghezza della colonna del nome del canale, perché gli stati si
/// allineino.
const _channelWidth = 90.0;

/// Contatti per il recupero (spec L §9.2): una riga per canale, con
/// "Collega" o "Cambia" e "Scollega".
class AccountContactsBlock extends ConsumerWidget {
  const AccountContactsBlock({super.key, required this.isAdministrator});

  /// Gli admin non hanno il recupero automatico: lo dice il testo sotto.
  final bool isAdministrator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final contacts = ref.watch(accountContactsProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _rowsMaxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.accountContactsTitle,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          switch (contacts) {
            AsyncData(:final value?) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final channel in AccountChannel.values)
                    _ContactRow(channel: channel, contacts: value),
                ],
              ),
            AsyncError() => Row(
                children: [
                  Flexible(child: Text(l.accountContactsError, style: _mutedStyle)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(accountContactsProvider),
                    child: Text(l.retry),
                  ),
                ],
              ),
            AsyncData() => const SizedBox.shrink(),
            _ => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          },
          const SizedBox(height: 8),
          Text(
              isAdministrator
                  ? '${l.accountContactsHint} ${l.accountContactsAdminHint}'
                  : l.accountContactsHint,
              style: _mutedStyle),
        ],
      ),
    );
  }
}

class _ContactRow extends ConsumerWidget {
  const _ContactRow({required this.channel, required this.contacts});

  final AccountChannel channel;
  final AccountContacts contacts;

  Future<void> _link(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final linked = await showLinkContactDialog(context, channel);
    if (linked == null || !context.mounted) return;
    ref.read(accountContactsProvider.notifier).replace(linked);
    messenger?.showSnackBar(SnackBar(content: Text(l.accountLinkedDone)));
  }

  Future<void> _unlink(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final unlinked = await showUnlinkContactDialog(context, channel);
    if (!unlinked || !context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(l.accountUnlinkedDone)));
    await ref.read(accountContactsProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final available = contacts.isAvailable(channel);
    final value = contacts.contactOf(channel);
    // Un canale spento è grigio anche con il contatto (i contatti restano,
    // spec L §11).
    final status = !available
        ? l.accountChannelOff
        : value == null
            ? l.accountNotLinked
            : l.accountLinked(value);
    final linkedAndOn = available && value != null;
    return Padding(
      key: Key('account-contact-${channel.wire}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            channel == AccountChannel.discord
                ? LucideIcons.messageCircle
                : LucideIcons.mail,
            size: 18,
            color: available ? WfColors.gold : WfColors.creamMuted,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _channelWidth,
            child: Text(accountChannelName(l, channel),
                style: TextStyle(
                    color: available ? WfColors.cream : WfColors.creamMuted,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(status,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color:
                        linkedAndOn ? WfColors.cream : WfColors.creamMuted)),
          ),
          if (available)
            TextButton(
              key: Key('account-link-${channel.wire}'),
              onPressed: () => unawaited(_link(context, ref)),
              child: Text(value == null ? l.accountLink : l.accountChange),
            ),
          if (value != null)
            TextButton(
              key: Key('account-unlink-${channel.wire}'),
              onPressed: () => unawaited(_unlink(context, ref)),
              child: Text(l.accountUnlink),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: la sezione**

Crea `lib/features/settings/account_settings_section.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../account/account_contacts_block.dart';
import '../account/account_providers.dart';
import '../account/change_password_dialog.dart';
import '../auth/session_controller.dart';
import '../profiles/avatar_dialog.dart';
import '../profiles/profile_switch.dart';

/// Diametro dell'avatar in Impostazioni → Account.
const _accountAvatarSize = 64.0;

/// Impostazioni → Account (spec L §9.2): chi è aperto, immagine, password,
/// profili, uscita e, con la funzione `account` del plugin, i contatti per
/// il recupero.
class AccountSettingsSection extends ConsumerWidget {
  const AccountSettingsSection({super.key});

  Future<void> _changePassword(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await showChangePasswordDialog(context)) {
      messenger
          ?.showSnackBar(SnackBar(content: Text(l.accountPasswordChanged)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final session = ref.watch(sessionControllerProvider);
    final user = session is SessionSignedIn ? session.user : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (user != null)
          Row(
            children: [
              UserAvatar(
                userId: user.id,
                name: user.name,
                size: _accountAvatarSize,
                imageTag: user.primaryImageTag,
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(l.settingsSignedInAs(user.name))),
            ],
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (user != null) ...[
              WfButton.secondary(
                label: l.settingsChangeImage,
                icon: LucideIcons.imagePlus,
                onPressed: () => unawaited(showAvatarDialog(context,
                    userId: user.id,
                    name: user.name,
                    imageTag: user.primaryImageTag)),
              ),
              WfButton.secondary(
                key: const Key('settings-change-password'),
                label: l.settingsChangePassword,
                icon: LucideIcons.keyRound,
                onPressed: () => unawaited(_changePassword(context)),
              ),
            ],
            WfButton.secondary(
              label: l.profilesSwitch,
              icon: LucideIcons.users,
              onPressed: () => unawaited(changeProfile(context, ref)),
            ),
            WfButton.secondary(
              label: l.menuLogout,
              icon: LucideIcons.logOut,
              onPressed: () => unawaited(
                  ref.read(sessionControllerProvider.notifier).logout()),
            ),
          ],
        ),
        if (user != null && ref.watch(accountAvailableProvider)) ...[
          const SizedBox(height: 24),
          AccountContactsBlock(isAdministrator: user.isAdministrator),
        ],
      ],
    );
  }
}
```

- [ ] **Step 5: in cima a Impostazioni**

In `lib/features/settings/settings_screen.dart`:
- togli gli import che non servono più: `lucide_icons_flutter`, `../../ui/user_avatar.dart`, `../../ui/wf_buttons.dart`, `../auth/session_controller.dart`, `../profiles/avatar_dialog.dart`, `../profiles/profile_switch.dart`; aggiungi `import 'account_settings_section.dart';`;
- togli la costante `_accountAvatarSize` e, in `build`, la riga `final session = ref.watch(sessionControllerProvider);`;
- sostituisci gli elementi da `item(1, …)` a `item(7, …)` con questi (Account prima, le altre nell'ordine di oggi):

```dart
            item(1, [
              section(l.settingsAccount),
              const AccountSettingsSection(),
            ]),
            item(2, [
              section(l.settingsLanguage),
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: 'system', label: Text(l.settingsLanguageSystem)),
                    const ButtonSegment(value: 'it', label: Text('Italiano')),
                    const ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {locale?.languageCode ?? 'system'},
                  onSelectionChanged: (selection) {
                    final code = selection.first;
                    unawaited(ref
                        .read(localeProvider.notifier)
                        .set(code == 'system' ? null : Locale(code)));
                  },
                ),
              ),
            ]),
            item(3, [
              section(l.settingsAppearance),
              const AppearanceSettingsSection(),
            ]),
            item(4, [
              section(l.settingsPlayer),
              const PlayerSettingsSection(),
            ]),
            item(5, [
              section(l.settingsLanguages),
              const LanguageSettingsSection(),
            ]),
            item(6, [
              section(l.settingsDiscord),
              const DiscordSettingsSection(),
            ]),
            item(7, [
              section(l.settingsSupport),
              const SupportSection(),
              const SizedBox(height: 40),
              Text(l.settingsVersion(version),
                  style: const TextStyle(
                      color: WfColors.creamMuted, fontSize: 12.5)),
            ]),
```

`_sectionCount` resta 8 (il titolo e sette sezioni).

- [ ] **Step 6: i test di Impostazioni**

In `test/features/settings/settings_test.dart`:
- aggiungi `import 'package:wonderflix/features/account/account_providers.dart';`;
- in **ogni** `pumpApp(… SettingsScreen() …)` del file (sono 8, compreso quello di `pumpSettings`) aggiungi agli `overrides`:

```dart
      // Niente plugin nei test di Impostazioni: senza, la sezione Account
      // chiederebbe `Info` per i contatti.
      accountAvailableProvider.overrideWithValue(false),
```

(il commento basta nel primo);
- nel test `'schermata: utente, lingua, versione, esci'`, dopo `expect(find.byType(UserAvatar), findsOneWidget);`:

```dart
    expect(find.text('Cambia password'), findsOneWidget);
    // Account è la prima sezione.
    expect(tester.getTopLeft(find.text('Account')).dy,
        lessThan(tester.getTopLeft(find.text('Aspetto')).dy));
```

Se un test che scorre la pagina (per esempio `'lingue: la sezione resta caricata scorrendo la pagina'`) cerca una sezione a una posizione che ora è cambiata, aggiusta lo scorrimento del test, non il codice.

- [ ] **Step 7: i test passano**

Run: `flutter test test/features/settings/`
Expected: PASS.

- [ ] **Step 8: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/account/account_contacts_block.dart lib/features/settings/account_settings_section.dart lib/features/settings/settings_screen.dart test/features/settings/account_settings_section_test.dart test/features/settings/settings_test.dart
git commit -m "feat(app): account section first in settings, with password and recovery contacts"
```

---

## Gruppo C — recupero e cassetta

### Task 8: "Password dimenticata?" nell'accesso

**Files:**
- Create: `lib/features/auth/recovery_panel.dart`
- Modify: `lib/features/auth/password_login_form.dart`
- Modify: `lib/features/auth/login_screen.dart`
- Create: `test/features/auth/recovery_panel_test.dart`

- [ ] **Step 1: il test**

Crea `test/features/auth/recovery_panel_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/account_api.dart';
import 'package:wonderflix/features/auth/auth_providers.dart';
import 'package:wonderflix/features/auth/login_screen.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';
import 'package:wonderflix/features/auth/session_controller.dart';

import '../../support/account_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/profile_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeAccountApi api;
  late FakeSessionController session;

  setUp(() {
    api = FakeAccountApi();
    session = FakeSessionController(const SessionSignedOut());
  });

  Future<void> pumpLogin(WidgetTester tester, {bool quickConnect = false}) async {
    await pumpApp(tester, const LoginScreen(), overrides: [
      sessionControllerProvider.overrideWith(() => session),
      quickConnectEnabledProvider.overrideWith((ref) async => quickConnect),
      profilesProvider
          .overrideWith(() => FixedProfiles(const ProfilesState())),
      ...accountTestOverrides(api),
    ]);
    await tester.pump();
  }

  Future<void> openRecovery(WidgetTester tester, {String username = 'garg'}) async {
    await tester.enterText(find.byKey(const Key('login-username')), username);
    await tester.tap(find.byKey(const Key('login-forgot')));
    await tester.pump();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pump();
  }

  String fieldText(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  testWidgets('si apre con il nome scritto e torna indietro con quello',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);

    expect(find.text('Recupera la password'), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsNothing);
    expect(fieldText(tester, 'recovery-username'), 'garg');

    await tester.enterText(find.byKey(const Key('recovery-username')), 'garg2');
    await tapKey(tester, 'recovery-back');

    expect(fieldText(tester, 'login-username'), 'garg2');
    expect(find.text('Recupera la password'), findsNothing);
  });

  testWidgets('con Quick Connect il recupero prende tutto il pannello',
      (tester) async {
    await pumpLogin(tester, quickConnect: true);
    await openRecovery(tester);

    expect(find.text('Quick Connect'), findsNothing);
    expect(find.byKey(const Key('recovery-username')), findsOneWidget);
  });

  testWidgets('primo passo: nome vuoto, poi la risposta neutra',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester, username: '');

    await tapKey(tester, 'recovery-send');
    expect(find.text('Scrivi il nome utente'), findsOneWidget);
    expect(api.recoveryStarts, isEmpty);

    await tester.enterText(find.byKey(const Key('recovery-username')), ' garg ');
    await tapKey(tester, 'recovery-send');

    expect(api.recoveryStarts.single, ('garg', 'it'));
    expect(
        find.text("Se l'account esiste e ha un contatto collegato, ti abbiamo "
            'mandato un codice su Discord o per email.'),
        findsOneWidget);
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
  });

  testWidgets('primo passo: troppe richieste, poi plugin vecchio',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);

    api.startRecoveryFailure = AccountFailure.rateLimited;
    await tapKey(tester, 'recovery-send');
    expect(find.text('Troppe richieste: riprova più tardi'), findsOneWidget);
    expect(find.byKey(const Key('recovery-code')), findsNothing);

    api.startRecoveryFailure = AccountFailure.unavailable;
    await tapKey(tester, 'recovery-send');
    expect(
        find.text('Il recupero automatico non è disponibile su questo server: '
            "contatta l'amministratore"),
        findsOneWidget);
    expect(find.text("Scrivi all'admin"), findsOneWidget);
    expect(find.text('Nessun contatto collegato?'), findsNothing);
    expect(find.byKey(const Key('recovery-send')), findsNothing);
  });

  testWidgets('secondo passo: controlli ed errori, nessun accesso',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'abc');
    await tapKey(tester, 'recovery-submit');
    expect(find.text('Almeno 6 caratteri'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(find.byKey(const Key('recovery-confirm')), 'nuova124');
    await tapKey(tester, 'recovery-submit');
    expect(find.text('Le password non coincidono'), findsOneWidget);
    expect(api.recoveryCompletes, isEmpty);

    await tester.enterText(find.byKey(const Key('recovery-confirm')), 'nuova123');
    api.completeRecoveryFailure = AccountFailure.invalidCode;
    await tapKey(tester, 'recovery-submit');
    expect(find.text('Codice non valido o scaduto'), findsOneWidget);
    expect(api.recoveryCompletes.single, (
      username: 'garg',
      code: '012345',
      newPassword: 'nuova123',
      language: 'it',
    ));

    api.completeRecoveryFailure = AccountFailure.rateLimited;
    await tapKey(tester, 'recovery-submit');
    expect(
        find.text(
            "Troppi tentativi: riprova tra un'ora o contatta l'amministratore"),
        findsOneWidget);

    // Il 500 di un codice già usato.
    api.completeRecoveryFailure = AccountFailure.serverError;
    await tapKey(tester, 'recovery-submit');
    expect(find.text('Cambio non riuscito: chiedi un nuovo codice'),
        findsOneWidget);

    // Senza rete il codice può essere ancora buono: non se ne chiede un altro.
    api.completeRecoveryFailure = AccountFailure.network;
    await tapKey(tester, 'recovery-submit');
    expect(find.text('WonderFlix non è raggiungibile. Controlla la connessione.'),
        findsOneWidget);
    expect(find.text('Cambio non riuscito: chiedi un nuovo codice'),
        findsNothing);

    expect(session.loginAttempts, isEmpty);
  });

  testWidgets('secondo passo riuscito: entra con la password nuova',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(find.byKey(const Key('recovery-confirm')), 'nuova123');
    await tapKey(tester, 'recovery-submit');

    expect(session.loginAttempts, [('garg', 'nuova123')]);
  });

  testWidgets("mentre il cambio è in volo, 'Torna all'accesso' è spento",
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(find.byKey(const Key('recovery-confirm')), 'nuova123');

    api.gate = Completer<void>();
    await tapKey(tester, 'recovery-submit');
    await tapKey(tester, 'recovery-back');
    expect(find.text('Recupera la password'), findsOneWidget);

    api.gate!.complete();
    await tester.pump();
    expect(session.loginAttempts, [('garg', 'nuova123')]);
  });

  testWidgets("accesso non riuscito dopo il cambio: si riprova solo l'accesso",
      (tester) async {
    session = FakeSessionController(const SessionSignedOut(),
        loginError: const ServerUnreachableException());
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(find.byKey(const Key('recovery-confirm')), 'nuova123');

    await tapKey(tester, 'recovery-submit');
    expect(find.text('WonderFlix non è raggiungibile. Controlla la connessione.'),
        findsOneWidget);

    // Il codice è già usato: il secondo tentativo non lo rimanda.
    await tapKey(tester, 'recovery-submit');
    expect(api.recoveryCompletes, hasLength(1));
    expect(session.loginAttempts,
        [('garg', 'nuova123'), ('garg', 'nuova123')]);
  });

  testWidgets('Rimanda dopo 60 s chiede un codice nuovo', (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.pump(const Duration(seconds: 60));
    await tapKey(tester, 'resend-code');

    expect(api.recoveryStarts, [('garg', 'it'), ('garg', 'it')]);
  });

  testWidgets('Rimanda con troppe richieste: avviso, e il conto riparte',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);
    await tapKey(tester, 'recovery-send');

    await tester.pump(const Duration(seconds: 60));
    api.startRecoveryFailure = AccountFailure.rateLimited;
    await tapKey(tester, 'resend-code');

    expect(find.text('Troppe richieste: riprova più tardi'), findsOneWidget);
    expect(find.text('Rimanda tra 60 s'), findsOneWidget);
    expect(find.byKey(const Key('recovery-code')), findsOneWidget);
  });
}
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/features/auth/recovery_panel_test.dart`
Expected: FAIL (`login-forgot` non esiste: nessun widget trovato, oppure errore di compilazione per un import).

- [ ] **Step 3: il pannello**

Crea `lib/features/auth/recovery_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/error_text.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/social/account_api.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../account/account_providers.dart';
import '../account/account_texts.dart';
import '../account/resend_code_button.dart';
import 'password_login_form.dart';
import 'session_controller.dart';

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 12.5);

/// "Password dimenticata?" (spec L §9.3), al posto del modulo di accesso:
/// il codice ai contatti collegati, poi la password nuova e l'accesso.
class RecoveryPanel extends ConsumerStatefulWidget {
  const RecoveryPanel({super.key, this.initialUsername, required this.onBack});

  /// Il nome scritto nel modulo di accesso.
  final String? initialUsername;

  /// Torna al modulo di accesso, con il nome scritto qui.
  final ValueChanged<String> onBack;

  @override
  ConsumerState<RecoveryPanel> createState() => _RecoveryPanelState();
}

class _RecoveryPanelState extends ConsumerState<RecoveryPanel> {
  late final _username = TextEditingController(text: widget.initialUsername);
  final _code = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  /// Il nome per cui è partito il codice; `null` al primo passo.
  String? _sentFor;

  /// Il plugin non ha il recupero (404): assente o vecchio (spec L §9.1).
  bool _unavailable = false;

  /// La password nuova, già cambiata sul server; `null` finché il cambio non
  /// riesce. Se poi l'accesso non riesce, "Cambia password" riprova solo
  /// l'accesso con questa: il codice è già usato.
  String? _changedTo;
  bool _busy = false;
  String? _usernameError;
  String? _codeError;
  String? _newError;
  String? _confirmError;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _code.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _clearErrors() {
    _usernameError = _codeError = _newError = _confirmError = _error = null;
  }

  /// Chiede il codice per [username]. `null` se la richiesta è passata (la
  /// risposta è la stessa che l'account esista o no), altrimenti l'errore,
  /// già mostrato.
  Future<AccountFailure?> _requestCode(String username) async {
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _busy = true;
      _clearErrors();
    });
    try {
      await ref
          .read(accountApiProvider)
          .startRecovery(username: username, language: language);
      return null;
    } on AccountException catch (error) {
      if (mounted) {
        setState(() {
          switch (error.failure) {
            case AccountFailure.unavailable:
              _unavailable = true;
            case AccountFailure.rateLimited:
              _error = l.accountErrorRateLimited;
            case AccountFailure.network:
              _error = l.errorServerUnreachable;
            case _:
              _error = l.errorGeneric;
          }
        });
      }
      return error.failure;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() =>
          _usernameError = AppLocalizations.of(context).recoveryNameNeeded);
      return;
    }
    if (await _requestCode(username) == null && mounted) {
      setState(() => _sentFor = username);
    }
  }

  /// "Rimanda il codice": il conto riparte se il codice è partito, e anche
  /// dopo un 429 (si aspetta comunque); dopo un altro errore si può
  /// riprovare subito.
  Future<bool> _resend() async {
    final failure = await _requestCode(_sentFor!);
    return failure == null || failure == AccountFailure.rateLimited;
  }

  Future<void> _complete() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final username = _sentFor!;
    final changedTo = _changedTo;
    if (changedTo != null) {
      // Il cambio è già riuscito e l'accesso no: si riprova solo l'accesso,
      // con la password già cambiata (il codice è usato).
      setState(() {
        _busy = true;
        _clearErrors();
      });
      await _signIn(l, username, changedTo);
      return;
    }
    final code = _code.text.trim();
    final password = _new.text;
    setState(() {
      _clearErrors();
      if (code.isEmpty) _codeError = l.accountErrorInvalidCode;
      if (password.length < accountMinPasswordLength) {
        _newError = l.accountPasswordTooShort;
      } else if (_confirm.text != password) {
        _confirmError = l.accountPasswordsDiffer;
      }
    });
    if (_codeError != null || _newError != null || _confirmError != null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(accountApiProvider).completeRecovery(
          username: username,
          code: code,
          newPassword: password,
          language: language);
    } on AccountException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          switch (error.failure) {
            case AccountFailure.invalidCode:
              _codeError = l.accountErrorInvalidCode;
            case AccountFailure.weakPassword:
              _newError = l.accountPasswordTooShort;
            case AccountFailure.rateLimited:
              _error = l.recoveryTooMany;
            // Senza rete il codice può essere ancora buono.
            case AccountFailure.network:
              _error = l.errorServerUnreachable;
            // Anche il 500 di Jellyfin: il codice è già usato (spec L §11).
            case _:
              _error = l.recoveryFailed;
          }
        });
      }
      return;
    }
    _changedTo = password;
    await _signIn(l, username, password);
  }

  /// Entra con la password nuova (spec L §9.3): il profilo salvato prende il
  /// token nuovo. Se l'accesso non riesce, l'errore resta qui e "Cambia
  /// password" riprova solo l'accesso ([_changedTo]).
  Future<void> _signIn(
      AppLocalizations l, String username, String password) async {
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .loginWithPassword(username, password);
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeError(l, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final supportUrl = ref.watch(appConfigProvider).supportUrl;
    final sentFor = _sentFor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('recovery-back'),
            // Spento durante una richiesta: tornando indietro a metà cambio
            // la password cambierebbe senza l'accesso e senza un avviso.
            onPressed: _busy ? null : () => widget.onBack(_username.text),
            icon: const Icon(LucideIcons.arrowLeft, size: 16),
            label: Text(l.recoveryBack),
          ),
        ),
        const SizedBox(height: 8),
        Text(l.recoveryTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        if (_unavailable)
          Text(l.recoveryUnavailable)
        else if (sentFor == null) ...[
          TextField(
            key: const Key('recovery-username'),
            controller: _username,
            autofocus: true,
            onSubmitted: (_) => unawaited(_start()),
            decoration: InputDecoration(
                hintText: l.loginUsername,
                errorText: _usernameError,
                errorMaxLines: accountErrorMaxLines),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('recovery-send'),
            onPressed: _busy ? null : () => unawaited(_start()),
            child: Text(l.accountSendCode),
          ),
        ] else ...[
          Text(l.recoveryCodeSent, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('recovery-code'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
                hintText: l.accountCode,
                errorText: _codeError,
                errorMaxLines: accountErrorMaxLines),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('recovery-new'),
            controller: _new,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
                hintText: l.accountNewPassword,
                errorText: _newError,
                errorMaxLines: accountErrorMaxLines),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('recovery-confirm'),
            controller: _confirm,
            obscureText: true,
            onSubmitted: (_) => unawaited(_complete()),
            decoration: InputDecoration(
                hintText: l.accountConfirmPassword,
                errorText: _confirmError,
                errorMaxLines: accountErrorMaxLines),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('recovery-submit'),
            onPressed: _busy ? null : () => unawaited(_complete()),
            child: Text(l.settingsChangePassword),
          ),
          Align(
            alignment: Alignment.centerLeft,
            // Spento mentre il cambio è in volo: un codice nuovo
            // sostituirebbe quello che si sta usando.
            child: ResendCodeButton(onResend: _busy ? null : _resend),
          ),
        ],
        if (supportUrl != null) ...[
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!_unavailable) Text(l.recoveryNoContact, style: _mutedStyle),
              TextButton(
                onPressed: () => unawaited(launchUrl(supportUrl)),
                child: Text(l.loginContactAdmin),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
```

- [ ] **Step 4: il link nel modulo**

In `lib/features/auth/password_login_form.dart`:
- il costruttore e il campo:

```dart
  const PasswordLoginForm(
      {super.key, this.initialUsername, this.onForgotPassword});

  /// Il nome già scritto ("Accedi di nuovo", spec K §9.3): il fuoco va alla
  /// password.
  final String? initialUsername;

  /// "Password dimenticata?" (spec L §9.3), con il nome scritto; senza, il
  /// link non c'è.
  final ValueChanged<String>? onForgotPassword;
```

- sostituisci il blocco finale `if (supportUrl != null) ...[ … ],` con:

```dart
        if (widget.onForgotPassword != null || supportUrl != null) ...[
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.onForgotPassword case final onForgot?)
                TextButton(
                  key: const Key('login-forgot'),
                  onPressed: () => onForgot(_username.text),
                  child: Text(l.loginForgotPassword),
                ),
              if (supportUrl != null)
                TextButton(
                  onPressed: () => unawaited(launchUrl(supportUrl)),
                  child: Text(l.loginContactAdmin),
                ),
            ],
          ),
        ],
```

- [ ] **Step 5: la seconda vista dell'accesso**

In `lib/features/auth/login_screen.dart`:
- aggiungi `import 'recovery_panel.dart';`;
- sopra la classe `LoginScreen`:

```dart
/// [name] se c'è scritto qualcosa, altrimenti `null`.
String? _nonEmpty(String? name) =>
    name == null || name.trim().isEmpty ? null : name;
```

- in `_LoginScreenState`, prima di `initState`:

```dart
  /// "Password dimenticata?" aperto (spec L §9.3): il pannello mostra il
  /// recupero al posto dell'accesso, anche con Quick Connect.
  bool _recovering = false;

  /// Il nome scritto nell'accesso o nel recupero: passa da uno all'altro.
  String? _typedUsername;
```

- sostituisci la costruzione di `form` (con il suo commento):

```dart
    // Un profilo migrato senza nome (il primo `/Users/Me` non è riuscito):
    // il nome si scrive, e il fuoco resta lì. Tornando dal recupero, il
    // nome scritto lì.
    final form = PasswordLoginForm(
      initialUsername: _nonEmpty(_typedUsername) ?? _nonEmpty(reloginName),
      onForgotPassword: (username) => setState(() {
        _recovering = true;
        _typedUsername = username;
      }),
    );
```

- nella `Column` del pannello (dentro il `Container` largo 380), sostituisci tutta la lista `children: [ … ]` con questa: i figli di oggi (l'avviso della sessione scaduta, Quick Connect o il modulo, "Annulla") passano nel ramo `else` del recupero, uguali:

```dart
                      children: [
                        if (_recovering)
                          RecoveryPanel(
                            initialUsername: _typedUsername,
                            onBack: (username) => setState(() {
                              _recovering = false;
                              _typedUsername = username;
                            }),
                          )
                        else ...[
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
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5),
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
                      ],
```

- [ ] **Step 6: i test passano**

Run: `flutter test test/features/auth/`
Expected: PASS (anche `login_screen_test.dart`: "Scrivi all'admin" c'è ancora).

- [ ] **Step 7: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/auth/recovery_panel.dart lib/features/auth/password_login_form.dart lib/features/auth/login_screen.dart test/features/auth/recovery_panel_test.dart
git commit -m "feat(app): forgot password recovery in the sign-in panel"
```

### Task 9: il promemoria nella cassetta

**Files:**
- Modify: `lib/core/social/inbox_models.dart`
- Create: `lib/features/inbox/inbox_account_row.dart`
- Modify: `lib/features/inbox/inbox_panel.dart`
- Modify: `test/support/social_fakes.dart`
- Modify: `test/core/social/inbox_models_test.dart`
- Create: `test/features/inbox/inbox_contact_reminder_test.dart`

- [ ] **Step 1: i test**

In `test/core/social/inbox_models_test.dart` aggiungi `import 'package:wonderflix/core/social/account_models.dart';` e, in fondo a `main`:

```dart
  test('promemoria dei contatti: i canali, quelli sconosciuti saltati', () {
    final entry = inboxEntryFromJson({
      'Id': 'c1',
      'Seq': 7,
      'Type': 'ContactReminder',
      'CreatedAt': '2026-10-09T08:00:00+00:00',
      'Read': false,
      'Channels': ['Discord', 'Email', 'Telegram'],
    }) as ContactReminderEntry;
    expect(entry.channels, [AccountChannel.discord, AccountChannel.email]);
    expect(entry.seq, 7);
    expect(entry.read, isFalse);
  });

  test('promemoria dei contatti senza canali', () {
    final entry = inboxEntryFromJson({
      'Id': 'c1',
      'Seq': 1,
      'Type': 'ContactReminder',
      'CreatedAt': '2026-10-09T08:00:00+00:00',
    }) as ContactReminderEntry;
    expect(entry.channels, isEmpty);
  });
```

In `test/support/social_fakes.dart` aggiungi `import 'package:wonderflix/core/social/account_models.dart';` e, dopo `testRequestPending`:

```dart
/// Il promemoria dei contatti nella cassetta.
ContactReminderEntry testContactReminder({
  String id = 'c1',
  int seq = 1,
  bool read = false,
  List<AccountChannel> channels = const [
    AccountChannel.discord,
    AccountChannel.email,
  ],
  DateTime? createdAt,
}) =>
    ContactReminderEntry(
      id: id,
      seq: seq,
      createdAt: createdAt ?? DateTime.utc(2026, 10, 9, 8),
      read: read,
      channels: channels,
    );
```

Crea `test/features/inbox/inbox_contact_reminder_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_account_row.dart';
import 'package:wonderflix/features/inbox/inbox_panel.dart';
import 'package:wonderflix/features/library/server_events_binding.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/wf_image.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  /// Apre il pannello con [entries] in un router con Impostazioni.
  Future<(GoRouter, ProviderContainer)> pumpPanel(
      WidgetTester tester, List<InboxEntry> entries) async {
    final api = FakeSocialApi()
      ..inboxSnapshot = InboxSnapshot(entries: entries, unread: entries.length);
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: InboxPanel.width, child: InboxPanel()),
            ),
          ),
        ),
        GoRoute(
            path: '/settings',
            builder: (context, state) => const Text('impostazioni')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        serverEventsBindingProvider.overrideWithValue(null),
        imageBuilderProvider
            .overrideWithValue((image, fit) => const SizedBox.shrink()),
        ...socialTestOverrides(api, features: const SocialFeatures(inbox: true)),
      ],
      retry: (_, _) => null,
      child: MaterialApp.router(
        theme: buildWonderflixTheme(),
        locale: const Locale('it'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(InboxPanel)));
    container.listen(shellPanelProvider, (_, _) {});
    container.read(shellPanelProvider.notifier).open(ShellPanel.inbox);
    await tester.pump();
    return (router, container);
  }

  testWidgets('il clic apre Impostazioni e chiude il pannello',
      (tester) async {
    final (router, container) = await pumpPanel(
        tester, [testContactReminder(channels: const [AccountChannel.email])]);

    expect(find.text('Proteggi il tuo account'), findsOneWidget);
    expect(
        find.text(
            'Collega la tua email per recuperare la password se la dimentichi.'),
        findsOneWidget);

    await tester.tap(find.text('Proteggi il tuo account'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/settings');
    expect(container.read(shellPanelProvider), ShellPanel.none);
  });

  test('i testi per i canali del server', () {
    final l = lookupAppLocalizations(const Locale('it'));
    expect(inboxContactReminderText(l, const [AccountChannel.discord]),
        'Collega Discord per recuperare la password se la dimentichi.');
    expect(inboxContactReminderText(l, const [AccountChannel.email]),
        'Collega la tua email per recuperare la password se la dimentichi.');
    const both =
        'Collega Discord o la tua email per recuperare la password se la dimentichi.';
    expect(
        inboxContactReminderText(
            l, const [AccountChannel.discord, AccountChannel.email]),
        both);
    expect(inboxContactReminderText(l, const []), both);
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/social/inbox_models_test.dart test/features/inbox/inbox_contact_reminder_test.dart`
Expected: FAIL in compilazione (`ContactReminderEntry` non esiste).

- [ ] **Step 3: la voce**

In `lib/core/social/inbox_models.dart`:
- aggiungi `import 'account_models.dart';`;
- dopo `RequestPendingEntry`:

```dart
/// Il promemoria di collegare un contatto per il recupero (spec L §7.7): ce
/// n'è al più uno, per chi non ha un contatto raggiungibile.
final class ContactReminderEntry extends InboxEntry {
  const ContactReminderEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    this.channels = const [],
  });

  /// I canali configurati sul server quando è stato scritto.
  final List<AccountChannel> channels;
}
```

- in `inboxEntryFromJson`, prima di `_ => null,`:

```dart
    'ContactReminder' => ContactReminderEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        channels: [
          for (final raw in json['Channels'] as List? ?? const [])
            if (AccountChannel.fromWire(raw) case final channel?) channel,
        ],
      ),
```

- [ ] **Step 4: la riga**

Crea `lib/features/inbox/inbox_account_row.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Il testo del promemoria per i canali del server (spec L §9.4). Senza un
/// canale noto, quello per tutti e due.
String inboxContactReminderText(
        AppLocalizations l, List<AccountChannel> channels) =>
    switch ((
      channels.contains(AccountChannel.discord),
      channels.contains(AccountChannel.email),
    )) {
      (true, false) => l.inboxContactReminderDiscord,
      (false, true) => l.inboxContactReminderEmail,
      _ => l.inboxContactReminderBoth,
    };

/// Il promemoria dei contatti: il clic chiude il pannello e apre
/// Impostazioni, dove la sezione Account è la prima.
class InboxContactReminderContent extends ConsumerWidget {
  const InboxContactReminderContent({
    super.key,
    required this.channels,
    required this.time,
  });

  final List<AccountChannel> channels;
  final String time;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: () {
          ref.read(shellPanelProvider.notifier).close();
          context.go('/settings');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.inboxContactReminderTitle,
                  style: const TextStyle(
                      color: WfColors.cream, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(inboxContactReminderText(l, channels),
                  style:
                      const TextStyle(color: WfColors.creamMuted, fontSize: 13)),
              const SizedBox(height: 4),
              Text(time,
                  style:
                      const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: nel pannello**

In `lib/features/inbox/inbox_panel.dart`:
- aggiungi `import 'inbox_account_row.dart';`;
- nello `switch` dell'icona di `_EntryTileState.build`, dopo `RequestPendingEntry() => …`:

```dart
              ContactReminderEntry() => const InboxRequestIcon(
                  icon: LucideIcons.shieldCheck, size: InboxPanel.leadingSize),
```

- nello `switch` del contenuto, dopo il ramo `RequestPendingEntry() => InboxRequestContent(…),`:

```dart
                ContactReminderEntry() => InboxContactReminderContent(
                    key: Key('inbox-contact-reminder-${entry.id}'),
                    channels: entry.channels,
                    time: widget.time,
                  ),
```

- [ ] **Step 6: i test passano**

Run: `flutter test test/core/social/inbox_models_test.dart test/features/inbox/`
Expected: PASS.

- [ ] **Step 7: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/core/social/inbox_models.dart lib/features/inbox/inbox_account_row.dart lib/features/inbox/inbox_panel.dart test/support/social_fakes.dart test/core/social/inbox_models_test.dart test/features/inbox/inbox_contact_reminder_test.dart
git commit -m "feat(app): recovery contacts reminder in the inbox"
```

---

## Gruppo D — chiusura

### Task 10: allineamento della spec, checklist, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-09-wonderflix-recupero-password-design.md`
- Modify: `docs/superpowers/plans/2026-10-09-wonderflix-18b-recupero-app-utente.md` (solo la decisione "Dalle review dei gruppi", se ci sono differenze)
- Modify: `docs/RELEASING.md`

- [ ] **Step 1: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "approvato; piani 18a e 18b realizzati (`…18a-recupero-plugin.md`, `…18b-recupero-app-utente.md`); piano 18c da scrivere".
- **§9.1:**
  - `AccountApi` sul client principale, senza token nell'accesso (decisione 5);
  - `AccountFailure` e la sua tabella (decisione 6), al posto di `AccountError`;
  - `changePassword(userId, {currentPassword, newPassword})`.
- **§9.2:**
  - la sezione è `lib/features/settings/account_settings_section.dart`, le righe `AccountContactsBlock`;
  - la password resta nella finestra fra i due passi (decisione 3);
  - "Scollega" anche su un canale spento (decisione 8);
  - gli avvisi "Contatto collegato" / "Contatto scollegato";
  - il 429: "Troppe richieste: riprova più tardi" (decisione 4).
- **§9.3:** il recupero è una seconda vista di `LoginScreen` (`RecoveryPanel`), non `/login/recover` (decisione 1); "Torna all'accesso"; il 429 del primo passo; il 500 del secondo diventa "Cambio non riuscito: chiedi un nuovo codice".
- **§9.4:** il clic apre `/settings` (decisione 2); l'icona è `InboxRequestIcon` con `LucideIcons.shieldCheck`.
- **§10:** i testi veri, con le chiavi (`account…`, `recovery…`, `inboxContactReminder…`, `settingsChangePassword`) e quelli in più della decisione 9.
- **§12:** i test dell'app che esistono davvero; il punto 5 della prova a mano (promemoria) si fa al rilascio, nel 18c (decisione 12).
- **§15:** 18b realizzato.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

Nel piano, se nei task è cambiato qualcosa rispetto al codice scritto qui, aggiungi alle "Decisioni del piano" una voce "Dalle review dei gruppi" con le differenze (come nei piani 17c e 18a).

- [ ] **Step 2: la checklist**

In `docs/RELEASING.md`, nella checklist dei test a mano, dopo le voci delle immagini del profilo, aggiungi (nello stesso stile):
- `- [ ] Impostazioni → Account (in cima): "Cambia password" con la password attuale sbagliata ("Password attuale sbagliata") e giusta (avviso; questo PC resta dentro, jellyfin-web deve rientrare).`
- `- [ ] Contatti per il recupero (plugin 1.6.0): collega Discord (password sbagliata, nome sbagliato, codice sbagliato, codice giusto) ed email; "Rimanda il codice" dopo 60 s; "Scollega" con la password.`
- `- [ ] "Password dimenticata?" nell'accesso con un account di prova non admin con un contatto: il codice arriva, la password nuova fa entrare, arriva l'avviso "password cambiata"; un nome inesistente ha la stessa risposta.`
- `- [ ] Promemoria "Proteggi il tuo account" nella cassetta per un utente senza contatti; il clic apre Impostazioni.`

- [ ] **Step 3: build**

`config/wonderflix.json` deve esserci nel worktree (`config/`); se manca, fermati e segnalalo. Poi:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

Expected: `√ Built build\windows\x64\runner\Release\wonderflix.exe`. Non lanciare l'app.

- [ ] **Step 4: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add docs
git commit -m "docs: align the password recovery spec with plan 18b"
```

### Task 11: prova a mano (orchestratore e utente)

L'utente avvia la build del Task 10 **da Esplora file** (un'app lanciata da Claude scrive AppData in una cartella separata). Sul server c'è la build di prova del plugin 1.6.0.0, con Discord ed email configurati e i promemoria spenti (`ContactReminderDays` = 0: **non** riaccenderli).

**Prima (utente):** nella Dashboard di Jellyfin crea un utente di prova **non admin** con una password (gli admin non hanno il recupero automatico). Credenziali e account li gestisce l'utente.

1. **Cambio password** (con il proprio account): Impostazioni → Account è in cima → "Cambia password":
   - password attuale sbagliata → "Password attuale sbagliata";
   - giusta → "Password cambiata. Gli altri dispositivi dovranno rientrare."; questo PC resta dentro; una sessione di jellyfin-web deve rientrare.
2. **Contatti** (con l'account di prova, aggiunto come profilo):
   - Collega Discord: password sbagliata, un nome che non c'è, il nome giusto; codice sbagliato, codice giusto → "Collegato: …";
   - Collega email: il codice arriva (guardare anche lo spam); "Rimanda il codice" si accende dopo 60 s e ne manda un altro;
   - Scollega email con la password → "Non collegato"; poi ricollegala.
3. **Recupero:** esci dall'account di prova → "Password dimenticata?":
   - il nome dell'account di prova → il codice arriva su Discord ed email;
   - codice sbagliato → "Codice non valido o scaduto"; codice giusto con una password nuova → l'app entra;
   - arriva l'avviso "password cambiata"; un'altra sessione dell'account di prova (jellyfin-web) si chiude;
   - un nome che non esiste → la stessa risposta neutra.
4. **Admin:** con il proprio account admin le righe dei contatti dicono anche "Gli admin non possono usare il recupero automatico."

Il promemoria della cassetta si prova al rilascio (18c), quando i promemoria si riaccendono (decisione 12).

Con l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`). Niente release: l'app 0.12.0 esce con il plugin 1.6.0 alla fine del 18c.

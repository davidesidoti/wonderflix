# WonderFlix — Piano 18c: recupero della password nell'app (lato admin) e release

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** l'ultima parte della Spec L:
- **Amministrazione → Utenti:** gli utenti con i loro contatti per il recupero, e per ognuno "Imposta password", "Invia codice di recupero" e "Scollega contatti";
- **Amministrazione → WonderFlix, card "Recupero password":** stato di Discord ed email, quanti utenti hanno un contatto, promemoria, "Invia prova a me";
- **"Ho già un codice"** nel recupero: il codice mandato dall'admin si usa senza chiederne un altro;
- **la release:** plugin 1.6.0 dal Catalogo, app 0.12.0 non obbligatoria, promemoria riaccesi (14 giorni), `docs/IDEE.md`.

**Spec:** `docs/superpowers/specs/2026-10-09-wonderflix-recupero-password-design.md` (§7.4 admin, §7.6 endpoint dell'admin, §9.3, §9.5, §9.6, §10 testi dell'admin, §12, §15).

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 8):
1. **Gli endpoint dell'admin stanno in `PluginAdminApi`, non in `AccountApi`.** `PluginAdminApi` è già "gli endpoint da admin del plugin" e lancia `ApiException` come Jellyfin: così valgono le regole della pagina Amministrazione (`AdminTabController.act`, che a un 403 rilegge l'utente e porta via la pagina a chi non è più admin; `AdminActionButton`; `describeError`). Il `{Code}` del plugin si legge con `pluginErrorCode(error)`. `AccountFailure` resta del lato utente: niente `NotAllowed`, `NoContacts` e `UnknownUser` lì (cambia la nota del 18b in §9.1 e §15).
2. **La scheda Utenti usa `AdminTabController`**, con una rilettura ogni 2 minuti oltre all'apertura e alle azioni (la spec diceva "niente `AdminPoller`"): l'infrastruttura delle schede (dati non aggiornati, "Riprova", rilettura dopo un riavvio di Jellyfin, 403) vuole un intervallo, e 2 minuti costano una lettura in memoria del plugin.
3. **"Recupero password" è una card della scheda WonderFlix**, dopo Seerr (la "scheda accanto a Seerr" di §9.6), e c'è solo con la funzione `account`.
4. **Le azioni di una riga** (`userActions`):
   - "Imposta password" su tutte le righe tranne la propria: per la propria Jellyfin vuole la password attuale anche da un admin, e c'è "Cambia password" in Impostazioni. Gli id si confrontano con `jellyfinIdKey`;
   - "Invia codice di recupero" solo per chi non è admin, è attivo e ha almeno un contatto. Un contatto su un canale spento dà `NoContacts` dal plugin, con il suo testo;
   - "Scollega contatti" solo con un contatto;
   - senza azioni, niente menu. Mentre un'azione è in corso il menu della riga è spento.
5. **Gli avatar delle righe con `UserAvatar.lookup`:** l'elenco del plugin non ha il tag dell'immagine.
6. **"Imposta password"** è una finestra sua (`SetPasswordDialog`): nuova password e conferma, almeno 6 caratteri, la frase "Le sessioni di {nome} verranno chiuse.". Come le finestre del 18b non si chiude durante la richiesta, e gli errori vanno sopra i campi (502/503/504 → "non raggiungibile"). Passa da `AccountUsersController.setPassword`, cioè da `act`.
7. **`NotAllowed`** dice "Gli admin e gli utenti disattivati non possono usare il recupero automatico": il plugin lo dà per tutti e due. Arriva solo con un elenco vecchio, perché il menu non offre il codice a loro.
8. **"Ho già un codice"** (non nella spec): senza, il codice mandato dall'admin non serviva, perché il primo passo del recupero ne chiedeva un altro che lo sostituiva. Porta al secondo passo con il nome scritto, senza chiamare `Start`, e il testo sopra il campo diventa "Scrivi il codice che hai ricevuto su Discord o per email.".
9. **La prova del promemoria vero** (punto 5 di §12) si fa nella release, dopo aver riacceso i promemoria.
10. **Dalle review dei gruppi** (il codice dei task sotto è quello di partenza: dove differisce, vale questa lista):
    - **Gruppo A** (i Task 4 e 5 sotto sono già aggiornati):
      - `_accountQuiet` è `{400, 403, 404, 409, ...restartGatewayStatuses}`: il 502 c'è già in `restartGatewayStatuses`, e un elemento doppio in un set costante non compila;
      - `NoContacts` arriva solo con un contatto su un canale spento (il menu offre il codice solo a chi ha un contatto): il testo è "{name} non ha contatti su un canale attivo", non "non ha contatti collegati";
      - la conferma dello scollegamento è "Scollegare i contatti di {name}?" (vale anche con un solo contatto); in inglese "…change their password?" e "Reminders every {days} days";
      - `accountAdminErrorText` dice "non raggiungibile" per 502/503/504 senza `Code`; lo usa anche `SetPasswordDialog`;
      - `sendRecoveryCode` lancia `ServerErrorException` se i canali noti sono zero;
      - il finto `unlinkContacts` toglie i contatti dall'elenco, come il plugin; test più precisi sui tipi degli errori e sui campi obbligatori.
    - **Gruppo B:**
      - in `users_tab.dart` `String text;` e non `final String text;` in `_sendRecovery` e `_unlink`: assegnata nel `try` e nel `catch`, con `final` non compila; due test in più in `wonderflix_tab_test.dart` (la card nella scheda, solo con `account`);
      - la riga in azione e la card durante la prova restano vive anche fuori vista (`AutomaticKeepAliveClientMixin`): la `ListView` le smontava, l'avviso si perdeva e il menu tornava acceso, e un secondo codice avrebbe sostituito il primo;
      - la card azzera l'esito all'inizio di una prova: dopo una prova fallita non resta quello vecchio;
      - "Ho già un codice": dopo un "Rimanda" riuscito il testo torna "Se l'account esiste…" (il codice dell'admin non vale più); un 404 a `Complete` dice che il recupero non è disponibile;
      - la riga: nome ed etichette in un `Expanded`, senza `Spacer` (un nome lungo si troncava a metà riga); il menu dice allo screen reader di chi è ("Azioni per {name}", `adminUsersActionsFor`);
      - test in più: la propria riga con un id in un altro formato, la riga senza menu, il menu spento durante un'azione, Utenti → Sessioni quando sparisce `account`, la card con i dati non aggiornati e gli errori, l'elenco vuoto, Esc con `pumpAndSettle`.
    - **Altre, viste nel Task 8** confrontando i task con il codice:
      - Task 1: la chiave `adminUsersActions` ("Azioni") non c'è; al suo posto `adminUsersActionsFor` ("Azioni per {name}", gruppo B), anche nel test dei testi;
      - Task 2: il finto ha `accountActionGate`, un `Completer` che tiene in corso codice, scollegamento e prova finché il test non lo completa (per i test del gruppo B sul menu spento e sulle righe e la card fuori vista);
      - Task 3: `recoverySentLabel` ha il caso `(true, true)` scritto, con un commento (zero canali non arrivano: `sendRecoveryCode` lancia); due test in più nei controller, lo scollegamento che rilegge la riga senza contatti e un 403 del plugin che fa rileggere l'utente;
      - Task 7: tre test in più per "Ho già un codice": "Rimanda" riuscito e non riuscito, il 404 a `Complete`.

**Architecture:**
- **Dati:** in `lib/core/social/plugin_admin_models.dart` `AdminAccountUser`, `AccountSendError`, `AccountChannelStatus`, `AccountAdminStatus`, `AccountTestResult`; in `lib/core/social/plugin_admin_api.dart` `accountUsers`, `sendRecoveryCode`, `unlinkContacts`, `accountStatus`, `testAccountChannels` e `pluginErrorCode`.
- **Amministrazione** (`lib/features/admin/`):
  - `account_admin_controllers.dart`: `AccountUsersController` e `AccountAdminController`;
  - `account_admin_labels.dart`: i testi degli esiti e degli errori;
  - `set_password_dialog.dart`: la finestra "Imposta password";
  - `users_tab.dart`: la scheda Utenti (`UsersTab`, `AccountUserRow`, `userActions`);
  - `account_recovery_card.dart`: la card "Recupero password";
  - `AdminTab.users` in `admin_navigation.dart`, `admin_screen.dart`, `wonderflix_tab.dart`.
- **Recupero:** "Ho già un codice" in `lib/features/auth/recovery_panel.dart`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.3.2, go_router, dio, lucide_icons_flutter 3.1.20; plugin .NET 9 (solo release).

**Worktree:** `.claude/worktrees/piano-18c`, branch `feat/piano-18c`. **Base:** `main` con questo piano. **Test a inizio piano:** 2555 Flutter (fine del 18b) e 748 plugin (il plugin qui non cambia).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-18c`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(app): …"`. Un messaggio su più righe va in un file e si usa `git commit -F <file>`.
- **Prima di ogni commit:** `flutter analyze` senza problemi e `flutter test` tutto verde (la suite intera).
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit (e all'inizio, se li trovi già così).
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati. Righe entro 80 colonne dove si può.
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content`, `Out-File` o `sed -i` sui sorgenti.
- **Durate, misure, limiti:** costanti nominate e commentate.
- **Lingua del codice:** commenti in italiano, codice in inglese.
- **UI:** icone solo `LucideIcons`; colori `WfColors`; `clock.now()`, mai `DateTime.now()`.
- **Spinner e `pumpAndSettle`:** un `CircularProgressIndicator` senza valore non si ferma mai, quindi `pumpAndSettle` va in timeout. Mentre c'è un indicatore, usa `pump()`.
- **Provider:** nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`. I container dei test hanno `retry: (_, _) => null`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa, un test che con dio vuole `pumpAndSettle` invece di `pump`):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

- **Endpoint dell'admin del plugin 1.6.0** (`Api/AccountAdminController.cs`, `Protocol/AccountDtos.cs`), base `WonderFlixWatchParty/Account/Admin`, `RequiresElevation`:
  - `GET Users` → 200 `[{Id, Name, IsAdmin, Enabled, Discord: {Name}?, Email: {Masked}?, LastReminderAt?}]`, già in ordine di nome (senza badare alle maiuscole). `Id` è nel formato `N`; l'email è mascherata (`m•••@example.com`);
  - `POST Users/{id}/Recovery {Language}` → 200 `{Channels: ["Discord", "Email"]}` (i canali dove è arrivato) · 400 `UnknownUser` · 403 `NotAllowed` (admin o disattivato) · 409 `NoContacts` · 502 `SendFailed`;
  - `DELETE Users/{id}/Contacts` → 204 · 400 `UnknownUser`. Annulla anche i codici già mandati;
  - `GET Status` → `{Discord: {Configured, LastError: {At, Code}?}, Email: {…}, WithContacts, Users, ReminderDays}`. `Users` sono gli utenti attivi e non admin, `WithContacts` quelli fra loro con un contatto raggiungibile. `LastError.Code` è `DmClosed`, `SendFailed` o `Invalid`;
  - `POST Test {Language, Discord?, Email?}` → 200 `{Discord, Email}`, gli esiti di `AccountTestCodes`: `Ok`, `NotConfigured`, `NoContact`, `Invalid`, `MemberNotFound`, `InvalidTarget`, `DmClosed`, `SendFailed`. Senza `Discord` ed `Email` la prova va ai contatti dell'admin; dura al più circa 24 s (il client ha 30 s).
- **Il codice mandato dall'admin** è un codice di recupero come gli altri (`CodePurpose.Recovery`): si usa con `Recovery/Complete`. Un nuovo `Recovery/Start` lo sostituisce.
- **Jellyfin 10.11.9, `POST /Users/Password?userId=`** con `{NewPw}` da un admin per un altro utente: niente `CurrentPw`, e Jellyfin chiude le sessioni di quell'utente (`RevokeUserTokens(user.Id, currentToken)`: il token dell'admin non è suo). `AuthApi.changePassword(userId, newPassword:)` c'è già (18b).
- **Pagina Amministrazione:**
  - `AdminTabController<T>` (`admin_tab_controller.dart`): `fetch`, `interval`, `refresh`, `act` (a un 403 rilegge l'utente; dopo un'azione riuscita rilegge e poi risponde). `AdminData` ha `value`, `error`, `updatedAt` e `stale`;
  - `AdminTab` e `adminTabs` in `admin_navigation.dart`; `admin_screen.dart` aspetta le funzioni del plugin se la scheda dell'indirizzo è del plugin e le funzioni non sono note;
  - widget: `AdminCard`, `AdminCardError`, `AdminStaleNote`, `AdminEmptyText` (`admin_widgets.dart`), `AdminActionButton`, `showAdminConfirmDialog`, `LoadingView`/`ErrorView`/`SkeletonBox` (`lib/ui/states.dart`), `wfPopUpAnimation` (`lib/ui/wf_menus.dart`);
  - test: `test/support/admin_fakes.dart` (`FakePluginAdminApi implements PluginAdminApi`: **ogni metodo nuovo di `PluginAdminApi` va aggiunto al finto nello stesso commit**, altrimenti non compila; `adminTestOverrides(api, {session, plugin, features, availability})`; `testAdmin` = `JellyfinUser(id: 'u1', name: 'Mario', isAdministrator: true)`).
- **Json:** `jsonString`, `jsonDate`, `jsonMap` in `lib/core/jellyfin/json_fields.dart`; `_required<T>` in `plugin_admin_models.dart` (lancia `ServerErrorException(null)`). `jellyfinIdKey(id)` toglie i trattini e mette in minuscolo.
- **ARB:** `app_it.arb` e `app_en.arb` hanno le stesse chiavi (il test `l10n_plan18b_test.dart` lo controlla). I plurali come `adminNewTitlesPending`.
- **Icone verificate in 3.1.20:** `ellipsisVertical`, `keyRound`, `send`, `messageCircle`, `mail`.
- **Server oggi:** build di prova del plugin 1.6.0.0 in `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.6.0.0`, promemoria a 0; la 1.5.0.0 del Catalogo è in `~/wfwp-backup/1.5.0.0-catalogo`. Il `manifest.json` ha ancora la 1.5.0.0 in cima; `meta.template.json` ha già `description` e `overview` con il recupero della password. App: `pubspec.yaml` a `0.11.0`, ultimo tag `v0.11.0`.

---

## Gruppo A — dati

### Task 1: i testi

**Files:**
- Modify: `l10n/app_it.arb`
- Modify: `l10n/app_en.arb`
- Create: `test/app/l10n_plan18c_test.dart`

- [ ] **Step 1: il test**

Crea `test/app/l10n_plan18c_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 18c', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.adminTabUsers, 'Utenti');
    expect(it.adminUsersPasswordSet('garg'),
        'Password impostata. Le sessioni di garg sono state chiuse.');
    expect(it.adminUsersSendRecoveryConfirm('garg'),
        'Mandare a garg un codice per cambiare la password?');
    expect(it.adminUsersNoContacts('garg'), 'garg non ha contatti collegati');
    expect(it.adminUsersUnlinkConfirm('garg'),
        'Scollegare Discord ed email di garg?');
    expect(it.adminRecoveryWithContacts(5, 23),
        '5 utenti su 23 hanno un contatto');
    expect(it.adminRecoveryWithContacts(1, 23),
        '1 utente su 23 ha un contatto');
    expect(it.adminRecoveryReminders(14), 'Promemoria ogni 14 giorni');
    expect(it.adminRecoveryReminders(1), 'Promemoria ogni giorno');
    expect(it.adminRecoveryLastError('DM chiusi', '2 h fa'),
        'Ultimo errore: DM chiusi, 2 h fa');
    expect(it.recoveryHaveCode, 'Ho già un codice');
    expect(en.adminTabUsers, 'Users');
    expect(en.adminRecoveryWithContacts(5, 23),
        '5 users out of 23 have a contact');
    expect(en.recoveryHaveCode, 'I already have a code');
  });
}
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/app/l10n_plan18c_test.dart`
Expected: FAIL in compilazione (`adminTabUsers` non esiste).

- [ ] **Step 3: italiano**

In `l10n/app_it.arb`, dopo l'ultima voce (aggiungi la virgola in fondo a quella riga), prima della `}` finale:

```json
  "adminTabUsers": "Utenti",
  "adminUsersAdmin": "Admin",
  "adminUsersDisabled": "Disattivato",
  "adminUsersEmpty": "Nessun utente",
  "adminUsersActions": "Azioni",
  "adminUsersDiscordLinked": "Discord: {name}",
  "@adminUsersDiscordLinked": {"placeholders": {"name": {"type": "String"}}},
  "adminUsersDiscordNone": "Discord non collegato",
  "adminUsersEmailLinked": "Email: {email}",
  "@adminUsersEmailLinked": {"placeholders": {"email": {"type": "String"}}},
  "adminUsersEmailNone": "Email non collegata",
  "adminUsersSetPassword": "Imposta password",
  "adminUsersSetPasswordTitle": "Imposta la password di {name}",
  "@adminUsersSetPasswordTitle": {"placeholders": {"name": {"type": "String"}}},
  "adminUsersSetPasswordHint": "Le sessioni di {name} verranno chiuse.",
  "@adminUsersSetPasswordHint": {"placeholders": {"name": {"type": "String"}}},
  "adminUsersPasswordSet": "Password impostata. Le sessioni di {name} sono state chiuse.",
  "@adminUsersPasswordSet": {"placeholders": {"name": {"type": "String"}}},
  "adminUsersSendRecovery": "Invia codice di recupero",
  "adminUsersSendRecoveryConfirm": "Mandare a {name} un codice per cambiare la password?",
  "@adminUsersSendRecoveryConfirm": {"placeholders": {"name": {"type": "String"}}},
  "adminUsersRecoverySentBoth": "Codice mandato su Discord ed email",
  "adminUsersRecoverySentDiscord": "Codice mandato su Discord",
  "adminUsersRecoverySentEmail": "Codice mandato per email",
  "adminUsersNoContacts": "{name} non ha contatti collegati",
  "@adminUsersNoContacts": {"placeholders": {"name": {"type": "String"}}},
  "adminUsersNotAllowed": "Gli admin e gli utenti disattivati non possono usare il recupero automatico",
  "adminUsersUnknown": "Questo utente non c'è più",
  "adminUsersUnlink": "Scollega contatti",
  "adminUsersUnlinkConfirm": "Scollegare Discord ed email di {name}?",
  "@adminUsersUnlinkConfirm": {"placeholders": {"name": {"type": "String"}}},
  "adminUsersUnlinked": "Contatti di {name} scollegati",
  "@adminUsersUnlinked": {"placeholders": {"name": {"type": "String"}}},
  "adminRecovery": "Recupero password",
  "adminRecoveryConfigured": "configurato",
  "adminRecoveryNotConfigured": "non configurato",
  "adminRecoveryChannelLine": "{channel}: {state}",
  "@adminRecoveryChannelLine": {"placeholders": {"channel": {"type": "String"}, "state": {"type": "String"}}},
  "adminRecoveryLastError": "Ultimo errore: {error}, {when}",
  "@adminRecoveryLastError": {"placeholders": {"error": {"type": "String"}, "when": {"type": "String"}}},
  "adminRecoveryErrorDmClosed": "DM chiusi",
  "adminRecoveryErrorInvalid": "token o server non validi",
  "adminRecoveryErrorSendFailed": "invio non riuscito",
  "adminRecoveryWithContacts": "{count, plural, =1{1 utente su {total} ha un contatto} other{{count} utenti su {total} hanno un contatto}}",
  "@adminRecoveryWithContacts": {"placeholders": {"count": {"type": "int"}, "total": {"type": "int"}}},
  "adminRecoveryReminders": "{days, plural, =1{Promemoria ogni giorno} other{Promemoria ogni {days} giorni}}",
  "@adminRecoveryReminders": {"placeholders": {"days": {"type": "int"}}},
  "adminRecoveryRemindersOff": "Promemoria spenti",
  "adminRecoveryTest": "Invia prova a me",
  "adminRecoveryTestSent": "inviato",
  "adminRecoveryTestNoContact": "collega prima il tuo contatto",
  "adminRecoveryTestDmClosed": "il bot non riesce a scriverti",
  "adminRecoveryTestMemberNotFound": "nome non trovato nel server",
  "adminRecoveryTestInvalidTarget": "contatto non valido",
  "adminRecoveryConfigHint": "Si configura nella Dashboard di Jellyfin → Plugin → WonderFlix",
  "recoveryHaveCode": "Ho già un codice",
  "recoveryEnterCode": "Scrivi il codice che hai ricevuto su Discord o per email."
```

- [ ] **Step 4: inglese**

In `l10n/app_en.arb`, dopo l'ultima voce (aggiungi la virgola), prima della `}` finale:

```json
  "adminTabUsers": "Users",
  "adminUsersAdmin": "Admin",
  "adminUsersDisabled": "Disabled",
  "adminUsersEmpty": "No users",
  "adminUsersActions": "Actions",
  "adminUsersDiscordLinked": "Discord: {name}",
  "adminUsersDiscordNone": "Discord not linked",
  "adminUsersEmailLinked": "Email: {email}",
  "adminUsersEmailNone": "Email not linked",
  "adminUsersSetPassword": "Set password",
  "adminUsersSetPasswordTitle": "Set {name}'s password",
  "adminUsersSetPasswordHint": "{name}'s sessions will be closed.",
  "adminUsersPasswordSet": "Password set. {name}'s sessions have been closed.",
  "adminUsersSendRecovery": "Send recovery code",
  "adminUsersSendRecoveryConfirm": "Send {name} a code to change the password?",
  "adminUsersRecoverySentBoth": "Code sent on Discord and by email",
  "adminUsersRecoverySentDiscord": "Code sent on Discord",
  "adminUsersRecoverySentEmail": "Code sent by email",
  "adminUsersNoContacts": "{name} has no linked contacts",
  "adminUsersNotAllowed": "Admins and disabled users can't use automatic recovery",
  "adminUsersUnknown": "This user no longer exists",
  "adminUsersUnlink": "Unlink contacts",
  "adminUsersUnlinkConfirm": "Unlink {name}'s Discord and email?",
  "adminUsersUnlinked": "{name}'s contacts unlinked",
  "adminRecovery": "Password recovery",
  "adminRecoveryConfigured": "configured",
  "adminRecoveryNotConfigured": "not configured",
  "adminRecoveryChannelLine": "{channel}: {state}",
  "adminRecoveryLastError": "Last error: {error}, {when}",
  "adminRecoveryErrorDmClosed": "DMs closed",
  "adminRecoveryErrorInvalid": "invalid token or server",
  "adminRecoveryErrorSendFailed": "sending failed",
  "adminRecoveryWithContacts": "{count, plural, =1{1 user out of {total} has a contact} other{{count} users out of {total} have a contact}}",
  "adminRecoveryReminders": "{days, plural, =1{Reminder every day} other{Reminder every {days} days}}",
  "adminRecoveryRemindersOff": "Reminders off",
  "adminRecoveryTest": "Send me a test",
  "adminRecoveryTestSent": "sent",
  "adminRecoveryTestNoContact": "link your contact first",
  "adminRecoveryTestDmClosed": "the bot can't message you",
  "adminRecoveryTestMemberNotFound": "name not found in the server",
  "adminRecoveryTestInvalidTarget": "invalid contact",
  "adminRecoveryConfigHint": "Configured in the Jellyfin Dashboard → Plugins → WonderFlix",
  "recoveryHaveCode": "I already have a code",
  "recoveryEnterCode": "Enter the code you received on Discord or by email."
```

- [ ] **Step 5: genera e prova**

```powershell
flutter gen-l10n
flutter test test/app/l10n_plan18c_test.dart test/app/l10n_plan18b_test.dart
```

Expected: PASS (il test del 18b controlla che le due lingue abbiano le stesse chiavi).

- [ ] **Step 6: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add l10n test/app/l10n_plan18c_test.dart
git commit -m "feat(app): texts for the admin side of password recovery"
```

### Task 2: modelli e `PluginAdminApi`

**Files:**
- Modify: `lib/core/social/plugin_admin_models.dart`
- Modify: `lib/core/social/plugin_admin_api.dart`
- Modify: `test/support/admin_fakes.dart`
- Create: `test/core/social/account_admin_api_test.dart`

- [ ] **Step 1: il test**

Crea `test/core/social/account_admin_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/core/social/plugin_admin_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late PluginAdminApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = PluginAdminApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('utenti: contatti, email mascherata, ultimo promemoria', () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {
            'Id': 'a1',
            'Name': 'garg',
            'IsAdmin': false,
            'Enabled': true,
            'Discord': {'Name': 'garg'},
            'Email': {'Masked': 'g•••@example.com'},
            'LastReminderAt': '2026-10-01T08:00:00+00:00',
          },
          {
            'Id': 'a2',
            'Name': 'Mario',
            'IsAdmin': true,
            'Enabled': true,
            'Discord': null,
            'Email': null,
            'LastReminderAt': null,
          },
        ]);

    final users = await api.accountUsers();

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Account/Admin/Users');
    expect(users.map((u) => u.name), ['garg', 'Mario']);
    expect(users[0].discordName, 'garg');
    expect(users[0].maskedEmail, 'g•••@example.com');
    expect(users[0].hasContacts, isTrue);
    expect(users[0].lastReminderAt, DateTime.utc(2026, 10, 1, 8));
    expect(users[1].isAdmin, isTrue);
    expect(users[1].hasContacts, isFalse);
  });

  test('utenti: senza Id, Name, IsAdmin o Enabled la risposta non vale',
      () async {
    adapter.handler = (_) => const FakeResponse(200, [
          {'Id': 'a1', 'Name': 'garg', 'IsAdmin': false},
        ]);
    await expectLater(
        api.accountUsers(), throwsA(isA<ServerErrorException>()));

    adapter.handler = (_) => const FakeResponse(200, {'Users': []});
    await expectLater(
        api.accountUsers(), throwsA(isA<ServerErrorException>()));
  });

  test('codice di recupero: lingua nel corpo, i canali usati', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Channels': ['Discord', 'Email', 'Telegram'],
        });

    final channels = await api.sendRecoveryCode('a1', language: 'it');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path,
        '/WonderFlixWatchParty/Account/Admin/Users/a1/Recovery');
    expect(request.data, {'Language': 'it'});
    expect(channels, [AccountChannel.discord, AccountChannel.email]);
  });

  test('scollegamento: DELETE dei contatti', () async {
    await api.unlinkContacts('a1');

    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Account/Admin/Users/a1/Contacts');
  });

  test('stato: canali, ultimo errore, conteggi, promemoria', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Discord': {
            'Configured': true,
            'LastError': {'At': '2026-10-09T08:00:00+00:00', 'Code': 'DmClosed'},
          },
          'Email': {'Configured': false, 'LastError': null},
          'WithContacts': 5,
          'Users': 23,
          'ReminderDays': 0,
        });

    final status = await api.accountStatus();

    expect(adapter.requests.single.path,
        '/WonderFlixWatchParty/Account/Admin/Status');
    expect(status.discord.configured, isTrue);
    expect(status.discord.lastError!.code, 'DmClosed');
    expect(status.discord.lastError!.at, DateTime.utc(2026, 10, 9, 8));
    expect(status.channel(AccountChannel.email).configured, isFalse);
    expect(status.email.lastError, isNull);
    expect(status.withContacts, 5);
    expect(status.users, 23);
    expect(status.reminderDays, 0);
  });

  test('stato: i campi obbligatori ci devono essere', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Discord': {'Configured': true},
          'WithContacts': 5,
          'Users': 23,
          'ReminderDays': 14,
        });
    await expectLater(
        api.accountStatus(), throwsA(isA<ServerErrorException>()));
  });

  test('prova: solo la lingua nel corpo; un esito per canale', () async {
    adapter.handler =
        (_) => const FakeResponse(200, {'Discord': 'Ok', 'Email': 'NoContact'});

    final result = await api.testAccountChannels(language: 'en');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/WonderFlixWatchParty/Account/Admin/Test');
    // Senza Discord ed Email: la prova va ai contatti dell'admin (spec L
    // §9.6).
    expect(request.data, {'Language': 'en'});
    expect(result.of(AccountChannel.discord), 'Ok');
    expect(result.of(AccountChannel.email), 'NoContact');
  });

  test('errori del codice: il Code del plugin si legge, nel log come info',
      () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);

    final cases = <(int, String)>[
      (403, 'NotAllowed'),
      (409, 'NoContacts'),
      (502, 'SendFailed'),
      (400, 'UnknownUser'),
    ];
    for (final (status, code) in cases) {
      adapter.handler = (_) => FakeResponse(status, {'Code': code});
      Object? caught;
      try {
        await api.sendRecoveryCode('a1', language: 'it');
      } on Object catch (error) {
        caught = error;
      }
      expect(caught, isA<ApiException>(), reason: '$status');
      expect(pluginErrorCode(caught!), code, reason: '$status');
    }
    expect([
      for (final record in records)
        if (record.loggerName == 'http') record.level,
    ], List.filled(cases.length, Level.INFO));
  });

  test('pluginErrorCode: senza Code, o un errore che non viene dal server',
      () {
    expect(pluginErrorCode(const ForbiddenException()), isNull);
    expect(pluginErrorCode(const ServerErrorException(500, 'testo')), isNull);
    expect(pluginErrorCode(const ServerErrorException(409, {'Code': 3})),
        isNull);
    expect(pluginErrorCode(StateError('x')), isNull);
  });
}
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/core/social/account_admin_api_test.dart`
Expected: FAIL in compilazione (`accountUsers` non esiste).

- [ ] **Step 3: i modelli**

In fondo a `lib/core/social/plugin_admin_models.dart` (aggiungi in cima `import 'account_models.dart';`):

```dart
/// Un utente nell'elenco del recupero (`Account/Admin/Users`, spec L §7.6).
class AdminAccountUser {
  const AdminAccountUser({
    required this.id,
    required this.name,
    required this.isAdmin,
    required this.enabled,
    this.discordName,
    this.maskedEmail,
    this.lastReminderAt,
  });

  /// `Id`, `Name`, `IsAdmin` ed `Enabled` ci devono essere; i contatti e
  /// l'ultimo promemoria no.
  factory AdminAccountUser.fromJson(Map<String, dynamic> json) =>
      AdminAccountUser(
        id: _required<String>(json, 'Id'),
        name: _required<String>(json, 'Name'),
        isAdmin: _required<bool>(json, 'IsAdmin'),
        enabled: _required<bool>(json, 'Enabled'),
        discordName: jsonString(
            jsonMap(json['Discord']) ?? const <String, dynamic>{}, 'Name'),
        maskedEmail: jsonString(
            jsonMap(json['Email']) ?? const <String, dynamic>{}, 'Masked'),
        lastReminderAt: jsonDate(json, 'LastReminderAt'),
      );

  /// Nel formato `N` di Jellyfin.
  final String id;
  final String name;
  final bool isAdmin;
  final bool enabled;

  /// Il nome utente Discord collegato; `null` se non c'è.
  final String? discordName;

  /// L'email collegata, mascherata dal plugin ("m•••@example.com"); `null`
  /// se non c'è.
  final String? maskedEmail;

  final DateTime? lastReminderAt;

  bool get hasContacts => discordName != null || maskedEmail != null;
}

/// L'ultimo errore d'invio di un canale.
class AccountSendError {
  const AccountSendError({required this.at, required this.code});

  /// `At` e `Code` ci devono essere.
  factory AccountSendError.fromJson(Map<String, dynamic> json) {
    final at = jsonDate(json, 'At');
    if (at == null) throw const ServerErrorException(null);
    return AccountSendError(at: at, code: _required<String>(json, 'Code'));
  }

  final DateTime at;

  /// `DmClosed`, `SendFailed` o `Invalid`.
  final String code;
}

/// Un canale del recupero: configurato, e l'ultimo errore d'invio.
class AccountChannelStatus {
  const AccountChannelStatus({required this.configured, this.lastError});

  /// `Configured` ci deve essere.
  factory AccountChannelStatus.fromJson(Map<String, dynamic> json) {
    final error = jsonMap(json['LastError']);
    return AccountChannelStatus(
      configured: _required<bool>(json, 'Configured'),
      lastError: error == null ? null : AccountSendError.fromJson(error),
    );
  }

  final bool configured;
  final AccountSendError? lastError;
}

/// Lo stato del recupero (`Account/Admin/Status`, spec L §7.6).
class AccountAdminStatus {
  const AccountAdminStatus({
    required this.discord,
    required this.email,
    required this.withContacts,
    required this.users,
    required this.reminderDays,
  });

  /// Tutti i campi ci devono essere.
  factory AccountAdminStatus.fromJson(Map<String, dynamic> json) {
    final discord = jsonMap(json['Discord']);
    final email = jsonMap(json['Email']);
    if (discord == null || email == null) {
      throw const ServerErrorException(null);
    }
    return AccountAdminStatus(
      discord: AccountChannelStatus.fromJson(discord),
      email: AccountChannelStatus.fromJson(email),
      withContacts: _required<int>(json, 'WithContacts'),
      users: _required<int>(json, 'Users'),
      reminderDays: _required<int>(json, 'ReminderDays'),
    );
  }

  final AccountChannelStatus discord;
  final AccountChannelStatus email;

  /// Utenti attivi e non admin con almeno un contatto raggiungibile.
  final int withContacts;

  /// Utenti attivi e non admin.
  final int users;

  /// Ogni quanti giorni il promemoria; 0: spento.
  final int reminderDays;

  AccountChannelStatus channel(AccountChannel channel) => switch (channel) {
        AccountChannel.discord => discord,
        AccountChannel.email => email,
      };
}

/// L'esito di "Invia prova a me" per canale: un `AccountTestCodes` del
/// plugin (`Ok`, `NotConfigured`, `NoContact`, `Invalid`, `DmClosed`,
/// `SendFailed`…).
class AccountTestResult {
  const AccountTestResult({required this.discord, required this.email});

  /// `Discord` ed `Email` ci devono essere.
  factory AccountTestResult.fromJson(Map<String, dynamic> json) =>
      AccountTestResult(
        discord: _required<String>(json, 'Discord'),
        email: _required<String>(json, 'Email'),
      );

  final String discord;
  final String email;

  String of(AccountChannel channel) => switch (channel) {
        AccountChannel.discord => discord,
        AccountChannel.email => email,
      };
}
```

- [ ] **Step 4: il client**

In `lib/core/social/plugin_admin_api.dart` aggiungi `import 'account_models.dart';`. Nella classe, dopo `_configQuiet`:

```dart
  static const _account = '$_base/Account/Admin';

  /// Esiti attesi delle azioni sugli utenti (spec L §7.6): utente
  /// sconosciuto (400), admin o disattivato (403 `NotAllowed`), senza
  /// contatti (409), invio non riuscito (502). Nel log come info.
  static const _accountQuiet = {400, 403, 404, 409, 502, ...restartGatewayStatuses};
```

e in fondo alla classe:

```dart
  /// Gli utenti con i loro contatti per il recupero, in ordine di nome.
  Future<List<AdminAccountUser>> accountUsers() async {
    final json = await _http.get('$_account/Users', quietStatuses: _quiet);
    if (json is! List) throw const ServerErrorException(null);
    return [for (final raw in json) parseJson(raw, AdminAccountUser.fromJson)];
  }

  /// Manda all'utente un codice di recupero: i canali dove è arrivato. Gli
  /// errori hanno il `{Code}` del plugin ([pluginErrorCode]).
  Future<List<AccountChannel>> sendRecoveryCode(String userId,
      {required String language}) async {
    final json = asJsonMap(await _http.post('$_account/Users/$userId/Recovery',
        body: {'Language': language}, quietStatuses: _accountQuiet));
    final channels = json['Channels'];
    if (channels is! List) throw const ServerErrorException(null);
    return [for (final raw in channels) ?AccountChannel.fromWire(raw)];
  }

  /// Toglie Discord ed email dell'utente; il plugin annulla anche i codici
  /// già mandati.
  Future<void> unlinkContacts(String userId) async {
    await _http.delete('$_account/Users/$userId/Contacts',
        quietStatuses: _accountQuiet);
  }

  Future<AccountAdminStatus> accountStatus() async => parseJson(
      await _http.get('$_account/Status', quietStatuses: _quiet),
      AccountAdminStatus.fromJson);

  /// Un messaggio di prova per canale, ai contatti dell'admin: senza i campi
  /// `Discord` ed `Email`, che usa la Dashboard.
  Future<AccountTestResult> testAccountChannels(
          {required String language}) async =>
      parseJson(
          await _http.post('$_account/Test',
              body: {'Language': language}, quietStatuses: _quiet),
          AccountTestResult.fromJson);
```

Dopo la classe, in fondo al file:

```dart
/// Il `{Code}` di un errore del plugin (spec L §7.6), se c'è: nel corpo di
/// un 403 o di un altro errore del server.
String? pluginErrorCode(Object error) {
  final body = switch (error) {
    ForbiddenException(:final body) => body,
    ServerErrorException(:final body) => body,
    _ => null,
  };
  if (body is! Map) return null;
  final code = body['Code'];
  return code is String ? code : null;
}
```

- [ ] **Step 5: il finto**

In `test/support/admin_fakes.dart` aggiungi l'import `package:wonderflix/core/social/account_models.dart` (serve per `AccountChannel`) e, prima di `class FakePluginAdminApi`:

```dart
/// Gli utenti della scheda Utenti, in ordine di nome: garg (Discord ed
/// email), lucia (senza contatti), Mario (l'admin del test, con Discord) e
/// vecchio (disattivato, con l'email).
List<AdminAccountUser> testAccountUsers() => const [
      AdminAccountUser(
          id: 'u2',
          name: 'garg',
          isAdmin: false,
          enabled: true,
          discordName: 'garg',
          maskedEmail: 'g•••@example.com'),
      AdminAccountUser(id: 'u3', name: 'lucia', isAdmin: false, enabled: true),
      AdminAccountUser(
          id: 'u1',
          name: 'Mario',
          isAdmin: true,
          enabled: true,
          discordName: 'mario_d'),
      AdminAccountUser(
          id: 'u4',
          name: 'vecchio',
          isAdmin: false,
          enabled: false,
          maskedEmail: 'v•••@example.com'),
    ];

/// Lo stato del recupero: Discord configurato con un ultimo errore (DM
/// chiusi), email non configurata, 5 utenti su 23 con un contatto,
/// promemoria ogni 14 giorni.
final testAccountStatus = AccountAdminStatus(
  discord: AccountChannelStatus(
      configured: true,
      lastError:
          AccountSendError(at: DateTime.utc(2026, 10, 9, 8), code: 'DmClosed')),
  email: const AccountChannelStatus(configured: false),
  withContacts: 5,
  users: 23,
  reminderDays: 14,
);
```

In `FakePluginAdminApi`, dopo `int announceRecipients = 12;`:

```dart
  List<AdminAccountUser> accountUsersValue = testAccountUsers();
  AccountAdminStatus accountStatusValue = testAccountStatus;
  AccountTestResult accountTestValue =
      const AccountTestResult(discord: 'Ok', email: 'NoContact');

  /// I canali dove arriva il codice mandato dall'admin.
  List<AccountChannel> recoveryChannels = const [
    AccountChannel.discord,
    AccountChannel.email,
  ];

  Object? accountUsersError;
  Object? accountStatusError;
```

Aggiorna il commento di `actionError` ("Errore delle azioni: annuncio, interruttore, "Invia ora", prova di Seerr, e le azioni del recupero: codice, scollegamento, prova") e quello di `calls` (aggiungi `accountUsers`, `accountStatus`, `recovery:<id>:<lingua>`, `unlink:<id>`, `accountTest:<lingua>`). Poi, in fondo alla classe:

```dart
  @override
  Future<List<AdminAccountUser>> accountUsers() async {
    calls.add('accountUsers');
    final error = accountUsersError;
    if (error != null) throw error;
    return accountUsersValue;
  }

  @override
  Future<List<AccountChannel>> sendRecoveryCode(String userId,
      {required String language}) async {
    calls.add('recovery:$userId:$language');
    final error = actionError;
    if (error != null) throw error;
    return recoveryChannels;
  }

  @override
  Future<void> unlinkContacts(String userId) async {
    calls.add('unlink:$userId');
    final error = actionError;
    if (error != null) throw error;
  }

  @override
  Future<AccountAdminStatus> accountStatus() async {
    calls.add('accountStatus');
    final error = accountStatusError;
    if (error != null) throw error;
    return accountStatusValue;
  }

  @override
  Future<AccountTestResult> testAccountChannels(
      {required String language}) async {
    calls.add('accountTest:$language');
    final error = actionError;
    if (error != null) throw error;
    return accountTestValue;
  }
```

- [ ] **Step 6: il test passa**

Run: `flutter test test/core/social/account_admin_api_test.dart test/core/social/plugin_admin_api_test.dart`
Expected: PASS.

- [ ] **Step 7: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/core/social/plugin_admin_models.dart lib/core/social/plugin_admin_api.dart test/support/admin_fakes.dart test/core/social/account_admin_api_test.dart
git commit -m "feat(app): admin endpoints of password recovery in the plugin admin API"
```

### Task 3: controller ed etichette

**Files:**
- Create: `lib/features/admin/account_admin_controllers.dart`
- Create: `lib/features/admin/account_admin_labels.dart`
- Create: `test/features/admin/account_admin_controllers_test.dart`
- Create: `test/features/admin/account_admin_labels_test.dart`

- [ ] **Step 1: i test**

Crea `test/features/admin/account_admin_controllers_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/features/admin/account_admin_controllers.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/test_data.dart';

void main() {
  late FakePluginAdminApi plugin;
  late FakeSessionController session;
  late FakeAdapter adapter;

  setUp(() {
    plugin = FakePluginAdminApi();
    session = FakeSessionController(const SessionSignedIn(testAdmin));
    adapter = FakeAdapter((_) => const FakeResponse(204));
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
      overrides: [
        ...adminTestOverrides(FakeAdminApi(),
            plugin: plugin,
            session: session,
            features: const SocialFeatures(inbox: true, account: true)),
        authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
            baseUrl: testServerUrl,
            clientInfo: testClientInfo,
            adapter: adapter))),
      ],
      retry: (_, _) => null,
    );
    container.listen(accountUsersControllerProvider, (_, _) {});
    container.listen(accountAdminControllerProvider, (_, _) {});
    return container;
  }

  test('legge gli utenti e lo stato del recupero', () async {
    final container = makeContainer();
    await pumpEventQueue();

    expect(container.read(accountUsersControllerProvider).value!.map((u) => u.name),
        ['garg', 'lucia', 'Mario', 'vecchio']);
    expect(container.read(accountAdminControllerProvider).value!.withContacts,
        5);
  });

  test('azioni: chiamano il plugin e rileggono', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final users = container.read(accountUsersControllerProvider.notifier);

    expect(await users.sendRecoveryCode('u2', language: 'it'),
        [AccountChannel.discord, AccountChannel.email]);
    await users.unlinkContacts('u2');
    final result = await container
        .read(accountAdminControllerProvider.notifier)
        .test(language: 'it');

    expect(result.of(AccountChannel.discord), 'Ok');
    expect(plugin.calls,
        containsAllInOrder(['recovery:u2:it', 'unlink:u2', 'accountTest:it']));
    expect(plugin.count('accountUsers'), greaterThanOrEqualTo(3));
    expect(plugin.count('accountStatus'), greaterThanOrEqualTo(2));
  });

  test('Imposta password: Jellyfin, senza la password attuale', () async {
    final container = makeContainer();
    await pumpEventQueue();

    await container
        .read(accountUsersControllerProvider.notifier)
        .setPassword('u3', 'nuova123');

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/Users/Password');
    expect(request.queryParameters, {'userId': 'u3'});
    expect(request.data, {'NewPw': 'nuova123'});
  });

  test('un 403 fa rileggere l\'utente', () async {
    final container = makeContainer();
    await pumpEventQueue();
    adapter.handler = (_) => const FakeResponse(403);

    await expectLater(
        container
            .read(accountUsersControllerProvider.notifier)
            .setPassword('u3', 'nuova123'),
        throwsA(isA<ForbiddenException>()));

    expect(session.refreshUserCalls, 1);
  });
}
```

Crea `test/features/admin/account_admin_labels_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/account_models.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/account_admin_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('dove è arrivato il codice', () {
    expect(
        recoverySentLabel(
            l, const [AccountChannel.discord, AccountChannel.email]),
        'Codice mandato su Discord ed email');
    expect(recoverySentLabel(l, const [AccountChannel.discord]),
        'Codice mandato su Discord');
    expect(recoverySentLabel(l, const [AccountChannel.email]),
        'Codice mandato per email');
  });

  test('errori delle azioni: i Code del plugin, poi describeError', () {
    expect(
        accountAdminErrorText(
            l, const ForbiddenException({'Code': 'NotAllowed'}), 'garg'),
        'Gli admin e gli utenti disattivati non possono usare il recupero '
        'automatico');
    expect(
        accountAdminErrorText(
            l, const ServerErrorException(409, {'Code': 'NoContacts'}), 'garg'),
        'garg non ha contatti collegati');
    expect(
        accountAdminErrorText(
            l, const ServerErrorException(502, {'Code': 'SendFailed'}), 'garg'),
        'Invio non riuscito, riprova più tardi');
    expect(
        accountAdminErrorText(
            l, const ServerErrorException(400, {'Code': 'UnknownUser'}), 'garg'),
        'Questo utente non c\'è più');
    expect(
        accountAdminErrorText(l, const ServerUnreachableException(), 'garg'),
        'WonderFlix non è raggiungibile. Controlla la connessione.');
  });

  test('ultimo errore di un canale', () {
    expect(sendErrorLabel(l, 'DmClosed'), 'DM chiusi');
    expect(sendErrorLabel(l, 'Invalid'), 'token o server non validi');
    expect(sendErrorLabel(l, 'SendFailed'), 'invio non riuscito');
    expect(sendErrorLabel(l, 'Altro'), 'invio non riuscito');
  });

  test('esito della prova', () {
    expect(
        testResultLabel(
            l, const AccountTestResult(discord: 'Ok', email: 'NoContact')),
        'Discord: inviato · Email: collega prima il tuo contatto');
    expect(
        testResultLabel(l,
            const AccountTestResult(discord: 'Invalid', email: 'NotConfigured')),
        'Discord: token o server non validi · Email: non configurato');
    expect(
        testResultLabel(
            l, const AccountTestResult(discord: 'DmClosed', email: 'SendFailed')),
        'Discord: il bot non riesce a scriverti · Email: invio non riuscito');
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/admin/account_admin_controllers_test.dart test/features/admin/account_admin_labels_test.dart`
Expected: FAIL in compilazione.

- [ ] **Step 3: i controller**

Crea `lib/features/admin/account_admin_controllers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/social/account_models.dart';
import '../../core/social/plugin_admin_models.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';

/// La scheda Utenti (spec L §9.5): gli utenti con i loro contatti per il
/// recupero e le azioni dell'admin. Si rilegge all'apertura della scheda,
/// dopo ogni azione e ogni [every].
class AccountUsersController
    extends AdminTabController<List<AdminAccountUser>> {
  /// L'elenco cambia di rado: basta una lettura ogni tanto (l'infrastruttura
  /// delle schede vuole un intervallo, decisione 2 del piano 18c).
  static const every = Duration(minutes: 2);

  @override
  Duration get interval => every;

  @override
  Future<List<AdminAccountUser>> fetch() =>
      ref.read(pluginAdminApiProvider).accountUsers();

  /// Manda all'utente il codice di recupero: i canali dove è arrivato.
  Future<List<AccountChannel>> sendRecoveryCode(String userId,
          {required String language}) =>
      act(() => ref
          .read(pluginAdminApiProvider)
          .sendRecoveryCode(userId, language: language));

  Future<void> unlinkContacts(String userId) =>
      act(() => ref.read(pluginAdminApiProvider).unlinkContacts(userId));

  /// "Imposta password": Jellyfin, senza la password attuale; chiude le
  /// sessioni dell'utente.
  Future<void> setPassword(String userId, String password) => act(() =>
      ref.read(authApiProvider).changePassword(userId, newPassword: password));
}

final accountUsersControllerProvider = NotifierProvider.autoDispose<
    AccountUsersController,
    AdminData<List<AdminAccountUser>>>(AccountUsersController.new);

/// La card "Recupero password" (spec L §9.6): lo stato dei canali, riletto
/// ogni 30 s, e "Invia prova a me".
class AccountAdminController extends AdminTabController<AccountAdminStatus> {
  static const every = Duration(seconds: 30);

  @override
  Duration get interval => every;

  @override
  Future<AccountAdminStatus> fetch() =>
      ref.read(pluginAdminApiProvider).accountStatus();

  /// La prova va ai contatti dell'admin.
  Future<AccountTestResult> test({required String language}) => act(() =>
      ref.read(pluginAdminApiProvider).testAccountChannels(language: language));
}

final accountAdminControllerProvider = NotifierProvider.autoDispose<
    AccountAdminController,
    AdminData<AccountAdminStatus>>(AccountAdminController.new);
```

- [ ] **Step 4: le etichette**

Crea `lib/features/admin/account_admin_labels.dart`:

```dart
import '../../app/error_text.dart';
import '../../core/social/account_models.dart';
import '../../core/social/plugin_admin_api.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../account/account_texts.dart';

/// Dove è arrivato il codice mandato dall'admin (spec L §9.5).
String recoverySentLabel(AppLocalizations l, List<AccountChannel> channels) =>
    switch ((
      channels.contains(AccountChannel.discord),
      channels.contains(AccountChannel.email),
    )) {
      (true, false) => l.adminUsersRecoverySentDiscord,
      (false, true) => l.adminUsersRecoverySentEmail,
      _ => l.adminUsersRecoverySentBoth,
    };

/// L'errore di un'azione sugli utenti: i `{Code}` del plugin (spec L
/// §7.6), altrimenti `describeError`. [name] è l'utente della riga.
String accountAdminErrorText(AppLocalizations l, Object error, String name) =>
    switch (pluginErrorCode(error)) {
      'NotAllowed' => l.adminUsersNotAllowed,
      'NoContacts' => l.adminUsersNoContacts(name),
      'SendFailed' => l.accountErrorSendFailed,
      'UnknownUser' => l.adminUsersUnknown,
      _ => describeError(l, error),
    };

/// L'ultimo errore d'invio di un canale ("DM chiusi").
String sendErrorLabel(AppLocalizations l, String code) => switch (code) {
      'DmClosed' => l.adminRecoveryErrorDmClosed,
      'Invalid' => l.adminRecoveryErrorInvalid,
      _ => l.adminRecoveryErrorSendFailed,
    };

/// L'esito della prova di un canale (`AccountTestCodes` del plugin).
String testOutcomeLabel(AppLocalizations l, String code) => switch (code) {
      'Ok' => l.adminRecoveryTestSent,
      'NotConfigured' => l.adminRecoveryNotConfigured,
      'NoContact' => l.adminRecoveryTestNoContact,
      'Invalid' => l.adminRecoveryErrorInvalid,
      'DmClosed' => l.adminRecoveryTestDmClosed,
      'MemberNotFound' => l.adminRecoveryTestMemberNotFound,
      'InvalidTarget' => l.adminRecoveryTestInvalidTarget,
      _ => l.adminRecoveryErrorSendFailed,
    };

/// "Discord: inviato · Email: collega prima il tuo contatto".
String testResultLabel(AppLocalizations l, AccountTestResult result) => [
      for (final channel in AccountChannel.values)
        l.adminRecoveryChannelLine(accountChannelName(l, channel),
            testOutcomeLabel(l, result.of(channel))),
    ].join(' · ');
```

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/admin/account_admin_controllers_test.dart test/features/admin/account_admin_labels_test.dart`
Expected: PASS.

- [ ] **Step 6: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/admin/account_admin_controllers.dart lib/features/admin/account_admin_labels.dart test/features/admin/account_admin_controllers_test.dart test/features/admin/account_admin_labels_test.dart
git commit -m "feat(app): admin controllers and labels for password recovery"
```

---

## Gruppo B — schede

### Task 4: la finestra "Imposta password"

**Files:**
- Create: `lib/features/admin/set_password_dialog.dart`
- Create: `test/features/admin/set_password_dialog_test.dart`

- [ ] **Step 1: il test**

Crea `test/features/admin/set_password_dialog_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/features/account/account_texts.dart';
import 'package:wonderflix/features/admin/account_admin_controllers.dart';
import 'package:wonderflix/features/admin/set_password_dialog.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late FakeSessionController session;
  Future<bool>? result;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    session = FakeSessionController(const SessionSignedIn(testAdmin));
    result = null;
  });

  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => result =
                showSetPasswordDialog(context, userId: 'u3', name: 'lucia'),
            child: const Text('apri'),
          ),
        ),
      ),
      overrides: [
        ...adminTestOverrides(FakeAdminApi(),
            session: session,
            features: const SocialFeatures(inbox: true, account: true)),
        authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
            baseUrl: testServerUrl,
            clientInfo: testClientInfo,
            adapter: adapter))),
      ],
    );
    // Come nella scheda Utenti, che lo guarda: il controller resta vivo.
    ProviderScope.containerOf(tester.element(find.text('apri')))
        .listen(accountUsersControllerProvider, (_, _) {});
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester,
      {required String next, String? confirm}) async {
    await tester.enterText(find.byKey(const Key('set-password-new')), next);
    await tester.enterText(
        find.byKey(const Key('set-password-confirm')), confirm ?? next);
    await tester.tap(find.byKey(const Key('set-password-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('titolo e avviso sulle sessioni', (tester) async {
    await open(tester);
    expect(find.text('Imposta la password di lucia'), findsOneWidget);
    expect(find.text('Le sessioni di lucia verranno chiuse.'), findsOneWidget);
    final field =
        tester.widget<TextField>(find.byKey(const Key('set-password-new')));
    expect(field.decoration!.errorMaxLines, accountErrorMaxLines);
  });

  testWidgets('password corta e conferma diversa: errori, nessuna chiamata',
      (tester) async {
    await open(tester);

    await fill(tester, next: 'abc');
    expect(find.text('Almeno 6 caratteri'), findsOneWidget);

    await fill(tester, next: 'nuova123', confirm: 'nuova124');
    expect(find.text('Le password non coincidono'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('riuscita: senza la password attuale, e chiude con true',
      (tester) async {
    await open(tester);

    await fill(tester, next: 'nuova123');

    final request = adapter.requests.single;
    expect(request.path, '/Users/Password');
    expect(request.queryParameters, {'userId': 'u3'});
    expect(request.data, {'NewPw': 'nuova123'});
    expect(await result, isTrue);
  });

  testWidgets('403: l\'errore sopra i campi e l\'utente riletto',
      (tester) async {
    adapter.handler = (_) => const FakeResponse(403);
    await open(tester);

    await fill(tester, next: 'nuova123');

    expect(find.text('Account disabilitato o accesso non consentito.'),
        findsOneWidget);
    expect(session.refreshUserCalls, 1);
    expect(find.byKey(const Key('set-password-submit')), findsOneWidget);
  });

  testWidgets('durante la richiesta Esc non chiude', (tester) async {
    final gate = Completer<void>();
    adapter.handler = (_) async {
      await gate.future;
      return const FakeResponse(204);
    };
    await open(tester);

    await tester.enterText(find.byKey(const Key('set-password-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('set-password-confirm')), 'nuova123');
    await tester.tap(find.byKey(const Key('set-password-submit')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('set-password-submit')), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });
}
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/features/admin/set_password_dialog_test.dart`
Expected: FAIL in compilazione.

- [ ] **Step 3: la finestra**

Crea `lib/features/admin/set_password_dialog.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/social/account_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import '../account/account_texts.dart';
import '../auth/password_login_form.dart';
import 'account_admin_controllers.dart';
import 'account_admin_labels.dart';

/// "Imposta password" per l'utente [userId] (spec L §9.5). `true` se
/// impostata.
Future<bool> showSetPasswordDialog(BuildContext context,
    {required String userId, required String name}) async {
  final l = AppLocalizations.of(context);
  return await showWfDialog<bool>(
        context,
        semanticLabel: l.adminUsersSetPasswordTitle(name),
        builder: (_) => SetPasswordDialog(userId: userId, name: name),
      ) ??
      false;
}

/// Nuova password e conferma, senza quella attuale: Jellyfin la imposta e
/// chiude le sessioni dell'utente. Come le finestre del 18b, non si chiude
/// durante la richiesta.
class SetPasswordDialog extends ConsumerStatefulWidget {
  const SetPasswordDialog(
      {super.key, required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  ConsumerState<SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends ConsumerState<SetPasswordDialog> {
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _newError;
  String? _confirmError;
  String? _error;

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final password = _new.text;
    setState(() {
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
      await ref
          .read(accountUsersControllerProvider.notifier)
          .setPassword(widget.userId, password);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      // Come le altre azioni della scheda: 502/503/504 "non raggiungibile",
      // altrimenti `describeError`.
      if (mounted) {
        setState(() => _error = accountAdminErrorText(l, error, widget.name));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.adminUsersSetPasswordTitle(widget.name),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(l.adminUsersSetPasswordHint(widget.name),
            style: const TextStyle(color: WfColors.creamMuted)),
        const SizedBox(height: 16),
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('set-password-new'),
          controller: _new,
          autofocus: true,
          obscureText: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l.accountNewPassword,
            errorText: _newError,
            errorMaxLines: accountErrorMaxLines,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('set-password-confirm'),
          controller: _confirm,
          obscureText: true,
          onSubmitted: (_) => unawaited(_submit()),
          decoration: InputDecoration(
            labelText: l.accountConfirmPassword,
            errorText: _confirmError,
            errorMaxLines: accountErrorMaxLines,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(l.accountCancel),
            ),
            const SizedBox(width: 12),
            FilledButton(
              key: const Key('set-password-submit'),
              // Il tema fa i FilledButton larghi all'infinito: in una Row
              // servono larghi quanto il testo.
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: Text(l.adminUsersSetPassword),
            ),
          ],
        ),
      ],
    );
    // Esc e il clic fuori non la chiudono durante la richiesta: la password
    // cambierebbe senza l'avviso.
    return PopScope(canPop: !_busy, child: content);
  }
}
```

- [ ] **Step 4: il test passa**

Run: `flutter test test/features/admin/set_password_dialog_test.dart`
Expected: PASS (5 test).

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/admin/set_password_dialog.dart test/features/admin/set_password_dialog_test.dart
git commit -m "feat(app): set password dialog for admins"
```

### Task 5: la scheda Utenti

**Files:**
- Modify: `lib/features/admin/admin_navigation.dart`
- Modify: `lib/features/admin/admin_screen.dart`
- Create: `lib/features/admin/users_tab.dart`
- Modify: `test/features/admin/admin_navigation_test.dart`
- Modify: `test/features/admin/admin_screen_test.dart`
- Create: `test/features/admin/users_tab_test.dart`

- [ ] **Step 1: i test**

In `test/features/admin/admin_navigation_test.dart` sostituisci i due test con:

```dart
  test('scheda dall\'indirizzo: senza o sconosciuta, Sessioni', () {
    expect(AdminTab.parse('sessions'), AdminTab.sessions);
    expect(AdminTab.parse('users'), AdminTab.users);
    expect(AdminTab.parse('maintenance'), AdminTab.maintenance);
    expect(AdminTab.parse('activity'), AdminTab.activity);
    expect(AdminTab.parse('wonderflix'), AdminTab.wonderflix);
    expect(AdminTab.parse(null), AdminTab.sessions);
    expect(AdminTab.parse('boh'), AdminTab.sessions);
  });

  test('Utenti solo con i contatti del plugin, WonderFlix con la cassetta',
      () {
    expect(adminTabs(inbox: true, account: true), AdminTab.values);
    expect(adminTabs(inbox: true, account: false), [
      AdminTab.sessions,
      AdminTab.maintenance,
      AdminTab.activity,
      AdminTab.wonderflix,
    ]);
    expect(adminTabs(inbox: false, account: false),
        [AdminTab.sessions, AdminTab.maintenance, AdminTab.activity]);
  });
```

In `test/features/admin/admin_screen_test.dart`, dopo il test `'senza la cassetta del plugin: niente WonderFlix, si mostra Sessioni'`:

```dart
  testWidgets('con i contatti del plugin: Utenti dopo Sessioni', (tester) async {
    final router = await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        features: const SocialFeatures(inbox: true, account: true));

    for (final tab in [
      'sessions',
      'users',
      'maintenance',
      'activity',
      'wonderflix',
    ]) {
      expect(find.byKey(ValueKey('admin-tab-$tab')), findsOneWidget);
    }
    double x(String tab) =>
        tester.getTopLeft(find.byKey(ValueKey('admin-tab-$tab'))).dx;
    expect(x('users'), greaterThan(x('sessions')));
    expect(x('users'), lessThan(x('maintenance')));

    await tester.tap(find.text('Utenti'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.toString(),
        '/admin?tab=users');
    expect(find.text('garg'), findsOneWidget);
  });

  testWidgets('senza i contatti del plugin: niente Utenti, si mostra Sessioni',
      (tester) async {
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        location: '/admin?tab=users');

    expect(find.byKey(const ValueKey('admin-tab-users')), findsNothing);
    expect(find.text('viviroby'), findsOneWidget);
  });

  testWidgets('funzioni del plugin non ancora note: Utenti aspetta',
      (tester) async {
    final availability = FakeSocialAvailability(SocialFeatures.unknown);
    await pumpScreen(tester,
        session: FakeSessionController(const SessionSignedIn(testAdmin)),
        location: '/admin?tab=users',
        availability: availability,
        settle: false);

    expect(find.byType(LoadingView), findsOneWidget);
    expect(api.count('sessions'), 0);

    availability.set(const SocialFeatures(inbox: true, account: true));
    await tester.pumpAndSettle();

    expect(find.text('garg'), findsOneWidget);
    expect(api.count('sessions'), 0);
  });
```

Crea `test/features/admin/users_tab_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/providers.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/auth_api.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/users_tab.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/ui/states.dart';

import '../../support/admin_fakes.dart';
import '../../support/fake_adapter.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/test_data.dart';

void main() {
  late FakePluginAdminApi plugin;
  late FakeAdapter adapter;

  setUp(() {
    plugin = FakePluginAdminApi();
    adapter = FakeAdapter((_) => const FakeResponse(204));
  });

  Future<void> pumpTab(WidgetTester tester) async {
    await pumpApp(tester, const Scaffold(body: UsersTab()), overrides: [
      ...adminTestOverrides(FakeAdminApi(),
          plugin: plugin,
          session: FakeSessionController(const SessionSignedIn(testAdmin)),
          features: const SocialFeatures(inbox: true, account: true)),
      authApiProvider.overrideWithValue(AuthApi(JellyfinHttp(
          baseUrl: testServerUrl,
          clientInfo: testClientInfo,
          adapter: adapter))),
    ]);
    await tester.pumpAndSettle();
  }

  /// Apre il menu della riga di [userId] e sceglie [label].
  Future<void> choose(WidgetTester tester, String userId, String label) async {
    await tester.tap(find.byKey(Key('user-menu-$userId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('userActions', () {
    const garg = AdminAccountUser(
        id: 'u2',
        name: 'garg',
        isAdmin: false,
        enabled: true,
        discordName: 'garg');

    test('un utente con un contatto: tutte e tre', () {
      expect(userActions(garg, isMe: false), [
        UserAction.setPassword,
        UserAction.sendRecovery,
        UserAction.unlink,
      ]);
    });

    test('la propria riga: niente "Imposta password"', () {
      expect(userActions(garg, isMe: true),
          [UserAction.sendRecovery, UserAction.unlink]);
    });

    test('senza contatti: solo "Imposta password"', () {
      const lucia = AdminAccountUser(
          id: 'u3', name: 'lucia', isAdmin: false, enabled: true);
      expect(userActions(lucia, isMe: false), [UserAction.setPassword]);
      expect(userActions(lucia, isMe: true), isEmpty);
    });

    test('admin o disattivato: niente codice', () {
      const admin = AdminAccountUser(
          id: 'u5',
          name: 'altro',
          isAdmin: true,
          enabled: true,
          maskedEmail: 'a•••@example.com');
      const disabled = AdminAccountUser(
          id: 'u4',
          name: 'vecchio',
          isAdmin: false,
          enabled: false,
          maskedEmail: 'v•••@example.com');
      expect(userActions(admin, isMe: false),
          [UserAction.setPassword, UserAction.unlink]);
      expect(userActions(disabled, isMe: false),
          [UserAction.setPassword, UserAction.unlink]);
    });
  });

  testWidgets('righe: nome, Admin, Disattivato, contatti nei tooltip',
      (tester) async {
    await pumpTab(tester);

    for (final name in ['garg', 'lucia', 'Mario', 'vecchio']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Disattivato'), findsOneWidget);
    expect(find.byTooltip('Discord: garg'), findsOneWidget);
    expect(find.byTooltip('Email: g•••@example.com'), findsOneWidget);
    expect(find.byTooltip('Discord non collegato'), findsNWidgets(2));
    expect(find.byTooltip('Email non collegata'), findsNWidgets(2));
  });

  testWidgets('il menu di garg ha le tre azioni', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.byKey(const Key('user-menu-u2')));
    await tester.pumpAndSettle();

    expect(find.text('Imposta password'), findsOneWidget);
    expect(find.text('Invia codice di recupero'), findsOneWidget);
    expect(find.text('Scollega contatti'), findsOneWidget);
  });

  testWidgets('Invia codice di recupero: conferma, poi dove è arrivato',
      (tester) async {
    await pumpTab(tester);

    await choose(tester, 'u2', 'Invia codice di recupero');
    expect(find.text('Mandare a garg un codice per cambiare la password?'),
        findsOneWidget);
    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();

    expect(plugin.calls, contains('recovery:u2:it'));
    expect(find.text('Codice mandato su Discord ed email'), findsOneWidget);
  });

  testWidgets('Invia codice: l\'errore del plugin con il suo testo',
      (tester) async {
    plugin.actionError =
        const ServerErrorException(409, {'Code': 'NoContacts'});
    await pumpTab(tester);

    await choose(tester, 'u2', 'Invia codice di recupero');
    await tester.tap(find.text('Invia'));
    await tester.pumpAndSettle();

    expect(find.text('garg non ha contatti su un canale attivo'),
        findsOneWidget);
  });

  testWidgets('Scollega contatti: conferma e avviso', (tester) async {
    await pumpTab(tester);

    await choose(tester, 'u2', 'Scollega contatti');
    expect(find.text('Scollegare i contatti di garg?'), findsOneWidget);
    await tester.tap(find.text('Scollega'));
    await tester.pumpAndSettle();

    expect(plugin.calls, contains('unlink:u2'));
    expect(find.text('Contatti di garg scollegati'), findsOneWidget);
    // La rilettura dopo l'azione: la riga non ha più contatti.
    expect(find.byTooltip('Discord: garg'), findsNothing);
    expect(find.byTooltip('Discord non collegato'), findsNWidgets(3));
  });

  testWidgets('Annulla: nessuna azione', (tester) async {
    await pumpTab(tester);

    await choose(tester, 'u2', 'Scollega contatti');
    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(plugin.calls.where((c) => c.startsWith('unlink')), isEmpty);
  });

  testWidgets('Imposta password: la finestra, poi l\'avviso', (tester) async {
    await pumpTab(tester);

    await choose(tester, 'u3', 'Imposta password');
    expect(find.text('Imposta la password di lucia'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('set-password-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('set-password-confirm')), 'nuova123');
    await tester.tap(find.byKey(const Key('set-password-submit')));
    await tester.pumpAndSettle();

    expect(adapter.requests.single.queryParameters, {'userId': 'u3'});
    expect(find.text('Password impostata. Le sessioni di lucia sono state '
        'chiuse.'), findsOneWidget);
  });

  testWidgets('elenco non letto: errore e Riprova', (tester) async {
    plugin.accountUsersError = const ServerUnreachableException();
    await pumpTab(tester);
    expect(find.byType(ErrorView), findsOneWidget);

    plugin.accountUsersError = null;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('garg'), findsOneWidget);
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/admin/admin_navigation_test.dart test/features/admin/users_tab_test.dart test/features/admin/admin_screen_test.dart`
Expected: FAIL in compilazione (`AdminTab.users`, `users_tab.dart`).

- [ ] **Step 3: la navigazione**

In `lib/features/admin/admin_navigation.dart`:
- nell'enum, `users` dopo `sessions`:

```dart
/// Le schede della pagina Amministrazione (spec J §9, spec L §9.5).
enum AdminTab {
  sessions,
  users,
  maintenance,
  activity,
  wonderflix;
```

- `adminTabs`:

```dart
/// Le schede da mostrare: Utenti solo con i contatti per il recupero del
/// plugin (`account`, spec L §9.5), WonderFlix solo con la cassetta
/// (`inbox`, spec J §7).
List<AdminTab> adminTabs({required bool inbox, required bool account}) => [
      for (final tab in AdminTab.values)
        if ((tab != AdminTab.wonderflix || inbox) &&
            (tab != AdminTab.users || account))
          tab,
    ];
```

- in `adminTabLabel`, dopo `AdminTab.sessions => …`: `AdminTab.users => l.adminTabUsers,`.

- [ ] **Step 4: la pagina**

In `lib/features/admin/admin_screen.dart`:
- aggiungi `import 'users_tab.dart';`;
- sostituisci il blocco da `// Senza la cassetta del plugin la scheda WonderFlix non c'è;` fino a `: AdminTab.sessions;` con:

```dart
    // Le schede del plugin (Utenti e WonderFlix) ci sono solo con le sue
    // funzioni; se una manca ed è nell'indirizzo (o la funzione sparisce
    // mentre la si guarda), si mostra Sessioni. Ma finché non si sa se il
    // plugin c'è (subito dopo il login) non si può dire che manchi: si
    // aspetta, senza passare da Sessioni, che si rileggerebbe per niente e
    // farebbe un lampo di contenuto sbagliato.
    final features = ref.watch(socialAvailabilityProvider.select(
        (f) => (inbox: f.inbox, account: f.account, known: f.known)));
    final tabs = adminTabs(inbox: features.inbox, account: features.account);
    final waitingForPlugin = !features.known && !tabs.contains(widget.tab);
    final tab = tabs.contains(widget.tab) || waitingForPlugin
        ? widget.tab
        : AdminTab.sessions;
```

- nello `switch` del contenuto, dopo `AdminTab.sessions => const SessionsTab(),`: `AdminTab.users => const UsersTab(),`.

- [ ] **Step 5: la scheda**

Crea `lib/features/admin/users_tab.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_menus.dart';
import '../auth/session_controller.dart';
import 'account_admin_controllers.dart';
import 'account_admin_labels.dart';
import 'admin_confirm_dialog.dart';
import 'admin_widgets.dart';
import 'set_password_dialog.dart';

/// Diametro dell'avatar di una riga.
const _avatarSize = 28.0;

/// Larghezza del posto del menu: le righe senza menu restano allineate.
const _menuWidth = 40.0;

/// La scheda Utenti (spec L §9.5): ogni utente con i suoi contatti per il
/// recupero e le azioni dell'admin.
class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key});

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(accountUsersControllerProvider);
    final users = data.value;
    if (users == null) {
      final error = data.error;
      if (error == null) return const LoadingView();
      return ErrorView(
        error: error,
        onRetry: () => unawaited(
            ref.read(accountUsersControllerProvider.notifier).refresh()),
      );
    }
    final me = ref.watch(sessionControllerProvider.select(
        (s) => s is SessionSignedIn ? jellyfinIdKey(s.user.id) : null));
    final updatedAt = data.updatedAt;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
      children: [
        if (data.stale && updatedAt != null)
          AdminStaleNote(updatedAt: updatedAt),
        if (users.isEmpty)
          AdminEmptyText(text: l.adminUsersEmpty)
        else
          for (final user in users)
            AccountUserRow(
              key: ValueKey('user-${user.id}'),
              user: user,
              isMe: jellyfinIdKey(user.id) == me,
            ),
      ],
    );
  }
}

/// Le azioni del menu di una riga.
enum UserAction { setPassword, sendRecovery, unlink }

/// Le azioni per [user] (spec L §9.5): "Imposta password" non sulla propria
/// riga (per la propria Jellyfin vuole la password attuale, e c'è "Cambia
/// password" in Impostazioni); il codice non agli admin né ai disattivati, e
/// solo con un contatto; lo scollegamento solo con un contatto.
List<UserAction> userActions(AdminAccountUser user, {required bool isMe}) => [
      if (!isMe) UserAction.setPassword,
      if (!user.isAdmin && user.enabled && user.hasContacts)
        UserAction.sendRecovery,
      if (user.hasContacts) UserAction.unlink,
    ];

/// Un utente: avatar, nome, etichette, contatti e il menu delle azioni.
class AccountUserRow extends ConsumerStatefulWidget {
  const AccountUserRow({super.key, required this.user, required this.isMe});

  final AdminAccountUser user;

  /// La riga dell'admin che guarda.
  final bool isMe;

  @override
  ConsumerState<AccountUserRow> createState() => _AccountUserRowState();
}

class _AccountUserRowState extends ConsumerState<AccountUserRow> {
  /// Un'azione in corso: intanto il menu è spento.
  bool _busy = false;

  AdminAccountUser get _user => widget.user;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final done =
        await showSetPasswordDialog(context, userId: _user.id, name: _user.name);
    if (done && mounted) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.adminUsersPasswordSet(_user.name))));
    }
  }

  Future<void> _sendRecovery() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final confirmed = await showAdminConfirmDialog(
      context,
      title: l.adminUsersSendRecovery,
      message: l.adminUsersSendRecoveryConfirm(_user.name),
      confirmLabel: l.adminSend,
    );
    if (!confirmed || !mounted) return;
    final String text;
    try {
      final channels = await ref
          .read(accountUsersControllerProvider.notifier)
          .sendRecoveryCode(_user.id, language: language);
      text = recoverySentLabel(l, channels);
    } on Object catch (error) {
      text = accountAdminErrorText(l, error, _user.name);
    }
    // Come `AdminActionButton`: con la scheda cambiata nel frattempo, niente
    // avviso.
    if (mounted) messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _unlink() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAdminConfirmDialog(
      context,
      title: l.adminUsersUnlink,
      message: l.adminUsersUnlinkConfirm(_user.name),
      confirmLabel: l.accountUnlink,
    );
    if (!confirmed || !mounted) return;
    final String text;
    try {
      await ref
          .read(accountUsersControllerProvider.notifier)
          .unlinkContacts(_user.id);
      text = l.adminUsersUnlinked(_user.name);
    } on Object catch (error) {
      text = accountAdminErrorText(l, error, _user.name);
    }
    if (mounted) messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  void _select(UserAction action) => unawaited(_run(switch (action) {
        UserAction.setPassword => _setPassword,
        UserAction.sendRecovery => _sendRecovery,
        UserAction.unlink => _unlink,
      }));

  String _actionLabel(AppLocalizations l, UserAction action) =>
      switch (action) {
        UserAction.setPassword => l.adminUsersSetPassword,
        UserAction.sendRecovery => l.adminUsersSendRecovery,
        UserAction.unlink => l.adminUsersUnlink,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final user = _user;
    final actions = userActions(user, isMe: widget.isMe);
    final discord = user.discordName;
    final email = user.maskedEmail;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          UserAvatar.lookup(
              userId: user.id, name: user.name, size: _avatarSize),
          const SizedBox(width: 10),
          Flexible(
            child: Text(user.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (user.isAdmin) ...[
            const SizedBox(width: 8),
            _Badge(text: l.adminUsersAdmin),
          ],
          if (!user.enabled) ...[
            const SizedBox(width: 8),
            _Badge(text: l.adminUsersDisabled),
          ],
          const Spacer(),
          _ContactIcon(
            icon: LucideIcons.messageCircle,
            linked: discord != null,
            tooltip: discord == null
                ? l.adminUsersDiscordNone
                : l.adminUsersDiscordLinked(discord),
          ),
          const SizedBox(width: 8),
          _ContactIcon(
            icon: LucideIcons.mail,
            linked: email != null,
            tooltip: email == null
                ? l.adminUsersEmailNone
                : l.adminUsersEmailLinked(email),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: _menuWidth,
            child: actions.isEmpty
                ? null
                : PopupMenuButton<UserAction>(
                    key: Key('user-menu-${user.id}'),
                    tooltip: l.adminUsersActions,
                    enabled: !_busy,
                    icon: const Icon(LucideIcons.ellipsisVertical,
                        size: 18, color: WfColors.creamMuted),
                    popUpAnimationStyle: wfPopUpAnimation(context),
                    onSelected: _select,
                    itemBuilder: (context) => [
                      for (final action in actions)
                        PopupMenuItem<UserAction>(
                            value: action,
                            child: Text(_actionLabel(l, action))),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Admin", "Disattivato".
class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: WfColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
      );
}

/// L'icona di un canale: oro se collegato, grigia se no; il tooltip dice il
/// contatto (l'email è mascherata dal plugin).
class _ContactIcon extends StatelessWidget {
  const _ContactIcon(
      {required this.icon, required this.linked, required this.tooltip});

  final IconData icon;
  final bool linked;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Icon(icon,
            size: 18, color: linked ? WfColors.gold : WfColors.creamMuted),
      );
}
```

- [ ] **Step 6: i test passano**

Run: `flutter test test/features/admin/`
Expected: PASS (anche gli altri test della pagina: senza la funzione `account` la scheda non c'è).

- [ ] **Step 7: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/admin/admin_navigation.dart lib/features/admin/admin_screen.dart lib/features/admin/users_tab.dart test/features/admin/admin_navigation_test.dart test/features/admin/admin_screen_test.dart test/features/admin/users_tab_test.dart
git commit -m "feat(app): users tab in administration with recovery actions"
```

### Task 6: la card "Recupero password"

**Files:**
- Create: `lib/features/admin/account_recovery_card.dart`
- Modify: `lib/features/admin/wonderflix_tab.dart`
- Create: `test/features/admin/account_recovery_card_test.dart`

- [ ] **Step 1: il test**

Crea `test/features/admin/account_recovery_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/social/plugin_admin_models.dart';
import 'package:wonderflix/features/admin/account_recovery_card.dart';
import 'package:wonderflix/features/admin/admin_widgets.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/admin_fakes.dart';
import '../../support/pump_app.dart';

void main() {
  late FakePluginAdminApi plugin;

  setUp(() => plugin = FakePluginAdminApi());

  Future<void> pumpCard(WidgetTester tester,
      {SocialFeatures features =
          const SocialFeatures(inbox: true, account: true)}) async {
    await pumpApp(
        tester,
        const Scaffold(
            body: SingleChildScrollView(child: AccountRecoveryCard())),
        overrides: adminTestOverrides(FakeAdminApi(),
            plugin: plugin, features: features));
    await tester.pumpAndSettle();
  }

  testWidgets('senza la funzione account: niente card, niente letture',
      (tester) async {
    await pumpCard(tester, features: const SocialFeatures(inbox: true));

    expect(find.text('Recupero password'), findsNothing);
    expect(plugin.count('accountStatus'), 0);
  });

  testWidgets('canali, ultimo errore, conteggi, promemoria, dove si configura',
      (tester) async {
    await pumpCard(tester);

    expect(find.text('Recupero password'), findsOneWidget);
    expect(find.text('Discord: configurato'), findsOneWidget);
    expect(find.text('Email: non configurato'), findsOneWidget);
    expect(find.textContaining('Ultimo errore: DM chiusi'), findsOneWidget);
    expect(find.text('5 utenti su 23 hanno un contatto'), findsOneWidget);
    expect(find.text('Promemoria ogni 14 giorni'), findsOneWidget);
    expect(
        find.text(
            'Si configura nella Dashboard di Jellyfin → Plugin → WonderFlix'),
        findsOneWidget);
  });

  testWidgets('promemoria spenti', (tester) async {
    plugin.accountStatusValue = const AccountAdminStatus(
      discord: AccountChannelStatus(configured: true),
      email: AccountChannelStatus(configured: true),
      withContacts: 2,
      users: 23,
      reminderDays: 0,
    );
    await pumpCard(tester);

    expect(find.text('Promemoria spenti'), findsOneWidget);
    expect(find.textContaining('Ultimo errore'), findsNothing);
  });

  testWidgets('Invia prova a me: l\'esito per canale', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.text('Invia prova a me'));
    await tester.pumpAndSettle();

    expect(plugin.calls, contains('accountTest:it'));
    expect(find.text('Discord: inviato · Email: collega prima il tuo contatto'),
        findsOneWidget);
  });

  testWidgets('lettura fallita: l\'errore della card', (tester) async {
    plugin.accountStatusError = const ServerUnreachableException();
    await pumpCard(tester);

    expect(find.byType(AdminCardError), findsOneWidget);
  });
}
```

- [ ] **Step 2: il test fallisce**

Run: `flutter test test/features/admin/account_recovery_card_test.dart`
Expected: FAIL in compilazione.

- [ ] **Step 3: la card**

Crea `lib/features/admin/account_recovery_card.dart`:

```dart
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/account_models.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../account/account_providers.dart';
import '../account/account_texts.dart';
import 'account_admin_controllers.dart';
import 'account_admin_labels.dart';
import 'admin_action_button.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';

const _muted = TextStyle(color: WfColors.creamMuted);

/// La card "Recupero password" della scheda WonderFlix (spec L §9.6):
/// Discord ed email, quanti utenti hanno un contatto, i promemoria e "Invia
/// prova a me". Niente campi: la configurazione è nella Dashboard. Senza la
/// funzione `account` del plugin la card non c'è.
class AccountRecoveryCard extends ConsumerStatefulWidget {
  const AccountRecoveryCard({super.key});

  @override
  ConsumerState<AccountRecoveryCard> createState() =>
      _AccountRecoveryCardState();
}

class _AccountRecoveryCardState extends ConsumerState<AccountRecoveryCard> {
  /// L'esito dell'ultima prova, accanto al pulsante.
  AccountTestResult? _result;

  Future<void> _test() async {
    final language = Localizations.localeOf(context).languageCode;
    final result = await ref
        .read(accountAdminControllerProvider.notifier)
        .test(language: language);
    if (mounted) setState(() => _result = result);
  }

  List<Widget> _channelLines(AppLocalizations l, AccountChannel channel,
      AccountChannelStatus status, DateTime now) {
    final lastError = status.lastError;
    return [
      Text(l.adminRecoveryChannelLine(
          accountChannelName(l, channel),
          status.configured
              ? l.adminRecoveryConfigured
              : l.adminRecoveryNotConfigured)),
      if (lastError != null)
        Text(
            l.adminRecoveryLastError(sendErrorLabel(l, lastError.code),
                adminTimeLabel(lastError.at, now, l)),
            style: const TextStyle(color: WfColors.error, fontSize: 13)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Senza la funzione la card non c'è, e lo stato non si legge.
    if (!ref.watch(accountAvailableProvider)) return const SizedBox.shrink();
    final data = ref.watch(accountAdminControllerProvider);
    final status = data.value;
    final error = data.error;
    final updatedAt = data.updatedAt;
    final result = _result;
    final Widget child;
    if (status == null) {
      child = error != null
          ? AdminCardError(
              error: error,
              onRetry: () => unawaited(
                  ref.read(accountAdminControllerProvider.notifier).refresh()))
          : const SkeletonBox(width: 240, height: 20);
    } else {
      final now = clock.now();
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final channel in AccountChannel.values)
            ..._channelLines(l, channel, status.channel(channel), now),
          const SizedBox(height: 8),
          Text(l.adminRecoveryWithContacts(status.withContacts, status.users),
              style: _muted),
          Text(
              status.reminderDays > 0
                  ? l.adminRecoveryReminders(status.reminderDays)
                  : l.adminRecoveryRemindersOff,
              style: _muted),
          const SizedBox(height: 12),
          Row(
            children: [
              AdminActionButton(
                label: l.adminRecoveryTest,
                icon: LucideIcons.send,
                onPressed: _test,
              ),
              if (result != null) ...[
                const SizedBox(width: 12),
                Flexible(child: Text(testResultLabel(l, result))),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(l.adminRecoveryConfigHint,
              style: const TextStyle(
                  color: WfColors.creamMuted, fontSize: 12.5)),
        ],
      );
    }
    // Come la card Seerr: la `Column` c'è sempre, così `child` non cambia
    // posto quando compare la nota (e la prova in corso non perde lo stato).
    return AdminCard(
      title: l.adminRecovery,
      icon: LucideIcons.keyRound,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          if (data.stale && updatedAt != null)
            AdminStaleNote(updatedAt: updatedAt),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: nella scheda WonderFlix**

In `lib/features/admin/wonderflix_tab.dart`:
- aggiungi `import 'account_recovery_card.dart';`;
- nel commento della classe: "La scheda WonderFlix (spec J §9.6, spec L §9.6): annuncio, novità, Seerr, recupero della password.";
- i figli della `ListView`:

```dart
        children: const [
          AnnouncementCard(),
          NewTitlesCard(),
          SeerrCard(),
          AccountRecoveryCard(),
        ],
```

- [ ] **Step 5: i test passano**

Run: `flutter test test/features/admin/`
Expected: PASS (nei test della scheda WonderFlix la funzione `account` è spenta: la card non c'è).

- [ ] **Step 6: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/admin/account_recovery_card.dart lib/features/admin/wonderflix_tab.dart test/features/admin/account_recovery_card_test.dart
git commit -m "feat(app): password recovery card in the WonderFlix admin tab"
```

### Task 7: "Ho già un codice" nel recupero

**Files:**
- Modify: `lib/features/auth/recovery_panel.dart`
- Modify: `test/features/auth/recovery_panel_test.dart`

- [ ] **Step 1: i test**

In fondo a `main` di `test/features/auth/recovery_panel_test.dart` (usa gli aiuti del file: `pumpLogin`, `openRecovery`, `tapKey`):

```dart
  testWidgets('Ho già un codice: il secondo passo senza chiederne un altro',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester);

    await tapKey(tester, 'recovery-have-code');

    expect(api.recoveryStarts, isEmpty);
    expect(
        find.text('Scrivi il codice che hai ricevuto su Discord o per email.'),
        findsOneWidget);
    await tester.enterText(find.byKey(const Key('recovery-code')), '012345');
    await tester.enterText(find.byKey(const Key('recovery-new')), 'nuova123');
    await tester.enterText(
        find.byKey(const Key('recovery-confirm')), 'nuova123');
    await tapKey(tester, 'recovery-submit');

    expect(api.recoveryCompletes.single.username, 'garg');
    expect(api.recoveryCompletes.single.code, '012345');
    expect(session.loginAttempts, [('garg', 'nuova123')]);
  });

  testWidgets('Ho già un codice senza il nome: l\'errore, si resta lì',
      (tester) async {
    await pumpLogin(tester);
    await openRecovery(tester, username: '');

    await tapKey(tester, 'recovery-have-code');

    expect(find.text('Scrivi il nome utente'), findsOneWidget);
    expect(find.byKey(const Key('recovery-code')), findsNothing);
  });
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/auth/recovery_panel_test.dart`
Expected: FAIL (`recovery-have-code` non c'è).

- [ ] **Step 3: il codice**

In `lib/features/auth/recovery_panel.dart`:
- dopo il campo `_changedTo`:

```dart
  /// Il codice c'è già (per esempio mandato dall'admin, spec L §9.5): il
  /// secondo passo dice di scriverlo, senza averne chiesto uno.
  bool _haveCode = false;
```

- dopo `_start`:

```dart
  /// "Ho già un codice" (decisione 8 del piano 18c): il secondo passo con il
  /// nome scritto, senza `Start`, che manderebbe un codice nuovo al posto di
  /// quello che l'utente ha già.
  void _haveCodeAlready() {
    if (_busy) return;
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() =>
          _usernameError = AppLocalizations.of(context).recoveryNameNeeded);
      return;
    }
    setState(() {
      _clearErrors();
      _haveCode = true;
      _sentFor = username;
    });
  }
```

- nel primo passo, dopo il `FilledButton` con `Key('recovery-send')`:

```dart
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('recovery-have-code'),
              onPressed: _busy ? null : _haveCodeAlready,
              child: Text(l.recoveryHaveCode),
            ),
          ),
```

- nel secondo passo, sostituisci `Text(l.recoveryCodeSent, style: const TextStyle(fontSize: 13)),` con:

```dart
          Text(_haveCode ? l.recoveryEnterCode : l.recoveryCodeSent,
              style: const TextStyle(fontSize: 13)),
```

- [ ] **Step 4: i test passano**

Run: `flutter test test/features/auth/`
Expected: PASS.

- [ ] **Step 5: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add lib/features/auth/recovery_panel.dart test/features/auth/recovery_panel_test.dart
git commit -m "feat(app): I already have a code in password recovery"
```

---

## Gruppo C — chiusura

### Task 8: allineamento della spec, checklist, build

**Files:**
- Modify: `docs/superpowers/specs/2026-10-09-wonderflix-recupero-password-design.md`
- Modify: `docs/superpowers/plans/2026-10-09-wonderflix-18c-recupero-app-admin.md` (solo una voce "Dalle review dei gruppi", se ci sono differenze)
- Modify: `docs/RELEASING.md`

- [ ] **Step 1: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "approvato; piani 18a, 18b e 18c realizzati (…); release da fare" (la release la segna il commit della release).
- **§9.1:** gli endpoint dell'admin in `PluginAdminApi` con `pluginErrorCode` (decisione 1); togli la nota "dal 18b: `NotAllowed`, `NoContacts` e `UnknownUser` vorranno valori loro in `AccountFailure`".
- **§9.3:** "Ho già un codice" e il testo "Scrivi il codice che hai ricevuto…" (decisione 8).
- **§9.5:** la scheda vera: `UsersTab`, `AccountUserRow`, `userActions` (decisione 4), `SetPasswordDialog` (decisione 6), `UserAvatar.lookup`, i testi degli esiti e degli errori (`NotAllowed` con il testo della decisione 7), la rilettura ogni 2 minuti (decisione 2).
- **§9.6:** la card `AccountRecoveryCard` nella scheda WonderFlix dopo Seerr (decisione 3), con i testi veri.
- **§10:** i testi veri dell'admin, con le chiavi (`adminTabUsers`, `adminUsers…`, `adminRecovery…`, `recoveryHaveCode`, `recoveryEnterCode`), al posto della lista "Amministrazione (piano 18c, da scrivere)".
- **§12:** i test dell'app del 18c che esistono davvero; il punto 4 della prova a mano si fa nel Task 9, il 5 nella release.
- **§15:** 18c realizzato; la release è il passo successivo; togli la riga "Dal 18b: …" o dì com'è finita.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

Nel piano, se nei task è cambiato qualcosa rispetto al codice scritto qui, aggiungi alle "Decisioni del piano" una voce "Dalle review dei gruppi" con le differenze (come nei piani 18a e 18b).

- [ ] **Step 2: la checklist**

In `docs/RELEASING.md`, nella checklist dei test a mano, dopo le voci del recupero della password:
- `- [ ] Amministrazione → Utenti (plugin 1.6.0): righe con "Admin"/"Disattivato" e le icone dei contatti; sulla propria riga niente "Imposta password"; "Imposta password" a un account di prova (le sue sessioni si chiudono), "Invia codice di recupero" (arriva, e con "Ho già un codice" fa cambiare la password), "Scollega contatti".`
- `- [ ] Amministrazione → WonderFlix → "Recupero password": Discord ed email, utenti con un contatto, promemoria, "Invia prova a me" con l'esito per canale.`

- [ ] **Step 3: build**

`config/wonderflix.json` deve esserci nel worktree (`config/`); se manca, fermati e segnalalo. Poi:

```powershell
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

Expected: `√ Built build\windows\x64\runner\Release\wonderflix.exe`. Non lanciare l'app. Dopo la build, `git checkout -- windows/flutter/` se cambiano solo le fine riga.

- [ ] **Step 4: commit**

Suite intera e `flutter analyze`, poi:

```powershell
git add docs
git commit -m "docs: align the password recovery spec with plan 18c"
```

### Task 9: prova a mano (orchestratore e utente)

L'utente avvia la build del Task 8 **da Esplora file** (un'app lanciata da Claude scrive AppData in una cartella separata). Sul server c'è la build di prova del plugin 1.6.0.0, con Discord ed email configurati e i promemoria a 0 (**non** riaccenderli qui). Serve l'account di prova non admin del 18b, con i suoi contatti collegati.

1. **Amministrazione → Utenti** (fra Sessioni e Manutenzione):
   - le righe con "Admin" e "Disattivato", le icone di Discord ed email piene per chi li ha, con il nome e l'email mascherata nel tooltip;
   - sulla propria riga non c'è "Imposta password".
2. **"Imposta password"** sull'account di prova → l'avviso "Password impostata…"; l'account di prova aperto su un altro dispositivo (o jellyfin-web) deve rientrare; si entra con la password nuova.
3. **"Invia codice di recupero"** sull'account di prova → "Codice mandato su Discord ed email"; il codice arriva. Poi, nell'accesso, "Password dimenticata?" → il nome → **"Ho già un codice"** → il codice e una password nuova → si entra.
4. **"Scollega contatti"** sull'account di prova → le icone tornano vuote; nelle Impostazioni dell'account di prova "Non collegato".
5. **WonderFlix → "Recupero password":** "Discord: configurato", "Email: configurato", il conteggio, "Promemoria spenti"; "Invia prova a me" → l'esito per canale, e arrivano il DM e l'email ai propri contatti.

Con l'ok dell'utente: merge fast-forward su `main` e push (vedi la memoria `wonderflix-workflow`), poi la release. Togliendo il worktree, `build/` può avere percorsi troppo lunghi: `cmd /c rd /s /q "\\?\<percorso>"`.

## Release (orchestratore, dopo il merge)

Ogni passo che pubblica (push dei tag, manifest, pubblicazione della release, configurazione del server) va fatto con l'ok dell'utente.

1. **Plugin 1.6.0** (vedi `docs/RELEASING.md`, sezione del plugin):
   - il csproj è già a `1.6.0`;
   - `git tag watch-party-plugin-v1.6.0` e push del tag. Il workflow pubblica una **pre-release** con `wonderflix-watch-party_1.6.0.zip` e `.zip.md5`; `releases/latest` resta l'app;
   - **controllo dei riferimenti** della dll della release contro Jellyfin 10.11.9 (progetto `refprobe` nella scratchpad, da ricreare: console `net9.0`, `FrameworkReference Microsoft.AspNetCore.App`, `Jellyfin.Controller`/`Jellyfin.Model` 10.11.9, risoluzione di ogni `TypeReference`/`MemberReference`). Atteso: 0 non risolti;
   - in `jellyfin-plugin-watch-party/manifest.json`, una voce in cima a `versions`:
     - `"version": "1.6.0.0"`, `"targetAbi": "10.11.0.0"`;
     - `sourceUrl` della pre-release, `checksum` uguale al contenuto del `.md5`, `timestamp` in UTC;
     - `changelog` in italiano, per esempio: "Recupero e cambio della password per WonderFlix 0.12.0: contatti Discord ed email verificati con un codice, «Password dimenticata?» nell'app, utenti e stato del recupero per l'admin. Bot Discord, SMTP e promemoria si configurano nella pagina del plugin.";
   - aggiorna `description` e `overview` come in `meta.template.json` (hanno già il recupero della password);
   - commit `chore: publish the watch party plugin 1.6.0`, push.
2. **Server:**
   - controlla che nessuno stia guardando;
   - `app-jellyfin stop`;
   - sposta la cartella di prova `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.6.0.0` in `~/wfwp-backup/1.6.0.0-prova` (altrimenti il Catalogo non la sostituirebbe mai: ha la stessa versione);
   - `app-jellyfin start`;
   - l'utente installa 1.6.0 da Dashboard → Plugin → Catalogo;
   - riavvio, poi nel log `Loaded plugin: "WonderFlix Watch Party" "1.6.0.0"`, l'md5 della dll uguale a quello della dll nello zip, e nella configurazione `ContactReminderDays` ancora 0, bot e SMTP al loro posto.
3. **App 0.12.0, non obbligatoria** (vedi `docs/RELEASING.md`, sezione dell'app):
   - versione nel `pubspec.yaml`, commit `chore: release 0.12.0`, tag `v0.12.0`, push;
   - il workflow crea la bozza con `WonderFlix-Setup-0.12.0.exe` e `.sha256`;
   - le note in italiano le scrivo io nella bozza, senza `min-version`. Devono dire:
     - Impostazioni → Account, ora in cima, con "Cambia password" e i contatti per il recupero (Discord ed email, verificati con un codice e con la password attuale);
     - "Password dimenticata?" nell'accesso: un codice su Discord o per email (non per gli admin), e "Ho già un codice";
     - il promemoria "Proteggi il tuo account" nella cassetta;
     - per gli admin la scheda Utenti e la card "Recupero password";
     - che il recupero vuole il plugin 1.6.0 (senza, c'è solo il cambio della password);
   - la pubblica l'utente.
4. **Promemoria** (dopo che l'app 0.12.0 è pubblicata):
   - l'utente mette "Reminder every (days)" a 14 nella pagina del plugin e salva;
   - il primo giro è 5 minuti dopo l'avvio di Jellyfin: per provarlo subito, `app-jellyfin restart` con nessuno che guarda. Il giro scrive la voce a tutti gli utenti attivi non admin senza un contatto raggiungibile (è il comportamento voluto) e segna `LastReminderAt`;
   - prova (punto 5 di §12): l'account di prova senza contatti (scollegati nel Task 9) ha "Proteggi il tuo account" nella cassetta; il clic apre Impostazioni; dopo il collegamento la voce sparisce (il plugin la toglie alla conferma).
5. **Documenti:**
   - `docs/IDEE.md`: esce l'idea 5; fra le fatte entra "Spec L — recupero e cambio della password (plugin 1.6.0, app 0.12.0)";
   - spec: "Stato: realizzata; plugin 1.6.0 e app 0.12.0 pubblicati il …", e in §14/§15 la build di prova sostituita dal Catalogo e i promemoria a 14;
   - commit `docs: Spec L done in the ideas list`, push.

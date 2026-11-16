# Revisione finale, fase 5: Amici, consigli, notifiche — piano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notifiche con righe tutte uguali (avatar di chi manda, frase, azione), gruppi per giorno e "Per te · Server" per gli admin; Amici con sezioni chiare e ⋯ con "Invita a un Match"; Consiglia con la griglia di avatar; una forma sola per le carte d'invito, con la barretta dei 10 secondi.

**Architecture:** Tre pezzi nuovi e piccoli (`ui/bold_spans.dart`, `ui/sender_avatar.dart`, `features/inbox/inbox_row.dart`) e due file di funzioni pure (`inbox_groups.dart`, i gruppi in `inbox_time.dart`) su cui si rifà `inbox_panel.dart`. Amici e Consiglia cambiano dentro i loro file. Le carte passano tutte da `InviteCardFrame`, che tiene il conto alla rovescia (i tre notifier non hanno più il loro `Timer`). Nessun cambio al plugin: "Svuota" su una sola vista toglie le voci una per una con `removeInboxEntry`.

**Tech Stack:** Flutter 3.47.5, flutter_riverpod 3.x, lucide_icons_flutter, flutter_test, fake_async.

**Spec:** `docs/superpowers/specs/2026-11-16-revisione-finale-ui-design.md` §7 (tutta), §2.1, §3.1, §10. Bozza: `docs/superpowers/specs/2026-11-16-revisione-finale-bozze/social.html`. Poggia sul piano della fase 1 (`2026-11-16-revisione-finale-fase-1-comuni.md`), che è già eseguito.

## Global Constraints

- Lavoro nel worktree `.claude/worktrees/revisione-finale`, branch `revisione-finale-ui`. Comandi da `app/`. In Git Bash: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Il worktree ha bisogno di `config/wonderflix.json` copiato da `C:\Users\sidot\Documents\Github\wonderflix\app\config\`, poi `flutter pub get` e `flutter gen-l10n` prima di `analyze`/`test`.
- Dalla fase 1 ci sono già, e si usano senza rifarli: `PanelHeader({title, subtitle, actions, closeTooltip, onClose})`, `PanelRowsSkeleton({rows})`, `ShellSidePanel.width == 380`, l'ordine Watch party · Amici · Notifiche, il messaggio di Consiglia in `TvTextFieldFrame`, `friendsWatchingEpisode` col formato "S1:E2", le sezioni di Amici e il titolo del menu dei party senza `toUpperCase`, i temi di `ChoiceChip`/checkbox.
- Nessun colore nuovo: solo `WfColors` (`bg`, `surface`, `surfaceHigh`, `border`, `gold`, `cream`, `creamMuted`, `error`, `online`). Titoli con `WfText.display(n)`. Numeri che cambiano con `FontFeature.tabularFigures()`.
- Testi in `l10n/app_it.arb` e `l10n/app_en.arb`, plurali con ICU; le chiavi che restano senza uso si tolgono. Niente etichette in maiuscolo. Episodi sempre "S1:E4".
- Fuori dalla TV il comportamento TV non cambia, e viceversa. Amici e Notifiche in TV restano assenti.
- Nessun cambio al plugin. Nessuna lettura nuova all'apertura dei pannelli, salvo le immagini degli avatar per nome (`avatarImageProvider`, già a lotti e in cache).
- `dart format` solo sulle righe toccate.
- Widget test con un indicatore indeterminato (la rotellina della ricerca) non si assestano: niente `pumpAndSettle`, `pump` espliciti.
- Commit: messaggio in italiano, nessun trailer `Co-Authored-By`, mai le parole `closes`/`fixes`/`resolves`. Messaggi su più righe con `git commit -F <file>` (senza BOM).
- Mai chiudere processi per nome immagine (`taskkill /IM`, `pkill`).

## Decisioni di questo piano

- **Questa settimana** = da 2 a `inboxDaysShown` (6) giorni di calendario fa, come le ore relative ("3 giorni fa"); oltre, "Prima". Una voce con l'ora nel futuro (orologio del server avanti) è "Oggi".
- **"Server"** (solo admin) raccoglie questi tipi di `inbox_models.dart`: `DownloadNeedsYouEntry`, `DownloadStalledEntry`, `LightenBlockedEntry`, `SpaceOperationFailedEntry`, `DiskAlmostFullEntry`, `RestartPendingEntry`, `RecoveryStartedEntry`, `RecoveryBlockedEntry`, `RequestPendingEntry`, `ReportPendingEntry` (la segnalazione aperta arriva solo agli admin). **"Per te"** tutto il resto: `InviteEntry`, `MatchInviteEntry`, `RecommendationEntry`, `AnnouncementEntry`, `NewTitlesEntry`, `RequestAvailableEntry`, `RequestApprovedEntry`, `RequestDeclinedEntry`, `ContactReminderEntry`, `ReportResolvedEntry`. Lo `switch` è esaustivo sulla classe sigillata: un tipo nuovo non compila finché non si sceglie.
- **Numero sulle pastiglie** = voci evidenziate (non lette a questa apertura) di quella vista; a 0 non si mostra.
- **Azione a destra:** "Unisciti" per inviti al party (solo se il party è nell'elenco e non ci sei) e al Match; "Apri" per ogni voce che ha dove andare; niente per annuncio e novità. La riga intera fa la stessa cosa dell'azione; il party non elencato non fa niente.
- **Toast dell'invito:** titolo `notifInviteTitle(nome, titolo)`, testo vuoto. Il push web del plugin resta col testo vecchio (niente plugin).
- **Carte:** il conto alla rovescia sta nella carta, non più nei notifier. Senza un party o un Match nell'invito ma con l'invito nella cassetta, la locandina viene da `InviteEntry.imageItemId` dello stesso gruppo; senza, il simbolo. La carta del party appena nato (non un invito) tiene "{host} ha avviato un watch party".

## Review Focus

- **Admin che svuota "Server":** spariscono solo le voci di Server; quelle di "Per te" restano anche dopo la rilettura; se un `removeInboxEntry` fallisce c'è la snackbar e la lista torna come sul plugin. Test in Task 5.
- **Puntatore sopra la carta all'ultimo secondo, poi via:** la carta riparte da dove era (non da 10 s) e si chiude; con movimento ridotto non si chiude mai, e "Più tardi" non tocca la cassetta. Test in Task 8.
- **Nome lungo, testo a 1,5 e 380 di larghezza:** righe delle notifiche e degli amici senza overflow, ✕ e ⋯ sempre dentro. Test in Task 3 e Task 6.
- **Consiglia oltre il limite:** con 35 amici online "Scegli gli online" ne accende 30, gli altri restano spenti e compare "Al massimo 30 amici alla volta". Test in Task 7.
- **"Invita a un Match" che non riesce dopo aver aperto la sala:** la sala resta aperta con la sua pagina e la snackbar dice il motivo; niente sala orfana senza pagina. Test in Task 6.

---

### Task 1: Funzioni pure (gruppi, viste, grassetti, episodi, membri)

**Files:**
- Modify: `app/lib/features/inbox/inbox_time.dart`, `app/lib/core/social/inbox_models.dart` (`formatEpisodeRanges`, riga `'S$season ${...}'`), `app/lib/features/watch_party/watch_party_directory.dart`
- Create: `app/lib/features/inbox/inbox_groups.dart`, `app/lib/ui/bold_spans.dart`
- Test: `app/test/features/inbox/inbox_time_test.dart` (aggiungi), `app/test/features/inbox/inbox_groups_test.dart` (nuovo), `app/test/ui/bold_spans_test.dart` (nuovo), `app/test/core/social/inbox_models_test.dart` (aggiorna), `app/test/features/watch_party/watch_party_directory_test.dart` (aggiungi)

**Interfaces:**
- Produces:
  - `enum InboxDay { today, yesterday, thisWeek, earlier }` e `InboxDay inboxDayOf(DateTime createdAt, DateTime now)` in `inbox_time.dart` (usa `_calendarDays`).
  - `bool isServerEntry(InboxEntry entry)` in `inbox_groups.dart` (lista sopra).
  - `TextSpan boldSpans(String text, List<String> bold)` in `ui/bold_spans.dart`: la prima occorrenza di ogni stringa non vuota in `cream` w600, il resto com'è; una stringa che non c'è si ignora. Sostituisce `_inviteFromSpan` di `inbox_panel.dart`.
  - `GroupInfo? listedGroup(List<GroupInfo> groups, String groupId)` in `watch_party_directory.dart`: id confrontati senza trattini né maiuscole.
  - `formatEpisodeRanges` con i due punti: `S3:E1–E10`, `S3:E1–E4, E6`, `S2:E10 · S3:E1–E3`.

- [ ] **Step 1: Test che falliscono**

```dart
test('gruppi per giorno', () {
  final now = DateTime(2026, 11, 16, 10);
  expect(inboxDayOf(DateTime(2026, 11, 16, 0, 5).toUtc(), now), InboxDay.today);
  expect(inboxDayOf(now.add(const Duration(minutes: 3)).toUtc(), now), InboxDay.today,
      reason: 'orologio del server avanti');
  expect(inboxDayOf(DateTime(2026, 11, 15, 23, 59).toUtc(), now), InboxDay.yesterday);
  expect(inboxDayOf(DateTime(2026, 11, 14, 9).toUtc(), now), InboxDay.thisWeek);
  expect(inboxDayOf(DateTime(2026, 11, 10, 9).toUtc(), now), InboxDay.thisWeek);
  expect(inboxDayOf(DateTime(2026, 11, 9, 9).toUtc(), now), InboxDay.earlier);
});
test('Server: download, spazio, riavvio, recupero, richieste in attesa', () {
  expect(isServerEntry(testRequestPending()), isTrue);
  final t = DateTime.utc(2026, 11, 16);
  expect(isServerEntry(RestartPendingEntry(id: 'x', seq: 1, createdAt: t, read: false)), isTrue);
  expect(isServerEntry(DiskAlmostFullEntry(id: 'd', seq: 1, createdAt: t, read: false, percent: 95)), isTrue);
  expect(isServerEntry(ReportPendingEntry(id: 'p', seq: 1, createdAt: t, read: false,
      reportId: 'r', fromName: 'Garg', itemId: 'm1', title: 'Dune')), isTrue);
  expect(isServerEntry(testInvite()), isFalse);
  expect(isServerEntry(testRequestAvailable()), isFalse);
  expect(isServerEntry(testRecommendationEntry()), isFalse);
});
test('grassetto sulla prima occorrenza di ogni nome', () {
  final span = boldSpans('Luigi ti invita a guardare Dune', ['Luigi', 'Dune']);
  final bold = [for (final s in span.children!.cast<TextSpan>())
    if (s.style?.fontWeight == FontWeight.w600) s.text];
  expect(bold, ['Luigi', 'Dune']);
  expect(span.toPlainText(), 'Luigi ti invita a guardare Dune');
  expect(boldSpans('Nuova richiesta', ['']).toPlainText(), 'Nuova richiesta');
});
test('un gruppo dell\'elenco per id, con o senza trattini', () {
  final g = testGroup(id: 'AB-12', participants: ['Davide', 'Luigi']);
  expect(listedGroup([g], 'ab12')?.participants.length, 2);
  expect(listedGroup([g], 'zz'), isNull);
});
```

In `inbox_models_test.dart` i valori attesi di `formatEpisodeRanges` diventano `'S3:E1–E10'`, `'S3:E1–E4, E6'`, `'S2:E10 · S3:E1–E3'`, `'S1:E5'`.

- [ ] **Step 2:** `flutter test test/features/inbox/inbox_time_test.dart test/features/inbox/inbox_groups_test.dart test/ui/bold_spans_test.dart test/core/social/inbox_models_test.dart test/features/watch_party/watch_party_directory_test.dart` → FAIL.
- [ ] **Step 3:** implementa le cinque funzioni; in `inbox_panel.dart` sostituisci `_inviteFromSpan` con `boldSpans(text, [name])` (stesso aspetto).
- [ ] **Step 4:** stesso comando → PASS; poi `flutter test test/features/inbox` → PASS (i test delle novità che cercano "S1 E5" passano a "S1:E5").
- [ ] **Step 5: Commit** `feat(app): gruppi per giorno, voci del server e episodi S1:E2 nelle novità`

### Task 2: Avatar di chi manda e cerchio di sistema

**Files:**
- Create: `app/lib/ui/sender_avatar.dart`
- Test: `app/test/ui/sender_avatar_test.dart`

**Interfaces:**
- Consumes: `UserAvatar.lookup(userId:, name:, size:, muted: true)` (`ui/user_avatar.dart`), `imageUrlsProvider.primaryOf(id)`, `WfImage`.
- Produces:
  - `class SenderAvatar extends StatelessWidget { const SenderAvatar({super.key, required String name, String? userId, String? posterItemId, IconData? badge, double size = 40}); }`: avatar `size`; in basso a destra (sporge di 4) la locandina 18×27 con angoli 3 e bordo `surface` 1,5 se c'è `posterItemId`, altrimenti, se c'è `badge`, un cerchio 18 `surfaceHigh` con l'icona oro 11. Chiave della locandina `Key('sender-poster')`, del simbolo `Key('sender-badge')`.
  - `class SystemAvatar extends StatelessWidget { const SystemAvatar({super.key, required IconData icon, bool alarm = false, String? posterItemId, double size = 40}); }`: cerchio `surfaceHigh` con l'icona oro 18; con `alarm` icona e bordo `WfColors.error`. Stessa locandina sovrapposta.
  - Tutti e due escludono la semantica (il nome è nella frase accanto).

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('avatar con la locandina sovrapposta', (t) async {
  await pumpApp(t, const Scaffold(body: Center(
      child: SenderAvatar(name: 'Luigi', posterItemId: 'm1'))), overrides: [avatarsFor(const [])]);
  expect(find.byType(UserAvatar), findsOneWidget);
  expect(find.byKey(const Key('sender-poster')), findsOneWidget);
  expect(t.getSize(find.byKey(const Key('sender-poster'))), const Size(18, 27));
});
testWidgets('senza locandina, il simbolo', (t) async {
  // SenderAvatar(name: 'Garg', badge: LucideIcons.heartHandshake)
  // → find.byKey(Key('sender-badge')) findsOneWidget, sender-poster findsNothing
});
testWidgets('lo spazio quasi pieno è rosso', (t) async {
  // SystemAvatar(icon: LucideIcons.hardDrive, alarm: true) → l'Icon ha color WfColors.error;
  // SystemAvatar(icon: LucideIcons.rotateCw) → color WfColors.gold
});
```

(`avatarsFor` è in `test/support/avatar_fakes.dart`.)

- [ ] **Step 2:** `flutter test test/ui/sender_avatar_test.dart` → FAIL.
- [ ] **Step 3:** implementa i due widget (uno `Stack(clipBehavior: Clip.none)` con `Positioned(right: -4, bottom: -4)`).
- [ ] **Step 4:** stesso comando → PASS.
- [ ] **Step 5: Commit** `feat(app): avatar di chi manda con la locandina piccola`

### Task 3: La riga comune delle notifiche

**Files:**
- Create: `app/lib/features/inbox/inbox_row.dart`
- Modify: `l10n/app_it.arb`, `l10n/app_en.arb` (`inboxRemove`: "Togli dalla lista" / "Remove from list"; nuova `inboxOpen`: "Apri" / "Open")
- Test: `app/test/features/inbox/inbox_row_test.dart`

**Interfaces:**
- Produces: `class InboxRow extends StatefulWidget { const InboxRow({super.key, required bool highlighted, required Widget leading, required InlineSpan sentence, Widget? below, required String meta, Widget? action, VoidCallback? onOpen, Key? openKey, required VoidCallback onRemove}); }`
  - Riga: pallino oro 8 (chiave `inbox-unread`) se `highlighted`, `leading`, poi colonna con `Text.rich(sentence)` (`cream` 14, max 3 righe), `below` (se c'è), e una riga con `meta` (`creamMuted` 12, cifre tabellari, ellissi) e `action` a destra; in fondo la ✕.
  - Con `highlighted` il fondo è `WfColors.surfaceHigh` al 50%.
  - Tutta la riga è un `InkWell(key: openKey, onTap: onOpen)`; con `onOpen` `null` non risponde al tocco.
  - ✕: `IconButton` 16, tooltip `l.inboxRemove`, opacità 0,4, 1 col passaggio del mouse sulla riga o col focus sulla ✕; raggiungibile con Tab.
  - Chiavi delle frasi da cercare nei test: i test di oggi cercano `inbox-request-<id>`, `inbox-alert-<id>`, `inbox-report-<id>`, `inbox-recommendation-<id>`, `inbox-contact-reminder-<id>` e li toccano: quelle chiavi passano in `openKey` (Task 4).
- Consumes: nient'altro dai task precedenti.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('la ✕ si vede sempre al 40%, piena col mouse', (t) async {
  // InboxRow(highlighted: false, leading: SizedBox(40,40), sentence: TextSpan(text: 'Ciao'),
  //          meta: 'adesso', onRemove: () => removed++)
  final opacity = find.ancestor(of: find.byTooltip('Togli dalla lista'), matching: find.byType(Opacity));
  expect(t.widget<Opacity>(opacity).opacity, 0.4);
  // gesture mouse dentro la riga → pump → opacity 1
  await t.tap(find.byTooltip('Togli dalla lista'));
  expect(removed, 1);
});
testWidgets('tutta la riga apre; senza onOpen niente', (t) async {
  // tap sul testo meta 'adesso' → opened == 1; con onOpen: null il tap non lancia e non apre
});
testWidgets('evidenziata: pallino e fondo più chiaro', (t) async {
  // highlighted: true → find.byKey(Key('inbox-unread')) findsOneWidget;
  // un DecoratedBox/ColoredBox antenato del testo con colore WfColors.surfaceHigh.withValues(alpha: 0.5)
});
testWidgets('nome lungo, testo a 1,5, larga 380: niente overflow', (t) async {
  // sentence con un nome di 60 caratteri, action: TextButton('Unisciti'), MediaQuery textScaler 1.5,
  // SizedBox(width: 380) → t.takeException() isNull; la ✕ è dentro i 380 (getTopRight.dx <= 380)
});
```

- [ ] **Step 2:** `flutter test test/features/inbox/inbox_row_test.dart` → FAIL.
- [ ] **Step 3:** implementa `InboxRow`; cambia `inboxRemove`, aggiungi `inboxOpen`; `flutter gen-l10n`.
- [ ] **Step 4:** stesso comando → PASS.
- [ ] **Step 5: Commit** `feat(app): una riga sola per tutte le notifiche`

### Task 4: Le voci delle Notifiche sulla riga comune, e una frase per invito

**Files:**
- Modify: `app/lib/features/inbox/inbox_panel.dart` (`_EntryTile` e i contenuti per tipo), `app/lib/features/inbox/notification_text.dart` (invito e Match), `app/lib/features/match/match_invites.dart:88`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Delete (se restano senza uso): `inbox_request_rows.dart` → tieni `inboxRequestTitle`/`inboxRequestPendingText` (spostali in `inbox_panel.dart` o lascia il file con solo quelle), `InboxRequestIcon`, `InboxRequestContent`, `InboxAlertContent` (resta `alertIconOf`), `InboxContactReminderContent` (resta `inboxContactReminderText`)
- Test: `app/test/features/inbox/inbox_panel_test.dart`, `inbox_match_invite_test.dart`, `inbox_recommendation_test.dart`, `inbox_reports_test.dart`, `inbox_requests_navigation_test.dart`, `inbox_alert_rows_test.dart`, `inbox_contact_reminder_test.dart`, `notification_text_test.dart`, `inbox_toaster_test.dart`

**Interfaces:**
- Consumes: `InboxRow` (Task 3), `SenderAvatar`/`SystemAvatar` (Task 2), `boldSpans`, `listedGroup` (Task 1).
- Produces: arb `notifInviteTitle` = "{name} ti invita a guardare {title}" / "{name} invites you to watch {title}" (placeholder `title` String); `notifMatchInviteTitle` = "{name} ti invita a un Match" / "{name} invites you to a Match"; `partyMembers` = "{count, plural, =1{1 nel party} other{{count} nel party}}" / "{count} in the party". Si tolgono `inboxInviteFrom` e `matchInviteFrom`.

Ogni tipo (leading · frase con i grassetti · sotto · azione · apre):

| Voce | Leading | Frase (grassetto) | Sotto | Azione / riga |
|---|---|---|---|---|
| `InviteEntry` | `SenderAvatar(fromName, poster: imageItemId)` | `notifInviteTitle(from, title)` (from, title) | — | "Unisciti" e join come oggi se elencato e non dentro; riga = join; meta `"$time · ${partyMembers(n)}"` se il gruppo è in `listedGroup` con membri, `"$time · Ci sei già"`, `"$time · Party finito"` |
| `MatchInviteEntry` | `SenderAvatar(fromName, badge: heartHandshake)` | `notifMatchInviteTitle(from)` (from) | — | "Unisciti" = `joinMatchRoom`; riga uguale |
| `RecommendationEntry` | `SenderAvatar(fromName, poster: itemId)` | `inboxRecommendation` (from, title) | il messaggio «…» | "Apri" → titolo |
| `RequestPendingEntry` | `SenderAvatar(requesterName)`; nome vuoto → `SystemAvatar(inbox)` | `inboxRequestPendingText` (nome, titolo) | — | "Apri" → Richieste, In attesa |
| `ReportPendingEntry` | `SenderAvatar(fromName, poster: titleId)` | `inboxReportPending` (from) | `reportTitleLine(...)` | "Apri" se `titleId`, come oggi |
| `RequestAvailableEntry` | `SystemAvatar(clapperboard, poster: itemId)` | `inboxRequestAvailable` (titolo) | — | "Apri" come oggi |
| `ReportResolvedEntry` | `SystemAvatar(circleCheck/circleAlert, poster: titleId)` | `_reportResolvedText` (titolo) | la nota | "Apri" se `titleId` |
| `ContactReminderEntry` | `SystemAvatar(shieldCheck)` | `inboxContactReminderTitle` (tutto) | `inboxContactReminderText` | "Apri" → `/settings` |
| `AlertedEntry` | `SystemAvatar(alertIconOf, alarm: entry is DiskAlmostFullEntry, poster: itemId di approvata/rifiutata)` | `notificationTextOf(...).title` (tutto) | `.body` | "Apri" → `.route` |
| `AnnouncementEntry` | `SystemAvatar(megaphone)` | `inboxAnnouncement` (tutto) | `SelectableText` del testo | niente, la riga non apre |
| `NewTitlesEntry` | `SystemAvatar(sparkles)` | `inboxNewTitles(summary)` (tutto) | le righe di oggi, ciascuna con locandina 24×36, il nome e i codici `formatEpisodeRanges`; "Mostra tutto (N)"; "…e altri" | niente, la riga non apre (aprono le sue righe) |

Ogni azione o apertura chiude il pannello come oggi. `notification_text.dart`: `InviteEntry` → `text(l.notifInviteTitle(entry.fromName, entry.title), '', '/inbox')`. La carta del Match (`match_invites.dart:88`) usa `notifMatchInviteTitle` finché il Task 8 non la rifà.

- [ ] **Step 1: Test che falliscono** (in `inbox_panel_test.dart` e nei file per tipo)

```dart
testWidgets('invito: avatar con la locandina, frase unica, "2 nel party"', (t) async {
  api.inboxSnapshot = inbox([testInvite(fromName: 'Luigi', title: 'Dune', createdAt: fiveMinutesAgo())]);
  await pumpPanel(t, parties: [testGroup(id: 'g1', participants: ['Luigi', 'Peach'])]);
  expect(find.text('Luigi ti invita a guardare Dune', findRichText: true), findsOneWidget);
  expect(find.text('5 min fa · 2 nel party'), findsOneWidget);
  expect(find.byType(SenderAvatar), findsOneWidget);
  expect(find.text('Unisciti'), findsOneWidget);
});
testWidgets('invito a un party finito: la riga non apre niente', (t) async {
  // parties: [] → '… · Party finito', nessun 'Unisciti'; tap sulla frase → syncPlay.calls vuoto
});
testWidgets('invito: toccare la riga entra come Unisciti', (t) async {
  // parties: [g1] → tap sulla frase → syncPlay.calls contiene 'join g1', pannello chiuso
});
testWidgets('Match: "Luigi ti invita a un Match", la riga entra nella sala', (t) async { /* in inbox_match_invite_test */ });
testWidgets('consiglio: Apri a destra apre il titolo', (t) async {
  // find.text('Apri') → tap → rotta /item/m1, pannello chiuso
});
testWidgets('spazio quasi pieno: cerchio rosso', (t) async {
  // DiskAlmostFullEntry → find.byWidgetPredicate((w) => w is SystemAvatar && w.alarm) findsOneWidget
});
testWidgets('annuncio: niente azione, la riga non apre', (t) async { /* find.text('Apri') findsNothing */ });
test('toast dell\'invito: la stessa frase', () {
  final text = notificationTextOf(testInvite(fromName: 'Luigi', title: 'Dune'), it);
  expect(text.title, 'Luigi ti invita a guardare Dune');
  expect(text.body, '');
  expect(notificationTextOf(testMatchInviteEntry(fromName: 'Luigi'), it).title,
      'Luigi ti invita a un Match');
});
```

I test di oggi che cercano `find.byTooltip('Rimuovi')`, "ti invita a guardare" senza titolo, "ti invita a un match" o le opacità 0/1 della ✕ si aggiornano ai valori nuovi; quelli che toccano `inbox-request-…`, `inbox-alert-…` ecc. funzionano con `openKey`.

- [ ] **Step 2:** `flutter test test/features/inbox` → FAIL sui casi nuovi.
- [ ] **Step 3:** riscrivi `_EntryTile` come uno `switch` che produce `InboxRow`; `_InviteContent` e `_MatchInviteContent` diventano `_InviteRow`/`_MatchInviteRow` (stateful per il `_joining` di oggi). Togli i widget rimasti senza uso. Cambia le chiavi arb; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/inbox test/features/match` → PASS.
- [ ] **Step 5: Commit** `feat(app): notifiche con chi le manda, una frase e l'azione a destra`

### Task 5: Gruppi per giorno, "Per te · Server", Svuota tutto

**Files:**
- Modify: `app/lib/features/inbox/inbox_panel.dart` (`_Entries`, `_ClearButton`, testa), `app/lib/features/inbox/inbox_controller.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/inbox/inbox_panel_test.dart`, `app/test/features/inbox/inbox_controller_test.dart`

**Interfaces:**
- Consumes: `inboxDayOf`, `isServerEntry` (Task 1), `isAdminProvider` (`features/admin/admin_providers.dart`), `PanelHeader(actions:)` e `PanelRowsSkeleton` (fase 1).
- Produces: `Future<SocialFailure?> InboxController.removeAll(List<String> ids)`: ottimista come `remove` (`ids.fold(snapshot, (s, id) => s.without(id))`), poi un `api.removeInboxEntry(id)` per voce in fila; al primo errore si ferma e restituisce il motivo; rilegge sempre (come `_act`).
- Arb (it / en):
  - `inboxGroupToday` "Oggi" / "Today", `inboxGroupYesterday` "Ieri" / "Yesterday", `inboxGroupThisWeek` "Questa settimana" / "This week", `inboxGroupEarlier` "Prima" / "Earlier";
  - `inboxForYou` "Per te" / "For you", `inboxServer` "Server" / "Server", `inboxServerHint` "Avvisi per gli admin: download, spazio, riavvii, recupero account e richieste in attesa." / "Admin alerts: downloads, space, restarts, account recovery and pending requests.";
  - `inboxClear` "Svuota tutto" / "Clear all", `inboxClearAsk` "Svuota tutto?" / "Clear all?", `inboxClearConfirm` "Sì, svuota" / "Yes, clear";
  - `inboxEmpty` "Niente di nuovo. Gli inviti e i consigli degli amici arrivano qui." / "Nothing new. Invites and tips from friends show up here.", `inboxServerEmpty` "Nessun avviso del server." / "No server alerts.";
  - `inboxUnavailable` "Non riesco a leggere le notifiche. Controlla la connessione e riprova." / "Can't load notifications. Check your connection and try again."

Regole:
- Admin: sotto la testa due `ChoiceChip` "Per te N" · "Server N" (chiavi `inbox-view-you`, `inbox-view-server`), vista di partenza "Per te"; in "Server" sotto le pastiglie la riga `inboxServerHint`. Chi non è admin non vede pastiglie né riga, e vede tutte le voci.
- Le voci della vista, dalla più recente, sotto i titoli dei gruppi non vuoti (Inter 12,5 w600 `creamMuted`, in frase normale), nell'ordine Oggi, Ieri, Questa settimana, Prima.
- "Svuota tutto" (in `actions` di `PanelHeader`, solo se la vista ha voci) → sul posto "Svuota tutto?" + `TextButton` rosso "Sì, svuota" (chiave `inbox-clear-confirm`) per `InboxPanel.clearConfirmFor` (4 s). Conferma: chi non è admin, o un admin la cui altra vista è vuota → `clear()`; altrimenti `removeAll(ids della vista)`.
- Vuoto: `inboxEmpty` (in "Server" `inboxServerEmpty`). In caricamento: `PanelRowsSkeleton` (già dalla fase 1). Errore: `inboxUnavailable` e "Riprova".

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('gruppi: Oggi, Ieri, Prima', (t) async {
  // withClock(Clock.fixed(DateTime(2026, 11, 16, 12))): tre annunci del 16, 15 e 1 novembre
  // → find.text('Oggi'), find.text('Ieri'), find.text('Prima') una volta ciascuno, in quest'ordine
  //   (getTopLeft(...).dy crescente); find.text('Questa settimana') findsNothing
});
testWidgets('chi non è admin non vede Per te · Server', (t) async {
  // isAdminProvider.overrideWithValue(false) → find.text('Per te') findsNothing, find.text('Server') findsNothing
});
testWidgets('admin: le voci del server stanno in Server, col numero', (t) async {
  // isAdminProvider true; voci: testInvite (non letta), testRequestPending (non letta), RestartPendingEntry (non letta)
  // → ChoiceChip 'Per te' con '1', 'Server' con '2'; in Per te si vede l'invito, non la richiesta;
  // tap 'Server' → si vedono richiesta e riavvio e la riga 'Avvisi per gli admin: download, spazio, riavvii, recupero account e richieste in attesa.'
});
testWidgets('admin: Svuota tutto in Server toglie solo quelle', (t) async {
  // come sopra, vista Server: tap 'Svuota tutto' → 'Svuota tutto?' e 'Sì, svuota';
  // tap 'Sì, svuota' → api.calls contiene 'remove-entry <richiesta>' e 'remove-entry <riavvio>',
  // NON 'clear-inbox'; dopo la rilettura (api.inboxSnapshot senza quelle due) l'invito c'è ancora in Per te
});
testWidgets('Svuota tutto? torna com\'era dopo 4 s', (t) async { /* pump(InboxPanel.clearConfirmFor) → 'Svuota tutto' */ });
testWidgets('chi non è admin: Sì, svuota svuota tutto', (t) async { /* api.calls contiene 'clear-inbox' */ });
testWidgets('vuota: la frase che invita', (t) async {
  expect(find.text('Niente di nuovo. Gli inviti e i consigli degli amici arrivano qui.'), findsOneWidget);
  expect(find.text('Svuota tutto'), findsNothing);
});
```

In `inbox_controller_test.dart`:

```dart
test('removeAll toglie subito, poi una chiamata per voce; un errore si ferma e rilegge', () async {
  // tre voci; removeAll(['a','b']) → stato senza a e b subito; api.calls ['remove-entry a','remove-entry b', ..., 'inbox']
  // con api che fallisce su 'remove-entry a': risultato non null, 'remove-entry b' non chiamato, poi 'inbox'
});
```

(Per far fallire una sola chiamata usa il meccanismo `_fail()` di `FakeSocialApi`; se fallisce tutto, il test si accontenta del primo errore e della rilettura.)

- [ ] **Step 2:** `flutter test test/features/inbox/inbox_panel_test.dart test/features/inbox/inbox_controller_test.dart` → FAIL.
- [ ] **Step 3:** implementa `removeAll`, vista, gruppi, pastiglie, Svuota; cambia gli arb; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/inbox` → PASS; i test con "Svuota"/"Conferma"/"Nessuna notifica" passano ai testi nuovi.
- [ ] **Step 5: Commit** `feat(app): notifiche per giorno e, per gli admin, Per te e Server`

### Task 6: Amici

**Files:**
- Modify: `app/lib/features/friends/friends_panel.dart`, `app/lib/features/match/match_actions.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/friends/friends_panel_test.dart`, `app/test/features/match/match_actions_test.dart` (aggiungi; crealo se non c'è)

**Interfaces:**
- Consumes: `PanelHeader(subtitle:)`, `PanelRowsSkeleton` (fase 1); `UserAvatar.lookup`; `matchEntryProvider`; `MatchRoomController.invite(List<String>)`.
- Produces: `Future<bool> openMatchRoomInviting(BuildContext context, WidgetRef ref, String userId)` in `match_actions.dart`: prende messenger e controller prima dell'attesa, `openMatchRoom` (apre e spinge la pagina); se riuscita, `invite([userId])`; un no di `invite` diventa la snackbar `matchFailureText`; la sala resta aperta. `true` se la sala è aperta.
- Arb (it / en): `friendsOnlineCount` "{count} online" / "{count} online"; `friendsIncoming` "Da rispondere ({count})" / "To answer ({count})"; `friendsOutgoing` "Richieste inviate ({count})" / "Sent requests ({count})"; `friendsOpenMatch` "Apri un Match" / "Start a Match"; `friendsInviteToMatch` "Invita a un Match" / "Invite to a Match"; `friendsEmpty` "Non hai ancora amici. Cerca qualcuno per nome qui sopra." / "No friends yet. Search for someone by name above."; `friendsSearchEmpty` "Nessuno si chiama così. Controlla il nome o chiedi il suo codice." / "Nobody has that name. Check it or ask for their code."; `friendsUnavailable` "Non riesco a leggere gli amici. Controlla la connessione e riprova." / "Can't load friends. Check your connection and try again.". Si tolgono `friendsRequests` e `friendsSent`.

Regole (spec §7.2):
- Testa: `PanelHeader(title: 'Amici', subtitle: Text(friendsOnlineCount(n)))`, n = amici online.
- Sezioni, ognuna solo se non vuota: "Da rispondere (N)" (N = `incomingCount`, il numero del badge) con "Accetta"/"Rifiuta"; "Online"; "Offline", dove ogni riga senza attività ha sotto "Offline"; in fondo "Richieste inviate (N)", chiusa, che si apre toccando il titolo (chiave `friends-outgoing-toggle`, chevron), con "In attesa"/"Annulla". Senza amici e senza richieste: `friendsEmpty`.
- Riga: avatar 32 (`UserAvatar.lookup(userId, name, size: 32, muted: true)`) col pallino verde per chi è online; azione come oggi.
- ⋯: "Invita a un Match" (solo con `matchEntryProvider`; chiude il pannello e chiama `openMatchRoomInviting`), `PopupMenuDivider`, "Rimuovi dagli amici" in `WfColors.error` con la conferma in riga di oggi. Niente "Invita a guardare" (§2.1).
- Piede fisso sotto l'elenco, sopra un filo `border`: "Ho un codice" (`_PartyCodeEntry`, con la funzione `parties`) e "Apri un Match" (con `matchEntryProvider`, chiave `friends-match` come oggi). I link in cima spariscono.
- Ricerca: nel campo, mentre `search.searching`, un `CircularProgressIndicator` 16 (strokeWidth 2) come `suffixIcon`; sotto i risultati (o al posto loro) `PanelRowsSkeleton(rows: 1)`; il piede sparisce (il codice scritto a metà resta, `maintainState`). Parole: none → "Aggiungi"; incoming → "Accetta" e "Rifiuta"; outgoing → "In attesa" e "Annulla"; friend → "✓ Amici". Nessun risultato: `friendsSearchEmpty`.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('testa con gli online e sezioni nell\'ordine', (t) async {
  api.snapshot = FriendsSnapshot(
    friends: [testFriend('u2', 'sara', online: true), testFriend('u3', 'CaptainC')],
    incoming: [testPerson('u4', 'luca88')], outgoing: [testPerson('u5', 'marta')]);
  await pumpPanel(t);
  expect(find.text('1 online'), findsOneWidget);
  final order = ['Da rispondere (1)', 'Online', 'Offline', 'Richieste inviate (1)']
      .map((s) => t.getTopLeft(find.text(s)).dy).toList();
  expect(order, [...order]..sort());
  expect(find.text('marta'), findsNothing, reason: 'Richieste inviate è chiusa');
  await t.tap(find.byKey(const Key('friends-outgoing-toggle')));
  await t.pump();
  expect(find.text('In attesa'), findsOneWidget);
});
testWidgets('Da rispondere ha lo stesso numero del badge', (t) async {
  // due incoming, tre outgoing → 'Da rispondere (2)' e container.read(friendsControllerProvider).incomingCount == 2
});
testWidgets('offline: la scritta sotto il nome; avatar da 32', (t) async {
  // find.descendant(of: riga di CaptainC, matching: find.text('Offline')) findsOneWidget;
  // t.getSize(find.byType(UserAvatar).first) == Size(32, 32)
});
testWidgets('⋯: Invita a un Match e Rimuovi in rosso, niente Invita a guardare', (t) async {
  // con matchEntryProvider true: apri il ⋯ di sara → 'Invita a un Match' e 'Rimuovi dagli amici'
  // (Text con style.color == WfColors.error), find.text('Invita a guardare') findsNothing
});
testWidgets('Invita a un Match apre la sala e invita l\'amico', (t) async {
  // FakeMatchApi: tap 'Invita a un Match' → match.calls contiene 'open' poi 'invite <room> u2'
});
testWidgets('piede: Ho un codice e Apri un Match in fondo, non in cima', (t) async {
  // getTopLeft(find.text('Apri un Match')).dy > getTopLeft(find.text('CaptainC')).dy;
  // getTopLeft(find.text('Ho un codice')).dy > getTopLeft(find.text('CaptainC')).dy
});
testWidgets('ricerca: rotellina e riga grigia mentre cerca, poi le parole giuste', (t) async {
  // enterText 'ca' → pump() → CircularProgressIndicator nel campo e PanelRowsSkeleton; piede nascosto;
  // pump(FriendSearch.debounce) + pump() con risultati incoming/outgoing/friend →
  // 'Accetta' e 'Rifiuta' nella prima, 'In attesa' e 'Annulla' nella seconda, 'Amici' con la spunta nella terza
});
testWidgets('nessun risultato e nessun amico: le frasi nuove', (t) async { /* le due stringhe di friendsSearchEmpty e friendsEmpty */ });
testWidgets('nome lungo, testo a 1,5, larga 380: niente overflow', (t) async {
  // amico online con nome di 50 caratteri e party (Unisciti + ⋯) → takeException isNull
});
```

In `match_actions_test.dart`:

```dart
testWidgets('se l\'invito non riesce la sala resta aperta e lo dice', (t) async {
  // FakeMatchApi con errore su 'invite …' → openMatchRoomInviting → true;
  // container.read(matchRoomProvider) non null; snackbar con matchFailureText; la pagina /match/<id> è aperta
});
```

I test di oggi con "RICHIESTE (2)", "Inviata", "Nessun utente trovato", "Nessun amico ancora…" e "Match del film" si aggiornano.

- [ ] **Step 2:** `flutter test test/features/friends test/features/match/match_actions_test.dart` → FAIL.
- [ ] **Step 3:** implementa; `_FriendLists` diventa stateful per la sezione chiusa; cambia gli arb; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/friends test/features/match` → PASS.
- [ ] **Step 5: Commit** `feat(app): Amici con le sezioni da fare, Invita a un Match e il piede`

### Task 7: Consiglia

**Files:**
- Modify: `app/lib/features/recommendations/recommend_panel.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/recommendations/recommend_panel_test.dart`

**Interfaces:**
- Consumes: `PanelHeader(subtitle:)` con locandina e titolo (già messi dalla fase 1, cambia solo il testo del titolo), `TvTextFieldFrame` (il messaggio è già in cornice; mettici anche il nuovo campo di ricerca), `UserAvatar.lookup`, `TvFocusBorder`.
- Arb (it / en): `recommendPanelTitle` "Consiglia" / "Recommend"; `recommendSearchHint` "Cerca tra gli amici" / "Search friends"; `recommendPickOnline` "Scegli gli online" / "Pick who's online"; `recommendMessageHint` "Messaggio, se vuoi" / "Message, if you like"; `recommendSendTo` "{count, plural, =0{Invia} =1{Invia a 1 amico} other{Invia a {count} amici}}" / "{count, plural, =0{Send} =1{Send to 1 friend} other{Send to {count} friends}}"; `recommendPickOne` "Scegli almeno un amico" / "Pick at least one friend". Si toglie `recommendSend`.

Regole (spec §7.3):
- Sopra la griglia: il campo `recommendSearchHint` (filtra per nome, senza maiuscole, solo in locale) e a destra il `TextButton` "Scegli gli online" (chiave `recommend-pick-online`): accende chi è online e può vederlo, fino a `recommendMaxRecipients`.
- Griglia (`GridView` con `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 88)`, celle alte almeno 44, di fatto ~96): avatar 48, nome (una riga, ellissi), sotto "Online" / "Offline" / "Non può vederlo". Cella `InkWell` chiave `recommend-target-<id>`, dentro `TvFocusBorder`; accesa = anello oro 2 attorno all'avatar e un cerchio oro 18 con `LucideIcons.check` (`bg`) in basso a destra (chiave `recommend-check-<id>`). Spenta (non può vederlo, o limite raggiunto e non scelta): opacità 0,4, nessun tocco. Semantica: `Semantics(selected:, button: true, label: nome)`.
- `recommendMaxReached(30)` solo quando le scelte sono 30.
- Messaggio: `buildCounter` mostra "N/200" (cifre tabellari) solo quando mancano 20 caratteri o meno, altrimenti niente.
- Piede: `WfButton.primary(label: recommendSendTo(n), icon: send)`; con n = 0 spento e sotto `recommendPickOne` in `creamMuted` 12,5. Esito: la snackbar di oggi.

- [ ] **Step 1: Test che falliscono**

```dart
testWidgets('griglia: toccare accende, il pulsante conta', (t) async {
  // targets: sara (online), Garg (online), marta (canSee: false)
  expect(find.text('Invia'), findsOneWidget);
  expect(find.text('Scegli almeno un amico'), findsOneWidget);
  await t.tap(find.byKey(const ValueKey('recommend-target-u1')));
  await t.pump();
  expect(find.byKey(const ValueKey('recommend-check-u1')), findsOneWidget);
  expect(find.text('Invia a 1 amico'), findsOneWidget);
  expect(find.text('Scegli almeno un amico'), findsNothing);
  expect(find.text('Non può vederlo'), findsOneWidget);
  await t.tap(find.byKey(const ValueKey('recommend-target-u3')));
  await t.pump();
  expect(find.byKey(const ValueKey('recommend-check-u3')), findsNothing);
});
testWidgets('Scegli gli online: al massimo 30, poi il limite', (t) async {
  // 35 target online e visibili → tap 'Scegli gli online' → 'Invia a 30 amici' e 'Al massimo 30 amici alla volta';
  // un 31° toccato resta spento
});
testWidgets('il contatore compare solo vicino al limite', (t) async {
  // enterText 179 caratteri → find.text('179/200') findsNothing; 181 → find.text('181/200') findsOneWidget
});
testWidgets('la ricerca filtra la griglia', (t) async { /* 'gar' → solo Garg */ });
testWidgets('caselle alte almeno 44 a 390×780, niente overflow', (t) async {
  // surfaceSize 390×780: getSize(recommend-target-u1).height >= 44; takeException isNull
});
testWidgets('TV: Giù dalla griglia passa le cornici e arriva a Invia', (t) async {
  // tv: true, Size(960, 540); focus sulla cella di sara; arrowDown ripetuto →
  // a un certo punto il focus è sul pulsante del piede e nessun TextField ha mai avuto il focus
});
```

I test di oggi su `CheckboxListTile`, "Invia" e "Aggiungi un messaggio (facoltativo)" si aggiornano.

- [ ] **Step 2:** `flutter test test/features/recommendations` → FAIL.
- [ ] **Step 3:** implementa; cambia gli arb; `flutter gen-l10n`.
- [ ] **Step 4:** `flutter test test/features/recommendations test/features/tv_pages_test.dart` → PASS.
- [ ] **Step 5: Commit** `feat(app): Consiglia con la griglia degli amici e il pulsante che conta`

### Task 8: Una forma sola per le carte d'invito

**Files:**
- Modify: `app/lib/features/watch_party/invite_card_frame.dart`, `app/lib/features/watch_party/watch_party_invites.dart`, `app/lib/features/match/match_invites.dart`, `app/lib/features/friends/friend_request_card.dart`, `app/lib/features/friends/friend_request_notices.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Test: `app/test/features/watch_party/watch_party_invite_card_test.dart`, `watch_party_invites_test.dart:221`, `app/test/features/match/match_invites_test.dart:53`, `app/test/features/friends/friend_request_notices_test.dart:39`, `app/test/features/watch_party/invite_card_frame_test.dart` (nuovo)

**Interfaces:**
- Consumes: `SenderAvatar` (Task 2), `boldSpans`, `listedGroup` (Task 1), `notifInviteTitle`/`notifMatchInviteTitle`/`partyMembers` (Task 4), `inboxControllerProvider` (per la locandina), `WfMotion.of(context).isReduced`.
- Produces:
  - `const inviteCardShowFor = Duration(seconds: 10);` (sostituisce i tre `showFor` di `WatchPartyInvites`, `MatchInvites`, `FriendRequestNotices`).
  - `enum InviteKind { party, match, friend }` e `newestInviteProvider` (`NotifierProvider<NewestInvite, InviteKind?>` con `void set(InviteKind kind)`): i tre notifier lo chiamano quando mostrano una carta.
  - `class InviteCardFrame extends StatefulWidget { const InviteCardFrame({super.key, required Widget leading, required InlineSpan sentence, String? detail, required String primaryLabel, required IconData primaryIcon, required VoidCallback onPrimary, required String secondaryLabel, required IconData secondaryIcon, required VoidCallback onSecondary, required bool newest, required VoidCallback onTimeout}); }`
    - Riga: `leading` (avatar 40), poi `Text.rich(sentence)` (w500, max 3 righe) e `detail` sotto (`creamMuted` 12,5, cifre tabellari); sotto, allineate al testo, le due azioni in un `Wrap`: con `newest` `WfButton.primary` + `WfButton.secondary`, senza `newest` due `WfButton.secondary`. Nessuna ✕.
    - In fondo una barretta oro alta 3 (chiave `invite-countdown`) che si accorcia in `inviteCardShowFor`; a fine corsa `onTimeout`. Si ferma col puntatore sopra la carta (`MouseRegion`) o col focus dentro (`Focus(canRequestFocus: false, skipTraversal: true, onFocusChange:)`) e riparte da dove era. Con `WfMotion.of(context).isReduced` niente barretta e niente chiusura da sola.
    - Larga 340, nello stretto a tutta larghezza (come oggi).
  - `InviteCardSlot` resta; `FriendRequestCard` lo usa al posto del suo `AnimatedSwitcher`.
- Arb (it / en): `inviteLater` "Più tardi" / "Later". Si tolgono `partyInviteTitle` e, se resta senza uso, `watchPartyDismiss`.

Le tre carte (spec §7.4):

| Carta | Leading | Frase (grassetto) | Sotto | Azioni |
|---|---|---|---|---|
| Party, invito | `SenderAvatar(invitedBy, poster: imageItemId dell'`InviteEntry` con lo stesso `groupId` nella cassetta, se c'è)`; senza locandina `badge: LucideIcons.users` | `notifInviteTitle(invitedBy, names.title)` (nome, titolo) | `partyMembers(n)` se `listedGroup` ha membri | "Unisciti" (play) / "Più tardi" (clock) |
| Party appena nato | `SenderAvatar(names.host, badge: users)` | `watchPartyInviteTitle(host)` (host) | `names.title` | come sopra |
| Match | `SenderAvatar(fromName, badge: heartHandshake)` | `notifMatchInviteTitle(fromName)` (nome) | — | "Unisciti" / "Più tardi" |
| Amicizia | `SenderAvatar(fromName, userId: fromUserId, badge: userPlus)` | `friendRequestTitle(fromName)` (nome) | — | "Accetta" (userCheck) / "Rifiuta" (userX) |

- "Più tardi" e `onTimeout` chiamano `dismiss()` del notifier: la voce resta nella cassetta (nessuna chiamata a `removeInboxEntry`).
- I notifier perdono `_timer` e il `Timer(showFor, dismiss)`; restano le regole di oggi (player, sala, party, accettata altrove). Un'amicizia mostrata con movimento ridotto si chiude comunque quando si apre il pannello Amici (`ref.listen(shellPanelProvider, …)` in `FriendRequestNotices`: con `ShellPanel.friends` → `dismiss()`).

- [ ] **Step 1: Test che falliscono** (`invite_card_frame_test.dart`, `pumpApp(..., motion: MotionLevel.full)`)

```dart
testWidgets('si chiude da sola dopo 10 s', (t) async {
  // InviteCardFrame(..., onTimeout: () => timedOut++) → pump(Duration(seconds: 9)) → timedOut 0;
  // pump(Duration(seconds: 1)) → timedOut 1
});
testWidgets('il puntatore sopra la ferma; via, riparte da dove era', (t) async {
  // pump 9 s; gesture mouse dentro la carta; pump 20 s → timedOut 0;
  // gesture fuori; pump 900 ms → timedOut 0; pump 200 ms → timedOut 1
});
testWidgets('col focus dentro si ferma', (t) async { /* focus su 'Unisciti' → pump 20 s → timedOut 0 */ });
testWidgets('movimento ridotto: niente barretta, non si chiude', (t) async {
  // motion: MotionLevel.reduced → find.byKey(Key('invite-countdown')) findsNothing; pump 30 s → timedOut 0
});
testWidgets('solo la più nuova ha il primario oro', (t) async {
  // newest: false → find.byWidgetPredicate((w) => w is WfButton && w.primary) findsNothing; newest: true → findsOneWidget
});
```

In `watch_party_invite_card_test.dart`:

```dart
testWidgets('invito di un amico: frase unica, locandina dalla cassetta, 2 nel party', (t) async {
  // invito invitedBy 'Luigi', gruppo 'Davide · Dune' (g1) con 2 membri nell'elenco,
  // cassetta con testInvite(groupId: 'g1') (imageItemId 'm1') →
  // find.text('Luigi ti invita a guardare Dune', findRichText: true) findsOneWidget;
  // find.text('2 nel party') findsOneWidget; find.byKey(Key('sender-poster')) findsOneWidget;
  // 'Unisciti' e 'Più tardi'; tap 'Più tardi' → carta via, api.calls senza 'remove-entry'
});
```

E per Match e amicizia: "Luigi ti invita a un Match" con "Unisciti"/"Più tardi"; "Luigi vuole essere tuo amico" con "Accetta"/"Rifiuta" e nessuna ✕ (`find.byTooltip('Chiudi')` findsNothing). Nei tre test dei notifier la riga `async.elapse(X.showFor); expect(..., isNull)` diventa: dopo `inviteCardShowFor` lo stato c'è ancora; `dismiss()` lo toglie. In `friend_request_notices_test.dart` in più: aprire `ShellPanel.friends` toglie la carta.

- [ ] **Step 2:** `flutter test test/features/watch_party test/features/match test/features/friends` → FAIL sui casi nuovi.
- [ ] **Step 3:** implementa `InviteCardFrame`, `newestInviteProvider`, le tre carte; togli i timer dai notifier; cambia gli arb; `flutter gen-l10n`.
- [ ] **Step 4:** stesso comando → PASS; `flutter test test/app` (la shell monta le carte) → PASS.
- [ ] **Step 5: Commit** `feat(app): carte d'invito con una forma sola, Più tardi e i 10 secondi`

### Task 9: Checklist e verifica completa

**Files:**
- Modify: `docs/RELEASING.md` (checklist della 0.42.0, dopo la riga "Stasera e Match nuovi")

- [ ] **Step 1:** aggiungi la riga:
  `- [ ] Revisione finale, fase 5 (app 0.42.0; da admin su PC, poi finestra sotto 1024 px): Notifiche per giorno con avatar e locandina, ✕ sempre visibile, "Per te · Server" e "Svuota tutto? Sì, svuota" che toglie solo la vista scelta, un invito con "2 nel party" e la riga che entra; Amici con "N online", Da rispondere / Online / Offline / Richieste inviate, ⋯ "Invita a un Match", piede con Ho un codice e Apri un Match, ricerca con la rotellina; Consiglia con la griglia, "Scegli gli online" e "Invia a N amici"; carte d'invito con Più tardi e la barretta che si ferma col mouse; toast "X ti invita a guardare Y"; TV: Consiglia col telecomando.`
- [ ] **Step 2: Verifica completa:** `flutter gen-l10n`, `flutter analyze` (nessun problema nuovo; nessuna chiave arb rimasta senza uso tra quelle toccate: `grep -rn` delle chiavi tolte in `lib/` e `test/` non trova niente), `flutter test` (tutti verdi; i flaky noti si rilanciano una volta).
- [ ] **Step 3: Commit** `docs: checklist della fase 5 della revisione finale`

## Prova a mano (dopo la review finale)

Plugin invariato. Release build e avvio dal worktree (`flutter build windows --release --dart-define-from-file=config/wonderflix.json`, poi `Start-Process build\windows\x64\runner\Release\wonderflix.exe`), da admin:
- Notifiche: gruppi Oggi/Ieri/…, avatar con la locandina, ✕ al 40% che si accende col mouse; "Server" con richieste e avvisi; "Svuota tutto" in Server e "Per te" che resta.
- Da un secondo account (web o un altro PC): un invito al party (carta con "Più tardi", barretta che si ferma col mouse, toast di Windows con la frase nuova, riga con "N nel party"), un invito al Match, una richiesta di amicizia, un consiglio.
- Amici: sezioni, ⋯ → "Invita a un Match" (la sala si apre, l'altro riceve l'invito), ricerca di un nome.
- Consiglia dalla scheda: griglia, "Scegli gli online", messaggio lungo (contatore a 180), "Invia a N amici".
- Finestra sotto 1024 px: `/inbox`, `/friends`, `/recommend` con la sola ←.
- APK sulla Fire Stick (comando in CLAUDE.md): Consiglia dalla scheda col telecomando, Giù dalla griglia fino a "Invia" senza tastiera; una carta d'invito col focus sopra non si chiude.

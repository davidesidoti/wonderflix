# Amministrazione "Cabina di proiezione": piano di implementazione

> **Per chi esegue:** SUB-SKILL OBBLIGATORIA: superpowers:subagent-driven-development (scelto dal progetto, `CLAUDE.md`). I passi usano le caselle (`- [ ]`).

**Obiettivo:** ridisegnare la pagina Amministrazione e la ricerca manuale dei download nello stile "Cabina di proiezione", senza cambiare dati, azioni né plugin.

**Architettura:** un piccolo kit condiviso (`admin_kit.dart`: spia, titoli, elenco, barra a fotogrammi) usato da tutte le schede; la pagina passa da titolo + schede orizzontali a colonna sinistra (largo) o fila orizzontale (stretto) con il blocco del server in cima; un controller dei contatori a 60 s. Poi ogni scheda e la ricerca vengono rifatte una per task, riusando il kit.

**Tech stack:** Flutter 3.47.5, flutter_riverpod 3.x, lucide_icons_flutter, test di widget con `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-12-admin-cabina-design.md` (bozze in `docs/superpowers/specs/2026-11-12-admin-cabina-bozze/`). Leggere la spec della sezione del proprio task prima di iniziare: qui ci sono le decisioni, lì le misure e i comportamenti.

## Vincoli globali

- Lavorare nel worktree `C:\Users\sidot\Documents\Github\wonderflix\.claude\worktrees\admin-cabina` (branch `feat/admin-cabina`), comandi da `app/`. In Git Bash prima: `export PATH="/c/Users/sidot/dev/flutter/bin:$HOME/.cargo/bin:$PATH"`. Copiare `app/config/wonderflix.json` dalla checkout principale se manca.
- Nessuna modifica al plugin (`plugin/`) e nessun campo nuovo nei DTO.
- Colori solo da `WfColors` (`app/lib/app/theme.dart`); unica eccezione le cinque sfumature d'oro della barra dello spazio (Task 9). Titoli e numeri grandi `WfText.display(size)`, il resto Inter.
- Largo/stretto: `FormFactor.of(context).compact` (< 1024 px). La TV non mostra Amministrazione: niente lavoro TV, ma i widget condivisi con la TV (`download_rows.dart`, `downloads_tab.dart`) non devono cambiare comportamento con `FormFactor.of(context).tv`.
- Testi: chiavi nuove in `app/l10n/app_it.arb` **e** `app_en.arb`, poi `flutter gen-l10n`. Testi esistenti invariati salvo `adminSessionsIdle`.
- Chiavi dei test esistenti da conservare: `admin-tab-<nome>`, `pending-restart`, `session-paused-<id>`, `activity-severity-<id>-<severity>`, `announcement-text`, `user-<id>`.
- Animazioni: l'unica non richiesta è la pellicola della ricerca in corso (Task 12), ferma se le animazioni sono disattivate (`core/system/animation_preference.dart`).
- Ogni task: `flutter analyze` pulito e `flutter test` verde prima del commit. Non formattare file interi con `dart format` (solo le righe toccate).
- Commit in italiano, senza `Co-Authored-By`, senza le parole `closes`/`fixes`/`resolves`. Messaggio con `git commit -F <file>` (file senza BOM).
- Mai chiudere processi per nome immagine (`taskkill /IM`, `pkill`); solo per PID.
- `app/windows/flutter/generated_plugin*` riscritti dai comandi Flutter con soli fine riga: `git checkout --` prima del commit.

## Da tenere d'occhio in review

1. **Server che non risponde**: con `serverInfoControllerProvider` in errore, il blocco del server mostra errore + "Riprova" e Riavvia resta raggiungibile, sia nel largo sia nello stretto, anche con la scheda in errore. Test nel Task 3.
2. **Plugin vecchio o funzioni spente**: con `socialAvailability` senza `downloads`/`account`/`inbox`, le voci spariscono dalla colonna e i contatori relativi non leggono niente (nessuna chiamata a `downloadsApi`). Test nel Task 2 e nel Task 3.
3. **Durata sconosciuta o zero** in una sala: barra a fotogrammi vuota, solo il tempo, nessuna divisione per zero. Test nel Task 4.
4. **Utenti senza la scheda Utenti** (funzione `account` spenta, `inbox` accesa): il recupero password resta nella scheda WonderFlix. Test nel Task 5.
5. **Righello con dati degeneri**: un'unica release valida, tutte con lo stesso peso o lo stesso punteggio, stagione senza pack interi, file attuale assente. Niente eccezioni né NaN; il righello sparisce sotto le 2 release mostrabili. Test nel Task 11.

---

### Task 1: Il kit condiviso

**File:**
- Create: `app/lib/features/admin/admin_kit.dart`
- Modify: `app/lib/features/admin/admin_widgets.dart` (`AdminSectionTitle` si sposta nel kit con il nuovo aspetto; `admin_widgets.dart` lo riesporta o i chiamanti cambiano import)
- Test: `app/test/features/admin/admin_kit_test.dart`

**Interfacce prodotte:**
```dart
enum LampState { ok, attention, broken, off }
class WfLamp extends StatelessWidget {
  const WfLamp({super.key, required this.state, required this.label, this.size = 9});
  // pallino + alone (BoxShadow dello stesso colore, nessuno per off); Semantics(label: label)
}
Color lampColor(LampState s); // ok→WfColors.online, attention→gold, broken→error, off→Color(0xFF444444)
class AdminTabTitle extends StatelessWidget {
  const AdminTabTitle({super.key, required this.title, this.count, this.actions = const []});
  // WfText.display(30); count in Inter 13 creamMuted accanto; actions a destra (Wrap nello stretto)
}
class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle({super.key, required this.title, this.count, this.note, this.action});
  // WfText.display(20); count/note in Inter 12 creamMuted; action allineata a destra. Padding top 24 bottom 10.
}
class AdminList extends StatelessWidget {
  const AdminList({super.key, required this.children});
  // un contenitore (border, raggio 6), separatori di 1 px WfColors.border tra i figli
}
class FilmStripBar extends StatelessWidget {
  const FilmStripBar({super.key, required this.progress, this.segments = 12, this.height = 6});
  // progress null → tutti vuoti; pieni = (progress.clamp(0,1) * segments).floor(); gap 3
}
```

- [ ] **Passo 1: test che falliscono** in `admin_kit_test.dart`:
  - `lampColor` per i quattro stati restituisce `online`, `gold`, `error`, `Color(0xFF444444)`.
  - `WfLamp(state: LampState.ok, label: 'Sonarr')` ha `Semantics` con label `'Sonarr'`; con `off` nessun `BoxShadow`.
  - `FilmStripBar(progress: 0.46)` → 5 segmenti pieni su 12 (contare i `Container` con colore `gold` tramite una chiave `film-strip-filled`); `progress: null` → 0; `progress: 1.5` → 12; `progress: -1` → 0.
  - `AdminSectionTitle(title: 'In riproduzione', count: 2)` mostra `'In riproduzione'` e `'2'`.
- [ ] **Passo 2:** `flutter test test/features/admin/admin_kit_test.dart` → FAIL (file mancante).
- [ ] **Passo 3:** implementare `admin_kit.dart` con le interfacce sopra; aggiornare gli import di `AdminSectionTitle` (era in `admin_widgets.dart`: grep sui chiamanti).
- [ ] **Passo 4:** test del kit verdi e `flutter test test/features/admin` verde (i test che cercano lo stile vecchio dei titoli, se ce ne sono, si aggiornano qui).
- [ ] **Passo 5:** commit `feat(app): kit della pagina Amministrazione (spia, titoli, elenco, pellicola)`.

---

### Task 2: I contatori

**File:**
- Create: `app/lib/features/admin/admin_counts.dart`
- Test: `app/test/features/admin/admin_counts_test.dart`

**Interfacce:**
- Consuma: `AdminTabController<T>` (`admin_tab_controller.dart`: `interval`, `fetch()`, `state.value`), `adminApiProvider` (`sessions()`, `tasks()`), `downloadsApiProvider.overview()`, `socialAvailabilityProvider` (`downloads`), `adminReportsProvider`, `sessionsControllerProvider`, `maintenanceControllerProvider`, `downloadsControllerProvider`.
- Produce:
```dart
class AdminCounts { const AdminCounts({this.playing, this.running, this.needsYou}); final int? playing, running, needsYou; }
class AdminCountsController extends AdminTabController<AdminCounts> { static const every = Duration(seconds: 60); }
final adminCountsProvider = NotifierProvider.autoDispose<AdminCountsController, AdminData<AdminCounts>>(...);
/// Il numero sul pallino di [tab], null = nessun pallino (anche 0 → null).
int? adminTabCount(WidgetRef ref, AdminTab tab, {required AdminTab current});
```

Regole:
- `fetch` legge in parallelo: sessioni (conta `nowPlaying != null`), attività (conta `state != TaskState.idle`), panoramica download solo se `socialAvailability.downloads` (conta `waiting` con `state == DownloadState.needsYou`, come `downloads_tab.dart:298`, senza filtro). Ogni lettura che fallisce dà il valore precedente di quel campo (`state.value?.x`), non fa fallire le altre.
- `adminTabCount`: per la scheda `current` usa il controller della scheda (`sessionsControllerProvider`, `maintenanceControllerProvider`, `downloadsControllerProvider`), che è già vivo; per le altre `adminCountsProvider`. WonderFlix conta sempre `adminReportsProvider.value?.length` (si aggiorna già da sé con gli eventi). Utenti, Registro e Spazio: sempre null. 0 → null.

- [ ] **Passo 1: test che falliscono** (con override di `adminApiProvider`/`downloadsApiProvider` con fake, come in `sessions_controller_test.dart` e `downloads_controller_test.dart`):
  - `counts are read every 60 s`: `AdminCountsController.every == Duration(seconds: 60)`.
  - `counts playing sessions, running tasks and needsYou items`: 2 sessioni con `nowPlaying`, 1 senza; 1 attività `running`, 1 `cancelling`, 1 `idle`; 3 elementi `needsYou` e 1 `waiting` → `AdminCounts(playing: 2, running: 2, needsYou: 3)`.
  - `downloads not enabled → no overview call`: con `downloads: false` il fake di `overview()` non viene chiamato e `needsYou` è null.
  - `a failed read keeps the previous value`: seconda lettura con `tasks()` che lancia → `running` resta quello della prima, `playing` si aggiorna.
- [ ] **Passo 2:** `flutter test test/features/admin/admin_counts_test.dart` → FAIL.
- [ ] **Passo 3:** implementare `admin_counts.dart`.
- [ ] **Passo 4:** test verdi.
- [ ] **Passo 5:** commit `feat(app): contatori delle schede di Amministrazione`.

---

### Task 3: Colonna, fila e blocco del server

**File:**
- Create: `app/lib/features/admin/admin_rail.dart`
- Modify: `app/lib/features/admin/server_strip.dart` (diventa il blocco del server, due aspetti), `app/lib/features/admin/admin_screen.dart`, `app/lib/features/admin/admin_navigation.dart` (icone)
- Test: `app/test/features/admin/admin_rail_test.dart`, aggiornare `admin_screen_test.dart`, `server_strip_test.dart`, `test/features/compact_screens_test.dart`

**Interfacce:**
- Consuma: `WfLamp`, `adminTabCount` (Task 1–2), `adminTabs`, `adminTabLabel`, `openAdmin`.
- Produce:
```dart
IconData adminTabIcon(AdminTab tab); // sessions monitorPlay, users users, maintenance wrench, activity scrollText, downloads download, space hardDrive, wonderflix sparkles
class AdminRail extends ConsumerWidget { const AdminRail({super.key, required this.tabs, required this.current}); } // largo
class AdminTabStrip extends ConsumerWidget { const AdminTabStrip({super.key, required this.tabs, required this.current}); } // stretto
class ServerStrip extends ConsumerWidget { const ServerStrip({super.key, this.vertical = false}); } // vertical: aspetto della colonna
```

Comportamento (spec "Struttura della pagina"):
- Largo: `Row(AdminRail(width 208), Expanded(contenuto))`. In cima alla colonna `ServerStrip(vertical: true)`, sotto le voci. Niente più titolo "AMMINISTRAZIONE": ogni scheda mette il suo `AdminTabTitle` (Task 4–10; finché un task non lo fa, va bene che manchi).
- Stretto: `header` passato alle schede = `Column(ServerStrip(), AdminTabStrip(...))`, così entrambi scorrono con la scheda come oggi; la pagina non ha altro sopra.
- Voce: `InkWell` con chiave `ValueKey('admin-tab-${tab.name}')`, icona 16, nome, pallino oro con il numero se `adminTabCount != null`. Selezionata: fondo `surfaceHigh` + barretta oro 2 px a sinistra (largo) o sotto (stretto). Focus da tastiera visibile (bordo oro 2 px come `tvFocusSide`). `Semantics(selected: …)`.
- `ServerStrip`: spia `ok` se `info != null && !hasPendingRestart`, `attention` con riavvio necessario, `broken` con errore e nessun dato, scheletro durante il primo caricamento. Restano: testo e chiave `pending-restart`, `RestartArea` con tutte le fasi, `AdminStaleNote`, "Riprova". Il nome del server in `WfText.display(24)`. `vertical: true` impila spia+nome, versione/OS, `RestartArea`, riavvio necessario.
- La pagina tiene vivi `restartControllerProvider` e `serverInfoControllerProvider` come oggi, e anche `adminCountsProvider` (`ref.listen`).

- [ ] **Passo 1: test che falliscono** in `admin_rail_test.dart` e negli esistenti:
  - largo (1440×900): `find.byType(AdminRail)` trovato, `find.text('AMMINISTRAZIONE')` assente, le sette chiavi `admin-tab-*` presenti con tutte le funzioni accese; con `downloads: false` manca `admin-tab-downloads`.
  - stretto (390×844): `AdminTabStrip` trovato, `AdminRail` assente; scorrendo la scheda il blocco del server esce dalla vista insieme alla fila.
  - contatore: con `adminTabCount` che dà 2 per Sessioni il testo `'2'` sta dentro la voce `admin-tab-sessions`; con 0 nessun pallino.
  - server in errore: con `serverInfoControllerProvider` in errore, `'Riprova'` e `'Riavvia'` visibili nel largo e nello stretto, anche con la scheda in errore (Da tenere d'occhio 1).
  - `pending-restart` presente con `hasPendingRestart` e la spia in `LampState.attention`.
- [ ] **Passo 2:** `flutter test test/features/admin` → i nuovi falliscono.
- [ ] **Passo 3:** implementare `admin_rail.dart`, rifare `ServerStrip`, ristrutturare `AdminScreen.build`; aggiornare gli assert su `'AMMINISTRAZIONE'` e su `WfTabButton` negli altri test (incluso `compact_screens_test.dart`). `WfTabButton` resta (lo usa altro codice): non toglierlo.
- [ ] **Passo 4:** `flutter test` tutto verde.
- [ ] **Passo 5:** commit `feat(app): colonna delle schede e blocco del server in Amministrazione`.

---

### Task 4: Sessioni, le sale

**File:**
- Modify: `app/lib/features/admin/sessions_tab.dart`, `app/l10n/app_it.arb`, `app/l10n/app_en.arb`
- Test: `app/test/features/admin/sessions_tab_test.dart`

**Interfacce:** consuma `AdminTabTitle`, `AdminSectionTitle`, `FilmStripBar`, `AdminUserLine`, `imageUrlsProvider` (`backdropOf(itemId, maxWidth:)`, `primaryOf`).

Decisioni:
- Testi: `adminSessionsSala` = "Sala {n}" / "Screen {n}" (`n` int); `adminSessionsIdle` diventa "In sala d'attesa" / "Waiting room".
- `PlayingSessionCard` (stesso nome, per i test) prende `required int number`. Riquadro alto 170, `ClipRRect` raggio 6, bordo `border`. Sfondo: `WfImage(image: backdropOf(item.seriesId ?? item.itemId, maxWidth: 960))`, sotto un velo `LinearGradient` dal basso (`bg` 0.95 al 25%, 0.2 in alto). Se l'immagine non c'è, `WfImage` mostra già il suo ripiego: basta un fondo `surfaceHigh` dietro.
- In alto a sinistra "Sala N" `WfText.display(15, color: gold)`; in alto a destra l'etichetta del metodo (`displayMethodLabel`): transcodifica oro su `gold` 18% alfa, altrimenti crema su `cream` 10%; icona pausa con la chiave `session-paused-<id>` accanto all'etichetta.
- In basso: titolo `WfText.display(26)` (max 1 riga), `AdminUserLine`, `FilmStripBar(progress: runtime == null ? null : progress)`, tempo, righe di transcodifica di oggi.
- Griglia: largo due per riga (`Wrap` o `GridView` non scrollabile con larghezza `(w - 14) / 2`), stretto una.
- "In sala d'attesa": `Wrap(spacing: 22, runSpacing: 8)` di `IdleSessionRow` compatte.
- Titolo scheda `AdminTabTitle(title: l.adminTabSessions)`; sezioni con `count`.

- [ ] **Passo 1: test che falliscono** in `sessions_tab_test.dart`:
  - due sessioni in riproduzione → `'Sala 1'` e `'Sala 2'` nell'ordine dello snapshot.
  - sessione con `runtime: Duration.zero` → `FilmStripBar` con 0 segmenti pieni, tempo senza " / " (Da tenere d'occhio 3).
  - transcodifica → etichetta del metodo e riga di transcodifica presenti; `session-paused-<id>` presente con `isPaused`.
  - titolo della sezione `'In sala d'attesa'`.
- [ ] **Passo 2:** test → FAIL.
- [ ] **Passo 3:** testi in arb, `flutter gen-l10n`, implementazione.
- [ ] **Passo 4:** `flutter test` verde.
- [ ] **Passo 5:** commit `feat(app): le sale in Sessioni`.

---

### Task 5: Utenti, tessere e recupero password

**File:**
- Modify: `app/lib/features/admin/users_tab.dart`, `app/lib/features/admin/account_recovery_card.dart`, `app/lib/features/admin/wonderflix_tab.dart`, arb
- Test: `users_tab_test.dart`, `account_recovery_card_test.dart`, `wonderflix_tab_test.dart`

**Interfacce:**
- Consuma: `WfLamp`, `AdminTabTitle`, `accountAdminControllerProvider` (`AccountAdminStatus.discord/email`: `configured`, `lastError`).
- Produce: `class AccountRecoveryBand extends ConsumerStatefulWidget` in `account_recovery_card.dart`: fascia con "Recupero password", `WfLamp` per Discord e per email (`ok` configurato, `off` no, `broken` con `lastError`), "Invia prova a me" con esito; cliccando la fascia (o un'icona chevron) si apre sotto il dettaglio di oggi (contenuto attuale di `AccountRecoveryCard` senza il titolo). La logica della prova e del keep-alive si riusa, non si duplica: estrarre il corpo in un widget privato condiviso dai due.

Decisioni:
- `UsersTab`: `AdminTabTitle(title: l.adminTabUsers, count: users.length)`, poi `AccountRecoveryBand`, poi le tessere: largo due per riga, stretto una. Tessera: fondo `surface`, bordo `border`, raggio 6, avatar 40, nome, etichette Admin (oro su oro 18%) / Disattivato (crema 8%, tessera con opacità 0.55), due caselline 20×20 (Discord "D"/icona, email "@"/icona): piene `cream` 12% se collegate, bordo tratteggiato o `border` se no, con `Tooltip` col testo di oggi (`adminUsersDiscordLinked`/`None`, `adminUsersEmailLinked`/`None`). Menu "⋯" di oggi.
- "nessun contatto" (testo nuovo `adminUsersNoContact` = "nessun contatto" / "no contact"), oro, solo se `!isAdmin && enabled && !hasContacts`.
- `WonderflixTab` mostra `AccountRecoveryCard` solo se `!socialAvailability.account` (con `account` acceso il recupero sta in Utenti).

- [ ] **Passo 1: test che falliscono:**
  - `users_tab_test`: un utente non admin, attivo, senza contatti → `'nessun contatto'`; admin senza contatti → no; disattivato → `Opacity` 0.55 attorno alla tessera; `AccountRecoveryBand` presente.
  - `account_recovery_card_test`: la fascia con Discord configurato ed email no → `WfLamp` `ok` con label contenente "Discord" e `off` per email; "Invia prova a me" funziona come oggi (riusare i casi esistenti sulla fascia).
  - `wonderflix_tab_test`: con `account: true` nessun `AccountRecoveryCard`; con `account: false, inbox: true` c'è (Da tenere d'occhio 4).
- [ ] **Passo 2:** FAIL.
- [ ] **Passo 3:** implementazione e testo nuovo.
- [ ] **Passo 4:** `flutter test` verde.
- [ ] **Passo 5:** commit `feat(app): tessere degli utenti e recupero password in Utenti`.

---

### Task 6: Manutenzione

**File:** Modify `app/lib/features/admin/maintenance_tab.dart`; Test `maintenance_tab_test.dart`.

**Interfacce:** consuma `AdminTabTitle`, `AdminSectionTitle(action:)`, `AdminList`, `WfLamp`, `LibraryFolder` (`kind`, `refreshing`, `refreshProgress`), `ScheduledTask` (`state`, `progress`, `lastResult`).

Decisioni:
- Librerie: tessere `surface` tre per riga nel largo (una nello stretto): nome `WfText.display(20)`, sotto il tipo (`LibraryKind`: testo esistente se c'è, altrimenti niente per `other`) e "Scansiona"; in scansione bordo `gold` 50%, "Scansione N%" oro e barra. "Scansiona tutte" come `action` del titolo di sezione.
- Attività: `AdminList` di righe con `WfLamp` a sinistra. Stato: `running`/`cancelling` → `attention` (barra + percentuale + "Ferma"/"Arresto…"); ultimo esito `completed` → `ok`; `failed`/`aborted`/`cancelled` → `broken` con il testo in `error`; mai eseguita → `off`. Gruppi per categoria come oggi (titolo del gruppo piccolo, grigio).
- Titolo scheda `AdminTabTitle(title: l.adminTabMaintenance)`.

- [ ] **Passo 1: test che falliscono:** un'attività per stato (in corso, completata, non riuscita, mai eseguita) → `WfLamp` con lo stato atteso (trovare per chiave `task-lamp-<id>`); una libreria in scansione al 64% → `'64%'` dentro la sua tessera.
- [ ] **Passo 2:** FAIL. **Passo 3:** implementazione. **Passo 4:** `flutter test` verde.
- [ ] **Passo 5:** commit `feat(app): Manutenzione con tessere e spie`.

---

### Task 7: Registro

**File:** Modify `app/lib/features/admin/activity_tab.dart`, `app/lib/features/admin/admin_time.dart`; Test `activity_tab_test.dart`, `admin_time_test.dart`.

**Interfacce:**
- Produce in `admin_time.dart`: `String adminDayLabel(DateTime date, DateTime now, AppLocalizations l)` → "Oggi"/"Ieri" (chiavi esistenti se ci sono, sennò nuove `adminToday`/`adminYesterday`), poi la data come le altre etichette di `admin_time.dart`; `String adminHourLabel(DateTime date)` → `HH:mm` locale.
- Produce in `activity_tab.dart`: `Color activityDotColor(ActivityEntry e)` → `error` se `severity` è `warning` o `error`; `gold` se `type` inizia con `VideoPlayback` o `AudioPlayback`; altrimenti `creamMuted`.

Decisioni:
- Filtro Tutto/Utenti/Sistema: `SegmentedButton` (o tre pulsanti a segmento) al posto dei `ChoiceChip`, a destra del titolo, con "Aggiorna".
- Elenco: intestazione di giorno `WfText.display(16, color: gold)` quando cambia `adminDayLabel`; riga = colonna ora `WfText.display(19)` larga 56, punto 8 px `activityDotColor` con la chiave `activity-severity-<id>-<severity>`, testo e "Apri il titolo" come oggi; il tooltip con data completa resta sull'ora. Voci senza data: in fondo al gruppo senza ora.

- [ ] **Passo 1: test che falliscono:** `adminDayLabel` per oggi, ieri, tre giorni fa; `activityDotColor` per `VideoPlayback`/info → gold, `AuthenticationFailed`/warning → error, altro/info → creamMuted; due voci di giorni diversi → due intestazioni.
- [ ] **Passo 2:** FAIL. **Passo 3:** implementazione. **Passo 4:** `flutter test` verde.
- [ ] **Passo 5:** commit `feat(app): il Registro come programma della serata`.

---

### Task 8: Download

**File:** Modify `app/lib/features/downloads/downloads_tab.dart`, `app/lib/features/downloads/download_rows.dart`; Test `downloads_tab_test.dart`.

**Interfacce:** consuma `WfLamp`, `AdminTabTitle`. `_BacklogCard` e `_SectionHeader` restano privati.

Decisioni:
- `AdminTabTitle(title: l.adminTabDownloads)` in cima. `DownloadsTab` si usa solo in Amministrazione (che sulla TV non c'è); i rami `tv` già nel file restano come sono.
- `_BacklogCard`: `WfLamp` a sinistra: `ok` in corsa, `attention` in pausa o in pausa per ricerca manuale, `broken` se `sonarrError`/`radarrError` non null. Testi di oggi.
- "Serve te": in `DownloadItemRow` `accent: needsYou ? WfColors.gold : null` e bordo sinistro di 3 px oro (`RowShell` prende un `bool leftAccent` o simile); `UnknownDownloadRow` resta `error`. L'azione primaria è già piena (`primary: i == 0 && needsYou`).
- `_SectionHeader`: titolo in `WfText.display(20)` con il conteggio in Inter piccolo, senza cambiare il comportamento apri/chiudi né le chiavi.

- [ ] **Passo 1: test che falliscono:** riga `needsYou` → `RowShell` con `accent == WfColors.gold`; backlog con `sonarrError` → `WfLamp` `broken`; il testo esistente `'Scelte automatiche · 0'` (o il suo equivalente nuovo) aggiornato nel test di `admin_screen_test`.
- [ ] **Passo 2:** FAIL. **Passo 3:** implementazione. **Passo 4:** `flutter test` verde (anche i test TV di Download, se ci sono).
- [ ] **Passo 5:** commit `feat(app): Download con la spia delle ricerche e "Serve te" in oro`.

---

### Task 9: Spazio, la barra dello spazio

**File:** Create `app/lib/features/space/space_gauge.dart`; Modify `app/lib/features/space/space_tab.dart`; Test `app/test/features/space/space_gauge_test.dart`, `space_tab_test.dart`.

**Interfacce:**
```dart
const spaceGaugeColors = [Color(0xFFD4A64A), Color(0xFFB9893A), Color(0xFF8C6A33), Color(0xFF5E4A2A), Color(0xFF3E342A)]; // film, serie, anime, solo torrent, altro
class SpaceGauge extends StatelessWidget {
  const SpaceGauge({super.key, required this.parts, this.totalBytes}); // parts: List<(String label, int bytes)>, 5 voci
  // totalBytes null → la barra è la somma delle parti; altrimenti il resto fino al totale è surfaceHigh. Altezza 22, raggio 4. Legenda sotto con quadratini.
}
```

Decisioni:
- `_quotaCard` diventa: riga con `AdminTabTitle(title: l.adminTabSpace, actions: [stato "Calcolato …", Aggiorna, Ricalcola])`; occupato `WfText.display(34)` + `spaceQuotaLine` in grigio; `SpaceGauge`. Senza quota: solo la barra con la somma e la riga d'errore di oggi. Prima del primo calcolo (`scannedAt == null`): niente barra, lo stato di oggi.
- Titoli delle sezioni con `AdminSectionTitle(note: totali, action: …)` dove oggi ci sono `_totals` e i pulsanti di sezione.

- [ ] **Passo 1: test che falliscono:** `SpaceGauge` con parti 440/400/560/160/60 GB e totale 2000 GB → cinque segmenti con flex proporzionali e un resto `surfaceHigh`; tutte le parti a 0 senza totale → nessuna eccezione, barra vuota; `space_tab_test` vede `'1,62 TB'` (o il formato di `spaceTb`) in Bebas.
- [ ] **Passo 2:** FAIL. **Passo 3:** implementazione. **Passo 4:** `flutter test` verde.
- [ ] **Passo 5:** commit `feat(app): la barra dello spazio`.

---

### Task 10: WonderFlix, la fila delle spie

**File:** Modify `app/lib/features/admin/wonderflix_tab.dart`, `app/lib/features/admin/home_admin_cards.dart`, `app/lib/features/admin/wonderflix_controllers.dart`; Test `wonderflix_tab_test.dart`, `home_admin_cards_test.dart`.

**Interfacce:**
- Produce in `wonderflix_controllers.dart`:
```dart
class TestResultNotifier<T> extends Notifier<T?> {
  @override
  T? build() => null;
  void set(T? value) => state = value;
}
final arrTestResultProvider = NotifierProvider.autoDispose<TestResultNotifier<ArrTestResults>, ArrTestResults?>(TestResultNotifier.new);
final seerrTestResultProvider = NotifierProvider.autoDispose<TestResultNotifier<SeerrTestResult>, SeerrTestResult?>(TestResultNotifier.new);
```
  La pagina Amministrazione li tiene vivi con `ref.listen` (come gli altri provider della pagina), così l'esito non si perde chiudendo la card.
  `ArrCard` e `SeerrCard` scrivono lì l'esito della prova invece che in `_result` (il keep-alive basato su `_result` diventa inutile: toglierlo).
- Produce: `class IntegrationLamps extends ConsumerWidget` (fila): Sonarr, Radarr (da `socialAvailability.upcomingSeries/upcomingMovies` + `arrTestResultProvider`), Seerr (da `seerrAdminControllerProvider` + `seerrTestResultProvider`; errore di lettura → `broken`), e, solo se `AccountRecoveryCard` è in questa scheda (Task 5), Discord ed email. Regola: non configurato → `off`; configurato senza prova → `ok`; prova riuscita → `ok`; prova fallita → `broken` con il testo breve di oggi (`arrResultText`, `seerrResultText` o equivalenti già nel file) in `error`.

Decisioni:
- Cliccando una spia si apre sotto la fila la card di oggi di quell'integrazione (`ArrCard` per Sonarr e Radarr, `SeerrCard`, `AccountRecoveryCard`); un secondo clic la chiude; una sola aperta alla volta. Stato locale del tab.
- Sotto: card su due colonne nel largo, una nello stretto, in quest'ordine: `ReportsCard` (titolo con "N aperte" in oro), `AnnouncementCard`, `NewTitlesCard` (numero in attesa `WfText.display(26)`), `RatingCommentsCard`, `HomeForEveryoneCard`. Sopra tutto `AdminTabTitle(title: l.adminTabWonderflix)`.
- `AdminCard`: stesso aspetto piatto, raggio 6, titolo Inter 14 w600; resta usato da Spazio e dalle card.

- [ ] **Passo 1: test che falliscono:** Seerr non configurato → spia `off`; Seerr con lettura in errore → `broken`; dopo "Prova collegamento" fallita in `SeerrCard` la spia diventa `broken` (stesso provider); tap sulla spia Sonarr → compare `ArrCard`, secondo tap → sparisce; ordine delle card (Segnalazioni prima di Annuncio).
- [ ] **Passo 2:** FAIL. **Passo 3:** implementazione. **Passo 4:** `flutter test` verde.
- [ ] **Passo 5:** commit `feat(app): WonderFlix con la fila delle spie`.

---

### Task 11: Ricerca manuale, testa, righello e tabella

**File:**
- Create: `app/lib/features/downloads/weight_ruler.dart`
- Modify: `app/lib/features/downloads/download_search_page.dart`, `app/lib/features/downloads/downloads_tab.dart`, `app/lib/features/space/space_tab.dart`, `app/lib/features/space/space_title_dialog.dart`, arb
- Test: `app/test/features/downloads/weight_ruler_test.dart`, `download_search_page_test.dart`

**Interfacce:**
- `showDownloadSearch(BuildContext, String key, String title, {bool reviewing = false, bool lighten = false, ImageRef? image})`. Chiamanti: Download passa `RemoteImages.poster(item.posterUrl!)` quando c'è (`DownloadItem`, `ReviewItem`, `DownloadChoice` hanno `posterUrl`); Spazio passa `ref.read(imageUrlsProvider).backdropOf(itemId)` quando l'elemento ha `itemId`.
- Produce in `weight_ruler.dart`:
```dart
class RulerMark { const RulerMark({required this.sizeBytes, required this.score, this.isChoice = false}); final int sizeBytes, score; final bool isChoice; }
/// Le tacche da mostrare: per le stagioni solo i pack interi (fullSeason != false); [] sotto le 2.
List<RulerMark> rulerMarks(DownloadSearch search);
class WeightRuler extends StatelessWidget { const WeightRuler({super.key, required this.marks, this.currentBytes}); }
/// "Libera {gb}": null senza file attuale, se la scelta non pesa meno, o per una stagione se la scelta non è un pack intero.
int? freedBytes(DownloadSearch search);
/// GB/ora: solo film con runtimeMinutes > 0, altrimenti null.
double? gbPerHour(DownloadSearch search, int sizeBytes);
```
- Testi nuovi: `downloadsWeightsTitle` "Pesi a confronto" / "Sizes compared"; `downloadsWeightsHint` "ogni tacca è una release; più alta, punteggio più alto" / "each mark is a release; taller means a higher score"; `downloadsRulerChoice` "scelta {gb}" / "pick {gb}"; `downloadsRulerCurrent` "attuale {gb}" / "current {gb}"; `downloadsFrees` "Libera {gb}" / "Frees {gb}"; `downloadsRuleChoiceTitle` "La scelta della regola" / "The rule's pick"; `downloadsAllReleases` "Tutte le release" / "All releases"; `downloadsShow` "Mostra" / "Show" (se non esiste una chiave adatta).

Regole del righello (spec "Pesi a confronto"): asse da 0 a `max(peso delle tacche, currentBytes)`, 5 etichette in GB (3 nello stretto); x = peso / max; altezza = 14 + 50 × (score − min) / (max − min), con `max == min` → altezza piena (64); tacca della scelta oro larga 5 sopra le altre, file attuale crema; `CustomPainter` o `Stack` di `Positioned`. Niente zona "troppo piccoli". Altezza totale 96.

Pagina (spec "La ricerca manuale"):
- Testa alta 190 (stretto 150): `WfImage(image)` sfocato (`ImageFiltered` sigma 12 per i poster, niente sfocatura per i backdrop: decidere dal chiamante con un `bool blur` interno o dal tipo di immagine) + velo; senza immagine `surfaceHigh`. "← Download" (chiude la pagina), titolo `WfText.display(44)` (stretto 32), riga meta di oggi; "scheda tecnica" del file attuale (peso `WfText.display(26)`, punteggio e qualità, GB/ora se `gbPerHour != null`), sotto nello stretto.
- Riga azioni: le stesse di `_Header` di oggi con le stesse condizioni, MIRCrew allineato a destra.
- `WeightRuler` se `rulerMarks(search).length >= 2`.
- Blocco della scelta: il candidato `isChoice && !(lighten && isCurrentFile)` fuori dalla tabella, fondo `calendarMovie`, bordo oro: rango `WfText.display(30, color: gold)`, release, punteggio, peso (+ GB/ora), seeders con spia, indexer, `choiceWhy` + `downloadsFrees` se `freedBytes != null`, "Scarica" pieno. Stesso `onGrab` e conferme di `_CandidateRow`.
- Tabella: `_CandidateRow` con rango in `WfText.display(18, color: creamMuted)`, punteggio con barretta oro lunga `40 × score / maxScore`, spia dei seeders (`off` per null o 0, `attention` 1–9, `ok` ≥ 10) in un helper `LampState seedersLamp(int? seeders)`; riga del file attuale come oggi (`isCurrent: lighten && …`), con opacità 0.6.
- Scartati: chiusi; riepilogo per `rejectedLabel` raggruppato (`Map<String,int>` con il conteggio) come pastiglie; "Mostra" apre l'elenco di oggi.

- [ ] **Passo 1: test che falliscono:**
  - `weight_ruler_test`: `rulerMarks` su una stagione con 3 singoli e 2 pack interi → 2 tacche; con 1 pack intero → `[]`; film con una sola release → `[]`; tutte con lo stesso punteggio → nessuna eccezione e altezze uguali; `freedBytes` con file da 78 GB e scelta da 16 GB → 62 GB; stagione con scelta non pack → null; `gbPerHour` per una stagione → null, per un film da 180 min e 16 GB → ≈5,3 (Da tenere d'occhio 5).
  - `download_search_page_test`: la scelta compare una volta sola (fuori dalla tabella); `seedersLamp(0)`/`(5)`/`(412)` → `off`/`attention`/`ok`; senza `lighten` la release uguale al file attuale ha "Scarica"; con `lighten` mostra "È il file che hai già"; gli scartati mostrano le pastiglie e l'elenco solo dopo "Mostra"; `showDownloadSearch` senza immagine non lancia.
- [ ] **Passo 2:** FAIL.
- [ ] **Passo 3:** testi, `flutter gen-l10n`, implementazione, chiamanti.
- [ ] **Passo 4:** `flutter test` verde.
- [ ] **Passo 5:** commit `feat(app): ricerca manuale con testa, righello dei pesi e scelta in evidenza`.

---

### Task 12: Ricerca manuale, migliori episodi e attesa

**File:** Modify `app/lib/features/downloads/download_search_page.dart`; Test `download_search_page_test.dart`.

**Interfacce:** consuma `_CandidateRow` (Task 11), `FilmStripBar`, `WfLamp`, la preferenza animazioni di `core/system/animation_preference.dart` (leggere lì il provider/funzione esistente).

Decisioni:
- `_BestEpisodes`: titolo di sezione con "Scarica tutti (N)"/"Scarico d/t" come `action`; griglia di tessere (`Wrap`, larghezza fissa ~92, sette per riga nel largo): `WfText.display(20)` "E01" (`downloadsEpisodeShort`), sotto il peso o "nessun file valido". Con release: bordo `gold` 50%; senza: bordo tratteggiato/`border` e opacità 0.5. Chiave `episode-tile-<n>`.
- Tap su una tessera con release: selezionata (bordo oro pieno) e sotto la griglia compare `_CandidateRow` di quell'episodio con il suo "Scarica" e le conferme di oggi (`needsConfirm`, `lowersScore`); secondo tap la chiude. Tessere senza release: non cliccabili. Niente filtro della tabella, niente stato "già c'è".
- `_SearchRunning`: riquadro `surface` con `WfLamp(attention)`, testo di oggi ("Ricerca su {servizio} in corso" e varianti), tempo `WfText.display(22)` a destra; sotto una pellicola animata: fila di 28 segmenti con 3 pieni che scorrono (un `AnimationController` ripetuto, 1,2 s per giro), ferma (3 pieni a sinistra) con le animazioni disattivate; sotto il suggerimento. Gli stati attesa/riconnessione/errore restano dentro lo stesso riquadro.

- [ ] **Passo 1: test che falliscono:** 14 episodi di cui 2 senza release → 14 tessere, 2 non cliccabili; tap su `episode-tile-3` → compare la riga con "Scarica" del singolo, secondo tap la toglie; "Scarica tutti (12)"; `_SearchRunning` con animazioni disattivate → nessun ticker attivo (`tester.binding.transientCallbackCount == 0` dopo il pump) — attenzione: con animazioni attive non usare `pumpAndSettle` (non si ferma mai), pompare con durate esplicite.
- [ ] **Passo 2:** FAIL. **Passo 3:** implementazione. **Passo 4:** `flutter test` verde.
- [ ] **Passo 5:** commit `feat(app): migliori episodi a tessere e pellicola dell'attesa`.

---

### Task 13: Verifica finale e build di prova

**File:** Modify `docs/RELEASING.md` (riga della checklist), `app/pubspec.yaml` (versione), nello stesso commit.

- [ ] **Passo 1:** da `app/`: `flutter gen-l10n`, `flutter analyze` (nessun problema), `flutter test` (tutto verde).
- [ ] **Passo 2:** riga nuova in fondo alla "Checklist dei test manuali" di `docs/RELEASING.md`, nello stile delle altre: "Amministrazione Cabina (app 0.41.0, un admin, su PC e su telefono web): colonna delle schede con i contatori (Sessioni, Manutenzione, Download, WonderFlix) e il server in cima con spia e Riavvia; nello stretto fila orizzontale che scorre con la scheda; sale con lo sfondo in Sessioni; tessere in Utenti con il recupero password; spie in Manutenzione, Download e WonderFlix (clic sulla spia apre il dettaglio); Registro per giorni; barra dello spazio; ricerca manuale con testa, righello dei pesi, scelta in evidenza, scartati per motivo, migliori episodi a tessere. Con il server spento il blocco del server dice l'errore e Riavvia resta raggiungibile." Versione `0.41.0` in `app/pubspec.yaml` (se nel frattempo `main` è andato oltre, la successiva libera).
- [ ] **Passo 3:** commit `chore(app): 0.41.0 e checklist della pagina Amministrazione`.
- [ ] **Passo 4:** build di prova: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`; chiudere solo una propria istanza di prova precedente per PID; avviare `build\windows\x64\runner\Release\wonderflix.exe` con `Start-Process`. Nessun deploy di plugin (non cambia).
- [ ] **Passo 5:** chiedere all'utente il test a mano. Merge e push solo dopo il suo ok.

# WonderFlix — Piano 21b: cosa guardano gli amici, app 0.15.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte app dello Spec O:
- il client delle funzioni nuove del plugin 1.9.0 (`NowPlaying` negli amici, posizione, impostazione, riga), la funzione `friendsActivity`, i testi;
- nel pannello Amici "Sta guardando *Dune*" e il tasto **Guarda insieme**;
- l'interruttore "Mostra agli amici cosa guardo" in Impostazioni → Account;
- la riga "Visti dagli amici" nella Home;
- app 0.15.0 **obbligatoria**, provata con l'utente sul plugin 1.9.0 di prova (piano 21a).

**Architecture:**
- Il client sta in `lib/core/social/`: `SocialApi` lancia solo `SocialException`, e `JellyfinHttp` guadagna `put`.
- "Guarda insieme" usa `startWatchParty` (con un invito facoltativo dopo la registrazione) da una funzione nuova, `watchWithFriend`.
- L'interruttore ha il suo provider (`shareActivityProvider`), letto e scritto sul plugin.
- La riga della Home segue la strada di "Consigliati per te": `HomeRowKind`, `homeRowGate`, `homeRowProvider`, `HomeRowContent`, `HomeRowView`.

**Tech Stack:** Flutter 3.47.5 / Dart, flutter_riverpod 3 (Notifier), go_router 18, lucide_icons_flutter, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-13-wonderflix-cosa-guardano-amici-design.md` (§3, §7, §8, §9, §11.2, §13). Il plugin 1.9.0 (piano 21a) è sul server come build di prova.

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 5):
1. **L'invito parte dentro la registrazione del party:** `startWatchParty` riceve `invite` (un id d'amico) e lo invita subito dopo `registerParty`, prima della coda. Un invito che non riesce non ferma il party: l'avviso "Invito non inviato" e il party continua (spec §7.2).
2. **Posizione:** i tick del plugin diventano una `Duration` (`ticks ~/ 10` microsecondi) e vanno in `start:`. Il player parte da lì; l'amico entra quando accetta.
3. **Il tasto "Guarda insieme" non compare** se io sono già in un gruppo SyncPlay, se l'amico è in un party (c'è "Unisciti") o durante "Conferma rimozione".
4. **"Non sta più guardando" (409)** rilegge l'elenco degli amici, così il testo e il tasto spariscono subito.
5. **L'interruttore sta in fondo alla sezione Account**, sotto i pulsanti e prima dei contatti per il recupero; vale per l'account aperto e si rilegge al cambio di profilo.
6. **"Visto da …"** usa una funzione sua (`friendsWatchedBy`) con gli stessi casi di `recommendedFrom` (uno, due, "e altri N"); `recommendedFrom` resta com'è.
7. **La funzione `friendsActivity` vale solo con l'accesso ai watch party** (`_canJoin`), come gli amici: il plugin usa la stessa policy.

## Global Constraints

- App **0.15.0** (`pubspec.yaml`), **obbligatoria** alla release (`<!-- wonderflix:min-version=0.15.0 -->` nelle note, `docs/RELEASING.md` passo 6).
- Plugin 1.9.0:
  - `GET WonderFlixWatchParty/Friends` → ogni voce può avere `NowPlaying {ItemId, Title, SeriesId?, SeriesName?, Season?, Episode?}` (assente se non vale);
  - `GET WonderFlixWatchParty/Friends/{userId}/NowPlaying` → `{ItemId, PositionTicks}`; 409 se non vale (→ `SocialFailure.conflict`);
  - `GET WonderFlixWatchParty/Activity/Settings` → `{ShareActivity}`; `PUT WonderFlixWatchParty/Activity/Settings` `{ShareActivity}` → 204;
  - `GET WonderFlixWatchParty/Activity/FriendsWatched` → `{Items: [{ItemId, By: [{UserId, Name, WatchedAt}]}]}` (al massimo 30, già filtrati e ordinati dal plugin).
- Funzione del plugin in `Info`: `friendsActivity`.
- Id della riga della Home: `friendsWatched`, subito dopo `recommended`.
- "Guarda insieme": party **privato**, senza il menu delle modalità, dalla posizione dell'amico, con l'invito all'amico.
- Testi it/en della spec §9; i testi non danno per scontato il genere di nessuno.
- Icone solo `LucideIcons`, colori `WfColors`; `clock.now()`, mai `DateTime.now()`.

## Review Focus

1. **L'amico smette di guardare tra la lettura dell'elenco e il clic** (409 dalla posizione): l'avviso "Non sta più guardando", nessun party creato, l'elenco riletto. Test: Task 2 (`Guarda insieme quando l'amico ha smesso: avviso e niente party`).
2. **L'invito non parte ma il party sì:** il party resta e compare "Invito non inviato". Test: Task 2 (`invito non riuscito: il party resta e lo dice`).
3. **Doppio clic su Guarda insieme:** una sola richiesta di posizione e un solo party. Test: Task 2 (`Guarda insieme spento mentre parte`).
4. **Salvataggio dell'interruttore che non riesce:** l'interruttore torna com'era e compare "Impostazione non salvata". Test: Task 3 (`salvataggio non riuscito: torna com'era e lo dice`).
5. **Plugin vecchio (senza `friendsActivity`):** niente interruttore, riga non disponibile con il motivo, nessuna chiamata nuova. Test: Task 3 (`senza la funzione: niente interruttore`) e Task 4 (`senza la funzione: riga non disponibile e nessuna chiamata`).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-21b`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(app): …"`.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit** `flutter analyze` senza problemi e la suite intera, tutta verde, con **`flutter test --concurrency=4`**. Con i 16 processi predefiniti il PC si è riavviato due volte il 2026-10-10;
  - la base di partenza è di **2905** test verdi (`main` `2b03b34`, verificato il 2026-10-13 con `--concurrency=4`).
- **File generati:**
  - Se `flutter test`, `analyze`, `pub get` o `build` riscrivono `windows/flutter/generated_plugin*` con soli cambi di fine riga, fai `git checkout -- windows/flutter/` prima del commit.
  - Dopo ogni modifica agli ARB: `flutter gen-l10n`. La cartella `lib/l10n/gen/` non si committa. In un worktree appena creato `lib/l10n/gen/` non c'è: fai `flutter gen-l10n` prima di tutto.
- **Formattazione e fine riga:**
  - Niente `dart format` su file interi: solo edit mirati.
  - Ogni file tiene le sue terminazioni di riga: la working copy è CRLF (`core.autocrlf=true`), l'indice è LF. I file nuovi vanno bene con LF.
  - Scrivi in UTF-8 (i commenti italiani hanno è, à, ù) con gli strumenti di modifica dei file. Non usare `Set-Content` o `Out-File` sui sorgenti.
- **Codice:**
  - durate, misure e limiti come costanti nominate e commentate;
  - commenti in italiano, codice in inglese;
  - icone solo `LucideIcons`, colori `WfColors`;
  - `clock.now()`, mai `DateTime.now()`;
  - nei log mai titoli o nomi: solo il tipo dell'errore o il nome del `SocialFailure`.
- **Provider e test:**
  - nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`; i container dei test hanno `retry: (_, _) => null`;
  - in un provider, tutti i `ref.watch` stanno prima del primo `await`;
  - **spinner e `pumpAndSettle`:** il carosello e gli shimmer non si fermano mai. Nei test della Home usa `pump()` e `pump(durata)`, non `pumpAndSettle`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa, uno `switch` esaustivo da completare in un file non elencato):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-13 sul codice di `main` (`2b03b34`).

- **`SocialApi`** (`lib/core/social/social_api.dart`):
  - ogni metodo passa da `_call`, che traduce gli errori in `SocialException(SocialFailure)`: 404 → `unavailable`, 400/401/403 → `forbidden`, 409 → `conflict`, 429 → `rateLimited`, il resto (rete, forma inattesa) → `network`;
  - le chiamate passano `quietStatuses: _quiet` (`{403, 404, 409, 429}`);
  - `asJsonMap` e `jsonList` (in `../jellyfin/json_fields.dart`) leggono i corpi.
- **`JellyfinHttp`** (`lib/core/jellyfin/jellyfin_http.dart`) ha `get`, `post`, `delete` sopra `_send(() => dio.xxx<dynamic>(...), quietStatuses:)`; **non ha `put`**.
- **`FakeSocialApi`** (`test/support/social_fakes.dart`) implementa `SocialApi`: ogni metodo nuovo va aggiunto lì.
  - `nextFailure` lancia alla prossima chiamata (tranne `info`) e si azzera; `calls` registra stringhe (`friends`, `register g1 Private`, `invite g1 u2`, …).
  - `registerParty` dà `registerCode` (`K7PQ2X`) per i privati.
  - `testFriend(userId, name, {online})` costruisce un `FriendEntry`; `socialTestOverrides(api, {events, features, session})` mette sessione, eventi, plugin e funzioni.
- **`SocialFeatures`** (`lib/features/social/social_providers.dart`):
  - un campo per funzione, con costruttore, `==`, `hashCode` e `toString` scritti a mano;
  - `SocialAvailability.refresh()` le legge da `info.features` (`_canJoin && …` per quelle legate ai watch party);
  - `PluginFeatures` (in `social_models.dart`) ha le costanti; `describePluginFeatures` (in `lib/features/settings/diagnostics.dart`) le elenca.
- **Amici:**
  - `FriendEntry {userId, name, online, FriendParty? party}` con `fromJson`;
  - `friendsControllerProvider` (`FriendsController.reload()`), con le rilettura su `FriendsChanged`;
  - `_FriendRow` in `lib/features/friends/friends_panel.dart`:
    - sottotitolo `l.friendsInParty(party.title)`;
    - il tasto `_ActionButton(key: Key('friend-join-…'), label: l.watchPartyJoin)`;
    - `_join` con `_joining`;
    - `watchPartySessionProvider` letto solo se serve;
    - `shellPanelProvider.notifier.close()` a ingresso riuscito.
- **Watch party:**
  - `startWatchParty(context, ref, item, {start, mode})` (`lib/features/watch_party/watch_party_actions.dart`) crea il gruppo con la coda, e con `mode` registra il party in `register: (groupId) async {…}`;
  - gli errori diventano un avviso in `_run` (`watchPartyErrorText`);
  - `currentPartyProvider.notifier.invited(groupId, userId)` dopo un invito; `PartyMode.private` (`lib/core/syncplay/party_mode.dart`).
- **Libreria:** `libraryApiProvider` e `currentUserIdProvider` (`lib/features/library/library_providers.dart`); `LibraryApi.item(userId, itemId)` → `JellyfinItem`; `itemsByIds(userId, ids)` in ordine qualunque, salta quelli che l'utente non vede.
- **Impostazioni → Account:** `AccountSettingsSection` (`lib/features/settings/account_settings_section.dart`), una `Column(crossAxisAlignment: stretch)`. Interruttori come `SwitchListTile(contentPadding: EdgeInsets.zero, title:, subtitle:, value:, onChanged:)` (vedi `discord_settings_section.dart`). Chiave ARB `retry` = "Riprova".
- **Home:**
  - `HomeRowKind` (con `fromJellyfin`), `HomeRowGate` e `homeRowGate` in `home_layout.dart`;
  - `homeRowProvider` (caso `recommended` = modello) e `_libraryRow` (lancia per le righe non della libreria) in `home_providers.dart`;
  - `RecommendedRowContent`/`RecommendedItem` in `home_row_content.dart`;
  - `loadRecommended` in `home_rows_logic.dart` (`homeRowLimit`, `jellyfinIdKey`);
  - `HomeRowView` con `build` e `_title` esaustivi, e `_recommended` come modello di riga di locandine con sottotitolo;
  - `homeRowName` e `homeRowGateReason` in `home_rows_editing.dart`;
  - `test/features/home/home_layout_test.dart` elenca tutti gli id e le righe con `fromJellyfin` falso.
- **Test:**
  - `pumpApp(tester, child, overrides:)` (`test/support/pump_app.dart`, lingua it);
  - `homeOverrides(library:, availability:, social:)` in `home_fakes.dart`;
  - `FakeLibraryApi` (`itemsById`, `item` lancia `NotFoundException` se manca), `testItem(id:, name:, kind:, seriesId:, seriesName:)` in `library_fakes.dart`;
  - `FakeSyncPlayApi` (`onCall`, `calls`) e `testGroup()` in `watch_party_fakes.dart`;
  - nel gruppo `party` di `test/features/friends/friends_panel_test.dart` ci sono `syncPlay`, `events` e `pumpPartyPanel`;
  - i test dei testi stanno in `test/app/l10n_planXX_test.dart`.

## File

| File | Responsabilità |
|---|---|
| `lib/core/social/activity_models.dart` | `FriendPosition`, `FriendWatcher`, `FriendsWatched` |
| `lib/core/social/social_models.dart`, `social_api.dart`, `lib/core/jellyfin/jellyfin_http.dart` (modifiche) | `FriendNowPlaying`, `PluginFeatures.friendsActivity`, i 4 endpoint, `put` |
| `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart` (modifiche) | `SocialFeatures.friendsActivity`, diagnostica |
| `l10n/app_it.arb`, `l10n/app_en.arb` (modifiche) | i testi |
| `lib/features/friends/activity_labels.dart` | "Sta guardando …", "Visto da …" |
| `lib/features/friends/watch_with_friend.dart` | "Guarda insieme" |
| `lib/features/watch_party/watch_party_actions.dart`, `lib/features/friends/friends_panel.dart` (modifiche) | invito dopo la registrazione, testo e tasto nella riga |
| `lib/features/social/share_activity.dart`, `lib/features/settings/share_activity_setting.dart` | l'interruttore |
| `lib/features/settings/account_settings_section.dart` (modifica) | dove sta l'interruttore |
| `lib/features/home/*` (modifiche) | riga `friendsWatched` |

---

## Gruppo A — client e amici

### Task 1: client, funzione e testi

**Files:**
- Create: `lib/core/social/activity_models.dart`
- Modify: `lib/core/social/social_models.dart`, `lib/core/social/social_api.dart`, `lib/core/jellyfin/jellyfin_http.dart`, `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify (test): `test/support/social_fakes.dart`
- Test: `test/core/social/activity_api_test.dart`, `test/features/social/social_providers_test.dart` (un test in più), `test/app/l10n_plan21b_test.dart`

**Interfaces:**
- Produces:
  - `class FriendNowPlaying { itemId, title, String? seriesId, String? seriesName, int? season, int? episode }` con `fromJson`; `FriendEntry.nowPlaying` (`FriendNowPlaying?`);
  - `class FriendPosition { itemId, Duration position }`, `class FriendWatcher { userId, name, DateTime watchedAt }`, `class FriendsWatched { itemId, List<FriendWatcher> by }`, ognuna con `fromJson`;
  - `JellyfinHttp.put(path, {body, quietStatuses})`;
  - `SocialApi.friendNowPlaying(String userId) → Future<FriendPosition>`, `activitySettings() → Future<bool>`, `setActivitySettings(bool share) → Future<void>`, `friendsWatched() → Future<List<FriendsWatched>>`;
  - `PluginFeatures.friendsActivity = 'friendsActivity'`, `SocialFeatures.friendsActivity` (bool);
  - in `FakeSocialApi`: `nowPlayingById` (mappa; manca → `conflict`), `nowPlayingGate`, `shareActivity` (bool, `true`), `shareActivityFailure`, `friendsWatchedList`, `inviteFailure`, e i 4 metodi, che registrano `nowPlaying ID`, `activitySettings`, `setActivity true|false`, `friendsWatched`;
  - `testFriend(..., {FriendNowPlaying? nowPlaying})`, `testFriendsWatched(itemId, names)`;
  - le chiavi ARB dello Step 3.

- [ ] **Step 1: i test che falliscono**

`test/core/social/activity_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late SocialApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = SocialApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('amico che guarda un episodio, e uno senza NowPlaying', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Friends': [
            {
              'UserId': 'u2',
              'Name': 'Luigi',
              'Online': true,
              'Party': null,
              'NowPlaying': {
                'ItemId': 'e1',
                'Title': 'Pilot',
                'SeriesId': 's1',
                'SeriesName': 'The Bear',
                'Season': 2,
                'Episode': 3,
              },
            },
            {'UserId': 'u3', 'Name': 'Peach', 'Online': true, 'Party': null},
          ],
          'Incoming': [],
          'Outgoing': [],
        });
    final friends = (await api.friends()).friends;
    final playing = friends.first.nowPlaying!;
    expect(playing.itemId, 'e1');
    expect(playing.title, 'Pilot');
    expect(playing.seriesId, 's1');
    expect(playing.seriesName, 'The Bear');
    expect(playing.season, 2);
    expect(playing.episode, 3);
    expect(friends.last.nowPlaying, isNull);
  });

  test('film: niente serie, stagione o numero', () {
    final entry = FriendEntry.fromJson(const {
      'UserId': 'u2',
      'Name': 'Luigi',
      'Online': true,
      'NowPlaying': {'ItemId': 'm1', 'Title': 'Dune'},
    });
    expect(entry.nowPlaying!.title, 'Dune');
    expect(entry.nowPlaying!.seriesName, isNull);
    expect(entry.nowPlaying!.season, isNull);
  });

  test('posizione dell\'amico: i tick diventano una durata', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'ItemId': 'm1',
          'PositionTicks': 25200000000,
        });
    final position = await api.friendNowPlaying('u2');
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/WonderFlixWatchParty/Friends/u2/NowPlaying');
    expect(position.itemId, 'm1');
    expect(position.position, const Duration(minutes: 42));
  });

  test('posizione: 409 = conflict', () async {
    adapter.handler = (_) => const FakeResponse(409);
    await expectLater(
        api.friendNowPlaying('u2'),
        throwsA(isA<SocialException>()
            .having((e) => e.failure, 'failure', SocialFailure.conflict)));
  });

  test('impostazione: lettura e scrittura', () async {
    adapter.handler = (_) => const FakeResponse(200, {'ShareActivity': false});
    expect(await api.activitySettings(), isFalse);
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Activity/Settings');

    adapter.handler = (_) => const FakeResponse(204);
    await api.setActivitySettings(true);
    final request = adapter.requests.last;
    expect(request.method, 'PUT');
    expect(request.path, '/WonderFlixWatchParty/Activity/Settings');
    expect(request.data, {'ShareActivity': true});
  });

  test('Visti dagli amici', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {
              'ItemId': 'm1',
              'By': [
                {'UserId': 'u2', 'Name': 'Luigi', 'WatchedAt': '2026-10-13T20:00:00Z'},
                {'UserId': 'u3', 'Name': 'Peach', 'WatchedAt': '2026-10-12T19:00:00Z'},
              ],
            },
          ],
        });
    final items = await api.friendsWatched();
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Activity/FriendsWatched');
    expect(items.single.itemId, 'm1');
    expect(items.single.by.map((w) => w.name), ['Luigi', 'Peach']);
    expect(items.single.by.first.watchedAt, DateTime.utc(2026, 10, 13, 20));
  });
}
```

(Se `FakeAdapter` registra la richiesta con nomi diversi da `method`, `path`, `data`, usa quelli di `test/support/fake_adapter.dart`. Se `FakeResponse` non accetta un corpo con `Party: null` o liste vuote, adatta il corpo senza cambiare cosa si controlla.)

In `test/features/social/social_providers_test.dart`, accanto al test dei consigli (`Info con i consigli: funzione recommendations, solo con i watch party`), un test uguale per la funzione nuova:

```dart
  test('Info con l\'attività degli amici: funzione friendsActivity, solo con '
      'i watch party', () async {
    api.install(features: const {
      PluginFeatures.friends,
      PluginFeatures.friendsActivity,
    });
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(friends: true, friendsActivity: true));

    final noParty = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(noParty.read(socialAvailabilityProvider).friendsActivity, isFalse);
  });
```

`test/app/l10n_plan21b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 21b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.friendsWatching('Dune'), 'Sta guardando Dune');
    expect(it.friendsWatchingEpisode('The Bear', 2, 3), 'Sta guardando The Bear · S2 E3');
    expect(it.friendsWatchTogether, 'Guarda insieme');
    expect(it.friendsNoLongerWatching, 'Non sta più guardando');
    expect(it.friendsInviteNotSent, 'Invito non inviato');
    expect(it.settingsShareActivity, 'Mostra agli amici cosa guardo');
    expect(it.settingsShareActivityHint,
        'Gli amici vedono il titolo che stai guardando e quelli che hai visto negli ultimi 30 giorni in WonderFlix');
    expect(it.settingsShareActivityLoadError, 'Impossibile caricare l\'impostazione');
    expect(it.settingsShareActivitySaveError, 'Impostazione non salvata');
    expect(it.homeRowFriendsWatched, 'Visti dagli amici');
    expect(it.friendsWatchedByOne('Luca'), 'Visto da Luca');
    expect(it.friendsWatchedByTwo('Luca', 'Marta'), 'Visto da Luca e Marta');
    expect(it.friendsWatchedByMany('Luca', 2), 'Visto da Luca e altri 2');
    expect(it.homeRowUnavailableFriendsActivity,
        'Serve il plugin 1.9.0 e l\'accesso ai watch party');
    expect(en.friendsWatching('Dune'), 'Watching Dune');
    expect(en.friendsWatchingEpisode('The Bear', 2, 3), 'Watching The Bear · S2 E3');
    expect(en.friendsWatchTogether, 'Watch together');
    expect(en.settingsShareActivity, 'Show friends what I watch');
    expect(en.homeRowFriendsWatched, 'Watched by friends');
    expect(en.friendsWatchedByMany('Luca', 2), 'Watched by Luca and 2 others');
    expect(en.homeRowUnavailableFriendsActivity, 'Needs plugin 1.9.0 and watch party access');
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/social/activity_api_test.dart test/features/social/social_providers_test.dart test/app/l10n_plan21b_test.dart`
Expected: FAIL (classi, metodi, campi e testi mancanti).

- [ ] **Step 3: il codice**

`lib/core/social/activity_models.dart`:

```dart
/// Modelli di "cosa guardano gli amici" (spec O §6.5, §6.6), come li manda
/// il plugin.
library;

/// Dove è arrivato un amico, per "Guarda insieme" (spec O §6.5).
class FriendPosition {
  const FriendPosition({required this.itemId, required this.position});

  factory FriendPosition.fromJson(Map<String, dynamic> json) => FriendPosition(
        itemId: json['ItemId'] as String,
        // Un tick di Jellyfin è 100 ns (piano 21b, decisione 2).
        position: Duration(
            microseconds: (json['PositionTicks'] as num? ?? 0).toInt() ~/ 10),
      );

  final String itemId;
  final Duration position;
}

/// Un amico che ha visto un titolo della riga, e quando l'ultima volta.
class FriendWatcher {
  const FriendWatcher({
    required this.userId,
    required this.name,
    required this.watchedAt,
  });

  factory FriendWatcher.fromJson(Map<String, dynamic> json) => FriendWatcher(
        userId: json['UserId'] as String,
        name: json['Name'] as String,
        watchedAt: DateTime.parse(json['WatchedAt'] as String).toUtc(),
      );

  final String userId;
  final String name;

  /// In UTC.
  final DateTime watchedAt;
}

/// Un titolo di "Visti dagli amici", con chi l'ha visto dal più recente.
class FriendsWatched {
  const FriendsWatched({required this.itemId, required this.by});

  factory FriendsWatched.fromJson(Map<String, dynamic> json) => FriendsWatched(
        itemId: json['ItemId'] as String,
        by: [
          for (final raw in json['By'] as List? ?? const [])
            FriendWatcher.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final String itemId;
  final List<FriendWatcher> by;
}
```

In `lib/core/social/social_models.dart`:
- in `PluginFeatures`, dopo `recommendations`:

```dart

  /// Cosa guardano gli amici (spec O §6.7).
  static const friendsActivity = 'friendsActivity';
```

- prima di `class FriendEntry`:

```dart
/// Cosa sta guardando un amico (spec O §6.2): il film o l'episodio; per un
/// episodio anche serie, stagione e numero, ognuno `null` se il plugin non
/// lo manda.
class FriendNowPlaying {
  const FriendNowPlaying({
    required this.itemId,
    required this.title,
    this.seriesId,
    this.seriesName,
    this.season,
    this.episode,
  });

  factory FriendNowPlaying.fromJson(Map<String, dynamic> json) =>
      FriendNowPlaying(
        itemId: json['ItemId'] as String,
        title: json['Title'] as String? ?? '',
        seriesId: json['SeriesId'] as String?,
        seriesName: json['SeriesName'] as String?,
        season: (json['Season'] as num?)?.toInt(),
        episode: (json['Episode'] as num?)?.toInt(),
      );

  final String itemId;
  final String title;
  final String? seriesId;
  final String? seriesName;
  final int? season;
  final int? episode;
}
```

- `FriendEntry`: nel costruttore `this.nowPlaying,` dopo `this.party,`; in `fromJson`:

```dart
    // `NowPlaying` manca se l'amico non guarda o non lo mostra (spec O §6.2).
    final nowPlaying = json['NowPlaying'];
```

  e nel costruttore restituito `nowPlaying: nowPlaying is Map<String, dynamic> ? FriendNowPlaying.fromJson(nowPlaying) : null,`; il campo:

```dart

  /// Cosa guarda, fuori da un party (spec O §6.2); `null` se non si sa.
  final FriendNowPlaying? nowPlaying;
```

In `lib/core/jellyfin/jellyfin_http.dart`, dopo `delete`:

```dart

  /// [quietStatuses] come in [get].
  Future<dynamic> put(String path,
          {Object? body, Set<int> quietStatuses = const {}}) =>
      _send(() => dio.put<dynamic>(path, data: body),
          quietStatuses: quietStatuses);
```

In `lib/core/social/social_api.dart`:
- import `'activity_models.dart'`;
- in fondo alla classe, prima di `_call`:

```dart

  /// Dove è arrivato l'amico, per "Guarda insieme" (spec O §6.5);
  /// `SocialFailure.conflict` se non sta più guardando.
  Future<FriendPosition> friendNowPlaying(String userId) => _call(() async =>
      FriendPosition.fromJson(asJsonMap(await _http.get(
          '$_base/Friends/$userId/NowPlaying',
          quietStatuses: _quiet))));

  /// "Mostra agli amici cosa guardo" dell'account aperto (spec O §6.1).
  Future<bool> activitySettings() => _call(() async =>
      asJsonMap(await _http.get('$_base/Activity/Settings',
          quietStatuses: _quiet))['ShareActivity'] as bool? ??
      true);

  Future<void> setActivitySettings(bool share) => _call(() => _http.put(
      '$_base/Activity/Settings',
      body: {'ShareActivity': share},
      quietStatuses: _quiet));

  /// La riga "Visti dagli amici" (spec O §6.6), già filtrata e ordinata.
  Future<List<FriendsWatched>> friendsWatched() => _call(() async => jsonList(
      asJsonMap(await _http.get('$_base/Activity/FriendsWatched',
          quietStatuses: _quiet))['Items'],
      FriendsWatched.fromJson));
```

In `lib/features/social/social_providers.dart`, `SocialFeatures`:
- costruttore: `this.friendsActivity = false,` dopo `this.recommendations = false,`;
- campo, dopo `recommendations`:

```dart

  /// Cosa guardano gli amici (spec O §7.1): come gli amici, solo con
  /// l'accesso ai watch party (piano 21b, decisione 7).
  final bool friendsActivity;
```

- `==`: `other.friendsActivity == friendsActivity &&` dopo la riga di `recommendations`; `hashCode`: `friendsActivity,` dopo `recommendations,`; `toString`: `'recommendations: $recommendations, friendsActivity: $friendsActivity, known: $known)'`;
- in `SocialAvailability.refresh()`, dopo `recommendations: …`:

```dart
        friendsActivity:
            _canJoin && info.features.contains(PluginFeatures.friendsActivity),
```

In `lib/features/settings/diagnostics.dart`, in `describePluginFeatures` dopo `'consigli'`:
`if (features.contains(PluginFeatures.friendsActivity)) 'attività degli amici',`
(se un test della diagnostica elenca le funzioni, aggiungilo lì).

ARB (`l10n/app_it.arb` e `l10n/app_en.arb`), in fondo, dopo `homeRowUnavailableRecommendations` (aggiungi la virgola alla sua riga). In italiano:

```json
  "friendsWatching": "Sta guardando {title}",
  "@friendsWatching": {"placeholders": {"title": {"type": "String"}}},
  "friendsWatchingEpisode": "Sta guardando {series} · S{season} E{episode}",
  "@friendsWatchingEpisode": {"placeholders": {"series": {"type": "String"}, "season": {"type": "int"}, "episode": {"type": "int"}}},
  "friendsWatchTogether": "Guarda insieme",
  "friendsNoLongerWatching": "Non sta più guardando",
  "friendsInviteNotSent": "Invito non inviato",
  "settingsShareActivity": "Mostra agli amici cosa guardo",
  "settingsShareActivityHint": "Gli amici vedono il titolo che stai guardando e quelli che hai visto negli ultimi 30 giorni in WonderFlix",
  "settingsShareActivityLoadError": "Impossibile caricare l'impostazione",
  "settingsShareActivitySaveError": "Impostazione non salvata",
  "homeRowFriendsWatched": "Visti dagli amici",
  "friendsWatchedByOne": "Visto da {name}",
  "@friendsWatchedByOne": {"placeholders": {"name": {"type": "String"}}},
  "friendsWatchedByTwo": "Visto da {first} e {second}",
  "@friendsWatchedByTwo": {"placeholders": {"first": {"type": "String"}, "second": {"type": "String"}}},
  "friendsWatchedByMany": "Visto da {name} e altri {count}",
  "@friendsWatchedByMany": {"placeholders": {"name": {"type": "String"}, "count": {"type": "int"}}},
  "homeRowUnavailableFriendsActivity": "Serve il plugin 1.9.0 e l'accesso ai watch party"
```

In inglese le stesse chiavi (con le stesse `@…` come fa `app_en.arb` per i consigli): "Watching {title}", "Watching {series} · S{season} E{episode}", "Watch together", "Not watching anymore", "Invite not sent", "Show friends what I watch", "Friends see what you're watching and what you watched in WonderFlix in the last 30 days", "Couldn't load the setting", "Setting not saved", "Watched by friends", "Watched by {name}", "Watched by {first} and {second}", "Watched by {name} and {count} others", "Needs plugin 1.9.0 and watch party access".

Poi `flutter gen-l10n`.

In `test/support/social_fakes.dart`:
- import `package:wonderflix/core/social/activity_models.dart`;
- in `invite`, prima di `_fail();`:

```dart
    final inviteError = inviteFailure;
    if (inviteError != null) throw SocialException(inviteError);
```

- in fondo a `FakeSocialApi`:

```dart

  /// Errore di ogni [invite], se valorizzato.
  SocialFailure? inviteFailure;

  /// Posizione per [friendNowPlaying], per amico; manca = 409 (`conflict`).
  final nowPlayingById = <String, FriendPosition>{};

  /// Se valorizzato, [friendNowPlaying] aspetta che si completi.
  Completer<void>? nowPlayingGate;

  @override
  Future<FriendPosition> friendNowPlaying(String userId) async {
    calls.add('nowPlaying $userId');
    await nowPlayingGate?.future;
    _fail();
    return nowPlayingById[userId] ??
        (throw const SocialException(SocialFailure.conflict));
  }

  /// "Mostra agli amici cosa guardo" del plugin finto.
  bool shareActivity = true;

  /// Errore di [setActivitySettings], se valorizzato.
  SocialFailure? shareActivityFailure;

  @override
  Future<bool> activitySettings() async {
    calls.add('activitySettings');
    _fail();
    return shareActivity;
  }

  @override
  Future<void> setActivitySettings(bool share) async {
    calls.add('setActivity $share');
    final failure = shareActivityFailure;
    if (failure != null) throw SocialException(failure);
    shareActivity = share;
  }

  /// Risposta di [friendsWatched].
  List<FriendsWatched> friendsWatchedList = const [];

  @override
  Future<List<FriendsWatched>> friendsWatched() async {
    calls.add('friendsWatched');
    _fail();
    return friendsWatchedList;
  }
```

- `testFriend` diventa:

```dart
FriendEntry testFriend(String userId, String name,
        {bool online = false, FriendNowPlaying? nowPlaying}) =>
    FriendEntry(
        userId: userId, name: name, online: online, nowPlaying: nowPlaying);
```

- accanto a `testRecommendation`:

```dart
/// Un titolo di "Visti dagli amici": [names] dal più recente.
FriendsWatched testFriendsWatched(String itemId, List<String> names) =>
    FriendsWatched(itemId: itemId, by: [
      for (final (i, name) in names.indexed)
        FriendWatcher(
            userId: 'u-$name',
            name: name,
            watchedAt: DateTime.utc(2026, 10, 13, 20).subtract(Duration(hours: i))),
    ]);
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `flutter analyze` e la suite intera con `--concurrency=4`.
Expected: PASS.

- [ ] **Step 5: commit**

```powershell
git checkout -- windows/flutter/
git add lib l10n test
git commit -m "feat(app): friends activity client, feature and strings"
```

### Task 2: "Sta guardando" e "Guarda insieme" nel pannello Amici

**Files:**
- Create: `lib/features/friends/activity_labels.dart`, `lib/features/friends/watch_with_friend.dart`
- Modify: `lib/features/watch_party/watch_party_actions.dart`, `lib/features/friends/friends_panel.dart`
- Test: `test/features/friends/activity_labels_test.dart`, `test/features/friends/friends_panel_test.dart` (test nuovi nel gruppo `party`)

**Interfaces:**
- Consumes: Task 1 (`FriendNowPlaying`, `FriendWatcher`, `friendNowPlaying`, `invite` del finto, `nowPlayingById`, testi).
- Produces:
  - `String friendNowPlayingText(AppLocalizations l, FriendNowPlaying playing)`, `String friendsWatchedBy(AppLocalizations l, List<FriendWatcher> by)` in `activity_labels.dart`;
  - `startWatchParty(context, ref, item, {start, mode, String? invite})`;
  - `Future<bool> watchWithFriend(BuildContext context, WidgetRef ref, FriendEntry friend)`;
  - nella riga dell'amico il tasto `Key('friend-watch-<userId>')`.

- [ ] **Step 1: i test che falliscono**

`test/features/friends/activity_labels_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/activity_models.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/friends/activity_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('Sta guardando: film, episodio, episodio senza numeri o senza serie', () {
    expect(friendNowPlayingText(l, const FriendNowPlaying(itemId: 'm1', title: 'Dune')),
        'Sta guardando Dune');
    expect(
        friendNowPlayingText(
            l,
            const FriendNowPlaying(
                itemId: 'e1', title: 'Pilot', seriesName: 'The Bear', season: 2, episode: 3)),
        'Sta guardando The Bear · S2 E3');
    expect(
        friendNowPlayingText(
            l, const FriendNowPlaying(itemId: 'e1', title: 'Pilot', seriesName: 'The Bear', season: 2)),
        'Sta guardando The Bear');
    expect(friendNowPlayingText(l, const FriendNowPlaying(itemId: 'e1', title: 'Speciale')),
        'Sta guardando Speciale');
  });

  test('Visto da: uno, due, tre o più', () {
    FriendWatcher w(String name) =>
        FriendWatcher(userId: name, name: name, watchedAt: DateTime.utc(2026));
    expect(friendsWatchedBy(l, [w('Luca')]), 'Visto da Luca');
    expect(friendsWatchedBy(l, [w('Luca'), w('Marta')]), 'Visto da Luca e Marta');
    expect(friendsWatchedBy(l, [w('Luca'), w('Marta'), w('Sara')]), 'Visto da Luca e altri 2');
    expect(friendsWatchedBy(l, const []), '');
  });
}
```

In `test/features/friends/friends_panel_test.dart`, nel gruppo `party`, dopo `pumpPartyPanel`:

```dart
    late FakeLibraryApi library;

    /// Il pannello con la libreria finta: "Guarda insieme" apre il titolo.
    Future<void> pumpWatchPanel(WidgetTester tester) async {
      library = FakeLibraryApi()
        ..itemsById['m1'] = testItem(id: 'm1', name: 'Dune');
      syncPlay.onCall = (call) {
        if (call.startsWith('create') || call.startsWith('join')) {
          events.add(SyncPlayGroupUpdated(GroupJoined('g1', testGroup())));
        }
      };
      await pumpApp(
        tester,
        const Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: FriendsPanel.width, child: FriendsPanel()),
          ),
        ),
        overrides: [
          ...socialTestOverrides(api,
              events: events.stream,
              features: const SocialFeatures(
                  friends: true, parties: true, friendsActivity: true)),
          syncPlayApiProvider.overrideWithValue(syncPlay),
          partyChannelApiProvider
              .overrideWithValue(FakePartyChannelApi()..install()),
          libraryApiProvider.overrideWithValue(library),
        ],
      );
      await tester.pump();
    }

    const dune = FriendNowPlaying(itemId: 'm1', title: 'Dune');

    testWidgets('Sta guardando: il testo e Guarda insieme', (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
        testFriend('u3', 'Peach', online: true),
      ]);
      await pumpWatchPanel(tester);
      expect(find.text('Sta guardando Dune'), findsOneWidget);
      expect(find.byKey(const Key('friend-watch-u2')), findsOneWidget);
      expect(find.byKey(const Key('friend-watch-u3')), findsNothing);
    });

    testWidgets('Guarda insieme: posizione, party privato senza menu e invito',
        (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      api.nowPlayingById['u2'] =
          const FriendPosition(itemId: 'm1', position: Duration(minutes: 42));
      await pumpWatchPanel(tester);
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pumpAndSettle();
      expect(api.calls, containsAllInOrder(['nowPlaying u2', 'register g1 Private', 'invite g1 u2']));
      expect(find.text('Pubblico'), findsNothing, reason: 'niente menu delle modalità');
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      expect(container.read(currentPartyProvider)?.mode, PartyMode.private);
      await leaveParty(tester);
    });

    testWidgets('Guarda insieme quando l\'amico ha smesso: avviso e niente party',
        (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      await pumpWatchPanel(tester);
      final friendsBefore = api.calls.where((c) => c == 'friends').length;
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pumpAndSettle();
      expect(find.text('Non sta più guardando'), findsOneWidget);
      expect(syncPlay.calls.where((c) => c.startsWith('create')), isEmpty);
      expect(api.calls.where((c) => c == 'friends').length, friendsBefore + 1,
          reason: 'l\'elenco si rilegge');
    });

    testWidgets('invito non riuscito: il party resta e lo dice', (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      api.nowPlayingById['u2'] =
          const FriendPosition(itemId: 'm1', position: Duration.zero);
      api.inviteFailure = SocialFailure.rateLimited;
      await pumpWatchPanel(tester);
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pumpAndSettle();
      expect(find.text('Invito non inviato'), findsOneWidget);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      expect(container.read(watchPartySessionProvider).inGroup, isTrue);
      await leaveParty(tester);
    });

    testWidgets('Guarda insieme spento mentre parte', (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      final gate = api.nowPlayingGate = Completer<void>();
      await pumpWatchPanel(tester);
      await tester.tap(find.byKey(const Key('friend-watch-u2')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('friend-watch-u2')), warnIfMissed: false);
      await tester.pump();
      expect(api.calls.where((c) => c == 'nowPlaying u2'), hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('già in un gruppo: niente Guarda insieme', (tester) async {
      api.snapshot = FriendsSnapshot(friends: [
        testFriend('u2', 'Luigi', online: true, nowPlaying: dune),
      ]);
      await pumpWatchPanel(tester);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(FriendsPanel)));
      await container.read(watchPartySessionProvider.notifier).join('g1');
      await tester.pumpAndSettle();
      expect(container.read(watchPartySessionProvider).inGroup, isTrue);
      expect(find.byKey(const Key('friend-watch-u2')), findsNothing);
      expect(find.text('Sta guardando Dune'), findsOneWidget);
      await leaveParty(tester);
    });
```

Import da aggiungere al test, se mancano: `activity_models.dart`, `social_api.dart`, `party_mode.dart`, `current_party.dart`, `library_providers.dart`, `../../support/library_fakes.dart`. Se il pannello del test ha un `FakeSocialApi` diverso da `api` nel gruppo, usa quello del gruppo. Se `"Pubblico"` non è il testo del menu delle modalità, usa un testo del menu da `party_mode_menu.dart`: il controllo è che il menu non si apra.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/friends/activity_labels_test.dart test/features/friends/friends_panel_test.dart`
Expected: FAIL (`activity_labels.dart` non esiste, il tasto non c'è).

- [ ] **Step 3: il codice**

`lib/features/friends/activity_labels.dart`:

```dart
import '../../core/social/activity_models.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// "Sta guardando Dune", "Sta guardando The Bear · S2 E3" (spec O §7.2):
/// senza stagione o numero solo la serie, senza serie il nome
/// dell'episodio.
String friendNowPlayingText(AppLocalizations l, FriendNowPlaying playing) {
  final series = playing.seriesName;
  if (series == null || series.isEmpty) return l.friendsWatching(playing.title);
  final season = playing.season;
  final episode = playing.episode;
  return season != null && episode != null
      ? l.friendsWatchingEpisode(series, season, episode)
      : l.friendsWatching(series);
}

/// "Visto da Luca", "Visto da Luca e Marta", "Visto da Luca e altri 2": chi
/// l'ha visto è già dal più recente (spec O §7.4, piano 21b decisione 6).
String friendsWatchedBy(AppLocalizations l, List<FriendWatcher> by) =>
    switch (by) {
      [] => '',
      [final one] => l.friendsWatchedByOne(one.name),
      [final first, final second] =>
        l.friendsWatchedByTwo(first.name, second.name),
      [final first, ...final others] =>
        l.friendsWatchedByMany(first.name, others.length),
    };
```

In `lib/features/watch_party/watch_party_actions.dart`:
- import `'../../core/social/social_api.dart'` se manca;
- `startWatchParty` riceve `String? invite,` dopo `PartyMode? mode,`; nel commento della funzione: "Con [invite] il party, appena registrato, invita quell'amico (spec O §7.2): un invito che non riesce non ferma il party, lo dice un avviso.";
- nel corpo, accanto a `final container = …` (prima della prima attesa):

```dart
        final messenger = ScaffoldMessenger.maybeOf(context);
        final inviteNotSent = AppLocalizations.of(context).friendsInviteNotSent;
```

- nel `register`, dopo `.registered(groupId, mode, code);`:

```dart
                    if (invite != null) {
                      try {
                        await social.invite(groupId, [invite]);
                        container
                            .read(currentPartyProvider.notifier)
                            .invited(groupId, invite);
                      } on SocialException {
                        // Piano 21b, decisione 1: il party resta.
                        messenger?.showSnackBar(
                            SnackBar(content: Text(inviteNotSent)));
                      }
                    }
```

`lib/features/friends/watch_with_friend.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../core/social/activity_models.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../../core/syncplay/party_mode.dart';
import '../../l10n/gen/app_localizations.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import '../watch_party/watch_party_actions.dart';
import 'friends_controller.dart';

/// "Guarda insieme" con un amico che sta guardando (spec O §7.2): legge dove
/// è arrivato, apre un party privato sullo stesso titolo da lì, senza il
/// menu delle modalità, e lo invita. `false` se non parte.
Future<bool> watchWithFriend(
    BuildContext context, WidgetRef ref, FriendEntry friend) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final FriendPosition position;
  final JellyfinItem item;
  try {
    position =
        await container.read(socialApiProvider).friendNowPlaying(friend.userId);
  } on SocialException catch (error) {
    if (error.failure == SocialFailure.conflict) {
      // Piano 21b, decisione 4: testo e tasto spariscono subito.
      messenger?.showSnackBar(SnackBar(content: Text(l.friendsNoLongerWatching)));
      await container.read(friendsControllerProvider.notifier).reload();
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(l.watchPartyCreateError)));
    }
    return false;
  }
  try {
    item = await container
        .read(libraryApiProvider)
        .item(container.read(currentUserIdProvider), position.itemId);
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text(l.watchPartyCreateError)));
    return false;
  }
  if (!context.mounted) return false;
  return startWatchParty(context, ref, item,
      start: position.position, mode: PartyMode.private, invite: friend.userId);
}
```

(Se `friendsControllerProvider.notifier.reload()` ha un altro nome, usa il metodo che rilegge gli amici in `friends_controller.dart`.)

In `lib/features/friends/friends_panel.dart`:
- import `'activity_labels.dart'` e `'watch_with_friend.dart'`;
- `_FriendRowState`: `bool _watching = false;` accanto a `_joining`, e dopo `_join`:

```dart
  /// "Guarda insieme" (spec O §7.2); partito, il pannello si chiude. Spento
  /// finché parte: un secondo clic farebbe un secondo party.
  Future<void> _watch() async {
    setState(() => _watching = true);
    try {
      final started = await watchWithFriend(context, ref, widget.friend);
      if (started && mounted) ref.read(shellPanelProvider.notifier).close();
    } finally {
      if (mounted) setState(() => _watching = false);
    }
  }
```

- in `build`, dopo `showJoin`:

```dart
    final nowPlaying = party == null ? friend.nowPlaying : null;
    // Già in un gruppo si invita dal menu del party (piano 21b, decisione 3).
    final inGroup = nowPlaying != null &&
        ref.watch(watchPartySessionProvider.select((s) => s.inGroup));
    final showWatch = nowPlaying != null && _confirm == null && !inGroup;
```

- `subtitle:` diventa:

```dart
      subtitle: party != null
          ? l.friendsInParty(party.title)
          : nowPlaying != null
              ? friendNowPlayingText(l, nowPlaying)
              : null,
```

- `trailing:` diventa (stesso `Row` per i due tasti):

```dart
      trailing: showJoin || showWatch
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showJoin)
                  _ActionButton(
                    key: Key('friend-join-${friend.userId}'),
                    label: l.watchPartyJoin,
                    onPressed: _joining
                        ? null
                        : () => unawaited(_join(party.groupId)),
                  )
                else
                  _ActionButton(
                    key: Key('friend-watch-${friend.userId}'),
                    label: l.friendsWatchTogether,
                    onPressed: _watching ? null : () => unawaited(_watch()),
                  ),
                menu,
              ],
            )
          : menu,
```

(`party` non è null quando `showJoin` è vero: se l'analyzer non lo capisce, usa `party!.groupId` dentro il ramo.)

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `flutter test test/features/watch_party/` (i test di `startWatchParty` restano verdi), `flutter analyze` e la suite intera con `--concurrency=4`.
Expected: PASS.

- [ ] **Step 5: commit**

```powershell
git checkout -- windows/flutter/
git add lib test
git commit -m "feat(app): friends now playing and watch together"
```

---

## Gruppo B — impostazione e riga

### Task 3: l'interruttore "Mostra agli amici cosa guardo"

**Files:**
- Create: `lib/features/social/share_activity.dart`, `lib/features/settings/share_activity_setting.dart`
- Modify: `lib/features/settings/account_settings_section.dart`
- Test: `test/features/settings/share_activity_setting_test.dart`

**Interfaces:**
- Consumes: Task 1 (`activitySettings`, `setActivitySettings`, `SocialFeatures.friendsActivity`, finto con `shareActivity` e `shareActivityFailure`, testi).
- Produces: `shareActivityProvider` (`AsyncNotifierProvider.autoDispose<ShareActivityController, bool>`), `ShareActivityController.set(bool) → Future<bool>`, `ShareActivitySetting` (widget, interruttore `Key('share-activity')`, "Riprova" `Key('share-activity-retry')`).

- [ ] **Step 1: i test che falliscono**

`test/features/settings/share_activity_setting_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/account_settings_section.dart';
import 'package:wonderflix/features/settings/share_activity_setting.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/account_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeSocialApi api;

  setUp(() => api = FakeSocialApi());

  Future<void> pumpSetting(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: ShareActivitySetting()),
      overrides: socialTestOverrides(api,
          features: const SocialFeatures(friends: true, friendsActivity: true)),
    );
    await tester.pump();
  }

  SwitchListTile tile(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byKey(const Key('share-activity')));

  testWidgets('acceso dal plugin, con il testo sotto', (tester) async {
    await pumpSetting(tester);
    expect(api.calls, contains('activitySettings'));
    expect(find.text('Mostra agli amici cosa guardo'), findsOneWidget);
    expect(
        find.text('Gli amici vedono il titolo che stai guardando e quelli che '
            'hai visto negli ultimi 30 giorni in WonderFlix'),
        findsOneWidget);
    expect(tile(tester).value, isTrue);
  });

  testWidgets('spento e riacceso: salva subito', (tester) async {
    await pumpSetting(tester);
    await tester.tap(find.byKey(const Key('share-activity')));
    await tester.pump();
    expect(api.calls, contains('setActivity false'));
    expect(tile(tester).value, isFalse);
    await tester.tap(find.byKey(const Key('share-activity')));
    await tester.pump();
    expect(api.calls, contains('setActivity true'));
    expect(tile(tester).value, isTrue);
  });

  testWidgets('salvataggio non riuscito: torna com\'era e lo dice',
      (tester) async {
    api.shareActivityFailure = SocialFailure.network;
    await pumpSetting(tester);
    await tester.tap(find.byKey(const Key('share-activity')));
    await tester.pump();
    await tester.pump();
    expect(tile(tester).value, isTrue);
    expect(find.text('Impostazione non salvata'), findsOneWidget);
  });

  testWidgets('lettura non riuscita: il messaggio e Riprova', (tester) async {
    api.nextFailure = SocialFailure.network;
    await pumpSetting(tester);
    expect(find.text('Impossibile caricare l\'impostazione'), findsOneWidget);
    expect(find.byKey(const Key('share-activity')), findsNothing);
    await tester.tap(find.byKey(const Key('share-activity-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('share-activity')), findsOneWidget);
  });

  testWidgets('in Account solo con la funzione', (tester) async {
    Future<void> pumpAccount(SocialFeatures features) => pumpApp(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: AccountSettingsSection())),
          overrides: [
            sessionControllerProvider.overrideWith(
                () => FakeSessionController(const SessionSignedIn(testUser))),
            ...accountTestOverrides(FakeAccountApi(), available: false),
            ...socialTestOverrides(api, features: features, session: false),
          ],
        );

    await pumpAccount(const SocialFeatures(friends: true));
    await tester.pump();
    expect(find.byType(ShareActivitySetting), findsNothing);
    expect(api.calls, isNot(contains('activitySettings')));

    await pumpAccount(const SocialFeatures(friends: true, friendsActivity: true));
    await tester.pump();
    expect(find.byType(ShareActivitySetting), findsOneWidget);
  });
}
```

(Il nome dell'ultimo test è quello della Review Focus: "senza la funzione: niente interruttore" è il suo primo controllo. Se il secondo `pumpApp` nello stesso test non ricostruisce i provider, dividilo in due test.)

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/settings/share_activity_setting_test.dart`
Expected: FAIL (`share_activity_setting.dart` non esiste).

- [ ] **Step 3: il codice**

`lib/features/social/share_activity.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/social/social_api.dart';
import '../auth/session_controller.dart';
import 'social_providers.dart';

/// "Mostra agli amici cosa guardo" dell'account aperto (spec O §7.3): sta
/// nel plugin, non nel dispositivo. Si rilegge a ogni cambio di profilo e
/// ogni volta che la sezione torna a vedersi (`autoDispose`).
class ShareActivityController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    return ref.watch(socialApiProvider).activitySettings();
  }

  /// Salva subito (spec O §7.3); non riuscito, torna com'era e risponde
  /// `false`.
  Future<bool> set(bool share) async {
    final previous = state.value;
    state = AsyncData(share);
    try {
      await ref.read(socialApiProvider).setActivitySettings(share);
      return true;
    } on SocialException {
      if (ref.mounted) state = AsyncData(previous ?? !share);
      return false;
    }
  }
}

final shareActivityProvider =
    AsyncNotifierProvider.autoDispose<ShareActivityController, bool>(
        ShareActivityController.new);
```

`lib/features/settings/share_activity_setting.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../social/share_activity.dart';

/// Larghezza massima della riga, come le altre impostazioni.
const _shareActivityMaxWidth = 640.0;

/// L'interruttore "Mostra agli amici cosa guardo" (spec O §7.3).
class ShareActivitySetting extends ConsumerWidget {
  const ShareActivitySetting({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, bool share) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!await ref.read(shareActivityProvider.notifier).set(share)) {
      messenger?.showSnackBar(
          SnackBar(content: Text(l.settingsShareActivitySaveError)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final value = ref.watch(shareActivityProvider);
    final Widget child;
    if (value.hasError && !value.hasValue) {
      child = Row(
        children: [
          Expanded(
            child: Text(l.settingsShareActivityLoadError,
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
          TextButton(
            key: const Key('share-activity-retry'),
            onPressed: () => ref.invalidate(shareActivityProvider),
            child: Text(l.retry),
          ),
        ],
      );
    } else {
      final share = value.value;
      child = SwitchListTile(
        key: const Key('share-activity'),
        contentPadding: EdgeInsets.zero,
        title: Text(l.settingsShareActivity),
        subtitle: Text(l.settingsShareActivityHint),
        // Mentre si legge resta spento e fermo.
        value: share ?? false,
        onChanged: share == null
            ? null
            : (next) => unawaited(_set(context, ref, next)),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _shareActivityMaxWidth),
        child: child,
      ),
    );
  }
}
```

(Se `WfColors` sta in un altro file o `l.retry` ha un altro nome, usa quelli della sezione Discord e della chiave `retry` dell'ARB.)

In `lib/features/settings/account_settings_section.dart`:
- import `'../social/social_providers.dart'` e `'share_activity_setting.dart'`;
- dopo il `Wrap` dei pulsanti, prima del blocco dei contatti:

```dart
        // Piano 21b, decisione 5: vale per l'account aperto.
        if (user != null &&
            ref.watch(socialAvailabilityProvider
                .select((f) => f.friendsActivity))) ...[
          const SizedBox(height: 24),
          const ShareActivitySetting(),
        ],
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `flutter test test/features/settings/`, `flutter analyze` e la suite intera con `--concurrency=4`.
Expected: PASS (i test di `AccountSettingsSection` che non danno la funzione restano come sono).

- [ ] **Step 5: commit**

```powershell
git checkout -- windows/flutter/
git add lib test
git commit -m "feat(app): show friends what I watch setting"
```

### Task 4: la riga "Visti dagli amici"

**Files:**
- Modify: `lib/features/home/home_layout.dart`, `home_providers.dart`, `home_row_content.dart`, `home_rows_logic.dart`, `home_row_view.dart`, `home_rows_editing.dart`
- Modify (test): `test/features/home/home_layout_test.dart`
- Test: `test/features/home/home_friends_watched_test.dart`

**Interfaces:**
- Consumes: Task 1 (`friendsWatched`, `FriendsWatched`, `SocialFeatures.friendsActivity`, `testFriendsWatched`, testi), Task 2 (`friendsWatchedBy`).
- Produces: `HomeRowKind.friendsWatched('friendsWatched')`, `HomeRowGate.friendsActivityOff`, `FriendsWatchedRowContent(List<FriendsWatchedItem> titles)`, `FriendsWatchedItem {item, List<FriendWatcher> by}`, `loadFriendsWatched(api, userId, list)`.

- [ ] **Step 1: i test che falliscono**

`test/features/home/home_friends_watched_test.dart` (stessa impostazione di `home_recommended_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/home/home_layout.dart';
import 'package:wonderflix/features/home/home_providers.dart';
import 'package:wonderflix/features/home/home_row_content.dart';
import 'package:wonderflix/features/home/home_row_view.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/home_fakes.dart';
import '../../support/library_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeLibraryApi library;
  late FakeSocialApi social;
  late FakeSocialAvailability availability;

  setUp(() {
    library = FakeLibraryApi();
    social = FakeSocialApi();
    availability = FakeSocialAvailability(SocialFeatures.none);
  });

  ProviderContainer container() => ProviderContainer.test(
        overrides: homeOverrides(
            library: library, availability: availability, social: social),
        retry: (_, _) => null,
      );

  Future<HomeLayout> layout(ProviderContainer c) {
    c.listen(homeLayoutProvider, (_, _) {});
    return c.read(homeLayoutProvider.future);
  }

  Future<HomeRowContent> row(ProviderContainer c) {
    const key = (kind: HomeRowKind.friendsWatched, language: 'it');
    c.listen(homeRowProvider(key), (_, _) {});
    return c.read(homeRowProvider(key).future);
  }

  const on = SocialFeatures(friends: true, friendsActivity: true);

  test('senza la funzione: riga non disponibile e nessuna chiamata', () async {
    availability = FakeSocialAvailability(const SocialFeatures(friends: true));
    final result = await layout(container());
    expect(result.visible, isNot(contains(HomeRowKind.friendsWatched)));
    expect(social.calls, isNot(contains('friendsWatched')));
    expect(
        homeRowGate(HomeRowKind.friendsWatched, const SocialFeatures(),
            seerrAccount: false),
        HomeRowGate.friendsActivityOff);
  });

  test('con la funzione: la riga c\'è, dopo Consigliati per te', () async {
    availability = FakeSocialAvailability(
        const SocialFeatures(friends: true, recommendations: true, friendsActivity: true));
    final visible = (await layout(container())).visible;
    expect(visible.indexOf(HomeRowKind.friendsWatched),
        visible.indexOf(HomeRowKind.recommended) + 1);
  });

  test('l\'ordine del plugin, senza i titoli che Jellyfin non dà', () async {
    availability = FakeSocialAvailability(on);
    library.itemsById['m2'] = testItem(id: 'm2', name: 'Arrival');
    library.itemsById['m1'] = testItem(id: 'm1', name: 'Dune');
    social.friendsWatchedList = [
      testFriendsWatched('m2', ['Luca']),
      testFriendsWatched('gone', ['Luca']),
      testFriendsWatched('m1', ['Marta', 'Luca']),
    ];
    final content = await row(container()) as FriendsWatchedRowContent;
    expect(content.titles.map((t) => t.item.id), ['m2', 'm1']);
    expect(content.titles.last.by.map((w) => w.name), ['Marta', 'Luca']);
  });

  test('errore del plugin: la riga è in errore (e quindi nascosta)', () async {
    availability = FakeSocialAvailability(on);
    social.nextFailure = SocialFailure.network;
    await expectLater(row(container()), throwsA(anything));
  });

  testWidgets('la card dice chi l\'ha visto', (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: HomeRowView(
          kind: HomeRowKind.friendsWatched,
          content: FriendsWatchedRowContent([
            FriendsWatchedItem(
                item: testItem(id: 'm1', name: 'Dune'),
                by: testFriendsWatched('m1', ['Luca', 'Marta', 'Sara']).by),
          ]),
          animateEntrance: false,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Visti dagli amici'), findsOneWidget);
    expect(find.text('Visto da Luca e altri 2'), findsOneWidget);
  });
}
```

(Importa `social_api.dart` per `SocialFailure`. Se `HomeRowView` nel test vuole provider in più, usa le stesse sostituzioni del test di `RecommendedRowContent` in `home_row_view_test.dart` o in `home_recommended_test.dart`.)

In `test/features/home/home_layout_test.dart`:
- nell'elenco degli id `'friendsWatched'` dopo `'recommended'`;
- nell'elenco delle righe con `fromJellyfin` falso `HomeRowKind.friendsWatched` dopo `HomeRowKind.recommended`.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/home/home_friends_watched_test.dart test/features/home/home_layout_test.dart`
Expected: FAIL (`friendsWatched` non esiste).

- [ ] **Step 3: il codice**

In `home_layout.dart`:
- `HomeRowKind`: `friendsWatched('friendsWatched'),` subito dopo `recommended('recommended'),`;
- `fromJellyfin`: `requests || recommended || friendsWatched || upcomingSeries || upcomingMovies => false,`;
- `HomeRowGate`, dopo `recommendationsOff`:

```dart

  /// Il plugin non ha l'attività degli amici (prima della 1.9.0, o senza
  /// accesso ai watch party).
  friendsActivityOff,
```

- `homeRowGate`, dopo il caso di `recommended`:

```dart
      HomeRowKind.friendsWatched when !features.friendsActivity =>
        HomeRowGate.friendsActivityOff,
```

In `home_row_content.dart`, dopo `RecommendedItem` (import `'../../core/social/activity_models.dart'`):

```dart

/// "Visti dagli amici" (spec O §7.4).
final class FriendsWatchedRowContent extends HomeRowContent {
  const FriendsWatchedRowContent(this.titles);

  final List<FriendsWatchedItem> titles;

  @override
  bool get isEmpty => titles.isEmpty;
}

class FriendsWatchedItem {
  const FriendsWatchedItem({required this.item, required this.by});

  final JellyfinItem item;
  final List<FriendWatcher> by;
}
```

In `home_rows_logic.dart`, dopo `loadRecommended` (import `'../../core/social/activity_models.dart'`):

```dart

/// "Visti dagli amici" (spec O §7.4): gli elementi da Jellyfin nell'ordine
/// del plugin; quelli che Jellyfin non dà si saltano.
Future<List<FriendsWatchedItem>> loadFriendsWatched(
    LibraryApi api, String userId, List<FriendsWatched> watched) async {
  final wanted = watched.take(homeRowLimit).toList();
  if (wanted.isEmpty) return const [];
  final byId = {
    for (final item
        in await api.itemsByIds(userId, [for (final w in wanted) w.itemId]))
      jellyfinIdKey(item.id): item,
  };
  return [
    for (final w in wanted)
      if (byId[jellyfinIdKey(w.itemId)] case final item?)
        FriendsWatchedItem(item: item, by: w.by),
  ];
}
```

In `home_providers.dart` (import `'../../core/social/activity_models.dart'`), in `homeRowProvider` dopo il caso `recommended`:

```dart
    case HomeRowKind.friendsWatched:
      // Come "Consigliati per te": si rilegge a ogni apertura della Home e
      // quando cambiano libreria o dati di visione. Tutti i watch prima
      // dell'attesa.
      ref.watch(libraryRevisionProvider);
      ref.watch(userDataRevisionProvider);
      final userId = ref.watch(currentUserIdProvider);
      final api = ref.watch(libraryApiProvider);
      final social = ref.watch(socialApiProvider);
      final List<FriendsWatched> watched;
      try {
        watched = await social.friendsWatched();
      } catch (error) {
        _log.info('visti dagli amici non disponibili: '
            '${error is SocialException ? error.failure.name : error.runtimeType}');
        rethrow; // la riga resta in errore, quindi nascosta
      }
      return FriendsWatchedRowContent(
          await loadFriendsWatched(api, userId, watched));
```

e in `_libraryRow` aggiungi `friendsWatched` al ramo che lancia (`… || recommended || friendsWatched || requests || …`).

In `home_row_view.dart` (import `'../friends/activity_labels.dart'`):
- in `build`, dopo il caso `RecommendedRowContent`:

```dart
      FriendsWatchedRowContent(:final titles) => _friendsWatched(l, titles),
```

- in `_title`: `HomeRowKind.friendsWatched => l.homeRowFriendsWatched,` dopo `recommended`;
- dopo `_recommended`:

```dart

  /// "Visti dagli amici": chi l'ha visto sotto la locandina (spec O §7.4).
  Widget _friendsWatched(AppLocalizations l, List<FriendsWatchedItem> titles) =>
      _row(l.homeRowFriendsWatched, posterRowHeight, titles.length,
          (context, i) {
        final title = titles[i];
        return PosterCard(
          key: ValueKey('friends-watched-${title.item.id}'),
          item: title.item,
          width: posterWidth,
          heroSource: 'home.${kind.id}.$i',
          subtitle: friendsWatchedBy(l, title.by),
        );
      });
```

In `home_rows_editing.dart`:
- `homeRowName`: `HomeRowKind.friendsWatched => l.homeRowFriendsWatched,` dopo `recommended`;
- `homeRowGateReason`: `HomeRowGate.friendsActivityOff => l.homeRowUnavailableFriendsActivity,`.

Cerca con `grep` altri `switch` su `HomeRowKind` o `HomeRowGate` (per esempio in `lib/features/admin/`) e completali con la stessa regola.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `flutter test test/features/home/ test/features/settings/ test/features/admin/`, `flutter analyze` e la suite intera con `--concurrency=4`.
Expected: PASS.

- [ ] **Step 5: commit**

```powershell
git checkout -- windows/flutter/
git add lib test
git commit -m "feat(app): watched by friends Home row"
```

---

## Gruppo C — chiusura

### Task 5: versione, spec e build

**Files:**
- Modify: `pubspec.yaml`, `docs/superpowers/specs/2026-10-13-wonderflix-cosa-guardano-amici-design.md`, `docs/superpowers/plans/2026-10-13-wonderflix-21b-attivita-amici-app.md` (solo "Dalle review dei gruppi", se servono)

- [ ] **Step 1: versione**

`pubspec.yaml`: `version: 0.15.0` (lo stesso numero di build della riga di oggi, se c'è un `+N`).

- [ ] **Step 2: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "… piano 21b realizzato (`docs/superpowers/plans/2026-10-13-wonderflix-21b-attivita-amici-app.md`), da provare con l'utente".
- **§7.1:** la funzione vale solo con l'accesso ai watch party (decisione 7).
- **§7.2:** l'invito parte dentro la registrazione del party e non lo ferma (decisione 1); la posizione in `start:` (decisione 2); quando il tasto non compare (decisione 3); il 409 rilegge l'elenco (decisione 4).
- **§7.3:** dove sta l'interruttore (decisione 5).
- **§7.4:** "Visto da …" con una funzione sua (decisione 6).
- Ogni altra differenza venuta fuori durante i task, con il motivo.

- [ ] **Step 3: build**

`flutter analyze`, `flutter test --concurrency=4`, poi la build di prova:

```powershell
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

(Il worktree non ha `config/wonderflix.json`: il controllore lo copia dal checkout principale prima del Task 5. Senza, la build parte ma l'app dice "Configurazione mancante".)

- [ ] **Step 4: commit**

```powershell
git checkout -- windows/flutter/
git add pubspec.yaml docs
git commit -m "chore: app 0.15.0 and spec aligned with plan 21b"
```

### Task 6: STOP — prova con l'utente (lo fa il controllore)

Dopo la review finale del branch e i suoi ritocchi:
1. Build di release nel worktree (`build/windows/x64/runner/Release/wonderflix.exe`).
2. L'utente prova con due istanze (`WONDERFLIX_PROFILE=b`), due utenti amici, sul plugin 1.9.0 di prova:
   - un amico guarda un film: nel pannello Amici dell'altro "Sta guardando …" (entro pochi secondi dall'inizio); poi un episodio, con "· S… E…"; allo stop torna "Online";
   - **Guarda insieme** con l'amico a metà: party privato dallo stesso punto, l'invito arriva all'amico, che entra;
   - l'interruttore spento: lo stato sparisce subito dall'altra parte, e la riga "Visti dagli amici" dell'altro si svuota alla prossima apertura della Home; riacceso, si torna a vedere;
   - una visione oltre 5 minuti: il titolo compare in "Visti dagli amici" dell'altro (se non l'ha già visto), con "Visto da …";
   - l'app 0.14.0 (installata) con il plugin 1.9.0: amici e Home come prima.
3. Con l'ok dell'utente: merge fast-forward su `main` e push (memoria `wonderflix-workflow`; prima `git fetch` e rebase se `origin/main` è avanti).

## Release (con l'OK dell'utente a ogni passo)

1. **Plugin 1.9.0:**
   - tag `watch-party-plugin-v1.9.0` → pre-release con lo zip (la `releases/latest` resta l'app);
   - voce 1.9.0.0 nel `manifest.json`;
   - sul server, quando nessuno guarda: la build di prova va in `~/wfwp-backup/1.9.0.0-prova`, poi riavvio, installazione dal Catalogo e di nuovo riavvio;
   - nel log "Loaded plugin … 1.9.0.0", e l'md5 della dll uguale a quello della release.
2. **App 0.15.0 obbligatoria:** `chore: release 0.15.0`, tag `v0.15.0`, la pipeline `Release`, le note in italiano scritte nella bozza **con** `<!-- wonderflix:min-version=0.15.0 -->`; la pubblica l'utente.
3. **Annuncio dell'admin** (spec §3.1), con l'ok dell'utente sul testo: `POST WonderFlixWatchParty/Inbox/Announcements` con un testo breve che spiega "Sta guardando", la riga "Visti dagli amici" e dove si spegne (Impostazioni → Account → "Mostra agli amici cosa guardo").
4. **Alla fine**, in `docs/IDEE.md`: l'idea 5 esce dalla lista e tra le fatte c'è "Spec O — cosa guardano gli amici (plugin 1.9.0, app 0.15.0)"; lo stato della spec diventa "Realizzata" con i dettagli della release.

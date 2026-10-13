# WonderFlix — Piano 20b: consigli tra amici, app 0.14.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte app dello Spec N:
- il client dei consigli (`SocialApi`), la funzione `recommendations`, i testi;
- la voce "X ti consiglia Y" nella cassetta;
- il pannello laterale "Consiglia a…" dal dettaglio di film e serie;
- la riga "Consigliati per te" nella Home, con i messaggi e "Non mi interessa" nell'anteprima delle card;
- app 0.14.0, provata con l'utente sul plugin 1.8.0 di prova (piano 20a).

**Architecture:** il client sta in `lib/core/social/` come il resto del plugin (`SocialApi` lancia solo `SocialException`). I widget nuovi stanno in `lib/features/recommendations/`. La riga della Home segue la strada delle righe del plugin (`HomeRowKind`, `homeRowGate`, `homeRowProvider`, `HomeRowContent`, `HomeRowView`). L'anteprima delle card riceve un'aggiunta facoltativa (`CardPreviewExtra`: righe di nota e un pulsante ×), usata solo da questa riga.

**Tech Stack:** Flutter 3.47.5 / Dart, flutter_riverpod 3 (Notifier), go_router 18, lucide_icons_flutter, flutter_test.

**Spec:** `docs/superpowers/specs/2026-10-12-wonderflix-consigli-design.md` (§3, §7, §8, §9, §11.2, §13). Il plugin 1.8.0 (piano 20a) è sul server come build di prova.

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 6):
1. **Voce della cassetta senza controllo "Non disponibile":** la voce apre sempre il dettaglio; se l'utente non vede più il titolo, è la pagina del dettaglio a mostrare il suo errore. Controllare ogni voce vorrebbe una chiamata a Jellyfin per voce a ogni apertura della cassetta.
2. **"Non mi interessa" senza animazione di uscita:** nell'app non c'è un modo di togliere una card da una riga con animazione (le righe sono `ListView` semplici). La card sparisce subito: il titolo entra in un insieme di "tolti" (`recommendationDismissalsProvider`) prima della chiamata al plugin, e torna se la chiamata non riesce.
3. **La riga si rilegge a ogni apertura della Home:** niente `keepFor` (le altre righe del plugin restano in memoria 5 minuti).
4. **Al massimo 30 amici per invio** (`recommendMaxRecipients`): il plugin accetta fino a 50 id ma i destinatari sono 30 all'ora (ruling del piano 20a). Raggiunti i 30, gli altri amici si spengono e compare "Al massimo 30 amici alla volta".
5. **Il pulsante "Consiglia a…" va dopo i due tondi** (La mia lista e Visto), non tra loro: i tondi restano vicini.
6. **Un solo testo con il plurale** per l'esito: `recommendSent` = "Consiglio inviato" (1) / "Consiglio inviato a N amici".
7. **La funzione `recommendations` vale solo con l'accesso ai watch party** (`_canJoin`), come gli amici: il plugin usa la stessa policy.

## Global Constraints

- App **0.14.0** (`pubspec.yaml`), non obbligatoria.
- Plugin: endpoint `GET WonderFlixWatchParty/Recommendations/Targets?itemId=` → `{Friends: [{UserId, Name, Online, CanSee}]}`; `POST WonderFlixWatchParty/Recommendations` `{ItemId, To, Message}` → `{Sent}`; `GET WonderFlixWatchParty/Recommendations` → `{Items: [{ItemId, From: [{UserId, Name, Message?, CreatedAt}]}]}`; `DELETE WonderFlixWatchParty/Recommendations/{itemId}` → 204. 400 → `SocialFailure.forbidden`, 429 → `SocialFailure.rateLimited`.
- Funzione del plugin in `Info`: `recommendations`.
- Voce della cassetta `Type: "Recommendation"` con `ItemId`, `FromUserId`, `FromName`, `Title`, `Text` (facoltativo).
- Id della riga della Home: `recommended`, subito dopo `nextUp`.
- Messaggio facoltativo, al massimo 200 caratteri; al massimo 30 amici per invio.
- Pannello laterale largo 360 (`ShellSidePanel`), uno alla volta con Amici e Notifiche; nell'app non ci sono dialog.
- Testi it/en (§9 della spec, con la decisione 6); i testi non danno per scontato il genere di nessuno.
- Icone solo `LucideIcons`, colori `WfColors`; `clock.now()`, mai `DateTime.now()`.

## Review Focus

1. **Invio che non arriva a nessuno** (`Sent` = 0: tutti saltati dal plugin, per esempio perché i permessi sono cambiati): l'utente deve vedere "Consiglio non inviato" e il pannello resta aperto, non "Consiglio inviato". Test: Task 5 (`nessun destinatario valido: non inviato, il pannello resta`).
2. **Doppio clic su Invia** durante l'invio: una sola chiamata. Test: Task 5 (`Invia spento durante l'invio`).
3. **Titolo consigliato che Jellyfin non restituisce più** (cancellato o non più visibile): la card non c'è, le altre sì, nell'ordine del plugin. Test: Task 4 (`la riga tiene l'ordine del plugin e salta i titoli che Jellyfin non dà`).
4. **"Non mi interessa" che non riesce:** la card torna e compare "Non riuscito: riprova". Test: Task 4 (`Non mi interessa non riuscito: la card torna`).
5. **Plugin vecchio (senza `recommendations`):** niente pulsante nel dettaglio, riga non disponibile con il motivo, nessuna chiamata. Test: Task 4 (`senza la funzione: riga non disponibile e nessuna chiamata`) e Task 5 (`niente pulsante senza la funzione o senza amici`).

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
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-20b`). La shell può partire nel checkout principale: fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - **Messaggi di commit:** su una riga sola e senza virgolette, `git commit -m "feat(app): …"`.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit** `flutter analyze` senza problemi e la suite intera, tutta verde, con **`flutter test --concurrency=4`**. Con i 16 processi predefiniti il PC si è riavviato due volte il 2026-10-10;
  - la base di partenza è di **2869** test verdi (`main` `eb252b2`, verificato il 2026-10-13 con `--concurrency=4`).
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
  - nei log mai titoli, messaggi o nomi: solo il tipo dell'errore o il nome del `SocialFailure`.
- **Provider e test:**
  - nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`; i container dei test hanno `retry: (_, _) => null`;
  - in un provider, tutti i `ref.watch` stanno prima del primo `await`;
  - **spinner e `pumpAndSettle`:** il carosello e gli shimmer non si fermano mai. Nei test della Home usa `pump()` e `pump(durata)`, non `pumpAndSettle`.
- **Se il codice del piano ha un errore** (analyzer, import, un dettaglio di un test, un'API con firma diversa, uno `switch` esaustivo da completare in un file non elencato):
  - correggilo in modo minimo, nello spirito del piano, e segnalalo;
  - preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-13 sul codice di `main` (`eb252b2`).

- **`SocialApi`** (`lib/core/social/social_api.dart`): ogni metodo passa da `_call`, che traduce gli errori in `SocialException(SocialFailure)`: 404 → `unavailable`, 400/401/403 → `forbidden`, 409 → `conflict`, 429 → `rateLimited`, il resto (rete, forma inattesa) → `network`. Le chiamate passano `quietStatuses: _quiet`. `asJsonMap` (in `jellyfin_http.dart`) e `jsonList` (in `../jellyfin/json_fields.dart`) per leggere i corpi.
- **`FakeSocialApi`** (`test/support/social_fakes.dart`) implementa `SocialApi`: ogni metodo nuovo va aggiunto lì. `nextFailure` lancia alla prossima chiamata (tranne `info`) e si azzera; `calls` registra stringhe.
- **`SocialFeatures`** (`lib/features/social/social_providers.dart`): un campo per funzione, con costruttore, `==`, `hashCode` e `toString`; `SocialAvailability.refresh()` le legge da `info.features`. `PluginFeatures` (in `social_models.dart`) ha le costanti. `describePluginFeatures` (in `lib/features/settings/diagnostics.dart`) le elenca per la diagnostica.
- **Cassetta:** `InboxEntry` è una classe `sealed` (`lib/core/social/inbox_models.dart`); `inboxEntryFromJson` restituisce `null` per i tipi sconosciuti. `lib/features/inbox/inbox_panel.dart` ha due `switch` esaustivi sulle voci (miniatura e contenuto, in `_EntryTile`). Per aprire un titolo dalla cassetta: `ref.read(shellPanelProvider.notifier).close(); openItemById(context, itemId);`. Miniatura di un titolo noto solo per id: `ref.watch(imageUrlsProvider).primaryOf(id)` in un `WfImage` 40×60 con angoli da 4.
- **Pannelli:** `ShellPanel { none, friends, inbox }` e `ShellPanelController` (`lib/app/shell_panels.dart`, `open`/`close`/`toggle`, `switch` esaustivo in `open`); `ShellSidePanel(open:, onClose:, scrimKey:, child:, onEscape:)` (`lib/ui/shell_side_panel.dart`); i "host" sono `Positioned.fill` in fondo allo `Stack` di `lib/app/app_shell.dart`, dopo `InboxPanelHost`. Esc e i tasti indietro con un pannello aperto chiudono il pannello (`back_navigation.dart` guarda solo `!= ShellPanel.none`).
- **Dettaglio:** `DetailHeader` (`lib/features/detail/detail_header.dart`) costruisce la fila dei pulsanti in un `Wrap` (`WfButton.secondary(label:, icon:, onPressed:)`, `WfIconToggle`); `item.kind` è `ItemKind.movie`/`series`/`episode`…; per una serie `DetailHeader.item` è la serie.
- **Amici:** `friendsControllerProvider` (stato `FriendsState` con `snapshot.friends`); `MemberAvatar(name:, userId:)` in `lib/features/watch_party/party_badge.dart`; `WfColors.online` per il pallino.
- **Home:** `HomeRowKind` (con `fromJellyfin`), `HomeRowGate` e `homeRowGate` in `lib/features/home/home_layout.dart`; `homeRowProvider` e `_libraryRow` (con un `switch` esaustivo che lancia per le righe non della libreria) in `home_providers.dart`; `HomeRowContent` sealed in `home_row_content.dart`; `HomeRowView` con due `switch` (`build` e `_title`) in `home_row_view.dart`; `homeRowName` e `homeRowGateReason` in `home_rows_editing.dart`; `homeRowLimit = 20` e `loadContinueSaga` (modello per `itemsByIds` + `jellyfinIdKey`) in `home_rows_logic.dart`. Una riga vuota non si mostra. `LibraryApi.itemsByIds(userId, ids)` dà gli elementi in ordine qualunque e salta quelli che l'utente non vede.
- **Anteprima delle card:** `CardPreviewHost(item:, heroSource:, child:)` (`lib/ui/card_preview_host.dart`) calcola il riquadro con `previewRect(card:, overlay:)` e monta `CardPreview(item:, heroTag:, body:, onPlay:, onDetails:)` (`lib/ui/card_preview.dart`); il corpo sotto l'immagine è alto `previewBodyHeight` (124); i pulsanti tondi privati `_RoundButton` sono da 36. `_hide({bool immediately = false, bool dismiss = false})` chiude l'anteprima. `PosterCard` (`lib/ui/poster_card.dart`) mostra nome e anno e si avvolge in `CardPreviewHost`.
- **Avvisi:** `ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(…)))`; prendi il messenger prima di un `await`.
- **Test:** `pumpApp(tester, child, overrides:)` (`test/support/pump_app.dart`, finestra 1440×900, animazioni ridotte, lingua it); `socialTestOverrides(api, features:)` e `FakeSocialAvailability` in `social_fakes.dart`; `homeOverrides(library:, home:, availability:, …)` in `home_fakes.dart`; `FakeLibraryApi` con `itemsById` e `itemsByIdsCalls`; `testItem(id:, name:, kind:, year:)` in `library_fakes.dart`; i test dei testi stanno in `test/app/l10n_planXX_test.dart` (lingue `it` ed `en` e stesse chiavi nei due ARB).

## File

| File | Responsabilità |
|---|---|
| `lib/core/social/recommendation_models.dart` | `RecommendationTarget`, `RecommendationSender`, `Recommendation` |
| `lib/core/social/social_api.dart`, `social_models.dart` (modifiche) | i 4 endpoint, `PluginFeatures.recommendations` |
| `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart` (modifiche) | `SocialFeatures.recommendations`, diagnostica |
| `l10n/app_it.arb`, `l10n/app_en.arb` (modifiche) | i testi |
| `lib/core/social/inbox_models.dart`, `lib/features/inbox/inbox_panel.dart` (modifiche) | voce `RecommendationEntry` |
| `lib/ui/card_preview.dart`, `lib/ui/card_preview_host.dart`, `lib/ui/poster_card.dart` (modifiche) | `CardPreviewExtra`, sottotitolo della locandina |
| `lib/features/recommendations/recommendation_labels.dart` | "Da Luca e Marta", le note dei messaggi |
| `lib/features/recommendations/recommendation_dismissals.dart` | "Non mi interessa" con l'insieme dei tolti |
| `lib/features/home/*` (modifiche) | riga `recommended` |
| `lib/features/recommendations/recommend_panel.dart` | soggetto del consiglio, amici, pannello, host |
| `lib/app/shell_panels.dart`, `lib/app/app_shell.dart`, `lib/features/detail/detail_header.dart` (modifiche) | `ShellPanel.recommend`, host nella shell, pulsante |

---

## Gruppo A — client e cassetta

### Task 1: client, funzione e testi

**Files:**
- Create: `lib/core/social/recommendation_models.dart`
- Modify: `lib/core/social/social_api.dart`, `lib/core/social/social_models.dart`, `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`
- Modify (test): `test/support/social_fakes.dart`
- Test: `test/core/social/recommendation_api_test.dart`, `test/features/social/social_providers_test.dart` (un test in più), `test/app/l10n_plan20b_test.dart`

**Interfaces:**
- Produces:
  - `class RecommendationTarget { userId, name, online, canSee }`, `class RecommendationSender { userId, name, String? message, DateTime createdAt }`, `class Recommendation { itemId, List<RecommendationSender> from }`, ognuna con `fromJson`;
  - `SocialApi.recommendationTargets(String itemId) → Future<List<RecommendationTarget>>`, `recommend(String itemId, List<String> userIds, String? message) → Future<int>` (i destinatari raggiunti), `recommendations() → Future<List<Recommendation>>`, `dismissRecommendation(String itemId) → Future<void>`;
  - `PluginFeatures.recommendations = 'recommendations'`, `SocialFeatures.recommendations` (bool);
  - in `FakeSocialApi`: `recommendationTargetsById` (mappa), `recommendationsList`, `recommendSent` (`null` = tutti gli scelti), `recommendGate` (Completer), e i 4 metodi, che registrano `targets ID`, `recommend ID ID1,ID2 MESSAGGIO|-`, `recommendations`, `dismiss ID`;
  - le chiavi ARB della tabella dello Step 3.

- [ ] **Step 1: i test che falliscono**

`test/core/social/recommendation_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/social/social_api.dart';

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

  test('amici a cui consigliare', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Friends': [
            {'UserId': 'u2', 'Name': 'Luigi', 'Online': true, 'CanSee': false},
          ],
        });
    final targets = await api.recommendationTargets('m1');
    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.path, '/WonderFlixWatchParty/Recommendations/Targets');
    expect(request.queryParameters['itemId'], 'm1');
    expect(targets.single.name, 'Luigi');
    expect(targets.single.online, isTrue);
    expect(targets.single.canSee, isFalse);
  });

  test('consiglio: corpo e destinatari raggiunti', () async {
    adapter.handler = (_) => const FakeResponse(200, {'Sent': 2});
    expect(await api.recommend('m1', ['u2', 'u3'], 'da vedere'), 2);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/WonderFlixWatchParty/Recommendations');
    expect(request.data, {
      'ItemId': 'm1',
      'To': ['u2', 'u3'],
      'Message': 'da vedere',
    });
  });

  test('consigli ricevuti, anche senza messaggio', () async {
    adapter.handler = (_) => const FakeResponse(200, {
          'Items': [
            {
              'ItemId': 'm1',
              'From': [
                {
                  'UserId': 'u2',
                  'Name': 'Luigi',
                  'Message': 'da vedere',
                  'CreatedAt': '2026-10-12T20:00:00Z',
                },
                {'UserId': 'u3', 'Name': 'Peach', 'CreatedAt': '2026-10-12T19:00:00Z'},
              ],
            },
          ],
        });
    final items = await api.recommendations();
    expect(adapter.requests.single.path, '/WonderFlixWatchParty/Recommendations');
    expect(items.single.itemId, 'm1');
    expect(items.single.from.map((s) => s.name), ['Luigi', 'Peach']);
    expect(items.single.from.first.message, 'da vedere');
    expect(items.single.from.last.message, isNull);
    expect(items.single.from.first.createdAt, DateTime.utc(2026, 10, 12, 20));
  });

  test('Non mi interessa', () async {
    await api.dismissRecommendation('m1');
    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/WonderFlixWatchParty/Recommendations/m1');
  });

  test('400 e 429', () async {
    adapter.handler = (_) => const FakeResponse(400);
    await expectLater(api.recommend('m1', ['u2'], null),
        throwsA(isA<SocialException>().having((e) => e.failure, 'failure', SocialFailure.forbidden)));
    adapter.handler = (_) => const FakeResponse(429);
    await expectLater(api.recommend('m1', ['u2'], null),
        throwsA(isA<SocialException>().having((e) => e.failure, 'failure', SocialFailure.rateLimited)));
  });
}
```

(Se `FakeAdapter` registra la richiesta con nomi diversi da `method`, `path`, `queryParameters`, `data`, usa quelli di `test/support/fake_adapter.dart`: il controllo è su metodo, percorso, parametro e corpo.)

In `test/features/social/social_providers_test.dart`, dopo il test `Info con la cassetta: funzione inbox`:

```dart
  test('Info con i consigli: funzione recommendations, solo con i watch party',
      () async {
    api.install(features: const {
      PluginFeatures.friends,
      PluginFeatures.recommendations,
    });
    final c = container();
    await pumpEventQueue();
    expect(c.read(socialAvailabilityProvider),
        const SocialFeatures(friends: true, recommendations: true));

    final noParty = container(
        session: const SessionSignedIn(JellyfinUser(
            id: 'u1', name: 'Mario', syncPlayAccess: SyncPlayAccess.none)));
    await pumpEventQueue();
    expect(noParty.read(socialAvailabilityProvider).recommendations, isFalse);
  });
```

`test/app/l10n_plan20b_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

void main() {
  test('stringhe del Piano 20b', () {
    final it = lookupAppLocalizations(const Locale('it'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(it.recommendButton, 'Consiglia a…');
    expect(it.recommendCannotSee, 'Non può vederlo');
    expect(it.recommendSent(1), 'Consiglio inviato');
    expect(it.recommendSent(3), 'Consiglio inviato a 3 amici');
    expect(it.recommendMaxReached(30), 'Al massimo 30 amici alla volta');
    expect(it.homeRowRecommended, 'Consigliati per te');
    expect(it.recommendedFromOne('Luca'), 'Da Luca');
    expect(it.recommendedFromTwo('Luca', 'Marta'), 'Da Luca e Marta');
    expect(it.recommendedFromMany('Luca', 2), 'Da Luca e altri 2');
    expect(it.recommendationQuote('Luca', 'da vedere'), 'Luca: «da vedere»');
    expect(it.inboxRecommendation('Luca', 'Dune (2021)'), 'Luca ti consiglia Dune (2021)');
    expect(it.homeRowUnavailableRecommendations, 'Serve il plugin 1.8.0');
    expect(en.recommendButton, 'Recommend to…');
    expect(en.recommendSent(1), 'Recommendation sent');
    expect(en.recommendSent(3), 'Recommendation sent to 3 friends');
    expect(en.recommendedFromMany('Luca', 2), 'From Luca and 2 others');
    expect(en.inboxRecommendation('Luca', 'Dune (2021)'), 'Luca recommends Dune (2021)');
  });
}
```

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/social/recommendation_api_test.dart test/features/social/social_providers_test.dart test/app/l10n_plan20b_test.dart`
Expected: FAIL (metodi, campi e testi mancanti).

- [ ] **Step 3: il codice**

`lib/core/social/recommendation_models.dart`:

```dart
/// Modelli dei consigli tra amici (spec N §6.2), come li manda il plugin.
library;

/// Un amico nel pannello "Consiglia a…": spento se non può vedere il titolo.
class RecommendationTarget {
  const RecommendationTarget({
    required this.userId,
    required this.name,
    required this.online,
    required this.canSee,
  });

  factory RecommendationTarget.fromJson(Map<String, dynamic> json) =>
      RecommendationTarget(
        userId: json['UserId'] as String,
        name: json['Name'] as String,
        online: json['Online'] as bool? ?? false,
        canSee: json['CanSee'] as bool? ?? false,
      );

  final String userId;
  final String name;
  final bool online;
  final bool canSee;
}

/// Chi ha consigliato un titolo, con il suo messaggio (`null` se nessuno).
class RecommendationSender {
  const RecommendationSender({
    required this.userId,
    required this.name,
    required this.createdAt,
    this.message,
  });

  factory RecommendationSender.fromJson(Map<String, dynamic> json) {
    final message = json['Message'] as String?;
    return RecommendationSender(
      userId: json['UserId'] as String,
      name: json['Name'] as String,
      message: message == null || message.isEmpty ? null : message,
      createdAt: DateTime.parse(json['CreatedAt'] as String).toUtc(),
    );
  }

  final String userId;
  final String name;
  final String? message;

  /// In UTC.
  final DateTime createdAt;
}

/// Un titolo consigliato all'utente, con i mittenti dal più recente.
class Recommendation {
  const Recommendation({required this.itemId, required this.from});

  factory Recommendation.fromJson(Map<String, dynamic> json) => Recommendation(
        itemId: json['ItemId'] as String,
        from: [
          for (final raw in json['From'] as List? ?? const [])
            RecommendationSender.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final String itemId;
  final List<RecommendationSender> from;
}
```

In `lib/core/social/social_api.dart`:
- import `'../jellyfin/json_fields.dart'` e `'recommendation_models.dart'`;
- dopo `clearInbox`:

```dart

  /// Gli amici a cui si può consigliare [itemId], con online e accesso al
  /// titolo (spec N §6.2).
  Future<List<RecommendationTarget>> recommendationTargets(String itemId) =>
      _call(() async => jsonList(
          asJsonMap(await _http.get('$_base/Recommendations/Targets',
              query: {'itemId': itemId}, quietStatuses: _quiet))['Friends'],
          RecommendationTarget.fromJson));

  /// Consiglia [itemId] agli amici [userIds]; risponde a quanti è arrivato.
  Future<int> recommend(String itemId, List<String> userIds, String? message) =>
      _call(() async => (asJsonMap(await _http.post('$_base/Recommendations',
              body: {'ItemId': itemId, 'To': userIds, 'Message': message},
              quietStatuses: _quiet))['Sent'] as num)
          .toInt());

  /// I consigli ricevuti ancora validi, dal più recente.
  Future<List<Recommendation>> recommendations() => _call(() async => jsonList(
      asJsonMap(await _http.get('$_base/Recommendations', quietStatuses: _quiet))[
          'Items'],
      Recommendation.fromJson));

  /// "Non mi interessa": il plugin risponde 204 anche se il titolo non c'è.
  Future<void> dismissRecommendation(String itemId) => _call(() =>
      _http.delete('$_base/Recommendations/$itemId', quietStatuses: _quiet));
```

In `lib/core/social/social_models.dart`, in `PluginFeatures` dopo `upcomingMovies`:

```dart

  /// I consigli tra amici (spec N §6.6).
  static const recommendations = 'recommendations';
```

In `lib/features/social/social_providers.dart`, `SocialFeatures`:
- costruttore: `this.recommendations = false,` dopo `this.upcomingMovies = false,`;
- campo, dopo `upcomingMovies`:

```dart

  /// I consigli tra amici (spec N §7.1): come gli amici, solo con l'accesso
  /// ai watch party (piano 20b, decisione 7).
  final bool recommendations;
```

- `==`: `other.recommendations == recommendations &&` prima di `other.known == known`;
- `hashCode`: `recommendations,` prima di `known`;
- `toString`: `'upcomingSeries: $upcomingSeries, upcomingMovies: $upcomingMovies, recommendations: $recommendations, '`;
- in `refresh()`, nel `SocialFeatures(...)` passato ad `_apply`: `recommendations: _canJoin && info.features.contains(PluginFeatures.recommendations),`.

In `lib/features/settings/diagnostics.dart`, in `describePluginFeatures`: `if (features.contains(PluginFeatures.recommendations)) 'consigli',` dopo `'notifiche'`.

In `test/support/social_fakes.dart`, import `package:wonderflix/core/social/recommendation_models.dart` e, prima della `}` di chiusura di `FakeSocialApi`:

```dart

  /// Risposte di [recommendationTargets], per id del titolo.
  final recommendationTargetsById = <String, List<RecommendationTarget>>{};

  /// Risposta di [recommendations].
  List<Recommendation> recommendationsList = [];

  /// Destinatari raggiunti da [recommend]; `null` = tutti quelli scelti.
  int? recommendSent;

  /// Se valorizzato, [recommend] aspetta che si completi.
  Completer<void>? recommendGate;

  @override
  Future<List<RecommendationTarget>> recommendationTargets(String itemId) async {
    calls.add('targets $itemId');
    _fail();
    return recommendationTargetsById[itemId] ?? const [];
  }

  @override
  Future<int> recommend(String itemId, List<String> userIds, String? message) async {
    calls.add('recommend $itemId ${userIds.join(',')} ${message ?? '-'}');
    await recommendGate?.future;
    _fail();
    return recommendSent ?? userIds.length;
  }

  @override
  Future<List<Recommendation>> recommendations() async {
    calls.add('recommendations');
    _fail();
    return recommendationsList;
  }

  @override
  Future<void> dismissRecommendation(String itemId) async {
    calls.add('dismiss $itemId');
    _fail();
  }
```

E in fondo al file, accanto alle altre fabbriche:

```dart
/// Un amico nel pannello dei consigli.
RecommendationTarget testTarget(String userId, String name,
        {bool online = false, bool canSee = true}) =>
    RecommendationTarget(userId: userId, name: name, online: online, canSee: canSee);

/// Un consiglio ricevuto: [itemId] da questi mittenti (nome e messaggio).
Recommendation testRecommendation(String itemId,
        List<(String name, String? message)> from) =>
    Recommendation(itemId: itemId, from: [
      for (final (i, (name, message)) in from.indexed)
        RecommendationSender(
          userId: 'u${i + 10}',
          name: name,
          message: message,
          createdAt: DateTime.utc(2026, 10, 12, 20 - i),
        ),
    ]);
```

ARB: in `l10n/app_it.arb` e `l10n/app_en.arb`, in fondo (prima della `}` finale), le chiavi seguenti con i loro `@`:

| Chiave | it | en | Segnaposti |
|---|---|---|---|
| `recommendButton` | Consiglia a… | Recommend to… | |
| `recommendPanelTitle` | Consiglia a… | Recommend to… | |
| `recommendCannotSee` | Non può vederlo | Can't watch it | |
| `recommendMessageHint` | Aggiungi un messaggio (facoltativo) | Add a message (optional) | |
| `recommendSend` | Invia | Send | |
| `recommendSent` | `{count, plural, =1{Consiglio inviato} other{Consiglio inviato a {count} amici}}` | `{count, plural, =1{Recommendation sent} other{Recommendation sent to {count} friends}}` | `count` int |
| `recommendNotSent` | Consiglio non inviato | Recommendation not sent | |
| `recommendRateLimited` | Troppi consigli: riprova più tardi | Too many recommendations: try again later | |
| `recommendTargetsError` | Impossibile caricare gli amici | Couldn't load your friends | |
| `recommendMaxReached` | Al massimo {count} amici alla volta | At most {count} friends at a time | `count` int |
| `homeRowRecommended` | Consigliati per te | Recommended for you | |
| `recommendedFromOne` | Da {name} | From {name} | `name` String |
| `recommendedFromTwo` | Da {first} e {second} | From {first} and {second} | `first`, `second` String |
| `recommendedFromMany` | Da {name} e altri {count} | From {name} and {count} others | `name` String, `count` int |
| `recommendationQuote` | {name}: «{message}» | {name}: “{message}” | `name`, `message` String |
| `recommendDismiss` | Non mi interessa | Not interested | |
| `recommendDismissFailed` | Non riuscito: riprova | Didn't work: try again | |
| `inboxRecommendation` | {name} ti consiglia {title} | {name} recommends {title} | `name`, `title` String |
| `homeRowUnavailableRecommendations` | Serve il plugin 1.8.0 | Needs plugin 1.8.0 | |

Esempio di forma (come le chiavi che ci sono già):

```json
  "recommendSent": "{count, plural, =1{Consiglio inviato} other{Consiglio inviato a {count} amici}}",
  "@recommendSent": {"placeholders": {"count": {"type": "int"}}},
```

Poi `flutter gen-l10n`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `flutter analyze` e `flutter test --concurrency=4`.
Expected: PASS; analyze pulito; suite verde.

- [ ] **Step 5: commit**

```powershell
git add lib l10n test
git commit -m "feat(app): recommendations client, plugin feature and texts"
```

---

### Task 2: la voce nella cassetta

**Files:**
- Modify: `lib/core/social/inbox_models.dart`, `lib/features/inbox/inbox_panel.dart`
- Modify (test): `test/support/social_fakes.dart`
- Test: `test/core/social/inbox_models_test.dart` (un test in più), `test/features/inbox/inbox_recommendation_test.dart`

**Interfaces:**
- Consumes: le chiavi ARB del Task 1 (`inboxRecommendation`, `recommendationQuote`).
- Produces: `final class RecommendationEntry extends InboxEntry { itemId, fromName, title, String? text }`; `testRecommendationEntry(...)` in `social_fakes.dart`.

- [ ] **Step 1: i test che falliscono**

In `test/core/social/inbox_models_test.dart`, nel `main` (aggiungi l'import di `inbox_models.dart` se manca):

```dart
  test('voce Recommendation, con e senza messaggio', () {
    final entry = inboxEntryFromJson({
      'Id': 'r1',
      'Seq': 4,
      'Type': 'Recommendation',
      'CreatedAt': '2026-10-12T20:00:00Z',
      'Read': false,
      'ItemId': 'm1',
      'FromUserId': 'u2',
      'FromName': 'Luigi',
      'Title': 'Dune (2021)',
      'Text': 'da vedere',
    })! as RecommendationEntry;
    expect(entry.itemId, 'm1');
    expect(entry.fromName, 'Luigi');
    expect(entry.title, 'Dune (2021)');
    expect(entry.text, 'da vedere');

    final bare = inboxEntryFromJson({
      'Id': 'r2',
      'Seq': 5,
      'Type': 'Recommendation',
      'CreatedAt': '2026-10-12T20:00:00Z',
      'ItemId': 'm1',
      'FromName': 'Luigi',
      'Title': 'Dune',
    })! as RecommendationEntry;
    expect(bare.text, isNull);
  });
```

In `test/support/social_fakes.dart`, accanto a `testInvite`:

```dart
/// Un consiglio nella cassetta: Luigi consiglia "Dune (2021)", titolo `m1`.
RecommendationEntry testRecommendationEntry({
  String id = 'r1',
  int seq = 1,
  bool read = false,
  String itemId = 'm1',
  String fromName = 'Luigi',
  String title = 'Dune (2021)',
  String? text = 'da vedere',
}) =>
    RecommendationEntry(
      id: id,
      seq: seq,
      createdAt: DateTime.utc(2026, 10, 12, 20),
      read: read,
      itemId: itemId,
      fromName: fromName,
      title: title,
      text: text,
    );
```

`test/features/inbox/inbox_recommendation_test.dart`: prendi come modello `test/features/inbox/inbox_new_titles_navigation_test.dart` (che monta la shell con il router, apre la cassetta e clicca una riga che apre `/item/ID`) e scrivi due test con la sua stessa impalcatura:

```dart
  testWidgets('consiglio: chi, cosa, messaggio; il clic apre il titolo e chiude il pannello',
      (tester) async {
    api.inboxSnapshot = InboxSnapshot(entries: [testRecommendationEntry()], unread: 1);
    // … monta la shell e apri la cassetta come nel file di modello …
    expect(find.textContaining('Luigi ti consiglia Dune (2021)'), findsOneWidget);
    expect(find.text('«da vedere»'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inbox-recommendation-r1')));
    await tester.pumpAndSettle();
    // … verifica che il percorso sia /item/m1 e che il pannello sia chiuso,
    // come fa il file di modello …
  });

  testWidgets('consiglio senza messaggio: niente riga del messaggio', (tester) async {
    api.inboxSnapshot = InboxSnapshot(
        entries: [testRecommendationEntry(text: null)], unread: 1);
    // … monta e apri come sopra …
    expect(find.textContaining('Luigi ti consiglia'), findsOneWidget);
    expect(find.textContaining('«'), findsNothing);
  });
```

I commenti `// …` indicano le righe da copiare dal file di modello (montaggio, apertura del pannello, controllo del percorso): copiale, non lasciarle come commenti.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/core/social/inbox_models_test.dart test/features/inbox/inbox_recommendation_test.dart`
Expected: FAIL (`RecommendationEntry` mancante).

- [ ] **Step 3: il codice**

In `lib/core/social/inbox_models.dart`, dopo `ContactReminderEntry`:

```dart

/// Un amico consiglia un film o una serie (spec N §7.5).
final class RecommendationEntry extends InboxEntry {
  const RecommendationEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    required this.itemId,
    required this.fromName,
    required this.title,
    this.text,
  });

  /// Il film o la serie: anche la locandina.
  final String itemId;
  final String fromName;

  /// "Dune (2021)".
  final String title;

  /// Il messaggio; `null` senza.
  final String? text;
}
```

e in `inboxEntryFromJson`, prima di `_ => null`:

```dart
    'Recommendation' => RecommendationEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        itemId: json['ItemId'] as String,
        fromName: json['FromName'] as String? ?? '',
        title: json['Title'] as String? ?? '',
        text: switch (json['Text']) {
          final String text when text.isNotEmpty => text,
          _ => null,
        },
      ),
```

In `lib/features/inbox/inbox_panel.dart`:
- nello `switch` della miniatura di `_EntryTile`: `RecommendationEntry() => _ItemPoster(itemId: entry.itemId),`;
- nello `switch` del contenuto: `RecommendationEntry() => _RecommendationContent(key: Key('inbox-recommendation-${entry.id}'), entry: entry, time: widget.time),`;
- dopo `_InvitePoster`:

```dart
/// La locandina di un titolo noto solo per id (un consiglio, spec N §7.5).
class _ItemPoster extends ConsumerWidget {
  const _ItemPoster({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: InboxPanel.leadingSize,
          height: InboxPanel.posterHeight,
          child: WfImage(image: ref.watch(imageUrlsProvider).primaryOf(itemId)),
        ),
      );
}
```

- dopo `_InviteContent` (e il suo `State`):

```dart
/// Consiglio: "Luigi ti consiglia Dune (2021)", il messaggio, l'ora. Il clic
/// chiude il pannello e apre il titolo (spec N §7.5; piano 20b, decisione 1).
class _RecommendationContent extends ConsumerWidget {
  const _RecommendationContent(
      {super.key, required this.entry, required this.time});

  final RecommendationEntry entry;
  final String time;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final text = entry.text;
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: () {
          ref.read(shellPanelProvider.notifier).close();
          openItemById(context, entry.itemId);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                  _inviteFromSpan(
                      l.inboxRecommendation(entry.fromName, entry.title),
                      entry.fromName),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: WfColors.cream)),
              if (text != null)
                Text('«$text»',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: _mutedStyle),
              const SizedBox(height: 4),
              Text(time, style: _timeStyle),
            ],
          ),
        ),
      ),
    );
  }
}
```

(`_inviteFromSpan` mette in evidenza il nome dentro la frase; il messaggio in italiano e in inglese è tra «» come nella spec: la riga è la stessa nelle due lingue.)

Cerca altri `switch` esaustivi su `InboxEntry` in `lib/` e `test/` (`grep -rn "InboxEntry\|ContactReminderEntry()" lib test`) e completali.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `flutter analyze` e `flutter test --concurrency=4`.
Expected: PASS; suite verde.

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): recommendation entries in the inbox"
```

---

## Gruppo B — anteprima e Home

### Task 3: note e × nell'anteprima, sottotitolo della locandina

**Files:**
- Modify: `lib/ui/card_preview.dart`, `lib/ui/card_preview_host.dart`, `lib/ui/poster_card.dart`
- Test: `test/ui/card_preview_test.dart`, `test/ui/card_preview_content_test.dart`, `test/ui/cards_test.dart` (un test in più ciascuno)

**Interfaces:**
- Produces:
  - `const previewNoteHeight = 18.0`;
  - `class CardPreviewExtra { const CardPreviewExtra({this.notes = const [], this.onDismiss, this.dismissTooltip = ''}); List<String> notes; VoidCallback? onDismiss; String dismissTooltip; double get height }`;
  - `previewRect(card:, overlay:, extraHeight: 0)`;
  - `CardPreview(..., extra:)`, `CardPreviewHost(..., extra:)`;
  - `PosterCard(..., subtitle:, previewExtra:)`: `subtitle` prende il posto dell'anno.

- [ ] **Step 1: i test che falliscono**

In `test/ui/card_preview_test.dart`:

```dart
  test('le note allungano l\'anteprima', () {
    const overlay = Size(1440, 900);
    const card = Rect.fromLTWH(600, 300, 160, 240);
    final plain = previewRect(card: card, overlay: overlay);
    final tall = previewRect(card: card, overlay: overlay, extraHeight: 2 * previewNoteHeight);
    expect(tall.height, plain.height + 2 * previewNoteHeight);
    expect(tall.width, plain.width);
  });
```

In `test/ui/card_preview_content_test.dart`, `pumpPreview` riceve un `CardPreviewExtra? extra` e lo passa a `CardPreview(extra: extra)`, con l'altezza del riquadro `360 * 9 / 16 + previewBodyHeight + (extra?.height ?? 0)`; poi:

```dart
  testWidgets('note e Non mi interessa', (tester) async {
    var dismissed = 0;
    await pumpPreview(tester, testItem(id: 'm1'),
        extra: CardPreviewExtra(
          notes: const ['Luca: «da vedere»', 'Marta: «bellissimo»'],
          dismissTooltip: 'Non mi interessa',
          onDismiss: () => dismissed++,
        ));
    expect(find.text('Luca: «da vedere»'), findsOneWidget);
    expect(find.text('Marta: «bellissimo»'), findsOneWidget);
    await tester.tap(find.byTooltip('Non mi interessa'));
    expect(dismissed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('senza extra niente ×', (tester) async {
    await pumpPreview(tester, testItem(id: 'm1'));
    expect(find.byIcon(LucideIcons.x), findsNothing);
  });
```

In `test/ui/cards_test.dart` (con l'impalcatura dei test di `PosterCard` del file):

```dart
  testWidgets('PosterCard: il sottotitolo prende il posto dell\'anno', (tester) async {
    // … monta una PosterCard come gli altri test del file, con
    // subtitle: 'Da Luca' …
    expect(find.text('Da Luca'), findsOneWidget);
    expect(find.text('2024'), findsNothing);
  });
```

(La riga `// …` è il montaggio, da copiare dal test di `PosterCard` vicino.)

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/ui/card_preview_test.dart test/ui/card_preview_content_test.dart test/ui/cards_test.dart`
Expected: FAIL.

- [ ] **Step 3: il codice**

In `lib/ui/card_preview.dart`:
- dopo `previewBodyPadding`:

```dart

/// Altezza di una riga di nota sotto i dati (i messaggi di un consiglio,
/// spec N §7.4): l'anteprima si allunga di tanto per ogni nota.
const previewNoteHeight = 18.0;

/// Aggiunte all'anteprima di una card, solo per chi le passa (la riga
/// "Consigliati per te"): righe di nota e un pulsante × con [onDismiss].
class CardPreviewExtra {
  const CardPreviewExtra({
    this.notes = const [],
    this.onDismiss,
    this.dismissTooltip = '',
  });

  final List<String> notes;
  final VoidCallback? onDismiss;
  final String dismissTooltip;

  /// Quanto si allunga l'anteprima.
  double get height => notes.length * previewNoteHeight;
}
```

- `previewRect` prende `double extraHeight = 0` e l'altezza diventa `width * 9 / 16 + previewBodyHeight + extraHeight`; aggiorna il commento ("… più [extraHeight] per le note").
- `CardPreview`: nuovo campo `final CardPreviewExtra? extra;` (costruttore: `this.extra,`); in `_content`, nella `Row` dei pulsanti, subito dopo il `WfIconToggle` del "visto" e prima dello `Spacer`:

```dart
                        if (extra?.onDismiss case final dismiss?) ...[
                          const SizedBox(width: 8),
                          _RoundButton(
                            icon: LucideIcons.x,
                            tooltip: extra!.dismissTooltip,
                            onPressed: dismiss,
                          ),
                        ],
```

  e nella colonna, dopo il testo dei generi e prima dello `Spacer`:

```dart
                  for (final note in extra?.notes ?? const <String>[])
                    SizedBox(
                      height: previewNoteHeight,
                      child: Text(note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted),
                    ),
```

In `lib/ui/card_preview_host.dart`:
- nuovo campo `final CardPreviewExtra? extra;` (costruttore: `this.extra,`, facoltativo);
- `previewRect(card: card, overlay: info.overlaySize, extraHeight: widget.extra?.height ?? 0)`;
- `CardPreview(... , extra: _extra)`, con:

```dart
  /// Le aggiunte della card; la × chiude l'anteprima prima di agire.
  CardPreviewExtra? get _extra {
    final extra = widget.extra;
    final dismiss = extra?.onDismiss;
    if (extra == null || dismiss == null) return extra;
    return CardPreviewExtra(
      notes: extra.notes,
      dismissTooltip: extra.dismissTooltip,
      onDismiss: () {
        _hide(immediately: true);
        dismiss();
      },
    );
  }
```

In `lib/ui/poster_card.dart`:
- campi `final String? subtitle;` ("Al posto dell'anno, per esempio chi ha consigliato il titolo (spec N §7.3).") e `final CardPreviewExtra? previewExtra;` (costruttore: `this.subtitle, this.previewExtra,`), con l'import di `card_preview.dart` se manca;
- la riga dell'anno diventa: `final line = widget.subtitle ?? year?.toString();` e `if (line != null) Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),`;
- `CardPreviewHost(item: item, heroSource: heroSource, extra: widget.previewExtra, child: card)`.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `flutter analyze` e `flutter test --concurrency=4`.
Expected: PASS; suite verde.

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): notes and dismiss button in the card preview"
```

---

### Task 4: la riga "Consigliati per te"

**Files:**
- Create: `lib/features/recommendations/recommendation_labels.dart`, `lib/features/recommendations/recommendation_dismissals.dart`
- Modify: `lib/features/home/home_layout.dart`, `home_row_content.dart`, `home_providers.dart`, `home_rows_logic.dart`, `home_row_view.dart`, `home_rows_editing.dart`
- Modify (test): `test/support/home_fakes.dart`
- Test: `test/features/recommendations/recommendation_labels_test.dart`, `test/features/home/home_recommended_test.dart`, più gli aggiornamenti dei test della Home che elencano tutte le righe

**Interfaces:**
- Consumes: `SocialApi.recommendations()`, `dismissRecommendation(itemId)`, `SocialFeatures.recommendations`, `Recommendation`, `RecommendationSender` (Task 1); `PosterCard(subtitle:, previewExtra:)`, `CardPreviewExtra` (Task 3); testi `homeRowRecommended`, `recommendedFrom*`, `recommendationQuote`, `recommendDismiss`, `recommendDismissFailed`, `homeRowUnavailableRecommendations` (Task 1).
- Produces:
  - `HomeRowKind.recommended` (id `recommended`, dopo `nextUp`, `fromJellyfin` falso), `HomeRowGate.recommendationsOff`;
  - `class RecommendedItem { JellyfinItem item; List<RecommendationSender> from }`, `final class RecommendedRowContent extends HomeRowContent { List<RecommendedItem> titles }`;
  - `Future<List<RecommendedItem>> loadRecommended(LibraryApi api, String userId, List<Recommendation> recommendations)`;
  - `String recommendedFrom(AppLocalizations l, List<RecommendationSender> from)`, `List<String> recommendationNotes(AppLocalizations l, List<RecommendationSender> from)`, `const recommendationNotesMax = 3`;
  - `recommendationDismissalsProvider` (`NotifierProvider<RecommendationDismissals, Set<String>>`, chiavi `jellyfinIdKey`), con `Future<bool> dismiss(String itemId)`;
  - `homeOverrides(..., social:)` con un `FakeSocialApi`.

- [ ] **Step 1: i test che falliscono**

`test/features/recommendations/recommendation_labels_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/recommendation_models.dart';
import 'package:wonderflix/features/recommendations/recommendation_labels.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';

RecommendationSender _s(String name, [String? message]) => RecommendationSender(
    userId: name, name: name, message: message, createdAt: DateTime.utc(2026, 10, 12));

void main() {
  final l = lookupAppLocalizations(const Locale('it'));

  test('chi ha consigliato', () {
    expect(recommendedFrom(l, [_s('Luca')]), 'Da Luca');
    expect(recommendedFrom(l, [_s('Luca'), _s('Marta')]), 'Da Luca e Marta');
    expect(recommendedFrom(l, [_s('Luca'), _s('Marta'), _s('Peach')]), 'Da Luca e altri 2');
    expect(recommendedFrom(l, const []), '');
  });

  test('le note: solo chi ha scritto, al massimo 3', () {
    expect(
        recommendationNotes(l, [
          _s('Luca', 'da vedere'),
          _s('Marta'),
          _s('Peach', 'a'),
          _s('Toad', 'b'),
          _s('Yoshi', 'c'),
        ]),
        ['Luca: «da vedere»', 'Peach: «a»', 'Toad: «b»']);
  });
}
```

`test/features/home/home_recommended_test.dart`: con l'impalcatura di `test/features/home/home_providers_test.dart` (container con `homeOverrides`, `retry: (_, _) => null`, aiuti `layout` e `row`) per i test di provider, e di `test/features/home/home_row_view_test.dart` per quelli dei widget:

```dart
  test('senza la funzione: riga non disponibile e nessuna chiamata', () async {
    availability = FakeSocialAvailability(const SocialFeatures(friends: true));
    final c = container();
    final result = await layout(c);
    expect(result.visible, isNot(contains(HomeRowKind.recommended)));
    expect(social.calls, isNot(contains('recommendations')));
    expect(
        homeRowGate(HomeRowKind.recommended, const SocialFeatures(), seerrAccount: false),
        HomeRowGate.recommendationsOff);
  });

  test('con la funzione: la riga c\'è, dopo Prossimi episodi', () async {
    availability = FakeSocialAvailability(
        const SocialFeatures(friends: true, recommendations: true));
    final result = await layout(container());
    final visible = result.visible;
    expect(visible.indexOf(HomeRowKind.recommended),
        visible.indexOf(HomeRowKind.nextUp) + 1);
  });

  test('la riga tiene l\'ordine del plugin e salta i titoli che Jellyfin non dà',
      () async {
    availability = FakeSocialAvailability(
        const SocialFeatures(friends: true, recommendations: true));
    library.itemsById['m2'] = testItem(id: 'm2', name: 'Arrival');
    library.itemsById['m1'] = testItem(id: 'm1', name: 'Dune');
    social.recommendationsList = [
      testRecommendation('m2', [('Luca', 'da vedere')]),
      testRecommendation('gone', [('Luca', null)]),
      testRecommendation('m1', [('Marta', null)]),
    ];
    final content = await row(container(), HomeRowKind.recommended)
        as RecommendedRowContent;
    expect(content.titles.map((t) => t.item.id), ['m2', 'm1']);
    expect(content.titles.first.from.single.name, 'Luca');
    expect(library.itemsByIdsCalls.single, ['m2', 'gone', 'm1']);
  });

  test('errore del plugin: la riga è in errore (e non si vede)', () async {
    availability = FakeSocialAvailability(
        const SocialFeatures(friends: true, recommendations: true));
    social.nextFailure = SocialFailure.network;
    final c = container();
    final key = (kind: HomeRowKind.recommended, language: 'it');
    c.listen(homeRowProvider(key), (_, _) {});
    await expectLater(c.read(homeRowProvider(key).future), throwsA(isA<SocialException>()));
  });

  testWidgets('card: chi l\'ha consigliata, messaggi e Non mi interessa', (tester) async {
    // … monta HomeRowView con kind: HomeRowKind.recommended e
    // content: RecommendedRowContent([RecommendedItem(item: testItem(id: 'm1'),
    // from: testRecommendation('m1', [('Luca', 'da vedere'), ('Marta', null)]).from)])
    // e gli override di socialApiProvider (social) …
    expect(find.text('Consigliati per te'), findsOneWidget);
    expect(find.text('Da Luca e Marta'), findsOneWidget);
  });

  testWidgets('Non mi interessa: la card sparisce subito', (tester) async {
    // … monta come sopra, con due titoli m1 e m2 …
    await tester.runAsync(() => ProviderScope.containerOf(
            tester.element(find.byType(HomeRowView)))
        .read(recommendationDismissalsProvider.notifier)
        .dismiss('m1'));
    await tester.pump();
    expect(social.calls, contains('dismiss m1'));
    expect(find.text('Dune: Parte Due'), findsNothing); // m1
    expect(find.text('Arrival'), findsOneWidget); // m2
  });

  testWidgets('Non mi interessa non riuscito: la card torna', (tester) async {
    // … monta come sopra, con il solo titolo m1 …
    social.nextFailure = SocialFailure.network;
    final ok = await tester.runAsync(() => ProviderScope.containerOf(
            tester.element(find.byType(HomeRowView)))
        .read(recommendationDismissalsProvider.notifier)
        .dismiss('m1'));
    await tester.pump();
    expect(ok, isFalse);
    expect(find.text('Dune: Parte Due'), findsOneWidget);
  });
```

Le righe `// …` sono il montaggio, da scrivere con l'impalcatura di `home_row_view_test.dart` (che monta `HomeRowView` con `pumpApp`): copiale, non lasciarle come commenti. `social` è un `FakeSocialApi` creato nel `setUp` e passato a `homeOverrides(social: social)` e, nei test dei widget, a `socialApiProvider.overrideWithValue(social)`. Nel test della card controlla anche l'anteprima solo se il file di modello ha già un modo semplice di aprirla; altrimenti bastano i testi della card (l'anteprima ha i suoi test nel Task 3).

Cerca i test della Home che elencano tutte le righe o `HomeRowKind.values` (`grep -rn "HomeRowKind.values\|HomeRowKind.myList\]" test`) e aggiorna gli attesi con `recommended` dopo `nextUp` dove la riga è disponibile.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/recommendations/recommendation_labels_test.dart test/features/home/home_recommended_test.dart`
Expected: FAIL.

- [ ] **Step 3: il codice**

`lib/features/recommendations/recommendation_labels.dart`:

```dart
import '../../core/social/recommendation_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Messaggi al massimo nell'anteprima di una card (spec N §7.4).
const recommendationNotesMax = 3;

/// "Da Luca", "Da Luca e Marta", "Da Luca e altri 2": i mittenti sono già dal
/// più recente (spec N §7.3).
String recommendedFrom(AppLocalizations l, List<RecommendationSender> from) =>
    switch (from) {
      [] => '',
      [final one] => l.recommendedFromOne(one.name),
      [final first, final second] => l.recommendedFromTwo(first.name, second.name),
      [final first, ...final others] => l.recommendedFromMany(first.name, others.length),
    };

/// I messaggi per l'anteprima: "Luca: «da vedere»"; chi non ha scritto non
/// compare.
List<String> recommendationNotes(
        AppLocalizations l, List<RecommendationSender> from) =>
    [
      for (final sender in from)
        if (sender.message case final message?)
          l.recommendationQuote(sender.name, message),
    ].take(recommendationNotesMax).toList();
```

`lib/features/recommendations/recommendation_dismissals.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/json_fields.dart';
import '../../core/social/social_api.dart';
import '../auth/session_controller.dart';
import '../social/social_providers.dart';

final _log = Logger('social');

/// I titoli tolti da "Consigliati per te" con "Non mi interessa" (spec N
/// §7.4): la card sparisce subito, prima della risposta del plugin, e torna
/// se la chiamata non riesce (piano 20b, decisione 2). Chiavi
/// `jellyfinIdKey`. Si svuota al cambio di utente.
class RecommendationDismissals extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    return const {};
  }

  /// Toglie [itemId]; `false` se il plugin non ha risposto (la card torna).
  Future<bool> dismiss(String itemId) async {
    final key = jellyfinIdKey(itemId);
    state = {...state, key};
    try {
      await ref.read(socialApiProvider).dismissRecommendation(itemId);
      return true;
    } on Object catch (error) {
      _log.info('consiglio non tolto: '
          '${error is SocialException ? error.failure.name : error.runtimeType}');
      if (ref.mounted) state = {...state}..remove(key);
      return false;
    }
  }
}

final recommendationDismissalsProvider =
    NotifierProvider<RecommendationDismissals, Set<String>>(
        RecommendationDismissals.new);
```

In `lib/features/home/home_layout.dart`:
- `HomeRowKind`: `recommended('recommended'),` subito dopo `nextUp('nextUp'),`;
- `fromJellyfin`: `requests || recommended || upcomingSeries || upcomingMovies => false,`;
- `HomeRowGate`, in fondo:

```dart

  /// Il plugin non ha i consigli (prima della 1.8.0, o senza accesso ai watch
  /// party).
  recommendationsOff,
```

- `homeRowGate`: `HomeRowKind.recommended when !features.recommendations => HomeRowGate.recommendationsOff,` prima di `_ => HomeRowGate.available`.

In `lib/features/home/home_row_content.dart` (import `../../core/social/recommendation_models.dart`), dopo `UpcomingMoviesRowContent`:

```dart

/// "Consigliati per te" (spec N §7.3).
final class RecommendedRowContent extends HomeRowContent {
  const RecommendedRowContent(this.titles);

  final List<RecommendedItem> titles;

  @override
  bool get isEmpty => titles.isEmpty;
}

/// Un titolo consigliato, con chi l'ha consigliato.
class RecommendedItem {
  const RecommendedItem({required this.item, required this.from});

  final JellyfinItem item;
  final List<RecommendationSender> from;
}
```

In `lib/features/home/home_rows_logic.dart` (import `../../core/social/recommendation_models.dart` e `home_row_content.dart` se mancano), dopo `loadContinueSaga`:

```dart
/// "Consigliati per te" (spec N §7.3): i titoli del plugin, al più
/// [homeRowLimit], letti da Jellyfin in una volta. Restano nell'ordine del
/// plugin; quelli che Jellyfin non dà (cancellati, non più visibili) si
/// saltano.
Future<List<RecommendedItem>> loadRecommended(
    LibraryApi api, String userId, List<Recommendation> recommendations) async {
  final wanted = recommendations.take(homeRowLimit).toList();
  if (wanted.isEmpty) return const [];
  final byId = {
    for (final item
        in await api.itemsByIds(userId, [for (final r in wanted) r.itemId]))
      jellyfinIdKey(item.id): item,
  };
  return [
    for (final r in wanted)
      if (byId[jellyfinIdKey(r.itemId)] case final item?)
        RecommendedItem(item: item, from: r.from),
  ];
}
```

In `lib/features/home/home_providers.dart` (import `../social/social_providers.dart` se manca), in `homeRowProvider`, prima del `case` delle righe della libreria:

```dart
    case HomeRowKind.recommended:
      // Niente `keepFor`: si rilegge a ogni apertura della Home (piano 20b,
      // decisione 3). Tutti i watch prima dell'attesa.
      final userId = ref.watch(currentUserIdProvider);
      final api = ref.watch(libraryApiProvider);
      final recommendations =
          await ref.watch(socialApiProvider).recommendations();
      return RecommendedRowContent(
          await loadRecommended(api, userId, recommendations));
```

e in `_libraryRow`, nel `case` che lancia `StateError`, aggiungi `HomeRowKind.recommended ||`.

In `lib/features/home/home_row_view.dart` (import `dart:async` c'è già; aggiungi `../../ui/card_preview.dart`, `../recommendations/recommendation_dismissals.dart`, `../recommendations/recommendation_labels.dart`):
- `_title`: `HomeRowKind.recommended => l.homeRowRecommended,`;
- nello `switch` di `build`: `RecommendedRowContent(:final titles) => _recommended(context, ref, l, titles),`;
- il metodo:

```dart
  /// "Consigliati per te": chi l'ha consigliato sotto la locandina, i
  /// messaggi e "Non mi interessa" nell'anteprima (spec N §7.3, §7.4). I
  /// titoli tolti spariscono subito.
  Widget _recommended(BuildContext context, WidgetRef ref, AppLocalizations l,
      List<RecommendedItem> titles) {
    final dismissed = ref.watch(recommendationDismissalsProvider);
    final shown = [
      for (final title in titles)
        if (!dismissed.contains(jellyfinIdKey(title.item.id))) title,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return _row(l.homeRowRecommended, posterRowHeight, shown.length, (context, i) {
      final title = shown[i];
      return PosterCard(
        key: ValueKey('recommended-${title.item.id}'),
        item: title.item,
        width: posterWidth,
        heroSource: 'home.${kind.id}.$i',
        subtitle: recommendedFrom(l, title.from),
        previewExtra: CardPreviewExtra(
          notes: recommendationNotes(l, title.from),
          dismissTooltip: l.recommendDismiss,
          onDismiss: () => unawaited(_dismiss(context, ref, title.item.id)),
        ),
      );
    });
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref, String itemId) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok =
        await ref.read(recommendationDismissalsProvider.notifier).dismiss(itemId);
    if (!ok) {
      messenger?.showSnackBar(SnackBar(content: Text(l.recommendDismissFailed)));
    }
  }
```

(`jellyfinIdKey` è in `../../core/jellyfin/json_fields.dart`: aggiungi l'import se manca. La chiave sulla card evita che, tolto un titolo, la card di un altro riusi lo stato di quella vecchia.)

In `lib/features/home/home_rows_editing.dart`:
- `homeRowName`: `HomeRowKind.recommended => l.homeRowRecommended,`;
- `homeRowGateReason`: `HomeRowGate.recommendationsOff => l.homeRowUnavailableRecommendations,`.

In `test/support/home_fakes.dart`: `homeOverrides` riceve `FakeSocialApi? social` e aggiunge `socialApiProvider.overrideWithValue(social ?? FakeSocialApi()),` (lo stesso in `homeSettingsOverrides`, se monta la Home con le funzioni del plugin).

Altri `switch` esaustivi su `HomeRowKind` o `HomeRowGate` (per esempio nelle impostazioni o nell'amministrazione): `flutter analyze` li trova; completali.

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `flutter analyze` e `flutter test --concurrency=4`.
Expected: PASS; suite verde.

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): Recommended for you Home row"
```

---

## Gruppo C — pannello e chiusura

### Task 5: il pannello "Consiglia a…"

**Files:**
- Create: `lib/features/recommendations/recommend_panel.dart`
- Modify: `lib/app/shell_panels.dart`, `lib/app/app_shell.dart`, `lib/features/detail/detail_header.dart`
- Test: `test/features/recommendations/recommend_panel_test.dart`, `test/features/detail/detail_recommend_test.dart`

**Interfaces:**
- Consumes: `SocialApi.recommendationTargets`, `recommend`, `RecommendationTarget`, `SocialFeatures.recommendations`, testi `recommend*` (Task 1); `friendsControllerProvider`, `MemberAvatar`, `ShellSidePanel`.
- Produces:
  - `ShellPanel.recommend`;
  - `class RecommendSubject { const RecommendSubject({required this.itemId, required this.name}); String itemId; String name; }`;
  - `recommendSubjectProvider` (`NotifierProvider<RecommendSubjectController, RecommendSubject?>`, con `set`);
  - `void openRecommendPanel(WidgetRef ref, RecommendSubject subject)`;
  - `recommendTargetsProvider` (`FutureProvider.autoDispose.family<List<RecommendationTarget>, String>`);
  - `const recommendMaxRecipients = 30`, `const recommendMessageMax = 200`;
  - `RecommendPanel(subject:)`, `RecommendPanelHost()`.

- [ ] **Step 1: i test che falliscono**

`test/features/recommendations/recommend_panel_test.dart`: monta `Scaffold(body: RecommendPanel(subject: RecommendSubject(itemId: 'm1', name: 'Dune')))` in una `SizedBox(width: 360)` con `pumpApp` e `socialTestOverrides(api, features: const SocialFeatures(friends: true, recommendations: true))`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/recommendations/recommend_panel.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';

void main() {
  late FakeSocialApi api;

  setUp(() {
    api = FakeSocialApi()..install(features: const {});
    api.recommendationTargetsById['m1'] = [
      testTarget('u3', 'Peach'),
      testTarget('u2', 'Luigi', online: true),
      testTarget('u4', 'Toad', canSee: false),
    ];
  });

  Future<void> pump(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 360,
            child: RecommendPanel(subject: RecommendSubject(itemId: 'm1', name: 'Dune')),
          ),
        ),
      ),
      overrides: socialTestOverrides(api,
          features: const SocialFeatures(friends: true, recommendations: true)),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder target(String userId) => find.byKey(ValueKey('recommend-target-$userId'));

  // `WfButton.primary` è un `FilledButton.icon`, una sottoclasse: si cerca
  // il pulsante che contiene il testo.
  Finder sendButton() => find.ancestor(
      of: find.text('Invia'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

  testWidgets('amici online prima, poi per nome; chi non può vederlo è spento',
      (tester) async {
    await pump(tester);
    expect(api.calls, contains('targets m1'));
    expect(find.text('Dune'), findsOneWidget);
    final luigi = tester.getTopLeft(target('u2')).dy;
    final peach = tester.getTopLeft(target('u3')).dy;
    final toad = tester.getTopLeft(target('u4')).dy;
    expect(luigi < peach && peach < toad, isTrue);
    expect(find.text('Non può vederlo'), findsOneWidget);
    await tester.tap(target('u4'));
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(sendButton()).onPressed, isNull);
  });

  testWidgets('invio con messaggio: il pannello si chiude e lo dice', (tester) async {
    await pump(tester);
    await tester.tap(target('u2'));
    await tester.tap(target('u3'));
    await tester.enterText(find.byType(TextField), '  da vedere  ');
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pump();
    await tester.pump();
    expect(api.calls.last, 'recommend m1 u2,u3 da vedere');
    expect(find.text('Consiglio inviato a 2 amici'), findsOneWidget);
  });

  testWidgets('nessun destinatario valido: non inviato, il pannello resta',
      (tester) async {
    api.recommendSent = 0;
    await pump(tester);
    await tester.tap(target('u2'));
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pump();
    await tester.pump();
    expect(find.text('Consiglio non inviato'), findsOneWidget);
    expect(find.byType(RecommendPanel), findsOneWidget);
    expect(api.calls.last, 'recommend m1 u2 -');
  });

  testWidgets('troppi consigli: lo dice', (tester) async {
    await pump(tester);
    await tester.tap(target('u2'));
    await tester.pump();
    api.nextFailure = SocialFailure.rateLimited;
    await tester.tap(sendButton());
    await tester.pump();
    await tester.pump();
    expect(find.text('Troppi consigli: riprova più tardi'), findsOneWidget);
  });

  testWidgets('Invia spento durante l\'invio', (tester) async {
    api.recommendGate = Completer<void>();
    await pump(tester);
    await tester.tap(target('u2'));
    await tester.pump();
    await tester.tap(sendButton());
    await tester.pump();
    expect(tester.widget<ButtonStyleButton>(sendButton()).onPressed, isNull);
    api.recommendGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(api.calls.where((c) => c.startsWith('recommend ')), hasLength(1));
  });

  testWidgets('elenco non caricato: errore e Riprova', (tester) async {
    api.nextFailure = SocialFailure.network;
    await pump(tester);
    expect(find.text('Impossibile caricare gli amici'), findsOneWidget);
    await tester.tap(find.text('Riprova'));
    await tester.pump();
    await tester.pump();
    expect(target('u2'), findsOneWidget);
  });

  testWidgets('al massimo 30 amici alla volta', (tester) async {
    api.recommendationTargetsById['m1'] = [
      for (var i = 0; i < 31; i++) testTarget('u$i', 'Amico ${i.toString().padLeft(2, '0')}'),
    ];
    await pump(tester);
    for (var i = 0; i < 30; i++) {
      await tester.ensureVisible(target('u$i'));
      await tester.tap(target('u$i'));
      await tester.pump();
    }
    expect(find.text('Al massimo 30 amici alla volta'), findsOneWidget);
    await tester.ensureVisible(target('u30'));
    await tester.tap(target('u30'));
    await tester.pump();
    final checkbox = tester.widget<CheckboxListTile>(target('u30'));
    expect(checkbox.value, isFalse);
  });
}
```

(Aggiungi `import 'dart:async';` per `Completer`. L'import di `shell_panels.dart` serve se controlli `shellPanelProvider` dopo l'invio riuscito: con il pannello montato da solo basta l'avviso.)

`test/features/detail/detail_recommend_test.dart`, con l'impalcatura di `test/features/detail/movie_detail_test.dart` (`pumpApp` + `ItemDetailScreen(itemId: 'm1')` + `FakeLibraryApi`) e in più `socialTestOverrides(api, features: …)` (con `session: false` se il file di modello imposta già la sessione) e `api.snapshot` con un amico:

```dart
  testWidgets('pulsante Consiglia a… su un film, con la funzione e un amico',
      (tester) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    // … monta il dettaglio di m1 (film) con features
    // SocialFeatures(friends: true, recommendations: true) …
    expect(find.text('Consiglia a…'), findsOneWidget);
  });

  testWidgets('niente pulsante senza la funzione o senza amici', (tester) async {
    api.snapshot = FriendsSnapshot(friends: [testFriend('u2', 'Luigi')]);
    // … monta con SocialFeatures(friends: true) …
    expect(find.text('Consiglia a…'), findsNothing);
  });

  testWidgets('niente pulsante su un episodio', (tester) async {
    // … m1 come episodio (testItem(kind: ItemKind.episode, seriesId: 's1')),
    // con la funzione e un amico …
    expect(find.text('Consiglia a…'), findsNothing);
  });
```

Le righe `// …` sono il montaggio del file di modello: scrivile per esteso. Se `FriendsSnapshot` ha un costruttore con altri campi obbligatori, passali vuoti.

- [ ] **Step 2: i test falliscono**

Run: `flutter test test/features/recommendations/recommend_panel_test.dart test/features/detail/detail_recommend_test.dart`
Expected: FAIL.

- [ ] **Step 3: il codice**

In `lib/app/shell_panels.dart`: `enum ShellPanel { none, friends, inbox, recommend }` (commento: "…, spec N §7.2"); nello `switch` di `open`: `case ShellPanel.recommend:` insieme a `case ShellPanel.none:` (`break`: il soggetto lo imposta chi apre, con `openRecommendPanel`).

`lib/features/recommendations/recommend_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/social/recommendation_models.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/shell_side_panel.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import '../watch_party/party_badge.dart';

final _log = Logger('social');

/// Amici al massimo in un consiglio: i destinatari sono 30 all'ora (piano
/// 20b, decisione 4).
const recommendMaxRecipients = 30;

/// Lunghezza massima del messaggio (spec N §6.2).
const recommendMessageMax = 200;

/// Il titolo da consigliare (spec N §7.2).
class RecommendSubject {
  const RecommendSubject({required this.itemId, required this.name});

  final String itemId;
  final String name;
}

/// Il titolo del pannello "Consiglia a…": lo imposta chi lo apre.
class RecommendSubjectController extends Notifier<RecommendSubject?> {
  @override
  RecommendSubject? build() => null;

  void set(RecommendSubject? subject) => state = subject;
}

final recommendSubjectProvider =
    NotifierProvider<RecommendSubjectController, RecommendSubject?>(
        RecommendSubjectController.new);

/// Apre il pannello per [subject] (spec N §7.2).
void openRecommendPanel(WidgetRef ref, RecommendSubject subject) {
  ref.read(recommendSubjectProvider.notifier).set(subject);
  ref.read(shellPanelProvider.notifier).open(ShellPanel.recommend);
}

/// Gli amici a cui si può consigliare il titolo, letti all'apertura.
final recommendTargetsProvider = FutureProvider.autoDispose
    .family<List<RecommendationTarget>, String>((ref, itemId) =>
        ref.watch(socialApiProvider).recommendationTargets(itemId));

/// Online prima, poi per nome (come il pannello Amici); chi non può vedere
/// il titolo in fondo.
List<RecommendationTarget> sortTargets(List<RecommendationTarget> targets) =>
    [...targets]..sort((a, b) {
        if (a.canSee != b.canSee) return a.canSee ? -1 : 1;
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 13);

/// Il pannello "Consiglia a…" (spec N §7.2): titolo, amici con la casella,
/// messaggio facoltativo, Invia.
class RecommendPanel extends ConsumerStatefulWidget {
  const RecommendPanel({super.key, required this.subject});

  final RecommendSubject subject;

  /// Lato della locandina in alto (2:3).
  static const posterWidth = 40.0;
  static const posterHeight = 60.0;

  @override
  ConsumerState<RecommendPanel> createState() => _RecommendPanelState();
}

class _RecommendPanelState extends ConsumerState<RecommendPanel> {
  final _message = TextEditingController();
  final _closeFocus = FocusNode(debugLabel: 'recommend-close');
  final _selected = <String>{};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Come negli altri pannelli: `autofocus` nella shell vera non basta.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _closeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _message.dispose();
    _closeFocus.dispose();
    super.dispose();
  }

  void _toggle(String userId) => setState(() {
        if (!_selected.remove(userId) &&
            _selected.length < recommendMaxRecipients) {
          _selected.add(userId);
        }
      });

  Future<void> _send() async {
    if (_sending || _selected.isEmpty) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = _message.text.trim();
    setState(() => _sending = true);
    String notice;
    var close = false;
    try {
      final sent = await ref.read(socialApiProvider).recommend(
          widget.subject.itemId, _selected.toList(), text.isEmpty ? null : text);
      close = sent > 0;
      notice = sent > 0 ? l.recommendSent(sent) : l.recommendNotSent;
    } on SocialException catch (error) {
      _log.info('consiglio non inviato: ${error.failure.name}');
      notice = error.failure == SocialFailure.rateLimited
          ? l.recommendRateLimited
          : l.recommendNotSent;
    }
    if (mounted) setState(() => _sending = false);
    if (close && mounted) ref.read(shellPanelProvider.notifier).close();
    messenger?.showSnackBar(SnackBar(content: Text(notice)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final subject = widget.subject;
    final targets = ref.watch(recommendTargetsProvider(subject.itemId));
    return Material(
      key: const Key('recommend-panel'),
      color: WfColors.surface,
      elevation: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.recommendPanelTitle,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  focusNode: _closeFocus,
                  tooltip: l.friendsClose,
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () => ref.read(shellPanelProvider.notifier).close(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: RecommendPanel.posterWidth,
                    height: RecommendPanel.posterHeight,
                    child: WfImage(
                        image: ref.watch(imageUrlsProvider).primaryOf(subject.itemId)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(subject.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WfColors.cream, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Expanded(
            child: targets.when(
              // Mentre carica il pannello resta vuoto (come gli altri).
              loading: () => const SizedBox.shrink(),
              error: (error, _) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.recommendTargetsError, style: _mutedStyle),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(recommendTargetsProvider(subject.itemId)),
                      style: TextButton.styleFrom(foregroundColor: WfColors.gold),
                      child: Text(l.retry),
                    ),
                  ],
                ),
              ),
              data: (list) => _targets(l, sortTargets(list)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _message,
                  maxLength: recommendMessageMax,
                  minLines: 1,
                  maxLines: 3,
                  // Invio non va a capo: il plugin toglie comunque gli a capo.
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                      hintText: l.recommendMessageHint, isDense: true),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: WfButton.primary(
                    label: l.recommendSend,
                    icon: LucideIcons.send,
                    onPressed: _sending || _selected.isEmpty
                        ? null
                        : () => unawaited(_send()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _targets(AppLocalizations l, List<RecommendationTarget> targets) {
    final full = _selected.length >= recommendMaxRecipients;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (full)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(l.recommendMaxReached(recommendMaxRecipients),
                style: _mutedStyle),
          ),
        for (final target in targets)
          CheckboxListTile(
            key: ValueKey('recommend-target-${target.userId}'),
            value: _selected.contains(target.userId),
            onChanged: !target.canSee ||
                    (full && !_selected.contains(target.userId))
                ? null
                : (_) => _toggle(target.userId),
            controlAffinity: ListTileControlAffinity.trailing,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            secondary: Stack(
              clipBehavior: Clip.none,
              children: [
                MemberAvatar(name: target.name, userId: target.userId),
                if (target.online)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: WfColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: WfColors.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(target.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: target.canSee ? WfColors.cream : WfColors.creamMuted)),
            subtitle: target.canSee
                ? null
                : Text(l.recommendCannotSee,
                    style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
          ),
      ],
    );
  }
}

/// Il pannello si vede: aperto, con la funzione e un titolo.
final recommendPanelVisibleProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(shellPanelProvider) == ShellPanel.recommend &&
    ref.watch(socialAvailabilityProvider.select((f) => f.recommendations)) &&
    ref.watch(recommendSubjectProvider) != null);

/// Pannello "Consiglia a…" sopra la shell e la barra, nel contenitore comune
/// dei pannelli laterali (spec N §7.2).
class RecommendPanelHost extends ConsumerWidget {
  const RecommendPanelHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Funzione sparita a pannello aperto: si chiude davvero.
    ref.listen(recommendPanelVisibleProvider, (_, visible) {
      if (!visible && ref.read(shellPanelProvider) == ShellPanel.recommend) {
        ref.read(shellPanelProvider.notifier).close();
      }
    });
    final subject = ref.watch(recommendSubjectProvider);
    return ShellSidePanel(
      open: ref.watch(recommendPanelVisibleProvider),
      onClose: () => ref.read(shellPanelProvider.notifier).close(),
      scrimKey: const Key('recommend-panel-scrim'),
      child: subject == null
          ? const SizedBox.shrink()
          // Un titolo nuovo: un pannello nuovo (scelte e messaggio vuoti).
          : RecommendPanel(key: ValueKey(subject.itemId), subject: subject),
    );
  }
}
```

(Se `WfColors.online` o `MemberAvatar` hanno altri nomi o percorsi, usa quelli del pannello Amici. Se il lettore del `CheckboxListTile` in un test trova la chiave sul `ListTile` interno invece che sul `CheckboxListTile`, metti la chiave dove il test la trova e adegua il test con lo stesso controllo.)

In `lib/app/app_shell.dart`: import `../features/recommendations/recommend_panel.dart` e, dopo `const Positioned.fill(child: InboxPanelHost()),`:

```dart
            // Pannello "Consiglia a…", sopra la barra e le schede (spec N §7.2).
            const Positioned.fill(child: RecommendPanelHost()),
```

In `lib/features/detail/detail_header.dart`: import `../friends/friends_controller.dart`, `../recommendations/recommend_panel.dart`, `../social/social_providers.dart`; in `build`, prima del `return`:

```dart
    // "Consiglia a…" (spec N §7.2): film e serie, con la funzione del plugin
    // e almeno un amico.
    final canRecommend = const {ItemKind.movie, ItemKind.series}.contains(item.kind) &&
        ref.watch(socialAvailabilityProvider.select((f) => f.recommendations)) &&
        ref.watch(friendsControllerProvider
            .select((s) => s.snapshot.friends.isNotEmpty));
```

e nel `Wrap`, dopo il `WfIconToggle` del "visto" e prima delle stagioni da chiedere:

```dart
              if (canRecommend)
                WfButton.secondary(
                  label: l.recommendButton,
                  icon: LucideIcons.send,
                  onPressed: () => openRecommendPanel(
                      ref, RecommendSubject(itemId: item.id, name: item.name)),
                ),
```

- [ ] **Step 4: i test passano**

Run: lo stesso comando dello Step 2, poi `flutter analyze` e `flutter test --concurrency=4`.
Expected: PASS; suite verde. Se un test esistente del dettaglio smette di funzionare perché ora il dettaglio legge gli amici, aggiungi lì gli override sociali con le funzioni di prima (`SocialFeatures.none`).

- [ ] **Step 5: commit**

```powershell
git add lib test
git commit -m "feat(app): Recommend to panel from the detail page"
```

---

### Task 6: versione, spec e build

**Files:**
- Modify: `pubspec.yaml`, `docs/superpowers/specs/2026-10-12-wonderflix-consigli-design.md`, `docs/superpowers/plans/2026-10-13-wonderflix-20b-consigli-app.md` (solo "Dalle review dei gruppi", se servono)

- [ ] **Step 1: versione**

`pubspec.yaml`: `version: 0.14.0` (lo stesso numero di build della riga di oggi, se c'è un `+N`).

- [ ] **Step 2: la spec**

Nella spec, controllando ogni frase sul codice:
- **Stato:** "… piano 20b realizzato (`docs/superpowers/plans/2026-10-13-wonderflix-20b-consigli-app.md`), da provare con l'utente".
- **§7.2:** il pulsante dopo i due tondi (decisione 5); al massimo 30 amici (decisione 4); l'esito con un solo testo al plurale (decisione 6); chi non può vedere il titolo in fondo all'elenco.
- **§7.3:** la riga si rilegge a ogni apertura della Home (decisione 3).
- **§7.4:** la card sparisce subito, senza animazione (decisione 2); il pulsante × nell'anteprima.
- **§7.5:** niente "Non disponibile" sulla voce (decisione 1).
- **§7.1:** la funzione vale solo con l'accesso ai watch party (decisione 7).
- **§9:** le chiavi vere (`recommendSent` al plurale, `recommendMaxReached`, `recommendationQuote`, `homeRowUnavailableRecommendations`).
- Ogni altra differenza venuta fuori durante i task, con il motivo.

- [ ] **Step 3: build**

`flutter analyze`, `flutter test --concurrency=4`, poi la build di prova:

```powershell
flutter build windows --release --dart-define-from-file=config/wonderflix.json
```

(Il worktree non ha `config/wonderflix.json`: il controllore lo copia dal checkout principale prima del Task 6. Senza, la build parte ma l'app dice "Configurazione mancante".)

- [ ] **Step 4: commit**

```powershell
git checkout -- windows/flutter/
git add pubspec.yaml docs
git commit -m "chore: app 0.14.0 and spec aligned with plan 20b"
```

### Task 7: STOP — prova con l'utente (lo fa il controllore)

Dopo la review finale del branch e i suoi ritocchi:
1. Build di release nel worktree (`build/windows/x64/runner/Release/wonderflix.exe`).
2. L'utente prova con due istanze (`WONDERFLIX_PROFILE=b`), due utenti amici, sul plugin 1.8.0 di prova:
   - "Consiglia a…" da un film e da una serie, con e senza messaggio; un amico con un limite d'età spento con "Non può vederlo";
   - la voce nella cassetta dell'amico, e il clic che apre il titolo;
   - la riga "Consigliati per te" con "Da …", i messaggi e "Non mi interessa" nell'anteprima;
   - un riconsiglio dello stesso amico (la voce si aggiorna, nessun doppione) e un secondo amico sullo stesso titolo (una card, "Da Luca e Marta");
   - il titolo guardato dopo il consiglio esce dalla riga alla prossima apertura della Home;
   - l'app 0.13.0 (installata) con il plugin 1.8.0: nessuna voce strana nella cassetta (spec §12, terzo punto).
3. Con l'ok dell'utente: merge fast-forward su `main` e push (memoria `wonderflix-workflow`; prima `git fetch` e rebase se `origin/main` è avanti).

## Release (con l'OK dell'utente a ogni passo)

1. **Plugin 1.8.0:** tag `watch-party-plugin-v1.8.0` → pre-release con lo zip (la `releases/latest` resta l'app); voce 1.8.0.0 nel `manifest.json`; sul server la build di prova va in `~/wfwp-backup/1.8.0.0-prova`, poi riavvio, installazione dal Catalogo e riavvio, quando nessuno guarda; nel log "Loaded plugin … 1.8.0.0" e l'md5 della dll uguale a quello della release.
2. **App 0.14.0 non obbligatoria:** `chore: release 0.14.0`, tag `v0.14.0`, la pipeline `Release`, le note in italiano scritte nella bozza (senza `min-version`); la pubblica l'utente.
3. **Alla fine**, in `docs/IDEE.md`: l'idea 6 esce dalla lista e tra le fatte c'è "Spec N — consigli tra amici (plugin 1.8.0, app 0.14.0)"; lo stato della spec diventa "Realizzata" con i dettagli della release.

# WonderFlix — Piano 23b: voti degli amici, app 0.17.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte app della Spec Q:
- il nucleo: modelli, le otto chiamate di `SocialApi`, l'avviso `RatingRoundUpdated`, la funzione `ratings`, i testi;
- la votazione di fine party in un provider (`ratingRoundProvider`): stato più recente per `Rev`, voto, salta, scopri, riletture;
- il pannello del voto nel post-play del party, con la coda ferma in `Voting`, il conto di 15 s dopo `Revealed` e la pillola "Voti del party";
- la riga "Voti degli amici" nella scheda di film e serie (per stagione) e il pannello laterale per votare;
- la card "Commenti degli utenti" nella dashboard admin;
- app 0.17.0 (obbligatoria), build per la prova a mano con l'utente.

**Architecture:**
- Nucleo in `lib/core/social/`: `rating_models.dart` (modelli) e i metodi nuovi di `SocialApi` e `PluginAdminApi`. L'avviso va in `social_models.dart`.
- La votazione sta in `lib/features/ratings/rating_round_controller.dart` (`RatingRoundController`, una per l'app come il match): ricorda l'elemento della coda (`playlistItemId`) che l'ha aperta. La coda è ferma solo nel player di quell'elemento (`holdsQueue`), e lo stato vive anche con il post-play chiuso o dopo il cambio di titolo.
- Il player (`player_screen.dart`) apre la votazione, decide quando il post-play c'è, non chiama `nextItem` mentre la coda è ferma e tiene il timer dei 15 s. Il pannello (`RatingRoundPanel`) è lo stesso nel post-play e nel pannello laterale del player che apre la pillola.
- Scheda: `FriendRatingsRow` (riga, `itemRatingsProvider`) e `RatePanel` (pannello laterale della shell, come "Consiglia a…") in `lib/features/ratings/`.

**Tech Stack:** Flutter 3.47.5 (Windows), Dart, Riverpod 3 (`Notifier`), go_router, intl (`NumberFormat`), lucide_icons_flutter, `flutter_test`, `fake_async`. Nessuna dipendenza nuova.

**Spec:** `docs/superpowers/specs/2026-10-20-wonderflix-voti-amici-design.md` (§3, §5, §7, §8, §9, §10, §11.2, §11.3, §13). Il plugin 1.11.0 è il piano 23a (`docs/superpowers/plans/2026-10-20-wonderflix-23a-voti-plugin.md`, DTO nel suo Task 1): endpoint e JSON come nella spec §6 e nelle decisioni 4–9 e 12 del 23a. Se il codice del plugin diverge dal piano, vale il plugin: correggi il parsing e segnala.

**Decisioni del piano** (rispetto alla spec; si allinea nel Task 8):
1. **`Mine`** (in `RatingRoundDto` e in `GET Ratings`) è un oggetto `{Score, Comment?}` (piano 23a, decisione 4; la spec non ne dà la forma). Modello `MyRating`.
2. **L'avviso** è `{"Protocol":1,"Type":"RatingRoundUpdated","State":{…RatingRoundDto}}`, come `MatchUpdated` (piano 23a, decisione 5). Quando il plugin scarta una votazione non manda avvisi (23a, decisione 9): l'app lo scopre con `GET Ratings/Rounds/{groupId}` → `{}`.
3. **Niente motivi dei 409 nell'app:** `SocialApi` resta com'è (409 → `conflict`). Nessuna reazione dell'app dipende dal motivo: `NotMember` all'apertura vuol dire niente pannello, `Closed` al voto vuol dire rileggere, `NotCreator` va solo nel log.
4. **400 tra gli esiti attesi** delle chiamate dei voti (`_ratingQuiet = {400, ..._quiet}`): un episodio intermedio dà 400 a ogni fine episodio. Senza questo finirebbe fra gli "Ultimi errori" della diagnostica.
5. **La pillola apre il pannello a lato**, non il post-play. Nel player nuovo, dopo il cambio di titolo, non c'è un post-play da riaprire a metà film. Così la pillola apre sempre lo stesso `RatingRoundPanel` in un `PlayerSidePanelHost` (`PlayerPopup.rating`), anche nel player di partenza.
6. **"La si chiude"** (§7.2): chiudendo il pannello in `Revealed` (Esc o "Guarda i titoli" nel post-play, ✕ o Esc nel pannello a lato) la votazione esce dall'app (`dismiss`) e la pillola sparisce. In `Voting` chiudere non toglie niente. Senza chiusura, l'app la toglie da sé **10 minuti** dopo aver visto `Revealed`.
7. **Esc a video finito nel party** chiude il post-play e basta. Oggi esce dal player, quindi dal party; con la coda ferma si resta sul video finito.
8. **Coda sbloccata quando la votazione sparisce** (`{}`, gruppo lasciato, funzione spenta): a video finito l'app chiama subito `nextItem`. A `Revealed` invece parte il conto di 15 s. Il conto è un timer del player (`_releaseTimer`). `PlayNowButton` lo mostra con i secondi che restano.
9. **Rete di sicurezza:** se 5 s dopo `EndsAt` lo stato è ancora `Voting`, il controller rilegge (`GET Ratings/Rounds/{groupId}`). Rilegge anche a ogni riconnessione del WebSocket. Così un avviso perso non lascia la coda ferma per sempre.
10. **Un avviso arrivato prima della propria apertura** (un altro client è più avanti, o chi entra durante la votazione) si adotta: l'elemento della coda è quello in riproduzione. Una votazione è la stessa se hanno uguali `ItemId` ed `EndsAt` (apertura + 2 min). Il `Rev` (23a, decisione 8) si confronta solo dentro la stessa votazione, e uno stato di un'altra la sostituisce. L'apertura è idempotente sul titolo risolto anche in `Revealed` (23a, decisione 6).
11. **Tasti nel post-play:** con i numeri visibili (fase `Voting`, non ancora votato o dopo "Cambia"), le cifre 1–9 e 0 (= 10) scelgono il voto e ← → lo spostano. Non mandano reazioni e non fanno salti. Con il fuoco nel commento i tasti vanno al campo, come per la ricerca della coda.
12. **Scelta del numero e "Cambia" nel controller** (`draft`, `editing`): i tasti li riceve il player, il pannello li mostra. Il commento in scrittura resta nel campo del pannello.
13. **Stagione nel titolo del post-play:** l'episodio non ha il nome della stagione, quindi "*Breaking Bad* · Stagione 2" usa `parentIndexNumber` e il testo nuovo `ratingSeason`; la stagione 0 è "Speciali" (`ratingSpecials`), come i titoli del plugin (23a, decisione 12). Nella scheda della serie vale il nome della scheda (`season.name`).
14. **Testi in più** rispetto alla §9: `ratingSeason`, `ratingSpecials`, `ratingYouSkipped`, `ratingPartyPill`, `ratingRevealedPill`, `ratingTimeLeft`, `adminCommentsMore`, `adminCommentsEmpty`, `adminCommentDeleteTitle`, `adminCommentDeleteMessage`. `ratingPartyAverage` ha il plurale ("1 voto").
15. **Card admin e accesso ai watch party:** come vuole la spec, `SocialFeatures.ratings` vale solo con l'accesso ai watch party. Un admin senza quell'accesso vede "Serve il plugin 1.11.0" (limite accettato, con un commento `shortcut:` nella card).
16. **La riga nella scheda dei film non c'è per gli episodi:** `MovieDetailView` mostra anche gli episodi aperti da soli, quindi la riga si mostra solo per `ItemKind.movie`. Le righe sotto la testata scalano di un posto: `detailEntranceCount` passa da 8 a 9.
17. **Pillola a `right: 32, bottom: 210`** (`ratingPillBottom`), sopra "Salta intro" e la scheda piccola, che stanno a 150. Nei 30 s finali di un titolo nuovo senza Outro la scheda piccola può coprirla: `shortcut:` nel codice.

## Global Constraints

- App **0.17.0** (`pubspec.yaml`), release **obbligatoria**: nelle note della release la riga `<!-- wonderflix:min-version=0.17.0 -->` (spec §7.5). Nessuna dipendenza nuova.
- Endpoint del plugin 1.11.0 sotto `/WonderFlixWatchParty` (spec §6.3–6.4): `POST Ratings/Rounds` `{GroupId, ItemId}`; `GET Ratings/Rounds/{groupId}` (→ `{}` se non c'è); `POST Ratings/Rounds/{groupId}/Vote` `{Score, Comment}`; `…/Skip`; `…/Reveal`; `GET Ratings?itemId=`; `PUT Ratings/{itemId}` `{Score, Comment}` → 204; `DELETE Ratings/{itemId}` → 204; `GET Ratings/Admin/Comments?before=`; `DELETE Ratings/Admin/Comments/{userId}/{itemId}` → 204. Il plugin non risponde mai 404: un 404 è un plugin vecchio.
- JSON PascalCase come gli altri DTO del plugin. `RatingRoundDto`: `GroupId`, `ItemId`, `Phase` (`Voting`/`Revealed`), `Rev`, `EndsAt`, `CanReveal`, `Mine?`, `Voters` `[{UserId, Name, Status: Waiting|Voted|Skipped}]`, solo in `Revealed` `Results` `[{UserId, Name, Score, Comment?}]` e `Average`. `GET Ratings`: `{CanRate, Mine?, Average?, Count, Friends: [{UserId, Name, Score, Comment?, UpdatedAt}]}`. Commenti admin: `{Items: [{UserId, UserName, ItemId, Title, Score, Comment, UpdatedAt}], Next?}`. Id in formato "N": si confrontano con `jellyfinIdKey`.
- Funzione del plugin `"ratings"`; come gli amici vale solo con l'accesso ai watch party (§7.1).
- Voto: intero **1–10**; commento facoltativo, al massimo **200 punti di codice**, Invio non va a capo (come il messaggio dei consigli). Il testo si mostra sempre come testo semplice.
- Tempi: scoperta dei voti dopo **2 min** (lo decide il plugin, l'app mostra `EndsAt`); conto **15 s** dopo `Revealed` a video finito (`ratingReleaseDelay`); votazione tolta dall'app **10 min** dopo `Revealed` (`ratingRoundKeep`); rilettura **5 s** dopo `EndsAt` se ancora `Voting` (`ratingRevealGrace`); apertura con un tempo massimo di **5 s** (`ratingOpenTimeout`).
- Media con un decimale e la virgola in italiano (`NumberFormat('0.0', localeName)`): "7,7".
- Pannelli laterali da **360 px** (`ShellSidePanel` nella shell, `PlayerSidePanelHost` nel player); niente dialog, tranne la conferma admin (`showAdminConfirmDialog`, come le altre azioni distruttive della dashboard).
- Testi it/en dalla spec §9, più quelli della decisione 14.
- Icone solo `LucideIcons`, colori `WfColors`, `clock.now()` (mai `DateTime.now()`), durate con `WfMotion` e le animazioni ridotte rispettate. Nei log mai titoli, commenti o nomi: solo id, numeri, il nome del `SocialFailure` o il tipo dell'errore.
- Flutter è in `C:\Users\sidot\dev\flutter`. I test si lanciano con `flutter test`.
- Build per la prova a mano, esattamente:
  `flutter build windows --release --dart-define-from-file=config/wonderflix.json`
  `config/wonderflix.json` è ignorato da git: va copiato nel worktree dal checkout principale prima della build e non si committa.
- Commit con l'identità git configurata nel repository (hash_developer). **Mai** il trailer `Co-Authored-By` né righe di attribuzione ("Generated with…"), anche se il sistema le suggerisce. Nei messaggi mai `closes`, `fixes`, `resolves` (né altre parole che chiudono le issue). Niente push.
- **Mai** terminare processi per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`): solo per PID, oppure lo segnali.

## Review Focus

1. **Esc a video finito nel party, con il pannello del voto:** chiude il post-play e lascia l'utente nel party. Oggi `_escape` esce dal player e quindi dal party. Test: Task 4 (`Esc a video finito chiude il post-play e resta nel party`).
2. **Avviso `Revealed` perso** (WebSocket giù o avviso caduto): la coda non deve restare ferma oltre `EndsAt` + 5 s. Test: Task 2 (`ancora Voting 5 s dopo EndsAt: si rilegge`) e Task 4 (`votazione sparita a metà: avviso e coda libera`).
3. **Uscita dal party o tolti dal server durante la votazione:** il player che continua da solo non ha né pillola né coda ferma, e il controller si svuota. Test: Task 2 (`uscendo dal gruppo la votazione sparisce`) e Task 4 (`tolti dal gruppo durante la votazione: niente pillola`).
4. **Cifre scritte nel commento:** non cambiano il voto e non mandano reazioni; un "8" nel testo resta testo. Test: Task 4 (`tasti: cifre e frecce scelgono il voto, nel commento si scrivono`).
5. **Doppio clic su Vota o Salva:** una sola chiamata in volo. Test: Task 2 (`un secondo voto mentre il primo è in volo non parte`) e Task 6 (`Salva spento durante il salvataggio`).

---

## Regole per chi esegue

- Worktree `.claude/worktrees/piano-23b` (branch `piano-23b` da `main`). Tutti i comandi partono dalla sua root: fai prima `Set-Location` lì e non toccare mai il checkout principale.
- **Shell:** PowerShell. In ogni comando con `flutter`, `dart` o `git`, prima rinfresca il PATH:
  `$env:Path = 'C:\Users\sidot\dev\flutter\bin;' + [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
- **Commit:** vedi le Global Constraints. Su una riga sola, `git commit -m "feat(app): …"`. Comandi git semplici: niente `git -C`, e mai `git checkout -- <file>` su un file che hai modificato.
- **Test:**
  - un file: `flutter test test/percorso/del_test.dart`;
  - **prima di ogni commit** `flutter analyze` senza problemi e la suite intera tutta verde con **`flutter test --concurrency=4`** (con i 16 processi predefiniti il PC si è riavviato);
  - prima del Task 1 misura la base (numero di test verdi su `main`) e scrivila nel primo resoconto.
- **File generati:** dopo ogni modifica agli ARB `flutter gen-l10n` (`lib/l10n/gen/` non si committa; in un worktree nuovo va generato prima di tutto). Se `windows/flutter/generated_plugin*` cambia solo nei fine riga: `git checkout -- windows/flutter/` prima del commit.
- **Formattazione:** niente `dart format` su file interi, solo modifiche mirate. Ogni file tiene i suoi fine riga. Scrivi in UTF-8 con gli strumenti di modifica dei file, mai con `Set-Content` o `Out-File`.
- **Codice:** commenti in italiano, codice in inglese; durate, misure e limiti come costanti nominate e commentate.
- **Provider e test:** nei test di provider usa `container.listen(...)` prima di leggere un provider `autoDispose`; i container hanno `retry: (_, _) => null`. In un provider tutti i `ref.watch` stanno prima del primo `await`. Cattura `final ref = this.ref` prima delle attese e controlla `ref.mounted` dopo, come `MatchRoomController`.
- **Se il codice del piano ha un errore** (analyzer, firma diversa, `switch` esaustivo da completare in un file non elencato, icona Lucide con un altro nome), correggilo in modo minimo e segnalalo. Meglio correggere il codice che indebolire un test.

## Note tecniche verificate

Sul codice di `main` `faf815e` (2026-10-20):
- **`SocialApi`** (`lib/core/social/social_api.dart`): `_call` mappa 404 → `unavailable`, 400/401/403 → `forbidden`, 409 → `conflict`, 429 → `rateLimited`, il resto → `network`; `_quiet = {403, 404, 409, 429}`; corpi letti con `asJsonMap` e `jsonList` (`json_fields.dart`, dove c'è anche `jellyfinIdKey`). `FakeSocialApi` (`test/support/social_fakes.dart`): `nextFailure` (una volta), `calls`, gate `Completer`; `socialTestOverrides(api, events:, features:)`, `FakeSocialAvailability`.
- **Avvisi:** `parseSocialEvent` e `MatchUpdatedEvent` in `social_models.dart`; il tipo va aggiunto anche a `socialEventTypes` (`lib/core/party_channel/party_channel_models.dart`), altrimenti il canale del party lo legge come un suo evento. `socialEventsProvider` in `social_providers.dart`. Nel plugin `SocialEvent.State` ha `[JsonPropertyName("State")]`.
- **Funzioni:** `PluginFeatures` (`social_models.dart`); `SocialFeatures` con campo, `==`, `hashCode`, `toString` e una riga in `SocialAvailability.refresh()` (`_canJoin && …`); `describePluginFeatures` (`lib/features/settings/diagnostics.dart`).
- **Modello della votazione:** `MatchRoomController` (`lib/features/match/match_room_controller.dart`): `build` guarda utente e funzione, ascolta `socialEventsProvider` e `watchPartyEventsProvider` (`ServerConnected(isReconnect)` → `reload`); `_apply` accetta solo `rev` più alti.
- **Party:** `watchPartySessionProvider` (`WatchPartyState`: `inGroup`, `group.id`, `queue.playing` (`PlayQueueEntry {itemId, playlistItemId}`), `nextEntry`, `hasNext`); `WatchPartySession.nextItem(fromPlaylistItemId) → Future<bool>` scarta da sé se il gruppo è già altrove. `partyQueueItemsProvider` (`party_queue_items.dart`): `Map<String, JellyfinItem>` dei titoli in coda.
- **Player** (`player_screen.dart`): `widget.args.party` è il `playlistItemId`; `_inParty`, `_endZone` (`_updateEndZone` da posizione, durata e segmenti), `_nextOffer`, `_canOfferNext` (offerta, `ready`, `_firstFrame`, `!_chrome.postPlayDismissed`), `_postPlayShown` (= `credits` && `_canOfferNext`), `_cardShown` (= `lastSeconds` && `_canOfferNext`), `_dismissNext`, `_playOffered`, `_playNext` (nel party → `_requestNextInParty`, che annuncia sul canale), `_onFinished` (nel party: `nextItem` subito), `_escape` (a video finito esce), `_onKey` (cifre 1–6 → reazioni con il fuoco al player e il canale attivo; `_queueSearchFocused` → `_onQueueSearchKey`), `_handOverTo` (cambio di titolo, `pushReplacement`), `_partyDetached`. Il post-play (`player-post-play`) è dentro `ExcludeFocus`; la chat e il pannello della coda no (il pannello della coda è avvolto in `Focus(focusNode: _queuePanelFocusNode)`). `EndZone { none, credits, lastSeconds }` e `endZoneAt` in `segments.dart`.
- **Post-play** (`post_play.dart`): `PostPlayFrame(active:)`, `PostPlayLayer(episode:, countdown:, paused:, onPlay:, onWatchCredits:, label:)` con l'immagine a destra (`post-play-image`) in `Positioned(top: postPlayInset, left: postPlayInset + filmWidth + postPlayGap, right: postPlayInset, bottom: postPlayInset)`. `PlayNowButton` (`player_extras.dart`): `countdown`, `paused`, `onPressed`, `static const countdownFrom = 10`; con `paused` il conto è fermo (a video finito `playing` è falso).
- **Chrome** (`player_chrome.dart`): `enum PlayerPopup { tracks, chat, reactions, queue }`, `openPopup`/`closePopup`/`togglePopup`, `dismissPostPlay()`, `postPlayDismissed`. `PlayerSidePanelHost(open:, panel:)` da 360 px.
- **Pillola:** `party_notice_pill.dart` ha solo testi e icone degli avvisi; il disegno è in `PlayerPill` (`player_pill.dart`: `WfColors.surfaceHigh` al 92%, angoli 20, bordo `WfColors.border`, icona oro 18, padding 16×8). La pillola nuova lo copia ed è cliccabile.
- **Scheda:** `MovieDetailView` (anche per gli episodi aperti da soli) e `SeriesDetailView` (`_selectedSeasonId`, `_seasonToShow(list, next)` dentro `seasons.when`, `_SeasonTabs`); `StaggerGroup(count: detailEntranceCount)` con `StaggerItem(index: 5–7)` sotto la testata (0–4); `test/features/detail/detail_entrance_test.dart` controlla il conto. `watchUserData(ref, item)` e `userDataOverridesProvider` (`lib/features/library/user_data.dart`). `MediaRow(title:, height:, itemCount:, itemBuilder:, animateEntrance:, onTitleTap:)` (`lib/ui/media_row.dart`), senza un'azione a destra del titolo. `UserAvatar.lookup(userId:, name:, size:)`.
- **Pannelli della shell:** `ShellPanel { none, friends, inbox, recommend }` con lo `switch` in `ShellPanelController.open` (`lib/app/shell_panels.dart`); modello completo in `lib/features/recommendations/recommend_panel.dart` (`RecommendSubject`, `recommendSubjectProvider`, `openRecommendPanel`, `RecommendPanelHost` con `recommendPanelVisibleProvider`, `_capRunes` sui punti di codice, `TextField` con `textInputAction: done`). Host in `lib/app/app_shell.dart` (`Positioned.fill(child: RecommendPanelHost())`).
- **Admin:** `WonderflixTab` (`lib/features/admin/wonderflix_tab.dart`, `ListView` di card); `AdminCard(title:, icon:, child:)`, `AdminCardError(error:, onRetry:)`, `AdminEmptyText` (`admin_widgets.dart`); `AdminActionButton(label:, icon:, onPressed:)`; `adminTimeLabel(at, now, l)` (`admin_time.dart`); `showAdminConfirmDialog(context, title:, message:, confirmLabel:) → Future<bool>`; il testo "Serve il plugin …" come `adminNeedsPlugin170` in `home_admin_cards.dart`. `PluginAdminApi` (`lib/core/social/plugin_admin_api.dart`, `_quiet`, `parseJson`), `pluginAdminApiProvider` (`admin_providers.dart`), `FakePluginAdminApi` (`test/support/admin_fakes.dart`, `calls`, `actionError`).
- **Test del player nel party:** `test/features/watch_party/party_player_test.dart`, `pumpPartyPlayer(tester, segments:)` (gruppo `g1` con Mario e Luigi, `e4` in `p1`, episodio 4 della stagione 1), `queueSeries` (coda `e4, e5, e6` → `p1, p2, p3`), `toCredits`, `finish`, `emit(GroupUpdate)`, `engine.emitPosition/emitCompleted`, `api.calls` (`next p1`). Il cambio di titolo è `emit(PlayQueueUpdate('g1', testSeriesQueue(playingIndex: 1, reason: 'NextItem', lastUpdate: …)))`; i social non sono sovrascritti.
- **Release:** `docs/RELEASING.md` (riga `min-version` nelle note; checklist dei test manuali).

## File

| File | Responsabilità |
|---|---|
| `lib/core/social/rating_models.dart` | fasi, stati, `RatingRound`, `MyRating`, `ItemRatings`, `FriendRating`, `AdminComment`, `AdminCommentsPage` |
| `lib/core/social/social_api.dart`, `social_models.dart`, `lib/core/party_channel/party_channel_models.dart` (modifiche) | le 8 chiamate, `RatingRoundUpdatedEvent`, `PluginFeatures.ratings` |
| `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart` (modifiche) | `SocialFeatures.ratings` |
| `l10n/app_it.arb`, `l10n/app_en.arb` | testi |
| `lib/features/ratings/rating_round_controller.dart` | `RatingRoundView`, `RatingRoundController`, `ratingRoundProvider` |
| `lib/ui/rune_limit.dart` (+ `recommend_panel.dart`) | formatter dei 200 punti di codice, condiviso |
| `lib/features/ratings/rating_widgets.dart` | numeri 1–10, campo del commento, media formattata |
| `lib/features/ratings/rating_round_panel.dart` | pannello del voto (Voting/Revealed/non disponibile), pillola |
| `lib/features/player/player_screen.dart`, `post_play.dart`, `player_extras.dart`, `player_chrome.dart` (modifiche) | apertura, post-play, coda ferma, conto, tasti, pillola |
| `lib/features/ratings/friend_ratings_row.dart`, `lib/ui/media_row.dart`, `lib/features/detail/*_detail_view.dart`, `detail_header.dart` (modifiche) | riga della scheda |
| `lib/features/ratings/rate_panel.dart`, `lib/app/shell_panels.dart`, `lib/app/app_shell.dart` (modifiche) | pannello per votare dalla scheda |
| `lib/core/social/plugin_admin_api.dart`, `lib/features/admin/rating_comments_card.dart`, `wonderflix_tab.dart` (modifiche) | commenti admin |
| `test/support/rating_fakes.dart` (+ `social_fakes.dart`, `admin_fakes.dart`) | stati di prova, avvisi, metodi finti |

---

## Gruppo A — nucleo

### Task 1: modelli, chiamate, avviso, funzione e testi

**Files:**
- Create: `lib/core/social/rating_models.dart`, `test/support/rating_fakes.dart`
- Modify: `lib/core/social/social_api.dart`, `lib/core/social/social_models.dart`, `lib/core/party_channel/party_channel_models.dart`, `lib/features/social/social_providers.dart`, `lib/features/settings/diagnostics.dart`, `l10n/app_it.arb`, `l10n/app_en.arb`, `test/support/social_fakes.dart`
- Test: `test/core/social/rating_models_test.dart`, `test/core/social/rating_api_test.dart`, `test/core/social/social_models_test.dart` (test nuovi), `test/features/social/social_providers_test.dart` (un test), `test/app/l10n_plan23b_test.dart`

**Interfaces:**
- Produces:
  - `enum RatingPhase { voting('Voting'), revealed('Revealed') }` con `wire` e `fromWire(Object?)`: un valore sconosciuto vale `revealed`, così una votazione che non capiamo non ferma la coda;
  - `enum RatingVoterStatus { waiting, voted, skipped }` (`Waiting`/`Voted`/`Skipped`), sconosciuto → `waiting`;
  - `class MyRating { int score; String? comment }`; `class RatingVoter { userId, name, status }`; `class RatingResult { userId, name, int score, String? comment }`;
  - `class RatingRound { groupId, itemId, phase, int rev, DateTime endsAt (UTC), bool canReveal, MyRating? mine, List<RatingVoter> voters, List<RatingResult> results, double? average }` con `fromJson`, `RatingVoter? voter(String userId)` (id normalizzati), `int get votedCount`;
  - `class FriendRating { userId, name, int score, String? comment, DateTime updatedAt }`; `class ItemRatings { bool canRate, MyRating? mine, double? average, int count, List<FriendRating> friends }`;
  - `class AdminComment { userId, userName, itemId, title, int score, String comment, DateTime updatedAt }`; `class AdminCommentsPage { List<AdminComment> items; String? next }`;
  - un `Comment` vuoto vale `null` ovunque;
  - in `SocialApi`: `Future<RatingRound> openRatingRound(String groupId, String itemId)`, `Future<RatingRound?> ratingRound(String groupId)` (`{}` → `null`), `Future<RatingRound> voteInRound(String groupId, int score, String? comment)`, `skipRound(String groupId)`, `revealRound(String groupId)` (→ `RatingRound`), `Future<ItemRatings> itemRatings(String itemId)`, `Future<void> rate(String itemId, int score, String? comment)`, `Future<void> deleteRating(String itemId)`; tutte con `quietStatuses: _ratingQuiet` (decisione 4);
  - `PluginFeatures.ratings = 'ratings'`, `SocialFeatures.ratings`, "voti" in `describePluginFeatures`;
  - `final class RatingRoundUpdatedEvent extends SocialEvent { final RatingRound state; }`, letto da `parseSocialEvent` (`Type` `RatingRoundUpdated`, chiave `State`), e `'RatingRoundUpdated'` in `socialEventTypes`;
  - `FakeSocialApi`: `Map<String, RatingRound?> rounds` (per gruppo), `RatingRound? openRoundResult`, `Map<String, ItemRatings> itemRatingsById`, `Completer<void>? ratingGate` (voto nella votazione, `rate`, `deleteRating`), metodi che registrano `round-open G I`, `round G`, `round-vote G 8 testo|-`, `round-skip G`, `round-reveal G`, `ratings I`, `rate I 8 testo|-`, `unrate I`. Il voto, il salto e lo scopri rispondono con `rounds[G]`;
  - `test/support/rating_fakes.dart`: `Map<String, dynamic> ratingRoundJson({groupId = 'g1', itemId = 's1', phase = 'Voting', rev = 1, canReveal = false, mine, voters, results, average, endsAt})` (presenti di default Mario `u1` e Luigi `u2` in `Waiting`), `RatingRound testRatingRound({…stessi…})`, `PartyChannelReceived ratingRoundUpdatedReceived(Map<String, dynamic> state)`, `ItemRatings testItemRatings({canRate, mine, average, count, friends})`, `FriendRating testFriendRating(userId, name, score, {comment})`;
  - tutte le chiavi ARB della spec §9 e della decisione 14, con questi testi in più:

| Chiave | it | en |
|---|---|---|
| `ratingPartyAverage` | `{count, plural, =1{media del party · 1 voto} other{media del party · {count} voti}}` | `{count, plural, =1{party average · 1 rating} other{party average · {count} ratings}}` |
| `ratingSeason` | Stagione {season} | Season {season} |
| `ratingSpecials` | Speciali | Specials |
| `ratingYouSkipped` | Hai saltato | You skipped |
| `ratingPartyPill` | Voti del party | Party ratings |
| `ratingRevealedPill` | Voti scoperti | Ratings revealed |
| `ratingTimeLeft` | Ancora {time} | {time} left |
| `adminCommentsMore` | Altri | More |
| `adminCommentsEmpty` | Nessun commento | No comments |
| `adminCommentDeleteTitle` | Cancellare il commento? | Delete the comment? |
| `adminCommentDeleteMessage` | Il commento di {name} su {title} sparisce; il voto resta. | {name}'s comment on {title} will be removed; the rating stays. |

- [ ] **Step 1: test che falliscono**
  - `rating_models_test.dart`:
    - `una votazione scoperta`: JSON con `Phase: 'Revealed'`, `Rev: 3`, `EndsAt: '2026-10-20T21:02:00Z'`, `Mine: {Score: 8}`, tre `Voters` (uno per stato), due `Results` (`{Score: 9, Comment: 'Capolavoro'}`, `{Score: 6, Comment: ''}`), `Average: 7.5` → `phase == revealed`, `rev == 3`, `endsAt.isUtc`, `mine!.score == 8`, `mine!.comment == null`, gli stati nell'ordine, `results[1].comment == null`, `average == 7.5`, `votedCount == 1`.
    - `in Voting senza Results né Average`: `results` vuota, `average == null`; `Phase: 'Boh'` → `revealed`; `Status: 'Boh'` → `waiting`; `voter('U-1')` trova `u1` (id normalizzati).
    - `voti della scheda`: `{CanRate: true, Count: 2, Average: 7.7, Friends: [...]}` → valori; senza `Mine` né `Average` → `null`; `UpdatedAt` in UTC.
    - `pagina dei commenti`: due voci e `Next: '2026-10-19T10:00:00Z'` → `next` è quella stringa; senza `Next` → `null`.
  - `rating_api_test.dart` (`FakeAdapter`, come `recommendation_api_test.dart`):
    - `openRatingRound` → `POST /WonderFlixWatchParty/Ratings/Rounds` con `{GroupId: 'g1', ItemId: 'e4'}`; il JSON di risposta diventa `RatingRound`.
    - `ratingRound`: `GET …/Ratings/Rounds/g1`; con `{}` → `null`.
    - `voteInRound('g1', 8, null)` → `POST …/Rounds/g1/Vote` con `{Score: 8, Comment: null}`; `skipRound` → `…/Skip`; `revealRound` → `…/Reveal`.
    - `itemRatings('m1')` → `GET …/Ratings` con `itemId=m1`; `rate('m1', 7, 'Bello')` → `PUT …/Ratings/m1` `{Score: 7, Comment: 'Bello'}`; `deleteRating` → `DELETE …/Ratings/m1`.
    - errori: 400 → `SocialFailure.forbidden`, 409 → `conflict`, 429 → `rateLimited`, 404 → `unavailable`.
  - `social_models_test.dart`: `RatingRoundUpdated` con `State` → `RatingRoundUpdatedEvent` con `rev` e `itemId`; `socialEventTypes` lo contiene; `State` malformato → `null`.
  - `social_providers_test.dart`: `ratings` vale con `Info` che la elenca e `canJoin`; senza accesso ai watch party resta `false`.
  - `l10n_plan23b_test.dart`: tutte le chiavi nuove in it ed en, fra cui `ratingVoted(8)` = "Hai votato 8", `ratingVotedCount(2, 4)` = "Hanno votato 2 su 4", `ratingFriendsCount(1)` = "1 amico", `ratingFriendsCount(3)` = "3 amici", `ratingPartyAverage(1)` = "media del party · 1 voto", `ratingFriendsRowSeason('Stagione 2')` = "Voti degli amici · Stagione 2", `ratingMine(8)` = "Il tuo voto: 8", `adminCommentsNeedPlugin` = "Serve il plugin 1.11.0"; `en.ratingVotedCount(2, 4)` = "2 of 4 have rated".
- [ ] **Step 2:** `flutter test test/core/social/rating_models_test.dart test/core/social/rating_api_test.dart` → errori di compilazione.
- [ ] **Step 3: il codice.** I modelli come `recommendation_models.dart` (cast diretti, liste con `jsonList` o un `for`, date con `DateTime.parse(...).toUtc()`). `ratingRound` restituisce `null` se la mappa non ha `GroupId`. Nelle chiamate il commento va nel corpo così com'è: lo ripulisce il plugin. ARB, poi `flutter gen-l10n`.
- [ ] **Step 4:** PASS; `flutter analyze`; suite intera.
- [ ] **Step 5:** `git commit -m "feat(app): friend ratings models, plugin calls, event and texts"`

### Task 2: la votazione nell'app (`ratingRoundProvider`)

**Files:**
- Create: `lib/features/ratings/rating_round_controller.dart`
- Test: `test/features/ratings/rating_round_controller_test.dart`

**Interfaces:**
- Consumes: `SocialApi` e `RatingRound*` (Task 1), `watchPartySessionProvider`, `partyQueueItemsProvider`, `currentUserIdProvider`, `socialEventsProvider`, `watchPartyEventsProvider`.
- Produces:
  - costanti `ratingRoundKeep = Duration(minutes: 10)`, `ratingRevealGrace = Duration(seconds: 5)`, `ratingOpenTimeout = Duration(seconds: 5)`, `ratingMin = 1`, `ratingMax = 10`;
  - `enum RatingSendError { notSaved, tooMany }`;
  - `class RatingRoundView { RatingRound round; String playlistItemId; JellyfinItem? source; String userId; bool unavailable; int? draft; bool editing; bool sending; RatingSendError? error }` con `copyWith`, e i getter:
    - `RatingVoterStatus? get myStatus`;
    - `bool get showsPicker` = `!unavailable && phase == voting && (myStatus == waiting || myStatus == null || editing)`;
    - `bool holdsQueue(String playlistItemId)` = `!unavailable && phase == voting && playlistItemId` uguale (normalizzato);
  - `class RatingRoundController extends Notifier<RatingRoundView?>` con:
    - `Future<void> open({required String groupId, required JellyfinItem item, required String playlistItemId})`;
    - `void select(int score)`, `void step(int delta)`, `void edit()`;
    - `Future<void> vote(String? comment)`, `Future<void> skip()`, `Future<void> reveal()`;
    - `Future<void> reload()`, `void dismiss()`;
  - `final ratingRoundProvider = NotifierProvider<RatingRoundController, RatingRoundView?>(...)`.

- [ ] **Step 1: test che falliscono** (container con `socialTestOverrides(api, events:, features: SocialFeatures(friends: true, parties: true, ratings: true))`, `watchPartySessionProvider` finto in gruppo `g1` con la coda `p1, p2` e `p1` in riproduzione; `testUser` è `u1`):
  - `l'apertura applica lo stato e ricorda l'elemento della coda`: `api.openRoundResult = testRatingRound(mine: MyRating(score: 7))`; `open(groupId: 'g1', item: e4, playlistItemId: 'p1')` → `api.calls.last == 'round-open g1 e4'`, `holdsQueue('p1')` vero, `holdsQueue('p2')` falso, `draft == 7`, `source` è `e4`.
  - `due aperture per lo stesso elemento: una sola chiamata`.
  - `apertura non riuscita: nessuna votazione`: con `nextFailure = forbidden`, poi con `network` → lo stato resta `null`, nessuna eccezione.
  - `solo gli stati più recenti della stessa votazione contano`: dopo l'apertura (`rev: 2`), avvisi con `rev: 1` (ignorato), `groupId: 'g9'` (ignorato), `rev: 3` (applicato). Uno stato con `itemId: 'm2'` e `rev: 1` sostituisce la votazione, e così uno con lo stesso `itemId` ma un altro `endsAt` (decisione 10).
  - `un avviso arrivato prima dell'apertura si adotta`: nessuna apertura, arriva `ratingRoundUpdatedReceived(...)` per `g1` → vista con `playlistItemId == 'p1'` (quello in riproduzione).
  - `voto: numero e commento, poi lo stato del plugin`: `select(8)`; `vote('Bello')` → `round-vote g1 8 Bello`; lo stato è `api.rounds['g1']` (`Voted`), `editing` falso, `sending` falso.
  - `un secondo voto mentre il primo è in volo non parte`: `api.ratingGate` aperto, due `vote(null)` → un solo `round-vote`.
  - `voto non riuscito`: `rateLimited` → `error == tooMany`; `network` → `notSaved`; `conflict` → `api.calls` contiene `round g1` (rilettura).
  - `select e step restano fra 1 e 10`: `select(0)` → ignorato; `step(+1)` da `null` → 1; `step(-1)` da 1 → 1; `step(+1)` da 10 → 10.
  - `Cambia riapre i numeri`: stato `Voted` → `showsPicker` falso; `edit()` → vero, `draft` = `mine.score`.
  - `skip e reveal`: `skip()` → `round-skip g1`; `reveal()` → `round-reveal g1`.
  - `Revealed non ferma la coda e dopo 10 minuti sparisce` (`fakeAsync`): avviso `Revealed` → `holdsQueue('p1')` falso; dopo `ratingRoundKeep` lo stato è `null`.
  - `ancora Voting 5 s dopo EndsAt: si rilegge` (`fakeAsync`, `endsAt` = adesso + 2 min): dopo 2 min e 5 s `api.calls` contiene `round g1`; se intanto è arrivato `Revealed`, nessuna rilettura.
  - `riconnessione: si rilegge; {} vuol dire non disponibile`: `api.rounds['g1'] = null`, `ServerConnected(isReconnect: true)` → `unavailable` vero, `holdsQueue('p1')` falso.
  - `uscendo dal gruppo la votazione sparisce`: la sessione esce dal gruppo → stato `null`; con la funzione spenta → `null`.
  - `dismiss toglie la votazione`.
- [ ] **Step 2:** `flutter test test/features/ratings/rating_round_controller_test.dart` → errori di compilazione.
- [ ] **Step 3: il codice.** `build` come `MatchRoomController`: guarda l'utente, `socialAvailabilityProvider.select((f) => f.ratings)` e `watchPartySessionProvider.select((s) => s.inGroup ? jellyfinIdKey(s.group!.id) : null)`, e senza gruppo o senza funzione restituisce `null`. Ascolta `RatingRoundUpdatedEvent` e `ServerConnected(isReconnect)`. `ref.onDispose` cancella abbonamenti e timer. `_apply(RatingRound next)` decide così:
  - `next` di un altro gruppo: si scarta;
  - stessa votazione (`itemId` ed `endsAt` uguali) con `rev` non più alto: si scarta;
  - un'altra votazione, oppure nessuna vista: vista nuova, con `playlistItemId` = la vista che si sta aprendo, altrimenti la coda in riproduzione, e `source` da `partyQueueItemsProvider`;
  - in ogni caso `draft` parte da `mine?.score` solo se non c'è già.

  Dopo ogni `_apply` ci sono due timer: quello della rilettura a `endsAt + ratingRevealGrace` (in `Voting`) e quello di `ratingRoundKeep`, che parte alla prima vista di `Revealed`. `open` usa `.timeout(ratingOpenTimeout)` e mette gli errori nel log con il nome del `SocialFailure`. `vote` esce subito se `sending` o se `draft` è `null`. Il commento è `null` se vuoto dopo `trim()`.
- [ ] **Step 4:** PASS; analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): party rating round controller"`

## Gruppo B — fine del film nel party

### Task 3: numeri, commento, pannello del voto e pillola

**Files:**
- Create: `lib/ui/rune_limit.dart`, `lib/features/ratings/rating_widgets.dart`, `lib/features/ratings/rating_round_panel.dart`
- Modify: `lib/features/recommendations/recommend_panel.dart` (usa `capRunes`)
- Test: `test/features/ratings/rating_widgets_test.dart`, `test/features/ratings/rating_round_panel_test.dart`

**Interfaces:**
- Consumes: `ratingRoundProvider`, `RatingRoundView` (Task 2); testi (Task 1); `UserAvatar.lookup`, `formatClock`, `WfMotion`.
- Produces:
  - `TextInputFormatter capRunes(int max)` (`lib/ui/rune_limit.dart`); `recommend_panel.dart` usa `capRunes(recommendMessageMax)` al posto di `_capRunes`;
  - `const ratingCommentMax = 200`;
  - `RatingScorePicker({int? selected, required ValueChanged<int> onSelect, bool enabled = true})`: dieci pulsanti in fila con chiavi `rating-score-1` … `rating-score-10`; quello scelto è oro;
  - `RatingCommentField({required TextEditingController controller, FocusNode? focusNode, VoidCallback? onSubmitted})`: `maxLength: ratingCommentMax`, `capRunes`, `minLines: 1`, `maxLines: 3`, `textInputAction: done`, hint `ratingCommentHint`;
  - `String formatRatingAverage(double value, String localeName)` (`NumberFormat('0.0', localeName)`);
  - `String ratingTitle(AppLocalizations l, JellyfinItem item)`: un film dà il nome; un episodio dà "{seriesName} · {ratingSeason(parentIndexNumber)}", con la stagione 0 "{seriesName} · Speciali";
  - `RatingRoundPanel({required VoidCallback onClose, FocusNode? commentFocusNode})` (`ConsumerStatefulWidget`, legge `ratingRoundProvider`): in `Voting`, in `Revealed`, oppure non disponibile;
  - `RatingRoundPill({required RatingPhase phase, required VoidCallback onTap})`: chiave `rating-pill`, testo `ratingPartyPill` o `ratingRevealedPill`, icona `LucideIcons.star`, nello stile di `PlayerPill`.

- [ ] **Step 1: test che falliscono** (`pumpApp`, `ratingRoundProvider` sovrascritto con un controller finto che parte da una `RatingRoundView` data e registra `select`, `vote`, `skip`, `reveal`, `edit`):
  - `rating_widgets_test.dart`:
    - `dieci numeri; il tocco sceglie`: tap su `rating-score-7` → `onSelect(7)`.
    - `il commento si ferma a 200 punti di codice`: 199 lettere più un'emoji di due unità → `controller.text.runes.length == 200`; Invio chiama `onSubmitted` e non va a capo.
    - `media con la virgola in italiano`: `formatRatingAverage(7.7, 'it')` = `'7,7'`; `(8, 'en')` = `'8.0'`.
    - `titolo del voto`: film "Il Padrino" → "Il Padrino"; episodio di Breaking Bad, stagione 2 → "Breaking Bad · Stagione 2"; stagione 0 → "Breaking Bad · Speciali".
  - `rating_round_panel_test.dart`:
    - `Voting: numeri, commento, Vota spento finché non c'è un numero`: con `source` = film "Il Padrino" il titolo è "Il tuo voto · Il Padrino"; Vota ha `onPressed == null` con `draft: null`; con `draft: 8`, il tap su Vota fa `vote('')` (testo del campo), il tap su Salta fa `skip`.
    - `presenti con la spunta e ha saltato, mai i voti degli altri`: Mario `Voted`, Luigi `Skipped`, Peach `Waiting` → "Hanno votato 1 su 3", la spunta (chiave `rating-voter-done-u1`), "ha saltato" accanto a Luigi; non c'è nessun numero da 1 a 10 fuori dai pulsanti.
    - `tempo che resta`: `endsAt` = adesso + 83 s → "Ancora 1:23"; dopo `pump(1 s)` → "Ancora 1:22"; mai sotto "0:00".
    - `Scopri i voti solo con CanReveal`: `canReveal: false` → nessun pulsante; `true` → tap → `reveal`.
    - `dopo il voto: Hai votato 8 e Cambia`: stato `Voted` con `mine: 8` e `showsPicker` falso → "Hai votato 8" e "Cambia"; tap su Cambia → `edit`. Con `Skipped` → "Hai saltato" e "Cambia".
    - `errore del voto`: `error: tooMany` → "Troppi voti: riprova più tardi"; `notSaved` → "Voto non salvato".
    - `Revealed: media del party e risultati`: `average: 7.5`, risultati Luigi 9 "Capolavoro" e Mario (`u1`) 6 → "7,5", "media del party · 2 voti", le righe "Luigi" e "Tu" con i voti e il commento, "Puoi cambiare il tuo voto dalla scheda del film"; nessun numero da scegliere.
    - `Revealed con le animazioni ridotte: tutte le righe subito`: con `pumpApp` (movimento ridotto) dopo un `pump()` le due righe sono visibili con opacità 1.
    - `non disponibile`: `unavailable: true` → "Votazione non disponibile: puoi votare dalla scheda".
    - `commento iniziale da Mine`: `mine: MyRating(score: 8, comment: 'Ottimo')` → il campo contiene "Ottimo".
    - `pillola`: `RatingRoundPill(phase: voting)` → "Voti del party"; `revealed` → "Voti scoperti"; il tap chiama `onTap`.
- [ ] **Step 2:** i test falliscono per compilazione.
- [ ] **Step 3: il codice.** Il pannello è una `Material` scura (`WfColors.surface` al 92%, angoli `postPlayRadius`) a colonna:
  - **Voting:** intestazione (`ratingYourVote` · titolo da `source`, se c'è); `RatingScorePicker` (che scrive con `select`) oppure "Hai votato {n}"/"Hai saltato" con Cambia; il commento; Vota (`WfButton.primary`) e Salta (`WfButton.secondary`), spenti mentre `sending`; `ratingVotedCount(votedCount, voters.length)`; l'elenco dei presenti (avatar 28, nome, spunta `LucideIcons.check` o `ratingSkipped`); "Ancora m:ss" in piccolo, da un `Timer.periodic` di 1 s (`shortcut: orologio del PC, non quello del server; da cambiare se gli scarti danno fastidio`); Scopri i voti con `canReveal`.
  - **Revealed:** la media `WfText.display(56)` e `ratingPartyAverage(results.length)`, poi le righe (avatar, "Tu" se `userId` è il mio, voto in oro, commento come `Text`). Tutte le righe entrano insieme con un `TweenAnimationBuilder` (`WfMotion.medium`, `emphasized`, dissolvenza più 12 px dal basso; con le animazioni ridotte niente spostamento); sotto c'è `ratingChangeLater`.
  - Il `TextEditingController` del commento parte da `mine?.comment`; Invio nel campo fa Vota se `draft` c'è.
- [ ] **Step 4:** PASS (anche `recommend_panel_test.dart`); analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): party rating panel, score picker and pill"`

### Task 4: il voto nel player del party

**Files:**
- Modify: `lib/features/player/player_screen.dart`, `lib/features/player/post_play.dart`, `lib/features/player/player_extras.dart`, `lib/features/player/player_chrome.dart`
- Test: `test/features/watch_party/party_player_test.dart` (gruppo nuovo `voti del party`), `test/features/player/player_extras_test.dart`, `test/features/player/post_play_test.dart`

**Interfaces:**
- Consumes: `ratingRoundProvider`, `holdsQueue`, `showsPicker`, `open`, `select`, `step`, `dismiss`, `ratingOpenTimeout` (Task 2); `RatingRoundPanel`, `RatingRoundPill` (Task 3).
- Produces:
  - `PlayNowButton(..., int seconds = PlayNowButton.countdownFrom)`: il conto parte da `seconds` (anche la larghezza riservata dell'etichetta);
  - `PostPlayLayer(...)` con `JellyfinItem? episode` (con `null` niente colonna sotto il film), `bool showImage = true`, `bool waiting = false` (al posto di `PlayNowButton` c'è `WfButton.primary(label: l.ratingWaiting, onPressed: null)`, chiave `post-play-waiting`) e `int countdownSeconds = PlayNowButton.countdownFrom`;
  - `Rect postPlaySideRect(Size size)` in `post_play.dart`: il riquadro a destra del film piccolo, lo stesso dell'immagine; lo usano l'immagine e lo strato del voto;
  - `PlayerPopup.rating`;
  - `const ratingReleaseDelay = Duration(seconds: 15)`, `const ratingPillBottom = 210.0` (in `player_screen.dart`).

- [ ] **Step 1: test che falliscono.**
  - `player_extras_test.dart`: `il conto può partire da 15`: `PlayNowButton(countdown: true, seconds: 15, onPressed: …)` → "Riproduci ora · 15"; dopo 15 s `onPressed` una volta.
  - `post_play_test.dart`: `senza il prossimo titolo e senza immagine`: `PostPlayLayer(episode: null, showImage: false, …)` → nessun `post-play-image`, nessun `PlayNowButton`; `waiting: true` → `post-play-waiting` spento.
  - `party_player_test.dart`: `pumpPartyPlayer(…, FakeSocialApi? social)`. Con `social` aggiunge `socialApiProvider` e `socialAvailabilityProvider` (`FakeSocialAvailability(SocialFeatures(friends: true, parties: true, ratings: true))`). `social.openRoundResult = testRatingRound(itemId: 's1')`, e `social.rounds['g1']` segue le risposte. Test:
    - `ai titoli di coda si apre la votazione nel post-play`: `segments: credits`, `queueSeries`, `toCredits` → `social.calls` contiene `round-open g1 e4`; si vede "Il tuo voto · Breaking Bad · Stagione 1" e il prossimo titolo; non c'è `post-play-image`; c'è `post-play-waiting` spento e nessun `PlayNowButton`.
    - `senza Outro si apre a video finito, non prima`: negli ultimi 30 s la scheda piccola come oggi e nessun `round-open`; `engine.emitCompleted()` → `round-open g1 e4`, il post-play con il pannello, e `api.calls` non contiene `next p1`.
    - `con 400 niente pannello e la coda va avanti`: `social.nextFailure = forbidden`; a video finito `api.calls` contiene `next p1` e non c'è "Il tuo voto". Lo stesso con `network`.
    - `in Voting il video finito non chiama nextItem; a Revealed 15 s e poi nextItem`: `credits`, `queueSeries`, `toCredits`, `emitCompleted` → niente `next p1`; arriva `ratingRoundUpdatedReceived(ratingRoundJson(phase: 'Revealed', rev: 2, results: […], average: 8))` → si vede "Riproduci ora · 15"; `pump(14 s)` → niente `next p1`; `pump(1 s)` → `next p1` una volta sola (contando anche lo scatto del pulsante).
    - `Revealed con il post-play chiuso: la coda riparte lo stesso`: come sopra, ma prima "Guarda i titoli" → la pillola `rating-pill`; dopo `Revealed` e 15 s → `next p1`.
    - `Revealed col video ancora in corso: come oggi`: `Revealed` ai titoli → `PlayNowButton` attivo senza conto; il tap → `next p1`.
    - `coda vuota: il post-play solo per il voto`: senza `queueSeries`, `toCredits` → pannello senza prossimo titolo; `Revealed` a video finito → nessun `next`, il pannello resta.
    - `votazione sparita a metà: avviso e coda libera`: video finito in `Voting`, `social.rounds['g1'] = null`, `events.add(const ServerConnected(isReconnect: true))` → "Votazione non disponibile: puoi votare dalla scheda" e `next p1`.
    - `Esc a video finito chiude il post-play e resta nel party`: video finito in `Voting`, Esc → il post-play sparisce, si vede `rating-pill`, `PlayerScreen` c'è ancora e `api.calls` non contiene `leave`.
    - `tasti: cifre e frecce scelgono il voto, nel commento si scrivono`: pannello in `Voting`. "8" → `rating-score-8` scelto; "0" → 10; ← → 9. Nessuna reazione mandata (`channelApi` senza invii di reazioni). Poi tap sul campo e "8" → il campo contiene "8" e la scelta resta 9.
    - `la pillola apre il pannello a lato`: post-play chiuso → tap su `rating-pill` → `RatingRoundPanel` dentro `PlayerSidePanelHost` aperto; ✕ in `Voting` lo chiude e la pillola resta; in `Revealed` ✕ → la pillola sparisce (decisione 6).
    - `cambio di titolo durante Voting: il player nuovo non ferma la coda`: ai titoli in `Voting`, `emit(PlayQueueUpdate(... playingIndex: 1, reason: 'NextItem' ...))` → nel player di `e5` c'è `rating-pill` con "Voti del party"; `emitCompleted` del nuovo motore → `next p2`. Arriva `Revealed` → la pillola dice "Voti scoperti".
    - `tolti dal gruppo durante la votazione: niente pillola`: `emit(const GroupLeft('g1'))` → nessun `rating-pill`, e il player continua da solo come oggi.
    - `Scopri i voti nel post-play solo con CanReveal`: `canReveal: true` → tap → `social.calls` contiene `round-reveal g1`.
- [ ] **Step 2:** i test falliscono.
- [ ] **Step 3: il codice.**
  - **Apertura:** `_maybeOpenRating()` parte una volta per player (`_ratingRequested`), solo se `_inParty`, la sessione è `inGroup`, c'è `ratings`, e `view.item` è un film o un episodio. Chiama `open(groupId: party.group!.id, item: view.item!, playlistItemId: widget.args.party!)`. La chiamano `_updateEndZone`, quando la zona diventa `credits`, e `_onFinished`.
  - **Viste:** `_ratingHere` = la vista c'è e `playlistItemId` è quello di questo player. Il post-play diventa:
    - `_postPlayShown` = `!postPlayDismissed && ready && _firstFrame && (credits || (_inParty && view.finished && _ratingHere)) && (_nextOffer(view) != null || _ratingHere)`;
    - `_cardShown` resta com'è, ma è falso quando c'è il post-play.
    Lo strato `player-post-play` passa `episode: offer`, `showImage: !_ratingHere` e `waiting: _holding`; con il conto attivo passa anche `countdown: true`, `countdownSeconds: _releaseLeft` e `paused: false`. La chiave è `ValueKey(offer?.id ?? 'rating')`.
  - **Pannello nel post-play:** uno strato nuovo `Positioned.fromRect(postPlaySideRect(size))` dopo `player-post-play`, **fuori** da `ExcludeFocus` e avvolto in `Focus(focusNode: _ratingPanelFocusNode)`, con `RatingRoundPanel` quando il post-play c'è e `_ratingHere`.
  - **Coda ferma:** `_holding` = `ref.watch(ratingRoundProvider.select((v) => v?.holdsQueue(widget.args.party ?? '') ?? false))`.
    - `_onFinished` nel party chiama `unawaited(_finishInParty())`: se serve, `await` dell'apertura; poi, se il player non è in uscita e `!_holding`, `nextItem` come oggi.
    - Un `ref.listen` sul passaggio di `_holding` da vero a falso, a video finito: con la fase `revealed`, `_startRelease()` (`_releaseAt = clock.now() + ratingReleaseDelay`, `_releaseTimer`); altrimenti `_releaseQueue()` subito (decisione 8).
    - `_releaseQueue()` ha una guardia (`_released`) e chiama `nextItem(widget.args.party!)` della sessione. Il `PlayNowButton` del conto ha `onPressed: _releaseQueue`.
    - `_releaseLeft` = i secondi che restano fino a `_releaseAt`, arrotondati in su, almeno 1.
    - `_releaseTimer` si cancella in `dispose` e in `_handOverTo`.
  - **Chiudere:** `_escape` chiude il post-play anche a video finito nel party (`_postPlayShown(view) && (!view.finished || _inParty)`, decisione 7). In `Revealed` `_dismissNext` chiama anche `dismiss()` (decisione 6).
  - **Tasti** in `_onKey`, dopo chat e ricerca: se `_ratingPanelFocusNode.hasFocus` (dentro c'è il campo) → `_onQueueSearchKey(event)`. Poi, se il pannello si vede (post-play con `_ratingHere`, oppure `PlayerPopup.rating`), `showsPicker` è vero e non ci sono Ctrl/Alt/Meta: su `KeyDownEvent` le cifre `digit1`–`digit9`/`numpad1`–`numpad9` fanno `select(n)`, `digit0`/`numpad0` fa `select(10)`, ←/→ fanno `step(-1/+1)`; risposta `handled`. Va prima delle reazioni.
  - **Pillola e pannello a lato:** `Positioned(right: 32, bottom: ratingPillBottom)` con `RatingRoundPill`. Si vede se la vista c'è, il post-play con il pannello non c'è e `PlayerPopup.rating` non è aperto. Il tap fa `openPopup(PlayerPopup.rating)`. `PlayerSidePanelHost(open: popup == rating, panel: RatingRoundPanel(onClose: …))`, avvolto in `Focus(_ratingPanelFocusNode)` come la coda. Senza vista il popup si chiude (`ref.listen`). Completa gli `switch` su `PlayerPopup` che l'analyzer segnala.
- [ ] **Step 4:** PASS (tutti i test di `party_player_test.dart` e `player_screen_test.dart` restano verdi); analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): rate the title in the party post-play with the queue on hold"`

## Gruppo C — scheda e admin

### Task 5: la riga "Voti degli amici"

**Files:**
- Create: `lib/features/ratings/friend_ratings_row.dart`
- Modify: `lib/ui/media_row.dart`, `lib/features/detail/movie_detail_view.dart`, `lib/features/detail/series_detail_view.dart`, `lib/features/detail/detail_header.dart`
- Test: `test/features/ratings/friend_ratings_row_test.dart`, `test/features/detail/detail_entrance_test.dart` (conto), `test/ui/media_row_test.dart` (se c'è; altrimenti nel test della riga)

**Interfaces:**
- Consumes: `SocialApi.itemRatings`, `ItemRatings` (Task 1); `formatRatingAverage` (Task 3); `openRatePanel` (Task 6; in questo task il tap chiama un callback, e il Task 6 lo collega).
- Produces:
  - `MediaRow(..., Widget? trailing)`: a destra nell'intestazione;
  - `final itemRatingsProvider = FutureProvider.autoDispose.family<ItemRatings, String>(...)`;
  - `FriendRatingsRow({required JellyfinItem item, String? title, ValueChanged<ItemRatings>? onRate})`: `title` di default `ratingFriendsRow`; chiavi `friend-ratings-average`, `friend-rating-<userId>`, `friend-ratings-action`;
  - `detailEntranceCount = 9`; le righe sotto la testata hanno gli indici 5–8.

- [ ] **Step 1: test che falliscono** (`pumpApp`, `socialTestOverrides(api, features: SocialFeatures(friends: true, ratings: true))`):
  - `senza la funzione nessuna riga e nessuna chiamata`: `features: SocialFeatures(friends: true)` → niente `friend-ratings-average`, `api.calls` senza `ratings m1`.
  - `media, numero e card degli amici`: `average: 7.7`, `count: 3`, tre amici (uno con un commento di 300 lettere) → "7,7", "3 amici", le tre card con nome e voto; il commento ha `maxLines: 3` e `TextOverflow.ellipsis`; un `Tooltip` con il commento intero.
  - `nessun voto ma si può votare`: `friends: []`, `canRate: true` → "Ancora nessun voto degli amici" e "Vota" (`friend-ratings-action`) → `onRate` con le `ItemRatings`.
  - `il mio voto a destra`: `mine: MyRating(score: 8)` → "Il tuo voto: 8" con `LucideIcons.pencil`; senza `canRate` né `mine` → niente azione.
  - `niente amici e niente voto possibile: nessuna riga`; `errore: nessuna riga` (`nextFailure = forbidden`).
  - `si rilegge quando cambia Visto`: `userDataOverridesProvider` mette `played: true` su `m1` → un secondo `ratings m1`.
  - Nella scheda (`MovieDetailView`/`SeriesDetailView` montate come nei loro test): `film: la riga sta tra la testata e il Cast` (posizione verticale); `episodio aperto da solo: nessuna riga` (decisione 16); `serie: la riga della stagione scelta, prima delle schede` → "Voti degli amici · Stagione 1" e `ratings season1`; il tap sulla scheda "Stagione 2" → "Voti degli amici · Stagione 2" e `ratings season2`.
  - `detail_entrance_test.dart`: `group.count == 9`.
- [ ] **Step 2:** i test falliscono.
- [ ] **Step 3: il codice.**
  - **Visibilità:** si vede con `ratings` e con `friends.isNotEmpty || canRate`. Mentre carica e con un errore c'è `SizedBox.shrink()`; l'errore va nel log con il nome del `SocialFailure`.
  - **Contenuto:** `MediaRow` con `itemCount = friends.length + 1`. L'elemento 0 è il riquadro della media (`WfText.display(40)` e `ratingFriendsCount`, oppure `ratingNoFriendsYet`); le card sono larghe 220 con `UserAvatar.lookup(size: 32)`, nome, voto in oro e commento.
  - **Riletture:** `ref.listen(userDataOverridesProvider.select((m) => m[item.id]?.played), …)` fa `ref.invalidate(itemRatingsProvider(item.id))`.
  - **Film:** `if (item.kind == ItemKind.movie) StaggerItem(index: 5, child: FriendRatingsRow(item: item))`, poi Cast 6, Saghe 7, Simili 8.
  - **Serie:** il `seasonId` si calcola fuori da `seasons.when` (con `seasons.value`), e la stagione scelta va in `FriendRatingsRow(item: season, title: l.ratingFriendsRowSeason(season.name))` all'indice 5, con la chiave `ValueKey(season.id)`; poi stagioni 6, Cast 7, Simili 8.
- [ ] **Step 4:** PASS (i test delle schede restano verdi); analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): friends' ratings row on movie and season pages"`

### Task 6: votare dalla scheda (pannello laterale)

**Files:**
- Create: `lib/features/ratings/rate_panel.dart`
- Modify: `lib/app/shell_panels.dart`, `lib/app/app_shell.dart`, `lib/features/detail/movie_detail_view.dart`, `lib/features/detail/series_detail_view.dart`
- Test: `test/features/ratings/rate_panel_test.dart`

**Interfaces:**
- Consumes: `SocialApi.rate/deleteRating`, `itemRatingsProvider`, `FriendRatingsRow.onRate` (Task 5); `RatingScorePicker`, `RatingCommentField` (Task 3).
- Produces:
  - `ShellPanel.rate`;
  - `class RateSubject { JellyfinItem item; String title; MyRating? mine }`;
  - `rateSubjectProvider` (`NotifierProvider<RateSubjectController, RateSubject?>`, con `set`);
  - `void openRatePanel(WidgetRef ref, RateSubject subject)`;
  - `RatePanel({required RateSubject subject})`, `RatePanelHost()` (con `ratePanelVisibleProvider`, come `RecommendPanelHost`).

- [ ] **Step 1: test che falliscono** (`RatePanel` in una `SizedBox(width: 360)`, `socialTestOverrides(... ratings: true)`):
  - `locandina, titolo, numeri e commento dal mio voto`: `mine: MyRating(score: 8, comment: 'Bello')` → titolo, `rating-score-8` scelto, il campo con "Bello", "Togli il mio voto".
  - `Salva spento senza numero; Salva manda e chiude`: senza `mine` → Salva spento; tap su `rating-score-7`, poi Salva → `api.calls` contiene `rate m1 7 -`, il pannello si chiude (`shellPanelProvider == ShellPanel.none`) e `itemRatingsProvider('m1')` si rilegge (un secondo `ratings m1`).
  - `Togli il mio voto solo con Mine`: senza `mine` non c'è; con `mine` → tap → `unrate m1`, il pannello si chiude.
  - `errore: il pannello resta con il motivo`: `nextFailure = network` → "Voto non salvato"; `rateLimited` → "Troppi voti: riprova più tardi"; il pannello è aperto.
  - `Salva spento durante il salvataggio`: `api.ratingGate` aperto, due tap → un solo `rate`.
  - Nella scheda: `Vota apre il pannello`: tap su `friend-ratings-action` → `shellPanelProvider == ShellPanel.rate` e il soggetto è il film (per la serie, la stagione con il titolo "Breaking Bad · {season.name}").
- [ ] **Step 2:** i test falliscono.
- [ ] **Step 3: il codice.** Come `recommend_panel.dart`:
  - **Soggetto e host:** un soggetto nuovo vuol dire un pannello nuovo (`ValueKey(item.id)`). L'host va in `app_shell.dart` dopo `RecommendPanelHost`. In `ShellPanelController.open`, `ShellPanel.rate` sta con `recommend` (il soggetto lo imposta chi apre).
  - **Contenuto:** locandina (`imageUrlsProvider.poster(item)`, 80×120, angoli 6) e titolo; `RatingScorePicker`; `RatingCommentField`; Salva (`WfButton.primary`); "Togli il mio voto" (`WfButton.secondary`, icona `LucideIcons.trash2`).
  - **Esito:** riuscito, si chiude il pannello e si fa `ref.invalidate(itemRatingsProvider(item.id))`. Con un errore l'avviso sta dentro il pannello.
  - **Nella scheda:** `onRate` delle due schede chiama `openRatePanel`.
- [ ] **Step 4:** PASS; analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): rate from the title page in a side panel"`

### Task 7: commenti nella dashboard admin

**Files:**
- Create: `lib/features/admin/rating_comments_card.dart`
- Modify: `lib/core/social/plugin_admin_api.dart`, `lib/features/admin/wonderflix_tab.dart`, `test/support/admin_fakes.dart`
- Test: `test/core/social/plugin_admin_api_test.dart` (test nuovi), `test/features/admin/rating_comments_card_test.dart`

**Interfaces:**
- Consumes: `AdminComment`, `AdminCommentsPage` (Task 1); `SocialFeatures.ratings`.
- Produces:
  - `PluginAdminApi.ratingComments({String? before}) → Future<AdminCommentsPage>`, `PluginAdminApi.deleteRatingComment(String userId, String itemId) → Future<void>`;
  - in `FakePluginAdminApi`: `List<AdminCommentsPage> commentPages` (una per chiamata, nell'ordine), `calls` `comments:<before|->`, `deleteComment:<userId>:<itemId>`, e `actionError` vale anche per la cancellazione;
  - `class RatingCommentsState { List<AdminComment> items; String? next; bool loadingMore; Object? error }`;
  - `ratingCommentsProvider` (`NotifierProvider.autoDispose<RatingCommentsController, AsyncValue<RatingCommentsState>>`), con `more()` e `delete(AdminComment)`;
  - `RatingCommentsCard()`, nella `ListView` di `WonderflixTab` dopo `AnnouncementCard`.

- [ ] **Step 1: test che falliscono.**
  - `plugin_admin_api_test.dart`:
    - `ratingComments()` → `GET /WonderFlixWatchParty/Ratings/Admin/Comments` senza `before`;
    - `ratingComments(before: '2026-10-19T10:00:00Z')` → la query `before` è quella; la pagina con `Next` si legge;
    - `deleteRatingComment('u2', 'm1')` → `DELETE …/Ratings/Admin/Comments/u2/m1`.
  - `rating_comments_card_test.dart` (con `pumpApp` e `FakePluginAdminApi`, come `wonderflix_tab_test.dart`):
    - `elenco: nome, titolo, voto, commento, data`: due voci → "Luigi", "Il Padrino (1972)", "9", il commento intero e la data relativa (`adminTimeLabel`).
    - `Altri finché c'è Next`: la prima pagina con `next` → "Altri" → `comments:<next>` e le voci della seconda pagina in fondo; la seconda senza `next` → niente "Altri".
    - `cancellare con conferma`: "Cancella commento" → dialog con `adminCommentDeleteTitle` → conferma → `deleteComment:u2:m1` e la voce sparisce; con Annulla nessuna chiamata.
    - `cancellazione non riuscita: la voce resta e c'è l'errore` (`actionError`).
    - `senza la funzione: Serve il plugin 1.11.0 e nessuna chiamata`.
    - `nessun commento`: pagina vuota → "Nessun commento".
- [ ] **Step 2:** i test falliscono.
- [ ] **Step 3: il codice.** Le chiamate usano `_quiet` e `parseJson`. Il controller carica in `build` (con un `await` dopo i `watch`), e `more` aggiunge in fondo. `delete` toglie la voce solo se la chiamata riesce e la cancella dalla lista per `userId` + `itemId` normalizzati. La card è `AdminCard(title: l.adminCommentsTitle, icon: LucideIcons.messageSquare)`. Ogni voce mostra nome, titolo, voto, commento intero e data, con `AdminActionButton(label: l.adminCommentDelete, icon: LucideIcons.trash2)`. In fondo c'è "Altri". Senza la funzione la card mostra `adminCommentsNeedPlugin`, con il commento `shortcut:` della decisione 15.
- [ ] **Step 4:** PASS; analyze; suite.
- [ ] **Step 5:** `git commit -m "feat(app): user comments card in the admin dashboard"`

## Gruppo D — chiusura

### Task 8: versione 0.17.0, spec e build

**Files:** Modify `pubspec.yaml`, `docs/RELEASING.md`, `docs/superpowers/specs/2026-10-20-wonderflix-voti-amici-design.md`

- [ ] `pubspec.yaml`: `version: 0.17.0`.
- [ ] `docs/RELEASING.md`: nella checklist dei test manuali, dopo il match, una voce "Voti degli amici". Contiene il voto nel post-play del party con due istanze (scoperta per tutti votato, per tempo scaduto e con il pulsante; uscita dal party), il voto dalla scheda e la cancellazione di un commento dalla dashboard.
- [ ] Spec, controllando ogni frase sul codice:
  - **Stato:** "… piano 23b realizzato (`docs/superpowers/plans/2026-10-20-wonderflix-23b-voti-app.md`), da provare con l'utente".
  - **§6.2–6.3:** le scrive il Task 9 del 23a (`Mine`, `State`, nessun avviso allo scarto); qui si controlla solo che ci siano.
  - **§7.1:** niente motivi dei 409 nell'app; il 400 fra gli esiti attesi (decisioni 3–4).
  - **§7.2:** la pillola apre il pannello a lato (5), "la si chiude" (6), Esc a video finito (7), coda libera quando la votazione sparisce e il timer del player (8), rilettura dopo `EndsAt` (9), avvisi adottati (10), tasti (11), il titolo con "Stagione N" (13), posizione della pillola (17).
  - **§7.3:** niente riga per gli episodi aperti da soli e `detailEntranceCount` 9 (16).
  - **§7.4:** il limite dell'admin senza accesso ai watch party (15).
  - **§9:** le chiavi in più e il plurale di `ratingPartyAverage` (14).
  - Ogni altra differenza venuta fuori durante i task, con il motivo.
- [ ] Copia `config/wonderflix.json` dal checkout principale nel worktree (non si committa). Poi `flutter analyze`, `flutter test --concurrency=4` e la build:
  ```powershell
  flutter build windows --release --dart-define-from-file=config/wonderflix.json
  ```
  L'exe è `build/windows/x64/runner/Release/wonderflix.exe`.
- [ ] `git checkout -- windows/flutter/` se serve; `git add pubspec.yaml docs`; `git commit -m "chore: app 0.17.0 and spec aligned with plan 23b"`

### Task 9: STOP — prova a mano con l'utente

Dopo la review finale del branch e i ritocchi, **fermati** e lascia la prova all'utente: niente merge, push o release.

Serve il plugin 1.11.0 di prova sul server (piano 23a). La prova si fa con due istanze dell'exe di release del worktree (la seconda con `WONDERFLIX_PROFILE=b`), due utenti amici, in un party sul server vero. Spec §11.3:
- un film breve con Outro, poi l'ultimo episodio di una stagione: il pannello nel post-play, la coda ferma ("In attesa dei voti"), il conto di 15 s e la partenza del titolo dopo;
- voti scoperti perché tutti hanno votato, per tempo scaduto (2 min) e con "Scopri i voti" (solo per chi ha creato il party);
- uscita dal party durante la votazione;
- post-play chiuso e la pillola; cambio di titolo durante la votazione;
- voto dalla scheda dopo il party (film e stagione), "Togli il mio voto";
- cancellazione di un commento dalla dashboard.

**Nota (non è un passo di questo piano):** con l'ok dell'utente seguono il merge su `main` e il push, poi la release. Il plugin esce prima (tag, manifest, Catalogo). Poi l'app 0.17.0 **obbligatoria**, con le note in italiano scritte nella bozza di GitHub e la riga `<!-- wonderflix:min-version=0.17.0 -->`. Alla fine l'idea 7 di `docs/IDEE.md` passa fra le fatte.

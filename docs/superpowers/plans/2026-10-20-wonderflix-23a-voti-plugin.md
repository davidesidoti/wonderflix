# WonderFlix — Piano 23a: voti degli amici, plugin 1.11.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** la parte server della Spec Q nel plugin 1.11.0:
- l'archivio dei voti `ratings.json`: un voto da 1 a 10 per utente e titolo (film o stagione), con un commento facoltativo;
- la votazione di fine party in memoria (`RatingRound`): presenti, `Waiting`/`Voted`/`Skipped`, voti scoperti per tutti votato, 2 minuti o creatore;
- gli endpoint della scheda (`GET`/`PUT`/`DELETE Ratings`) con il filtro degli amici;
- gli endpoint admin dei commenti;
- l'avviso `RatingRoundUpdated`, raggruppato ogni 250 ms, con lo stato visto da ogni destinatario;
- la funzione `ratings` in `Info`, versione 1.11.0, e una build di prova sul server.

L'app arriva nel piano 23b, scritto in parallelo: si appoggia ai JSON della spec §6, quindi **i nomi delle proprietà JSON non si cambiano**.

**Architecture:** la logica sta in `Hub/` e non conosce Jellyfin:
- `RatingBook` (i voti in memoria), `RatingStore` (il file), `RatingService` (scheda, voto, admin, pulizia; lock e scrittura come `RecommendationService`);
- `RatingRound` (una votazione: presenti, stati, fase, `Rev`, stato per chi guarda; puro, senza lock);
- `RatingRoundService` (le votazioni per gruppo: lock, presenti da SyncPlay, timer dei 2 minuti, avvisi raggruppati per destinatario, pulizia).

Le domande nuove alla libreria stanno dietro `IRatingLibrary`, con l'adattatore `Server/JellyfinRatingLibrary`. `RatingsController` e `RatingsAdminController` espongono gli endpoint; `RatingsHostedService` pulisce le votazioni ogni 30 s e l'archivio ogni 5 minuti.

**Tech Stack:** C# / .NET 9, controller ASP.NET Core del plugin, xUnit, `Microsoft.Extensions.TimeProvider.Testing`. Il plugin si compila contro Jellyfin 10.11.0; i test e il server usano la 10.11.9.

**Spec:** `docs/superpowers/specs/2026-10-20-wonderflix-voti-amici-design.md` (§3, §5, §6, §8, §10, §11.1, §12, §13).

**Decisioni del piano** (rispetto alla spec; si allineano nel Task 9):
1. **Endpoint admin in un controller a parte**, `RatingsAdminController`, con `[Authorize]` sulla classe e `Policies.RequiresElevation` sui metodi (come gli annunci in `InboxController`). In `RatingsController` la policy `SyncPlayHasAccess` della classe si sommerebbe a quella del metodo: un admin senza SyncPlay, o la chiave API, resterebbero fuori.
2. **Chi chiama si ricava dal token** (`AuthorizationInfo.UserId`), come `MatchController`. I gruppi SyncPlay però si leggono da una sessione: i presenti si chiedono con `IGroupDirectory.GetParticipants` dalle sessioni WonderFlix (`ISessionDirectory.GetAppSessions()`), prima quelle di chi chiama e poi quelle degli utenti già nella votazione. Basta la prima risposta non null. I nomi dei partecipanti diventano utenti con `IUserDirectory.GetUsers()`, senza badare alle maiuscole (come `PartyHub`). Se nessuna sessione WonderFlix vede più il gruppo, il gruppo è finito per il plugin e la votazione si scarta.
3. **L'archivio è la sola fonte dei voti.** `RatingRound` tiene solo presenti, stati e fase; `Mine` e `Results` si leggono da `RatingService` a ogni stato. Un voto tolto dalla scheda durante la votazione sparisce anche dai risultati.
4. **Forma di `Mine`** (la spec non la dice), uguale in `RatingRoundDto` e in `GET Ratings`: `{"Score": 8, "Comment": "…"}`, con `Comment` assente se non c'è.
5. **`RatingRoundUpdated`** porta lo stato nella proprietà `"State"`, come `MatchUpdated`: `{"Protocol":1,"Type":"RatingRoundUpdated","State":{…}}`. `SocialEvent.State` diventa `object?`: System.Text.Json scrive il tipo vero, e il JSON di `MatchUpdated` non cambia (lo controlla `ProtocolJsonTests`).
6. **Apertura idempotente sul titolo risolto** (la stagione, non l'episodio), in qualunque fase: anche una votazione già in `Revealed` (nei suoi 10 minuti) si restituisce così com'è.
7. **Motivi dei 409:** chi non è fra i presenti → `NotMember` (anche per `POST Rounds` su un gruppo che non c'è); `Vote`/`Skip`/`Reveal` senza votazione → `Closed`; `Skip` in `Revealed` → `Closed`; `Reveal` di chi non è il creatore, o con il creatore non noto → `NotCreator`. `Reveal` del creatore in `Revealed` risponde con lo stato, senza cambi (doppio clic). `GET Rounds/{groupId}` non dà mai 409: `{}`.
8. **`Rev`** cresce a ogni voto (anche un voto cambiato), a ogni cambio di stato di un presente, a ogni cambio dei presenti e al cambio di fase.
9. **Nessun avviso quando una votazione si scarta:** l'app lo scopre con `GET Rounds/{groupId}` → `{}` (spec §7.2, "Errori").
10. **Limite `Ratings`:** si controlla dopo la validazione del corpo e conta `Vote`, `PUT` e `DELETE`, anche un `DELETE` di un voto che non c'era. Un `DELETE` con un id non valido risponde 204 senza contare, come "Non mi interessa" dei consigli.
11. **Il commento tolto dall'admin** lascia `UpdatedAt` com'era: l'ordine degli amici nella scheda non cambia.
12. **Titoli:** un film è "Nome (Anno)" (solo il nome senza anno); una stagione è "Serie · Stagione N", e la stagione 0 è "Serie · Speciali". Una stagione senza numero non si può votare. Un episodio senza `IndexNumber`, `ParentIndexNumber` o `SeasonId` non apre una votazione (400).
13. **Episodi di una stagione** (vedi "Note tecniche verificate"): gli episodi della serie (`AncestorIds = [SeriesId]`) con `ParentIndexNumber` uguale al numero della stagione, senza i virtuali. Vale anche per gli episodi fuori da una cartella della stagione, e gli speciali restano nella stagione 0 anche con `DisplaySpecialsWithinSeasons`. "Ultimo della stagione" si chiede alla libreria senza un utente; `CanRate` si chiede con l'utente, quindi gli episodi che lui non vede non contano.
14. **La pulizia dell'archivio non tocca i titoli** durante una scansione della libreria (`ILibraryTitles.IsScanRunning`) né se la libreria lancia: un voto si perde solo per un titolo che Jellyfin non ha davvero più.
15. **Paginazione dei commenti:** `before` è esclusivo, e `Next` è l'`UpdatedAt` dell'ultima voce della pagina. Due commenti con lo stesso `UpdatedAt` a cavallo di due pagine perderebbero il secondo. Si accetta: le date hanno la precisione dei tick.
16. **Media** con `decimal` e `MidpointRounding.AwayFromZero` (7,25 → 7,3), restituita come `double`.
17. **Un solo servizio in background** (`RatingsHostedService`) con due timer, per le votazioni (30 s) e per l'archivio (5 min). Il conteggio dei servizi in background passa da 6 a 7.
18. **Errori della libreria** in `GET`/`PUT Ratings` e in `POST Rounds` → 400, con un `Warning`; mai un 500.
19. **Dalle review dei gruppi** (differenze dalla spec, allineate nel Task 9):
    - i callback dei timer (`Expire`, `FirePush`) non lanciano mai, ma scrivono un `Warning` con il solo id del gruppo: un `ratings.json` illeggibile su un thread del pool farebbe cadere Jellyfin. `Load` non restituisce un libro vuoto, perché il salvataggio successivo sovrascriverebbe il file vero;
    - il timer dei 2 minuti scopre i voti direttamente, con la ragione `timeout`, senza ricontrollare l'orologio;
    - una stagione senza id o nome della serie non è mai vista né votabile;
    - `Open` rifiuta (400) un bersaglio che `FindRated` rifiuta, così non restano voti su un titolo che `GET Ratings` non mostra;
    - la chiave API non ha un utente: gli endpoint dei voti sono respinti dalla policy SyncPlay di Jellyfin (400), mai 404 (build di prova, Task 8).

## Global Constraints

- Plugin **1.11.0**; Jellyfin 10.11.x (`targetAbi` 10.11.0.0); compilato contro 10.11.0, test con 10.11.9. Ogni proprietà di `InternalItemsQuery` usata deve esistere nella 10.11.0.
- Endpoint sotto `/WonderFlixWatchParty`:
  - in `RatingsController`, con `[Authorize(Policy = Policies.SyncPlayHasAccess)]`: `POST Ratings/Rounds`, `GET Ratings/Rounds/{groupId}`, `POST Ratings/Rounds/{groupId}/Vote`, `/Skip`, `/Reveal`, `GET Ratings?itemId=`, `PUT Ratings/{itemId}`, `DELETE Ratings/{itemId}`;
  - in `RatingsAdminController`, con `Policies.RequiresElevation` sul metodo: `GET Ratings/Admin/Comments?before=`, `DELETE Ratings/Admin/Comments/{userId}/{itemId}`.
- **Mai 404:** gli id sono stringhe senza vincoli di rotta. Un `groupId` non valido nella rotta → 400. I 409 hanno il corpo `{"Reason": "…"}` con i valori di `RatingReasons` (`NotMember`, `NotCreator`, `Closed`).
- Valori: voto intero da 1 a 10; commento al massimo 200 punti di codice dopo la pulizia; votazione di 2 minuti (`RatingRoundService.VotingTime`); votazione scartata 10 minuti dopo `Revealed` (`RevealedKept`); avvisi al più ogni 250 ms (`PushInterval`); pulizia delle votazioni ogni 30 s e dell'archivio ogni 5 minuti; 60 scritture all'ora per utente (`LimitTypes.Ratings`); 50 commenti per pagina (`RatingService.CommentsPageSize`).
- JSON, con i nomi esatti della spec §6 (PascalCase, come il resto del plugin):
  - `ratings.json`: `{"Version":1,"Items":{"<itemId N>":[{"UserId","Score","Comment"?,"CreatedAt","UpdatedAt"}]}}`;
  - `RatingRoundDto`: `GroupId`, `ItemId`, `Phase` (`Voting`/`Revealed`), `Rev`, `EndsAt`, `CanReveal`, `Mine`?, `Voters` (`UserId`, `Name`, `Status` `Waiting`/`Voted`/`Skipped`), e solo in `Revealed` `Results` (`UserId`, `Name`, `Score`, `Comment`?) e `Average`?;
  - `GET Ratings`: `{CanRate, Mine?, Average?, Count, Friends: [{UserId, Name, Score, Comment?, UpdatedAt}]}`;
  - admin: `{Items: [{UserId, UserName, ItemId, Title, Score, Comment, UpdatedAt}], Next?}`.
- **In `Voting` i voti e i commenti degli altri non escono mai**, né nelle risposte né negli avvisi.
- `Info`: `Version` "1.11.0", `Protocol` 1, `Features` con `"ratings"` dopo `"match"`.
- Id di Jellyfin in formato `"N"`; date ISO-8601 UTC (`TimeProvider`, mai `DateTimeOffset.UtcNow`).
- Log: **mai titoli, commenti o nomi**, solo id e numeri. `Debug` per apertura, cambio di fase (con la ragione: tutti votato, tempo scaduto, creatore) e chiusura; `Warning` per file illeggibile, errori di scrittura ed errori della libreria; la cancellazione di un commento va in `Information` con `AdminCaller.Describe`.
- **Commit:** con l'identità git del repository; **mai** trailer `Co-Authored-By` né righe "Generated with…"; mai le parole `closes`, `fixes`, `resolves` (né simili) nei messaggi.
- **Processi:** mai terminarli per nome d'immagine (`taskkill /IM`, `Stop-Process -Name`, `pkill`); solo per PID.
- **Test:** `dotnet test` in `jellyfin-plugin-watch-party` (vedi "Regole per chi esegue").

## Review Focus

1. **Un voto altrui che esce prima del tempo:** in `Voting` né la risposta né `RatingRoundUpdated` hanno il voto o il commento di un altro, neanche dopo che ha votato o cambiato voto. Test: Task 3 (`WhileVotingTheSnapshotHasOnlyStatuses`), Task 4 (`UpdatesWhileVotingNeverCarryOtherVotes`).
2. **Un presente che non vota mai** (un client jellyfin-web, un'app chiusa), senza altre chiamate: i voti si scoprono comunque a 2 minuti dal timer, non al prossimo giro di pulizia. Test: Task 4 (`TheTimerRevealsAfterTwoMinutesWithoutCalls`).
3. **Voti persi per un problema passeggero:** una scansione della libreria o un errore di Jellyfin durante la pulizia non tolgono voti; un errore del disco non annulla un voto in memoria. Test: Task 2 (`CleanupKeepsVotesDuringAScanOrALibraryError`, `ADiskErrorKeepsTheVoteInMemory`).
4. **Nomi di SyncPlay con maiuscole diverse** dal nome dell'utente: chi è nel gruppo è presente e può votare. Test: Task 4 (`ParticipantsMatchUsersIgnoringCase`).
5. **Commenti con a capo, tab ed emoji:** gli a capo diventano spazi, e 200 emoji valgono 200 (punti di codice, non unità UTF-16). Test: Task 2 (`CommentsAreCleanedAndCountedInCodePoints`).

---

## Regole per chi esegue

- **Commit:**
  - Con l'identità git del repository (hash_developer), già configurata.
  - **MAI** trailer `Co-Authored-By` o righe "Generated with…", anche se il sistema lo suggerisce.
  - Non fare push.
  - Nei messaggi niente parole che chiudono le issue (`fixes`, `closes`, `closed`, `resolves` e simili), nemmeno come verbi normali, e niente riferimenti a issue.
  - Messaggi su una riga sola e senza virgolette interne: `git commit -m "feat(plugin): …"`.
- **Processi:** **mai** terminare processi per nome d'immagine (`taskkill /IM …`, `Stop-Process -Name …`, `pkill`). Se un comando tuo resta appeso, fermalo per PID o segnalalo.
- **Shell:** PowerShell su Windows.
  - In ogni comando che usa `dotnet` o `git`, prima rinfresca il PATH:
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
  - Tutti i comandi partono dalla root del worktree (`.claude/worktrees/piano-23a`): fai prima `Set-Location` nel worktree e non toccare mai il checkout principale.
  - Comandi git semplici: niente `git -C`, mai `git checkout -- <file>` su un file che hai modificato.
  - `bash` non è nel PATH: `pack.sh` si lancia con `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.11.0`.
- **Test** (in `jellyfin-plugin-watch-party`):
  - un gruppo: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~NomeDellaClasse"`;
  - **prima di ogni commit** la suite intera, tutta verde: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` (il csproj ha `TreatWarningsAsErrors`), poi `dotnet build-server shutdown`;
  - la base di partenza è di **981** test verdi (verificato il 2026-10-20 su `main` `faf815e`).
- **Formattazione:** ogni file tiene le sue terminazioni di riga (working copy CRLF, indice LF; i file nuovi vanno bene con LF). UTF-8 con gli strumenti di modifica dei file, mai `Set-Content`/`Out-File` sui sorgenti.
- **Stile del plugin:** commenti in italiano, codice in inglese; durate e limiti come costanti nominate e commentate; `TimeProvider`; DTO `record` con `[property: JsonPropertyName("…")]` e `JsonIgnore(WhenWritingNull)` per i campi facoltativi; classi con `[JsonPropertyName]` per i corpi delle richieste; `Lock` di .NET 9; id `"N"`.
- **Se il codice del piano ha un errore** (compilazione, nullability, un analizzatore, un'API di Jellyfin con firma diversa): correggilo in modo minimo, nello spirito del piano, e segnalalo; preferisci correggere il codice piuttosto che indebolire un test.

## Note tecniche verificate

Verificate il 2026-10-20 sul codice di `main` (`faf815e`) e sul sorgente di Jellyfin al tag `v10.11.9`.

**Plugin** (`main`)
- `RecommendationStore`/`RecommendationBook`/`RecommendationService` sono il modello dell'archivio: `Load()` con `.bad`, `Save()` con file `.tmp` e `Flush(flushToDisk: true)`, `Book` pigro sotto `_lock`, `Persist()` che scrive un `Warning` per `IOException`/`UnauthorizedAccessException`. `RecommendationService.CleanMessage(string?)` è `internal static` e fa già la pulizia del §6.1: si riusa.
- `MatchService` è il modello delle votazioni: `Lock`, `Push(room, immediate)` con `PushState { LastAt, Timer }`, `FirePush`, `Deliver` fuori dal lock, `SendAsync` alle sessioni di `GetAppSessions()` con `IEventSender.TrySendAsync(sessionId, payload, CancellationToken.None)`, `Dispose` dei timer. `MatchOutcome(HubStatus, Reason, State)` è il modello dell'esito.
- `IGroupDirectory.GetParticipants(string sessionId, Guid groupId)` restituisce i **nomi utente**, o null se il gruppo non c'è o la sessione non lo vede. `PartyDirectory.Get(groupId)?.CreatorId` è il creatore (solo in RAM).
- `FriendService.AreFriends(Guid, Guid)`; `IUserDirectory.GetUser(Guid)` → `UserRef(Id, Name, Enabled, …)` o null; `ILibraryAccess.CanSee(Guid userId, Guid itemId)`; `ILibraryTitles.IsScanRunning`.
- `RateLimiter.TryAcquire(string key, string type)`, con la chiave l'id `"N"` dell'utente e i limiti nel dizionario `Limits`.
- `AdminCaller.Describe(Guid)` è `internal` in `Account/`. `InboxController` mette `[Authorize(Policy = Policies.RequiresElevation)]` sui metodi; `InboxControllerTests` controlla la policy con `GetCustomAttributes<AuthorizeAttribute>()`.
- `InfoControllerTests` controlla `"1.10.1"` e i due elenchi di funzioni; `ServiceRegistrationTests.AllServicesResolve` conta **6** servizi in background; il csproj ha `<Version>1.10.1</Version>`.
- Test: `FakeServer` implementa le interfacce di `Hub/` (`Users`, `AddUser`, `AddSession(id, user)`, `Groups` gruppo → nomi, `Hidden`, `Unseen`, `LibraryFails`, `ScanRunning`, `Sent`, `SentTo`); `TestRecommendations.Friends(...)` e `MakeFriendsAsync(friends, a, b)`; `TempFolder`; `InterfaceStub<T>` (`Handlers["Nome"]`, `Calls`); `RecordingLogger<T>.Entries`; `FakeAuthorizationContext`; `FakeTimeProvider`. `FakeServer.GetTitle` esiste già per `IRecommendationLibrary`: i metodi di `IRatingLibrary` hanno nomi diversi.
- L'app legge `json['State']` per `MatchUpdated` (`lib/core/social/social_models.dart`): per questo la decisione 5.

**Jellyfin 10.11.9** (spec §12)
- **`IsPlayed`** (`BaseItemRepository.TranslateQuery`): con `IncludeItemTypes = [Episode]` (non solo `Series`) si guarda la riga dei dati dell'utente della query (`filter.User`) sull'elemento stesso; senza riga vale "non visto". Quindi `IsPlayed = false` sugli episodi trova proprio quelli che l'utente non ha visto, e serve `new InternalItemsQuery(user)`.
- **Episodi mancanti:** il filtro è `IsVirtualItem ?? IsMissing`, cioè `IsVirtualItem = false` toglie gli episodi mancanti (`LocationType.Virtual`).
- **Episodi di una stagione:** Jellyfin (`Series.GetSeasonEpisodes`/`FilterEpisodesBySeason`) sceglie gli episodi per numero della stagione (`ParentIndexNumber`, o `AiredSeasonNumber` con `DisplaySpecialsWithinSeasons`), non per cartella: un episodio fuori dalla cartella della stagione ha come genitore la serie. `ParentIndexNumber` e `MinIndexNumber` filtrano `e.ParentIndexNumber ==` e `e.IndexNumber >=`. Da qui la decisione 13.
- **Episodi doppi:** `Episode.IndexNumberEnd` (S01E05-E06 ha `IndexNumber` 5 e `IndexNumberEnd` 6). "Nessun episodio dopo" si chiede con `MinIndexNumber = (IndexNumberEnd ?? IndexNumber) + 1`, e così un doppio alla fine della stagione è l'ultimo.
- **Speciali:** stagione 0 (`ParentIndexNumber` 0); con la regola sopra si votano come le altre stagioni.
- **Quando si segna `Played`:** a `OnPlaybackStopped` (anche in SyncPlay, che usa le stesse segnalazioni di riproduzione), `UserDataManager.UpdatePlayState` mette `Played = true` se la posizione supera `MaxResumePct` (90 % di serie) o è entro 1 s dalla fine; senza posizione lo segna comunque. All'inizio dei titoli di coda `Played` può quindi mancare ancora: per questo il voto nella votazione non lo chiede (spec §6.2), e dalla scheda basta `Played`.
- `InternalItemsQuery` ha in 10.11.0 e 10.11.9 `AncestorIds`, `IncludeItemTypes`, `ParentIndexNumber`, `MinIndexNumber`, `IsVirtualItem`, `IsPlayed`, `Limit`; il Task 6 lo ricontrolla compilando contro la 10.11.0.

## File

| File | Responsabilità |
|---|---|
| `Protocol/RatingDtos.cs` | fasi, stati, motivi, stato della votazione, risposte della scheda e dell'admin, corpi delle richieste |
| `Hub/RatingFile.cs`, `Hub/RatingBook.cs`, `Hub/RatingStore.cs` | `ratings.json`: contenuto, voti in memoria, lettura e scrittura |
| `Hub/IRatingLibrary.cs` | `RatedTitle` e le domande alla libreria |
| `Hub/RatingService.cs` | scheda, voto, admin, pulizia, media |
| `Hub/RatingRound.cs` | una votazione (puro) |
| `Hub/RatingRoundService.cs` | votazioni per gruppo, timer, presenti, avvisi, pulizia |
| `Api/RatingsController.cs`, `Api/RatingsAdminController.cs` | endpoint |
| `Server/JellyfinRatingLibrary.cs` | le domande a Jellyfin |
| `RatingsHostedService.cs` | i due timer di pulizia |
| `Protocol/SocialEvent.cs`, `Hub/LimitTypes.cs`, `Hub/RateLimiter.cs`, `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, csproj, `Plugin.cs`, `../meta.template.json`, `../README.md` (modifiche) | avviso, limite, montaggio, versione, documentazione |

I percorsi sono relativi a `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/` (codice) e `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests/` (test, scritti `Tests/…`), se non è detto altro.

---

## Gruppo A — archivio e regole

### Task 1: DTO e archivio dei voti

**Files:**
- Create: `Protocol/RatingDtos.cs`, `Hub/RatingFile.cs`, `Hub/RatingBook.cs`, `Hub/RatingStore.cs`
- Modify (test): `Tests/TempFolder.cs` (`RatingsFile`, accanto a `RecommendationsFile`)
- Test: `Tests/RatingBookTests.cs`, `Tests/RatingStoreTests.cs`

**Interfaces:**
- Produces:
  - `Protocol/RatingDtos.cs`:
    - `RatingPhases` (`Voting`, `Revealed`), `RatingVoterStatuses` (`Waiting`, `Voted`, `Skipped`), `RatingReasons` (`NotMember`, `NotCreator`, `Closed`): classi statiche di `const string`, come `MatchPhases`/`MatchReasons`;
    - `RatingScoreDto(int Score, string? Comment)` (`Mine`);
    - `RatingVoterDto(string UserId, string Name, string Status)`;
    - `RatingResultDto(string UserId, string Name, int Score, string? Comment)`;
    - `RatingRoundDto(string GroupId, string ItemId, string Phase, long Rev, DateTimeOffset EndsAt, bool CanReveal, RatingScoreDto? Mine, IReadOnlyList<RatingVoterDto> Voters, IReadOnlyList<RatingResultDto>? Results, double? Average)`;
    - `RatingRoundEmptyDto()` (senza proprietà: si scrive `{}`), `RatingErrorDto(string Reason)`;
    - `FriendRatingDto(string UserId, string Name, int Score, string? Comment, DateTimeOffset UpdatedAt)`;
    - `ItemRatingsDto(bool CanRate, RatingScoreDto? Mine, double? Average, int Count, IReadOnlyList<FriendRatingDto> Friends)`;
    - `AdminCommentDto(string UserId, string UserName, string ItemId, string Title, int Score, string Comment, DateTimeOffset UpdatedAt)`, `AdminCommentsDto(IReadOnlyList<AdminCommentDto> Items, DateTimeOffset? Next)`;
    - corpi: `OpenRatingRoundRequest { string? GroupId; string? ItemId }`, `RateRequest { int? Score; string? Comment }`.
    - Ogni proprietà con il nome JSON uguale al nome C#; quelle con `?` hanno `JsonIgnore(WhenWritingNull)`.
  - `StoredRating(Guid UserId, int Score, string? Comment, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt)` (in `RatingBook.cs`).
  - `RatingBook`: `StoredRating? Get(Guid itemId, Guid userId)`; `IReadOnlyList<StoredRating> ForItem(Guid itemId)`; `StoredRating Set(Guid itemId, Guid userId, int score, string? comment, DateTimeOffset now)`; `bool Remove(Guid itemId, Guid userId)`; `bool RemoveComment(Guid itemId, Guid userId)`; `IReadOnlyList<(Guid ItemId, StoredRating Rating)> Comments(DateTimeOffset? before, int limit)` (solo con commento, `UpdatedAt < before`, dal più recente); `int Prune(Func<Guid, bool> userExists, Func<Guid, bool> itemExists)`; `static RatingBook FromFile(RatingFile)` (`FormatException` per un id, un voto fuori da 1–10 o una voce null); `RatingFile ToFile()`.
  - `RatingFile` (`Version`, `Items: Dictionary<string, List<RatingFileEntry?>?>?`), `RatingFileEntry` (`UserId`, `Score`, `Comment` con `WhenWritingNull`, `CreatedAt`, `UpdatedAt`).
  - `RatingStore(string filePath, ILogger<RatingStore> logger)`: `FileName = "ratings.json"`, `DefaultPath(IApplicationPaths)` (cartella `FriendStore.FolderName`), `FilePath`, `RatingBook Load()`, `void Save(RatingBook)`; stesso codice di `RecommendationStore` (`Warning` "Voti illeggibili…").

- [ ] **Step 1: test che falliscono**

`Tests/RatingBookTests.cs` (date `T0 = 2026-10-20 21:00 UTC`):

```csharp
[Fact]
public void AVoteAgainReplacesScoreAndCommentAndKeepsCreatedAt()
{
    var book = new RatingBook();
    book.Set(_film, _mario, 8, "Capolavoro", T0);
    var again = book.Set(_film, _mario, 6, null, T0.AddDays(1));
    Assert.Equal(new StoredRating(_mario, 6, null, T0, T0.AddDays(1)), again);
    Assert.Equal(again, book.Get(_film, _mario));
    Assert.Single(book.ForItem(_film));
}

[Fact]
public void RemovingTheCommentKeepsScoreAndUpdatedAt()
{
    var book = new RatingBook();
    book.Set(_film, _mario, 8, "Capolavoro", T0);
    Assert.True(book.RemoveComment(_film, _mario));
    Assert.Equal(new StoredRating(_mario, 8, null, T0, T0), book.Get(_film, _mario));
    Assert.False(book.RemoveComment(_film, _luigi));
    Assert.True(book.Remove(_film, _mario));
    Assert.Null(book.Get(_film, _mario));
    Assert.False(book.Remove(_film, _mario));
}

[Fact]
public void CommentsAreNewestFirstBeforeADate()
{
    var book = new RatingBook();
    book.Set(_film, _mario, 8, "a", T0);
    book.Set(_film, _luigi, 7, "b", T0.AddHours(1));
    book.Set(_season, _mario, 9, null, T0.AddHours(2));
    Assert.Equal(new[] { _luigi, _mario }, book.Comments(null, 50).Select(c => c.Rating.UserId));
    Assert.Equal(_mario, Assert.Single(book.Comments(T0.AddHours(1), 50)).Rating.UserId);
    Assert.Equal(_luigi, Assert.Single(book.Comments(null, 1)).Rating.UserId);
}

[Fact]
public void PruneDropsGoneUsersAndGoneTitles()
{
    // mario e luigi sul film, mario sulla stagione; luigi non c'è più, la stagione neanche.
    Assert.Equal(2, book.Prune(user => user != _luigi, item => item != _season));
    Assert.Equal(_mario, Assert.Single(book.ForItem(_film)).UserId);
    Assert.Empty(book.ForItem(_season));
}
```

`Tests/RatingStoreTests.cs`:
- `AMissingFileIsEmpty`: `Load()` su `folder.RatingsFile` inesistente → `ForItem(any)` vuoto.
- `TheSavedFileHasTheSpecShape`: `Set(film, mario, 8, null, T0)`, `Save`; con `JsonDocument`: `Version` = 1, `Items[film.ToString("N")][0]` ha `UserId` = mario `"N"`, `Score` = 8, `CreatedAt`, `UpdatedAt` e **nessuna** proprietà `Comment`; un nuovo `Load()` dà lo stesso `StoredRating`.
- `AnUnreadableFileGoesToBad`: scrivi `{nope` → `Load()` vuoto e `File.Exists(path + ".bad")`.
- `AScoreOutsideOneToTenMakesTheFileUnreadable`: un file valido con `"Score": 11` → vuoto e `.bad`.

- [ ] **Step 2: i test falliscono**

Run: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release --filter "FullyQualifiedName~RatingBookTests|FullyQualifiedName~RatingStoreTests"`
Expected: FAIL (tipi mancanti).

- [ ] **Step 3: il codice** con le firme sopra. `RatingBook` è un `Dictionary<Guid, List<StoredRating>>` per titolo; `ToFile` scrive le voci dal più recente.

- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): ratings store and DTOs"
```

### Task 2: `IRatingLibrary` e `RatingService`

**Files:**
- Create: `Hub/IRatingLibrary.cs`, `Hub/RatingService.cs`, `Tests/TestRatings.cs`
- Modify: `Hub/LimitTypes.cs` (`Ratings`), `Hub/RateLimiter.cs` (`[LimitTypes.Ratings] = (60, TimeSpan.FromHours(1))`), `Tests/FakeServer.cs` (implementa `IRatingLibrary`)
- Test: `Tests/RatingServiceTests.cs`

**Interfaces:**
- Consumes: `RatingStore`, `RatingBook`, `StoredRating`, i DTO (Task 1); `RecommendationService.CleanMessage`; `FriendService.AreFriends`; `IUserDirectory`; `ILibraryAccess.CanSee`; `ILibraryTitles.IsScanRunning`; `RateLimiter`.
- Produces:
  - `Hub/IRatingLibrary.cs`:
    ```csharp
    /// <summary>Un film o una stagione che si può votare; DisplayTitle "Il Padrino (1972)" o "Breaking Bad · Stagione 2".</summary>
    public sealed record RatedTitle(Guid Id, bool IsSeason, string DisplayTitle);

    public interface IRatingLibrary
    {
        /// <summary>Il film o la stagione (con numero); null se non c'è o è un altro tipo.</summary>
        RatedTitle? FindRated(Guid itemId);

        /// <summary>Cosa si vota a fine party: il film stesso, la stagione per l'ultimo episodio della stagione; null altrimenti.</summary>
        Guid? RoundTarget(Guid itemId);

        /// <summary>L'utente ha visto il titolo: il film Played, la stagione senza episodi veri non visti.</summary>
        bool HasWatched(Guid userId, RatedTitle title);
    }
    ```
  - `LimitTypes.Ratings = "Ratings"` (commento: "Scritture dei voti (Vote, PUT, DELETE), per utente: sessanta all'ora (spec Q §6.3)").
  - `RatingService(RatingStore store, FriendService friends, IUserDirectory users, ILibraryAccess access, IRatingLibrary library, ILibraryTitles titles, RateLimiter limiter, TimeProvider time, ILogger<RatingService> logger)`:
    - `const int MaxCommentLength = 200`, `const int CommentsPageSize = 50`; `void Load()`;
    - `HubResult<ItemRatingsDto> ForItem(Guid userId, string? itemId)`;
    - `HubStatus Rate(Guid userId, string? itemId, RateRequest? request)` → `Ok`, `Invalid`, `RateLimited`;
    - `HubStatus Delete(Guid userId, string? itemId)` → `Ok`, `RateLimited`;
    - `HubStatus Save(Guid userId, Guid itemId, int? score, string? comment)`: valida voto e commento, conta il limite, scrive; **senza** controlli sul titolo (li fa chi chiama). La usano `Rate` e le votazioni (Task 4);
    - `IReadOnlyDictionary<Guid, StoredRating> Of(Guid itemId, IReadOnlyCollection<Guid> userIds)`;
    - `HubResult<AdminCommentsDto> Comments(string? before)` (`Invalid` se `before` c'è e non è una data ISO);
    - `HubStatus DeleteComment(Guid adminId, string? userId, string? itemId)` (`Invalid` per un id non valido; `Information` "Commento di {UserId} su {ItemId} tolto dall'admin {AdminId}" solo se c'era);
    - `int Cleanup()`;
    - `internal static double? Average(IReadOnlyCollection<int> scores)`.
  - `TestRatings.Create(FakeServer server, TempFolder folder, TimeProvider time, FriendService friends, ILogger<RatingService>? logger = null) : RatingService`.
  - `FakeServer`: `Dictionary<Guid, RatedTitle> RatedTitles`, `RatedTitle AddRated(string displayTitle, bool isSeason = false)`, `Dictionary<Guid, Guid> RoundTargets`, `HashSet<(Guid UserId, Guid ItemId)> WatchedTitles`, `bool RatingLibraryFails` (i tre metodi lanciano `InvalidOperationException`).

**Regole** (spec §6.1, §6.3, §6.4):
- `ForItem`: `Invalid` se l'id non vale, `FindRated` è null, `CanSee` è falso o la libreria lancia (`Warning` con l'id). `Friends`: voti degli amici attuali (`AreFriends`), utenti esistenti e attivi, senza chi chiama, per `UpdatedAt` decrescente. `Count` = `Friends.Count`, `Average` = `Average(punteggi di Friends)`. `Mine` è il voto di chi chiama. `CanRate` = `Mine != null || HasWatched` (un errore di `HasWatched` vale falso).
- `Rate`: `Invalid` per titolo come `ForItem`, oppure se `!CanRate`; poi `Save`.
- `Save`: `Invalid` se `score` è null o fuori da 1–10, o se il commento ripulito (`CleanMessage`) supera 200 punti di codice (`EnumerateRunes().Count()`); poi `TryAcquire(N(userId), LimitTypes.Ratings)` → `RateLimited`; poi `Set` sotto lock e `Persist()`.
- `Delete`: id non valido → `Ok` senza contare; altrimenti limite, poi `Remove` e `Persist()` solo se c'era.
- `Comments`: `Book.Comments(before, CommentsPageSize + 1)`; con 51 voci se ne restituiscono 50 e `Next` è l'`UpdatedAt` della 50ª. `UserName` = `GetUser(...)?.Name ?? ""`, `Title` = `FindRated(...)?.DisplayTitle ?? ""` (un errore della libreria dà `""`).
- `Cleanup`: `Prune` con `userExists` = `GetUser(id) is not null`; `itemExists` = `true` se `titles.IsScanRunning`, altrimenti `FindRated(id) is not null`, e `true` se lancia (un solo `Warning` per giro). `Persist()` se ha tolto qualcosa.
- `Persist()` come in `RecommendationService` ("Voti non salvati in {Path}").

- [ ] **Step 1: test che falliscono**

`Tests/RatingServiceTests.cs`. Utenti: Mario (chi chiama), Luigi e Peach amici, Toad non amico, Daisy amica e poi disabilitata (`_server.Users[id] = daisy with { Enabled = false }`). `_film = _server.AddRated("Il Padrino (1972)")`, `_season = _server.AddRated("Breaking Bad · Stagione 2", isSeason: true)`. Per votare per conto di un altro senza `CanRate`: `_service.Save(...)`.

```csharp
[Fact]
public void FriendsOnlyNewestFirstWithoutDisabledAndMineApart()
{
    _service.Save(_mario.Id, _film.Id, 7, null);
    _service.Save(_luigi.Id, _film.Id, 8, null);
    _time.Advance(TimeSpan.FromHours(1));
    _service.Save(_peach.Id, _film.Id, 6, "Lento");
    _service.Save(_toad.Id, _film.Id, 10, null);
    _service.Save(_daisy.Id, _film.Id, 1, null);
    DisableDaisy();

    var view = _service.ForItem(_mario.Id, N(_film.Id)).Value!;
    Assert.Equal(new[] { "Peach", "Luigi" }, view.Friends.Select(f => f.Name));
    Assert.Equal(new FriendRatingDto(N(_peach.Id), "Peach", 6, "Lento", T0.AddHours(1)), view.Friends[0]);
    Assert.Equal(7.0, view.Average);
    Assert.Equal(2, view.Count);
    Assert.Equal(new RatingScoreDto(7, null), view.Mine);
}

[Fact]
public void AverageRoundsHalfUpToOneDecimal()
{
    Assert.Equal(7.3, RatingService.Average([7, 7, 7, 8]));   // 7,25
    Assert.Equal(7.5, RatingService.Average([7, 8]));
    Assert.Equal(7.3, RatingService.Average([8, 7, 7]));      // 7,333…
    Assert.Equal(9.3, RatingService.Average([10, 9, 9]));     // 9,333…
    Assert.Null(RatingService.Average([]));
}
```

E inoltre (asserzioni in breve):
- `WithoutFriendsVotesThereIsNoAverage`: solo Toad ha votato → `Friends` vuoto, `Average` null, `Count` 0, `Mine` null, `CanRate` falso.
- `CanRateWhenWatchedOrWithAnEarlierVote`: film e stagione non visti → `CanRate` falso; con `WatchedTitles.Add((mario, id))` → vero; tolto di nuovo, ma con un voto di Mario → vero.
- `ATitleThatIsNotRatableOrNotVisibleIs400`: `"abc"`, un id sconosciuto, `_film` in `Unseen` per Mario, `RatingLibraryFails = true` → `HubStatus.Invalid` sia per `ForItem` sia per `Rate`.
- `RateNeedsWatchedOrAnEarlierVote`: senza visione → `Invalid` e niente nell'archivio; visto → `Ok`; non più visto ma con il voto → `Ok` (cambio voto).
- `ScoresOutsideOneToTenAreInvalid`: `Score` 0, 11 e null → `Invalid`.
- `CommentsAreCleanedAndCountedInCodePoints`: `"  Bello\n\tdavvero  "` → salvato `"Bello davvero"`; `"   "` → `Comment` null; 200 volte `"🎬"` → `Ok`; 201 volte `"a"` → `Invalid`.
- `DeleteIs204EvenWithoutAVote`: `Delete` di un voto che non c'è → `Ok`; `Delete("abc")` → `Ok`; dopo un `Delete` vero, `Mine` null.
- `TheSixtyFirstWriteInAnHourIsRateLimited`: 30 `Rate` e 30 `Delete` → `Ok`; il 61° `Rate` → `RateLimited` e il voto non cambia; `Advance(1 h)` → `Ok`. `Delete("abc")` non conta.
- `AdminCommentsComeInPagesOf50`: 51 utenti con commento a `T0 + i min` più uno senza commento; la prima pagina ha 50 voci dal più recente, `Title` "Il Padrino (1972)", `UserName` giusto, `Next` = `UpdatedAt` della 50ª; `Comments(Next!.Value.ToString("O"))` → 1 voce e `Next` null; `Comments("ieri")` → `Invalid`; con il film tolto da `RatedTitles` il `Title` è `""`.
- `AdminDeleteRemovesOnlyTheComment`: con `RecordingLogger<RatingService>`: `DeleteComment(admin, N(peach), N(film))` → `Ok`, il voto resta con `Score` 6, `Comment` null e lo stesso `UpdatedAt`; una voce `Information` che contiene gli id e non `"Lento"`; una seconda volta → `Ok`, nessuna voce nuova; `DeleteComment(admin, "x", N(film))` → `Invalid`.
- `CleanupDropsGoneUsersAndGoneTitles`: un utente tolto da `Users` e un titolo tolto da `RatedTitles` → `Cleanup()` = 2, e il file non li ha più.
- `CleanupKeepsVotesDuringAScanOrALibraryError`: titolo tolto da `RatedTitles` con `ScanRunning = true` → `Cleanup()` = 0; con `ScanRunning = false` e `RatingLibraryFails = true` → 0; un utente sparito esce lo stesso.
- `ADiskErrorKeepsTheVoteInMemory`: crea una **cartella** al percorso di `ratings.json`, `Save` → `Ok`, `ForItem` mostra il voto, nel log un `Warning`.

- [ ] **Step 2: i test falliscono**

Run: `dotnet test … --filter "FullyQualifiedName~RatingServiceTests"`
Expected: FAIL.

- [ ] **Step 3: il codice** con le firme e le regole sopra; `RatingService` ha la struttura di `RecommendationService` (`_lock`, `Book` pigro con `Information` "Voti in {Path}", `Persist`). La media:

```csharp
internal static double? Average(IReadOnlyCollection<int> scores) =>
    scores.Count == 0 ? null : (double)Math.Round((decimal)scores.Sum() / scores.Count, 1, MidpointRounding.AwayFromZero);
```

- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): ratings service with friends filter and admin comments"
```

### Task 3: `RatingRound`

**Files:**
- Create: `Hub/RatingRound.cs`
- Test: `Tests/RatingRoundTests.cs`

**Interfaces:**
- Consumes: i DTO e `StoredRating` (Task 1), `RatingService.Average` (Task 2).
- Produces: `RatingRound(Guid groupId, Guid itemId, DateTimeOffset openedAt, TimeSpan votingTime)`, non sicuro tra thread:
  - `GroupId`, `ItemId`, `OpenedAt`, `EndsAt` (= `openedAt + votingTime`), `string Phase`, `DateTimeOffset? RevealedAt`, `long Rev`, `IReadOnlyCollection<Guid> PresentIds`;
  - `bool IsPresent(Guid userId)`;
  - `void SetPresent(IReadOnlyList<UserRef> present)`: i nuovi entrano in `Waiting` (o con lo stato che avevano prima di uscire); chi esce resta ricordato ma non si vede e non si aspetta;
  - `void Vote(Guid userId)` → `Voted` (ammesso in tutte e due le fasi); `bool Skip(Guid userId)` → `Skipped`, false in `Revealed`;
  - `string? RevealIfDue(DateTimeOffset now)`: in `Voting`, `"allVoted"` se nessun presente è in `Waiting`, `"timeout"` se `now >= EndsAt`; passa a `Revealed`; null se niente;
  - `bool Reveal(DateTimeOffset now)`: false se già `Revealed`;
  - `RatingRoundDto Snapshot(Guid viewerId, bool viewerIsCreator, IReadOnlyDictionary<Guid, StoredRating> ratings)`: `CanReveal` = creatore e `Voting`; `Mine` dal voto di chi guarda; `Voters` dei presenti per nome (`OrdinalIgnoreCase`); solo in `Revealed`, `Results` dei presenti `Voted` con un voto in `ratings`, dal voto più alto (a pari voto per nome), e `Average` dei loro voti.
  - `Rev` cresce come nella decisione 8.

- [ ] **Step 1: test che falliscono**

Aiuti del file: `Round(params UserRef[] present)` apre a `T0` con `TimeSpan.FromMinutes(2)` (`RatingRoundService` arriva nel Task 4) e fa `SetPresent`; `Ratings(params (Guid UserId, int Score, string? Comment)[])` costruisce il dizionario di `StoredRating` a `T0`.

```csharp
[Fact]
public void WhileVotingTheSnapshotHasOnlyStatuses()
{
    var round = Round(_mario, _luigi);
    round.Vote(_luigi.Id);
    var ratings = Ratings((_luigi.Id, 9, "Bello"), (_mario.Id, 7, null));

    var seen = round.Snapshot(_mario.Id, viewerIsCreator: true, ratings);
    Assert.Equal(RatingPhases.Voting, seen.Phase);
    Assert.True(seen.CanReveal);
    Assert.Equal(new RatingScoreDto(7, null), seen.Mine);
    Assert.Equal(
        new[] { new RatingVoterDto(N(_luigi.Id), "Luigi", RatingVoterStatuses.Voted), new RatingVoterDto(N(_mario.Id), "Mario", RatingVoterStatuses.Waiting) },
        seen.Voters);
    Assert.Null(seen.Results);
    Assert.Null(seen.Average);
    Assert.DoesNotContain("Bello", JsonSerializer.Serialize(seen));
}

[Fact]
public void RevealedResultsAreThePresentVotersFromTheHighest()
{
    var round = Round(_mario, _luigi, _peach);
    round.Vote(_mario.Id); round.Vote(_luigi.Id); round.Skip(_peach.Id);
    Assert.Equal("allVoted", round.RevealIfDue(T0));
    var seen = round.Snapshot(_luigi.Id, viewerIsCreator: false, Ratings((_mario.Id, 7, null), (_luigi.Id, 9, "Bello")));
    Assert.Equal(new[] { "Luigi", "Mario" }, seen.Results!.Select(r => r.Name));
    Assert.Equal(new RatingResultDto(N(_luigi.Id), "Luigi", 9, "Bello"), seen.Results[0]);
    Assert.Equal(8.0, seen.Average);
    Assert.False(seen.CanReveal);
}
```

E inoltre:
- `LeaversAreNotAwaitedAndJoinersWait`: Mario vota, Luigi in `Waiting`; `SetPresent([mario])` → `RevealIfDue` = `"allVoted"`. Un'altra votazione: `SetPresent([mario, peach])` → Peach in `Waiting`, `RevealIfDue(T0)` null.
- `ALeaverWhoVotedIsNotInTheResults`: Luigi vota 9 ed esce; dopo `Reveal`, `Results` non ha Luigi e la media è quella degli altri.
- `TheDeadlineRevealsAfterTwoMinutes`: `RevealIfDue(T0 + 1:59)` null, `RevealIfDue(T0 + 2:00)` = `"timeout"`, `RevealedAt` = quell'ora.
- `SkipOnlyWhileVotingAndVoteAlsoAfter`: dopo `Reveal`, `Skip` → false; `Vote` di chi era `Waiting` → `Voted` e compare nei risultati.
- `RevGrowsOnlyWithAVisibleChange`: `SetPresent` con gli stessi presenti non cambia `Rev`; `Vote`, `Skip`, `SetPresent` diverso e `Reveal` lo fanno crescere; un secondo `Reveal` no.

- [ ] **Step 2–4:** `--filter "FullyQualifiedName~RatingRoundTests"`: prima FAIL, poi il codice, poi PASS e suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): rating round state"
```

### Task 4: `RatingRoundService` e l'avviso `RatingRoundUpdated`

**Files:**
- Create: `Hub/RatingRoundService.cs`
- Modify: `Protocol/SocialEvent.cs`, `Tests/ProtocolJsonTests.cs`, `Tests/TestRatings.cs` (`Rounds(...)`)
- Test: `Tests/RatingRoundServiceTests.cs`

**Interfaces:**
- Consumes: `RatingRound` (Task 3), `RatingService.Save`/`Of` (Task 2), `IRatingLibrary.RoundTarget`, `ILibraryAccess.CanSee`, `IGroupDirectory.GetParticipants`, `ISessionDirectory.GetAppSessions`, `IUserDirectory.GetUsers`, `PartyDirectory.Get`, `IEventSender`.
- Produces:
  - `SocialEventTypes.RatingRoundUpdated = "RatingRoundUpdated"`; `SocialEvent.State` diventa `object?` (decisione 5); `SocialEvent.RatingRoundUpdated(RatingRoundDto state)`.
  - `RatingOutcome(HubStatus Status, string? Reason, RatingRoundDto? State)` con `Ok(state)`, `Conflict(reason)`, `Invalid`, `RateLimited` (come `MatchOutcome`). `Ok(null)` vuol dire `{}`.
  - `RatingRoundService(RatingService ratings, IRatingLibrary library, ILibraryAccess access, IGroupDirectory groups, ISessionDirectory sessions, IUserDirectory users, PartyDirectory parties, IEventSender sender, TimeProvider time, ILogger<RatingRoundService> logger) : IDisposable`:
    - `static readonly TimeSpan VotingTime = 2 min`, `RevealedKept = 10 min`, `PushInterval = 250 ms`;
    - `RatingOutcome Open(Guid userId, OpenRatingRoundRequest? request)`;
    - `RatingOutcome Get(Guid userId, Guid groupId)`;
    - `RatingOutcome Vote(Guid userId, Guid groupId, RateRequest? request)`;
    - `RatingOutcome Skip(Guid userId, Guid groupId)`, `RatingOutcome Reveal(Guid userId, Guid groupId)`;
    - `int Cleanup()`; `void Dispose()`.
  - `TestRatings.Rounds(FakeServer server, RatingService ratings, TimeProvider time, PartyDirectory? parties = null) : RatingRoundService`.

**Regole** (spec §6.2, decisioni 2, 6, 7, 9):
- **Presenti** (fuori dal lock, chiedono a Jellyfin): `IReadOnlyList<UserRef>? Present(Guid groupId, Guid callerId, IEnumerable<Guid> known)`: le sessioni di `GetAppSessions()` di chi chiama, poi quelle di `known`; la prima `GetParticipants` non null; i nomi diventano utenti di `GetUsers()` senza badare alle maiuscole (chi non si trova si salta). Chi chiama è presente se il suo id è nell'elenco.
- **`Open`:** `GroupId` e `ItemId` validi, altrimenti `Invalid`; poi presenti (null o chi chiama assente → `Conflict(NotMember)`); poi `CanSee(chi chiama, ItemId)` e `RoundTarget(ItemId)` (null, falso o un errore → `Invalid` con `Warning` per l'errore). Sotto il lock: con una votazione dello stesso gruppo e dello stesso titolo risolto si risponde con quella (dopo `SetPresent`); con un titolo diverso la vecchia si chiude (timer via) e si apre la nuova, con un timer `time.CreateTimer(_ => Expire(groupId, round), null, VotingTime, Timeout.InfiniteTimeSpan)`. `Debug` "Votazione {GroupId} aperta su {ItemId}".
- **Ogni chiamata su una votazione** (`Get`, `Vote`, `Skip`, `Reveal`) rilegge i presenti e fa `SetPresent` e `RevealIfDue` prima di rispondere. Senza votazione, o con chi chiama non presente: `Get` → `Ok(null)`; gli altri → `Closed` o `NotMember` (decisione 7).
- **`Vote`:** chi chiama presente, poi `ratings.Save(userId, round.ItemId, request?.Score, request?.Comment)` (`Invalid` → 400, `RateLimited` → 429, la votazione non cambia), poi `round.Vote` e `RevealIfDue`.
- **`Reveal`:** il creatore è `parties.Get(groupId)?.CreatorId`; diverso da chi chiama o null → `NotCreator`.
- **`Expire`:** sotto il lock, se `_rounds[groupId]` è ancora quella votazione, `RevealIfDue(now)`.
- **Cambio di fase:** `Debug` "Votazione {GroupId}: voti scoperti ({Reason})" con `allVoted`, `timeout` o `creator`.
- **Avvisi:** ogni cambio di `Rev` fa `Push(round, immediate: false)` come in `MatchService`, ma la consegna è per destinatario: per ogni presente `SocialEvent.RatingRoundUpdated(round.Snapshot(id, id == creatore, ratings.Of(itemId, presenti)))` alle sue sessioni WonderFlix. Lo stato si calcola sotto il lock e si manda fuori. Ordine dei lock: quello delle votazioni, poi quello di `RatingService` (che non chiama mai le votazioni).
- **Sostituzione:** `Debug` "Votazione {GroupId} chiusa: nuovo titolo {ItemId}".
- **`Cleanup`:** per ogni votazione, i presenti; null → scartata (`Debug` "Votazione {GroupId} scartata: gruppo finito"); `Revealed` da `RevealedKept` → scartata (`Debug` "…: tempo finito"); altrimenti `SetPresent`, `RevealIfDue` e l'avviso se `Rev` è cambiato. Nessun avviso per le scartate (decisione 9). Restituisce quanti cambi.

- [ ] **Step 1: test che falliscono**

In `Tests/ProtocolJsonTests.cs`:

```csharp
[Fact]
public void RatingRoundUpdatedCarriesTheStateLikeMatchUpdated()
{
    var state = new RatingRoundDto("g1", "i1", RatingPhases.Voting, 2, new DateTimeOffset(2026, 10, 20, 21, 2, 0, TimeSpan.Zero),
        false, null, [new RatingVoterDto("u1", "Mario", RatingVoterStatuses.Waiting)], null, null);
    Assert.Equal(
        "{\"Protocol\":1,\"Type\":\"RatingRoundUpdated\",\"State\":{\"GroupId\":\"g1\",\"ItemId\":\"i1\",\"Phase\":\"Voting\",\"Rev\":2,"
        + "\"EndsAt\":\"2026-10-20T21:02:00+00:00\",\"CanReveal\":false,\"Voters\":[{\"UserId\":\"u1\",\"Name\":\"Mario\",\"Status\":\"Waiting\"}]}}",
        JsonSerializer.Serialize(SocialEvent.RatingRoundUpdated(state)));
}
```

(il test esistente di `MatchUpdated` resta com'è e deve passare).

`Tests/RatingRoundServiceTests.cs`. Impianto: Mario, Luigi, Peach con una sessione WonderFlix ciascuno; il gruppo `_group` in `_server.Groups` con `["mario", "LUIGI", "Peach"]` (nomi di SyncPlay); Mario creatore (`parties.Register(_group, _mario.Id, PartyModes.Friends)`); `_film` con `RoundTargets[_film.Id] = _film.Id`; un episodio `_last` con `RoundTargets[_last.Id] = _season.Id`; `_middle` senza voce.

```csharp
[Fact]
public void OpeningTheSameTitleTwiceKeepsOneRoundAndAnotherTitleReplacesIt()
{
    var first = _rounds.Open(_mario.Id, Request(_group, _film.Id)).State!;
    var again = _rounds.Open(_luigi.Id, Request(_group, _film.Id)).State!;
    Assert.Equal(first.EndsAt, again.EndsAt);
    Assert.Equal(N(_film.Id), again.ItemId);

    var season = _rounds.Open(_mario.Id, Request(_group, _last.Id)).State!;
    Assert.Equal(N(_season.Id), season.ItemId);
    Assert.Equal(N(_season.Id), _rounds.Get(_peach.Id, _group).State!.ItemId);
}

[Fact]
public void UpdatesWhileVotingNeverCarryOtherVotes()
{
    _rounds.Open(_mario.Id, Request(_group, _film.Id));
    _rounds.Vote(_luigi.Id, _group, Vote(9, "Splendido"));
    _time.Advance(RatingRoundService.PushInterval);
    _rounds.Vote(_luigi.Id, _group, Vote(8, "Splendido, sì"));
    _time.Advance(RatingRoundService.PushInterval);

    Assert.All(_server.Sent.Where(s => s.SessionId != "s-luigi"), sent => Assert.DoesNotContain("Splendido", sent.Payload));
    var toMario = Last<RatingRoundDto>(_server.SentTo("s-mario"));
    Assert.True(toMario.CanReveal);
    Assert.False(Last<RatingRoundDto>(_server.SentTo("s-luigi")).CanReveal);
    Assert.Equal(new RatingScoreDto(8, "Splendido, sì"), Last<RatingRoundDto>(_server.SentTo("s-luigi")).Mine);
}

[Fact]
public void TheTimerRevealsAfterTwoMinutesWithoutCalls()
{
    _rounds.Open(_mario.Id, Request(_group, _film.Id));
    _time.Advance(RatingRoundService.VotingTime);
    Assert.Equal(RatingPhases.Revealed, Last<RatingRoundDto>(_server.SentTo("s-peach")).Phase);
}
```

(`Last<T>` legge l'ultimo payload e ne prende `State`.)

E inoltre:
- `OpenNeedsAMovieOrTheLastEpisode`: `_middle` → `Invalid`; un id non valido → `Invalid`; `_film` in `Unseen` per Mario → `Invalid`; `RatingLibraryFails` → `Invalid`.
- `NonMembersGet409AndAnEmptyGet`: Toad (sessione sua, non nel gruppo): `Open` → `Conflict(NotMember)`, `Get` → `Ok(null)`, `Vote` → `Conflict(NotMember)`; un gruppo sconosciuto: `Open` → `NotMember`, `Skip` → `Closed`.
- `ParticipantsMatchUsersIgnoringCase`: `"LUIGI"` nel gruppo → Luigi in `Voters` e il suo `Vote` → `Ok`.
- `RevealsWhenEveryoneVotedOrSkipped`: Mario 7, Luigi 9, Peach `Skip` → `Phase` `Revealed`, `Results` Luigi e Mario, `Average` 8.
- `TheCreatorRevealsAndOthersCannot`: `Reveal` di Luigi → `NotCreator`; di Mario → `Revealed`; di nuovo → `Ok` con lo stesso `Rev`.
- `AnUnknownCreatorLeavesOnlyAllVotedAndTimeout`: senza `parties.Register` → `CanReveal` falso per tutti e `Reveal` di Mario → `NotCreator`.
- `LeaversAreNotAwaitedAndJoinersWait`: Mario e Luigi votano; Peach tolta da `_server.Groups[_group]` → al `Get` successivo `Revealed`. In un'altra votazione: Toad aggiunto al gruppo → `Waiting` in `Voters`.
- `AVoteAfterRevealIsSavedAndShown`: dopo il tempo, `Vote` di Peach 6 → `Ok`, `Results` ha Peach, `ratings.ForItem(peach, film).Mine` = 6. `Skip` dopo il tempo → `Closed`.
- `AVoteDoesNotNeedTheTitleWatched` e `InvalidVotesAre400`: `WatchedTitles` vuoto → `Vote` `Ok`; `Score` 11 → `Invalid`, e lo stato non cambia.
- `RoundsAreDiscardedTenMinutesAfterRevealOrWhenTheGroupEnds`: `Revealed` a T; `Cleanup` a T + 9:59 → votazione c'è; a T + 10:00 → `Get` → `Ok(null)`. Un'altra: `_server.Groups.Remove(_group)` → `Cleanup` > 0 e `Get` → `Ok(null)`.
- `UpdatesAreCoalescedEvery250ms`: tre voti in fila nello stesso istante → un avviso subito per sessione, poi uno solo dopo `PushInterval`, con l'ultimo `Rev`.

- [ ] **Step 2–4:** `--filter "FullyQualifiedName~RatingRoundServiceTests|FullyQualifiedName~ProtocolJsonTests"`: prima FAIL, poi il codice, poi PASS e suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): end of party rating rounds"
```

## Gruppo B — endpoint e Jellyfin

### Task 5: `RatingsController` e `RatingsAdminController`

**Files:**
- Create: `Api/RatingsController.cs`, `Api/RatingsAdminController.cs`
- Test: `Tests/RatingsControllerTests.cs`

**Interfaces:**
- Consumes: `RatingService` (Task 2), `RatingRoundService`, `RatingOutcome` (Task 4).
- Produces:
  - `RatingsController(IAuthorizationContext authorizationContext, RatingService ratings, RatingRoundService rounds)`, con `[ApiController]`, `[Route("WonderFlixWatchParty")]`, `[Authorize(Policy = Policies.SyncPlayHasAccess)]`: `OpenRound([FromBody] OpenRatingRoundRequest?)` (`POST Ratings/Rounds`), `GetRound(string groupId)` (`GET Ratings/Rounds/{groupId}`), `VoteInRound(string groupId, [FromBody] RateRequest?)`, `SkipRound(string groupId)`, `RevealRound(string groupId)`, `GetRatings([FromQuery] string? itemId)` (`GET Ratings`), `Rate(string itemId, [FromBody] RateRequest?)` (`PUT Ratings/{itemId}`), `DeleteRating(string itemId)` (`DELETE Ratings/{itemId}`).
  - `RatingsAdminController(IAuthorizationContext authorizationContext, RatingService ratings)`, `[Authorize]` sulla classe: `GetComments([FromQuery] string? before)` e `DeleteComment(string userId, string itemId)`, ognuno con `[Authorize(Policy = Policies.RequiresElevation)]`.
- Risposte: `RatingOutcome` → 200 con lo stato, 200 `RatingRoundEmptyDto` per `Ok(null)`, 409 `RatingErrorDto`, 429, 400 (come `MatchController.Result`). `HubStatus.Ok` di `Rate`/`DeleteRating`/`DeleteComment` → 204; `Invalid` → 400; `RateLimited` → 429. Un `groupId` di rotta non valido → 400.

- [ ] **Step 1: test che falliscono** (impianto come `RecommendationsControllerTests`: utenti `new User("mario", …)` anche in `FakeServer.Users`, `FakeAuthorizationContext`)

- `RoundEndpointsMapTheOutcomes`: `OpenRound` → `OkObjectResult` con `RatingRoundDto`; `GetRound` di Toad → `OkObjectResult` con `RatingRoundEmptyDto` e JSON `{}`; `GetRound("abc")` → 400; `RevealRound` di Luigi → 409 con `RatingErrorDto("NotCreator")`; `VoteInRound` con `Score` 0 → 400.
- `RatingsEndpointsMapTheOutcomes`: `GetRatings` → `ItemRatingsDto`; `GetRatings("abc")` → 400; `Rate` → 204; `DeleteRating` → 204; il 61° `Rate` → 429.
- `AdminEndpoints`: `GetComments` → `AdminCommentsDto`; `GetComments("ieri")` → 400; `DeleteComment` → 204; `DeleteComment("x", "y")` → 400.
- `PoliciesAndNoRouteConstraints`: `RatingsController` ha una sola `AuthorizeAttribute` con `Policies.SyncPlayHasAccess`; `RatingsAdminController` ha `[Authorize]` senza policy sulla classe e `Policies.RequiresElevation` su `GetComments` e `DeleteComment`; nessun template di `HttpGet`/`HttpPost`/`HttpPut`/`HttpDelete` dei due controller contiene `:` (niente vincoli di rotta). I template sono esattamente `Ratings/Rounds`, `Ratings/Rounds/{groupId}`, `Ratings/Rounds/{groupId}/Vote`, `…/Skip`, `…/Reveal`, `Ratings`, `Ratings/{itemId}` (PUT e DELETE), `Ratings/Admin/Comments`, `Ratings/Admin/Comments/{userId}/{itemId}`.

- [ ] **Step 2–4:** `--filter "FullyQualifiedName~RatingsControllerTests"`: FAIL, il codice, PASS e suite intera.

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): ratings endpoints"
```

### Task 6: verifiche su Jellyfin 10.11.9, `JellyfinRatingLibrary` e `RatingsHostedService`

**Files:**
- Create: `Server/JellyfinRatingLibrary.cs`, `RatingsHostedService.cs`
- Test: `Tests/JellyfinRatingLibraryTests.cs`, `Tests/RatingsHostedServiceTests.cs`

**Interfaces:**
- Consumes: `IRatingLibrary`, `RatedTitle` (Task 2), `RatingService.Load`/`Cleanup` (Task 2), `RatingRoundService.Cleanup` (Task 4).
- Produces: `JellyfinRatingLibrary(ILibraryManager libraryManager, IUserManager userManager, IUserDataManager userDataManager) : IRatingLibrary`; `RatingsHostedService(RatingService ratings, RatingRoundService rounds, TimeProvider time, ILogger<RatingsHostedService> logger) : IHostedService, IDisposable` con `RoundsInterval` (30 s) e `StoreInterval` (5 min).

- [ ] **Step 1: verifiche sul sorgente** (spec §12)

Rileggi al tag `v10.11.9` (e `v10.11.0` per le firme) i punti di "Note tecniche verificate" → "Jellyfin 10.11.9": `BaseItemRepository.TranslateQuery` (`IsPlayed`, `IsVirtualItem ?? IsMissing`, `ParentIndexNumber`, `MinIndexNumber`), `Series.FilterEpisodesBySeason`, `Episode.IndexNumberEnd`/`SeasonId`, `UserDataManager.UpdatePlayState`. Se qualcosa è diverso, correggi l'adattatore in modo minimo e annotalo per il Task 9.

- [ ] **Step 2: test che falliscono**

`Tests/JellyfinRatingLibraryTests.cs` con `InterfaceStub<ILibraryManager>` (`GetItemById`, `GetItemList` che registra le query), `InterfaceStub<IUserManager>` (`GetUserById`) e `InterfaceStub<IUserDataManager>` (`GetUserData`):

```csharp
[Fact]
public void TheLastEpisodeOfASeasonGivesTheSeason()
{
    // S02E07-E08, doppio; nessun episodio dopo.
    var episode = new Episode { Id = Guid.NewGuid(), SeriesId = _series, SeasonId = _season, ParentIndexNumber = 2, IndexNumber = 7, IndexNumberEnd = 8 };
    _items[episode.Id] = episode;

    Assert.Equal(_season, Library().RoundTarget(episode.Id));
    var query = Assert.Single(_queries);
    Assert.Equal(new[] { _series }, query.AncestorIds);
    Assert.Equal(new[] { BaseItemKind.Episode }, query.IncludeItemTypes);
    Assert.Equal(2, query.ParentIndexNumber);
    Assert.Equal(9, query.MinIndexNumber);
    Assert.False(query.IsVirtualItem);
    Assert.Null(query.User);
    Assert.Equal(1, query.Limit);
}

[Fact]
public void ASeasonIsWatchedWhenNoRealEpisodeIsUnplayed()
{
    var title = new RatedTitle(_season, true, "Breaking Bad · Stagione 2");
    Assert.True(Library().HasWatched(_luigi.Id, title));
    var query = Assert.Single(_queries);
    Assert.Same(_luigi, query.User);
    Assert.False(query.IsPlayed);
    Assert.False(query.IsVirtualItem);
    Assert.Equal(2, query.ParentIndexNumber);
    Assert.Equal(new[] { _series }, query.AncestorIds);
    Assert.Equal(1, query.Limit);
}
```

E inoltre:
- `AMiddleEpisodeGivesNothing`: `GetItemList` restituisce un episodio → `RoundTarget` null.
- `AMovieIsItsOwnTargetAndOtherTypesNone`: `Movie` → il suo id, senza query; `Series`, `Season`, un id sconosciuto, `Guid.Empty`, un episodio senza `IndexNumber` o senza `SeasonId` → null.
- `RatedTitlesHaveTheirDisplayNames`: `Movie { Name = "Il Padrino", ProductionYear = 1972 }` → `RatedTitle(id, false, "Il Padrino (1972)")`; senza anno → `"Il Padrino"`; `Season { SeriesName = "Breaking Bad", IndexNumber = 2 }` → `"Breaking Bad · Stagione 2"`; `IndexNumber = 0` → `"Breaking Bad · Speciali"`; senza `IndexNumber` → null; `Episode` → null.
- `AMovieIsWatchedWhenPlayed`: `GetUserData` con `Played = true` → vero; `false` o null → falso; utente sconosciuto → falso.
- `TheSeasonQueryCarriesTheUsersContentLimits` (come `JellyfinMatchLibraryTests`): `_luigi.MaxParentalRatingScore = 12`, `HasWatched` sulla stagione → `Assert.NotNull(Assert.Single(_queries).MaxParentalRating)` (la query nasce con `new InternalItemsQuery(user)`).

`Tests/RatingsHostedServiceTests.cs` (come `MatchHostedServiceTests`):
- `StartLoadsAndBothTimersClean`: `StartAsync` legge il file (un `ratings.json` illeggibile diventa `.bad` subito); una votazione scoperta e poi 10 minuti → il giro successivo dei 30 s la scarta (`Get` → `Ok(null)`); un utente tolto da `Users` → dopo `Advance(5 min)` il suo voto non è più nel file.

- [ ] **Step 3: il codice**

`JellyfinRatingLibrary`:
- `FindRated`: `itemId != Guid.Empty`, `GetItemById`; `Movie` → `"{Name} ({ProductionYear})"` o `Name`; `Season` con `IndexNumber` → `"{SeriesName} · Stagione {n}"`, 0 → `"{SeriesName} · Speciali"` (testi in `CultureInfo.InvariantCulture`); altrimenti null.
- `RoundTarget`: `Movie` → il suo id; `Episode` con `SeriesId`, `SeasonId`, `ParentIndexNumber` e `IndexNumber` → la query `new InternalItemsQuery { AncestorIds = [SeriesId], IncludeItemTypes = [Episode], ParentIndexNumber, MinIndexNumber = (IndexNumberEnd ?? IndexNumber) + 1, IsVirtualItem = false, Limit = 1 }`: vuota → `SeasonId`, altrimenti null.
- `HasWatched`: film → `userDataManager.GetUserData(user, item)?.Played == true`; stagione → `GetItemList(new InternalItemsQuery(user) { AncestorIds = [season.SeriesId], IncludeItemTypes = [Episode], ParentIndexNumber = season.IndexNumber, IsVirtualItem = false, IsPlayed = false, Limit = 1 }).Count == 0`.
- Commento nella classe: le verifiche su 10.11.9 (punti di "Note tecniche verificate") in una riga ciascuna.

`RatingsHostedService`: `StartAsync` chiama `ratings.Load()` nel suo `try/catch` (`Warning` "Voti non caricati all'avvio"), poi due timer con `time.CreateTimer(...)`, ognuno con il suo `try/catch` e `Debug` "Pulizia …: {Count} cambi" se > 0; `StopAsync`/`Dispose` come `MatchHostedService`.

- [ ] **Step 4: i test passano** (`--filter "FullyQualifiedName~JellyfinRatingLibraryTests|FullyQualifiedName~RatingsHostedServiceTests"`, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): Jellyfin ratings library and cleanup service"
```

### Task 7: montaggio, `Info` e plugin 1.11.0

**Files:**
- Modify: `PluginServiceRegistrator.cs`, `Protocol/WatchPartyProtocol.cs`, `Jellyfin.Plugin.WonderFlixWatchParty.csproj`, `Plugin.cs`, `../meta.template.json`, `../README.md`
- Modify (test): `Tests/ServiceRegistrationTests.cs`, `Tests/InfoControllerTests.cs`

- [ ] **Step 1: test che falliscono**

In `Tests/ServiceRegistrationTests.cs`, prima del conteggio:

```csharp
        // Voti degli amici (spec Q).
        Assert.Same(provider.GetRequiredService<RatingService>(), provider.GetRequiredService<RatingService>());
        Assert.Same(provider.GetRequiredService<RatingRoundService>(), provider.GetRequiredService<RatingRoundService>());
        Assert.IsType<Server.JellyfinRatingLibrary>(provider.GetRequiredService<IRatingLibrary>());
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.RatingsController>(provider));
        Assert.NotNull(ActivatorUtilities.CreateInstance<Api.RatingsAdminController>(provider));
```

e il conteggio diventa `Assert.Equal(7, …)`, con la riga di commento "I voti degli amici (spec Q), oltre ai sei di prima.".

In `Tests/InfoControllerTests.cs`: `"1.11.0"` e, nei due elenchi, `"ratings"` dopo `"match"`. Cerca con `grep` altri test su versione, funzioni o `Description` (per esempio `PluginPagesTests`) e aggiornali con la stessa regola.

- [ ] **Step 2: i test falliscono** (`--filter "FullyQualifiedName~ServiceRegistrationTests|FullyQualifiedName~InfoControllerTests"`).

- [ ] **Step 3: il codice**

- `PluginServiceRegistrator.cs`, dopo il blocco "Match del film (spec P)":
  ```csharp
        // Voti degli amici (spec Q).
        serviceCollection.AddSingleton(provider => new RatingStore(
            RatingStore.DefaultPath(provider.GetRequiredService<IApplicationPaths>()),
            provider.GetRequiredService<ILogger<RatingStore>>()));
        serviceCollection.AddSingleton<IRatingLibrary, JellyfinRatingLibrary>();
        serviceCollection.AddSingleton<RatingService>();
        serviceCollection.AddSingleton<RatingRoundService>();
  ```
  e in fondo `serviceCollection.AddHostedService<RatingsHostedService>();`.
- `WatchPartyProtocol.Features`: "spec Q §6.5" nel commento, `"ratings"` dopo `"match"`.
- csproj: `<Version>1.11.0</Version>`.
- `Plugin.cs`: nel commento della classe "e, dalla 1.11.0, i voti degli amici (spec Q)"; in `Description`, dopo "the movie match", ", friends' ratings".
- `../meta.template.json`: `description` dopo la frase del match ", friends' ratings (a 1 to 10 rating with a comment at the end of a watch party, revealed to everyone at once, and friends' ratings on the title page)"; `overview` dopo "movie match" ", friends' ratings".
- `../README.md`:
  - nell'introduzione, dopo la frase della 1.10.0: "Dalla 1.11.0 ci sono i voti degli amici: a fine film nel watch party ognuno vota da 1 a 10, i voti si scoprono tutti insieme, e nella scheda restano la media e i commenti degli amici (spec Q, `docs/superpowers/specs/2026-10-20-wonderflix-voti-amici-design.md`).";
  - un punto "**Voti degli amici (dalla 1.11.0):**" dopo quello del match: `ratings.json` (un voto per utente e titolo, film o stagione); la votazione di fine party in memoria per gruppo (`POST Ratings/Rounds`, `Vote`, `Skip`, `Reveal`; voti scoperti per tutti votato, 2 minuti o il creatore; avviso `RatingRoundUpdated`, mai voti altrui prima); `GET Ratings?itemId=` solo con i voti degli amici, `PUT`/`DELETE Ratings/{itemId}`; 60 scritture all'ora; `GET`/`DELETE Ratings/Admin/Comments` per l'admin; i 409 hanno `{Reason}`;
  - nel punto "Funzioni": "…dalla 1.10.0 anche `match`, dalla 1.11.0 anche `ratings`…"; "Quelli di `Ratings` hanno la stessa policy degli amici, tranne `Ratings/Admin`, solo per l'admin.";
  - in "Installazione a mano": `pack.sh 1.11.0` e `WonderFlix Watch Party_1.11.0.0/`.

- [ ] **Step 4: i test passano** (stesso comando, poi la suite intera).

- [ ] **Step 5: commit**

```powershell
git add jellyfin-plugin-watch-party
git commit -m "feat(plugin): friends ratings wiring and plugin 1.11.0"
```

---

## Gruppo C — server e chiusura

### Task 8: STOP — build di prova sul server (lo fa l'orchestratore)

Il subagent del Gruppo B si ferma qui. L'orchestratore fa la review finale del branch e i ritocchi, poi questi passi, con un solo riavvio di Jellyfin e **dopo l'OK dell'utente al riavvio**. Il server lo usano gli amici: ogni passo che ferma Jellyfin aspetta che nessuno stia guardando. Gli script vanno in un file nella scratchpad, copiati con `scp` e lanciati con `ssh ultra "sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' f.sh && bash f.sh; rm -f f.sh"` (memoria `ultra-ssh`). **Nessuno script stampa chiavi o token.**

1. **Riferimenti della dll:** la dll di Release contro gli assembly di Jellyfin 10.11.9, come per le versioni passate: nessun membro non risolto (in particolare `InternalItemsQuery.ParentIndexNumber`/`MinIndexNumber` e `Episode.IndexNumberEnd`).
2. **Pacchetto:** dalla root del worktree, con il PATH rinfrescato, `& "C:\Program Files\Git\bin\bash.exe" jellyfin-plugin-watch-party/pack.sh 1.11.0` → `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.11.0.0/`.
3. **Installazione** (`ssh ultra`):
   - controlla che nessuno stia guardando (`/Sessions` con la chiave API "Wonderflix": base `http://127.0.0.1:17502/jellyfin`, intestazione `Authorization: MediaBrowser Token="<chiave>"`); se qualcuno guarda, aspetta;
   - `app-jellyfin stop`;
   - `mkdir -p ~/wfwp-backup`; sposta `~/.apps/jellyfin/data/plugins/WonderFlix Watch Party_1.10.1.0` in `~/wfwp-backup/1.10.1.0-catalogo` (con un suffisso se c'è già); copia `~/.apps/jellyfin/data/plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml` in `~/wfwp-backup/config-1.10.1-prima-23a.xml`;
   - `scp -r` della cartella `WonderFlix Watch Party_1.11.0.0` in `ultra:.apps/jellyfin/data/plugins/`, poi `ls` per controllare il nome;
   - `app-jellyfin start`, poi nel log di oggi `Loaded plugin: "WonderFlix Watch Party" "1.11.0.0"` e nessun errore del plugin. L'avvio può durare minuti.
   - **Se qualcosa va storto:** ferma Jellyfin, sposta via la cartella 1.11.0.0, rimetti `~/wfwp-backup/1.10.1.0-catalogo` e la configurazione salvata, riavvia, e segnalalo.
4. **Controlli** (stessa base e intestazione; risposte riassunte con `python3`, mai stampate intere):
   - `GET /WonderFlixWatchParty/Info`: versione `1.11.0`; funzioni con `ratings`, e ancora `match`, `friendsActivity`, `recommendations`, `home`, `account`;
   - `GET /WonderFlixWatchParty/Ratings?itemId=x` e `POST /WonderFlixWatchParty/Ratings/Rounds` con la sola chiave API: **non 404** (la policy SyncPlay respinge la chiave: 401 o 403);
   - `GET /WonderFlixWatchParty/Ratings/Admin/Comments` con la chiave API: 200 con `{"Items":[]}`;
   - nel log la riga "Voti in …/WonderFlixWatchParty/ratings.json" e nessun `Warning` del plugin dopo l'avvio;
   - spec §12, dal vivo e in sola lettura: il valore di `MaxResumePct` nella configurazione di Jellyfin (`system.xml`; 90 se manca), da riportare nel Task 9;
   - nella configurazione del plugin `SeerrUrl`, `SonarrUrl`, `ContactReminderDays`, `HomeRowsSeen` ancora al loro posto.
   - Il giro completo (votazione nel party, scheda, dashboard) si prova con l'app nel piano 23b.
5. **Riporta all'utente** l'esito in breve: versione, funzioni, `MaxResumePct`, eventuali avvisi nel log.

La build di prova resta sul server fino al rilascio (fine del 23b). Le app 0.16.x non chiamano gli endpoint dei voti.

### Task 9: allineamento della spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-20-wonderflix-voti-amici-design.md`
- Modify: `docs/superpowers/plans/2026-10-20-wonderflix-23a-voti-plugin.md` (solo una voce "Dalle review dei gruppi" nelle decisioni, se ci sono differenze)

- [ ] **Step 1: la spec**, controllando ogni frase sul codice:
- **Stato:** "approvata il 2026-10-20; piano 23a realizzato (`docs/superpowers/plans/2026-10-20-wonderflix-23a-voti-plugin.md`), build di prova sul server; piano 23b da realizzare".
- **§6.2:** i presenti letti dalle sessioni WonderFlix, e il gruppo che nessuna di loro vede più conta come finito (decisione 2); l'apertura idempotente anche in `Revealed` (decisione 6); `Rev` (decisione 8); nessun avviso quando una votazione si scarta (decisione 9); la forma di `Mine` (decisione 4); l'avviso con `"State"` (decisione 5).
- **§6.3:** i motivi dei 409 (decisione 7); il limite e il `DELETE` con un id non valido (decisione 10); gli errori della libreria → 400 (decisione 18).
- **§6.4:** il controller admin a parte (decisione 1); `UpdatedAt` che non cambia (decisione 11); `before` esclusivo (decisione 15); "Speciali" per la stagione 0 (decisione 12).
- **§6.1:** la pulizia che non tocca i titoli durante una scansione o un errore della libreria (decisione 14).
- **§12:** le verifiche fatte (decisione 13 e "Note tecniche verificate"), con il valore di `MaxResumePct` del server dal Task 8.
- **§13:** 23a realizzato; il plugin 1.11.0 resta build di prova fino alla fine del 23b.
- Ogni altra differenza venuta fuori durante i task, con il motivo.

- [ ] **Step 2: commit**

Suite intera verde, poi:

```powershell
git add docs
git commit -m "docs: align the friends ratings spec with plan 23a"
```

### Task 10: ok dell'utente e merge

Con l'ok dell'utente sull'esito del Task 8: merge fast-forward su `main` e push (memoria `wonderflix-workflow`; prima `git fetch` e, se `origin/main` è avanti, rebase dei commit locali). Niente tag e niente manifest: il plugin 1.11.0 si pubblica alla fine del 23b, insieme all'app 0.17.0.

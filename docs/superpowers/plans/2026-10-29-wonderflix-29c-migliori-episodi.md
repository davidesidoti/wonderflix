# WonderFlix — Piano 29c: migliori episodi singoli nella ricerca di una stagione

**Goal:** nella ricerca di una stagione (scheda Download, solo admin), quando non c'è un pack conveniente, mostrare per ogni episodio il singolo migliore secondo la regola dell'admin e permettere di scaricarli tutti con un pulsante. Plugin 1.15.0, app 0.24.0.

**Spec:** `docs/superpowers/specs/2026-10-28-wonderflix-download-automatici-design.md` (spec T, §5.4 e §8.2).

**Decisioni (confermate dall'utente il 2026-10-29):**
1. **Riquadro "Migliori episodi"** in cima alla pagina di ricerca di una stagione, solo quando la scelta del pack è null (nessun pack o pack non conveniente, `SeasonPackRule.ChoosePack`). Una riga per episodio: numero, il singolo scelto (release, punteggio, peso, seeders, indexer, pulsante "Scarica") o "nessun file valido". Pulsante "Scarica tutti (N)", N = episodi con un singolo. Sotto resta la lista completa di oggi.
2. **Episodi considerati:** quelli che mancano (come la regola di oggi, `RuleEpisodes`). Se non ne manca nessuno (titolo da "Da ripassare"): quelli il cui file ha punteggio sotto l'obiettivo del profilo; se il profilo non ha obiettivo, tutti.
3. **Il singolo di un episodio** è `DownloadRule.Choose(singoli di quell'episodio, regola per episodio)`, la stessa scelta che usa `SeasonPackRule.ChoosePack` per i singoli e il giro quando divide la stagione. Singolo = release non `FullSeason` con un solo episodio.
4. **"Scarica tutti"** nell'app: i grab partono uno dopo l'altro con l'endpoint esistente `POST Downloads/Grab` (chiave della stagione + guid/indexer del singolo: il plugin lo segue già come voce dell'episodio, ruling 13). Prima una sola conferma se qualche episodio non migliora il file attuale o non verrebbe importato (decisione 5 del piano 29b), con quanti sono. Durante: pulsanti spenti e avanzamento "3/21". Alla fine uno SnackBar con quanti partiti e quanti no (con il primo motivo); la pagina resta aperta se qualcuno è fallito, si chiude se sono partiti tutti.

## Global Constraints
- Plugin **1.15.0** (csproj), app **0.24.0** (pubspec); `manifest.json` solo alla release.
- **JSON nuovo** in `DownloadSearchDto`: `EpisodeChoices` (sempre presente, lista vuota per film, episodi e stagioni con un pack scelto), elementi `DownloadEpisodeChoiceDto`: `EpisodeNumber` (int), `Release` (`DownloadReleaseDto`, null se nessun singolo valido, sempre scritto), `WouldImport` (bool, falso senza release). PascalCase, `[property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]` sui nullable.
- L'app legge `EpisodeChoices` in modo tollerante: campo mancante = lista vuota (plugin 1.14.0), riga rotta saltata.
- Testi it/en con chiavi `downloads…`. Stile come piani 29a/29b (commenti in italiano, codice in inglese, `/// <summary>` con riferimento alla spec nel plugin, log senza titoli di release).
- Commit: identità del repository, una riga in italiano, niente `Co-Authored-By` né "Generated with", mai closes/fixes/resolves. Niente push.
- Processi mai per nome d'immagine. Build di rilascio (se serve): `flutter build windows --release --dart-define-from-file=config/wonderflix.json` da `app/`.

### Task 1: plugin
- `DownloadService.Admin.cs` (`RunSearchAsync`/`ApplyRule` o un helper accanto): per una stagione con scelta null calcola gli episodi della decisione 2 (serve il file di ogni episodio e il punteggio obiettivo: `settings.For(...).TargetScore`, i file sono già letti in `files`) e il singolo di ognuno (decisione 3), in ordine di episodio. `WouldImport` contro il file di quell'episodio (non il peggiore della stagione).
- DTO e versione 1.15.0; README (Downloads: `EpisodeChoices`).
- Test (`DownloadServiceAdminTests`): stagione senza pack → un singolo per episodio mancante, il migliore per la regola, "nessuno" per un episodio senza singoli validi; stagione con pack scelto → lista vuota; stagione senza mancanti con un episodio sotto obiettivo → solo quello; senza obiettivo → tutti; film → lista vuota. E: **due grab di singoli di episodi diversi dalla stessa ricerca di stagione, uno dopo l'altro, partono tutti e due** (il secondo non toglie dalla coda il primo né torna Busy/Expired): verifica `GrabCalls`, le voci degli episodi e che nessun `RemoveFromQueue` tocchi il primo.
- Commit `feat(plugin): migliori episodi singoli nella ricerca di una stagione`.

### Task 2: app
- Modello: `DownloadEpisodeChoice` e `DownloadSearch.episodeChoices` (tollerante).
- `download_search_page.dart`: il riquadro della decisione 1 (largo come tabella, stretto come schede, come il resto della pagina), "Scarica tutti" della decisione 4 sul `DownloadSearchController` (un metodo `grabAll(List<DownloadCandidate|release>)` o simile, `grabbing` vero per tutta la durata, si ferma se la pagina si chiude), "Scarica" per riga = il grab di oggi.
- Test: riquadro solo quando `episodeChoices` non è vuoto; "nessun file valido"; "Scarica tutti" chiama i grab in ordine e mostra l'avanzamento, pulsanti spenti durante; un fallimento lascia la pagina aperta con il riepilogo; tutti ok → si chiude con lo SnackBar; conferma unica quando qualcuno non migliora; layout stretto senza overflow a 375.
- Versione 0.24.0; checklist in `docs/RELEASING.md` (una voce); spec T §5.4/§8.2 con le decisioni.
- Commit `feat(app): scarica i migliori episodi di una stagione`.

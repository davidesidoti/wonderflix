# Torrent già in qBittorrent: importa invece di "rifiutato"

Quando l'admin sceglie una release dalla pagina di ricerca e Sonarr/Radarr la rifiutano perché il torrent è già in qBittorrent, l'app chiede se importare i file di quel torrent. Se l'admin conferma, i file sostituiscono quelli in libreria anche se Sonarr li giudica peggiori. Niente spec a parte: questo piano è il design approvato dall'utente in chat.

## Fatti verificati sul seedbox (2026-11-03)

- Sonarr risponde 500 `Download client failed to add torrent`, e il plugin dà `GrabOutcome.Refused`. Il motivo è solo nel log di qBittorrent.
- `GET {qbit}/api/v2/log/main?normal=true&info=false&warning=false&critical=false` dà righe `{id, message, timestamp, type}`, `timestamp` in **secondi**. I due formati visti:
  - `Detected an attempt to add a duplicate torrent. Existing torrent: Una mamma per amica - Stagione 03 (2000-2016) [COMPLETA] 1080p H265 ITA AAC. Result: Trackers cannot be merged because it is a private torrent`
  - `Detected an attempt to add a duplicate torrent. Source: magnet:?xt=urn:btih:...&dn=... Existing torrent: Mushoku Tensei - Isekai Ittara Honki Dasu - 23 (Amazon Prime CBR 1080p). Result: Trackers are merged from new source`
- La release non basta per riconoscere il torrent: spesso non ha `infoHash` e il titolo differisce dal nome del torrent ("S03" contro "Stagione 03").
- `manualimport?downloadId=<hash>` non serve qui: 0 file con l'hash minuscolo, 500 con quello maiuscolo.
- `manualimport?folder=<content_path>&filterExistingFiles=false` dà i file giusti su Sonarr (22 su 22, con `series`, `episodes`, `seasonNumber`) e su Radarr (con `movie`).
- `manualimport?folder=...&seriesId=...` **ignora la cartella** e dà i file già in libreria: mai passare `seriesId`.
- Il comando `ManualImport` con `importMode: "auto"` e senza download collegato sposterebbe i file fuori dal torrent, rompendo il seed sui tracker privati: qui serve `"copy"`.

## Global Constraints

- Lavoro solo nel worktree `.claude/worktrees/torrent-gia-presente`, branch `feat/torrent-gia-presente`.
- Commenti e doc in italiano, codice in inglese, stile del codice attorno.
- Commit in italiano, formato `feat(plugin): ...` / `feat(app): ...`. Nessun trailer `Co-Authored-By` né riga "Generated with Claude Code". Nei messaggi di commit mai le parole `closes`, `fixes`, `resolves`.
- Vietato chiudere processi per nome immagine (`taskkill /IM`, `pkill`). Vietato merge e push.
- Il giro automatico, "Scarica tutti" e "Scarica il migliore" non cambiano. `GrabAsync` tiene firma e comportamento.
- Le app vecchie devono continuare a vedere l'errore di oggi: il motivo della risposta resta `Refused`.
- Non cambiare la versione del plugin né dell'app: si fa al rilascio.

## Task 1: Plugin

**File:** `Space/IQbitClient.cs`, `Space/QbitClient.cs`, `Space/QbitJson.cs`, `Home/IArrClient.cs`, `Home/ArrClient.cs`, `Home/ArrJson.cs`, `Downloads/DownloadService.cs` (costruttore), `Downloads/DownloadService.Admin.cs`, `Downloads/DownloadService.Review.cs`, `Api/DownloadsController.cs`, `Protocol/DownloadsDtos.cs`; un nuovo file per il parser; i test e i fake (`FakeQbitClient`, il fake di `IArrClient`).

1. **qBittorrent.** Aggiungi `QbitLogEntry` (`id`, `message`, `timestamp`) e `IQbitClient.GetLogAsync(CancellationToken)` con la query sopra.
2. **Parser.** Una funzione statica pura, per esempio `QbitDuplicate.NameOf(string? message)`: null se il messaggio non inizia con `Detected an attempt to add a duplicate torrent.`; altrimenti il testo tra `Existing torrent: ` e l'ultimo `. Result: ` (null se manca uno dei due). Il nome può contenere punti e parentesi. Copri con un test entrambi i formati sopra, un nome con punti e messaggi diversi.
3. **Arr client.** Aggiungi `GetManualImportByFolderAsync(kind, folder, ct)`: `manualimport?folder=<escaped>&filterExistingFiles=false`, con `SearchTimeout` come `GetManualImportAsync`, con un commento sul perché non si passa `seriesId`. Aggiungi un parametro a `ManualImportAsync` per mandare `importMode: "copy"`; il default resta `auto`, e i chiamanti esistenti non cambiano. Aggiungi `int? SeasonNumber` a `ArrManualImportItem`.
4. **Trovare il duplicato.** `DownloadService` prende un `IQbitClient? qbit = null` come **ultimo** parametro opzionale del costruttore. Nuovo metodo pubblico `GrabOrFindExistingAsync(key, guid, indexerId, ct, lighten)`, che restituisce l'esito e un `ExistingTorrent(Hash, Name)` nullable:
   - prende l'ora con `time.GetUtcNow()` e chiama `GrabAsync`;
   - solo con `Refused` e `qbit` non null legge il log; sceglie la riga **più recente** con `timestamp >= inizio - 2 s` per cui il parser dà un nome (il log ha la precisione del secondo);
   - cerca in `GetTorrentsAsync` i torrent con quel nome esatto: serve **esattamente uno**, con `Progress >= 1`, `Hash` e `ContentPath` non vuoti; altrimenti `null`;
   - una `QbitException` qui dà `null` con un log a livello Information, mai un errore: l'admin deve vedere il `Refused` di oggi.
5. **Importare.** Nuovo metodo pubblico `ImportExistingAsync(key, hash)` che restituisce `(BlockedOutcome Outcome, string? Error)`, come `ImportBlockedAsync`:
   - chiave non valida o hash vuoto: `Invalid`;
   - `_grabbing.Add(key)` falso: `Changed`; rilascia la chiave in un `finally`;
   - `qbit` null o `QbitException`: `Unavailable`;
   - torrent con quell'hash (senza distinguere maiuscole) assente, incompleto o senza `ContentPath`: `Changed`;
   - legge `GetManualImportByFolderAsync` su `ContentPath`, tiene i file `Importable` **del titolo della chiave**, poi `OnePerTitle`. Film: `Movie.Id == key.Id`. Episodio: `Episodes` contiene `key.Id`. Stagione: `Series.Id == key.Id && SeasonNumber == key.Season`;
   - nessun file: `(Failed, "NoFiles")`. Errore di Radarr/Sonarr: `(Failed, ErrorOf(ex))`, come in `ImportDownloadAsync`;
   - manda il comando con `copy`; il token è sempre `CancellationToken.None`, perché il lavoro deve finire anche se l'app si chiude;
   - dopo il successo, sotto `_lock`: per la chiave e per ogni episodio dei file importati (`Key(DownloadKinds.Episode, id)`) esegue `Book.Accept(k)` e `Book.Remove(k)`, quale che sia lo stato della voce, così il giro non rifà upgrade; poi `SaveAfterGrab()`. Fuori dal lock `Nudge()`, e `LogInformation` senza nomi di file;
   - non marcare `Lightened`.
6. **Controller.** `Grab` usa `GrabOrFindExistingAsync`: con un `ExistingTorrent` risponde 502 con un nuovo `DownloadsRefusedDto(Reason="Refused", Hash, Name)` (proprietà JSON `Reason`, `Hash`, `Name`), altrimenti `Result(outcome)` come oggi. Nuovo `POST ImportExisting` con corpo `{Key, Hash}`: 204; 400 se manca qualcosa; 409 `Changed`; 502 `NoFiles` o `ImportFailed`; 503 `Unavailable`. Riusa `Result(BlockedOutcome)` e la gestione di `Failed` di `Import`, senza duplicarla.
7. **Test** (`DownloadServiceAdminTests` o un file nuovo, e `ArrClientTests`):
   - rifiuto con duplicato trovato;
   - rifiuto senza riga nel log, con una riga più vecchia, con il torrent incompleto, con due torrent con lo stesso nome, con qBittorrent in errore o assente: niente `ExistingTorrent`;
   - un grab riuscito non legge il log;
   - import di una stagione da un pack con più stagioni: arrivano solo i file della stagione, con `copy`;
   - import di un episodio da un pack: solo quell'episodio;
   - file di un altro titolo: `NoFiles`, nessun comando;
   - la voce esce dal libro ed è accettata, anche per gli episodi;
   - la chiave occupata dà `Changed`;
   - il JSON del comando con `importMode:"copy"` e l'URL con `folder` senza `seriesId`.

**Verifica** da `plugin/`: `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`. `SubtitleServiceTests.AFailedDownloadIsFailed`, `ArrClientTests.ASlowSearchUsesTheReleaseSearchTimeout` e `DownloadAlertsTests` sono instabili: rilanciali prima di indagare.

## Task 2: App

**File:** `app/lib/core/downloads/downloads_api.dart`, `app/lib/features/downloads/download_search_controller.dart`, `app/lib/features/downloads/download_search_page.dart`, `app/l10n/app_it.arb`, `app/l10n/app_en.arb`; i test in `app/test/core/downloads/downloads_api_test.dart`, `app/test/features/downloads/download_search_controller_test.dart`, `app/test/features/downloads/download_search_page_test.dart`.

Il plugin del Task 1 risponde a `POST .../Grab` con 502 `{"Reason":"Refused","Hash":"...","Name":"..."}` se il torrent è già in qBittorrent, e con 502 `{"Reason":"Refused"}` negli altri casi. `POST .../ImportExisting` con `{"Key","Hash"}` risponde 204, 409 `Changed`, 502 `NoFiles` o `ImportFailed`, 503 `Unavailable`.

1. **API.** Aggiungi una classe `ExistingTorrent(hash, name)` e un campo opzionale `existing` a `DownloadsException`, valorizzato in `_call` solo con 502 `Refused` e `Hash` e `Name` stringhe non vuote. Aggiungi `importExisting(key, hash)` con `receiveTimeout: searchTimeout` e `quietStatuses: _quiet`.
2. **Controller.** Aggiungi un metodo per il grab singolo che restituisce failure e `ExistingTorrent?`, senza cambiare `_act`: per esempio cattura `error.existing` in una closure dentro la chiamata e rilancia. Aggiungi `importExisting(hash)` tramite `_act`. `grabAll` non cambia.
3. **Pagina.** In `_grab`, se c'è un `existing`, mostra `showAdminConfirmDialog` con titolo, messaggio con il nome del torrent ed etichetta di conferma:
   - annullato: la pagina resta com'è, senza messaggi di errore;
   - confermato: `importExisting`; con un errore `_fail(context, failure)` e la pagina resta; se va bene, snackbar "Import avviato" e `navigator.pop()`, come dopo un grab;
   - senza `existing`: `_fail` come oggi.
4. **Testi** in entrambi gli arb, poi `flutter gen-l10n`:
   - `downloadsExistingTorrentTitle`: "Già in qBittorrent" / "Already in qBittorrent"
   - `downloadsExistingTorrentMessage` con segnaposto `name`: "Il torrent \"{name}\" è già in qBittorrent. Importo i suoi file? Sostituiranno quelli in libreria." / "The torrent \"{name}\" is already in qBittorrent. Import its files? They will replace the ones in your library."
   - `downloadsExistingTorrentImport`: "Importa" / "Import"
   - `downloadsExistingTorrentStarted`: "Import avviato" / "Import started"
5. **Test:**
   - l'API legge `existing` dal 502, e non lo legge da un 502 senza `Hash`;
   - `importExisting` manda il corpo giusto e mappa gli errori;
   - nella pagina: il dialogo compare con il nome; annulla non importa; conferma importa e chiude la pagina; un errore dell'import lascia la pagina aperta; un `Refused` senza `existing` mostra l'errore di oggi.

**Verifica** da `app/`: `flutter gen-l10n`, `flutter analyze`, `flutter test test/core/downloads test/features/downloads`. In PowerShell aggiorna prima il PATH: `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`. Riporta tutti i file `app/windows/flutter/generated_plugin*` modificati solo nei fine riga con `git checkout --`, e non committarli. Non serve la build di release in questo task; se la lanci, il comando è `flutter build windows --release --dart-define-from-file=config/wonderflix.json`.

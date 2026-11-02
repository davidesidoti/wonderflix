# WonderFlix — Spec W: ricerca dei download in background

- **Data:** 2026-11-01
- **Stato:** design approvato in chat, da pianificare. Branch `fix/pwa-ios` (worktree `.claude/worktrees/pwa-ios`).
- **Ambito:** estende la Spec T (download automatici, `2026-10-28-wonderflix-download-automatici-design.md`), §8.2 (ricerca dell'admin). Plugin + app.

## 1. Perché

La ricerca manuale di una **stagione anime** (esempio: "A Sign of Affection" stagione 1) non arriva mai al risultato. Per le serie anime Sonarr, con `GET release?seriesId=…&seasonNumber=…`, cerca prima la stagione e poi **ogni episodio uno per uno**, 20–25 s ciascuno: per 12 episodi circa 5 minuti e mezzo (log di Sonarr del 2026-11-01). Oggi:

- l'app aspetta la risposta di `GET Downloads/Search` con una richiesta aperta (150 s);
- il plugin aspetta Sonarr al massimo `ArrClient.SearchTimeout` = 2 minuti, poi risponde con `Error: "Unreachable"` ("Non raggiungibile: controlla l'indirizzo");
- nginx taglia a 180 s.

Lo stesso limite di 2 minuti fa fallire anche il **giro automatico** sulle stagioni anime ("ricerca di … su Sonarr non riuscita (Unreachable)" nei log del 2026-10-31). Ogni nuovo tentativo rilancia tutta la ricerca, e Prowlarr spegne gli indexer per il limite di richieste.

Su iPhone (web app dalla Home) una richiesta aperta per minuti si perde appena iOS mette l'app in pausa.

## 2. Obiettivi

1. Una ricerca manuale può durare quanto serve (fino al nuovo limite, §4.1): il plugin la fa in background, l'app chiede a che punto è.
2. Chiudendo la pagina (o con iOS che sospende la web app) la ricerca continua; riaprendo, **i risultati sono pronti** (richiesta esplicita dell'utente).
3. **Ogni attesa si vede**: barra, testo, tempo che scorre (richiesta esplicita dell'utente: "qualsiasi azione dell'app voglio che si veda in qualche modo").
4. Il giro automatico smette di fallire sulle stagioni anime.
5. Due richieste per lo stesso titolo non lanciano due ricerche su Sonarr.

## 3. Non obiettivi e anti-obiettivi

- **Niente stima del tempo rimanente:** Sonarr non dice a che episodio è.
- **"Scarica il migliore intanto" resta com'è:** vale solo per film ed episodi (`GrabBestAsync` rifiuta le stagioni), che Sonarr/Radarr cercano in decine di secondi. *(Mia: in chat avevo proposto di cambiarlo, leggendo il codice non serve.)*
- **"Scarica"/"Cambia" non cambiano:** rifanno la ricerca solo se Radarr/Sonarr hanno dimenticato le release (dopo circa 30 minuti); con i risultati che scadono a 30 minuti (§4.3) non succede quasi mai.
- **Anti-obiettivo:** un'app 0.27.x con il plugin nuovo non deve rompersi. Anche il contrario: l'app nuova con un plugin 1.18.x continua a cercare come oggi.
- **Anti-obiettivo:** una ricerca non deve fermarsi perché l'admin ha chiuso la pagina o la connessione è caduta.

## 4. Plugin

### 4.1 Limite verso Radarr/Sonarr

- Nuova costante `ArrClient.ReleaseSearchTimeout` = **60 minuti** *(mia; erano 15: una stagione anime di 14 episodi dura ~30 minuti, nginx aspetta 3600 s)*, solo per `SearchReleasesAsync` (`GET release`). Vale per la ricerca dell'admin e per le ricerche dentro grab e grabBest. Il giro automatico cerca un titolo alla volta e ha un limite suo, `ArrClient.CycleSearchTimeout` = **15 minuti**: una ricerca lunga non deve fermare gli altri titoli.
- `SearchTimeout` (2 minuti) resta per `manualimport`, che non è una ricerca sugli indexer.
- Effetto voluto: un giro con diverse stagioni anime può durare fino a un'ora (10 ricerche in fila). Intanto i tick del timer si saltano e un `Nudge()` aspetta la fine del giro. *(Mia: meglio un giro lungo che ricerche che falliscono a ogni giro; non serve un limite diverso per il giro.)*
- Aggiornare `ArrClientTests.ASlowSearchUsesTheSearchTimeout` (o un test nuovo) per il limite delle release. Il test è già noto come instabile: va rieseguito prima di indagare.

### 4.2 Le ricerche in background ("job")

- Al più **una ricerca dell'admin per chiave** alla volta, in memoria nel `DownloadService`, sotto `_lock`.
- Gira con un token legato alla vita del servizio, **non** a `RequestAborted` (vedi la nota del CLAUDE.md: il lavoro che deve finire non usa `RequestAborted`). Allo spegnimento del plugin si annulla.
- Fa lo stesso lavoro di oggi: `ReadAsync(ServiceOf(kind), c => RunSearchAsync(parsed, c), token)`. Un errore di Radarr/Sonarr dà il DTO con `Error` e le liste vuote, come `SearchAsync` oggi. Un titolo che Radarr/Sonarr non hanno, o una chiave non valida, danno l'esito "Missing" (§4.4).
- Mentre gira, la chiave è "in ricerca" nella panoramica: `Phase = Searching`, come per il giro (oggi `_searching` contiene solo le chiavi del giro).
- Il giro automatico e una ricerca dell'admin sullo stesso titolo restano indipendenti: il caso è raro e non fa danni. *(Mia.)*

### 4.3 Quanto restano i risultati

- Il risultato di una ricerca riuscita resta in `_lastSearch` (come oggi, con `MaxRememberedSearches` = 20) e si mostra all'app per **30 minuti** da `At` *(mia: circa quanto Radarr/Sonarr ricordano le release)*. Dopo, `Status` dice "None" e l'app ne lancia una nuova.
- Anche l'esito con `Error` (Sonarr giù, limite di 60 minuti superato) resta per **30 minuti**, come un risultato: riaprendo la pagina si vede l'errore e la ricerca **non** riparte da sola, così non si consumano gli indexer. Il pulsante "Ricerca di nuovo" della schermata d'errore manda `Again`. L'errore non va in `_lastSearch`, che serve a grab: basta un campo del job. *(Mia; il come è lasciato al builder.)*
- Le chiavi dei job dell'admin stanno in un insieme a parte da `_searching`, così la fine di una ricerca del giro non toglie "Searching" a un job dell'admin (la panoramica guarda tutti e due).

### 4.4 Protocollo

Due endpoint nuovi in `DownloadsController` (solo admin, come gli altri):

- `POST Downloads/SearchStart` con body `{ "Key": "...", "Again": false }`
  - Se c'è già un job in corso per la chiave: non ne lancia un altro e restituisce lo stato.
  - Se c'è un risultato con meno di 30 minuti e `Again` è false: restituisce quello (stato "Done").
  - Altrimenti (o con `Again` true) avvia un job nuovo. `Again` con un job in corso **non** lo riavvia: aggancia quello.
  - 400 per una chiave che non si legge (`DownloadKey.TryParse`).
- `GET Downloads/SearchStatus?key=...` restituisce lo stato senza avviare niente.

Risposta di entrambi, `DownloadSearchStatusDto`:

| Campo | Tipo | Note |
|---|---|---|
| `Key` | string | la chiave normalizzata |
| `State` | string | `Running`, `Done`, `Missing`, `None` (costanti in una classe statica come `DownloadSearchPhases`) |
| `StartedAt` | string ISO, nullable | inizio del job; con `Done`, l'ora della ricerca (`At`) |
| `Service` | string | `Radarr` o `Sonarr`, per il testo dell'app |
| `Result` | `DownloadSearchDto`, nullable | solo con `Done` |

I campi nullable che l'app legge sempre vanno con `[property: JsonIgnore(Condition = JsonIgnoreCondition.Never)]` (nota del CLAUDE.md sulle DTO).

`GET Downloads/Search` (il vecchio) resta per le app 0.27.x: avvia o aggancia il job come `SearchStart` **con `Again` true** e **aspetta** il suo esito. *(Mia: le app vecchie chiamano lo stesso endpoint anche per "Ricerca di nuovo", quindi deve fare una ricerca nuova come oggi; se ce n'è una in corso la aggancia.)* `RequestAborted` annulla solo l'attesa, non il job. Così un'app vecchia che riprova mentre la ricerca è ancora in corso si aggancia a quella e riceve il suo esito quando finisce. Le risposte restano quelle di oggi: 400 per "Missing", il DTO altrimenti.

### 4.5 Funzione in GET Info

Nuova funzione `downloadsSearchJobs`, in `GET Info` insieme a `downloads` (stesse condizioni). L'app la usa per scegliere fra il vecchio e il nuovo modo.

### 4.6 Versione

Plugin **1.19.0**: aggiornare anche la versione in `InfoControllerTests` (nota del CLAUDE.md). Il manifest si aggiorna al rilascio, non qui.

### 4.7 Test del plugin

Almeno: start avvia e restituisce `Running`; un secondo start aggancia lo stesso job (Sonarr chiamato una volta); dopo la fine, start senza `Again` restituisce `Done` con il risultato; `Again` ne lancia uno nuovo; dopo 30 minuti (con il `TimeProvider` finto) lo stato è `None`; chiudere la richiesta del vecchio `Search` non annulla il job; durante il job la panoramica mostra `Searching`; un errore di Sonarr dà `Done` con `Error`, e uno start senza `Again` nei 30 minuti dopo restituisce lo stesso errore senza chiamare Sonarr; il vecchio `Search` con un risultato pronto fa comunque una ricerca nuova; un titolo assente dà `Missing`. `SearchStatus` con una chiave non valida: 400.

## 5. App

### 5.1 API

In `DownloadsApi`: `startSearch(key, {again})` e `searchStatus(key)` → nuovo modello `DownloadSearchStatus` (stato, inizio, servizio, risultato). Nessun `receiveTimeout` lungo: rispondono subito. Gli errori passano da `_call` come gli altri.

### 5.2 Controller

`DownloadSearchController` (stesso provider, stessa pagina, quindi vale anche per "Alleggerisci" da Spazio):

- **Con `downloadsSearchJobs`:** `build()` chiama `startSearch(key)`. Con `Running` chiede `searchStatus` **ogni 3 secondi** *(mia)* finché lo stato non è `Done` (risultato) o `Missing` (errore come il 400 di oggi). `searchAgain()` chiama `startSearch(key, again: true)`.
- Mentre è `Running` la pagina deve conoscere `StartedAt` e il servizio: un provider a parte per la chiave, o uno stato più ricco. *(Lasciato al builder.)*
- Un errore di rete durante il polling **non** chiude la ricerca: si riprova al giro dopo e la pagina lo dice (§5.3). Dopo 3 errori di fila *(mia)* la pagina mostra l'errore con "Riprova", che riprende a chiedere lo stato senza rilanciare la ricerca.
- Smontando il provider (pagina chiusa) il polling si ferma; la ricerca sul server continua.
- Quando la web app torna in primo piano il timer riprende da solo; se Dart è rimasto fermo, alla prima richiesta il risultato è già pronto. *(Nessun codice speciale per iOS, salvo che il builder trovi che serve.)*
- **Senza la funzione** (plugin 1.18.x): tutto come oggi, `GET Downloads/Search`.

### 5.3 Pagina della ricerca

Al posto della rotella con "Cerco su Radarr/Sonarr, può volerci un minuto":

- **barra indeterminata** (`LinearProgressIndicator`) con sotto "Ricerca su Sonarr in corso · 2:15" (servizio vero, minuti:secondi da `StartedAt`, aggiornati ogni secondo);
- una riga in grigio: "Le stagioni anime possono richiedere qualche minuto: puoi chiudere, i risultati restano pronti.";
- durante un errore di rete passeggero, una riga in più: "Connessione persa, riprovo…".

Con il plugin vecchio resta la schermata di oggi.

Testi in `app/l10n` (it ed en), con `flutter gen-l10n`. I widget test con la barra indeterminata non finiscono mai `pumpAndSettle`: vanno pompati a mano (nota del CLAUDE.md).

### 5.4 Test dell'app

Almeno: con la funzione, start → running → done mostra i risultati; il testo con il tempo che scorre; il polling si ferma chiudendo la pagina; un errore di rete passeggero non chiude la ricerca; "Ricerca di nuovo" manda `Again`; senza la funzione si usa ancora `GET Search`.

## 6. Già sul ramo (fuori da questa spec)

Sul ramo `fix/pwa-ios` ci sono già, non ancora committati: niente `connectTimeout` nel browser (`jellyfin_http.dart`), COEP `require-corp` nelle conf nginx (`app/deploy/`), le immagini fallite tolte dalla cache con l'icona "immagine barrata" (`wf_image.dart`).

## 7. Lasciato al builder

- Come tenere i job (classe a parte o dentro `DownloadService.Admin.cs`), purché sotto `_lock` come il resto.
- La forma dello stato nel controller dell'app (§5.2).
- Il nome del provider o del timer per il tempo che scorre.

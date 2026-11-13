# Tappabuchi 720p — design

Data: 2026-11-13. Plugin (Download automatici) e app (tab Download).

## Perché

Anime, serie e film vecchi a volte non esistono in 1080p: la ricerca li scarta tutti e tra gli scartati c'è un 720p
che andrebbe benissimo intanto. Oggi il 720p non è mai proponibile, perché il profilo di qualità non lo ammette
("NotWanted" nei controlli di Prowlarr, o rifiuto di Sonarr/Radarr) e il tappabuchi considera solo il punteggio basso
e il peso basso.

## Obiettivi

- Quando non c'è niente in 1080p, "Serve te" propone il miglior 720p come tappabuchi; l'admin decide se scaricarlo.
- Vale per film, episodi e stagioni intere (pack).
- Dopo il download si continua a cercare il 1080p (come per gli altri tappabuchi).

## Non obiettivi / anti-obiettivi

- Mai un 720p scaricato in automatico dal giro: sarebbe un fallimento anche se "funziona".
- Niente 480p/SD: solo 720p (`Quality.Resolution == 720`).
- Niente "approva tutti" nell'app.
- Una stagione con un pack 720p non cerca l'upgrade per singoli episodi (resta il limite di oggi: l'upgrade di una
  stagione guarda solo i pack).

## Approcci considerati

- **A. Pack 720p prima di dividere (scelto dall'utente).** Una stagione senza nessun 1080p (né pack né singoli) ma con
  un pack 720p completo non si divide: diventa una voce sola in "Serve te". Un clic per la stagione.
- B. Solo episodi: la stagione si divide sempre e ogni episodio propone il suo 720p. Meno codice, ma decine di
  approvazioni e singoli al posto di un pack.
- C. Come B più "Approva tutti" nell'app. Un clic, ma tanti singoli e più lavoro nell'app.

## Design

### Il nuovo tappabuchi
- `DownloadStopgaps.Quality = "Quality"`: il miglior 720p scartato **solo** per la qualità non ammessa dal profilo.
  - Prowlarr: `ReleaseChecks.Check` lo scarta con `NotWanted` + nome qualità. Una release 720p deve però passare tutti
    gli altri controlli (blocklist, termini, dimensioni della definizione 720p, seeders, punteggio minimo del profilo)
    e il peso minimo in GB/h di WonderFlix: un 720p scartato anche per altro non è un tappabuchi.
  - Sonarr/Radarr (motore Arr): il rifiuto è il testo "… is not wanted in profile"; vale solo se è l'unico rifiuto
    reale (oltre agli ignorati di `IgnoredRejectionPrefixes`).
  - Ordine tra i 720p: lo stesso della regola (punteggio, risoluzione, peso, seeders, priorità indexer, guid).
- Precedenza in `ChooseStopgap`: Score → Size → Quality. Un 1080p sotto soglia o leggero batte sempre un 720p.
- `DownloadSummary` guadagna `StopgapKind` (string?, null se non c'è tappabuchi) accanto a `StopgapAvailable`; nel DTO
  con `JsonIgnore(Condition = Never)`.

### Film ed episodi
- Il giro non cambia: senza scelta va in `NeedsYou`/`NothingFound` con il riassunto, che ora dice anche "Quality".
- "Scarica il migliore intanto" (`GrabBest`) prende il 720p. Il push verrebbe rifiutato per qualità: per questo grab il
  rifiuto "not wanted in profile" conta come voluto e il torrent va direttamente in qBittorrent (`AddDirectAsync`,
  `DirectGrabs`), poi si importa per cartella a mano forzando la qualità del file (come il tappabuchi per peso,
  `ForceImport`).
- `entry.Stopgap = "Quality"` dopo il grab.

### Stagioni
- Nel giro, quando `PackCandidates` è vuoto e non è un upgrade: se tra i risultati della **ricerca della stagione**
  non c'è nessuna release di qualità ammessa (né pack né singolo; contano anche quelle sotto il punteggio minimo e le
  `TooSmall`, cioè tutto ciò che non è scartato per qualità o rifiutato da Arr), e c'è un pack 720p completo che
  sarebbe un tappabuchi Quality (stessa regola sopra, sulla durata di tutti gli episodi mancanti), la stagione **non**
  si divide: va in `NeedsYou`/`NothingFound` con il riassunto (`StopgapKind = Quality`).
- Decisione dell'utente: basta la ricerca della stagione, niente ricerche per episodio prima di decidere. Un 1080p
  che esiste solo a episodi singoli e la ricerca stagione non vede resta nascosto dietro la proposta: l'admin può
  rifiutarla e scegliere a mano.
- Se c'è un 1080p qualsiasi (pack o singolo), si divide come oggi; gli episodi senza 1080p propongono poi il loro
  720p come film/episodi. Mia scelta: un episodio diviso non può prendere un pack 720p come tappabuchi (solo
  singoli); se ne trova solo uno resta "Non trovato" e si sceglie a mano.
- `DownloadActions.For`: per una stagione `GrabBest` si offre solo se `Summary.StopgapKind == Quality`
  (gli altri tappabuchi restano solo per film ed episodi).
- `GrabBest` su una stagione sceglie il pack 720p con la stessa regola e lo scarica come sopra.

### Upgrade dopo il tappabuchi
- Una voce con `Stopgap = Quality` continua a cercare come gli altri tappabuchi (non scade con `UpgradeUntil`).
- Si accetta un candidato della regola (qualità ammessa) che Sonarr/Radarr importerebbero (un file fuori profilo vale
  -1 in `WouldImport`) **e** con punteggio ≥ quello del 720p (decisione dell'utente: non si perde l'audio italiano;
  il 720p può restare a lungo). Come per gli altri tappabuchi il punteggio minimo di WonderFlix non conta; all'arrivo del file `StopgapKindOf` ricalcola il tipo (diventa Score/Size se il 1080p è sotto
  soglia, null se è buono).
- `StopgapKindOf` deve sapere anche se la qualità del file è ammessa: se non lo è il tipo resta Quality.

### App
- `DownloadSummary.stopgapKind` (nullable).
- Spiegazione in "Serve te": con `stopgapKind == 'Quality'` un suggerimento suo, es. "Non c'è in 1080p: c'è un 720p
  da prendere intanto." al posto di `downloadsExplainStopgapHint` (che resta per Size/Score). Testi in `app_it.arb`
  e `app_en.arb`.
- Il bottone resta "Scarica il migliore intanto"; vale anche per le righe stagione.

### Versioni e test
- Plugin 1.31.0 (con `InfoControllerTests`), app minor bump con la riga nuova della checklist in `docs/RELEASING.md`.
- Test plugin: scelta del tappabuchi Quality (solo 720p, solo se scartato solo per qualità, precedenza Score/Size),
  stagione che non si divide / che si divide, `DownloadActions` per stagione, grab diretto + import forzato,
  upgrade che accetta il 1080p e ricalcolo di `StopgapKindOf`.
- Test app: testo della spiegazione per `Quality`.

## Da verificare dal vivo

- Che l'import per cartella (`ManualImport`, `importMode: "copy"`, qualità nel payload) accetti un 720p che il profilo
  non ammette. Se Sonarr/Radarr lo rifiutano, il design va rivisto prima di proseguire: è il primo passo del piano.
- Il rifiuto di qualità è "… is not wanted in profile": `IntentionalRejections` confronta prefissi, qui serve un
  "contiene".

## Lasciato al builder

- Dove esattamente riconoscere "scartato solo per qualità" (probabilmente una variante di `ReleaseChecks.Check` che
  salta il controllo di qualità, o un motivo dedicato nel `RuleRejected`).
- Il testo esatto del rifiuto di qualità di Sonarr/Radarr da riconoscere (verificarlo su una risposta vera).
- Il testo finale delle stringhe dell'app.

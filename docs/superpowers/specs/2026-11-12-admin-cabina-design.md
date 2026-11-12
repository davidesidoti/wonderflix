# Amministrazione "Cabina di proiezione": design

Data: 2026-11-12. Riguarda la pagina Amministrazione dell'app Flutter (Windows e web; sulla TV la pagina non c'è, `_tvExcluded` in `app/router.dart`) e la pagina della ricerca manuale dei download.

Le bozze approvate sono in `2026-11-12-admin-cabina-bozze/` accanto a questo file (HTML statico, si aprono nel browser): `cabina-schede.html` e `cabina-ricerca.html` sono il riferimento, `cabina-telefono.html` il layout stretto, `direzioni.html` le tre direzioni da cui è stata scelta la A (la sola parte valida di quel file è l'opzione A). Dove bozza e documento non coincidono vale il documento.

## Intento

L'admin funziona e non gli manca niente: all'utente semplicemente non piace com'è. Oggi la pagina è un titolo "AMMINISTRAZIONE", una striscia del server, una fila di schede di solo testo e contenuti fatti di titoletti a 18 pt, righe di testo e card `#121212` tutte uguali (`admin_widgets.dart`). Sembra un pannello di servizio attaccato a un'app che per il resto ha un'identità forte (Noir & Oro, Bebas Neue).

L'obiettivo è renderla bella da vedere per chi la usa, senza togliere niente di quello che fa. La direzione scelta è "Cabina di proiezione": l'admin come la cabina del proiezionista di un piccolo cinema. Le riproduzioni in corso sono "sale", lo stato delle cose è una spia accesa o spenta, il registro è il programma della serata.

## Obiettivi

- Stessi dati, stesse azioni, stessi permessi di oggi, presentati con una gerarchia visiva chiara.
- Un linguaggio comune a tutte le schede (spia, titoli, righe, tessere), con un solo momento scenografico per scheda al massimo: le sale in Sessioni, la barra dello spazio in Spazio, il righello dei pesi nella ricerca manuale.
- A colpo d'occhio: cosa sta succedendo (chi guarda), cosa chiede attenzione (contatori, spie oro), cosa è rotto (spie rosse).

## Non obiettivi

- Nessuna funzione nuova lato plugin e nessun endpoint nuovo. Se un dato delle bozze non esiste oggi nei DTO, non si inventa: si toglie dal design (vedi "Dati").
- Nessun cambio al resto dell'app (shell, barra in alto, barra in basso, TV).
- Nessun cambio di testi oltre a quelli elencati qui sotto; i testi esistenti in `app/l10n` restano.

## Anti-obiettivi

- Perdere un comportamento esistente: riavvio con le sue fasi, nota "dati non aggiornati", stati di caricamento ed errore con "Riprova", la striscia del server raggiungibile anche con il server che non risponde, il comportamento delle schede del plugin che compaiono e spariscono (`adminTabs`), la permanenza dello stato di riavvio cambiando scheda.
- Un'admin "da template SaaS": card identiche con ombre e gradienti decorativi. Le card restano piatte (`surface` + `border`), lo stile nasce da spia, Bebas e oro.
- Animazioni sparse. L'unica animazione non richiesta dall'utente è la pellicola della ricerca in attesa, ferma quando le animazioni sono disattivate (`core/system/animation_preference.dart`).
- Peggiorare lo stretto (telefono, finestra < 1024 px): ogni pagina deve restare usabile lì.

## Vincoli

- Tema esistente: `WfColors` e `WfText` in `app/lib/app/theme.dart`. Colori: `bg`, `surface`, `surfaceHigh`, `border`, `gold`, `cream`, `creamMuted`, `error`, `online` (verde della spia), `calendarMovie` (oro scuro, fondo della scelta). Font: Bebas Neue (`WfText.display`) per titoli e numeri grandi, Inter per tutto il resto. Nessun colore nuovo tranne le sfumature d'oro della barra dello spazio (vedi Spazio).
- Icone: `lucide_icons_flutter`, come oggi.
- Layout largo/stretto da `FormFactor.of(context).compact` (soglia 1024 px, `ui/form_factor.dart`).
- Le schede si rileggono solo mentre sono in vista (`AdminTabController` e `AdminPoller`, spec J §10). Questo pesa sui contatori, vedi sotto.
- Le regole del repo valgono: test di widget esistenti da aggiornare, `flutter analyze` pulito, niente `dart format` su file interi.

## Linguaggio comune

### La spia

Un pallino di 8–10 px con un alone dello stesso colore. Quattro stati, sempre con lo stesso significato:

| Stato | Colore | Significato |
|---|---|---|
| ok | `online` (verde) | funziona, collegato, completato |
| attenzione | `gold` | in corso, chiede un'azione, riavvio necessario, pochi seeders |
| rotto | `error` | errore, non raggiungibile, non riuscito |
| spento | grigio, senza alone | non configurato, mai eseguito, zero seeders |

La spia non è mai l'unico segnale: accanto c'è sempre un testo (o un tooltip/`Semantics` dove il testo non sta), per chi non distingue i colori e per gli screen reader.

### Titoli, righe, tessere

- Titolo della scheda: Bebas ~30 in cima all'area del contenuto, al posto di "AMMINISTRAZIONE". Accanto, dove serve, le azioni della scheda (es. "Aggiorna", "Ricalcola").
- Titolo di sezione: Bebas ~20, con a fianco il conteggio in Inter piccolo grigio ("In riproduzione 2") e, a destra, l'azione della sezione se c'è ("Scansiona tutte").
- Elenco: righe in un solo contenitore con bordo e separatori, non una card per riga.
- Tessera: card piatta per oggetti da guardare come insieme (utenti, librerie, episodi).
- Oro solo per ciò che chiede attenzione o è l'azione consigliata. L'azione consigliata è un pulsante pieno oro; le altre sono pulsanti col bordo.

### Contatori

Numeri nella colonna delle schede (e nella fila dello stretto), in un pallino oro. Contano solo ciò che chiede attenzione, mai totali. Senza niente da contare, niente pallino.

| Scheda | Conta |
|---|---|
| Sessioni | riproduzioni in corso |
| Manutenzione | attività pianificate in esecuzione |
| Download | elementi "Serve te" |
| WonderFlix | segnalazioni aperte |

Le altre schede non hanno contatore.

**Aggiornamento dei contatori (mia scelta):** il contatore della scheda in vista viene dai dati che la scheda ha già. Per le altre schede si legge lo stesso endpoint della scheda con una rilettura lenta (60 s, come `ServerInfoController`) finché la pagina Amministrazione è aperta. Una lettura che fallisce lascia l'ultimo valore; senza nessun valore, niente pallino. Il meccanismo (provider dedicati, riuso dei controller con un intervallo diverso) è del builder; il vincolo è non rileggere ogni 5 s schede che non si vedono.

## Struttura della pagina

### Largo (≥ 1024 px)

```
+--------------------+------------------------------------------+
| ● WonderFlix       | TITOLO SCHEDA                [azioni]    |
|   Jellyfin 10.11.9 |                                          |
|   su Linux         |  contenuto della scheda                  |
|   [Riavvia]        |                                          |
|--------------------|                                          |
| ▌Sessioni      (2) |                                          |
|  Utenti            |                                          |
|  Manutenzione  (1) |                                          |
|  Attività          |                                          |
|  Download      (3) |                                          |
|  Spazio            |                                          |
|  WonderFlix    (2) |                                          |
+--------------------+------------------------------------------+
```

- Colonna a sinistra, larga circa 200–220 px, fondo `surface`, bordo destro `border`. Non scorre con il contenuto.
- In cima alla colonna il blocco del server (prende il posto della `ServerStrip` di oggi, con tutti i suoi stati): spia (verde se il server risponde, oro con "Riavvio necessario" e il suggerimento sotto se `hasPendingRestart`, rossa con l'errore e "Riprova" se non risponde, scheletro durante il primo caricamento), nome in Bebas, versione e sistema su una riga sotto, `RestartArea` sotto (con le sue fasi: Riavvia, "Riavvio in corso…", "non risponde ancora" + Ricontrolla). La nota "dati non aggiornati" resta.
- Sotto, le voci delle schede: icona + nome + contatore. Quella scelta ha il fondo `surfaceHigh` e una barretta oro di 2 px a sinistra. Icone (mia scelta, lucide): Sessioni `monitorPlay`, Utenti `users`, Manutenzione `wrench`, Attività `scrollText`, Download `download`, Spazio `hardDrive`, WonderFlix `sparkles` (o l'equivalente più vicino disponibile).
- Le schede restano nell'indirizzo (`/admin?tab=…`) e restano quelle di `adminTabs`.
- La tastiera deve poter percorrere la colonna con il focus ben visibile.

### Stretto (< 1024 px)

Vedi `cabina-telefono.html`.

- In cima: il blocco del server su una riga (spia, nome in Bebas, versione sotto, Riavvia a destra; con poco spazio Riavvia va sotto, come oggi).
- Sotto: le schede come una fila che scorre in orizzontale (icona facoltativa, nome, contatore), la scelta con fondo `surfaceHigh` e una barretta oro sotto.
- Come oggi, nello stretto blocco del server e fila scorrono con il contenuto della scheda (`header` passato alle schede), così Riavvia resta raggiungibile anche con una scheda in errore.
- Le griglie (sale, tessere, card) diventano una colonna sola; le tabelle diventano righe a due piani.

## Le schede

### Sessioni

Il momento scenografico della pagina.

- **In riproduzione**: ogni sessione è una "sala". Riquadro alto ~170 px, due per riga nel largo e uno nello stretto. Ha come sfondo il backdrop del titolo (`ImageUrls.backdropOf`; per un episodio quello della serie; senza backdrop la locandina sfocata, o un fondo `surfaceHigh`), con un velo nero che sale dal basso.
  - In alto a sinistra "Sala N" in Bebas oro, numerata nell'ordine dell'elenco (testo nuovo: "Sala {n}").
  - In alto a destra un'etichetta: "Diretta" (crema su velo crema) oppure "Transcodifica" (oro su velo oro), i testi di `displayMethodLabel`. Se c'è un'icona di pausa oggi, resta accanto all'etichetta.
  - In basso: titolo in Bebas ~26 (`nowPlayingTitle`), sotto la riga utente (avatar, nome, dispositivo), sotto la barra a fotogrammi, sotto il tempo e, per le transcodifiche, la riga e i motivi di oggi (`transcodeLine`, `transcodeReasons`).
  - Barra a fotogrammi: 12 segmenti separati da 3 px, pieni in oro fino all'avanzamento (il segmento parziale si arrotonda per difetto). Durata sconosciuta: barra vuota e solo il tempo, come oggi.
- **In sala d'attesa** (oggi "Collegati": cambia il testo di `adminSessionsIdle`): sessioni collegate senza riprodurre, in una riga compatta che va a capo (avatar, nome, dispositivo, "4 min fa").
- **Watch party**: sezione sotto, stile elenco comune, contenuto di oggi.
- Elenco vuoto: il testo di oggi.

### Utenti

- Titolo con il numero di utenti accanto.
- **Recupero password** (oggi è `AccountRecoveryCard` in WonderFlix): una fascia in cima con una spia per canale (Discord, email: verde configurato, spenta non configurato, rossa con l'ultimo errore) e "Invia prova a me" a destra. Il dettaglio di oggi (ultimo errore, promemoria spenti, suggerimento per configurare) resta, sotto la fascia o in un pannello che si apre cliccandola (scelta del builder). **Mia scelta:** la fascia sta in Utenti quando la scheda Utenti c'è (funzione `account`); se c'è WonderFlix ma non Utenti, la card resta in WonderFlix com'è oggi.
- **Utenti** come tessere, due per riga nel largo: avatar ~40 px, nome, etichetta "Admin" (oro) o "Disattivato" (grigia, tessera attenuata), i contatti come due caselline (Discord, email): piene se collegati, tratteggiate se no. Un utente non admin e attivo senza nessun contatto ha "nessun contatto" in oro accanto (testo nuovo), perché non può recuperare la password. Il menu "⋯" con le azioni di oggi (Imposta password, Invia codice di recupero, Associa Discord/email, Scollega contatti) resta uguale.

### Manutenzione

- **Librerie**: tessere in fila (tre per riga nel largo), nome in Bebas, sotto il tipo e "Scansiona". La scansione in corso si vede dentro la tessera (bordo oro tenue, percentuale, barra). "Scansiona tutte" a destra del titolo della sezione. I dati per tessera sono quelli che `LibraryRow` ha oggi: se il tipo non c'è, solo il nome.
- **Attività pianificate**: elenco con la spia a sinistra di ogni riga: oro in corso (con barra e percentuale e "Ferma"), verde completata ("Ultima: …, completata in …"), rossa non riuscita/interrotta (testo in `error`), spenta mai eseguita. "Avvia"/"Ferma" a destra come oggi. Ritmo di rilettura di oggi (15 s, 2 s con un'attività in corso).

### Attività

- In alto a destra il filtro Tutto/Utenti/Sistema come un selettore a segmenti, e "Aggiorna".
- Il registro come il programma della serata: le voci raggruppate per giorno, con un'intestazione Bebas oro ("Oggi", "Ieri", poi la data); ogni voce ha l'ora in Bebas ~19 in una colonna a sinistra, un punto colorato e il testo di oggi. Colore del punto (mia scelta, dal tipo/gravità della voce di Jellyfin): oro per riproduzioni, `error` per voci con gravità di errore o avviso (accessi non riusciti, errori), grigio per il resto.
- Caricamento a pagine, "Apri il titolo" e fine elenco come oggi.

### Download

- In cima la fascia delle ricerche automatiche, con la spia (verde in corsa, oro in pausa o in pausa per una ricerca manuale, rossa con un errore di Sonarr/Radarr), la riga di oggi (quante, fine stimata, ricerche/ora) e "Aggiorna ora".
- **Serve te** per primo: righe con bordo sinistro oro di 3 px, locandina piccola, titolo, motivo, azioni con la prima (consigliata) piena oro. Oggi l'accento di "Serve te" è `error` (`download_rows.dart`): diventa oro, perché chiede un'azione e non è un guasto.
- Le altre sezioni (Scelte automatiche, In attesa, Da ripassare, Senza titolo) restano con contenuto e ordine di oggi, nello stile elenco comune; i download in corso hanno barra oro e la riga di oggi ("62% · …, finisce tra 12 min").
- Filtro, sezioni che si chiudono, rush e tutto il resto: come oggi.

### Spazio

- In alto a destra "Calcolato …" e "Ricalcola".
- **La barra dello spazio** (momento scenografico): l'occupato in Bebas ~34 ("1,62 TB") con accanto "su 2,00 TB, liberi 380 GB" (testi di `spaceQuotaLine`), sotto una barra alta ~22 px divisa per tipo, Film/Serie/Anime/Solo torrent/Altro, in cinque sfumature d'oro dalla più chiara alla più scura (colori nuovi, solo qui; il resto della barra fino al totale è `surfaceHigh`), sotto la legenda con i GB. Senza quota: la ripartizione da sola, con la riga d'errore di oggi.
- Le liste di oggi (Cancellare, Alleggerire, Pulizia, In attesa di fine seed, Tenuti, Ultime operazioni) nello stile elenco comune, con i totali di oggi a fianco del titolo della sezione e l'azione della sezione ("Elimina selezionati (…)") a destra.

### WonderFlix

- **La fila delle spie** in cima: una spia per integrazione, Sonarr, Radarr, Seerr (e, se la fascia del recupero non è andata in Utenti, Discord ed email), con il nome e, se rotta, il motivo breve in rosso. Lo stato viene dalle card di oggi (`ArrCard`, `SeerrCard`, `AccountRecoveryCard`): prima della "Prova collegamento" si sa solo configurato/non configurato (verde/spento), dopo la prova l'esito. Cliccare una spia apre il dettaglio di oggi di quella card (ultimo evento del webhook, "Prova collegamento", ecc.); il modo (pannello che si apre sotto la fila, dialogo) lo sceglie il builder.
- Sotto, le card su due colonne nel largo (una nello stretto), in ordine di urgenza: Segnalazioni (con "N aperte" in oro) per prima, poi Annuncio, Novità (il numero dei titoli in attesa in Bebas), Commenti degli utenti, Home per tutti. Contenuti e azioni di ogni card: come oggi. Le card restano piatte, senza ombre.

## La ricerca manuale

`download_search_page.dart`, pagina a tutto schermo, con le tre aperture di oggi (normale, `reviewing`, `lighten`). Vedi `cabina-ricerca.html`.

- **Testa**: lo sfondo del titolo (velo nero dal basso, ~190 px nel largo, più bassa nello stretto), "← Download" in alto a sinistra, il titolo in Bebas ~44, sotto la riga meta di oggi (durata, risultati validi su totali, risultati da Prowlarr/Sonarr/Radarr). A destra (nello stretto sotto) la "scheda tecnica" del file attuale: peso in Bebas, punteggio e qualità. Senza file: "Nessun file".
  - Immagine (mia scelta): `DownloadSearch` non ha immagini e il titolo spesso non è ancora in Jellyfin. `showDownloadSearch` riceve un'immagine facoltativa dai chiamanti, solo lato app: il backdrop Jellyfin quando il chiamante ha un `itemId` (Spazio), altrimenti la locandina di Sonarr/Radarr (`posterUrl`, passata da `RemoteImages`) sfocata e scurita. Senza immagine, fondo `surfaceHigh`. Nessun campo nuovo nel plugin.
  - GB/ora del file attuale (mia scelta): solo per i film, se la pagina ha i minuti; per le stagioni non si mostra, perché `runtimeMinutes` non dice in modo sicuro la durata della stagione.
- **Azioni** in una riga sotto la testa: Ricerca di nuovo, Cerca con Sonarr/Radarr, Già al minimo (solo `lighten`), Va bene così (solo `reviewing`, pieno oro), Cerca su MIRCrew a destra. Le stesse condizioni di oggi.
- **Pesi a confronto** (momento scenografico, testo nuovo per il titolo e per la spiegazione "ogni tacca è una release; più alta, punteggio più alto"): un righello orizzontale in un riquadro `surface` alto ~96 px. Asse in GB da 0 al peso massimo tra le release valide e il file attuale, con 4–5 etichette. Ogni release valida è una tacca verticale alla posizione del suo peso, alta in proporzione al punteggio (dal minimo al massimo tra le valide, con un'altezza minima perché si veda). La scelta della regola in oro e più larga, con l'etichetta "scelta {peso}"; il file attuale (`current.sizeBytes`, in ogni apertura, è un segno sul righello e non una release) in crema con "attuale {peso}". Niente zona "troppo piccoli": la soglia (`MinGbPerHour`) non arriva all'app. Per le stagioni il righello mostra solo i pack interi (`fullSeason != false`, come `hasLighter`), perché `current.sizeBytes` è la stagione intera e singoli e pack parziali accanto non vorrebbero dire niente; con meno di 2 pack interi validi il righello non c'è. Tacche sovrapposte: si disegnano tutte, la scelta e il file attuale sopra le altre. Cliccare una tacca porta alla sua riga nella tabella (facoltativo, scelta del builder). Con meno di 2 release valide il righello non si mostra. Nello stretto il righello resta, a tutta larghezza, con meno etichette.
- **La scelta della regola**: la release scelta (`isChoice`, non il file attuale) da sola in un riquadro con fondo `calendarMovie` e bordo oro: rango in Bebas oro, nome della release, punteggio, peso e GB/ora, seeders con spia, indexer, il motivo di oggi (`choiceWhy`) in oro e, se c'è un file attuale più pesante, "Libera {gb}" (testo nuovo; per le stagioni solo se la scelta è un pack intero, altrimenti la cifra sarebbe sbagliata). Il GB/ora della scelta segue la regola del file attuale (solo film). "Scarica" pieno oro a destra. La stessa release non si ripete nella tabella sotto.
- **Tutte le release**: la tabella di oggi (rango in Bebas grigio, release, punteggio con una barretta oro proporzionale, peso, seeders con spia, indexer, "Scarica"). Spia dei seeders (mia scelta): spenta a 0 o sconosciuti, oro da 1 a 9, verde da 10 in su. La riga del file attuale è attenuata e al posto di "Scarica" ha "È il file che hai già", con la stessa condizione di oggi (solo con `lighten`; nelle altre aperture quella release resta scaricabile come oggi). Nello stretto, righe a due piani come oggi.
- **Migliori episodi** (stagioni): una griglia di tessere, sette per riga nel largo (meno nello stretto): "E01" in Bebas e sotto il peso del singolo scelto. Tessera con bordo oro tenue se c'è un file valido, tratteggiata e attenuata con "nessun file valido". (Lo stato "già c'è" delle bozze non ha un dato in `DownloadEpisodeChoice`: non c'è.) "Scarica tutti (N)" pieno oro a destra del titolo della sezione, con l'avanzamento di oggi ("Scarico 3/11").
  - Ogni episodio oggi ha la sua riga completa con il suo "Scarica" e le sue conferme, e deve restare (mia scelta): cliccare una tessera la seleziona (bordo oro pieno) e sotto la griglia compare la riga di oggi di quell'episodio (`_CandidateRow` con release, punteggio, peso, seeders, indexer, "Scarica" e conferme), cliccandola di nuovo si chiude. Nello stretto lo stesso. Il filtro della tabella proposto nelle bozze non si fa: `DownloadRelease` non ha i numeri degli episodi.
- **Scartati**: chiusi di default, con un riepilogo per motivo come pastiglie ("9 altro titolo", "8 qualità non voluta", …, dai `rejectedLabel` di oggi) e "Mostra" che apre l'elenco di oggi.
- **In attesa dei risultati** (`_SearchRunning`): riquadro con la spia oro, "Ricerca su {servizio} in corso" e il tempo in Bebas a destra; sotto una pellicola (fila di segmenti) che scorre al posto della barra indeterminata, ferma se le animazioni sono disattivate; sotto il suggerimento di oggi. Gli stati "in attesa della ricerca automatica", "riconnessione" e gli errori con "Riprova" restano, nello stesso riquadro.

## Dati

Tutto quello che il design mostra deve venire da dati che l'app ha già. Le bozze usano valori verosimili, non nuovi campi. Già verificati come presenti: tipo di libreria (`LibraryKind`), gravità delle voci in Attività, `itemId`/serie delle sessioni per il backdrop, ripartizione dello spazio e quota, contatti/admin/disattivato degli utenti, conteggi di "Serve te" e delle segnalazioni. Se il builder scopre che un altro dato manca, lo toglie dal design e lo segnala, invece di aggiungere un campo al plugin.

## Testi nuovi

Da aggiungere in `app_it.arb` e `app_en.arb`: "Sala {n}", "In sala d'attesa" (nuovo valore di `adminSessionsIdle`), "nessun contatto", "Pesi a confronto" e la sua spiegazione, "scelta {gb}", "attuale {gb}", "troppo piccoli" (se non c'è già una chiave adatta), "Libera {gb}", la fila e le etichette dei riepiloghi degli scartati se le chiavi di oggi non bastano. Le etichette delle spie usano i testi di stato già esistenti dove ci sono.

## Lasciato al builder

- Come strutturare i widget (un `AdminRail`, un `WfLamp` condiviso, ecc.), purché spia, titoli ed elenchi siano componenti unici riusati.
- Misure esatte, spaziature e raggi, entro quanto detto qui e nelle bozze.
- Il meccanismo dei contatori, con il vincolo sul ritmo di rilettura.
- Come si apre il dettaglio di una spia in WonderFlix e del recupero password in Utenti.
- L'ordine dei lavori, purché ogni passo lasci l'app funzionante e i test verdi.

## Scelte mie da verificare

Non sono state chieste dall'utente: le ho decise io, vanno confermate leggendo.

Il recupero password in Utenti e i contatori erano nelle bozze approvate dall'utente ("mi piacciono"); le regole di dettaglio qui sotto le ho decise io:

1. Recupero password in Utenti: resta in WonderFlix se Utenti non c'è.
2. Contatori: rilettura a 60 s per le schede non in vista. È la parte che costa di più (provider accanto ai controller `autoDispose`; `DownloadsController` e `adminReportsProvider` non si rileggono da soli).
3. "Serve te" con accento oro al posto di rosso.
4. Rinomina "Collegati" in "In sala d'attesa"; "Sala N" sulle sale.
5. Colori dei punti in Attività e soglie della spia dei seeders (0 / 1–9 / 10+).
6. Migliori episodi: tessera che apre la riga dell'episodio sotto la griglia (al posto del filtro delle bozze); niente stato "già c'è".
7. Icone delle schede nella colonna.
8. Ricerca manuale: immagine della testa passata dai chiamanti (backdrop o locandina sfocata); GB/ora solo per i film; righello delle stagioni solo con i pack interi; "È il file che hai già" solo con `lighten`, come oggi.

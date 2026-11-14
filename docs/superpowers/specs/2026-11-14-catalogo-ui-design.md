# WonderFlix — Film e Serie, nuova UI ("Sala per genere")

Data: 2026-11-14. Bozza della strada scelta: [`2026-11-14-catalogo-bozze/sala.html`](2026-11-14-catalogo-bozze/sala.html); le tre strade confrontate stanno in [`catalogo.html`](2026-11-14-catalogo-bozze/catalogo.html). Locandine, voti, generi, visti ed episodi da vedere sono veri (server, utente davide.sidoti, 14 novembre); le bozze contengono circa 100 film degli 801, i conteggi sono quelli reali. Codice di partenza: `features/catalog/` (spec A per il catalogo, spec K §8.4 per la vista Saghe). Dove questa spec non dice nulla valgono quelle.

## 1. Perché

L'utente vuole pagine Film e Serie più belle da vedere e più comode; l'unico problema che ha notato sono i filtri. Oggi (app 0.41/0.42):

- **Generi e Anni sono vuoti.** `GET /Items/Filters` con Jellyfin 10.11 risponde con liste vuote (verificato sul server il 14 novembre: 0 generi e 0 anni per film e serie). `GET /Items/Filters2` dà i generi (29 film, 30 serie), non gli anni. Lo stesso provider (`catalogFiltersProvider`) alimenta anche il menu dei generi di "Cosa guardo stasera?", che quindi è vuoto anche lui.
- **Generi in due lingue.** Film quasi tutti in italiano (Azione 330, Dramma 212) con doppioni inglesi (Drama 6, Action 5); serie quasi tutte in inglese (Drama 138, Science Fiction 62).
- La pagina è una testata di tre righe (titolo, schede, filtri a menu) sopra un muro di locandine dalla A alla Z, che parte da "2 Fast 2 Furious". Niente ricerca nella pagina, niente verso dell'ordine, titoli tagliati a una riga.
- Saghe ha ricerca e ordine, Film e Serie no; i nomi delle saghe ripetono "- Collezione".
- Le serie non dicono se sono in corso né si possono filtrare così (66 in corso, 122 concluse).

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- Filtri di genere e di decennio che funzionano, con generi in italiano e senza doppioni.
- Il genere scelto è il **cartellone** della pagina: il nome in grande sopra l'immagine del primo titolo della lista. È l'unico elemento vistoso.
- I generi sono un **indice sempre in vista** (nomi con il conteggio), non un menu.
- Ricerca dentro la pagina, ordine con verso, "Nascondi i visti", titoli su due righe.
- Serie: stato (in corso / conclusa) ed episodi da vedere sulla card, filtro In corso / Concluse.
- Saghe: card con tre locandine e i film visti, nomi senza "- Collezione".
- Telefono e TV con lo stesso disegno, adattato.

**Non obiettivi**
- La mia lista non cambia (usa ancora `CatalogFiltersBar`, che resta com'è).
- La scheda del titolo, la Home, Cerca, la pagina di una persona e la pagina di una saga non cambiano: le card nuove (§8, §9) sono una variante usata solo da Film, Serie e Saghe; `PosterCard` e `CollectionCard` restano come sono per gli altri. Anche i nomi ripuliti delle saghe valgono solo nella card nuova (decisione mia).
- Niente filtro per più generi insieme; niente colonna A–Z (era la strada A).
- Al plugin una sola riga (§6.2, la stanza del Match); nient'altro.

**Anti-obiettivi**
- Lo stile non cambia: Noir & Oro, Bebas Neue per i titoli, Inter per il resto. Nessun colore nuovo; l'oro solo per lo stato attivo e i segni di avanzamento.
- La pagina non deve aprirsi più lenta di oggi: il cartellone non aspetta conteggi né letture in più per comparire.
- Fuori dalla TV il comportamento TV non deve cambiare, e viceversa (regola di `FormFactor.tv`).

## 3. Strade considerate

| Strada | Idea | Scelta |
|---|---|---|
| A. Schedario | griglia a blocchi con una grande lettera (o decennio, fascia di voto) ferma a sinistra e una colonna A–Z | scartata dall'utente |
| B. Scaffali | file orizzontali (arrivati da poco, da vedere, generi) e poi la griglia | scartata: troppo simile alla Home |
| **C. Sala per genere** | il genere scelto diventa un cartellone con il suo titolo di punta; sotto, l'indice dei generi e la griglia | **scelta dall'utente** |

## 4. La pagina

Dall'alto (bozza `sala.html`):

1. **Cartellone** (§5), alto 320 px su desktop, che parte da sotto la barra di navigazione e ci passa sotto con la sfumatura che la barra ha già sulla Home. In alto a sinistra le schede **FILM  SAGHE** (Bebas 30, attiva in crema, l'altra al 32% di opacità); in basso il nome del genere e una riga di testo. Serie non ha schede: solo "SERIE".
2. **Barra dei generi e degli attrezzi**, che quando il cartellone esce dallo schermo resta ferma in cima (sotto la barra di navigazione), così si cambia genere senza risalire:
   - riga dei generi (§6);
   - riga degli attrezzi: Ordina (menu) e verso (pulsante freccia), Decennio (menu), per le serie Tutte / In corso / Concluse, "Nascondi i visti" (interruttore), e a destra il campo "Cerca tra i film" / "Cerca tra le serie".
3. **Griglia** delle locandine come oggi (`SliverGridDelegateWithMaxCrossAxisExtent`, caricamento a pagine da 100, entrata a gruppi), con le card del §8.

Il genere scelto sta nell'indirizzo (`/movies?genre=Fantascienza`, `/series?genre=Dramma`; con `view=sagas` per le saghe), come oggi la vista: Indietro dalla scheda di un titolo torna allo stesso genere. Ordine, decennio, ricerca e "Nascondi i visti" invece si azzerano lasciando la pagina, come oggi i filtri.

Aprendo la pagina senza genere si vede **Tutti**: cartellone "TUTTI I FILM" / "TUTTE LE SERIE", ordine per data di aggiunta.

## 5. Il cartellone

- **Immagine:** il fondale (`Backdrop`) del **primo titolo della lista mostrata che ne ha uno**, qualunque sia l'ordine. Con "Tutti" e l'ordine di default è l'ultimo arrivato; con un genere e l'ordine per voto è il più votato del genere. Una sola regola, nessuna lettura in più: il titolo è già nella prima pagina. Se nessuno dei primi 100 ha un fondale, il cartellone è solo nero con la sfumatura.
- **Sfumatura:** da sinistra (nero pieno → trasparente al 75%) e dal basso (nero → trasparente a metà), come nella bozza, perché il testo resti leggibile su qualsiasi immagine.
- **Titolo:** il nome del genere in Bebas 112 px (desktop), crema. "Tutti i film" / "Tutte le serie" con Tutti.
- **Riga sotto il titolo:** "**243 film**, 211 già visti. I più votati per primi." Il primo pezzo è il conteggio del genere (o il totale), il secondo i visti, il terzo descrive l'ordine scelto ("Gli ultimi arrivati per primi", "Dalla A alla Z", "Dal più recente", "I più votati per primi"; col verso invertito la frase opposta). Per le serie: "**138 serie**, 41 in corso." Conteggi e visti possono arrivare dopo l'immagine: finché non ci sono, la riga mostra solo la frase dell'ordine. Sono sempre quelli del **genere intero**, non della griglia filtrata: decennio, stato, "Nascondi i visti" e ricerca non li cambiano (così si leggono una volta per sessione).
- Cambiando genere o ordine immagine e testo sfumano nei nuovi (`WfSwitcher`, già usato per la griglia). Con il movimento ridotto del sistema, cambio secco.
- L'immagine è decorativa: non si clicca e per i lettori di schermo conta solo il testo.

## 6. I generi

### 6.1 Da dove vengono
- Nomi: `GET /Items/Filters2?userId&includeItemTypes=Movie|Series&recursive=true` (campo `Genres`, oggetti con `Name`). `LibraryApi.filters` passa a questo endpoint.
- Anni: `Filters2` non li dà, e non servono: i decenni sono un elenco fisso (§7), e il filtro passa `years=2010,2011,…,2019` ("Prima": dal 1900 al 1989). Un decennio senza titoli dà la griglia vuota con "Azzera filtri" (decisione presa scrivendo il piano: niente lettura in più all'apertura).
- Il fix vale anche per "Cosa guardo stasera?" (`tonightGenresProvider`), che legge lo stesso provider.

### 6.2 Un genere solo per nome
Una tabella nell'app porta i nomi inglesi a quelli italiani già usati dai film: Drama→Dramma, Action→Azione, Adventure→Avventura, Science Fiction e Sci-Fi→Fantascienza, Comedy→Commedia, Mystery→Mistero, Animation→Animazione, Documentary→Documentario, History→Storia, War→Guerra, Family→Famiglia, Sport e Sports→Sport, Suspense→Thriller, Mini-Series→Miniserie, Music→Musica, Supernatural→Soprannaturale. I nomi non in tabella restano come sono.

Un genere dell'app è quindi un'etichetta con uno o più nomi del server: la griglia filtra con `genres=Drama|Dramma` (Jellyfin unisce con `|`), e così i conteggi. "Cosa guardo stasera?" usa le stesse etichette.

**Stanza del Match.** Usa gli stessi filtri di "Cosa guardo stasera?" (`TonightFiltersBar`) e manda il genere al plugin come stringa unica; il plugin oggi fa `query.Genres = [genre]` (`Server/JellyfinMatchLibrary.cs`). L'app manda i nomi del server uniti con `|` ("Drama|Dramma") e il plugin li divide (`genre.Split('|')`). Il plugin 1.31.0 non è ancora uscito: la riga va in quella versione, senza cambio di numero (decisione mia: le altre strade facevano perdere le serie con i generi inglesi, o davano al Match un elenco di generi diverso da Stasera). Un genere salvato con il nome inglese (`tonight.genre` = "Drama") si legge come la sua etichetta ("Dramma"), non si scarta.

### 6.3 La riga
- In ordine di conteggio, dal più grande: "Tutti 801", "Azione 330", "Avventura 283"… Il numero è piccolo e in alto a destra del nome, al 32% di opacità (oro sul genere scelto). Il genere scelto è oro con una linea sotto, come le schede di oggi.
- Si mostrano i generi con **almeno 5 titoli**; gli altri ("televisione film" 4, "Psychological" 1, …) non compaiono.
- Scorre di lato se non entra, con una sfumatura sul bordo destro che dice che continua.
- I conteggi richiedono una lettura per genere (`limit=0`, `enableTotalRecordCount`), circa 20 per tipo, in parallelo, tenute per la sessione e rilette quando cambia la libreria (`libraryRevisionProvider`). Finché non ci sono, la riga mostra solo "Tutti" (la soglia dei 5 titoli ha bisogno dei conteggi; decisione presa scrivendo il piano). Se `GET /Genres` con i conteggi si rivela affidabile su 10.11 (da verificare), meglio una lettura sola.

## 7. Attrezzi

- **Ordina:** Aggiunti (per le serie "Nuovi episodi", stessa chiave di oggi `DateLastContentAdded`), Titolo, Anno, Voto. Default: **Aggiunti con Tutti, Voto con un genere**; scegliendo un genere l'ordine torna al default del genere, poi l'utente può cambiarlo.
- **Verso:** pulsante freccia accanto al menu; inverte l'ordine (`sortOrder` Ascending/Descending sulla prima chiave, la seconda resta `SortName` crescente).
- **Decennio:** Tutti, 2020, 2010, 2000, 1990, Prima (elenco fisso; "Prima" unisce quelli prima del 1990: oggi 30 film).
- **Serie:** pulsanti Tutte / In corso 66 / Concluse 122 (`seriesStatus=Continuing|Ended`).
- **Nascondi i visti** (per le serie "Nascondi le viste"): interruttore, `isPlayed=false`. Sostituisce Tutti / Non visti / Visti: "solo i visti" sparisce (decisione mia: serve poco, e La mia lista lo tiene).
- **Cerca:** campo nella riga degli attrezzi, filtra la griglia mentre si scrive (`searchTerm`, con un'attesa di 300 ms tra un tasto e l'altro), dentro il genere e i filtri scelti.
- **Azzera filtri** compare in fondo alla riga solo se c'è un filtro diverso dal default (decennio, stato, nascondi, ricerca); il genere si toglie con "Tutti".

## 8. Card

- Locandina 2:3 come oggi (`PosterCard`), titolo su **due righe** prima dei puntini.
- Film: seconda riga "2014  ★ 8.5" (anno e voto della comunità, se c'è). Visto: il segno oro di oggi, e la locandina un po' spenta (saturazione 55%, luminosità 80%) che si riaccende al passaggio del mouse o al focus.
- Serie: seconda riga "In corso" in oro, oppure gli anni di inizio e fine, "2008–2013" (`ProductionYear` ed `EndDate`, da chiedere nei `fields`; senza `EndDate` solo l'inizio; nella bozza c'è "2022, conclusa" perché non ha la data di fine); terza riga "5 episodi da vedere" o "Vista tutta". Il numero oro sulla locandina sparisce (lo dice la riga); resta il segno di vista tutta. La barra di avanzamento resta.

## 9. Saghe

- Stessa pagina: cartellone "SAGHE" con il fondale del primo film della saga più recente, riga "100 saghe, 23 finite."; niente riga dei generi; attrezzi: Ordina (Nome, Aggiunte di recente, Più film), "Nascondi le saghe finite", Cerca.
- Card: tre locandine dei primi film della saga a ventaglio (quella centrale più alta), nome della saga senza i suffissi " - Collezione", " Collection", " - Collection", "Collezione" a fine nome; sotto "4 film, 3 visti" e una barra con un tratto per film, oro se visto.
- I film e i visti vengono da `CollectionSummary.itemIds` più **una** lettura `GET /Items?ids=…` (tutti gli id delle saghe, campi minimi, con i dati dell'utente), tenuta come `collectionsProvider`. Le immagini con `Items/{id}/Images/Primary`.

## 10. Telefono e finestre strette (`FormFactor.compact`)

- Cartellone alto 220 px, nome del genere 64 px, schede 26 px.
- Riga dei generi uguale (scorre).
- Attrezzi su una riga: Ordina, verso, Decennio, un'icona occhio per "Nascondi i visti" (con il nome nel tooltip e per i lettori di schermo) e un'icona lente che apre il campo di ricerca al posto della riga.
- Serie: In corso / Concluse vanno nel menu Decennio, che diventa "Filtri" (decisione mia: su 390 px non entra un'altra riga).
- Griglia a 3 colonne su 390 px, come oggi.

## 11. TV (`FormFactor.tv`)

La griglia deve avere quasi tutto lo schermo (richiesta dell'utente): lo schermo è 960×540 e oggi le schede e i filtri della TV stanno apposta su una riga sola.

- Cartellone alto **160 px** (nome del genere 64 px, riga di testo sotto), senza ricerca (la TV ha Cerca nella barra laterale). Generi e attrezzi su due righe compatte: all'apertura si vede già la prima fila di locandine intera.
- Sulla TV la barra dei generi e degli attrezzi **non resta ferma**: quando il focus entra nella griglia, cartellone e barra escono dallo schermo e la griglia lo occupa tutto (due file e mezza di locandine). Su dalla prima fila riporta il focus agli attrezzi e la pagina torna in cima.
- Il focus parte dal genere scelto nella riga dei generi; giù si va agli attrezzi, poi alla griglia. Le schede FILM / SAGHE sono raggiungibili da su dalla riga dei generi.
- Sinistra dal primo genere va alla barra laterale come oggi (`tv_sidebar.dart`).
- I menu (Ordina, Decennio) restano `DropdownButton` dentro `TvFocusBorder` come oggi.

## 12. Stati

- **Caricamento:** cartellone nero con la sfumatura e il titolo già scritto (il nome del genere lo sappiamo subito), griglia a scheletro come oggi.
- **Nessun titolo:** "Nessun film di questo genere con questi filtri." (o "Nessun film con questi filtri." con Tutti) e il pulsante "Azzera filtri"; il cartellone resta, nero.
- **Errore:** come oggi (`ErrorView` con Riprova).
- **Generi non letti:** la riga mostra solo "Tutti" e la pagina funziona; si riprova alla prossima apertura.

## 13. Lasciato a chi costruisce

- Struttura dei widget e dei provider; se il cartellone e la barra ferma si fanno con `SliverAppBar`/`SliverPersistentHeader` o altro.
- Come normalizzare i nomi dei generi (tabella in `core/jellyfin/` o nel catalogo), purché "Cosa guardo stasera?" usi la stessa.
- `GET /Genres` con conteggi o una lettura per genere (§6).
- Misure fini (spazi, dimensioni al pixel) partendo dalla bozza.
- Test: widget test per cartellone (immagine dal primo titolo con fondale, frase dell'ordine), riga dei generi (soglia 5, ordine, etichette unite), filtri che arrivano alla query (`genres` con `|`, `years`, `seriesStatus`, `isPlayed`, verso), saghe (nome ripulito, tratti dei visti), TV (giro del focus). Test di `LibraryApi.filters` sul nuovo endpoint.

## 14. Release

Esce con l'app **0.42.0** e il plugin **1.31.0** se non sono ancora pubblicati (oggi non lo sono, insieme a Richieste), con una riga nuova nella checklist di `docs/RELEASING.md`; altrimenti con le versioni successive (e allora il plugin cambia numero, con `InfoControllerTests`). Il plugin ha un test per il genere diviso su `|`.

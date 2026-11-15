# WonderFlix — La mia lista, nuova UI

Data: 2026-11-15. Bozza: [`2026-11-15-mia-lista-bozze/lista.html`](2026-11-15-mia-lista-bozze/lista.html).

I dati della bozza sono veri: sono gli 8 preferiti di davide.sidoti al 15 novembre, con locandine, voti, generi, visti ed episodi. La "lista lunga" (42 titoli) è ipotetica: aggiunge altri titoli del server, e alcuni "iniziati" sono inventati.

Codice di partenza:
- `features/mylist/`;
- i pezzi della sala per genere (spec [`2026-11-14-catalogo-ui-design.md`](2026-11-14-catalogo-ui-design.md)): `CatalogBand`, `CatalogGenreIndex`, `PosterCard(catalogStyle: true)`, `catalogCellExtent`, `genreLabel`.

Dove questa spec non dice nulla vale la spec del catalogo.

## 1. Perché

L'utente ha chiesto come migliorare la UI/UX di La mia lista. Oggi (app 0.42):

- **Una lista che non aiuta a scegliere.** È una griglia dalla data di arrivo sul server, con lo stesso peso per un film a metà, uno mai iniziato e uno già visto. VisionQuest, iniziata e a un episodio dalla fine, sta in mezzo agli altri sette titoli.
- **Attrezzi troppi e vecchi.** La barra è la vecchia `CatalogFiltersBar` (Ordina, Genere, Anno, Tutti/Non visti/Visti), con quattro controlli per 8 titoli. I generi del menu sono quelli grezzi dei preferiti, in due lingue ("Drama" e "Dramma"). Non si separano film e serie.
- **"Data di aggiunta" mente.** Usa `dateCreated`, cioè quando il titolo è arrivato sul server, non quando è entrato nella lista: Jellyfin salva il preferito come sì/no, senza data.
- **Stile rimasto indietro.** Le card sono quelle vecchie (`PosterCard` senza `catalogStyle`). La griglia ha `childAspectRatio: 0.55` fisso e 32 px di margine su ogni schermo. Titolo e conteggio sono su una riga, come il catalogo prima della sala.
- **Due icone per la stessa cosa.** La voce della barra è un segnalibro (`LucideIcons.bookmark`); il pulsante che aggiunge, nella scheda e nell'anteprima, è un cuore. Il testo della lista vuota parla del cuore.
- **Lista vuota muta.** Mostra una riga di testo e non porta da nessuna parte.

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- All'apertura si vede subito **cosa guardare adesso**: il cartellone propone il prossimo titolo, con Riproduci/Riprendi a un clic.
- La lista si divide in **Da continuare**, **Da iniziare** e **Visti**.
- Le schede **Tutti / Film / Serie**.
- Attrezzi che crescono con la lista: con pochi titoli solo Ordina; con tanti anche i generi e la ricerca.
- Togliere un titolo, o tutti i visti, in un gesto, con Annulla.
- "Aggiunti alla lista" che ordina davvero per data di aggiunta alla lista.
- Lo stesso linguaggio della sala per genere: cartellone, card, margini.
- Un'icona sola, il cuore.

**Non obiettivi**
- La riga "La mia lista" della Home non cambia.
- La scheda del titolo e l'anteprima non cambiano, a parte la data salvata (§10).
- Nessun cambio al plugin.
- Niente liste multiple, cartelle o ordine a mano (Jellyfin non ha liste: c'è solo il preferito).

**Anti-obiettivi**
- Lo stile non cambia: Noir & Oro, Bebas Neue e Inter, nessun colore nuovo.
- La pagina non deve aprirsi più lenta di oggi. La lista arriva con una richiesta sola, come oggi; cartellone, gruppi e card compaiono con quella. Il prossimo episodio e le date (§10) possono arrivare dopo.
- Fuori dalla TV il comportamento TV non cambia, e viceversa (`FormFactor.tv`).

## 3. Strade considerate

| Strada | Idea | Scelta |
|---|---|---|
| A. La sala per genere | la pagina Film con il filtro preferiti: cartellone del genere, indice dei generi, attrezzi, griglia | scartata: con 8 titoli generi e attrezzi sono rumore, e non separa l'iniziato dal visto |
| B. Scaffali | una fila orizzontale per film e una per serie, come la Home | scartata: è la Home ripetuta e nasconde i titoli fuori schermo |
| **C. Gruppi per stato** | cartellone col prossimo titolo; sotto Da continuare, Da iniziare e Visti | **proposta nella bozza**, l'utente ha chiesto la spec dopo averla vista |

## 4. La pagina

Dall'alto (bozza, sezione "La tua lista di oggi"):

1. **Cartellone** (§5): `CatalogBand` alto come nel catalogo, con le schede TUTTI FILM SERIE in alto a sinistra.
2. **Attrezzi** (§7): una riga con Ordina e verso; con più di 24 titoli, sopra, la riga dei generi e il campo di ricerca. A differenza del catalogo **non restano fermi in cima**: con pochi titoli la pagina è corta, e i gruppi hanno già i loro titoli.
3. **Gruppi** (§6), in quest'ordine: Da continuare, Da iniziare, Visti. Un gruppo vuoto non compare.

La scheda scelta sta nell'indirizzo (`/mylist?kind=movies`, `/mylist?kind=series`), come la vista del catalogo: Indietro dalla scheda di un titolo torna alla stessa scheda. Ordine, genere, ricerca e Visti aperto si azzerano lasciando la pagina, come oggi i filtri.

I margini sono quelli del catalogo: 32 su desktop, 16 sulle finestre strette, 24 in TV.

## 5. Il cartellone

- **Titolo:** "LA MIA LISTA", Bebas 112 su desktop (le misure di `CatalogBand`).
- **Schede:** TUTTI FILM SERIE, come FILM SAGHE nel catalogo (attiva in crema, le altre al 32%).
- **Il titolo di punta.** Nella scheda scelta e nell'ordine scelto, è il primo **da continuare**; se non ce n'è uno, il primo **da iniziare**. Se la lista ha solo visti, non c'è un titolo di punta.
- **Immagine:** il fondale del titolo di punta, se no il fondale del primo titolo della lista mostrata, se no nero. Sfumature come nel catalogo.
- **Riga sotto il titolo:** "**8 titoli**: 1 da continuare, 4 da iniziare, 3 visti." I pezzi a zero non compaiono. L'unità segue la scheda ("titoli", "film", "serie"), al singolare con un titolo ("1 titolo", "1 visto"). I conteggi sono della scheda intera: genere e ricerca non li cambiano.
- **Pulsante oro, con la frase accanto:**
  - film iniziato: "Riprendi", e "Da dove eri rimasto: **Parasite**, ne restano 66 min";
  - film da iniziare: "Riproduci", e "Il prossimo: **Parasite**";
  - serie: "Riprendi S1 E8" se quell'episodio è iniziato, altrimenti "Riproduci S1 E8". Accanto: "Da dove eri rimasto: **VisionQuest**, S1 E8, l'ultimo episodio" ("l'ultimo episodio" solo se ne manca uno).

  L'episodio viene da `findNextEpisode` (`seriesNextEpisodeProvider`). Finché non arriva, il pulsante dice solo "Riproduci", senza S/E, e apre la scheda della serie.
- Il pulsante avvia la riproduzione come "Riproduci" nella scheda del titolo, con lo stesso punto di ripresa. Il titolo di punta si apre anche cliccando il nome nella frase.
- Il titolo di punta **non si ripete** nei gruppi sotto.

## 6. I gruppi

### 6.1 Chi va dove
Con i dati utente che la lista ha già (`UserItemData`, con le modifiche della sessione da `userDataOverridesProvider`):

| | Visti | Da continuare | Da iniziare |
|---|---|---|---|
| Film | `played` | `playbackPositionTicks > 0` | gli altri |
| Serie | `unplayedItemCount == 0` | ha episodi visti (`playedPercentage > 0`) e altri da vedere | nessun episodio visto |

Una serie in corso vista tutta sta in Visti. Quando esce un episodio nuovo torna in Da continuare, con la riga "Nuovo episodio" (§8.2).

Due cose da sistemare perché la tabella funzioni:
- **`RecursiveItemCount` nei `fields`.** Jellyfin dà `PlayedPercentage` di una serie solo se si chiede `RecursiveItemCount` (vedi `randomUnplayed` in `library_api.dart`), e oggi `favoritesProvider` non lo chiede. Va aggiunto alla richiesta della lista, insieme a `DateLastMediaAdded` (§8.2), `Status` ed `EndDate` (le card del catalogo). Serve anche per la barra degli episodi visti sul totale.
- **La risposta di `toggleFavorite`.** `_toggle` sostituisce i dati utente con quelli che rimanda il server, che per una serie possono arrivare senza `PlayedPercentage`. Allora, dopo un Annulla, una serie iniziata finirebbe in Da iniziare. Chi costruisce lo verifica; se è così, l'app tiene i campi di avanzamento di prima quando la risposta non li ha.

### 6.2 Ordine
L'ordine scelto (§7) vale dentro ogni gruppo. I gruppi restano nell'ordine fisso del §4.

### 6.3 Aspetto
- Ogni gruppo ha un titolo (Inter semibold, crema) con il conteggio accanto, al 50% di opacità.
- **Da continuare:** fila di card larghe 16:9 (§8.2). Va a capo su desktop, ed è una colonna su telefono.
- **Da iniziare:** griglia delle card del catalogo (§8.1), con le stesse colonne e la stessa altezza (`catalogCellExtent`).
- **Visti:** parte **chiuso**. La testata ha:
  - una freccia, il titolo e il conteggio, che insieme aprono e chiudono il gruppo;
  - le prime 6 locandine in piccolo (decorative);
  - il pulsante "Togli i visti dalla lista" (§9).

  Aperto, il gruppo mostra la stessa griglia di Da iniziare.

## 7. Attrezzi

- **Ordina** (menu): Aggiunti alla lista (default, §10), Titolo, Anno, Voto. Accanto il pulsante del verso, come nel catalogo. Cambiando voce, il verso torna al default (decrescente, ma A→Z per Titolo).
- **Con più di 24 titoli nella lista** (tutte le schede insieme) compaiono anche:
  - **la riga dei generi**: `CatalogGenreIndex`, con "Tutti" e i generi dei titoli della scheda. I nomi passano per `genreLabel`, quindi Drama e Dramma diventano un genere solo. Sono ordinati per conteggio, senza soglia minima. I conteggi si calcolano nell'app, sulla lista già caricata. Cambiando scheda il genere si azzera;
  - **il campo "Cerca nella lista"** a destra di Ordina: filtra mentre si scrive, sul nome, senza distinguere maiuscole e minuscole.

  Con 24 titoli o meno, generi e ricerca non servono e non compaiono.
- Il filtro Anno e Tutti/Non visti/Visti spariscono: li sostituiscono i gruppi.
- Genere e ricerca filtrano tutti i gruppi. Il titolo di punta resta quello della scheda intera.
- Se genere e ricerca non lasciano nulla: "Nessun titolo della lista con questi filtri." e il pulsante "Azzera filtri".

`buildMyListView` resta il posto dove si filtra e si ordina. Cambia così:
- dà i gruppi e il titolo di punta;
- conta i generi con `genreLabel`;
- non usa più `ItemQuery.year` né `watched`.

## 8. Card

### 8.1 Da iniziare e Visti
`PosterCard(catalogStyle: true)`, come in Film e Serie: titolo su due righe, per i film anno e voto, per le serie stato ed episodi da vedere, locandina spenta se visto.

### 8.2 Da continuare
`LandscapeCard`, la card 16:9 di "Continua a guardare", con il fondale del titolo e la barra d'oro. Titolo e riga restano sotto l'immagine, come nella Home, e non sopra come nella bozza (decisione mia: una card sola per le due pagine). `LandscapeCard` oggi non ha il pulsante play, il posto per il cuore né una larghezza che si adatta: servono parametri nuovi o un involucro (§16).
- film: barra sul punto di ripresa; riga "Riprendi da 52 min, ne restano 66";
- serie: barra sugli episodi visti sul totale; riga "S2 E3, 5 episodi da vedere" ("S1 E8, l'ultimo" se ne manca uno). Il prossimo episodio arriva dopo la lista: finché non c'è, la riga dice solo "5 episodi da vedere". Meglio una lettura `/Shows/NextUp` per tutte le serie che una per card.
- **Nuovo episodio.** Davanti alla riga, in oro, "Nuovo episodio," se l'ultimo episodio è arrivato negli ultimi 7 giorni. La data è `DateLastMediaAdded` della serie, da chiedere nei `fields` e da aggiungere a `JellyfinItem`.
- Un clic apre la scheda del titolo, come le altre card. Il pulsante play sulla card avvia la riproduzione da dove eri. Per una serie vale la regola del cartellone (§5): finché il prossimo episodio non è arrivato, il play apre la scheda della serie.

## 9. Togliere dalla lista

- **Il cuore sulla card** (desktop, card del §8): al passaggio del mouse o col focus compare in alto a destra un cuore pieno, con il tooltip "Togli dalla lista". Un clic toglie il titolo con `userDataOverrides.toggleFavorite`, e il titolo sparisce subito come oggi.
- Sul telefono il cuore sulla card non c'è: si toglie dall'anteprima (pressione lunga) o dalla scheda, come oggi.
- **Avviso con Annulla.** Togliere un titolo dalla pagina mostra "Tolto dalla lista: Parasite" con **Annulla** per 5 s (una `SnackBar` con azione, come `features/home/resume_removal.dart`). Annulla rimette il cuore e la data di aggiunta di prima (§10).

  Vale solo per i titoli tolti da questa pagina (decisione mia). Nell'anteprima e nella scheda il cuore resta lì sotto il dito, quindi per rimettere il titolo basta toccarlo di nuovo.
- **"Togli i visti dalla lista"**, nella testata di Visti: toglie in un colpo tutti i visti della scheda mostrata (e del genere, se scelto). L'avviso dice "Tolti dalla lista 3 titoli visti", con Annulla. Fuori dalla TV non chiede conferma, perché c'è Annulla.

  Sulla TV l'Annulla di una `SnackBar` non si raggiunge col telecomando in 5 s. Lì il pulsante chiede prima conferma ("Togliere 3 titoli visti dalla lista?", Togli / Annulla, focus su Annulla). Decisione mia: un errore col telecomando svuoterebbe Visti senza ritorno.

  **Decisione mia:** il pulsante lascia le serie in corso viste tutte. Tornano in Da continuare quando esce un episodio, e toglierle farebbe perdere l'avviso "Nuovo episodio". Se in Visti ci sono solo quelle, il pulsante non compare.
- Una richiesta al server per titolo, in parallelo. Se una fallisce, quel titolo torna nella lista e l'avviso lo dice ("Non sono riuscito a togliere 1 titolo").

## 10. "Aggiunti alla lista": la data

Jellyfin non salva quando un titolo diventa preferito. L'app la salva per conto suo nei `CustomPrefs` della DisplayPreferences `wonderflix-home`, come già fa per `homeHidden` e `nextUpHidden` (`DisplayPreferencesApi._update`). **Decisione mia**, perché "Aggiunti alla lista" è l'ordine di default e oggi ordina per un'altra cosa.

- Chiave `myListAdded`: una mappa JSON da id del titolo a data e ora UTC (ISO 8601).
- Si scrive in `UserDataOverrides.toggleFavorite`, il punto da cui passano il cuore della scheda (anche in TV), quello dell'anteprima e quello di questa pagina. Si aggiunge la voce quando il cuore si accende e si toglie quando si spegne.
- Annulla (§9) non deve rimettere l'ora attuale. Serve una strada che riaccende il cuore con la data di prima, per esempio un parametro della data in `toggleFavorite` o un metodo apposta.
- `DisplayPreferencesApi._update` rilegge e riscrive tutto l'oggetto, quindi due scritture insieme si cancellano a vicenda. Questo vale anche tra `myListAdded`, `homeHidden` e `nextUpHidden`. Le scritture di `myListAdded` vanno quindi in fila, una alla volta. "Togli i visti" e il suo Annulla fanno **una** scrittura per tutti i titoli.
- Se la scrittura fallisce il cuore resta: la data manca e basta.
- Nell'ordinamento prima vengono i titoli con la data, dal più recente. Poi quelli senza: aggiunti prima di questa versione o da un altro client, ordinati per `dateCreated` come oggi. All'inizio quindi l'ordine è quello di oggi, e cambia man mano che si aggiungono titoli.
- Le voci di titoli che non sono più preferiti (tolti da un altro client) si puliscono alla prima scrittura successiva.
- La data si legge insieme alla lista, in parallelo. Se non arriva, l'ordine è quello per `dateCreated`.

## 11. Lista vuota

- Cartellone nero, senza schede né attrezzi, con "LA MIA LISTA".
- Sotto: "Qui trovi i film e le serie che salvi con il cuore, nella scheda del titolo o nell'anteprima."
- I pulsanti "Vai ai film" (oro, apre `/movies`) e "Vai alle serie" (bordato, apre `/series`).
- Su TV il focus parte da "Vai ai film".
- Questa lista vuota vale anche per una scheda vuota (Film senza film): "Nessun film nella lista." con il solo pulsante della sua pagina.

## 12. Telefono e finestre strette (`FormFactor.compact`)

- Cartellone come nel catalogo compatto (220 px, titolo 64), con il pulsante oro e la frase sotto, su due righe se serve.
- Attrezzi: Ordina senza la parola "Ordina", più il verso. Oltre i 24 titoli c'è la riga dei generi ma non la ricerca: lo spazio manca, e Cerca sta già nella barra.
- Da continuare in una colonna di card larghe a tutta larghezza. Da iniziare e Visti con le colonne del catalogo (2 su 390 px).
- Nessun cuore sulle card (§9).
- Barra in basso: voce "Lista" con il cuore.

## 13. TV (`FormFactor.tv`)

- Cartellone alto 160 come nel catalogo TV, con il pulsante oro. **Il focus parte dal pulsante del cartellone:** un OK e si riparte.
- Su dal pulsante si va alle schede TUTTI FILM SERIE. Giù si va agli attrezzi (solo Ordina e verso: niente generi né ricerca in TV), poi ai gruppi.
- I gruppi sono gli stessi. Da continuare è una fila che scorre di lato col focus. Visti chiuso ha due controlli raggiungibili: la testata (apre e chiude) e "Togli i visti dalla lista", così la pulizia si fa col telecomando.
- Le card non hanno il cuore (non c'è mouse). Un titolo singolo si toglie dal cuore nella testata della scheda, come oggi (il menu "⋯" non ha il preferito).
- Sinistra dal bordo va alla barra laterale (`tv_sidebar.dart`), la cui voce usa il cuore.
- Come nel catalogo, quando il focus scende nei gruppi il cartellone esce dallo schermo.

## 14. Stati

- **Caricamento:** cartellone nero con "LA MIA LISTA" e le schede, e sotto la griglia a scheletro.
- **Errore:** `ErrorView` con Riprova, come oggi.
- **Ricarica dopo un cambio sul server:** resta la lista vecchia finché arriva la nuova (`skipLoadingOnReload`, come oggi).
- **Prossimo episodio o date non arrivati:** la pagina funziona senza (§5, §8.2, §10).

## 15. Icona

La voce La mia lista usa `LucideIcons.heart` al posto di `LucideIcons.bookmark`, in `shell_bottom_bar.dart` e in `tv_sidebar.dart`.

## 16. Lasciato a chi costruisce

- Struttura dei widget e dei provider, e come `CatalogBand` riceve il pulsante e la frase (un parametro in più, o un `line` più ricco).
- Il cuore sulla card: un parametro di `PosterCard` e di `LandscapeCard`, o un involucro nella pagina.
- Misure fini, partendo dalla bozza.
- Test:
  - `buildMyListView`: gruppi (tabella §6.1, serie in corso vista tutta), titolo di punta (primo da continuare, se no da iniziare, mai ripetuto), ordini con la data di §10 (con e senza date), generi uniti con `genreLabel`, soglia dei 24;
  - widget test: riga del cartellone, Visti chiuso e aperto, Togli i visti con Annulla (serie in corso esclusa), conferma solo in TV, lista vuota e scheda vuota;
  - `toggleFavorite` che scrive e toglie `myListAdded`; Annulla che rimette la data di prima; scritture in fila che non si perdono;
  - una serie iniziata che resta in Da continuare dopo un Annulla;
  - TV: focus iniziale sul pulsante del cartellone, e il giro su/giù.

## 17. Release

Esce con la prossima versione dell'app che non è ancora pubblicata (oggi 0.42.0), con una riga nuova nella checklist di `docs/RELEASING.md`. Nessun plugin.

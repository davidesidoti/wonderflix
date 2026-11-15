# WonderFlix — Home, nuova UI

Data: 2026-11-15. Bozza scelta: [`2026-11-15-home-ui-bozze/home-b.html`](2026-11-15-home-ui-bozze/home-b.html). L'altra, [`home-a.html`](2026-11-15-home-ui-bozze/home-a.html), teneva la struttura di oggi e la correggeva: le sue correzioni (§14) valgono anche qui.

I dati delle bozze sono veri: la Home di davide.sidoti la sera del 15 novembre (app installata), con immagini e trame da TMDB tramite Seerr. Inventati: i minuti che restano, le stagioni di Black Clover, i giorni di arrivo del carosello e i voti delle locandine.

Codice di partenza:
- `features/home/` (`home_screen.dart`, `hero_carousel.dart`, `home_row_view.dart`, `home_layout.dart`, `home_providers.dart`, `home_data.dart`, `home_rows_logic.dart`);
- `ui/media_row.dart`, `ui/poster_card.dart` (`catalogStyle`), `ui/landscape_card.dart`, `ui/user_avatar.dart`;
- le pagine già rifatte: catalogo (spec [`2026-11-14-catalogo-ui-design.md`](2026-11-14-catalogo-ui-design.md)), La mia lista (spec [`2026-11-15-mia-lista-ui-design.md`](2026-11-15-mia-lista-ui-design.md)), Calendario.

La spec della Home di oggi è la spec M (righe, composizione, Personalizza la Home): dove questa spec non dice nulla vale quella.

## 1. Perché

L'utente ha chiesto come migliorare la UI/UX della Home su tutte le piattaforme, l'ultima pagina rimasta dopo catalogo, La mia lista, Richieste, Calendario e Impostazioni. Oggi (app 0.42):

- **Difetti visibili** (§14): frecce delle righe a metà schermo; carosello senza trama né stagioni; generi in due lingue; titoli già visti in evidenza (Ace Ventura); "S02E08" accanto a "S1:E8"; scheletro diverso dalla pagina.
- **Righe tutte uguali.** Fino a 12 righe con lo stesso titolo in Bebas e la stessa striscia di card. Niente dice quali sono "le mie" (da riprendere), quali "degli amici", quali "in arrivo".
- **Due coppie di righe che si somigliano.** Continua a guardare e Prossimi episodi sono due file di card 16:9 con "S1:E8" sotto; Serie in arrivo e Film in arrivo sono due file di uscite con la data in grigio in fondo.
- **Le righe non portano da nessuna parte.** Le mie richieste, La mia lista, Film aggiunti, le uscite hanno una pagina, ma il titolo della riga non ci porta (`MediaRow.onTitleTap` esiste, la Home non lo usa).
- **Card vecchie.** Le locandine sono quelle di prima del catalogo nuovo (`PosterCard` senza `catalogStyle`): l'unica pagina rimasta così.
- **TV.** La Fire Stick disegna a 960×540, quindi la Home usa il layout stretto: carosello alto 432 su 540, "Cosa guardo stasera?" su una riga sotto, e della prima riga si vede solo il titolo. Il focus parte da "Riproduci": un OK di troppo avvia un titolo appena arrivato.

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- Correggere i difetti di §14.
- In cima, dopo il carosello, **cosa riprendere stasera**, in una riga sola.
- Ogni tipo di riga ha una forma che dice cosa contiene: biglietti per riprendere, facce per gli amici, giorni per le uscite, locandine per scoprire.
- Il carosello mostra cosa viene dopo e perché un titolo è lì.
- Ogni riga che ha una pagina ci porta.
- Card uguali al catalogo.
- Una Home TV pensata per 960×540, con la prima riga intera sullo schermo.

**Non obiettivi**
- Nessuna riga nuova e nessuna tolta: restano le 12 di `HomeRowKind`, con gli stessi id.
- Nessun cambio al plugin, alla composizione dell'admin (`home_admin_cards.dart`) e a dove si salvano le preferenze (`homeRows`/`homeHidden`).
- Scheda del titolo, anteprima delle card e "Cosa guardo stasera?"/Match non cambiano.

**Anti-obiettivi**
- Lo stile non cambia: Noir & Oro, Bebas Neue e Inter, nessun colore nuovo.
- La Home non deve aprirsi più lenta di oggi: stesse letture, salvo i campi in più di §5.1. L'apertura con l'entrata scaglionata (spec M §8.2) resta.
- Fuori dalla TV il comportamento TV non cambia, e viceversa (`FormFactor.tv`).

## 3. Strade considerate

| Strada | Idea | Scelta |
|---|---|---|
| A. Correggere | la Home di oggi senza difetti, card del catalogo, link, agenda per le uscite | bozza `home-a.html`, scartata dall'utente a favore della B |
| **B. Cambiare forma** | carosello con la coda, Stasera in biglietti, amici con le facce, settimana delle uscite | **scelta** |

## 4. La pagina

Dall'alto (bozza B, "Desktop"):

1. **Carosello** (§5), con l'alone (§5.4).
2. Le righe nell'ordine della composizione (spec M §6.4), con due unioni:
   - **Stasera** (§6) al posto di Continua a guardare e Prossimi episodi;
   - **In arrivo** (§8) al posto di Serie in arrivo e Film in arrivo.
3. "Personalizza la Home", in fondo, come oggi.

Una sezione unita sta al posto della prima delle sue due righe, nell'ordine della composizione; c'è se almeno una delle due è visibile e ha qualcosa. Le altre righe restano come sono, con l'intestazione e le card nuove (§9).

Margini come oggi: 32 su desktop, 16 nelle finestre strette, 24 in TV. Spazio sopra ogni sezione 28 (oggi 24).

## 5. Il carosello

### 5.1 Titoli

- Come oggi: gli ultimi film e le ultime serie aggiunti, alternati, al massimo 5, solo con un fondale (`pickFeatured`).
- **Senza i titoli visti** (`userData.played`): se ne restano meno di 5, sono meno.
- Le due letture (`homeLatestMoviesProvider`, `homeLatestSeriesProvider`) chiedono anche `Overview`, `ChildCount` e `DateCreated`. Le stesse letture servono le righe Film/Serie aggiunti: i campi in più non cambiano altro.

### 5.2 Diapositiva

Dall'alto, a sinistra (larga 600):
- **Perché è qui**, in oro, 12,5 semibold: "Film · arrivato oggi", "Serie · arrivata ieri", "Film · arrivato martedì" (negli ultimi 7 giorni il giorno della settimana), poi "Film · arrivato il 3 novembre". Il genere grammaticale segue il tipo (film/serie). Senza `DateCreated` la riga non c'è.
- **Logo** se c'è, come oggi; se no il nome in Bebas **104** su desktop (oggi 56).
- **Riga dei dati:** anno · durata (film) o stagioni (serie) · al massimo due generi, passati da `genreLabel` e senza doppioni dopo la traduzione.
- **Trama:** fino a 3 righe.
- **Riproduci** e **Dettagli**, come oggi.

Altezza del carosello: **500** su desktop (oggi 460). Ken Burns, dissolvenza, testi scaglionati e pausa (mouse sopra, anteprima aperta, pagina coperta) come oggi.

### 5.3 La coda

Al posto dei puntini, in basso a destra (a 32 dal bordo e a 56 dal fondo): le locandine dei **prossimi tre titoli**, nell'ordine in cui arriveranno.
- La prima è larga 108, le altre 92; sotto ognuna il nome (11, una riga).
- Sotto la prima, una linea di 2 px che si riempie d'oro con il tempo della diapositiva (il lavoro che oggi fa il puntino attivo, anche con le animazioni ridotte).
- Un clic su una locandina porta a quel titolo. Col mouse sopra si alza di 3 px.
- Con 2 titoli la coda ne ha uno; con 1 titolo la coda non c'è.
- Il carosello col dito si scorre come oggi.

Match e "Cosa guardo stasera?" lasciano l'angolo del carosello e vanno nell'intestazione di Stasera (§6.3).

### 5.4 L'alone

Sotto il carosello, dietro le prime sezioni: il fondale del titolo mostrato, sfocato, opacità 0,28, alto 640, che sfuma dall'alto (da 0 a pieno in 140 px, così non fa scalino col fondo del carosello) e verso il basso fino a sparire. Scorre con la pagina e cambia con la diapositiva, in dissolvenza.

Per non pesare su telefono, web e Fire Stick lo sfocato non è un filtro: è il fondale chiesto piccolissimo (larghezza 32 px) e ingrandito. Con le animazioni ridotte cambia senza dissolvenza.

## 6. Stasera

### 6.1 Cosa contiene

Nell'ordine:
1. i titoli di **Continua a guardare** (se la riga è visibile), come oggi, senza i tolti;
2. i titoli di **Prossimi episodi** (se la riga è visibile), come oggi, senza le serie tolte e **senza le serie che hanno già un biglietto** da Continua a guardare.

Ognuna delle due parti resta limitata a `homeRowLimit` come oggi. La × dell'anteprima resta quella della riga di provenienza (`removeFromResume`, `hideFromNextUp`).

### 6.2 Il biglietto

Una card orizzontale, 392×124 su desktop, fondo `surface`, angoli 8:
- **a sinistra l'immagine** (220 di larghezza, l'immagine di `LandscapeCard`), con la barra d'avanzamento oro in basso se il titolo è iniziato;
- **lo strappo:** una linea tratteggiata verticale `#333` e due mezzi cerchi del colore della pagina, in alto e in basso;
- **a destra la matrice:** titolo (13,5 semibold), episodio come oggi (`cardSubtitle`, "S1:E8 · Per sempre"), e in basso in Bebas 30:
  - iniziato: i minuti che restano, "52 MIN", con "restano" accanto in Inter 11. Minuti = durata meno punto di ripresa, arrotondati per eccesso; sotto un minuto "1 MIN". Senza durata, niente minuti;
  - da Prossimi episodi: "PROSSIMO" in oro (Bebas 22) e accanto la durata dell'episodio se c'è ("58 min"). La bozza scriveva "Nuovo episodio": è cambiato perché l'episodio successivo non è per forza uscito da poco.

Clic, anteprima col mouse fermo, volo Hero e focus TV come `LandscapeCard` oggi. Col mouse sopra o col focus: su di 3 px e bordo oro di 2.

### 6.3 Intestazione

"STASERA" e accanto, piccolo, "9 da guardare" (il numero dei biglietti). A destra, prima delle frecce: "Non sai cosa scegliere?" in `creamMuted`, poi **Match** e **Cosa guardo stasera?** (pulsanti bassi, 32, fondo `surfaceHigh`). Sono gli stessi pulsanti e le stesse azioni di oggi (`MatchButton`, `TonightButton`).

Se Stasera non c'è (nessun titolo da riprendere, o le due righe nascoste), i due pulsanti vanno in cima alle righe, a destra, come oggi `_TonightCorner`, con "Non sai cosa scegliere?" accanto.

## 7. Visti dagli amici

Stessi titoli di oggi. Sopra ogni locandina (176 di larghezza): le facce di chi l'ha visto (`UserAvatar` da 22, sovrapposte di 7, al massimo 3) e accanto i nomi in crema, con lo stesso testo di `friendsWatchedBy` senza "Visto da" ("Garg e CaptainC", "Garg e altri 2"). La locandina è quella del catalogo (`catalogStyle`, quindi senza il numero oro degli episodi), con sotto solo il titolo: chi l'ha visto è già sopra.

## 8. In arrivo

### 8.1 Cosa contiene

Le uscite di **Serie in arrivo** e di **Film in arrivo** (quelle delle righe visibili), raggruppate per giorno, dal più vicino:
- episodi: il giorno di `airDate` come oggi (`upcomingDayLabel`);
- film: il giorno UTC dell'uscita digitale, come oggi (decisione 5 del piano 19b).

### 8.2 La settimana

Una fila orizzontale di giorni (colonne da 236 su desktop, una linea `surface` tra l'una e l'altra):
- **testa:** il numero del giorno in Bebas 44, accanto giorno della settimana e mese in Bebas 18 `creamMuted` ("MAR NOV"); entro due giorni il numero è oro e a destra c'è "oggi", "domani" o "dopodomani" in oro;
- **sotto, le uscite del giorno:** episodio con l'immagine 16:9 da 96 (stessa fonte di oggi: fondale Jellyfin, poi Sonarr, poi locandina), film con la locandina da 40; accanto titolo (12,5 semibold) e "S2:E8" (`episodeCode`, mai più "S02E08") o "Film, in digitale". Un gruppo di episodi ("S2:E8–E10") come oggi `upcomingEpisodes`, con il codice nuovo.
- Clic come oggi: la scheda se il titolo è in libreria, se no Seerr, se no niente.

### 8.3 Intestazione

"IN ARRIVO →" apre il Calendario sulla settimana (`openCalendarWeek`); accanto "7 uscite".

## 9. Le altre righe e le intestazioni

### 9.1 Intestazione di ogni sezione

In `MediaRow`, per tutte le pagine che la usano:
- **titolo** (Bebas 26 nella Home; altrove come oggi) a sinistra;
- **link:** se la riga ha una pagina, il titolo è un link con la freccia oro (c'è già, `onTitleTap`);
- **conteggio** piccolo accanto (Inter 12, `creamMuted` al 32%): il numero delle card;
- **frecce sul bordo destro**: compaiono solo se la riga scorre, e quella del lato già raggiunto è spenta. Mai nelle finestre a tocco (`FormFactor.touch`) e in TV, come oggi in TV.

Il difetto di oggi (§14 punto 1) si corregge qui, una volta sola: tutte le righe che usano `MediaRow` ne beneficiano.

| Riga | Link |
|---|---|
| Le mie richieste | Richieste (`/requests`) |
| Film aggiunti di recente | Film (`/movies`) |
| Serie aggiunte di recente | Serie (`/series`) |
| Continua la saga | Film, vista Saghe (`/movies?view=sagas`) |
| La mia lista | La mia lista (`/mylist`) |
| In arrivo | Calendario, settimana |
| Stasera, Visti dagli amici, Consigliati per te, Perché hai visto X | nessuno |

### 9.2 Card

- Locandine (Film/Serie aggiunti, La mia lista, Perché hai visto X, Consigliati per te, Visti dagli amici): `PosterCard(catalogStyle: true)`, cioè anno e voto, locandina vista un po' spenta. Consigliati per te tiene la sua riga sotto ("Consigliato da …") e le note nell'anteprima.
- Le mie richieste e Continua la saga: card di oggi, con l'intestazione nuova.

## 10. Personalizza la Home

L'elenco delle righe non cambia: 12 voci, ognuna con il suo interruttore e il suo posto, come oggi, per l'utente e per l'admin. Sotto le voci Continua a guardare e Prossimi episodi una nota: "Nella Home stanno insieme in Stasera"; sotto Serie in arrivo e Film in arrivo: "Nella Home stanno insieme in In arrivo". Spostare la voce che viene prima sposta la sezione (§4).

## 11. Stati

- **Caricamento:** lo scheletro ha la forma della pagina vera sul suo schermo: carosello a tutta larghezza dal bordo alto (500, 470 sul telefono, 300 in TV), poi una fila di biglietti e una di locandine, con le misure di §12 e §13.
- **Apertura:** come oggi (spec M §8.2): aspetta le righe fino a 1,5 s, poi entrano insieme; una sezione unita entra quando la prima delle sue due righe è arrivata, e la seconda si aggiunge al suo posto senza un'altra entrata.
- **Errore:** come oggi (`ErrorView` con Riprova se carosello e righe di Jellyfin falliscono tutti).
- **Home vuota:** come oggi, con Match e "Cosa guardo stasera?".

## 12. Telefono e finestre strette (`FormFactor.compact`)

Bozza B, "Telefono e TV", a sinistra.
- **Carosello:** alto come oggi nello stretto (`heightOf`, al massimo 470), immagine allineata in alto; nome in Bebas 62; trama 2 righe. Al posto della coda una **barra a tacche** sotto i pulsanti (una tacca per titolo: le passate oro, quella attuale che si riempie, le altre al 20%). Le tacche si toccano su 44 px di altezza.
- **Intestazioni:** il titolo va a capo sopra Match e "Cosa guardo stasera?"; "Non sai cosa scegliere?" sparisce.
- **Misure:** biglietto 300×104 con immagine 150, Bebas 24; locandine 112 (amici 124); giorni 200.
- **Alone:** come su desktop, sotto il carosello.

## 13. TV (`FormFactor.tv`)

Bozza B, "Telefono e TV", a destra (960×540, barra laterale da 64).
- **Carosello alto 300.** Nome in Bebas 64, trama 2 righe. Ai pulsanti si aggiunge **"Stasera?"** (`TonightButton` con un'etichetta corta, nuova), perché Match in TV non c'è e la riga dei pulsanti di Stasera in TV non c'è.
- **La coda resta,** più piccola (72 e 62), e non prende il focus: si cambia titolo con Destra dall'ultimo pulsante e con ⏪/⏩, come oggi.
- **Focus iniziale sul primo biglietto di Stasera**; senza Stasera, su "Riproduci" del carosello come oggi. Su dal primo biglietto porta ai pulsanti del carosello.
- **Stasera:** biglietti 330×108 con immagine 182; la prima riga sta intera sotto il carosello. Intestazione senza Match e "Cosa guardo stasera?".
- **Focus delle card:** ingrandimento e bordo oro come oggi (`TvFocusable`), anche sul biglietto.
- **Alone:** anche in TV. Se sulla Fire Stick fa perdere fotogrammi nello scorrimento, in TV si toglie (da provare a mano).

## 14. Correzioni (anche senza il resto)

1. **Frecce delle righe a metà riga.** In `MediaRow` il titolo è `Flexible` con uno `Spacer` accanto: si dividono lo spazio libero e la parte non usata dal titolo resta vuota, così le frecce cambiano posto a ogni riga. Il titolo prende lo spazio (`Expanded`, allineato a sinistra) e le frecce stanno sul bordo. Più §9.1 (frecce solo se la riga scorre).
2. **Carosello senza trama né stagioni:** §5.1 (`Overview`, `ChildCount`).
3. **Generi in due lingue nel carosello:** `genreLabel` (§5.2).
4. **Titoli visti nel carosello:** §5.1.
5. **"S02E08":** `upcomingEpisodeLabel` (usata solo dalla Home) scrive il codice come `episodeCode` (§8.2).
6. **Scheletro diverso dalla pagina:** §11.

## 15. Lasciato a chi costruisce

- Struttura dei widget: dove vive l'unione delle righe (un passo dopo `composeHomeLayout` che produce "sezioni"; i provider delle righe restano uno per riga), come `MediaRow` riceve conteggio e intestazione ricca (`trailing` c'è già).
- Il biglietto: un widget nuovo (`TicketCard`) o una variante di `LandscapeCard`.
- Le etichette del giorno di arrivo (§5.2) e di "oggi/domani/dopodomani" (§8.2): nuove chiavi l10n, data con `clock`.
- Misure fini, partendo dalla bozza.
- Test:
  - unione: posizione della sezione (prima delle due nell'ordine), una sola riga visibile, nessuna, serie con biglietto di Continua a guardare tolta da Prossimi episodi, tolti e nascosti;
  - `pickFeatured` senza i visti; riga "perché è qui" (oggi, ieri, giorno della settimana, data; film/serie);
  - minuti che restano (arrotondamento, sotto il minuto, senza durata);
  - In arrivo: raggruppamento per giorno (episodi locali, film UTC), "dopodomani", `episodeCode`;
  - `MediaRow`: frecce sul bordo con titoli di lunghezze diverse, nascoste se la riga non scorre, spente ai capi, assenti col tocco e in TV;
  - widget test della Home: Stasera con Match e "Cosa guardo stasera?", la coda che cambia titolo, link delle intestazioni;
  - TV: focus iniziale sul primo biglietto, Su verso il carosello, "Stasera?" tra i pulsanti, e senza Stasera il focus su "Riproduci".

## 16. Release

Esce con la prossima versione dell'app non ancora pubblicata (oggi 0.42.0), con una riga nuova nella checklist di `docs/RELEASING.md`. Nessun plugin.

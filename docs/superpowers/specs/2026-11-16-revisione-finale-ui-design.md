# WonderFlix — Revisione finale della UI prima della 0.42

Data: 2026-11-16. Bozze: [`2026-11-16-revisione-finale-bozze/`](2026-11-16-revisione-finale-bozze/indice.html) (indice, `player.html`, `scheda.html`, `strumenti.html`, `social.html`, `cerca.html`, `accesso.html`; pezzi comuni in `kit.css`, dati in `data.js`).

Immagini, trame, cast ed episodi delle bozze sono veri (Seerr/TMDB, 16 novembre); i risultati di "ist" in Cerca vengono dal database di Jellyfin del seedbox; le persone sono quelle del server. Inventati: voti degli amici, punti di ripresa, durate di alcuni episodi, la classificazione VM14, la riga "Fa parte di" di The Wrestler, le candidate di Locandina e sfondo. Le bozze scrivono nelle didascalie cosa è inventato.

L'analisi viene dal codice di `main` (8fe4346f), non dall'app aperta: ogni "Oggi" delle bozze cita file e riga.

Codice di partenza: `features/player/`, `features/trailer/`, `features/detail/`, `features/ratings/`, `features/person/`, `features/collections/collection_screen.dart`, `features/requests/tmdb_title_screen.dart`, `features/reports/`, `features/item_edit/`, `features/subtitles/`, `features/friends/`, `features/recommendations/`, `features/inbox/`, `features/watch_party/` (carte e menu d'invito), `features/search/`, `features/profiles/`, `features/auth/`, `features/startup/`, `features/update/`, `ui/wf_dialog.dart`, `ui/shell_side_panel.dart`, `app/shell_panels.dart`, `app/app_shell.dart`, `app/theme.dart`, `core/jellyfin/genre_labels.dart`.

Le pagine già rifatte (Home, Catalogo, La mia lista, Calendario, Impostazioni, Richieste, Cabina, Stasera/Match) non cambiano. Dove questa spec non dice nulla valgono le spec di ogni funzione.

## 1. Perché

L'utente ha chiesto una revisione finale, prima della release, delle pagine non ancora rifatte. Letto il codice, i problemi sono di tre tipi:

- **Difetti veri.**
  - La TV prende i layout del telefono nel player, nella pagina Persona e in Segnala / Info tecniche (`compact` senza `&& !tv`).
  - Quattro campi di testo raggiungibili in TV aprono la tastiera appena prendono il focus: la nota di Segnala, il commento del voto, il messaggio di Consiglia a…, il recupero password.
  - "Riprova" nell'errore del player sembra irraggiungibile col telecomando.
  - I generi della scheda sono in inglese, e mancano nella tabella delle traduzioni quelli delle serie TMDB ("Sci-Fi & Fantasy", "Action & Adventure"…).
- **Cose che mancano.**
  - "Segna come visto" per episodio e per stagione.
  - Tempo che resta e ora di fine nel player; i tasti scritti da qualche parte.
  - Ricerche recenti, miglior risultato e "Vedi tutti" in Cerca.
  - Notifiche raggruppate.
  - Conferma prima di cambiare una locandina.
- **Pagine fuori dal linguaggio dell'app.**
  - Finestre e pannelli con titoli in Inter e piedi diversi.
  - Chip, checkbox, radio e switch Material di serie.
  - Etichette in maiuscolo; tre frasi diverse per lo stesso invito; "S1 E2" accanto a "S1:E2".

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- Correggere i difetti (§3.5, §3.6 e le sezioni di ogni area).
- Un guscio comune per finestre e pannelli, e controlli a tema (§3).
- Per ogni area, le proposte delle bozze, con un solo elemento "forte":
  - player: la scheda dei tasti;
  - scheda: il biglietto del prossimo episodio;
  - Identifica: i biglietti "Ora" e "Dopo";
  - notifiche: i gruppi per giorno, con chi le manda;
  - Cerca: il miglior risultato;
  - accesso: il server che si avvia.

**Non obiettivi**
- **Nessun cambio al plugin.** Le tre proposte delle bozze che lo richiederebbero restano fuori:
  - la lettura per riga delle notifiche (il plugin segna lette fino a un numero, `Inbox/Read`);
  - l'"ultima visita" degli amici offline;
  - il QR di Quick Connect.
- **Qualità nel player**: resta in Impostazioni. La bozza la propone; riaprire lo stream dal punto attuale è lavoro in più, non correzione.
- **Altre pagine e funzioni:** Amici e Notifiche in TV, elenco dei capitoli da scegliere, modifica di cast, studi e tag, chat e coda del watch party.
- Il comportamento delle pagine già rifatte.

**Anti-obiettivi**
- **Lo stile non cambia:** Noir & Oro, Bebas Neue e Inter, nessun colore nuovo (verde `WfColors.online`, rosso `WfColors.error` ci sono già).
- Fuori dalla TV il comportamento TV non cambia, e viceversa.
- **Nessuna lettura in più all'apertura delle pagine**, salvo dove la spec lo dice:
  - le persone in Cerca;
  - il controllo di "Fatto" in Aggiorna metadati.

### 2.1 Dove la spec si scosta dalle bozze

Le bozze restano il riferimento visivo. Dove dicono altro, vale la spec:

- **Player:** la riga "Qualità" del pannello tracce non c'è (§2).
- **Notifiche:**
  - letto come oggi, non "quando la vedi";
  - al posto del ⋯ con "Segna da leggere" e "Togli dalla lista", una ✕ sempre visibile (§7.1): il plugin non ha lo stato "letto" per voce.
- **Amici:** il ⋯ della riga non ha "Invita a guardare". Senza un titolo scelto non c'è niente a cui invitare. "Guarda insieme" sulla riga di chi sta guardando c'è già (`watch_with_friend.dart`), e un party aperto ha già "Invita amici".
- **Carte e righe d'invito:** "2 nel party" solo se il dato arriva con l'invito (§11).

## 3. Regole e pezzi comuni

### 3.1 Regole

1. **Il titolo dice dove sei.** Finestre e pannelli hanno il titolo in Bebas. Se agiscono su un titolo, sotto c'è la riga del titolo o dell'episodio ("L'Istituto · S1:E4 La scatola", "The Wrestler · Film · 2008"), con la locandina piccola.
2. **Un'azione, un nome.** Lo stesso verbo nel pulsante, nell'avviso e nel menu. Il pulsante dice cosa succede ("Salva voto", "Invia segnalazione", "Usa questa locandina"), mai "Conferma".
3. **Niente di nascosto.** Niente controlli che compaiono solo al passaggio del mouse. Sul telefono, se c'è spazio per una parola, le icone hanno il nome. Blocchi e opzioni si spiegano in una riga.
4. **Un solo primario per vista; il "⋯" è sempre l'ultimo.**
5. **Niente etichette in maiuscolo**: "Stai guardando", "Prossimo episodio", "Da rispondere", "Accedi", "Aggiornamento necessario".
6. **Episodi sempre con `episodeCode`** ("S1:E4"). **Generi sempre con `genreLabel`**, al massimo 2 nelle righe dei dati.
7. **Numeri che cambiano (tempi, conti) con cifre tabellari** (`FontFeature.tabularFigures()`).

### 3.2 Guscio delle finestre (`ui/wf_dialog.dart`)

- **Testa:** locandina piccola (se c'è un titolo), titolo `WfText.display(32)`, la riga del titolo in `creamMuted` 12,5.
- **Piede comune** (un widget nuovo in `ui/`, usato da tutte le finestre di questa spec e da `wf_confirm_dialog.dart`):
  - a sinistra un suggerimento o un conteggio ("Scegli che problema c'è", "3 modifiche");
  - a destra "Annulla" (`WfButton.secondary`) e un solo `WfButton.primary` col verbo dell'azione.
- **Stretto:** pagina intera con una barra in alto (titolo e ✕) e il piede fisso in basso, sempre visibile, anche con la tastiera aperta.
- **TV:** sempre finestra (`fullPageWhenCompact: !tv`), focus iniziale sul primo controllo o sul primario.
- **Chiudere con modifiche non salvate** (Esc, clic fuori, Annulla) chiede "Buttare le N modifiche?". Senza modifiche chiude subito. Vale per Modifica metadati e per la nota di Segnala.

### 3.3 Guscio dei pannelli (`ui/shell_side_panel.dart`, `app/shell_panels.dart`)

- Largo 380 (oggi 360). Restano come oggi il velo, Esc, il clic fuori e un pannello alla volta.
- **Titolo** `WfText.display(30)` e una riga sotto che dice di cosa si parla: "2 online" per Amici, locandina e titolo per Consiglia.
- **Stretto:** le pagine `/friends`, `/inbox`, `/recommend` hanno il titolo nella barra e si chiudono solo con la ←. Il titolo e la ✕ del pannello spariscono.
- **Pulsanti in alto:** stesso ordine ovunque, Watch party · Amici · Notifiche (oggi lo stretto inverte gli ultimi due, `app_shell.dart:226`).
- **Caricamento:** tre righe grigie con la forma delle righe vere (`ui/skeletons.dart`), non un pannello vuoto.
- **Errore:** una frase che dice cosa fare e "Riprova".

### 3.4 Controlli a tema (`app/theme.dart`)

- Temi per `chipTheme`, `checkboxTheme`, `radioTheme`, `switchTheme` e `dropdownMenuTheme`, con i token di oggi:
  - **pastiglia scelta:** bordo oro, fondo oro al 14%, testo oro;
  - **switch acceso:** traccia oro;
  - **checkbox:** oro.
- Niente controlli nuovi dove basta il tema. Le scelte "a riquadro" di Segnala e Aggiorna metadati (§6.2, §6.6) sono un widget proprio.

### 3.5 TV

- Ogni layout TV è `compact && !tv`, mai quello del telefono. Punti da correggere:
  - `player_side_panel_host.dart:447`, `pause_screen.dart:242`, `post_play.dart:105,196`, `player_screen.dart:1736`;
  - `person_screen.dart:81`;
  - le finestre Segnala e Info tecniche (`fullPageWhenCompact: !tv`).
- Ogni campo di testo raggiungibile in TV sta in `TvTextFieldFrame`:
  - nota di Segnala (`report_dialog.dart:286`);
  - commento del voto (`rating_widgets.dart:87`, usato anche da `rating_round_panel.dart`);
  - messaggio di Consiglia a… (`recommend_panel.dart:228`);
  - campi del recupero password, senza autofocus (`recovery_panel.dart:301-368`).
- Il focus è quello di tutta la TV (bordo crema 2 e scala 1,06), anche sui pulsanti del player e sulle carte di Chi guarda? (oggi solo l'anello o il velo oro).

### 3.6 Generi (`core/jellyfin/genre_labels.dart`)

- Aggiungere i generi TMDB delle serie e i comuni che mancano:

  | Server | Italiano |
  |---|---|
  | Sci-Fi & Fantasy | Fantascienza e fantasy |
  | Action & Adventure | Azione e avventura |
  | War & Politics | Guerra e politica |
  | Crime | Crime |
  | Fantasy | Fantasy |
  | Horror | Horror |
  | Romance | Romantico |
  | Thriller | Thriller |
  | Western | Western |
  | Kids | Bambini |
  | Reality | Reality |
  | Soap | Soap |
  | Talk | Talk show |
  | News | Notizie |

- Prima di scriverli, controllare i nomi veri con `/Items/Filters2?recursive=true` sul server: nella tabella vanno solo quelli che esistono.
- `genreServerNames` resta com'è: un genere unito (es. "Fantascienza") manda al server tutti i suoi nomi inglesi.

## 4. Player e trailer (bozza `player.html`)

### 4.1 Comandi, desktop

- **Barra bassa: quattro gruppi** separati da un filo verticale `border` alto 20:
  1. −10, riproduci/pausa, +10, muto, volume (slider **oro**, oggi crema);
  2. ⏮ ⏭;
  3. Guarda insieme, Chat, Reazioni;
  4. Coda, Audio e sottotitoli, **Velocità** (nuovo, §4.3), Schermo intero.
- **Tempo** con cifre tabellari: la posizione a sinistra della seek bar. A destra "−49:55 · finisce alle 23:41"; l'ora viene dall'orologio del dispositivo, al minuto.
- **Seek bar:** il pallino è sempre visibile (oggi solo al passaggio).
- **Tooltip col tasto:** ogni tooltip mostra il suo tasto in un riquadro piccolo:

  | Tooltip | Tasto |
  |---|---|
  | Pausa / Riproduci | Spazio |
  | Indietro / Avanti di 10 secondi | ← / → |
  | Volume | ↑/↓ |
  | Disattiva audio | M |
  | Schermo intero | F |
  | Episodio successivo / precedente | N / P |
  | Chat | Invio |
  | Reazioni | 1–6 |

- La freccia in alto si chiama "Torna alla scheda", o "Torna alla Home" se il video è partito da lì. "Indietro" resta solo per i 10 secondi.
- **Avvisi:** "Il server sta convertendo questo video." e "Il sottotitolo sarà disponibile dalla prossima riproduzione" vanno nella pastiglia del player (`player_pill.dart`), non in una SnackBar (`player_screen.dart:1327,1558`).

### 4.2 Pausa e scheda dei tasti

- **Schermata pausa** (`pause_screen.dart`):
  - "Stai guardando" in oro, frase normale;
  - un solo primario "Riprendi" con accanto il tasto Spazio;
  - il puntatore che si muove riporta i comandi, un clic ovunque riprende;
  - in basso l'avanzamento sottile al posto della scritta "In pausa".
- **Scheda "Tasti"** (l'elemento forte):
  - **Forma:** un riquadro `surface` con doppio filo oro, titolo Bebas "Tasti", righe "azione ……… tasto" con i puntini fino al tasto (tutti i tasti di `player_commands.dart`).
  - **Dove compare:** nella pausa su desktop, a destra.
  - **Il tasto `?`** (nuovo, solo app) la apre e la chiude in ogni momento; Esc la chiude.
  - **Non c'è** su telefono e TV.

### 4.3 Audio e sottotitoli

- **Testa e righe:** titolo Bebas e la riga dell'episodio. Righe alte 44, con la lingua in italiano e sotto il dettaglio in `creamMuted` ("AC3 5.1 · predefinita"); la scelta è in oro con la spunta.
- **Ritardo:** pulsanti del kit (non `IconButton`), con il valore tabellare "+0,3 s" e accanto i tasti G/H.
- **Dimensione:** cinque "Aa" della grandezza vera, col nome della scelta nell'etichetta ("Dimensione · Medi").
- **Velocità** (nuova, `setRate` c'è già nel motore):
  - scelte 0,75× · 1× · 1,25× · 1,5× · 2×;
  - **in Guarda insieme** resta 1× e la riga lo dice ("In compagnia la velocità resta 1×"), perché SyncPlay non la sincronizza;
  - vale per la riproduzione in corso e torna a 1× al titolo dopo.

### 4.4 Telefono

- Titolo in Bebas 26 (oggi `titleLarge` in Inter, `player_overlay.dart:266`).
- Trio centrale 52/68.
- **Seek bar:** area tattile alta 44 (oggi 28) e pallino sempre visibile.
- Sotto, quattro pulsanti con la parola: Audio e sottotitoli, Episodio successivo, Guarda insieme e "Altro" per ultimo. "Altro" tiene Chat, Reazioni, Coda, Episodio precedente, Velocità e Schermo intero.
- **Pannelli come vero foglio dal basso:**
  - maniglia, angoli 16 in alto, nessun bordo a sinistra;
  - righe alte 48, ✕ grande 44;
  - si chiude trascinando giù o toccando il video.

### 4.5 TV

- Icone 30 (32 per la pausa) in cerchi 56, col focus di §3.5. Sotto il pulsante col focus compare il suo nome.
- Pannelli laterali (380 a destra), non fogli dal basso. Righe alte 52; sulla riga piena la scala scende a 1,03.
- Il ritardo dei sottotitoli resta fuori dalla TV, come oggi.

### 4.6 Errore e caricamento

- **Errore:**
  - tutto centrato, al massimo 46 caratteri per riga;
  - il titolo dice cosa è successo, il testo cosa fare;
  - il dettaglio tecnico resta, piccolo;
  - "Riprova" ha il focus all'apertura anche in TV (dentro un `FocusScope` proprio, fuori dalla gestione dei tasti del player, `player_screen.dart:1159`); "Torna alla scheda" è la seconda azione.
- **SafeArea** sulla ← del caricamento e di "Riproduci" (oggi "Tocca per riprodurre") e sui comandi del trailer.
- **Buffering:** la stessa linea oro del caricamento al centro, non `CircularProgressIndicator` (`player_loading.dart:347`).
- **"Tocca per riprodurre" diventa "Riproduci"**: vale per il dito e per il mouse.

### 4.7 Prossimo episodio

- **Post-play:** "Prossimo episodio" in frase normale. Primario "Riproduci tra 8 s", con l'oro che riempie come oggi. Seconda azione "Guarda i titoli".
- **Carta del prossimo episodio** (`player_extras.dart`): stessi due pulsanti con gli stessi nomi ("Annulla" sparisce); bordo `border`, senza elevazione.
- **In TV** l'immagine c'è, perché il layout non è più quello del telefono. La trama si toglie per stare nei 540 di altezza; il focus parte sul primario.

### 4.8 Trailer (`trailer_screen.dart`)

- Usa i pezzi del player:
  - sfumature in alto e in basso;
  - seek bar col tempo tabellare;
  - la pastiglia per volume e salti;
  - gli stessi tasti (Spazio, ←/→, ↑/↓, M, Esc).
- Un clic sul video mette in pausa.
- Un solo "Chiudi", con la parola, in alto a destra.
- **Non disponibile:** "Trailer non disponibile" al centro e quel solo "Chiudi" col focus (oggi due "Chiudi" e un `FilledButton`).
- **Autoplay bloccato:** lo stesso strato "Riproduci" del player.

## 5. Scheda del titolo (bozza `scheda.html`)

### 5.1 Intestazione (`detail_header.dart`)

- **Come la Home:**
  - riga oro piccola: "Film di {regista}" per un film, "Serie · {anno di inizio}" per una serie (`hero_labels.dart` per lo stile);
  - nome in Bebas 96 su desktop (oggi 56), o il logo alla stessa altezza;
  - **una sola riga di dati**: anno · durata o "N stagioni" · due generi tradotti · ★ voto · classificazione (oggi i generi stanno su una riga a parte, in inglese, `:290-298`);
  - trama di 3 righe con "Altro" che la apre sul posto.
- **Azioni in ordine fisso:**
  1. primario (Riproduci / "Riprendi da 34:12" / "Riprendi S1:E8"), con accanto ↺ Ricomincia come icona (solo se c'è un punto di ripresa);
  2. Guarda insieme;
  3. Trailer;
  4. icone di stato: La mia lista, Visto, Vota, Consiglia a…;
  5. ⋯ per ultimo ("Richiedi stagioni" entra nel ⋯, §6.1).
- Sotto il primario, se c'è un punto di ripresa, quanto manca ("rimangono 18 min").
- **Telefono:**
  - immagine 16:9 e testo sotto (come oggi), una riga di dati, primario a tutta larghezza;
  - poi **sei azioni con icona e parola sotto**, alte 58: La mia lista, Visto, Trailer, Insieme, Consiglia, Altro;
  - Ricomincia e Richiedi stagioni vanno in Altro.
- **TV:**
  - intestazione più bassa: logo o nome alto 80, trama di 2 righe;
  - le icone hanno il nome sotto; il focus parte sul primario;
  - sotto l'intestazione si intravedono le stagioni, non i voti.

### 5.2 Episodi (`series_detail_view.dart`)

- **Stagioni** in una riga che scorre (oggi un `Wrap`), con "Stagione 1 · 8 episodi" e la sottolineatura oro di oggi. Accanto, il ⋯ della stagione: "Segna la stagione come vista" / "Segna la stagione come da vedere" e "Vota la stagione".
- **Voti della stagione** subito sotto le schede, in una riga bassa: media in Bebas oro, numero di amici, avatar con voto, "Vota la stagione". Oggi stanno sopra le schede (`:116`).
- **Episodio:**
  - still 200 con la barretta, nome;
  - "S1:E4 · 27 lug 2025 · 52 min" (data da `PremiereDate`), trama di 2 righe;
  - a destra un pulsante **Visto** (contorno, spunta; acceso in oro) **prima** del ⋯;
  - Visto e Visto della stagione usano `/UserPlayedItems` come il Visto dell'intestazione (`togglePlayed`).
- **Prossimo episodio come biglietto** (l'elemento forte):
  - forma di `ui/ticket_shape.dart`, bordo oro, still con ▶;
  - sopra il nome "Prossimo" in oro;
  - in fondo "Riprendi · rimangono 18 min" e la barretta (o "Riproduci" se non iniziato).
- La lista si costruisce a pezzi (sliver), non tutta in una `Column` (`:341`).
- **Telefono:** episodi compatti con data, durata e Visto; il biglietto c'è anche qui.
- **TV:** Giù dal primario porta alle stagioni, poi al primo episodio; i voti della stagione vengono dopo le schede.

### 5.3 Film, sotto l'intestazione (`movie_detail_view.dart`)

- **Ordine:** Voti degli amici, Cast, Fa parte di, Simili.
- **Righe:**
  - "Fa parte di" usa `rowPosterSize` come Simili (oggi 160/300 fissi, `collection_rows.dart:61,71`);
  - il cast ha foto e personaggio; chi non ha foto ha la sagoma;
  - "Voti degli amici" ha il pulsante del kit ("Vota", o "Il tuo voto: 8" in oro), non un `TextButton.icon` (`friend_ratings_row.dart:55`).

### 5.4 Il tuo voto (`rate_panel.dart`)

- **Pannello e testa:** pannello del guscio (§3.3), titolo "Il tuo voto", la riga con locandina e titolo.
- **Scala** grande: due file da cinque, numeri in Bebas 30, il voto scelto in oro. Sotto, una parola:

  | Voto | Parola |
  |---|---|
  | 1–2 | Da evitare |
  | 3–4 | Deludente |
  | 5–6 | Così così |
  | 7 | Bello |
  | 8 | Molto bello |
  | 9 | Bellissimo |
  | 10 | Imperdibile |

- **Commento** in `TvTextFieldFrame` in TV.
- **Un piede solo:** "Togli il mio voto" a sinistra (testo rosso tenue, solo se c'è un voto) e "Salva voto" a destra. Oggi sono due righe a destra.

### 5.5 Persona, saga, pagina TMDB

- **Persona** (`person_screen.dart`):
  - margini 16 nello stretto (oggi 32);
  - biografia di 4 righe con "Altro";
  - "Su WonderFlix" solo se c'è almeno un titolo, altrimenti una riga che invita a cercarlo in Richieste;
  - in TV layout proprio: foto a sinistra, biografia che prende il focus (OK la apre), titoli in una fila.
- **Saga** (`collection_screen.dart`): griglia allineata all'intestazione (16 nello stretto). Vuota: una frase su cosa fare, non "0 film · 0 visti".
- **Pagina TMDB** (`tmdb_title_screen.dart`):
  - stessa intestazione della scheda, compreso lo stretto;
  - riga oro "Non ancora su WonderFlix", una riga di dati, "Richiedi" come primario.

## 6. Menu ⋯ e strumenti (bozza `strumenti.html`)

### 6.1 Menu ⋯ (`item_actions_menu.dart`)

- **Voci con icona Lucide**, in gruppi con un nome in frase normale:
  - **La tua visione:** Togli da Continua a guardare, Togli da / Rimetti in Prossimi episodi; nello stretto anche Consiglia a… e Richiedi stagioni…;
  - **Controlla e segnala:** Segnala un problema…, Info tecniche…, Sottotitoli…;
  - **Admin:** Modifica metadati…, Identifica…, Aggiorna metadati…, Locandina e sfondo….
- I puntini ci sono su tutte le voci che aprono una finestra, mai su quelle che agiscono subito.
- **TV:** stesse voci di oggi, stessi nomi, righe alte 44, focus di §3.5. Il menu si apre sopra il ⋯ se sotto non c'è posto.

### 6.2 Segnala un problema (`report_dialog.dart`)

- **Testa:** "Segnala un problema" e "L'Istituto · S1:E4 La scatola".
- **Due domande con etichetta:**
  - "Su cosa?": Questo episodio / Stagione 1 / Tutta la serie;
  - "Che problema c'è?": quattro riquadri con icona e un esempio in una riga:

    | Riquadro | Esempio |
    |---|---|
    | Sottotitoli | mancano, sono fuori sincrono, lingua sbagliata |
    | Titolo o informazioni | nome, trama o locandina sbagliati |
    | Audio o video | si blocca, niente audio, lingua sbagliata |
    | Altro | qualcos'altro: scrivilo nella nota |

- **Nota** (contatore solo vicino al limite, come oggi).
- **Piede:**
  - finché manca il tipo, a sinistra "Scegli che problema c'è";
  - se l'hai già segnalato, il riquadro lo spiega e il pulsante dice "Aggiorna la segnalazione".
- **Telefono:** i riquadri vanno in colonna. **TV:** finestra, nota in cornice.

### 6.3 Segnalazioni, lato admin (`reports_banner.dart`, `resolve_report_dialog.dart`)

- **Elenco** con i pezzi della Cabina (`AdminList`, `WfLamp`: oro aperta, verde chiusa) al posto del riquadro bordato d'oro.
- **Riga:**
  - avatar, nome, "S1:E4 La scatola · Sottotitoli", la nota tra virgolette;
  - una sola azione in evidenza, in contorno: "Segna come sistemato…";
  - la scorciatoia (Identifica / Modifica metadati / Cerca sottotitoli) come pulsante di testo;
  - "Segna come non sistemabile…" nel ⋯.
- **Finestra di chiusura:**
  - mostra la segnalazione (chi, cosa, quando, nota);
  - il pulsante ripete il titolo ("Segna come sistemato" / "Segna come non sistemabile");
  - dopo, l'avviso "Segnalazione chiusa".

### 6.4 Modifica metadati (`edit_metadata_dialog.dart`)

- **Testa** col titolo su cui lavori.
- **Spiegazione del blocco**, una riga in cima: "I campi che modifichi restano tuoi: Jellyfin non li sovrascrive più. Il lucchetto li libera."
- **Gruppi** in due colonne:
  - Titoli: Titolo, Titolo originale, Titolo per l'ordinamento;
  - Trama e frase di lancio ("Tagline" diventa "Frase di lancio");
  - Date;
  - Generi;
  - Classificazione;
  - Blocca tutto.
- **Campi bloccabili:** dicono a parole lo stato ("Bloccato" in oro / "Si aggiorna da solo" spento). Gli altri non hanno lo spazio vuoto del lucchetto.
- **Data di uscita:** formato "gg/mm/aaaa" e calendario; gli errori sotto il campo (`errorText`). "Salva" porta al primo campo sbagliato.
- **Generi:** "+ Aggiungi" accanto al campo; un genere scritto e non confermato si aggiunge al salvataggio.
- **Piede:** "N modifiche"; "Salva" spento solo senza modifiche.
- **Chiudere con modifiche:** §3.2. **Caricamento fallito:** "Riprova".

### 6.5 Identifica (`identify_dialog.dart`)

- **Ricerca:**
  - campi Nome, Anno, ID TheMovieDb, ID IMDb (suggerimento "tt…"); ID TVDB solo per le serie;
  - risultati in riquadri con locandina (sagoma se manca), anno e fonte, regista o creatore;
  - il risultato scelto in oro con la spunta; quello attuale segnato "Attuale".
- **"Ora" e "Dopo"** (l'elemento forte): due biglietti sotto i risultati, nella stessa vista:
  - "Ora" spento: l'abbinamento attuale;
  - "Dopo" in oro, con in oro ciò che cambia (anno, durata, "Locandina e sfondo nuovi", regista).
- **Opzioni:**
  - "Sostituisci anche le immagini": acceso;
  - "Sblocca i N campi modificati a mano (Titolo, Trama)": **spento di serie**, nomina i campi. Oggi sono accesi tutti e due, `:75-76`.
- **Piede:** "Annulla" chiude; "Applica questo risultato". Il "Annulla" che voleva dire "indietro" sparisce.
- **Telefono:** i biglietti vanno in una seconda pagina con "Indietro" e "Applica".
- Restano "Può volerci qualche minuto…" e "Jellyfin sta ancora lavorando: ricarica tra poco".

### 6.6 Aggiorna metadati (`refresh_metadata_dialog.dart`)

- **Scelte:** due riquadri che dicono cosa toccano:
  - "Completa i dati": cerca solo ciò che manca;
  - "Riscrivi tutto": sostituisce tutto tranne i campi bloccati.
- **Altre righe:**
  - "Anche le immagini", attiva solo con "Riscrivi tutto";
  - su una serie, l'avviso "Vale anche per le sue N stagioni e M episodi".
- Il pulsante ripete la scelta.
- **Dopo l'avvio:** la finestra resta aperta con "In corso…", poi passa a "Fatto" quando `DateLastRefreshed` del titolo cambia (una lettura ogni 5 s, al massimo 2 minuti; poi "Ancora in corso: puoi chiudere"). Da verificare (§11): se Jellyfin non aggiorna quella data, si resta all'avviso di oggi.

### 6.7 Locandina e sfondo (`images_dialog.dart`)

- **"Attuale"** fissa a sinistra; la griglia scorre a destra con segnaposto della forma giusta.
- **Scegliere una candidata** la segna in oro e trasforma il piede in una barra: "Usare questa locandina?" con Annulla / "Usa questa locandina".
  - Niente cambia prima.
  - Dopo, l'attuale di prima resta tra le candidate.
- **Testi delle candidate:**
  - "★ 5,3 · Italiano · 2000×3000": lingua in parole, voto con la virgola;
  - "Carica dal PC…" diventa "Carica un file…";
  - per un episodio il titolo è "Immagine dell'episodio" e le pastiglie spariscono.

### 6.8 Sottotitoli (`subtitles_dialog.dart`)

- **Testa:** serie ed episodio (dal menu oggi arriva solo il nome, `item_actions_menu.dart:161`).
- **Tracce presenti** in cima:
  - si leggono: "Italiano · SRT · file esterno";
  - quelle dentro il video dicono perché non si eliminano;
  - la conferma nomina la traccia: "Eliminare i sottotitoli Italiano (SRT, file esterno)?".
- **Ricerca:**
  - parte all'apertura nella lingua dell'app; lingua in un campo con cornice;
  - riparte se cambi lingua;
  - solo il risultato "Sincronizzato col file" ha "Scarica" in oro.
- **"Carica un file"** ha il suo riquadro con le sue opzioni Forzati / Per non udenti, che così non sembrano filtri della ricerca.
- `PopScope` mentre scarica o carica, come le altre finestre.

### 6.9 Info tecniche (`media_info_dialog.dart`)

- **Quattro gruppi con icona:** File, Video, Audio (N), Sottotitoli (N), al posto dell'etichetta ripetuta su ogni riga.
- **Valori leggibili:**
  - codec come si scrivono (HEVC, E-AC-3 5.1, SRT);
  - decimali con la virgola;
  - "Copia" sul nome del file (solo admin, come oggi).
- **Più versioni:** una pastiglia per versione.
- **Errore:** "Non riesco a leggere le info del file" e "Riprova".
- **TV:** finestra, niente nome del file; focus su "Chiudi", Su/Giù scorrono.

## 7. Amici, consigli, notifiche (bozza `social.html`)

### 7.1 Notifiche (`inbox_panel.dart`)

- **Gruppi per giorno:** "Oggi", "Ieri", "Questa settimana", "Prima" (dalla data della voce).
- **Per gli admin**, un selettore "Per te · Server" (pastiglie col numero):
  - "Server" raccoglie gli avvisi di download, spazio, riavvio e recupero account, e le richieste in attesa;
  - "Per te" tutto il resto;
  - la divisione usa i tipi che il plugin manda già;
  - chi non è admin non vede il selettore.
- **Righe tutte uguali** (l'elemento forte):
  - a sinistra, avatar 40 di chi la manda con la locandina piccola sovrapposta in basso a destra; per gli avvisi di sistema un cerchio con l'icona (rosso solo per lo spazio quasi pieno);
  - una frase con nome e titolo in grassetto;
  - sotto, ora e stato dal vivo ("adesso · 2 nel party" se il dato c'è, "Ci sei già", "Party finito");
  - a destra l'azione visibile ("Unisciti", "Apri", "Riproduci").
  - Tutta la riga si tocca e apre, come oggi la parte di testo.
  - L'invito al watch party, l'invito al Match e l'annuncio, oggi senza tocco, aprono rispettivamente il party, la sala e niente.
- **Togliere una riga:** una ✕ sempre visibile al 40% di opacità, piena col passaggio o col focus. Non c'è un ⋯: l'unica voce sarebbe "Togli dalla lista".
- **Letto:** come oggi (il plugin segna lette fino all'ultima voce). Le non lette di questa apertura hanno il pallino e un fondo appena più chiaro fino alla chiusura.
- **"Svuota tutto"** diventa sul posto "Svuota tutto? Sì, svuota" per 4 s, e svuota la vista scelta.
- **Novità** (nuovi titoli): restano le 5 righe e "Mostra tutto (N)", con locandina e codice dell'episodio.
- **Stretto:** la pagina `/inbox` con "Svuota tutto" nella barra.
- **Vuoto:** "Niente di nuovo. Gli inviti e i consigli degli amici arrivano qui."

### 7.2 Amici (`friends_panel.dart`)

- **Testa:** "Amici" e "N online".
- **Sezioni:**
  - "Da rispondere (N)": stesso numero del badge, "Accetta" / "Rifiuta";
  - "Online";
  - "Offline", con la scritta "Offline";
  - "Richieste inviate (N)", chiusa in fondo, "In attesa" / "Annulla".
- **Riga:**
  - avatar 32 col pallino;
  - nome e attività col formato giusto: "Sta guardando L'Istituto · S1:E4";
  - azione come oggi ("Unisciti" / "Guarda insieme");
  - ⋯ con "Invita a un Match" (apre la sala come "Apri un Match" e invita l'amico con `MatchRoomController.invite`) e, separata in rosso, "Rimuovi dagli amici" con la conferma in riga di oggi.
- **Piede:** "Ho un codice" e "Apri un Match" scendono qui (oggi sono link in cima, `:140-164`).
- **Ricerca:**
  - indicatore nel campo e una riga grigia mentre cerca;
  - solo risultati, senza sezioni né link;
  - le stesse parole del pannello ("Accetta" / "Rifiuta" anche qui, "In attesa" / "Annulla", "✓ Amici").
- **Vuoti:**
  - nessun amico: "Non hai ancora amici. Cerca qualcuno per nome qui sopra.";
  - nessun risultato: "Nessuno si chiama così. Controlla il nome o chiedi il suo codice."

### 7.3 Consiglia a… (`recommend_panel.dart`)

- **Testa:** "Consiglia" con locandina e titolo.
- **Ricerca** tra gli amici e "Scegli gli online".
- **Destinatari** come griglia di avatar grandi (caselle alte almeno 44), al posto dei `CheckboxListTile`:
  - toccarne uno lo accende con l'anello oro e la spunta;
  - chi non può vederlo resta spento e lo dice sotto il nome.
- **Messaggio e limiti:**
  - contatore solo quando mancano 20 caratteri;
  - "Al massimo 30 amici alla volta" solo quando ci arrivi.
- **Piede:** "Invia a 2 amici" (il pulsante conta). Spento, sotto dice "Scegli almeno un amico".
- **Esito:** la snackbar di oggi.
- **TV:** messaggio in cornice (§3.5).

### 7.4 Carte d'invito (`invite_card_frame.dart`, `friend_request_card.dart`)

- **Una forma sola per watch party, Match e amicizia:**
  - avatar di chi invita, con la locandina se c'è un titolo o il simbolo se è Match o amicizia;
  - una frase;
  - due azioni: "Unisciti" / "Più tardi"; per l'amicizia "Accetta" / "Rifiuta".
- **"Più tardi"** chiude la carta; l'invito resta nelle Notifiche.
- **Barretta dei 10 secondi:** una barretta oro in fondo mostra quanto manca e si ferma col puntatore o col focus sopra. Con movimento ridotto la carta non si chiude da sola.
- **Una frase per invito**, uguale nella carta, nel pannello e nel toast di Windows (`notifInviteTitle`):

  | Invito | Frase |
  |---|---|
  | Watch party | "{nome} ti invita a guardare {titolo}" |
  | Match | "{nome} ti invita a un Match" |
  | Amicizia | "{nome} vuole essere tuo amico" |

- **Più carte insieme:** il primario oro va solo alla più nuova.

## 8. Cerca (bozza `cerca.html`)

### 8.1 Prima di scrivere

- **Campo** alto 56 con la lente, suggerimento "Titolo, attore o regista":
  - ✕ quando c'è testo (svuota e ridà il focus);
  - Esc svuota, Invio apre il miglior risultato;
  - in TV niente ✕: OK sulla cornice riapre la tastiera.
- **"Ricerche recenti":**
  - pastiglie con ✕ e "Cancella"; gli ultimi 8 termini in `SharedPreferences`, solo sul dispositivo (lo dice una riga);
  - si salvano aprendo un risultato o con Invio, non a ogni lettera.
- **"Prova con un genere":** i generi del catalogo (`/Items/Filters2` + `genreLabel`). Una pastiglia apre il catalogo Film o Serie (le due pastiglie a destra) col genere scelto.
- **"Aggiunti di recente":** la riga della Home, con la griglia del catalogo.

### 8.2 Risultati

- **Miglior risultato** (l'elemento forte): una carta larga col fondale, contenuto:
  - "Miglior risultato" in oro;
  - nome in Bebas col pezzo scritto sottolineato in oro;
  - una riga di dati, due righe di trama;
  - "Riproduci" e "Scheda".
- **Punteggio** (una funzione pura, testata):

  | Punteggio | Quando |
  |---|---|
  | 0 | il titolo comincia col termine, saltando articoli ("L'", "Il", "La", "The"…) |
  | 1 | una parola del titolo comincia col termine |
  | 2 | il titolo lo contiene |
  | 3 | lo contiene solo il titolo originale |

  - Vince il più basso, purché sia 0 o 1. A parità vincono prima i titoli già iniziati, poi le serie.
  - Una persona vince solo se il nome comincia col termine e nessun titolo ha 0.
  - Senza 0 o 1 la carta non c'è.
- **Persone accanto al miglior risultato** (desktop):
  - le prime sei, ognuna con ruolo, titolo per cui è nota e numero di titoli;
  - una chiamata `/Items?personIds=…&limit=1&sortBy=CommunityRating` ciascuna, dopo i risultati; il ruolo viene dal `People` di quel titolo;
  - si riordinano per numero di titoli.
- **Sezioni** in ordine di punteggio del loro primo elemento:
  - ciascuna col conteggio (`TotalRecordCount`, oggi ignorato) e "Vedi tutti" quando la lista è tagliata;
  - "Vedi tutti" apre il catalogo con la ricerca già scritta; per le persone una lista con la stessa griglia;
  - dentro una sezione i titoli col punteggio 3 vanno in fondo con la riga "Titolo originale: …".
- **Griglia** del catalogo (`catalogCellExtent`, margini 16/32/24, titoli di sezione 26/30/22), al posto delle carte 150 fisse in un `Wrap`.
- **"Da richiedere":**
  - sottotitolo "Trovati su TMDB, non ancora su WonderFlix: chiedili all'admin";
  - una riga sola, solo titoli con locandina, niente carte "Su WonderFlix";
  - su ogni carta "+ Richiedi" o lo stato ("Richiesto", "In arrivo", "In parte"); "Richiedi" apre la scheda di richiesta di oggi.
- **Mentre si affina:** una linea oro sottile sotto il campo mentre `SearchState.loading`; i risultati vecchi si attenuano e non si aprono.

### 8.3 Telefono, vuoto, TV

- **Telefono:**
  - margini 16, due colonne;
  - miglior risultato a tutta larghezza, persone in una fila che scorre;
  - quattro titoli per sezione e "Vedi tutti i 15 film";
  - "Da richiedere" in una fila.
- **Nessun risultato:**
  - "Nessun titolo per “{termine}”. Controlla l'ortografia o prova col titolo originale.";
  - sotto, subito, i risultati da richiedere; se non c'è nemmeno quello, la frase finisce con "nemmeno su TMDB".
- **TV:**
  - focus sulla cornice del campo;
  - prima di scrivere, due file (recenti e generi);
  - risultati in file orizzontali, una per sezione: il miglior risultato è la prima carta (larga) della sua fila, l'ultima carta è "Vedi tutti";
  - margine 24, titoli 22.

## 9. Prima dell'app (bozza `accesso.html`)

### 9.1 Chi guarda? (`profiles_screen.dart`, `avatar_dialog.dart`)

- **Pagina:**
  - avatar 132 e titolo 56 su desktop; sul telefono due colonne con avatar 96;
  - sotto le carte "4 profili su 5 su questo dispositivo".
- **Limite:** con 5 profili il "+" lascia il posto a "5 profili su questo {dispositivo}: rimuovine uno per aggiungerne un altro".
- **Gestisci profili:**
  - il titolo diventa "Gestisci profili";
  - gli avatar si spengono e ogni carta ha due pulsanti scritti, "Modifica" e "Rimuovi", raggiungibili uno per uno in TV.
- **TV:** focus di §3.5.
- **Testi:**

  | Oggi | Nuovo |
  |---|---|
  | "Rimuovere {nome} da questo PC?" | "da questo PC / browser / telefono / TV", secondo la piattaforma |
  | Scheda "Dal PC" | "Dal PC" (Windows), "Dal telefono" (Android), "Carica immagine" (web); niente scheda in TV |
  | Titolo "Immagine del profilo" | "Immagine di {nome}", con l'immagine attuale accanto |
  | Scheda "Rimuovi" | sparisce; sotto l'immagine attuale c'è il pulsante "Togli immagine" |

### 9.2 Accesso (`login_screen.dart`, `password_login_form.dart`, `quick_connect_panel.dart`)

- **Titolo:**
  - "Accedi a WonderFlix";
  - con sessione scaduta "Bentornato, {nome}", avatar, nome già scritto e "Non sei tu?";
  - l'avviso di sessione scaduta è neutro (grigio con orologio), non il riquadro rosso.
- **Campi:**
  - etichetta sopra;
  - `AutofillGroup` con `autofillHints` username/password;
  - occhio per mostrare la password.
- **Pannello:** "Accedi" in frase normale, l'altezza cresce col contenuto (niente 300 fisso, `login_screen.dart:229`).
- **Quick Connect:**
  - codice in Bebas 68 tabellare;
  - due passi numerati col nome vero della voce: "Su un dispositivo già collegato apri Impostazioni › Account › Autorizza un dispositivo" e "Scrivi il codice e premi Autorizza";
  - in TV, "Scrivi all'admin" diventa testo ("Chiedi all'admin di autorizzarti").

### 9.3 Server irraggiungibile (`unreachable_screen.dart`)

- **Tre casi**, dal tipo di errore che l'app riceve già:

  | Risposta | Titolo | Lampade |
  |---|---|---|
  | Nessuna risposta (connessione, timeout) | "Sei offline" | prima rossa, seconda spenta |
  | 503 (Jellyfin in avvio) | "Il server si sta avviando" | verde, oro |
  | 502/504 dal proxy | "Il server non risponde" | verde, oro |

  - "Il server si sta avviando" aggiunge "Dopo un riavvio può volerci anche mezz'ora".
  - "Il server non risponde" è senza la frase sulla mezz'ora.
- **Catena di due lampade** in cima (l'elemento forte): la tua connessione, il server.
- **Attesa:**
  - "Riprovo tra 12 s" con cifre tabellari e una linea oro che si riempie in 15 s (ferma con movimento ridotto);
  - un "Riprova ora" a mano fa ripartire il conto (oggi no, `:146`);
  - "In attesa da 6 min" nelle attese lunghe.
- **Pulsanti:** "Riprova ora" primario, col focus iniziale in TV; "Cambia profilo".
- **Telefono:** tutto centrato, margini 16, pulsanti a tutta larghezza.
- **Splash** (`splash_screen.dart`): dopo 10 s compaiono "Apro il profilo di {nome}…" e "Cambia profilo".

### 9.4 Aggiornamento (`update_banner.dart`, `mandatory_update_screen.dart`)

- **Banner:** sotto i 640 px va su due righe, titolo sopra e pulsanti sotto; "Riavvia ora" resta l'unico primario.
- **Schermata obbligatoria:**
  - "Aggiornamento necessario" in frase normale;
  - "Download in corso…" senza "0%" finché la percentuale non c'è.

## 10. Testi

- Le chiavi nuove o cambiate stanno in `app_it.arb` e `app_en.arb`, raccolte per area. Plurali e generi con ICU, come le altre pagine.
- Le chiavi che non servono più si tolgono se non le usa nessuno.
- Da cambiare in tutta l'app:
  - le etichette in maiuscolo di §3.1;
  - `friendsWatchingEpisode` col formato `episodeCode`;
  - "Tagline" diventa "Frase di lancio";
  - "Carica dal PC…" diventa "Carica un file…";
  - "Conferma" nei pulsanti di §6.3 e "Svuota" / "Conferma" nelle Notifiche (§7.1).

## 11. Da verificare prima di costruire

Ogni punto ha una strada di riserva che non richiede il plugin.

| Cosa | Come | Se no |
|---|---|---|
| "Segna la stagione come vista" segna anche gli episodi | `POST /UserPlayedItems/{seasonId}` su una stagione di prova, poi `UserData` degli episodi | un `POST` per episodio |
| Jellyfin aggiorna `DateLastRefreshed` a fine refresh | refresh di un titolo e lettura prima/dopo | Aggiorna metadati resta con "Aggiornamento avviato" |
| Media3 regge `setRate` | prova sulla Fire Stick | Velocità solo fuori dalla TV |
| L'invito al watch party porta il numero dei presenti | DTO dell'invito | niente "2 nel party" |
| `/Persons` restituisce `TotalRecordCount` | chiamata di prova | il conteggio delle persone sparisce |
| "Riprova" nell'errore del player in TV è irraggiungibile oggi | Fire Stick, video che fallisce | (è il difetto: si corregge comunque) |
| Generi reali del server | `/Items/Filters2?recursive=true` | si traducono solo quelli presenti |

## 12. Lasciato a chi costruisce

- Struttura dei widget, misure fini partendo dalle bozze, nomi delle chiavi arb.
- **Test**, per area:
  - **Comuni:**
    - guscio delle finestre: testa, piede, pagina intera nello stretto, finestra in TV, "Buttare le modifiche?" solo con modifiche;
    - pannelli: una sola chiusura nello stretto, ordine dei pulsanti in alto;
    - `genreLabel` coi generi nuovi;
    - nessun campo nudo in TV: un test per ogni campo di §3.5, Giù lo passa senza aprire la tastiera.
  - **Player:**
    - tooltip con i tasti;
    - tempo che resta e ora di fine (orologio finto);
    - `?` apre e chiude la scheda dei tasti;
    - Velocità che resta 1× in Guarda insieme;
    - pannelli laterali in TV a 960×540;
    - focus su "Riprova" nell'errore in TV;
    - "Riproduci tra N s" e "Guarda i titoli" nella carta;
    - trailer con un solo "Chiudi".
  - **Scheda:**
    - riga dei dati con due generi tradotti;
    - ordine delle azioni e ⋯ ultimo;
    - Visto per episodio e per stagione;
    - biglietto del prossimo episodio;
    - voti sotto le schede;
    - parola del voto;
    - piede del pannello voto;
    - persona in TV;
    - stati vuoti di persona e saga.
  - **Strumenti:**
    - menu con gruppi e puntini, TV con le sue voci;
    - Segnala: suggerimento senza tipo, "Aggiorna la segnalazione";
    - Modifica: "Bloccato", errore sotto la data, conteggio;
    - Identifica: sblocco spento di serie, "Attuale", nessun "Annulla" che torna indietro;
    - Locandina: niente cambia prima della conferma;
    - Sottotitoli: ricerca all'apertura, conferma che nomina la traccia;
    - Info: errore con "Riprova".
  - **Social:**
    - gruppi per giorno;
    - "Per te · Server" solo per gli admin;
    - riga con avatar e locandina;
    - ✕ visibile;
    - Amici: sezioni e numero uguale al badge, voci del ⋯;
    - Consiglia: griglia, pulsante che conta, motivo quando è spento;
    - una frase per invito nei tre posti.
  - **Cerca:**
    - punteggio del miglior risultato (articoli, parola, contiene, originale, persona);
    - recenti (massimo 8, salvati solo su Invio o apertura);
    - conteggi e "Vedi tutti";
    - due colonne a 390;
    - nessun risultato con i da richiedere sotto;
    - linea oro durante `loading`.
  - **Accesso:**
    - tre stati dell'irraggiungibile dal tipo di errore;
    - conto che riparte dopo "Riprova ora";
    - "Bentornato" con sessione scaduta;
    - testi per piattaforma;
    - banner su due righe sotto 640.
  - **Misure:** nessun overflow a 1280×800, 390×780 e 960×540.

## 13. Ordine di lavoro

Un piano per fase. Ogni fase è indipendente e si prova a mano da sola:

1. **Correzioni e pezzi comuni:** §3 tutto, i testi di §10, gli errori in TV di §4.5–§4.6. Da sola vale già una release.
2. **Player e trailer** (§4).
3. **Scheda** (§5).
4. **Menu ⋯ e strumenti** (§6), sopra il guscio della fase 1.
5. **Amici, consigli, notifiche** (§7), sopra il guscio dei pannelli della fase 1.
6. **Cerca** (§8).
7. **Prima dell'app** (§9).

## 14. Release

Esce nella 0.42.0, non ancora pubblicata, insieme a Home, Stasera e Match: una riga per fase nella checklist di `docs/RELEASING.md`. Nessun plugin.

Se i tempi stringono, la fase 1 esce nella 0.42.0 e le altre nella versione dopo. Decide l'utente prima del piano.

# WonderFlix — Calendario, nuova UI

Data: 2026-11-13. Bozza approvata: [`2026-11-13-calendario-bozze/calendario.html`](2026-11-13-calendario-bozze/calendario.html) (la pagina di com'è oggi è `oggi.jpg`, accanto). Spec di partenza: [`2026-10-22-wonderflix-calendario-uscite-design.md`](2026-10-22-wonderflix-calendario-uscite-design.md) (spec S, §7). Dove questa spec non dice nulla vale la spec S.

## 1. Perché

La pagina Calendario (app 0.20.0) funziona, ma a guardarla:

- passato e futuro hanno lo stesso peso: il 26 ottobre si legge come il 27 novembre;
- film e serie si distinguono da due fondi scuri quasi uguali (`#2B2418` e `#1D2630`) e da un'icona da 12 px;
- il puntino verde "già sul server" sta su quasi tutte le voci passate, quindi non dice niente; l'informazione utile è il contrario (doveva arrivare e non c'è);
- il testo è da 11 px anche a schermo intero, il "+2" si perde;
- l'elenco di un giorno è in ordine di nome e non di ora (03:00, 09:00, 15:30, 18:00, 18:40, 09:00, 03:00) e mostra "TBA" come titolo dell'episodio;
- la domanda più comune ("cosa esce nei prossimi giorni?") richiede di leggere una griglia ripetitiva (Black Clover ogni sabato, The Institute ogni domenica);
- sul telefono la griglia a puntini rende poco.

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- Il passato si spegne, oggi spicca, il futuro è a piena luce.
- Film e serie si distinguono a colpo d'occhio.
- Un segno solo per "doveva arrivare e non c'è"; niente segno per ciò che è arrivato (tranne oggi).
- Una vista **"Prossimi 7 giorni"** a elenco con le locandine; sul telefono è quella di partenza.
- L'elenco di un giorno in ordine di ora, con lo stato per riga e senza "TBA".

**Non obiettivi**
- Niente modifiche al plugin (l'endpoint `Upcoming/Calendar` accetta già periodi fino a 42 giorni, `CalendarService.MaxDays`).
- Niente TV: `/calendar` resta in `_tvExcluded` (`router.dart`).
- Il titolo "CALENDARIO" resta, come "RICHIESTE" nella pagina Richieste (decisione dell'utente; il punto 9 della bozza cade).
- Niente avvisi, filtri per tipo, o "solo le mie serie".

**Anti-obiettivi**
- Lo stile non cambia: Noir & Oro, Bebas Neue per i titoli, Inter per il resto. Nessun colore nuovo oltre a quello delle serie (§4.1).
- Il cerchio "non ancora arrivato" non deve accendersi per ciò che non è ancora uscito.

## 3. Strade considerate

| Strada | Pro | Contro | Scelta |
|---|---|---|---|
| **A. Modificare i widget esistenti** (`calendar_month_grid.dart`, `calendar_day_dialog.dart`, `calendar_screen.dart`) e aggiungere un widget per i 7 giorni; vista nell'indirizzo; un provider nuovo per i 7 giorni | riusa griglia, tastiera, semantica e test; nessuna dipendenza | — | **scelta** (approvata dall'utente) |
| B. Pacchetto calendario (`table_calendar`, …) | griglia pronta | dipendenza nuova, stile da piegare al Noir & Oro, tastiera e semantica da rifare | scartata |
| C. 7 giorni ricavati dal mese già caricato | una richiesta in meno | a fine mese i 7 giorni escono dalla griglia: servirebbe comunque una seconda richiesta, con più logica | scartata |

## 4. Design

### 4.1 Colori e segni

- Film: barretta **oro** (`WfColors.gold`). Serie: barretta **azzurra** `#7E9CBD`, token nuovo `WfColors.calendarSeriesMark` (stessa tinta del vecchio fondo delle serie, più chiara). Il token `calendarSeries` sparisce (lo usa solo la griglia); `calendarMovie` resta (lo usa anche `download_search_page.dart`).
- "Non ancora arrivato": cerchio vuoto oro, 9 px, bordo 1,5 px.
- "Sul server": ✓ verde (`WfColors.online`), solo nella casella di oggi, nell'elenco del giorno e nei 7 giorni.
- Legenda in alto a destra (solo fuori dallo stretto): `▍Film  ▍Serie  ○ Non ancora arrivato`.
- Il colore non è l'unico segno: la legenda, il tooltip ("Film: Odissea") e la semantica per gli screen reader ("Film, Odissea, non ancora arrivato") lo dicono anche a parole. L'icona film/serie dentro la voce sparisce (mia scelta: con la barretta e la legenda è un doppione che ruba 16 px).

### 4.2 Stato di una voce

Funzione pura in `calendar_logic.dart`, con `now` passato da fuori (`clock.now()`):

- **uscita**: un episodio quando `airDate <= now`; un film quando il suo giorno (UTC, come oggi in `entriesByDay`) è oggi o prima.
- stato `arrived` = uscita e `onServer`; `missing` = uscita e non `onServer`; `upcoming` = non ancora uscita.
- Una voce raggruppata (serie ×n): `missing` se almeno un episodio uscito non è sul server; altrimenti `arrived` se tutti sono usciti; altrimenti `upcoming`.

### 4.3 Intestazione

```
CALENDARIO                                                     (resta com'è)
NOVEMBRE 2026   ‹  ›  [Oggi]        ▍Film ▍Serie ○ Non ancora arrivato   [ Mese | Prossimi 7 giorni ]
```

- Il pulsante a due voci **Mese | Prossimi 7 giorni** (un `SegmentedButton` o due `TextButton` col segno oro sotto quello attivo, come nella bozza) cambia l'indirizzo (§4.7).
- Nella vista 7 giorni spariscono mese, frecce e "Oggi"; restano legenda e pulsante.
- Nello stretto: niente legenda; il pulsante va su una riga sua, largo quanto la pagina, sotto il titolo; mese e frecce sotto, solo nella vista Mese.
- "Oggi" spento quando si guarda il mese di oggi (com'è adesso).

### 4.4 Griglia del mese (fuori dallo stretto)

- Intestazioni dei giorni allineate **a sinistra** come numeri e voci (padding 8); sabato e domenica un po' più spenti (`creamMuted` al 45%).
- **Caselle**
  - mese corrente, futuro: fondo `surfaceHigh` (com'è);
  - mese corrente, passato (giorno < oggi): fondo `surface`, numero e voci al 42% di opacità, **tranne le voci `missing`**, che restano a piena luce;
  - giorni dei mesi vicini: fondo trasparente con bordo `surface`, numero e voci al 30%;
  - **oggi**: bordo oro 2 px, numero in una pillola oro piena (testo `bg`) seguito da "Oggi" in oro.
- **Voci**: altezza 20 (com'è), barretta 3 px a sinistra, testo 12,5 px `cream`, "×n" in `creamMuted` subito dopo il nome. A destra:
  - `missing`: il cerchio oro (in ogni casella);
  - nella casella di oggi: ✓ verde per `arrived`, l'ora (`HH:mm`, cifre tabellari) per `upcoming` con un'ora (gli episodi);
  - altrove niente.
- **Ordine delle voci** nella casella: film per nome, poi serie per ora del primo episodio, poi per nome (§4.6, stessa funzione).
- **Troppe voci**: come adesso (almeno 1, `minEntries`), ma la riga in più dice **"+{n} altre"** in `cream` al 75%, 12,5 px; sottolineata al passaggio del mouse sulla casella.
- **Passaggio del mouse**: la casella con voci prende il bordo `#3A3A3A`; una voce apribile prende il fondo `border` (`#262626`). Ogni voce ha un `Tooltip` con "Film: {titolo}" / "Serie: {titolo} ×n" (attesa 500 ms).
- Clic, tastiera (frecce, Invio) e semantica restano come nella spec S §7.2; il bordo crema del fuoco della tastiera resta e vince su quello di oggi.

### 4.5 Elenco del giorno (finestra, fuori dallo stretto)

- Titolo come adesso ("Venerdì 13 novembre") con accanto una pillola oro **"Oggi"** o **"Domani"** quando vale; negli altri giorni nessuna pillola (la bozza ha "Tra 7 giorni" nel testo, ma non serve).
- Sotto il titolo: **"{n} uscite · {k} già sul server"** (la seconda parte solo con k > 0). Le uscite si contano per riga (un blocco "E01–E03" è una riga).
- Righe in ordine §4.6; a destra l'ora (episodi) e lo stato: "Sul server" ✓ verde, "Non ancora arrivato" con il cerchio oro, niente per `upcoming`.
- Titolo dell'episodio **"TBA"** o **"TBD"** (senza badare a maiuscole e spazi) = nessun titolo: la riga mostra solo `S01E08`.
- Il resto come spec S §7.3 (locandina 34×51, clic che chiude e apre, righe senza destinazione senza clic).

### 4.6 Ordine

Una sola funzione per griglia, elenco del giorno e 7 giorni: prima i film (per nome), poi gli episodi per ora di uscita, a parità di ora per nome della serie, poi per numero di stagione ed episodio. Per la griglia l'ora di una voce raggruppata è quella del suo primo episodio.

### 4.7 Indirizzo e vista di partenza

- `/calendar?view=week` → vista 7 giorni.
- `/calendar?month=YYYY-MM` → vista Mese su quel mese (le frecce e "Oggi" usano già questo indirizzo).
- `/calendar` senza nulla → **7 giorni nello stretto** (`FormFactor.compact`), **Mese** altrove. La barra in basso del telefono e la voce in alto portano qui.
- Il pulsante "Mese" porta a `calendarRoute(mese di oggi)`, "Prossimi 7 giorni" a `/calendar?view=week`. Un `view` sconosciuto vale come assente.
- La pagina si rifà a ogni indirizzo (chiave = indirizzo, com'è adesso).
- Il cambio di vista usa `context.go`, come le frecce del mese e le schede di Richieste (mia scelta): sul web l'Indietro del browser torna alla vista di prima; su Windows il tasto Indietro del mouse non torna tra le viste, come già tra le schede di Richieste.

### 4.8 Vista "Prossimi 7 giorni"

- I giorni da oggi a oggi + 6, ognuno con la sua intestazione:
  - oggi: **"Oggi"** in Bebas oro 24 + "venerdì 13 novembre" in `creamMuted` 13;
  - domani: **"Domani"** in Bebas crema + la data;
  - gli altri: **"Domenica 15 novembre"** in Bebas crema;
  - giorno senza uscite: la sua intestazione e sotto "Nessuna uscita" in `creamMuted`.
- Righe come l'elenco del giorno (§4.5) ma con locandina 40×60 (34×51 nello stretto), una per film e per episodio o blocco, ordine §4.6. Nello stretto lo stato è solo il segno (✓ o cerchio), senza testo; la semantica ha il testo.
- Larghezza massima 720 px, allineata a sinistra sotto l'intestazione (fuori dallo stretto).
- Clic su una riga: come spec S §7.4. Le righe sono raggiungibili con Tab (InkWell); nessuna tastiera a frecce propria.
- Tutta la settimana vuota e nessun servizio in errore: sotto le intestazioni niente "Nessuna uscita" ripetuto, ma un solo "Nessuna uscita nei prossimi 7 giorni".
- Errori: come la vista Mese (spec S §7.6): righe "Le serie/I film non si possono caricare ora", pagina d'errore se tutti i servizi accesi falliscono.
- Dati: provider nuovo `calendarWeekProvider` (autoDispose, senza parametri), che chiede `calendar(oggi, oggi + 7)` (`end` escluso) con gli stessi controlli di `calendarPageProvider` (disponibilità, utente). Oggi = `dayKey(clock.now())` all'apertura della pagina.

### 4.9 Telefono, vista Mese (stretto)

- "Stretto" = `FormFactor.compact` (finestra sotto i 1024 px: telefono, tablet, web in una finestra stretta). Nello stretto valgono **sempre** puntini ed elenco sotto la griglia, qualunque sia la larghezza della casella (mia scelta: un ramo solo). Fuori dallo stretto la regola dei 96 px (`compactCellWidth`) resta come protezione: puntini, ma con la finestra del giorno.
- La griglia resta a puntini (caselle alte 48), ma:
  - puntini oro per i film, azzurri per le serie (`calendarSeriesMark`); una voce `missing` è un cerchio vuoto oro; al massimo 4 segni;
  - passato e mesi vicini spenti come §4.4, oggi col bordo oro e il numero in oro.
- Toccare un giorno **non apre la finestra**: lo seleziona (fondo `#2A2418`) e le sue uscite compaiono **sotto la griglia**, con l'intestazione del giorno e le righe dei 7 giorni (§4.8). All'apertura è selezionato oggi se è nella griglia, altrimenti il primo del mese. Un giorno senza uscite si può selezionare e mostra "Nessuna uscita". Anche i giorni dei mesi vicini si possono selezionare (i dati coprono tutti i 42 giorni).
- Griglia ed elenco scorrono insieme (una sola colonna che scorre); la griglia non scorre più da sola.
- Fuori dallo stretto la finestra del giorno resta.

### 4.10 Testi nuovi (ARB it + en)

| Chiave | it | en |
|---|---|---|
| `calendarViewMonth` | Mese | Month |
| `calendarViewWeek` | Prossimi 7 giorni | Next 7 days |
| `calendarMore` (cambia) | +{count} altre | +{count} more |
| `calendarNotArrived` | Non ancora arrivato | Not here yet |
| `calendarTomorrow` | Domani | Tomorrow |
| `calendarNoReleases` | Nessuna uscita | No releases |
| `calendarWeekEmpty` | Nessuna uscita nei prossimi 7 giorni | No releases in the next 7 days |
| `calendarDaySummary` | {count, plural, =1{1 uscita} other{{count} uscite}} | {count, plural, =1{1 release} other{{count} releases}} |
| `calendarDayOnServer` | {count} già sul server | {count} already on the server |

"Oggi" usa `calendarToday`, "Film"/"Serie" della legenda `requestsKindMovie`/`requestsKindSeries`, "Sul server" `calendarOnServer`. Le due parti del riassunto si uniscono con " · ".

## 5. File toccati

- `lib/app/theme.dart`: `calendarSeriesMark`, via `calendarSeries`.
- `lib/features/calendar/calendar_logic.dart`: stato (§4.2), ordine (§4.6), "TBA", periodo dei 7 giorni.
- `lib/features/calendar/calendar_navigation.dart`: `view=week`, rotta della settimana, lettura della vista.
- `lib/features/calendar/calendar_providers.dart`: `calendarWeekProvider`.
- `lib/features/calendar/calendar_screen.dart`: intestazione, pulsante della vista, legenda, scelta della vista, telefono con elenco sotto la griglia.
- `lib/features/calendar/calendar_month_grid.dart`: caselle, voci, puntini, "+n altre", passaggio del mouse, selezione nello stretto.
- `lib/features/calendar/calendar_day_dialog.dart`: ordine, stato, riassunto, "TBA"; la riga diventa un widget condiviso con i 7 giorni.
- nuovo `lib/features/calendar/calendar_week_view.dart`: la vista 7 giorni e l'elenco di un giorno sotto la griglia.
- `lib/app/router.dart`: passa `view` allo schermo.
- `l10n/app_it.arb`, `l10n/app_en.arb`.
- Test in `test/features/calendar/` (aggiornare gli esistenti: colori dei puntini, ordine, "+n"; nuovi: stato, ordine, "TBA", indirizzo e vista di partenza, 7 giorni, elenco sotto la griglia nello stretto).
- `docs/RELEASING.md`: la riga della prova a mano, marcata "app 0.42.0". Esce con la 0.42.0 ancora da pubblicare (decisione dell'utente): la versione in `pubspec.yaml` non cambia.

## 6. Prova a mano

- Finestra intera e minima (1024×640): passato spento, oggi in pillola, barrette, cerchio su una voce uscita e non sul server, ✓ e ore nella casella di oggi, "+n altre", tooltip.
- Elenco del giorno di oggi e di un giorno affollato: ordine per ora, niente "TBA", riassunto.
- Pulsante Mese / Prossimi 7 giorni, frecce del mese; sul web l'Indietro del browser tra le due viste.
- Web su iPhone: si apre sui 7 giorni; Mese → tocco su un giorno → elenco sotto la griglia; scorrimento unico.
- Fire TV: nessun cambiamento (il Calendario non c'è).

## 7. Lasciato a chi costruisce

- Widget esatto del pulsante a due voci, purché somigli alla bozza e abbia il fuoco visibile da tastiera.
- Come dividere i widget tra i file, purché la riga di un'uscita sia una sola per finestra, 7 giorni e telefono.
- Tempi del tooltip e animazioni (nessuna richiesta).

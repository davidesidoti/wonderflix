# WonderFlix — "Cosa guardo stasera?" e Match, nuova UI

Data: 2026-11-16. Bozza: [`2026-11-16-stasera-match-bozze/stasera-match.html`](2026-11-16-stasera-match-bozze/stasera-match.html).

I dati della bozza sono veri: i filtri salvati di davide.sidoti (Film, Brutti), i titoli proposti davvero la sera del 16 novembre (Shrooms, Dr. Brain) e l'amica online (sara.lippolis). La pila del match è inventata, con titoli del server.

Codice di partenza:
- `features/tonight/` (`tonight_dialog.dart`, `tonight_filters_bar.dart`, `tonight_controller.dart`, `tonight_logic.dart`);
- `features/match/` (`match_screen.dart`, `match_members_bar.dart`, `match_swipe_deck.dart`, `match_card.dart`, `match_column.dart`, `match_celebration.dart`);
- `ui/ticket_card.dart` (il biglietto della Home, spec [`2026-11-15-home-ui-design.md`](2026-11-15-home-ui-design.md) §6.2).

Dove questa spec non dice nulla valgono la spec M (§8.4, "Cosa guardo stasera?") e la spec P ([`2026-10-14-wonderflix-match-film-design.md`](2026-10-14-wonderflix-match-film-design.md), Match).

## 1. Perché

L'utente ha chiesto di migliorare anche "Match" e "Cosa guardo stasera?", dopo la Home. Visti dal vivo il 16 novembre (app 0.41, uguali sul branch della Home):

- **I filtri pesano più del titolo.** Tre gruppi a segmenti Material e un menu: undici scelte in vista prima del titolo proposto. Con "Serie" la durata resta, spenta.
- **Generi in inglese.** `tonightMeta` non passa da `genreLabel`: Dr. Brain mostra "Science Fiction · Drama · Thriller". La carta del match usa la stessa riga.
- **"Un altro" cancella il titolo di prima.** Non si torna indietro.
- **Il dado gira, il titolo no.** L'unico movimento è l'icona in alto.
- **La sala del match non spiega.** "Match del film" anche con le serie; nessuna riga sulle regole; "Invita" sul bordo destro della pagina, lontano dal nome; chi è invitato vede solo "In attesa che…".
- **Voto con comandi piccoli** (icone da 28) e progressi in testo ("12/30"); la colonna dei match è un elenco in Inter, fuori dal linguaggio della Home.

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- I filtri diventano **una frase** con le parole che si cambiano, uguale nella finestra e nella sala.
- Il titolo proposto è al centro: locandina, generi in italiano, perché è stato scelto.
- I titoli già proposti si riprendono.
- La sala del match spiega le regole, mostra chi c'è (i posti) e mette "Invita" accanto al nome.
- Voto con comandi grandi e progressi visibili; i match sono biglietti, come Stasera nella Home.

**Non obiettivi**
- Nessun cambio al plugin, alle regole del match, alla pila, ai filtri disponibili e a come si salvano (`tonight.*` nel profilo).
- Match resta fuori dalla TV.
- Il pannello Amici tiene la sua voce "Match del film".

**Anti-obiettivi**
- Lo stile non cambia: Noir & Oro, Bebas Neue e Inter, nessun colore nuovo (il verde del sì e il rosso del no ci sono già: `WfColors.online`, `WfColors.error`).
- Fuori dalla TV il comportamento TV non cambia, e viceversa.

## 3. La frase dei filtri

Un widget nuovo, `AskSentence` (`features/tonight/ask_sentence.dart`), al posto di `TonightFiltersBar` nella finestra e nella sala. `TonightFiltersBar` si toglie.

### 3.1 Testo

Testo in Inter 21 (19 nella sala, 18 nello stretto), `creamMuted`; le parole che si cambiano in crema, semibold, sottolineate d'oro (2 px) con una piccola freccia oro, e vanno a capo come il testo.

**Finestra** (singolare), dopo "Stasera ":

| Parola | Valori |
|---|---|
| tipo | "un film" · "una serie" · "un film o una serie" |
| durata | "di qualsiasi durata" · "sotto i 90 minuti" · "sotto le 2 ore" |
| genere | "di ogni genere" · "di genere {genere}" |
| voto | "con qualsiasi voto" · "bello" / "bella" (serie) · "brutto" / "brutta" (serie) |

Esempio: "Stasera un film di qualsiasi durata, di ogni genere, brutto."

**Sala** (plurale), dopo "Si vota tra ":

| Parola | Valori |
|---|---|
| tipo | "film" · "serie" · "film e serie" |
| durata | come sopra |
| genere | come sopra |
| voto | "con qualsiasi voto" · "belli" / "belle" (serie) · "brutti" / "brutte" (serie) |

Esempio: "Si vota tra serie, di ogni genere, brutte."

- Con tipo "serie" la **durata non c'è** nella frase (oggi è un controllo spento). Con "un film o una serie" c'è e vale per i film, come oggi.
- La frase è: introduzione, tipo, poi " " e la durata seguita da ",", poi " " genere ",", poi " " voto ".". Senza durata: "tipo, genere, voto." In inglese la stessa costruzione con testi suoi ("Tonight a movie of any length, of any genre, rated badly.").
- Il genere usa le etichette di oggi (`tonightGenresProvider`, già in italiano). Un genere che non c'è più torna a "di ogni genere", come fa oggi la barra.

### 3.2 Cambiare una parola

Ogni parola è un pulsante che apre un menu sotto di sé (`PopupMenuButton` con `wfPopUpAnimation`, come gli altri menu dell'app). Le voci del menu sono le scelte scritte per intero: tipo "Film", "Serie", "Film e serie"; durata "Qualsiasi durata", "Meno di 90 minuti", "Meno di 2 ore"; genere "Tutti i generi" e i generi; voto "Qualsiasi voto", "Belli (7 o più)", "Brutti (5 o meno)". La scelta attuale è oro. Scegliere cambia il filtro (`setFilters`) e la frase.

- **TV:** ogni parola prende il focus (`TvFocusable`/il focus del pulsante), Sinistra/Destra passano tra le parole, OK apre il menu.
- **Sola lettura** (`readOnly: true`): le parole in crema, senza sottolineatura né menu.

## 4. "Cosa guardo stasera?"

### 4.1 La finestra (desktop)

Larga 760 (oggi 720). Dall'alto:
1. **Intestazione:** il dado oro e "Cosa guardo stasera?" in Inter 15 semibold `creamMuted`.
2. **La frase** (§3), margine 14 sopra e 22 sotto.
3. **Il titolo proposto**, alto almeno 258 (lo spazio resta mentre si pesca, come oggi):
   - a sinistra la **locandina** larga 172, angoli 8, ombra;
   - a destra: **perché** in oro 12,5 semibold ("Un film che non hai mai visto", "Una serie che non hai mai iniziato"); il **nome** in Bebas 46 (al massimo 2 righe); la **riga dei dati** `tonightMeta` con i generi tradotti (§6) e il voto oro ("★ 4,9"); la **trama**, al massimo 4 righe.
   - In cima alla finestra, dietro intestazione e frase, il **fondale** del titolo al 35%, sfumato verso il basso (alto 300). Cambia col titolo.
4. **Piede**, sopra una linea `border`: a sinistra "Già proposti" e fino a 3 locandine piccole (26 di larghezza) dei titoli proposti prima in questa finestra, dal più vecchio al più recente; a destra "Un altro", "Dettagli", "Riproduci" come oggi.

Stati (vuoto, errore, caricamento) come oggi, nello spazio del titolo.

### 4.2 Un altro e Già proposti

- "Un altro": il titolo attuale va in "Già proposti" (il più vecchio esce oltre i 3), il dado del pulsante fa un giro e il titolo nuovo entra salendo di 14 px in dissolvenza (450 ms, curva `emphasized`). Con le animazioni ridotte: niente giro né salita. Il dado dell'intestazione non gira più.
- Un clic su una locandina di "Già proposti" la riporta come titolo proposto; quello che c'era prende il suo posto in fondo alla fila.
- Cambiare un filtro svuota "Già proposti" (i titoli di prima non rispettano più i filtri).
- "Già proposti" vive nella finestra: chiusa la finestra, si perde.

### 4.3 Telefono e finestre strette

Una pagina, come oggi: frase (va a capo), locandina a tutta larghezza alta al massimo 330, perché, nome Bebas 38, dati, trama; "Già proposti"; in fondo "Un altro" e "Riproduci" affiancati e "Dettagli" a tutta larghezza sotto.

### 4.4 TV

La finestra larga 680, locandina 140, nome Bebas 38, trama 3 righe. Il focus parte da "Un altro". Su da lì porta alla frase. Le locandine di "Già proposti" prendono il focus.

## 5. Match

### 5.1 La pagina

- **Titolo** "Match" (Bebas 56 su desktop, 40 nello stretto) al posto di "Match del film".
- Sotto, in `creamMuted` 14, al massimo 62 caratteri per riga: "Votate gli stessi titoli, ognuno per conto suo: quelli che piacciono a tutti diventano un match. Chi ha aperto la sala sceglie da quale cominciare."

### 5.2 I posti

Un widget nuovo, `MatchSeats`, al posto di `MatchMembersBar`.
- Un posto è largo 68: una poltrona (56×62, angoli 14 in alto e 6 in basso, con una barretta sotto) e il nome sotto (11,5). Occupato: bordo e barretta oro, avatar da 36 dentro, nome crema. Libero: bordo tratteggiato `border`, "libero" in `creamMuted`.
- **Attesa:** gli 8 posti della sala (il massimo del plugin, `MatchRoom.MaxMembers`), sopra "In sala, {n} su 8".
- **Votazione:** solo i posti occupati; sotto ogni posto una barra di 3 px che si riempie d'oro con i voti e "12 su 30", o "finito" in oro quando ha votato tutto.

### 5.3 L'attesa

Desktop, due colonne (1,25 e 1, distanza 48):
- **A sinistra:** i posti; sotto "Amici online" e, per ogni amico, una riga: avatar 32, nome (almeno 160 di larghezza), **"Invita"** subito dopo (pulsante basso, `WfButton.secondary(small: true)`; poi "Invitato"). Nessun amico: "Nessun amico online".
- **A destra, chi ha aperto:** un riquadro `surface` con bordo, angoli 10: "Si vota tra" in piccolo, la frase (§3, plurale) e sotto "Inizia" con accanto il motivo: "Serve almeno un amico nella sala" finché manca, poi "Dopo l'inizio non entra più nessuno".
- **A destra, gli altri:** il riquadro con "In attesa che {nome} inizi…" (i filtri di chi ha aperto non arrivano a chi entra).

Nello stretto le due colonne vanno una sotto l'altra: posti, amici, riquadro.

### 5.4 La votazione (desktop)

- In alto il titolo "Match" a sinistra e i posti (§5.2) a destra, sulla stessa riga.
- Sotto, due colonne: il mazzo a sinistra, i match a destra (larga 360, distanza 40).
- **Carta verticale** 2:3, larga 270 (oggi orizzontale 1,5:1): la locandina, sfumata in basso, con il nome in Bebas 34, la riga dei dati (§6) e la trama su 3 righe. Le due carte sotto si vedono ruotate di ±4° e rimpicciolite, più scure.
- **"SÌ" e "NO"** durante il trascinamento come timbri: Bebas 34, bordo di 3, ruotati di ∓12°, verde (`WfColors.online`) e rosso (`WfColors.error`), in proporzione alla distanza come oggi.
- **Pulsanti tondi** da 64 (icone 28), bordo di 2 del loro colore al 60%, fondo `surface`; sotto, in piccolo, "No · ←" e "Sì · →". Distanza tra i due 44.
- Sotto: "Ne restano {n}" in `creamMuted` al 32%.
- Gesto, tasti, voto ottimista, fine pila, "Altri 30 titoli": come oggi.

### 5.5 I match come biglietti

- Intestazione "Piaciuti a tutti" in Bebas 26 con accanto "{n} match" (o "Ancora nessun match").
- Ogni match è un **biglietto** basso (84): fondale a sinistra (150), strappo tratteggiato con le tacche, poi nome e una riga: "Film · 1h 49m" o "Serie · 1 stagione"; quello scelto per primo ha il bordo oro e la riga "Parte per primo" in oro. Un clic sceglie il primo, come oggi (solo per chi ha aperto).
- "Piaciuti a quasi tutti" in Inter 12,5 semibold `creamMuted`, poi i quasi match come biglietti al 75% con la riga "{sì} sì su {di}".
- **"Avvia il party con {n} titoli"** a tutta larghezza della colonna, alto 44 (il numero: i match, più il quasi match scelto come primo). Un titolo: "Avvia il party con 1 titolo".
- La forma del biglietto (ritaglio con le tacche e strappo tratteggiato) è la stessa del biglietto della Home: si estrae da `ticket_card.dart` in un pezzo comune.

### 5.6 La votazione nello stretto

- Titolo e, a destra, gli avatar dei membri (30, bordo oro a chi ha finito); sotto una riga: "Tu {n} su {tot}" e per gli altri "{nome} ha finito" o "{nome} {n} su {tot}", separati da " · ".
- Carta larga 250, pulsanti con distanza 56 e senza le scritte sotto.
- "Piaciuti a tutti" con i biglietti in una fila orizzontale (biglietti da 250, fondale 104), poi "Avvia il party".

### 5.7 "È un match!"

Lo strato di oggi, con la locandina dentro un **biglietto**: locandina 2:3 larga 260, sotto la matrice col nome, strappo orizzontale tratteggiato con le tacche, bordo oro; entra ingrandendosi da 0,8 con una leggera rotazione (500 ms). Sotto "È un match!" in Bebas 64 oro e "Piace a tutti". Con le animazioni ridotte: compare senza movimento. Durata, chiusura e coda dei match come oggi.

## 6. Generi in italiano

`tonightMeta` passa ogni genere da `genreLabel` e toglie i doppioni dopo la traduzione (al massimo 3), come `heroMeta` della Home. Vale per la finestra e per la carta del match.

## 7. Testi

Nuove chiavi in `app_it.arb` e `app_en.arb` per: la frase (parole della finestra e della sala, voci dei menu), "Già proposti", i due perché, "Match" come titolo della pagina, la riga delle regole, "In sala, {n} su 8", "libero", "{n} su {tot}", "finito", "Dopo l'inizio non entra più nessuno", "Ne restano {n}", "Piaciuti a tutti", "{n} match", "{sì} sì su {di}", "Avvia il party con {n} titoli" (plurale), "Piace a tutti", "Tu {n} su {tot}", "{nome} ha finito", "No · ←", "Sì · →". Le chiavi che non servono più (segmenti dei filtri) si tolgono se non le usa nessuno.

## 8. Lasciato a chi costruisce

- Struttura dei widget; come la frase compone le parole (un modello con i pezzi, così i test controllano il testo).
- Misure fini, partendo dalla bozza.
- Test:
  - frase: tutti i tipi e voti, genere e maschile/femminile, singolare/plurale, durata assente con "serie", sola lettura senza pulsanti, menu che cambia il filtro;
  - "Già proposti": "Un altro" sposta il titolo, massimo 3, il clic lo riporta, i filtri svuotano;
  - `tonightMeta` con generi tradotti e senza doppioni;
  - posti: 8 in attesa con i liberi, solo occupati in votazione, "finito";
  - attesa: "Invita" accanto al nome, motivo di "Inizia" prima e dopo, chi è invitato vede l'attesa;
  - biglietti dei match: scelta del primo, quasi match, testo del pulsante col numero;
  - TV: il focus parte da "Un altro" e Su porta alla frase; OK su una parola apre il menu;
  - nessun overflow a 1280×800 e 390×780.

## 9. Release

Esce con la Home nuova nella 0.42.0 non ancora pubblicata: una riga nella checklist di `docs/RELEASING.md`. Nessun plugin.

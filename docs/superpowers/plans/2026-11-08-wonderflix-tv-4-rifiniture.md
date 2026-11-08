# WonderFlix TV 4: rifiniture dell'interfaccia

Punti aperti del piano 2 (`2026-11-07-wonderflix-tv-2-interfaccia.md`, "Da riprendere"). Solo sulla TV (`FormFactor.of(context).tv` / `androidTvProvider`): fuori dalla TV il comportamento resta identico. Branch `feat/tv-ui-rifiniture`.

## 1. Focus dopo il salvaschermo

Sintomo: dopo il salvaschermo del Fire Stick il focus torna su "Riproduci" del carosello (`features/home/hero_carousel.dart`, `_HeroSlide(autofocus: form.tv)`) invece che sull'ultimo elemento; un OK distratto fa partire un film.

- Prima la causa (superpowers:systematic-debugging): cosa succede al ritorno (ciclo di vita `paused/resumed`, righe della Home che si ricostruiscono, nodo con il focus smontato, autofocus della slide che prende lo scope vuoto). Riprodurla sul dispositivo se serve (vedi "Dispositivo").
- Decisione: il focus resta sull'elemento che l'aveva; se quel nodo non c'è più, va sul suo equivalente ricostruito (stessa riga, stessa posizione) o almeno non sul pulsante Riproduci. L'autofocus della slide vale solo alla prima apertura della Home (e quando nessuno ha il focus), non a ogni cambio di slide o ricostruzione.
- Anche il cambio automatico di slide non deve rubare il focus a un'altra riga.

## 2. Intestazione della pagina del titolo

`features/detail/detail_header.dart`: `detailHeaderHeight = 560` su uno schermo TV di 540 dp. Sulla TV l'intestazione si accorcia in modo che nella prima schermata si intraveda la riga delle stagioni (bozza `.superpowers/brainstorm/1947-1794062218/content/tv-detail-player.html`, sezione 1: titolo, meta, trama, pulsanti, poi le schede delle stagioni in basso). Altezza dalla dimensione dello schermo, non un numero fisso; titolo e pulsanti restano dentro l'overscan. Su PC e telefono 560 invariato.

## 3. Slide del carosello col telecomando

Decisione (del controller):
- Destra sull'ultimo pulsante della slide → slide successiva, focus sul suo primo pulsante (in giro, dopo l'ultima la prima).
- Sinistra resta com'è: tra i pulsanti, e dal primo apre la barra laterale (non si rompe).
- Tasti ⏪/⏩ del telecomando (`LogicalKeyboardKey.mediaRewind` / `mediaFastForward`) col focus sul carosello → slide precedente/successiva.
- Col focus sul carosello la rotazione automatica resta ferma come oggi (verificarlo).

## 4. Indietro nel login e in "Chi guarda?"

- Login (`features/auth/login_screen.dart`, pannelli Quick Connect e recupero): Indietro chiude il pannello e torna alla scheda/al modulo di prima, invece di annullare l'aggiunta o armare l'uscita. Ricordare: su Fire TV Indietro arriva prima come `LogicalKeyboardKey.goBack` e poi come pop di sistema (`PopScope`), vedi `app/tv_back.dart`.
- "Chi guarda?" (`features/profiles`): Indietro mentre un profilo si sta aprendo non arma l'uscita (si ignora).

## Test

Test widget per ogni punto con `FormFactor` TV (come i test TV esistenti: cercare `tv: true` / `androidTvProvider` nei test), più un test che fuori dalla TV non cambia niente dove il codice è condiviso. Ricordare le regole dei test sul focus in `CLAUDE.md` (`SingleChildScrollView`, `autofocus` in uno scope già con focus).

## Dispositivo

Prova finale col telecomando dell'utente. Build APK e installazione con i comandi di `CLAUDE.md`. Attenzione: il salvaschermo può mangiare un tasto e lasciare il focus su "Riproduci"; per il player usare "2012".

## Esito

Branch `feat/tv-ui-rifiniture`, un commit per punto.

**1. Focus dopo il salvaschermo** (`hero_carousel.dart`, `ui/media_row.dart`).

Causa:
- Il salvaschermo da solo non sposta il focus. Su Android il `FocusManager` di Flutter ignora il ciclo di vita (il ripristino del focus in pausa/ripresa c'è solo su desktop e web), e l'attività del Fire Stick riprende senza essere ricreata (`onRestart/onStart/onResume` nel log degli eventi). Provato sul dispositivo col focus su una card di "Continua a guardare": salvaschermo di 20 s (`service call dreams 1`), standby di 40 s (`KEYCODE_SLEEP`) e venti secondi di diapositive: al risveglio il focus era ancora sulla card.
- Il focus finisce su "Riproduci" quando il nodo che lo aveva viene smontato. Flutter lo passa all'ultimo nodo ancora montato tra quelli che l'hanno avuto nella pagina (spesso "Riproduci" della prima diapositiva, che lo prende all'apertura) o, se non ce n'è, alla pagina stessa (focus invisibile, OK non fa niente). Nel secondo caso al cambio di diapositiva successivo l'`autofocus: form.tv` della diapositiva nuova vale di nuovo (la pagina non ha più un figlio col focus) e "Riproduci" prende il focus. Riprodotto con un test widget.
- Chi smonta la card mentre l'utente non tocca niente: dedotto, non riprodotto (servono più di 20 minuti di salvaschermo). Dopo 20 minuti il Fire Stick va in standby (`sleep_timeout` = 1200000) e Jellyfin chiude il WebSocket inattivo ("Lost 1 WebSockets" nel log del server). Al risveglio l'app si riconnette (`ServerConnected(isReconnect: true)`), alza `libraryRevisionProvider` e rilegge tutte le righe della libreria: se una riga cambia (card con chiave riordinate in "Consigliati"/"Visti dagli amici", riga più corta o sparita) la card col focus si smonta. Una rilettura con gli stessi dati, o fallita, non sposta il focus (provato nei test).

Correzione:
- il carosello passa `autofocus` solo alla prima diapositiva costruita; i cambi di diapositiva (automatici o no) non prendono più il focus;
- sulla TV ogni card di una `MediaRow` sta in uno slot con la chiave della card: se lo slot col focus viene smontato, il focus va alla card che ora sta nello stesso posto, o all'ultima se la riga si è accorciata. Se sparisce la riga intera resta il comportamento di Flutter (un nodo già focalizzato della pagina o la pagina stessa), ma non più "Riproduci" a ogni diapositiva.

**2. Intestazione della pagina del titolo** (`detail_header.dart`, `item_detail_screen.dart`): `detailHeaderHeightOf(context)`, sulla TV altezza dello schermo meno 140 dp (al massimo 560). A 540 dp la testata è 400 e sotto si vede la scheda della stagione. Il margine sotto i pulsanti torna 28 anche sulla TV (`tvDetailHeaderTextBottom` tolto): con 64 il logo alto 120 uscirebbe dallo schermo in alto, e i pulsanti restano comunque lontani dal bordo basso. Sfondo, sfumatura del testo e scheletro seguono la stessa altezza; anche la pagina della saga (stessa cornice). La pagina TMDB delle richieste ha una testata sua e resta a 560.

**3. Diapositive col telecomando** (`hero_carousel.dart`): Destra sull'ultimo pulsante della diapositiva passa alla successiva (in giro) col focus sul suo primo pulsante; ⏪/⏩ col focus nel carosello vanno alla precedente/successiva. I pulsanti della diapositiva che esce stanno in un `ExcludeFocus` (sulla TV), così durante la dissolvenza il focus non ci finisce. Sinistra invariata. Col focus dentro la rotazione resta ferma (test).

**4. Indietro nel login e in "Chi guarda?"** (`tv_back.dart`, `login_screen.dart`, `profiles_screen.dart`): `TvBackGuard.onBack` ora restituisce se ha gestito Indietro, altrimenti doppio Indietro. Login: Indietro chiude il recupero e torna alla scheda Password (anche il pulsante "indietro" del recupero ora torna lì sulla TV, prima ripartiva da Quick Connect); da Quick Connect torna a Password; poi annulla l'aggiunta o chiede l'uscita. "Chi guarda?": Indietro mentre un profilo si apre non fa niente.

**Verifiche:** `flutter analyze` senza problemi; `flutter test` 4218 passati. Sul Fire Stick, con l'APK di questo ramo installato: Destra, Destra da "Riproduci" passa alla diapositiva successiva col focus sul suo "Riproduci"; ⏩ (`KEYCODE_MEDIA_FAST_FORWARD`) e ⏪ cambiano diapositiva. Non provati sul dispositivo: la testata della scheda (aprirla richiede OK, non premuto), Indietro nel login e in "Chi guarda?" (servirebbe uscire dal profilo), il caso vero del punto 1 (salvaschermo oltre 20 minuti, poi standby).

**Da fare:** il giro col telecomando dell'utente, soprattutto lasciare la Home sul salvaschermo fino allo standby e controllare dove è il focus al risveglio.

**Dopo la revisione finale:**
- scheletri di caricamento della saga e del passaggio alla saga all'altezza della testata della TV; sulla TV la testata non scende sotto 320 dp (all'avvio e alla ripresa lo schermo può misurare 0 per un attimo e l'altezza diventava negativa);
- carosello: se una rilettura mette un altro titolo al posto della diapositiva col focus, il focus va sul primo pulsante della nuova (prima restava invisibile sulla pagina, visto che l'autofocus vale solo all'apertura);
- login sulla TV: Indietro sulla scheda iniziale (Quick Connect) annulla l'aggiunta o chiede l'uscita, da un'altra scheda torna a quella iniziale, dal recupero torna alla password da cui si era aperto (anche col pulsante del recupero); dopo ogni passaggio il focus va sulla scheda;
- righe: se si esce dalla pagina (un titolo aperto da una riga, la barra laterale) e intanto la card lasciata sparisce, al ritorno il focus va alla card nello stesso posto invece che all'ultimo nodo rimasto (spesso "Riproduci" del carosello). Probabilmente è il caso più frequente del sintomo del punto 1: si guarda un episodio da "Continua a guardare", la riga cambia, si torna alla Home.

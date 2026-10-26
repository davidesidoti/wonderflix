# WonderFlix — Progetto 1c: WonderFlix dal browser del telefono

- **Data:** 2026-10-25
- **Stato:** approvata il 2026-10-25; **realizzata** il 2026-10-26 con il piano 28 (`docs/superpowers/plans/2026-10-25-wonderflix-28-web-telefono.md`), provata dall'utente dall'iPhone sul sito di prova `https://hashvps.proton.usbx.me/wonderflix-prova/`.
- **Ambito:** progetto 1c dell'idea 1 di `docs/IDEE.md` ("Versione web"). Viene dopo il progetto 1b (sito per il PC, su `main`, spec `2026-10-22-wonderflix-web-pc-design.md`).
- **Ricerca:** inventario del codice nella nota di sessione `1c-inventario-desktop.md`. Le cose che servono sono riportate qui sotto.

I percorsi `lib/…`, `test/…`, `web/…` sono dentro `app/`.

## 1. Perché e per chi

L'utente e gli altri utenti del server vogliono usare WonderFlix fuori casa quando hanno solo il telefono. I due momenti che l'utente ha raccontato:
- voleva passare il tempo guardando un episodio, ma non era possibile;
- voleva cercare un sottotitolo nuovo per un titolo, ma dal telefono non poteva.

In generale l'accesso dal telefono deve essere facile. Deve funzionare tutta l'app, non solo il player: guardare, e tutte le funzioni da admin che ci sono oggi (decisione dell'utente).

Il sito è quello della 1b, `https://hashvps.proton.usbx.me/wonderflix/`. Oggi sull'iPhone dell'utente si apre, il login funziona e un episodio si vede e si sente. I problemi sono tre:
- il layout è pensato per il PC e sul telefono ha misure sbagliate;
- lo schermo intero non funziona;
- un tocco sul video mette in pausa, come il clic del mouse.

**Per l'utente il sito sul telefono è una soluzione quasi temporanea.** Quando arriveranno le app native (idea 2), dal telefono userà quelle. Da qui la regola su come spendere lo sforzo:
- le parti che le app native riusano vanno fatte bene, nel codice Flutter comune: layout per schermi stretti, tocco al posto dell'hover, controlli del player col tocco;
- le parti che servono solo al browser del telefono si tengono semplici, per esempio lo schermo intero su iPhone.

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- Tutta l'app si usa dal browser del telefono, in verticale e in orizzontale, senza tagliare nessuna funzione: login, profili, home, ricerca, schede, player, watch party, richieste, calendario, voti, amici, notifiche, segnalazioni, match, impostazioni e tutte le schermate admin.
- Telefoni garantiti: iPhone e Android, tutti e due (decisione dell'utente).
  - Su iPhone ogni browser usa il motore di Safari (WebKit), quindi Safari passa da "non garantito" (1b) a garantito.
  - Il riferimento è l'iPhone dell'utente con Chrome.
- Col dito l'hover è sostituito dal tocco su qualsiasi misura di schermo, quindi anche un tablet in orizzontale funziona.
- Il lavoro su layout e tocco sta nel codice Flutter comune e non dipende dal browser, così le app native lo ritrovano pronto.

**Non obiettivi**
- L'icona sulla schermata Home e l'apertura come app (PWA): restano per l'app nativa (decisione dell'utente).
- Il player di sistema di iOS a schermo intero (decisione dell'utente, §4.5).
- Un layout dedicato al tablet: il tablet usa lo stesso layout adattivo (decisione dell'utente).
- Gesti per volume e luminosità: il volume si regola con i tasti del telefono (decisione dell'utente).
- Nessuna modifica al plugin né alla conversione video lato server, salvo che lo richieda un problema trovato durante il lavoro.

**Anti-obiettivi** (sarebbe un fallimento anche se "funziona")
- Una funzione che c'è sul PC non si riesce a usare dal telefono. Vale anche se è solo nascosta dietro un hover o un tooltip.
- L'app Windows o il sito sul PC cambiano aspetto o comportamento con mouse e tastiera su una finestra larga.
- Sul telefono compaiono strisce gialle e nere di overflow, o testo e pulsanti tagliati.
- Il layout stretto scatta in base al browser o al sistema invece che alla misura della finestra, quindi le app native non potrebbero riusarlo.

## 3. Vincoli

- Flutter 3.47.5, Jellyfin 10.11.9, plugin 1.13.0. L'app passa da 0.21.0 a 0.22.0 con questo progetto (scelta di Claude).
- **iPhone (WebKit).**
  - Non c'è la Fullscreen API sugli elementi. Esiste solo `video.webkitEnterFullscreen()`, che passa al player di sistema.
  - `video.volume` è in sola lettura (`core/video/web_video_engine.dart` lo imposta senza effetto). Il mute funziona.
  - iOS può rifiutare `play()` con l'audio se non c'è stato un tocco dell'utente (`NotAllowedError`).
  - Il sito usa già `playsInline = true` e l'HLS nativo quando `canPlayType` lo permette.
  - L'autofocus di un campo non apre la tastiera.
- **Oggi nel codice** (dall'inventario):
  - non c'è un breakpoint globale, né un `SafeArea`, né un riconoscimento del tipo di puntatore (tranne l'anteprima delle card, solo mouse);
  - tutto presume una finestra di almeno 1024×640;
  - l'app Windows ha `minWindowSize = Size(1024, 640)` in `app/window_setup.dart`.
- Regole del progetto:
  - build Windows con `flutter build windows --release --dart-define-from-file=config/wonderflix.json`, build web come in `docs/RELEASING.md`, tutte e due lanciate da `app/`;
  - commit solo a nome dell'utente;
  - merge su `main` e push solo dopo il suo ok sulla prova dal telefono.
- Ogni tag `vX.Y.Z` pubblica il sito per tutti (`docs/RELEASING.md`). Le prove prima del merge non possono quindi passare da un tag (§6).

## 4. Come funziona (deciso)

Dove una scelta è solo di Claude è segnata come "scelta di Claude". Il resto l'ha deciso l'utente nel brainstorming.

### 4.1 Misura e dito: due cose separate

- **Layout stretto.** Si usa quando la finestra è larga meno di 1024 punti logici (scelta di Claude: è la misura minima di oggi, sopra la quale il layout attuale è già provato).
  - Sono quindi strette: il telefono in verticale e in orizzontale, e il tablet in verticale.
  - Il tablet in orizzontale e il PC hanno il layout di oggi.
  - La misura viene da `MediaQuery`, non dal browser né dal sistema. C'è un solo punto nel codice che la decide, e lo usano tutte le schermate.
- **Modo tocco.** È attivo quando l'ultimo puntatore usato è un dito (o una penna). Vale per qualsiasi misura. Col mouse torna il comportamento di oggi. Anche il modo tocco viene da Flutter (tipo di puntatore), non dal browser (scelta di Claude).
  - Col dito, le cose che oggi compaiono solo con l'hover sono sempre visibili o raggiungibili (§4.4).
- **App Windows.** Tiene la finestra minima 1024×640 (scelta di Claude). Sul sito non c'è una misura minima.
- **Bersagli del tocco.** Nel layout stretto e nel modo tocco, ogni elemento che si tocca è grande almeno 44×44 punti (scelta di Claude, la misura minima di Apple).
- **Bordi dello schermo.** Barra in basso, barra in alto e player rispettano le aree sicure (`SafeArea`), che servono alle app native.
  - Sul sito si lascia il viewport di oggi, senza `viewport-fit=cover`. Così Safari tiene già il contenuto dentro le aree sicure e gli inset valgono zero (scelta di Claude).

### 4.2 Navigazione nel layout stretto

È l'opzione A scelta dall'utente nelle bozze.

- **Barra in basso**, sempre visibile fuori dal player: Home, Cerca, La mia lista, Richieste, Altro.
  - Richieste c'è solo quando ci sono le richieste con Seerr, come oggi. Senza, la barra ha quattro voci (scelta di Claude).
- **"Altro"** si apre dal basso, come foglio. Contiene Film, Serie, Calendario (solo se c'è, come oggi), Impostazioni, Admin (solo per gli admin), Cambia profilo, Aggiungi profilo ed Esci.
  - Sono le voci della barra in alto e del menu del profilo che non stanno nella barra in basso.
- **Barra in alto**, più bassa di quella di oggi:
  - a sinistra la freccia indietro quando serve e il logo;
  - al centro il titolo della pagina scorsa, come oggi;
  - a destra il pulsante del watch party (solo se ci sono party, come oggi), Notifiche, Amici e l'avatar del profilo.
  - L'avatar apre lo stesso menu di oggi.
- **Amici e Notifiche**, e anche i pannelli Consiglia e Vota, nel layout stretto si aprono come pagina intera con la freccia indietro, invece che come pannello laterale.
  - Sopra i 1024 punti restano pannelli laterali come oggi.
  - Lo stato "uno alla volta" di `ShellPanelController` resta. Il builder sceglie se sono rotte vere o lo stesso pannello a tutta larghezza, purché il tasto indietro del telefono li chiuda.
- **Avvisi** (inviti al party e al match, richiesta d'amicizia): nel layout stretto si mostrano a tutta larghezza in alto, sotto la barra.

### 4.3 Schermate nel layout stretto

Regola generale: nessuna misura fissa più larga dello schermo, i titoli grandi si rimpiccioliscono e le righe che non stanno vanno a capo o scorrono. Il builder sceglie i dettagli, rispettando quanto segue.

- **Finestre.** Nel layout stretto `showWfDialog` mostra la finestra come pagina intera, con titolo, freccia indietro e contenuto che scorre (decisione dell'utente).
  - Vale per tutte le finestre con contenuto o moduli: password, contatti, richieste, sottotitoli, metadati, identifica, immagini, informazioni sul media, segnalazioni, avatar, stasera, giorno del calendario, riavvio.
  - Le conferme brevi (sì/no) restano finestre al centro, ma scorrono se non ci stanno (scelta di Claude).
  - Con la tastiera aperta il campo attivo resta visibile.
- **Login.** Logo sopra e pannello sotto, in una colonna che scorre. Le schede del login non hanno più altezza fissa.
- **Home.**
  - Il carosello in alto è più basso, il testo prende tutta la larghezza e i pulsanti Stasera/Match non coprono il testo.
  - Il carosello si sfoglia col dito.
  - Le card delle righe sono più piccole.
- **Scheda di film e serie.**
  - La testata non ha altezza fissa, e i pulsanti non vengono tagliati.
  - Riproduci resta il pulsante principale. Le altre azioni possono stare in una riga di icone e nel menu ⋯, purché ognuna resti raggiungibile.
  - Gli episodi hanno la miniatura più piccola o sopra il testo.
- **Persona.** Foto sopra e testo sotto.
- **Intestazioni delle pagine** (catalogo, lista, richieste, calendario, admin): il titolo si rimpicciolisce e va a capo.
- **Admin.**
  - Le cinque schede scorrono in orizzontale.
  - La striscia del server scorre con la pagina invece di restare fissa.
  - Le righe e le tabelle larghe diventano liste, con le azioni in un menu o sotto il testo.
- **Richieste.** Le schede scorrono. I pulsanti Rifiuta/Approva vanno sotto il titolo.
- **Calendario.**
  - L'intestazione del mese sta in una riga stretta.
  - Le celle del mese hanno un'altezza minima toccabile. Se lo schermo è basso (telefono in orizzontale) la griglia scorre.
- **Match.** Il mazzo sopra e i membri e le coppie sotto.
- **Menu a comparsa** con larghezza fissa (modalità del party 380, gruppi del party 320): nel layout stretto non superano lo schermo.
- **Impostazioni e profili:** già fluidi, si controllano soltanto.

### 4.4 Tocco al posto dell'hover

- **Card.**
  - Un tocco apre la scheda del titolo.
  - Tenendo premuto si apre l'anteprima di oggi come foglio dal basso, con Riproduci, Preferito, Visto, Dettagli, la × "non mi interessa" dei consigli e le note dei consigli.
  - Così la × dei consigli, che oggi esiste solo nell'anteprima, resta raggiungibile.
  - Col mouse l'anteprima resta com'è oggi.
- **Suggerimenti delle icone (tooltip).** Col dito compaiono tenendo premuto, come fa già Flutter. Basta anche per i tooltip che contengono informazioni (commento intero di un amico, data intera, descrizione dei task, contatti collegati) (scelta di Claude).
- **Cose oggi visibili solo con l'hover**, che col dito diventano sempre visibili:
  - la maniglia di spostamento e la × delle righe della coda del party;
  - la × delle voci nelle Notifiche.
- **Timer che oggi si rinnovano con l'hover.** Col dito si rinnovano con un tocco o uno scroll: la chat del party, che non si chiude mentre la scorri, e il vassoio delle reazioni.
- **Effetti hover puramente estetici** (bordo oro, ingrandimenti): col dito non devono restare "accesi" dopo un tocco.

### 4.5 Player

- **Tocco** (decisione dell'utente):
  - un tocco sul video mostra o nasconde i controlli, non mette in pausa;
  - pausa e play stanno nel pulsante al centro;
  - un doppio tocco sulla metà destra o sinistra salta avanti o indietro di 10 secondi;
  - la barra del tempo si trascina col dito, con l'anteprima del fotogramma (oggi funziona già).
  - Col mouse resta tutto come oggi: il clic mette in pausa e il doppio clic va a schermo intero.
- **Controlli che si nascondono.** Col dito il tocco li fa tornare (oggi tornano solo col movimento del puntatore). Si nascondono dopo qualche secondo come oggi.
- **Volume.** Col dito non c'è il cursore del volume: si usano i tasti del telefono (decisione dell'utente). Il builder decide se tenere il pulsante del mute.
- **Disposizione nel layout stretto:**
  - in alto: indietro, titolo più piccolo e badge del party;
  - al centro: indietro 10 s, play/pausa grande, avanti 10 s;
  - in basso: barra del tempo con i tempi e una riga di icone (tracce e sottotitoli, coda, chat, reazioni, guarda insieme, episodio precedente e successivo, schermo intero). Se le icone non ci stanno, le meno usate vanno in un menu ⋯.
  - Nessuna funzione del player va persa.
- **Pannelli del player** (tracce e sottotitoli, coda, voto): nel layout stretto si aprono dal basso, a tutta larghezza (scelta di Claude). Lo stesso vale per la chat del party, con il campo di testo sopra la tastiera.
- **Altri pezzi del player nel layout stretto:**
  - Fine del titolo: il riquadro del video sopra, le informazioni e il voto sotto, invece che di lato.
  - Schermata di pausa: logo e testo ridimensionati.
  - "Salta intro" e la card dell'episodio successivo: dentro lo schermo.
- **Schermo intero** (decisione dell'utente):
  - **Android e browser con la Fullscreen API:** schermo intero vero. Su un telefono il player prova a entrare a schermo intero e a bloccarsi in orizzontale quando si apre. Qui "telefono" vuol dire modo tocco e lato corto della finestra sotto i 600 punti, così un tablet in verticale non ruota da solo (scelta di Claude). Esce quando si chiude (scelta di Claude: la decisione dell'utente era "schermo intero e telefono in orizzontale"). Se il browser rifiuta, resta il pulsante.
  - **iPhone:** il player riempie la pagina. Resta visibile la barra del browser. Il pulsante dello schermo intero non c'è dove la Fullscreen API non esiste. Non si usa il player di sistema di iOS.
  - In verticale il video sta al centro e l'app non obbliga a ruotare (scelta di Claude).
- **Avvio bloccato da iOS.** Se il browser rifiuta di far partire il video con l'audio, il player mostra "Tocca per riprodurre", e un tocco lo fa partire (scelta di Claude).
  - Vale per l'avvio nel watch party quando parte l'host, per l'episodio successivo e per qualsiasi altro avvio.
  - Nel party, dopo il tocco, il `DriftCorrector` riporta il telefono in pari come oggi.

### 4.6 Cosa non cambia

- Sopra i 1024 punti e col mouse, sito sul PC e app Windows sono identici a oggi: barra in alto, pannelli laterali, anteprime con l'hover, finestre al centro, player e scorciatoie.
- Scorciatoie da tastiera: restano tutte. Sul telefono non servono, perché niente è raggiungibile solo da tastiera.
- Profilo video del browser, token, sottotitoli, watch party e build: come nella 1b.

## 5. Prove

- **Test automatici** (`flutter test`, da `app/`):
  - le schermate principali costruite a misura di telefono, cioè 390×844 in verticale e 844×390 in orizzontale, e di tablet (768×1024), senza errori di overflow. Le schermate sono: login, profili, home, scheda di film e serie, persona, ricerca, catalogo, lista, richieste, calendario, match, impostazioni, admin (ogni scheda), Amici e Notifiche come pagina, le finestre principali come pagina, il player con i suoi pannelli;
  - a 1024 punti e oltre, la shell ha la barra in alto e i pannelli laterali di oggi;
  - modo tocco: il tocco sul video mostra i controlli e non mette in pausa, il doppio tocco ai lati salta di 10 s, mentre col mouse il comportamento è quello di oggi;
  - pressione lunga su una card apre l'anteprima, e col tocco l'anteprima non si apre;
  - la coda del party permette spostamento e rimozione col tocco;
  - "Tocca per riprodurre" quando il motore segnala l'avvio rifiutato.
  - I test esistenti continuano a passare, e `flutter analyze` è pulito.
- **Prova di Claude**, prima di passare all'utente:
  - con il browser integrato in modalità telefono (misura e tocco simulati), sul sito di prova (§6), in verticale e in orizzontale, con gli account di prova (ClaudeAdmin, ClaudeSubs, ClaudeNormal; il login lo fa l'utente, Claude non scrive le password);
  - si prova: navigazione con la barra in basso e "Altro", una scheda, l'anteprima tenendo premuto, un episodio con controlli, salti, tracce e sottotitoli, la ricerca di un sottotitolo, una richiesta approvata, ogni scheda dell'admin, Amici e Notifiche, un watch party tra il browser in modalità telefono e il sito sul PC;
  - il server e Seerr sono quelli veri, quindi Claude non tocca le richieste degli altri utenti (scelta di Claude):
    - per la prova della richiesta, ClaudeNormal chiede un titolo piccolo e ClaudeAdmin la approva;
    - per i sottotitoli Claude cerca soltanto, senza scaricare. Lo scaricamento lo prova l'utente;
  - il builder verifica anche come Flutter web su iOS riceve l'altezza della tastiera. Lo fa sul telefono dell'utente durante la sua prova, se Claude non ha un WebKit a disposizione.
  - Se si può avere WebKit su Windows senza installazioni pesanti (per esempio Playwright WebKit, con l'ok dell'utente), Claude ci prova layout, player e "Tocca per riprodurre". Altrimenti WebKit lo prova solo l'utente.
  - Si controlla che il sito sul PC e l'app Windows siano come prima: build Windows avviata e un giro veloce.
- **Prova dell'utente:** dal suo iPhone sul sito di prova (§6). Guarda un episodio e fa le azioni da admin, compresa la ricerca di un sottotitolo. Poi un'occhiata al sito sul PC e all'app Windows.

## 6. Sito di prova e pubblicazione

- **Sito di prova.** Dato che ogni tag pubblica il sito per tutti, la build del ramo va su un percorso separato dello stesso server, `https://hashvps.proton.usbx.me/wonderflix-prova/` (scelta di Claude). Così l'utente prova dal telefono prima del merge, senza toccare il sito di tutti.
  - I file stanno in `~/wonderflix-web-prova/`.
  - Una conf nginx gemella di `app/deploy/wonderflix.conf` è nella repo, con gli stessi header (COOP/COEP, `no-cache`, wasm, niente query string nei log).
  - La build usa `--base-href /wonderflix-prova/`. È la stessa origine, quindi il login di Jellyfin funziona.
  - Claude la pubblica a mano con `ssh ultra` (lavoro sul server autorizzato).
  - Il percorso resta per i progetti futuri, e `docs/RELEASING.md` spiega come usarlo.
- **Pubblicazione.** Dopo l'ok dell'utente: merge su `main`, push, poi la release 0.22.0 con il tag, che pubblica il sito come oggi. Le note della release le scrive Claude nella bozza.
- **Documenti.**
  - `docs/RELEASING.md`: la checklist dei test manuali aggiunge le prove dal telefono.
  - `docs/IDEE.md`: 1c passa tra le fatte.
  - Questa spec passa a "realizzata".

## 7. Fatto quando

- Dal browser di un telefono vero, sul sito pubblicato, si guarda un titolo e si fanno le azioni da admin senza bisogno di un PC.
- Il sito sul PC e l'app Windows funzionano come prima.
- `flutter analyze` e `flutter test` passano da `app/`.
- L'utente ha provato tutto sul sito di prova prima del merge su `main`.
- La release 0.22.0 ha pubblicato il sito.

## 8. Lasciato al builder

- Il nome e la forma del punto unico che decide layout stretto e modo tocco: per esempio un `InheritedWidget` o un provider, con il tipo dell'ultimo puntatore letto da un `Listener` alla radice.
- Come mostrare le finestre come pagina: la stessa `showWfDialog` con una rotta a tutto schermo, o altro.
- Se Amici, Notifiche, Consiglia e Vota nel layout stretto sono rotte vere o pannelli a tutta larghezza.
- Quali icone del player vanno nel menu ⋯, e se resta il pulsante del mute col dito.
- L'aspetto della barra in basso e del foglio "Altro", nello stile dell'app (colori, icone Lucide).
- Se lo sfondo sfocato della barra resta anche sul telefono: va tolto se su Safari scatta.
- L'ordine dei passi nel piano.

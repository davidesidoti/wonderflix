# WonderFlix — Spec C: rinnovo grafico (movimento e rifiniture)

- **Data:** 2026-09-30
- **Stato:** approvato in brainstorming, in attesa di revisione finale
- **Ambito:** Spec C. Si appoggia allo Spec A (`2026-09-29-wonderflix-client-core-design.md`, §6 Navigazione e schermate, tema Noir & Oro) e allo Spec B (`2026-09-30-wonderflix-watch-party-design.md`, §7 Interfaccia), entrambi realizzati (v0.2.0).

## 1. Obiettivo

Rendere WonderFlix un'app più "viva" e più bella da vedere, in stile **spettacolare**, senza cambiare identità:

- **i colori Noir & Oro, i font (Bebas Neue, Inter), il logo e la disposizione delle schermate restano**;
- cambiano il **movimento** (transizioni, entrate, passaggio del mouse, scroll) e la **cura dei dettagli** (caricamento, barra, pulsanti, menu);
- l'app deve restare fluida (obiettivo 60 fps) e rispettare chi vuole meno animazioni.

### Situazione di partenza

- Una sola transizione tra le pagine: la dissolvenza su nero del player (150 ms, `playerPage` in `lib/app/router.dart`). Le altre pagine compaiono senza animazione.
- Nessun `Hero`, `AnimatedSwitcher` o `AnimationController` fuori dal player. Unici movimenti: bordo oro delle card (`AnimatedContainer` 120 ms), puntini e scorrimento del carosello (`PageView`, 600 ms), frecce delle righe (`animateTo` 300 ms), dissolvenza delle immagini (200 ms).
- Caricamento: blocchi grigi fermi (`SkeletonBox`) solo nella Home; altrove uno spinner (`LoadingView`).
- Scroll di Flutter standard: su Windows la rotella avanza a scatti, senza inerzia. Il touchpad di precisione è già fluido.
- Su Windows `MediaQuery.disableAnimations` è **sempre falso**: l'engine comunica solo il contrasto elevato (`FlutterWindowsEngine::SendAccessibilityFeatures`), non l'impostazione "Effetti di animazione".

## 2. Decisioni

| Tema | Decisione |
|---|---|
| Intensità | **Spettacolare**: sollevamenti, anteprime, voli, parallasse, entrate "volanti" con rimbalzo leggero. |
| Perimetro | **Tutta l'app** in un solo spec, diviso in piani. Il player resta fuori. |
| Riduzione | Impostazione "Animazioni" nell'app (*Come Windows* predefinito, *Complete*, *Ridotte*) + lettura della preferenza di Windows via FFI. |
| Passaggio del mouse sulle card | **Anteprima che si espande** (stile Netflix) dopo 500 ms di sosta. Niente inclinazione 3D. |
| Dove c'è l'anteprima | Ovunque ci sia una `PosterCard` o una `LandscapeCard`, **tranne le card degli episodi** nella scheda di una serie. |
| Card → scheda | **Hero**: l'immagine vola nella testata, poi il contenuto entra scaglionato. |
| Scroll della scheda | **Parallasse** dello sfondo **e** titolo con "Riproduci" nella barra quando la testata esce. |
| Carosello della Home | **Dissolvenza cinematografica** con Ken Burns, testi scaglionati, puntino che si riempie. |
| Caricamento | **Riflesso oro sincronizzato**: un'unica onda attraversa tutti gli scheletri della pagina. |
| Altri tocchi | Tutti e cinque: barra in alto, pulsanti e icone, avvio e login, menu/dialoghi/avvisi, griglie. |
| Tecnica | **Tutto fatto in casa** sulle primitive di Flutter; nessuna dipendenza nuova. |

### Perché nessun pacchetto

Valutati `flutter_animate`, `animations` (flutter.dev) e `flutter_smooth_wheel_scroll`:

- `flutter_animate` gestisce i ritardi con timer propri: nei widget test lascia timer pendenti, un problema già incontrato (vedi passaggio di consegne, "Timer nei widget test");
- `animations` 3.0 dipende dal nuovo pacchetto `material_ui`, da verificare con Flutter 3.47, e offre transizioni che qui servono poco (Hero e `CustomTransitionPage` sono già nel framework);
- `flutter_smooth_wheel_scroll` è alla 0.1.3, con pochissimo uso;
- la modalità ridotta andrebbe collegata effetto per effetto. Con un punto centrale (`WfMotion`) si applica una volta sola.

## 3. Perimetro

### Incluso

- Fondamenta: token di movimento, livello completo/ridotto, impostazione "Animazioni", preferenza di Windows (§4).
- Scroll morbido con la rotella in tutte le pagine scorrevoli (§5).
- Transizioni tra le pagine e Hero (§6).
- Anteprima espansa delle card (§7).
- Home: carosello ed entrata delle righe (§8).
- Scheda del titolo: parallasse, titolo nella barra, cambio di stagione (§9).
- Caricamento: shimmer sincronizzato e nuovi scheletri (§10).
- Barra in alto, pulsanti e icone, avvio e login, menu/dialoghi/avvisi, griglie, impostazioni (§11).

### Escluso (idee future)

- Player: overlay, barra, pannelli, avvisi del watch party dentro il player.
- Colori, font, icona dell'app, logo.
- Spostamenti di blocchi o nuove disposizioni delle schermate.
- Trailer in riproduzione dentro l'anteprima.
- Inclinazione 3D delle card.

## 4. Fondamenta del movimento

### 4.1 Token (`lib/app/motion.dart`)

`WfMotion` è un oggetto immutabile con durate, curve e livello. Tutti i widget lo leggono con `WfMotion.of(context)`, attraverso un `InheritedWidget` (`WfMotionScope`) messo sopra il router in `app.dart`. **Nessun widget ha durate o curve scritte a mano** (il player resta com'è).

| Token | Valore | Uso |
|---|---|---|
| `fast` | 150 ms | dissolvenze brevi, uscite, modalità ridotta |
| `medium` | 300 ms | anteprima, sottolineatura della barra, dissolvenza scheletro → contenuto |
| `slow` | 450 ms | entrate di righe e card |
| `hero` | 420 ms | volo dell'immagine card → scheda |
| `crossfade` | 900 ms | diapositive del carosello |
| `stagger` | 60 ms | ritardo tra elementi della stessa entrata |
| `emphasized` | `Cubic(0.2, 0.8, 0.2, 1)` | curva principale (entrate, voli, anteprima) |
| `standard` | `Curves.easeInOut` | dissolvenze |
| `bounce` | `Cubic(0.2, 0.9, 0.25, 1.2)` | entrate "volanti", apertura dell'anteprima |

Le durate specifiche di un effetto (per esempio gli 80 ms tra le righe della Home, o gli 8 s del carosello) sono costanti nominate accanto ai token, non numeri sparsi nei widget.

### 4.2 Livello completo e ridotto

`MotionLevel { full, reduced }`. Con **`reduced`**:

- ogni effetto che si muove nello spazio diventa una dissolvenza di `fast` (150 ms): scaglionamento, entrate "volanti", parallasse, Ken Burns, volo Hero, scala e rimbalzo dell'anteprima, pop delle icone, scala dei pulsanti;
- lo shimmer diventa un blocco fermo;
- restano: scroll morbido (è una comodità), anteprima (è utile, si apre in dissolvenza), titolo nella barra, sottolineatura della barra (che però salta alla voce nuova senza scorrere).

`WfMotion` espone un aiuto per non ripetere la regola in ogni widget, per esempio `motion.pick(full: ..., reduced: ...)` e `motion.isReduced`.

### 4.3 Impostazione "Animazioni"

- Nuova sezione **"Aspetto"** in Impostazioni, prima di "Player".
- Voce "Animazioni" con tre valori: **Come Windows** (predefinito), **Complete**, **Ridotte**.
- `AppearanceSettingsController` è un `Notifier` salvato in `shared_preferences` con la chiave `appearance.motion`, come `PlayerSettingsController`.
- Testi nei file ARB (it + en).

### 4.4 Preferenza di Windows (`lib/core/system/windows_animation_pref.dart`)

- Legge `SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION = 0x1042)` da `user32.dll` via `dart:ffi` (come `windows_discord_pipe.dart` con kernel32): `FALSE` → ridotte.
- Interfaccia `AnimationPreference` con l'implementazione Windows e un fake per i test.
- Si legge all'avvio e a ogni ritorno del focus sulla finestra (`WindowListener.onWindowFocus` di `window_manager`), così un cambio in Windows vale senza riavvio.
- In caso di errore della chiamata: animazioni complete, con una riga nel log.

### 4.5 Livello effettivo

Un provider `motionLevelProvider` combina impostazione e preferenza:

| Impostazione | Preferenza di Windows | Livello |
|---|---|---|
| Come Windows | animazioni attive | `full` |
| Come Windows | animazioni disattivate | `reduced` |
| Complete | qualsiasi | `full` |
| Ridotte | qualsiasi | `reduced` |

### 4.6 Nei test

- L'helper comune (`test/support/pump_app.dart`) monta `WfMotionScope` con livello **`reduced`** e il fake della preferenza: shimmer fermo, nessuna animazione infinita. I `pumpAndSettle` esistenti restano stabili.
- I test delle animazioni nuove impostano `full` esplicitamente.

## 5. Scroll morbido con la rotella (`lib/ui/smooth_scroll.dart`)

- `SmoothScrollController extends ScrollController` crea una `SmoothScrollPosition` (sottoclasse di `ScrollPositionWithSingleContext`) che ridefinisce **`pointerScroll(double delta)`**. Flutter lo chiama **solo** per `PointerScrollEvent` (la rotella del mouse).
- Comportamento:
  - ogni scatto sposta una **destinazione**, limitata tra `minScrollExtent` e `maxScrollExtent`;
  - la posizione ci arriva con `animateTo` in circa 200 ms, curva `easeOutCubic`;
  - uno scatto durante l'animazione aggiorna la destinazione e riparte dalla posizione attuale, così gli scatti ravvicinati si sommano senza strappi;
  - un trascinamento, un `jumpTo` o un `animateTo` esterno (frecce delle righe, "torna su") annullano la destinazione in sospeso.
- Il touchpad di precisione di Windows invia `PointerPanZoom*`, gestiti come trascinamento: **resta com'è**.
- Righe orizzontali: ricevono solo lo scorrimento orizzontale (Shift + rotella, o i pulsanti freccia). La rotella verticale sopra una riga continua a scorrere la pagina, come oggi.
- Si usa in: Home, scheda del titolo (film e serie), Catalogo, La mia lista, Ricerca, Persona, Impostazioni, righe orizzontali (`MediaRow`, righe della scheda).
- Attivo anche con le animazioni ridotte.

## 6. Transizioni tra le pagine

### 6.1 Voci della barra

Home ↔ Film ↔ Serie ↔ La mia lista ↔ Cerca ↔ Impostazioni:

- dissolvenza incrociata "fade through": la vecchia pagina esce in 90 ms, la nuova entra in 210 ms con scala da 0,98 a 1;
- `pageBuilder` con `CustomTransitionPage` sulle rotte della `ShellRoute` (funzione `shellPage`, accanto a `playerPage`);
- ridotte: sola dissolvenza di `fast`.

### 6.2 Card → scheda del titolo (Hero)

- **Tag:** `WfHeroTag(itemId, source)`, dove `source` identifica la card che è stata cliccata (riga o griglia + posizione). Due card dello stesso titolo nella stessa pagina non entrano in conflitto.
- **Passaggio del tag:** `openItem(context, item, hero: launch)` fa `context.push(route, extra: launch)`, dove `HeroLaunch` contiene il tag e le immagini già note dalla card (sfondo e locandina di ripiego, `ImageRef`). La rotta `/item/:id` legge `state.extra` e lo passa alla scheda. Senza `HeroLaunch` (link diretto, ricostruzione della rotta) la scheda entra con la sola dissolvenza.
- **Destinazione subito presente:** il volo parte nel fotogramma del `push`, quando la scheda di solito sta ancora caricando (`itemProvider`). Per questo la testata con lo sfondo avvolto nell'`Hero` si disegna **già durante il caricamento**, usando le immagini di `HeroLaunch`; sotto resta l'indicatore di caricamento (lo scheletro arriva nel piano 6b). Quando i dati arrivano, la testata resta la stessa e compare il resto.
- **Volo** (`hero`, 420 ms, `emphasized`) con `flightShuttleBuilder`:
  - da una locandina 2:3: l'immagine in volo passa in dissolvenza dalla locandina allo sfondo 16:9 (stesso `BoxFit.cover`, bordi da 6 a 0);
  - dall'anteprima (§7) o da una card orizzontale: lo sfondo è già quello, vola e basta.
- **Pagina:** la pagina sotto si dissolve (`CustomTransitionPage` per `/item/:id` e `/person/:id`). A volo finito entrano scaglionati, di `stagger`: logo o titolo, dati, generi, trama, pulsanti, poi le righe sotto.
- **Indietro:** l'immagine rivola nella card (Hero inverso), il contenuto della scheda esce in dissolvenza.
- **Persone:** anche il volto del cast (`CastRow`) vola nella foto della pagina della persona, con la stessa regola dei tag e la foto già presente durante il caricamento.
- **Ridotte:** niente `Hero` (il tag non viene applicato), sola dissolvenza di `fast`.

### 6.3 Player

Resta com'è: dissolvenza su nero di 150 ms (`playerPage`). Chiudendo l'anteprima o la scheda per aprire il player non parte nessun volo.

## 7. Anteprima espansa delle card

### 7.1 Dove e quando

- In `PosterCard` e `LandscapeCard`, in tutta l'app, **tranne** le card degli episodi nella scheda di una serie (`_EpisodeList` in `series_detail_view.dart`), che restano come oggi con il loro pulsante play.
- Sulle card con anteprima il pulsante play al passaggio del mouse (`CardPlayButton`) sparisce: il play sta nell'anteprima.
- **Passaggio del mouse:** subito il bordo oro (come oggi). Dopo **500 ms** di sosta sulla stessa card (`previewHoverDelay`, un `Timer` cancellato all'uscita del mouse e in `dispose`) si apre l'anteprima.
- **Una sola aperta alla volta**, gestita da un `CardPreviewController` (provider). Passando direttamente da un'anteprima aperta a un'altra card, o entro `previewChainWindow` (400 ms) dalla chiusura dell'ultima, la nuova si apre **subito**, senza aspettare i 500 ms.
- **Overlay:** l'anteprima si disegna nell'overlay **principale** (`OverlayChildLocation.rootOverlay`), quindi sta sopra anche la barra in alto.
- **Si chiude:** il mouse esce dall'anteprima, rotella, scroll (della riga e anche della pagina che la contiene, comunque avvenga: tastiera, barra di scorrimento, codice), Esc, finestra non attiva (`AppLifecycleState` diverso da `resumed`), pagina della card non più in cima (push o `go`), apertura di un'altra anteprima. Chiusura in `fast`; con rotella, scroll, finestra non attiva e cambio di pagina è immediata.
- **Dopo Esc, rotella, scroll o finestra non attiva** l'anteprima **non si riapre** sotto il mouse fermo: serve uscire dalla card e rientrare (il primo movimento del mouse fuori dalla card riarma la sosta).
- **Solo con il mouse** (`PointerDeviceKind.mouse`): con tocco o tastiera il clic apre direttamente la scheda.

### 7.2 Aspetto e posizione

- `OverlayPortal`: l'anteprima sta sopra righe e barra senza spostare nulla.
- Centrata sulla card; larghezza circa 1,8 × la card, minimo 300 px; altezza data dal contenuto.
- Resta dentro la finestra con un margine di 16 px: vicino a un bordo si sposta verso l'interno. Il calcolo della posizione è una funzione pura, testata a parte.
- Apertura: scala da 0,6 a 1 dal centro della card con la curva `bounce` e dissolvenza, in `medium`. Ombra profonda e contorno oro sottile (oro al 50%).
- `RepaintBoundary` attorno all'anteprima.
- **Uscita verso la scheda (Dettagli):** il riquadro, il bordo oro, l'ombra e il corpo (pulsanti, dati, titolo) spariscono in dissolvenza di `fast` e resta solo l'immagine, che vola. Durante l'uscita l'anteprima non riceve clic (la pagina nuova sta sotto). Si chiude a transizione della pagina finita (`secondaryAnimation` della rotta della card completata) o se la pagina della card torna in cima. Per il resto dell'app l'anteprima è già chiusa appena parte l'uscita: Esc durante la transizione torna indietro come sempre.

### 7.3 Contenuto

- **In alto:** sfondo 16:9 (`ImageUrls.backdrop`, con la locandina sfocata come ripiego, come `BackdropImage`), blurhash durante il caricamento, sfumatura verso il basso. Logo o titolo in Bebas Neue in basso a sinistra.
- **Pulsanti:**
  - **Riproduci / Riprendi** (oro, pieno): stessa logica di `playItem`; per una serie parte il prossimo episodio;
  - **La mia lista** (cuore) e **Visto** (spunta), con gli stessi `userDataOverridesProvider` della scheda;
  - a destra **Dettagli** (freccia): apre la scheda con il volo Hero dallo **sfondo dell'anteprima** (sorgente `<sorgente della card>.preview`, per non duplicare il tag della card nella stessa pagina).
  - I pulsanti sono tondi da **36 px** (icone da 18), più piccoli di quelli della scheda (44/20), per stare con tutte le righe di dati; `WfIconToggle` ha i parametri `size` e `iconSize` (predefiniti 44 e 20).
  - **Card degli episodi** ("Continua a guardare", "Prossimi episodi"): titolo della serie con "S1:E4 · titolo"; Riprendi fa ripartire l'episodio, Visto vale per l'episodio, Dettagli apre la serie; **niente cuore**.
  - **Riproduci / Riprendi** chiude l'anteprima e avvia la riproduzione (nessun volo).
- **Dati:** anno · durata (film, episodio) o stagioni (serie) · ★ voto · classificazione; sotto, fino a 3 generi.
- **Avanzamento:** barra oro, se c'è.
- Clic sullo sfondo o sul titolo: come "Dettagli". Tornando indietro la scheda rientra con la sola dissolvenza: l'anteprima non c'è più, quindi non c'è un volo di ritorno verso di essa.
- Testi (tooltip, etichette) nei file ARB.

### 7.4 Dati

Si aggiunge `Genres` ai campi base delle liste (`fields` in `lib/core/jellyfin/item_query.dart`, che diventano `PrimaryImageAspectRatio,Genres`). L'anteprima usa lo sfondo a 1920 px (`ImageUrls.backdrop`), lo stesso della testata della scheda: il volo lo trova già scaricato. Anno, durata, voto, classificazione e immagini (sfondo, logo) arrivano già. **Nessuna chiamata in più** all'apertura dell'anteprima.

### 7.5 Ridotte

L'anteprima si apre lo stesso, dopo gli stessi 500 ms, con una sola dissolvenza di `fast`, senza scala né rimbalzo.

## 8. Home

### 8.1 Carosello "In evidenza" (`hero_carousel.dart`)

- Il `PageView` diventa una pila di due diapositive: l'attuale sopra, la precedente sotto, in **dissolvenza incrociata** (`crossfade`, 900 ms).
- **Ken Burns:** lo sfondo della diapositiva attiva va da scala 1 a 1,1 con una deriva laterale del 2%, lineare, per tutta la durata della diapositiva più la dissolvenza.
- **Testi:** quelli uscenti sfumano in 250 ms; gli entranti (logo o titolo, dati, trama, pulsanti) entrano dal basso di 10 px, con ritardo 250 ms e 90 ms tra un elemento e l'altro.
- **Puntini:** quello attivo si allunga (da 6 a 26 px) e si riempie d'oro in 8 s (`HeroCarousel.interval`). Cliccando un puntino si va a quella diapositiva e il tempo riparte. Il tempo della diapositiva è un `AnimationController` (niente timer); nei widget test l'autoplay è spento (`carouselAutoplayProvider`).
- **Pausa** (il puntino si ferma e riprende da dove era):
  - mouse sopra il carosello;
  - un'anteprima aperta (§7);
  - Home coperta da un'altra pagina: il carosello legge `TickerMode.valuesOf(context).enabled` in `didChangeDependencies`, perché un ticker silenziato continua comunque a contare il tempo; tornando alla Home il puntino riprende da dov'era.
- **Ridotte:** dissolvenza di `fast` tra le diapositive, niente Ken Burns, testi senza scaglionamento. Il puntino si riempie comunque (indica il tempo, non è decorazione).

### 8.2 Entrata delle righe

- Al **primo** arrivo dei dati della Home, le righe salgono in dissolvenza (20 px), scaglionate di 80 ms.
- Dentro ogni riga, le prime card visibili (al massimo 8) entrano "volando" da destra (40 px, scala da 0,85 a 1, curva `bounce`), a 40 ms l'una dall'altra.
- Si vede **una volta per sessione dell'app**: tornando alla Home, anche dalla barra, non si ripete, né quando i dati si aggiornano (eventi WebSocket, preferiti, visti).
- Stesso comportamento per le righe della scheda del titolo (cast, "Simili"), dopo l'entrata della testata.
- Un widget riutilizzabile (`StaggeredEntrance`) con un solo `AnimationController` per gruppo e intervalli (`Interval`) per ogni figlio, senza timer. Il calcolo degli intervalli è una funzione pura, testata a parte.

## 9. Scheda del titolo

### 9.1 Parallasse

- La scheda (film e serie) usa uno `SmoothScrollController`. Un `AnimatedBuilder` su di esso (niente `setState` della pagina) applica alla testata:
  - sfondo: traslazione verticale a metà della velocità di scroll, scala da 1 a 1,08, scurimento fino al 50%;
  - blocco dei testi (logo, dati, trama, pulsanti): opacità che scende e leggera salita, fino a sparire quando la testata è quasi uscita.
- Con la barra sovrapposta (§11.1) lo sfondo della testata arriva fino al bordo alto della finestra.

### 9.2 Titolo nella barra

- Quando il testo della testata è quasi sparito, compaiono in dissolvenza nella barra in alto, a destra delle voci:
  - il titolo del film o della serie in Bebas Neue;
  - un piccolo pulsante oro **"Riproduci"**, con la stessa azione e la stessa etichetta del pulsante principale della scheda (Riproduci, Riprendi, Riproduci S1:E5…).
- **Quando (decisione della prova 6b):** una soglia fissa di scroll (380 px) non si raggiungeva sulle schede corte o nelle finestre alte. La regola è legata alla dissolvenza del testo della testata (`barTitleVisible` in `header_parallax.dart`):
  - animazioni complete: quando l'opacità del testo scende a `barTitleTextOpacity` (0,3, circa 245 px di scroll);
  - animazioni ridotte (il testo non sfuma): quando la riga dei pulsanti passa sotto la barra, cioè a `detailHeaderHeight − detailHeaderTextBottom − shellBarHeight` (468 px).
  Se la pagina non scorre abbastanza, il testo della testata resta leggibile e il titolo non serve nella barra.
- **Realizzazione:** la scheda pubblica `ShellHeader(title, actionLabel, onAction)` con `ShellHeaderPublisher` quando la regola è vera per lo scroll; `ShellPageFrame` lo ricorda per la propria pagina e lo passa alla barra quando la pagina è in cima, come lo stato "scorsa". Tornando indietro la barra ritrova il titolo della pagina tornata in cima.
- Anche con le animazioni ridotte (in dissolvenza di `fast`).

### 9.3 Serie

- Cambiando stagione, l'elenco degli episodi fa una dissolvenza incrociata (`AnimatedSwitcher`, `medium`) e gli episodi entrano scaglionati (§8.2).
- L'indicatore della stagione attiva (`_SeasonTabs`) scorre da una stagione all'altra, come la sottolineatura della barra (§11.1).

## 10. Caricamento

### 10.1 Shimmer sincronizzato

- `WfShimmer` avvolge lo scheletro di una pagina e possiede **un solo** `AnimationController` in loop (1,8 s, `easeInOut`).
- Ogni `SkeletonBox` è un `CustomPainter` che si ridipinge con il controller dell'onda (senza ricostruire widget) e dipinge un gradiente lineare diagonale (trasparente → oro 10% → crema 10% → oro 10% → trasparente) **in coordinate di `WfShimmer`**, calcolate con la posizione del blocco rispetto all'antenato. Il risultato è un'unica onda che attraversa tutti i blocchi.
- `RepaintBoundary` sullo scheletro: l'animazione ridisegna solo i blocchi.
- `SkeletonBox` senza `WfShimmer` sopra, o con le animazioni ridotte: blocco fermo come oggi.

### 10.2 Nuovi scheletri

Imitano la pagina vera: scheda del titolo (testata + righe), elenco degli episodi, griglia del Catalogo e di La mia lista, risultati della Ricerca, pagina della Persona. `LoadingView` (lo spinner) resta solo per azioni piccole, dentro pulsanti e pannelli.

### 10.3 Dallo scheletro al contenuto

Dissolvenza incrociata di `medium` (`AnimatedSwitcher`), poi l'entrata scaglionata del contenuto (§8.2, §9, §11.5).

## 11. Il resto dell'app

### 11.1 Barra in alto (`app_shell.dart`)

- **Sottolineatura scorrevole:** una sola linea oro sotto la voce attiva, che scorre da una voce all'altra in `medium` (`emphasized`). Posizione misurata dalle voci con `GlobalKey`.
- **Barra sovrapposta:** la barra (64 px) diventa un livello sopra il contenuto (`Stack`) invece di stare sopra in una `Column`.
  - Home e scheda del titolo: lo sfondo arriva fino al bordo alto della finestra;
  - le altre pagine ricevono un margine superiore di 64 px e non cambiano aspetto.
- **Barra scura:** appena la pagina scorre (`ScrollNotification` di profondità 0 intercettate nella shell), la barra passa in `medium` a sfondo `bg` al 75% con sfocatura (`BackdropFilter`, sigma 12). Torna trasparente in cima.
- La card d'invito del watch party e il pulsante dei gruppi restano dove sono.

### 11.2 Pulsanti e icone (`wf_buttons.dart`)

- `WfButton` (primario e secondario): al passaggio del mouse alone oro (ombra oro al 30%, raggio 18) e scala 1,03; al clic "pressione" a 0,97; in `fast`.
- `WfIconToggle` (cuore, spunta): all'attivazione "pop" (scala 1 → 1,3 → 1, curva `bounce`) e riempimento. Alla disattivazione, solo il riempimento che si svuota.
- Icone della barra (indietro, cerca, gruppi, utente): si tingono d'oro al passaggio del mouse.
- Ridotte: niente scala né pop, i colori cambiano in `fast`.

### 11.3 Avvio e login

- **Splash:** il logo compare scalando da 0,9 a 1 con dissolvenza, poi un riflesso oro lo attraversa una volta (`ShaderMask` con gradiente animato). Nessuna animazione infinita: lo splash non deve aspettarla per proseguire.
- **Login:** il pannello sale in dissolvenza. Password e Quick Connect usano il `TabBarView` esistente, che scorre già tra le due schede: resta com'è.
- Anche le schermate "Server non raggiungibile" e "Aggiornamento obbligatorio" entrano in dissolvenza.

### 11.4 Menu, dialoghi e avvisi

- **Menu a comparsa:** `popUpAnimationStyle` non esiste in `PopupMenuThemeData` (Flutter 3.47), solo come parametro di `PopupMenuButton`/`showMenu`. Si passa a ciascun menu un `AnimationStyle` costruito da `WfMotion` (`wfPopUpAnimation` in `lib/ui/wf_menus.dart`), così usano durata e curva dei token. Sono i tre menu fuori dal player (menu utente e i due del watch party); il badge del player non si tocca.
- **Dialoghi:** nell'app non ce ne sono, quindi nessun `showWfDialog` e nessun `showDialog`.
- **Card d'invito del watch party:** entra da destra con dissolvenza, esce in dissolvenza.
- **Banner di aggiornamento:** **sale dal basso** (sta in basso).
- **Snackbar:** stile del tema (flottante), animazione predefinita.

### 11.5 Griglie

- Catalogo, La mia lista, Ricerca, Persona: le locandine entrano scaglionate (§8.2) a ogni nuova pagina di risultati, **solo le nuove** e al massimo le prime 12 per blocco (`BatchedEntrance`/`BatchedEntranceItem`, un controller per blocco caricato, liberato a entrata finita), così lo scroll infinito non rallenta. Togliere un elemento (per esempio un preferito da La mia lista) non fa rientrare nulla.
- Cambio di filtro, ordinamento o ricerca: la griglia fa una dissolvenza incrociata, poi l'entrata scaglionata.
- **Ricerca:** le card rientrano quando arrivano risultati nuovi, non a ogni lettera (mentre si scrive restano i risultati di prima).
- **Struttura stabile:** a entrata finita le card delle griglie mantengono la stessa struttura (`EntranceTransition` con animazione completa): non si ricreano e non perdono lo stato (immagini, anteprima aperta).

### 11.6 Impostazioni

Il titolo e le sezioni (ognuna con il proprio titolo) entrano scaglionati all'apertura. Nuova sezione "Aspetto" (§4.3).

## 12. Prestazioni

- Tutto ciò che si muove passa da `Transform`, `Opacity`/`FadeTransition` e `ShaderMask`: niente ricalcoli del layout durante le animazioni.
- Parallasse e barra scura con `AnimatedBuilder`/listener sul controller dello scroll, senza `setState` della pagina.
- `RepaintBoundary` su card, righe, carosello, shimmer, anteprima.
- Immagini dell'anteprima e del volo decodificate alla dimensione mostrata (`memCacheWidth`, come `WfImage`), con la stessa cache su disco.
- `BackdropFilter` solo sulla barra (64 px), non su superfici grandi.
- Il carosello fermo (pagina coperta, mouse sopra) non anima nulla, Ken Burns compreso.
- **Obiettivo: 60 fps.** Si verifica nella prova manuale con `flutter run --profile` e l'overlay delle prestazioni: Home (carosello + entrata), anteprima, volo Hero, parallasse, shimmer.

## 13. Prove

### 13.1 Automatiche

- **Unitarie:**
  - livello effettivo (tabella §4.5) e salvataggio dell'impostazione;
  - `SmoothScrollPosition`: gli scatti si sommano, la destinazione resta nei limiti, uno scatto a metà animazione riparte dalla posizione attuale, un `jumpTo` o un trascinamento annullano la destinazione;
  - posizione dell'anteprima vicino ai quattro bordi e con card piccole;
  - intervalli dello scaglionamento (numero di figli, massimo, ritardo);
  - `WfHeroTag` (uguaglianza, unicità per sorgente).
- **Widget:**
  - l'anteprima si apre dopo 500 ms e non prima, si chiude con uscita del mouse, rotella ed Esc, ne resta aperta una sola, il passaggio diretto a un'altra card la apre subito, niente anteprima sulle card degli episodi;
  - pulsanti dell'anteprima (riproduci, lista, visto, dettagli);
  - carosello con `fakeAsync`: cambio a 8 s, pausa con il mouse sopra, clic su un puntino;
  - titolo e "Riproduci" nella barra dopo lo scroll della scheda, e via alla chiusura;
  - sottolineatura della barra sulla voce attiva;
  - "Animazioni" in Impostazioni;
  - schermate principali in modalità ridotta senza animazioni residue;
  - **nessun timer pendente** a fine test (helper di chiusura che smonta l'albero e avanza il tempo).
- **Esistenti:** partono in modalità ridotta (§4.6). Si aggiornano quelli che cercano il pulsante play sulle card con anteprima (`test/ui/cards_test.dart` e simili) e quelli della struttura della shell.
- `flutter analyze` pulito, tutti i test verdi.

### 13.2 Manuali (sul server reale)

- Rotella del mouse: morbida su Home, scheda, catalogo; touchpad invariato; righe orizzontali con Shift + rotella e frecce.
- Anteprima: apertura, passaggio tra card, bordi della finestra, pulsanti, "Dettagli" con volo.
- Volo Hero da locandina, da card orizzontale, da anteprima, dal cast; indietro.
- Carosello, entrata delle righe, parallasse, titolo nella barra, cambio di stagione.
- Shimmer su connessione lenta (per esempio con la finestra appena aperta, cache vuota).
- Barra, pulsanti, splash e login, menu e dialoghi, griglie con scroll infinito e filtri.
- "Animazioni": *Ridotte*, *Complete*, *Come Windows* con "Effetti di animazione" di Windows acceso e spento (cambiandolo con l'app aperta).
- Build `--profile` con l'overlay delle prestazioni: 60 fps nei punti del §12.
- Regressioni: player, watch party (inviti, badge, "Guarda insieme" dalla scheda; l'anteprima non lo mostra), Discord.

## 14. Rischi e punti aperti

- **Hero e go_router:** il `HeroControllerScope` del navigatore della `ShellRoute` esiste da go_router 6.0.7. Il volo tra `/home` e `/item/:id` (stessa shell, `push`) va verificato presto, nel primo piano che lo usa.
- **Barra sovrapposta:** cambia la struttura della shell e i margini di tutte le pagine; è il punto con più rischio di regressioni visive (card d'invito, pulsante indietro, pagina persona).
- **Anteprima e scroll:** l'anteprima è in un overlay: con la rotella si chiude subito, così non resta "staccata" dalla card.
- **Preferenza di Windows:** `SPI_GETCLIENTAREAANIMATION` è la voce "Effetti di animazione" di Impostazioni → Accessibilità; se Windows non avvisa del cambio, basta il controllo al ritorno del focus.
- **Test lenti o bloccati:** qualunque animazione infinita (shimmer, Ken Burns) deve essere spenta in modalità ridotta, altrimenti `pumpAndSettle` non termina.
- **Versione:** nuova funzione, quindi release **0.3.0**, non obbligatoria.

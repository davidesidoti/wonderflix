# WonderFlix — Spec D: rinnovo del player

- **Data:** 2026-10-01
- **Stato:** realizzato nei piani 8a, 8b e 8c (`docs/superpowers/plans/2026-10-01-wonderflix-08a-player-fondamenta-controlli.md`, `…-08b-player-momenti.md`, `…-08c-player-fine-episodio-party.md`), provato dall'utente
- **Ambito:** Spec D. Porta nel player il linguaggio dello Spec C (`2026-09-30-wonderflix-rinnovo-grafico-design.md`, token `WfMotion`, livello completo/ridotto), che lo aveva escluso. Si appoggia allo Spec A (`2026-09-29-wonderflix-client-core-design.md`, player) e allo Spec B (`2026-09-30-wonderflix-watch-party-design.md`, §7 interfaccia del watch party nel player), tutti realizzati (v0.3.1).

## 1. Obiettivo

Rendere il player all'altezza del resto dell'app: controlli, barra, pannelli, avvisi e momenti di passaggio (caricamento, pausa, fine episodio) con lo stesso movimento e la stessa cura dello Spec C.

- **La disposizione dei controlli resta quella di oggi**; colori, font e logo non cambiano.
- **Il movimento si fa da parte davanti al film** (decisione dello Spec C): niente sopra il video che si muova senza motivo, riscontri piccoli e brevi, nessuna sfocatura sopra il video.
- Il player segue **Impostazioni → Aspetto → Animazioni** come il resto dell'app.

## 2. Situazione di partenza

- `lib/features/player/player_screen.dart` (~800 righe) tiene insieme riproduzione, watch party, finestra, tasti e interfaccia (timer dei controlli, pannello, scheda "Prossimo episodio"). Il player è escluso dai token: durate scritte a mano (200 ms dei controlli, 150 ms di `playerPage` in `lib/app/router.dart`).
- `PlayerOverlay` (`player_overlay.dart`): in alto indietro, titolo, badge del party; in basso `SeekBar` (uno `Slider` con tacche dei capitoli dipinte sopra e anteprima trickplay) e una riga di `IconButton` (indietro/avanti 10 s, play/pausa, volume con slider, tempo, episodio successivo, "Guarda insieme", tracce, schermo intero). I controlli compaiono e spariscono con un `AnimatedOpacity` di 200 ms; ogni tasto li fa ricomparire.
- Caricamento e buffering: schermo nero con `CircularProgressIndicator` oro. Errore: icona, titolo, testo e pulsanti su nero (`_PlayerError`).
- `TracksPanel` (`tracks_panel.dart`): riquadro a due colonne (Audio | Sottotitoli + ritardo) sopra i controlli, senza animazione. La dimensione dei sottotitoli si cambia solo in Impostazioni (`PlayerSettings.subtitleScale`, valori `subtitleScaleOptions`).
- `NextEpisodeCard` (`player_extras.dart`): scheda in basso a destra dall'inizio dei titoli di coda (segmento `Outro`) o negli ultimi 30 s (`nextEpisodeCardFrom` in `segments.dart`), conto alla rovescia di 10 s solo da soli con "Avvia automaticamente il prossimo episodio".
- "Salta intro / Salta riassunto": `WfButton.secondary` in basso a destra, senza animazione. Il salto automatico (`PlayerController._onPosition`) non dà riscontro.
- Watch party (`lib/features/watch_party/`): `PartyNoticePill` (avvisi in coda, 3 s ciascuno, `PartyNotices`), `PartyBadge` (chip "Watch party · N" con menu dei membri), `PartyWaitingOverlay` (dopo 1 s, su nero al 60%).
- Il video è un `Texture` di media_kit (`MediaKitEngine.buildView`): si ridisegna a ogni fotogramma, quindi ogni effetto sopra di lui ha un costo per fotogramma.

## 3. Decisioni

| Tema | Decisione |
|---|---|
| Perimetro | Tutto: controlli e barra, pannelli e schede, watch party nel player, momenti nuovi (caricamento, pausa, riscontro dei tasti, ingresso e uscita). |
| Disposizione | **Come oggi, rifinita.** Nessuna nuova disposizione. |
| Comparsa dei controlli | **Dissolvenza + scivolamento**: la parte alta scende, quella bassa sale (entrata `medium`, uscita `fast`). |
| Barra | **Segmenti per capitolo** + zone rigate per riassunto, intro e titoli di coda; l'anteprima le nomina. |
| Riscontro dei tasti | **Pillola in alto** al centro, la stessa degli avvisi del party. **I tasti mostrano solo la pillola**: i controlli compaiono solo con il mouse. |
| Caricamento | **Sfondo del titolo scurito + logo al centro + linea oro**; lo sfondo sfuma nel film al primo fotogramma. |
| Pausa | **"Stai guardando" con trama** (stile Netflix) dopo 8 s di pausa con il mouse fermo, anche nel watch party. |
| Prossimo episodio | **Il film si rimpicciolisce** (post-play stile Netflix) all'inizio dei titoli di coda noti (`Outro`). **Senza `Outro`**: scheda piccola negli ultimi 30 s, rinnovata. |
| Audio e sottotitoli | **Pannello laterale** a tutta altezza **+ dimensione dei sottotitoli**, che si salva nelle impostazioni. |
| Watch party | Avvisi nella pillola con icona; badge con iniziali dei membri; attesa del gruppo animata. |
| "Salta intro", buffering, errore | Pulsante che entra da destra con linea che si accorcia; spinner solo oltre 300 ms; errore sullo sfondo del titolo. |
| Codice | **`PlayerChromeController` + strati separati**; la logica di riproduzione e del gruppo non si tocca. |
| Release | **0.4.0**, non obbligatoria, dopo l'ultimo piano. |

## 4. Perimetro

### Incluso

- Architettura dell'interfaccia del player (§5), movimento e prestazioni (§6).
- Controlli (§7), barra di avanzamento (§8), tastiera e pillola (§9).
- Caricamento, buffering ed errore (§10), schermata di pausa (§11).
- Fine episodio: post-play e scheda (§12), "Salta intro" (§13).
- Pannello Audio e sottotitoli (§14), watch party nel player (§15).

### Escluso

- Nuove disposizioni dei controlli, comandi al centro dello schermo.
- Tempo che manca al posto del totale.
- Chat, reazioni, nome di chi agisce nel watch party (limite del server, vedi handoff).
- Trailer, HDR, cambio di qualità durante la visione.
- I punti aperti del player elencati nell'handoff (report di fine se si chiude durante il caricamento, remux come "Transcode", ecc.).

## 5. Architettura

### 5.1 `PlayerChromeController`

Nuovo file `lib/features/player/player_chrome.dart`. È un `ChangeNotifier` in Dart puro, creato e distrutto da `_PlayerScreenState`. Tiene **solo lo stato dell'interfaccia**, mai quello della riproduzione.

Stato:

- `controlsVisible`: controlli mostrati.
- `pauseScreen`: schermata "Stai guardando" mostrata.
- `panelOpen`: pannello Audio e sottotitoli aperto.
- `postPlayDismissed`: l'utente ha chiuso il post-play o la scheda ("Guarda i titoli", "Annulla", Esc, clic sul film piccolo); per quell'episodio non tornano.
- `feedback`: riscontro corrente di un tasto (`PlayerFeedback?`, vedi §9), con la somma dei salti.

Ingressi (chiamati da `PlayerScreen`):

- `pointerActivity()`: il mouse si è mosso → controlli visibili, schermata di pausa chiusa, tempi azzerati.
- `setPlayback({required bool playing, required bool canShowPauseScreen})`: in riproduzione i controlli si nascondono dopo **3 s** di mouse fermo (`PlayerChromeController.hideDelay`); in pausa, dopo **8 s** di mouse fermo (`pauseScreenDelay`) i controlli si nascondono e compare la schermata di pausa, se `canShowPauseScreen` (vedi §11.1).
- `togglePanel()` / `closePanel()`: con il pannello aperto i controlli non si nascondono e la pausa non compare.
- `showFeedback(PlayerFeedback)`: mostra il riscontro per **1,2 s** dall'ultima pressione (`feedbackDuration`), senza far comparire i controlli.
- `seek(step, from:, duration:)`: il salto da tastiera. I salti nella stessa direzione entro **1 s** (`seekSumWindow`) si sommano: l'offset è la somma e l'arrivo parte da quello del salto precedente (non dalla posizione del motore, che può non essersi ancora mossa), tra 0 e la durata. Poi mostra il riscontro con `showFeedback`.
- `isRecentKeyAction(PartyNoticeKind)`: per il watch party (vedi §9.3), dice se nell'ultimo secondo (`keyActionWindow`) un tasto ha fatto la stessa azione di gruppo: pausa, ripresa o salto. Le azioni da tastiera si ricordano **per tipo** (l'ultimo Spazio con il suo stato, l'ultimo salto), non solo l'ultimo riscontro: ← seguito da ↑ o da Spazio non fa dimenticare il salto, il cui avviso "Hai…" arriva anche 400 ms dopo.
- `keyActivity()`: un tasto premuto chiude la schermata di pausa e riparte da capo con gli 8 s, **senza** mostrare i controlli.
- `dismissPostPlay()`: chiude post-play o scheda (vale per entrambi); i controlli tornano e riparte il loro conto.

**Il controller non ha uno stato `postPlay`.** Post-play e scheda li calcola `PlayerScreen`:

- tiene una zona di fine episodio, `_endZone` (`EndZone`: `none`, `credits`, `lastSeconds`; `endZoneAt` in `segments.dart`), ricalcolata da `_updateEndZone` con la posizione del motore, la durata e i segmenti di adesso (ognuno può arrivare per ultimo, per esempio i segmenti a video fermo nei titoli). Cambia poche volte: solo allora la schermata si ricostruisce;
- il post-play è la zona `credits`, la scheda la zona `lastSeconds`; per entrambi serve anche un episodio successivo (nel gruppo il prossimo della coda, `WatchPartyState.nextEntry`), il player in stato `ready` e l'offerta non chiusa (`postPlayDismissed`);
- il post-play può comparire o sparire anche senza un cambio di zona (aggiornamento della coda del gruppo, uscita dal gruppo, episodio successivo arrivato tardi, stato del file). Quando compare, **per qualsiasi motivo**, il pannello si chiude e la schermata di pausa si rivaluta: lo fa un `addPostFrameCallback` in `build`, che confronta il post-play di adesso con quello dell'ultima costruzione (`_postPlayWasShown`).

Usa `clock` e `Timer` cancellabili, quindi si prova con `fake_async`. In `dispose` cancella tutti i timer.

### 5.2 Strati

Ogni strato è un widget nel suo file in `lib/features/player/`, montato nello `Stack` di `PlayerScreen` in quest'ordine (dal basso):

1. video (`engine.buildView()`, dentro `PostPlayFrame` che lo rimpicciolisce nel post-play, §12.1);
2. `player_loading.dart`: `BufferingSpinner` (spinner del buffering, §10.2);
3. `PartyWaitingOverlay` (§15.3);
4. `pause_screen.dart`: `PauseScreen` (§11);
5. `PlayerOverlay` (controlli, §7–8), oppure `PlayerErrorLayer` (errore, §10.3) al suo posto;
6. `player_loading.dart`: `PlayerLoadingLayer` (caricamento, §10.1), sopra i controlli: durante il caricamento i controlli sono nascosti e la freccia per uscire sta nello strato;
7. `skip_button.dart`: `SkipSegmentButton` (§13), e subito sopra la scheda piccola del prossimo episodio (`NextEpisodeCard` in `player_extras.dart`, §12.2): due strati distinti;
8. `post_play.dart`: `PostPlayLayer` (informazioni del post-play, §12.1). Questo strato (sempre nello `Stack`) e quello della scheda piccola (con il player `ready`) sono due **posti fissi**: quello che cambia è il contenuto, dentro un `AnimatedSwitcher` (§12.1);
9. `player_pill.dart`: `PlayerPill` (§9);
10. `tracks_panel.dart`: `TracksPanelHost` con il `TracksPanel` laterale (§14).

Ogni strato ha una `ValueKey`: i figli dello `Stack` si abbinano per posizione, e uno strato condizionale che compare o sparisce farebbe rimontare (perdendo lo stato) quelli vicini.

`player_screen.dart` resta il punto in cui si collegano motore, `PlayerController`, watch party, finestra, sessione media e tasti; perde la parte di interfaccia (timer dei controlli, `_PlayerError`, logica della scheda), che passa al controller e agli strati.

### 5.3 Modifiche fuori dall'interfaccia

- **`VideoEngine`:** nuovo `Future<void> get firstFrame`. `MediaKitEngine` lo prende da `VideoController.waitUntilFirstFrameRendered` (su Windows si completa una sola volta per motore, al primo `VideoOutput.Resize` con dimensioni valide). `FakeVideoEngine` lo completa a comando.
- **`PlayerController`:**
  - espone i salti automatici di intro e riassunto (`Stream<SkipKind> autoSkips`) per la pillola (§9);
  - `setSubtitleScale(double)`: applica subito la dimensione al motore e la salva in `playerSettingsProvider` (§14).
- **`segments.dart`:** `outroStart(segments)` (inizio dell'`Outro`, o `null`); `nextEpisodeCardFrom` (da quando si propone l'episodio successivo, e da quando quello lasciato conta come visto: l'`Outro` se c'è, altrimenti gli ultimi 30 s, `null` se la durata non è nota); `EndZone` (`none`, `credits`, `lastSeconds`) ed `endZoneAt(segmenti, durata, posizione)`, che dicono a `PlayerScreen` se mostrare il post-play, la scheda piccola o niente (§5.1).
- **`PartyNotices`:** `mine` riceve `{bool show = true}`: con `show: false` registra l'eco senza mostrare l'avviso (§9.3). Il resto della logica non cambia.

## 6. Movimento e prestazioni

### 6.1 Token

Tutto passa da `WfMotion` (`lib/app/motion.dart`), comprese le durate oggi scritte a mano nel player. Nessun token nuovo:

| Effetto | Durata | Curva |
|---|---|---|
| Entrata di controlli, pillola, pannello, pulsante "Salta", scheda piccola | `medium` | `emphasized` (pulsante e scheda: `bounce`) |
| Uscite | `fast` | `accelerate` |
| Rimpicciolimento del film, sfondo del caricamento che sfuma nel film, schermata di pausa | `slow` | `emphasized` / `standard` |
| Barra (altezze), cursore, spunta, anteprima | `fast` | `emphasized` / `bounce` |
| Voci del pannello, errore, attesa del gruppo | scaglionate di 40 ms (pannello) o `WfMotion.stagger` | `emphasized` |

Le animazioni continue esistono solo dove indicano un'attesa: spinner, linea del caricamento (periodo `loadingLinePeriod` = 1,2 s), clessidra dell'attesa del gruppo (periodo `hourglassPeriod` = 2,4 s) e puntini (`waitingDotsPeriod` = 1,2 s), riempimento oro del conto alla rovescia di "Riproduci ora" (a passi lineari di 1 s, uno per secondo del conto: chiede fotogrammi finché il conto corre, §12.1). I periodi sono costanti nominate e commentate.

### 6.2 Livello ridotto

Con **Animazioni → Ridotte** (o "Come Windows" con gli effetti spenti):

- niente scivolamenti, rimbalzi né scale: solo dissolvenze di `fast` (150 ms);
- il film passa alla posizione del post-play in `fast`;
- clessidra e puntini dell'attesa del gruppo fermi; spinner e linea del caricamento restano (indicano un'attesa);
- il riempimento del conto alla rovescia non si muove tra un secondo e l'altro: scatta di un passo a ogni secondo.

### 6.3 Ingresso e uscita dal player

`playerPage` (`lib/app/router.dart`) usa i token:

- **ingresso:** dissolvenza incrociata in `medium` (niente `ColoredBox` nero): la scheda sfuma nello sfondo del caricamento, che è la stessa immagine della testata;
- **sostituzione di un player** (episodio successivo, player del gruppo: `pushReplacement` con `extra: playerReplacement`): resta il nero sotto la transizione, perché la pagina sotto non è quella di partenza;
- **uscita:** dissolvenza in `fast`.

### 6.4 Prestazioni

- Nessun `BackdropFilter` (sfocatura) sopra il video: costerebbe a ogni fotogramma.
- Si animano solo opacità e spostamenti degli strati sopra il video; le immagini (sfondo, logo, episodio) sono ferme.
- `RepaintBoundary` attorno a barra, pillola e tempo, che cambiano molte volte al secondo.
- Il rimpicciolimento usa un `Transform` sul widget del video: cambia solo il disegno, il video nativo non viene ridimensionato.
- Misura con `flutter run --profile` e overlay delle prestazioni nella prova finale (anche per il punto aperto dello Spec C §12).

## 7. Controlli

### 7.1 Comparsa e scomparsa

- La parte alta (`PlayerOverlay`, gradiente e riga indietro/titolo/badge) scende di **24 px** mentre sfuma; quella bassa (barra e comandi) sale di 24 px. Entrata `medium` / `emphasized`, uscita `fast` / `accelerate`.
- Il cursore sparisce insieme ai controlli, come oggi.
- I controlli compaiono **solo con il mouse** (§9.1). Restano visibili con il pannello aperto.

### 7.2 Pulsanti

- Nuovo `PlayerIconButton` (in `player_overlay.dart`) per tutte le icone dei controlli, con il linguaggio di `WfButton`: al passaggio del mouse fondo crema al 12%, alone oro, scala 1,08 (nessuna scala con il livello ridotto); premuto, scala 0,97.
- Play/pausa: l'icona cambia con una dissolvenza in scala (`fast`).
- Volume (slider), tempo e ordine dei pulsanti restano come oggi.

## 8. Barra di avanzamento

`SeekBar` (`seek_bar.dart`) diventa un widget proprio con `CustomPaint` e `GestureDetector` (clic e trascinamento come oggi). `Slider` non sa disegnare segmenti.

### 8.1 Segmenti

- Un tratto per capitolo (`ChapterMark.start > 0` apre un tratto nuovo), separati da **3 px**. Senza capitoli la barra è unica.
- I capitoli che sullo schermo sarebbero più corti di **8 px** si uniscono al tratto precedente (niente briciole).
- Colori come oggi: parte vista oro, scaricata crema al 35%, resto crema al 15%.

### 8.2 Altezze e cursore

- **4 px** a riposo, **6 px** con il mouse sulla barra, **9 px** per il tratto sotto il mouse; passaggi in `fast` / `emphasized`.
- Il cursore oro (raggio 7 px, alone oro) è nascosto a riposo, compare con `bounce` al passaggio del mouse e resta durante il trascinamento.

### 8.3 Zone

- I segmenti `Recap`, `Intro` e `Outro` sono **rigati**: righe diagonali scure sopra il colore della barra, sia nella parte vista sia in quella da vedere. Gli altri tipi (`Preview`, `Commercial`) non si mostrano.

### 8.4 Anteprima

- L'immagine trickplay (240 px, bordo crema, angoli arrotondati) sale dalla barra crescendo da 0,92 e sfumando (`fast`), segue il mouse e anche il trascinamento; resta dentro la finestra.
- Sotto, l'etichetta "18:02 · Nome del capitolo" e, dentro una zona, l'etichetta oro "Riassunto", "Intro" o "Titoli di coda".
- Senza trickplay resta solo l'etichetta.
- `Semantics` con il valore della posizione (lo `Slider` lo dava già).

## 9. Tastiera e pillola

### 9.1 Comportamento dei tasti

- Le scorciatoie restano quelle di oggi (`player_commands.dart`).
- **Un tasto non mostra più i controlli**: mostra la pillola (se il comando ne ha una) e chiude la schermata di pausa (`keyActivity`).
- Esc chiude, in quest'ordine: pannello → post-play o scheda → schermo intero → player.

### 9.2 Riscontri

| Comando | Icona | Testo |
|---|---|---|
| Play/pausa | `play` / `pause` | "Riproduzione" / "In pausa" |
| ← / → | `rewind` / `fastForward` | "−10 s · 17:32", "+20 s · 18:02" (salti sommati, posizione di arrivo) |
| ↑ / ↓ | `volume2` / `volumeX` | "Volume 70%" |
| M | `volumeX` / `volume2` | "Audio disattivato" / "Volume 70%" |
| G / H | `captions` | "Sottotitoli +0,3 s" (formato di `formatSubtitleDelay`) |
| Salto automatico | `skipForward` | "Intro saltata" / "Riassunto saltato" |

F, N, Esc e Alt+← non hanno pillola: il loro effetto si vede già.

### 9.3 Una sola pillola

`PlayerPill` (`player_pill.dart`) prende il posto di `PartyNoticePill` nel player (stessa posizione: in alto al centro, 96 px dal bordo).

- Mostra il riscontro del tasto se c'è, altrimenti l'avviso corrente del party (`partyNoticesProvider`).
- Il riscontro del tasto prende subito il posto di quello che c'è; quando scade, se l'avviso del party è ancora nei suoi 3 s, torna visibile.
- Cambiando contenuto la pillola non sparisce: testo e icona sfumano (`fast`) e la larghezza si adatta (`AnimatedSize`, `medium`). Entrata: scende di 12 px sfumando (`medium`); uscita `fast`.
- La sfumatura parte solo quando cambia il **tipo** di contenuto (Spazio con il suo stato, salto indietro o avanti, volume, ritardo dei sottotitoli, un avviso nuovo del party). Con un tasto tenuto premuto (il testo cambia ogni ~33 ms) la riga si aggiorna sul posto e si adatta solo la larghezza. Con le animazioni ridotte non c'è `AnimatedSize`: la larghezza cambia di colpo.
- Larghezza massima 560 px (`PlayerPill.maxWidth`): un avviso più lungo resta su una riga e finisce con i puntini.
- **Watch party:** per pausa, ripresa e salti dati **da tastiera**, la pillola del tasto sostituisce l'avviso "Hai…". `PlayerScreen` passa a `GroupAuthority` un `onAction` che, se `isRecentKeyAction(kind)` dice che nell'ultimo secondo (`keyActionWindow`, più dei 400 ms di `GroupAuthority.seekDebounce`) un tasto ha fatto la stessa azione, chiama `PartyNotices.mine(kind, show: false)`: l'eco resta registrata (l'aggiornamento del server non produce un altro avviso) ma l'avviso "Hai…" non si mostra. Con il mouse si continua a vedere "Hai messo in pausa", "Hai saltato a…".
- `IgnorePointer`, `ExcludeFocus`.

## 10. Caricamento, buffering, errore

### 10.1 Caricamento (`PlayerLoadingLayer`)

- Visibile finché lo stato è `loading`, e dopo `ready` fino al **primo fotogramma** (`engine.firstFrame`). Per le aperture successive dello stesso motore ("Riprova", ripiego sulla conversione) basta `ready`.
- Se il motore non segnala il primo fotogramma entro 3 s da `ready` (`PlayerScreen.firstFrameTimeout`; per esempio un video del gruppo aperto in pausa), il caricamento sfuma comunque.
- Sfondo: `urls.backdrop(item)` a 1920 px (la stessa immagine della testata della scheda, già in cache), scurito al 55%.
- Al centro il logo (`urls.logo(item)`, per gli episodi quello della serie), largo al massimo il 40% della finestra e alto al massimo 160 px; senza logo il titolo in Bebas (`WfText.display`), per gli episodi il nome della serie.
- Sotto, una linea oro sottile (3 × 200 px) che scorre con periodo `loadingLinePeriod`.
- Prima che arrivi l'elemento restano solo il nero e la linea; sfondo e logo entrano sfumando (`fast`).
- Uscita: lo strato sfuma in `slow` e scopre il film.
- Durante il caricamento dei controlli resta solo la freccia "indietro" in alto a sinistra (per uscire), sopra lo strato; il resto compare a video partito.
- Vale anche passando all'episodio successivo (il nuovo player mostra lo sfondo del nuovo episodio) e nel player del gruppo.

### 10.2 Buffering

- Lo spinner oro attuale compare solo se il buffering dura più di **300 ms** (`bufferingSpinnerDelay`) e sfuma in entrata e in uscita (`fast`). Le attese brevi dopo un salto non fanno più lampeggiare nulla.

### 10.3 Errore (`PlayerErrorLayer`)

- Sfondo del titolo scurito al 75%, o nero se l'elemento non è arrivato.
- Icona, titolo, testo e pulsanti ("Riprova", "Indietro" / "Esci dal watch party") come oggi, ma entrano scaglionati con `StaggerGroup` / `StaggerItem` (`lib/ui/staggered_entrance.dart`).
- Come oggi, in errore i controlli non si mostrano.

## 11. Schermata di pausa (`PauseScreen`)

### 11.1 Quando

Compare quando **tutte** queste condizioni valgono:

- stato `ready`, video in pausa, nessun buffering, video non finito;
- da **8 s** (`pauseScreenDelay`) né movimenti del mouse né tasti;
- pannello chiuso, nessun post-play, nessuna attesa del gruppo visibile (`PartyWaitingOverlay` ha la precedenza).

Vale anche nel watch party, quando il gruppo è in pausa.

### 11.2 Contenuto

- Sfumatura nera da sinistra (88% → 15%) sopra il fermo immagine.
- A sinistra, centrati in verticale: "STAI GUARDANDO" in oro; il logo (o il titolo in Bebas); per gli episodi "S1:E3 · Titolo" (`cardSubtitle`); anno · durata · al massimo due generi (si omette ciò che manca); la trama (`overview`), al massimo 4 righe con i puntini.
- In basso a destra: icona `pause` e "In pausa".

### 11.3 Movimento

- Entra sfumando in `slow`, con il testo che sale di 16 px; i controlli sfumano via insieme.
- Esce in `fast` al primo movimento del mouse (tornano i controlli), a un tasto (§9.1), alla ripresa. Un clic sul film riprende la riproduzione, come oggi.

## 12. Fine episodio

### 12.1 Post-play (solo con segmento `Outro`)

**Quando:** la zona di fine episodio è `credits` (la posizione è ≥ `outroStart`), c'è un episodio successivo (nel party: è il prossimo della coda, come oggi), il player è `ready` e il post-play non è stato chiuso. `PlayerScreen` lo ricalcola dalla posizione, dalla durata e dai segmenti (§5.1).

**Movimento e disposizione:**

- Il film si rimpicciolisce al **42%** della finestra, ancorato in alto a sinistra con 32 px di margine, angoli arrotondati (12 px) e un bordo crema sottile (`slow` / `emphasized`; `Transform` + `ClipRRect` in `PostPlayFrame`). Il `Transform` sposta anche il bersaglio dei clic.
- I controlli si nascondono e non ricompaiono con il mouse; il cursore resta visibile.
- Se all'inizio dei titoli il pannello "Audio e sottotitoli" è aperto, **il pannello si chiude** (vale ogni volta che il post-play compare, §5.1).
- Sotto il film, a sinistra (`PostPlayLayer`, entra sfumando in `medium` quando il rimpicciolimento è a metà): "PROSSIMO EPISODIO" in oro; il nome della serie in Bebas; "S1:E4 · Titolo"; la trama (al massimo 3 righe); i pulsanti. La colonna è larga quanto il film piccolo e arriva fino a 32 px dal fondo.
- **Quando lo spazio non basta (finestra bassa, testo grande) cede la trama**: restano solo le righe intere che entrano (fino a 3, con i puntini sull'ultima), e se non ne entra nessuna la trama sparisce. Titoli e pulsanti restano sempre visibili.
- A destra: l'immagine grande dell'episodio (`urls.landscape(next)`, 16:9, angoli arrotondati, ombra), che riempie lo spazio rimasto a destra del film piccolo (circa la metà della finestra) ed è **limitata nei due sensi**: in una finestra molto larga non esce dal fondo.
- **I due posti** (post-play e scheda piccola) hanno un `AnimatedSwitcher` ciascuno (chiave: l'episodio successivo). Il contenuto nuovo è subito opaco (`switchInCurve` `Threshold(0)`), perché ha già la sua entrata e altrimenti sfumerebbe due volte; quando esce, sfuma in `fast`.

**Pulsanti:**

- **"Riproduci ora"** (primario, `PlayNowButton` in `player_extras.dart`, lo stesso della scheda piccola):
  - da soli con "Avvia automaticamente il prossimo episodio" il fondo si riempie d'oro in **10 s** (da sinistra; la parte ancora da riempire è oro al 35%) e l'etichetta conta ("Riproduci ora · 7"); a zero parte l'episodio. Senza l'impostazione, o nel watch party, niente conto alla rovescia. Nel party il pulsante fa passare il gruppo all'elemento dopo (`nextItem`, come oggi);
  - il conto è un `Timer` al secondo, fermo in pausa e durante il buffering;
  - **con le animazioni complete il riempimento è continuo**: a ogni secondo parte un passo lineare di 1 s che arriva al passo successivo proprio quando il secondo scatta. In pausa o durante il buffering il fondo torna in `fast` sull'ultimo passo compiuto, e alla ripresa il secondo riparte da zero. Con le animazioni ridotte il fondo scatta di un passo a ogni secondo e **tra un secondo e l'altro non si muove**, quindi non chiede fotogrammi;
  - l'etichetta ha due toni, divisi dove arriva il fondo: crema sulla parte non riempita, scura sull'oro;
  - l'altezza segue la densità del tema, come `WfButton` (44 px, 36 con la densità compatta di Windows); la larghezza è riservata per l'etichetta più larga ("· 10"), così non balla a ogni secondo;
  - **agisce solo se l'offerta è ancora mostrata** (`PlayerScreen._playOffered`), sia con il clic sia allo scadere del conto: uscendo, il pulsante resta montato un attimo dentro l'`AnimatedSwitcher`, e il suo conto potrebbe scadere dopo che l'utente ha chiuso il post-play.
- **"Guarda i titoli"** (secondario): il film torna a tutto schermo (`slow`) e il post-play si chiude. Lo stesso con Esc (a video non finito) o con un clic sul film piccolo; **un clic sullo sfondo fuori dal film piccolo non fa nulla**.

**A fine video:**

- post-play chiuso dall'utente: si esce come oggi;
- post-play aperto, da soli e senza conto alla rovescia: **si resta sul post-play** (film piccolo fermo sull'ultimo fotogramma) finché non si sceglie; Esc o "indietro" escono;
- nel watch party: si passa all'elemento dopo come oggi.

La schermata di pausa non compare durante il post-play (se compare quando è già in pausa, si chiude); tasti e pillola continuano a funzionare.

### 12.2 Scheda piccola (senza segmento `Outro`)

- Negli **ultimi 30 s** (zona `lastSeconds`, stesse condizioni di §12.1 sull'episodio successivo) compare la scheda attuale in basso a destra (`NextEpisodeCard`), rinnovata: entra da destra di 40 px con `bounce` (`medium`), esce in `fast`.
- Il conto alla rovescia diventa il riempimento oro di "Riproduci ora · N" (`PlayNowButton`, stesse regole di §12.1, compreso il fatto che agisce solo se la scheda è ancora mostrata); "Annulla" resta e chiude la scheda. Anche Esc la chiude, come "Annulla".
- Il film resta a tutto schermo.

## 13. "Salta intro" / "Salta riassunto" (`SkipSegmentButton`)

- Stessa posizione di oggi (in basso a destra, visibile anche a controlli nascosti).
- Entra da destra di 40 px (`medium` / `bounce`), esce in `fast`.
- Una linea oro (3 px, con gli angoli in basso arrotondati come il pulsante) alla base si accorcia con il tempo che manca alla fine del segmento; il pulsante segue la posizione del motore e ridisegna la linea solo se cambia di almeno lo 0,5%.
- Al passaggio del mouse: alone oro e scala 1,03 (come `WfButton`).
- Con "Salta automaticamente intro e riassunti" il salto avviene da solo (come oggi: solo da soli, una volta per segmento) e la pillola lo dice:
  - `PlayerController.autoSkips` è un `Stream<SkipKind>` (broadcast) che emette `intro` o `recap` a ogni salto automatico;
  - `PlayerScreen` lo ascolta e chiama `showFeedback(SkipFeedback(kind))` sul `PlayerChromeController`;
  - `PlayerPill` mostra l'icona `skipForward` e "Intro saltata" / "Riassunto saltato" (§9.2). Il salto manuale con il pulsante non ha pillola.

## 14. Pannello "Audio e sottotitoli" (`TracksPanel`)

- **Forma:** a tutta altezza sul lato destro, largo **360 px** (al massimo il 35% della finestra); fondo `WfColors.surface` al 94%, senza sfocatura; bordo `WfColors.border` a sinistra. Il film resta visibile, scurito appena verso il pannello (gradiente nero fino al 45%).
- **Movimento:** entra scorrendo da destra (`medium` / `emphasized`), le voci entrano scaglionate di 40 ms; esce in `fast`.
- **Contenuto** (in colonna, scorre se non ci sta):
  1. intestazione "Audio e sottotitoli" con una × per chiudere;
  2. **Audio**: le tracce;
  3. **Sottotitoli**: "Nessuno" e le tracce;
  4. **Ritardo**: −, valore, + (come oggi);
  5. **Dimensione**: Piccoli · Normali · Grandi · Molto grandi (`subtitleScaleOptions`, testi di Impostazioni). Si applica subito (`PlayerController.setSubtitleScale`) e **si salva** in Impostazioni → Player. Quattro pillole selezionabili (non il selettore delle Impostazioni), con le stesse etichette (`subtitleScaleLabel`).
- La traccia scelta ha il testo crema in grassetto e la spunta oro, che compare con `bounce`.
- **Chiusura:** ×, clic sul film o Esc (il pannello, sopra i controlli, copre l'icona dei sottotitoli). Con il pannello aperto i controlli restano visibili e la schermata di pausa non compare.

## 15. Watch party nel player

### 15.1 Avvisi

Gli avvisi passano nella `PlayerPill` (§9.3) con i testi di oggi (`partyNoticeText`) e un'icona oro:

| Avviso | Icona |
|---|---|
| pausa | `pause` |
| ripresa, ripresa senza aspettare | `play` |
| salto | `fastForward` |
| entra | `userPlus` |
| esce | `userMinus` |
| episodio successivo | `skipForward` |
| nuovo titolo | `clapperboard` |
| riallineamento | `refreshCw` |
| gruppo terminato | `circleStop` |
| tolto dal gruppo | `logOut` |

### 15.2 Badge

- Le iniziali dei membri sono `MemberAvatarStack` (di `MemberAvatar`, sovrapposte di 8 px; al massimo 3, poi "+N") accanto a "Watch party · N", **solo nel badge del player** (`PartyBadge`). Il chip della barra in alto (`PartyChip`, in `watch_party_button.dart`) resta com'è, senza iniziali.
- Chi entra compare con un "pop" (`bounce`; con le animazioni ridotte sfuma soltanto). Chi esce fa stringere la fila: la larghezza si adatta con un `AnimatedSize` (`medium` / `emphasized`), senza una dissolvenza a parte.
- Il badge fa un piccolo sobbalzo (scala 1,08: sale nel primo 40% del tempo con `decelerate`, poi torna a 1 con `bounce`; `medium` in tutto) a ogni cambio del numero di membri. Con le animazioni ridotte non c'è sobbalzo.
- Il menu dei membri usa `wfPopUpAnimation` (`lib/ui/wf_menus.dart`), come gli altri menu dell'app.

### 15.3 Attesa del gruppo (`PartyWaitingOverlay`)

- Compare dopo 1 s come oggi, ma sfumando (`medium`); sfuma via in `fast` e, sparita, non è nell'albero.
- La clessidra sta ferma per il 70% del periodo e poi si gira (`hourglassPeriod`); tre puntini oro pulsano uno dopo l'altro (`waitingDotsPeriod`); clessidra, testo, puntini e pulsante "Riprendi senza aspettare" entrano scaglionati.
- Con il livello ridotto clessidra e puntini restano fermi.

## 16. Testi nuovi (ARB, it + en)

- Pillola: "Riproduzione", "In pausa", "{offset} · {time}" per i salti, "Volume {percent}%", "Audio disattivato", "Sottotitoli {delay}", "Intro saltata", "Riassunto saltato".
- Barra: "Riassunto", "Intro", "Titoli di coda".
- Pausa: "Stai guardando" (e "In pausa", condiviso con la pillola).
- Post-play e scheda: "Riproduci ora · {seconds}", "Guarda i titoli".
- Pannello: "Dimensione" e "Chiudi" (tooltip della ×; `watchPartyDismiss` è del watch party e non si riusa). Le dimensioni riusano `settingsSubtitleSmall/Normal/Large/Huge`.
- Il testo "Inizia tra {seconds} s" (`playerNextEpisodeIn`) non serve più e si toglie.

## 17. Test

- **`PlayerChromeController`** (`fake_async` + `clock`): controlli nascosti dopo 3 s in riproduzione; schermata di pausa dopo 8 s in pausa e solo se ammessa; il mouse azzera i tempi e chiude la pausa; un tasto chiude la pausa senza mostrare i controlli; il pannello blocca la scomparsa e la pausa; salti sommati entro 1 s e nella stessa direzione; scadenza del riscontro dopo 1,2 s; `dispose` senza timer pendenti.
- **Barra:** segmenti per capitolo; unione dei capitoli più corti di 8 px; zone solo per `Recap`/`Intro`/`Outro`; etichetta dell'anteprima con capitolo e zona; clic e trascinamento chiamano `onSeek`.
- **Pillola:** riscontro del tasto sopra l'avviso del party e ritorno dell'avviso; nel party, avviso "Hai…" non mostrato dopo un tasto dello stesso tipo, mostrato dopo un clic.
- **Caricamento:** sfondo e logo; titolo di ripiego; resta fino a `firstFrame`, poi sfuma; con `ready` dopo "Riprova".
- **Buffering:** nessuno spinner sotto i 300 ms.
- **Pausa:** compare solo con tutte le condizioni di §11.1; contenuto (episodio, generi, trama); il mouse la chiude.
- **Post-play:** compare solo con `Outro`; conto alla rovescia da soli con l'impostazione, fermo in pausa; nel party senza conto alla rovescia e con `nextItem`; "Guarda i titoli"/Esc/clic lo chiudono; a fine video si resta sul post-play aperto senza conto alla rovescia. Scheda piccola negli ultimi 30 s senza `Outro`.
- **"Salta":** entra con il segmento, linea proporzionale al tempo che manca; pillola al salto automatico (`autoSkips`).
- **Pannello:** voci e chiusure; la dimensione chiama il motore e si salva nelle impostazioni.
- **Watch party:** icone degli avvisi; badge con iniziali e "+N"; attesa con livello ridotto ferma.
- Si adattano i test esistenti del player (`player_overlay_test`, `player_screen_test`, `seek_bar_test`, `tracks_panel_test`, `player_extras_test`) e del watch party nel player.
- `pumpApp` resta in modalità ridotta. Con le animazioni continue visibili (linea del caricamento, spinner, clessidra e puntini) **mai** `pumpAndSettle`: si avanza con `pump(durata)`. Vale anche per il conto alla rovescia di `PlayNowButton` con `MotionLevel.full`: il riempimento è continuo finché il conto corre, e `pumpAndSettle` lo farebbe arrivare a zero (e partire l'episodio). Con le animazioni ridotte (il caso di `pumpApp`) tra un secondo e l'altro non si muove nulla.

## 18. Piani e release

Divisione approvata in brainstorming:

- **8a · Fondamenta e controlli:** `PlayerChromeController`; token nel player e `playerPage`; `PlayerIconButton` e comparsa dei controlli; barra a segmenti con anteprima; `PlayerPill` (tasti e avvisi del party unificati, icone degli avvisi). §5, §6, §7, §8, §9, §15.1.
- **8b · Momenti:** `VideoEngine.firstFrame`; caricamento; buffering a 300 ms; errore; schermata di pausa; pannello laterale con dimensione dei sottotitoli. §10, §11, §14.
- **8c · Fine episodio e party:** post-play e scheda senza `Outro`; "Salta intro" e `autoSkips`; badge e attesa del gruppo; spec allineato all'implementazione. §12, §13, §15.2, §15.3. Poi **release 0.4.0**, non obbligatoria.

Ogni piano segue il flusso concordato (worktree, subagent, revisione, prova manuale sul server reale).

## 19. Rischi e punti da verificare

- **`Transform` sul video:** il `Texture` di media_kit scalato e ritagliato (`ClipRRect`) va provato su Windows durante la riproduzione (nessuno sfarfallio, nessun ridimensionamento nativo).
- **Primo fotogramma:** `waitUntilFirstFrameRendered` su Windows si completa al primo `VideoOutput.Resize` valido, una volta per motore; con un video in pausa all'apertura (player del gruppo) il primo fotogramma deve comunque arrivare. Se non arriva entro l'apertura, il caricamento sfuma con `ready` (nessuna attesa infinita).
- **Prestazioni** su un PC modesto: barra e pillola cambiano spesso; misurare con `--profile`.
- **Precedenze sopra il video:** pausa, post-play, attesa del gruppo, pannello ed errore non devono comparire insieme; le regole sono in §11.1, §12.1 e §14 e vanno coperte dai test.

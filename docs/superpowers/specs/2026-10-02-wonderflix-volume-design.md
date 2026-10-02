# WonderFlix — Piano 9: volume ricordato e rotella del mouse

- **Data:** 2026-10-02
- **Stato:** realizzata nel piano 9 (`docs/superpowers/plans/2026-10-02-wonderflix-09-volume.md`), provata dall'utente il 2026-10-02
- **Ambito:** realizzazione delle issue #3 e #4 (enhancement), poi release 0.4.1. Si appoggia allo Spec A (`2026-09-29-wonderflix-client-core-design.md`: player, preferenze) e allo Spec D (`2026-10-01-wonderflix-rinnovo-player-design.md`: pillola dei tasti §9, schermata di pausa §11, pannello "Audio e sottotitoli" §14).

## 1. Obiettivo

- **#3 — "Salvataggio livello volume":** il volume scelto durante la visione si perde. Al riavvio dell'app e a ogni cambio di media (episodio successivo, altro film…) torna al massimo. Deve passare alle visioni successive.
- **#4 — "Modificare il volume con la rotella del mouse":** il volume si cambia solo trascinando la barra o con ↑/↓. La rotella deve cambiarlo sia sul player sia sulla barra del volume.
- **Release 0.4.1**, non obbligatoria.

## 2. Situazione di partenza

- `PlayerViewState.volume` (0–100) parte da `100` in ogni `PlayerController` (`lib/features/player/player_controller.dart`). Ogni media apre un controller nuovo (il provider ha come chiave `PlayerArgs`), quindi il volume riparte da 100: episodio successivo, "Guarda insieme" (il player si riapre) e altri titoli.
- `_start` applica al motore `_view.muted ? 0 : _view.volume` dopo ogni apertura del file.
- `setVolume(v)` porta il valore tra 0 e 100, toglie il muto e lo passa al motore. `changeVolumeBy(d)` (↑/↓, passo `volumeStep = 5`) passa da `setVolume`. `toggleMute()` cambia solo il muto.
- Barra del volume: `Slider` (`Key('volume-slider')`) in `PlayerOverlay`, `onChanged` → `controller.setVolume`.
- ↑/↓/M: `PlayerScreen._run` → comando del controller → `_showVolume()` (pillola "Volume N%" o "Audio disattivato"). Prima del comando `_onKey` chiama `_chrome.keyActivity()`: chiude la schermata di pausa e non mostra i controlli (spec D §9.1).
- Le preferenze del player (`PlayerSettings`, `lib/features/player/player_settings.dart`) stanno in `SharedPreferences`. `PlayerSettingsController.update()` riscrive tutte le chiavi a ogni chiamata.
- In `PlayerScreen` c'è già un `Listener` attorno a tutto il player (tasto "indietro" del mouse, movimenti col tasto premuto). Nessuno gestisce la rotella.
- L'unica lista che scorre nel player è il pannello "Audio e sottotitoli" (`ListView` in `lib/features/player/tracks_panel.dart`).
- Su Windows uno scatto della rotella arriva come `PointerScrollEvent` (circa 60 px: 3 righe × 20 px, vedi `lib/ui/smooth_scroll.dart`). Il touchpad di precisione arriva come `PointerPanZoom…`, non come `PointerScrollEvent`.

## 3. Decisioni

| Tema | Decisione |
|---|---|
| Cosa si ricorda | **Solo il livello** (0–100). Il muto non si salva: ogni player parte senza muto. |
| Livello 0 | Si salva com'è: il player successivo parte a 0, con l'icona dell'altoparlante barrato. |
| Dove si salva | Provider a sé (`player.volume`), **non** in `PlayerSettings`: il volume non è una preferenza della pagina Impostazioni, e `update()` riscriverebbe tutte le chiavi a ogni scatto. Scartato anche il salvataggio alla chiusura del player: con l'episodio successivo il player nuovo parte prima che il vecchio si chiuda. |
| Scrittura su disco | Il valore in memoria cambia subito; su disco si scrive 500 ms dopo l'ultimo cambio (trascinando la barra arrivano decine di cambi al secondo). |
| Passo della rotella | **5 per scatto**, come ↑/↓. Uno scatto per evento, a prescindere dall'ampiezza. |
| Riscontro della rotella | **Come ↑/↓**: pillola "Volume N%", schermata di pausa chiusa, controlli che non compaiono. |
| Dove funziona la rotella | **In tutto il player tranne il pannello "Audio e sottotitoli"**: film, controlli (barra del volume e barra di avanzamento comprese), post-play, schermata di pausa, caricamento, errore. Sul pannello la rotella scorre la lista e non tocca mai il volume, anche a lista ferma in cima o in fondo. |
| Release | 0.4.1 non obbligatoria (nessun marcatore `min-version`). |

## 4. Volume ricordato (#3)

### 4.1 `PlayerVolumeController` (`lib/features/player/player_volume.dart`)

`Notifier<double>` con il volume salvato (0–100), provider `playerVolumeProvider` (non `autoDispose`).

- `build()`: legge `player.volume` da `sharedPreferencesProvider`.
  - chiave assente o `NaN` → `100`;
  - fuori dall'intervallo → portato tra 0 e 100.
- `set(double volume)`:
  - `NaN` → ignorato;
  - porta il valore tra 0 e 100;
  - se è uguale allo stato non fa nulla;
  - altrimenti aggiorna subito lo stato e (ri)avvia un `Timer` di `PlayerVolumeController.saveDelay` (500 ms). Allo scadere scrive su disco l'ultimo valore.
- `Future<void> flush()`: ferma il timer e scrive subito il valore in sospeso, se c'è. La chiamano il timer, la dismissione del provider (`ref.onDispose`) e la chiusura della finestra dal player (§4.2): il provider dell'app non viene mai dismesso, perché la finestra si distrugge e il processo finisce.
- Nessuna stringa e nessuna voce nelle Impostazioni.

### 4.2 `PlayerController`

- `build()` legge `ref.read(playerVolumeProvider)` e parte con `_view` già a quel volume, senza muto. `_start` lo applica al motore come oggi (`_view.muted ? 0 : _view.volume`).
- `setVolume(v)` aggiorna anche il valore salvato (`playerVolumeProvider.notifier.set(value)`). Barra, ↑/↓ e rotella passano tutte da qui.
- `toggleMute()` non tocca il valore salvato.
- Il volume riferito a Jellyfin (`VolumeLevel`) resta quello di `_view`.
- `PlayerScreen._onWindowClose` aspetta anche `playerVolumeProvider.notifier.flush()`, insieme alla chiusura del player e all'uscita dal gruppo, prima di distruggere la finestra: un cambio di volume fatto da meno di 500 ms non va perso.

Effetti:

- episodio successivo, "Guarda insieme" (player riaperto) e qualsiasi altro titolo partono dall'ultimo volume scelto. Durante il passaggio il player nuovo legge il valore in memoria, già aggiornato;
- al riavvio dell'app si parte dall'ultimo volume scritto su disco;
- nel watch party il volume resta locale, come oggi.

## 5. Rotella del mouse (#4)

### 5.1 `PlayerScreen`

Il `Listener` che avvolge il player riceve anche `onPointerSignal`:

- solo `PointerScrollEvent` con `scrollDelta.dy != 0`. Lo scorrimento orizzontale (`dy == 0`) e il touchpad di precisione (`PointerPanZoom…`) non fanno nulla;
- l'azione si registra con `GestureBinding.instance.pointerSignalResolver.register`: vince chi registra per primo, cioè il widget più interno. Così una lista sotto il puntatore si prende la rotella prima del volume;
- l'azione fa quello che fa un tasto: `_chrome.keyActivity()`, poi `_run(PlayerCommand.volumeUp)` se `dy < 0` (rotella in su) o `_run(PlayerCommand.volumeDown)` se `dy > 0`. Quindi ±5, pillola "Volume N%", schermata di pausa chiusa e controlli che non compaiono. Se i controlli sono già visibili restano e la barra del volume si sposta con il valore.

Funziona ovunque nel player, anche sopra la barra del volume, e in ogni stato (caricamento, errore, post-play), come ↑/↓.

### 5.2 Pannello "Audio e sottotitoli"

Il pannello è avvolto da un `Listener` il cui `onPointerSignal` registra un'azione vuota per ogni `PointerScrollEvent`:

- se la lista può scorrere, il suo `Scrollable` registra per primo e scorre;
- se non può (in cima, in fondo, lista corta), vince l'azione vuota del pannello: il volume non cambia.

Il `Listener` sta sopra tutto il pannello (intestazione e bordo compresi), non solo sopra la lista.

## 6. Test

### 6.1 Automatici

- `PlayerVolumeController`:
  - chiave assente → 100; valore salvato → quel valore; 150 → 100; −5 → 0; `NaN` → 100;
  - `set` aggiorna subito lo stato; su disco non c'è nulla prima di 500 ms, dopo c'è l'ultimo valore. Più `set` ravvicinati danno una sola scrittura, con l'ultimo valore;
  - `set` dello stesso valore o di `NaN` non scrive; `set` fuori intervallo è portato tra 0 e 100;
  - `flush` scrive subito il valore in sospeso e ferma il timer; senza nulla in sospeso non scrive;
  - dismissione con una scrittura in sospeso → valore scritto subito.
- `PlayerController`:
  - parte dal volume salvato (primo valore passato al motore) e senza muto;
  - `setVolume` e `changeVolumeBy` aggiornano il valore salvato; `toggleMute` no.
- `PlayerScreen`:
  - ↓ ↓ poi M, poi episodio successivo (N): il nuovo player parte da 90, senza muto;
  - chiusura della finestra: la finestra si distrugge solo dopo la scrittura del volume;
  - rotella in su sul film → volume +5 e pillola "Volume N%"; in giù → −5;
  - rotella sopra la barra del volume → stesso effetto;
  - a controlli nascosti la rotella non li mostra; con la schermata di pausa aperta la chiude;
  - scorrimento orizzontale → nulla;
  - pannello aperto, rotella sopra il pannello → volume invariato (anche a lista ferma);
  - durante il caricamento la rotella cambia il volume e mostra la pillola.
- `TracksPanel`: la rotella non esce mai dal pannello (lista corta; lista lunga ferma in cima con la rotella in su); una lista lunga scorre.
- I test esistenti (tasti, pillola, pannello, player) restano verdi. Dove serve, i test usano un volume salvato finto (`FakePlayerVolume`, come `FakePlayerSettings`).

### 6.2 Manuali (utente, server vero)

- Volume abbassato → episodio successivo (pulsante, post-play, conto alla rovescia): stesso volume.
- Volume abbassato → chiudere il player → aprire un altro film: stesso volume.
- Volume abbassato → chiudere l'app → riaprirla e avviare un titolo: stesso volume. Anche chiudendo l'app con la X subito dopo il cambio, dal player.
- Muto → episodio successivo: audio di nuovo attivo al volume di prima.
- Rotella sul film (controlli nascosti e visibili), sulla barra del volume, sulla barra di avanzamento, nel post-play, sulla schermata di pausa, durante il caricamento: pillola e volume corretti.
- Rotella sul pannello "Audio e sottotitoli": la lista scorre, il volume no.
- Rotella "veloce", a scorrimento libero o ad alta risoluzione, e touchpad senza driver di precisione (se disponibili): il volume non salta in modo strano. Su questi dispositivi uno scatto fisico può arrivare come più eventi, e quindi più passi da 5.
- Rotella sopra la barra del volume senza muovere il mouse, in riproduzione: i controlli spariscono dopo 3 s come con ↑/↓. Da valutare se va bene così.
- Watch party: "Guarda insieme" dal player non riporta il volume a 100.

## 7. Release 0.4.1

- Procedura di `docs/RELEASING.md`: versione 0.4.1 in `pubspec.yaml`, commit `chore: release 0.4.1`, tag `v0.4.1`, workflow, note in italiano scritte nella bozza della release. Non obbligatoria: nessun marcatore `min-version`.
- Dopo la pubblicazione (fatta dall'utente), chiusura delle issue #3 e #4 con un commento che rimanda alla 0.4.1, solo con l'ok dell'utente.

## 8. Fuori ambito

- Ricordare il muto.
- Volume nella pagina Impostazioni.
- Volume con il touchpad di precisione (gesti a due dita).
- Rotella per saltare avanti e indietro.

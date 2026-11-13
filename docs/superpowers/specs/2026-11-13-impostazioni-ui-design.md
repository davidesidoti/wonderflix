# Impostazioni: nuova UI (PC, web, TV)

Bozze: `2026-11-13-impostazioni-bozze/impostazioni.html` (approvate dall'utente il
2026-11-13, PC/web e TV). Solo app, nessuna modifica al plugin.

## Problemi di oggi

- Una colonna di 640 px su finestre larghe: 60% vuoto, pagina lunga ~5
  schermate, nessun modo di saltare a una sezione.
- Controlli disomogenei: menu a tendina Material con la riga sotto,
  interruttori lontani dall'etichetta, nessun filo tra le righe.
- 20 interruttori delle notifiche senza un comando per gruppo.
- "Lingua" e "Lingue di riproduzione" quasi omonime; la dimensione dei
  sottotitoli sta in "Player", la loro lingua altrove.
- Dove si salva un'impostazione è detto con frasi diverse o non è detto.
- "Esci" ha lo stesso peso di "Cambia immagine", accanto a "Cambia profilo".
- TV: spiegazioni a 12,5 px, menu a tendina e bottoni segmentati scomodi col
  telecomando, "Decodifica hardware" mostrata ma ignorata (Media3 decodifica
  sempre in hardware), aggiornamento in fondo sotto la versione.

## PC e web

### Sezioni (decisione 1)

Ordine e id (`/settings?section=<id>` vale per tutte; `home` resta
`homeSettingsSection`):

| id | Titolo | Contenuto | Dove si salva |
|---|---|---|---|
| `account` | Account | tessera, "Mostra agli amici cosa guardo", contatti per il recupero, Esci | Il tuo account |
| `notifications` | Notifiche | push del dispositivo (web), gruppi | Il tuo account |
| `home` | Home | righe della Home, ripristino | Il tuo account |
| `playback` | Riproduzione | qualità, prossimo episodio, salta intro, decodifica hardware (non web) | Questo PC |
| `subtitles` | Audio e sottotitoli | lingua audio, lingua sottotitoli, quando mostrarli, dimensione + anteprima | Il tuo account, in tutti i client Jellyfin |
| `app` | App | lingua dell'app, animazioni | Questo PC |
| `discord` | Discord | come oggi (solo Windows) | Questo PC |
| `support` | Supporto | come oggi | — |

Le condizioni di oggi restano (Notifiche solo con `push`, Discord non nel
browser, ecc.). "Dimensione" nella sezione `subtitles` ha l'aiuto "Solo su
questo PC" (è nelle preferenze locali del profilo, non sul server).

Spariscono le frasi sostituite dal "dove si salva": `settingsLanguagesHint`,
`homeRowsAllPcs`. Resta "Le modifiche valgono dal prossimo video." come nota
sotto l'elenco di Riproduzione.

### Navigazione (decisione 2)

- Largo (`!compact`): colonna a sinistra larga 208 px come `AdminRail`
  (sfondo `surface`, filo a destra), titolo "Impostazioni" in Bebas, una
  voce per sezione visibile (icona Lucide + nome), separatori tra i gruppi
  account (account/notifiche/home), riproduzione (playback/subtitles), resto.
  In fondo "WonderFlix X.Y.Z". Un clic scorre alla sezione
  (`Scrollable.ensureVisible`, durata `WfMotion`); la voce accesa è l'ultima
  sezione il cui titolo è salito sopra un terzo dell'altezza visibile (scroll
  spy), l'ultima sezione quando si è in fondo.
- Stretto: fila di etichette orizzontale fissa sopra la pagina che scorre,
  stessa logica di scorrimento e di voce accesa; la voce accesa resta in
  vista nella fila. La versione resta in fondo alla pagina.
- Il titolo grande "IMPOSTAZIONI" in cima al contenuto sparisce nel largo
  (sta nella colonna), resta nello stretto.
- La pagina resta un `SingleChildScrollView` (le sezioni non devono
  smontarsi, vedi commento attuale).

### Righe (decisione 3)

- Titolo di sezione: Bebas 24, a destra il "dove si salva" (icona piccola +
  testo muted 12): `monitor` per "Questo PC", `cloud` per "Il tuo account".
- Ogni gruppo di controlli sta in un `AdminList` (riuso dal kit Cabina).
- Riga: etichetta (e aiuto muted 12 sotto) a sinistra, controllo a destra,
  padding 14×11. Riga con interruttore: tutta la riga attiva l'interruttore.
  Riga con controllo largo (bottoni segmentati) nello stretto: il controllo
  va sotto l'etichetta.
- Menu a tendina: senza riga sotto, riquadro con bordo `border`, raggio 6,
  sfondo `surface`, come i bottoni secondari. Le chiavi dei widget di oggi
  restano (i test le usano).
- Larghezza massima del contenuto 640 px, allineato a sinistra; la sezione
  `subtitles` nel largo mette l'anteprima a destra dell'elenco (larga 300) se
  c'è spazio, sotto altrimenti.

### Notifiche (decisione 4)

- Un gruppo è una riga di intestazione (sfondo `surface`, freccia, nome,
  "8 di 10 attive", interruttore) e, aperto, le sue righe rientrate.
- L'interruttore del gruppo è acceso se tutti i tipi lo sono. Toccato: se
  sono tutti accesi li spegne tutti, altrimenti accende quelli spenti. Una
  `setEnabled` per ogni tipo da cambiare (in parallelo, nessuna modifica al
  plugin); se una fallisce, il solito avviso, una volta sola.
- Un gruppo con un solo tipo ("Richieste da approvare") è una riga normale
  con il nome del gruppo come etichetta, senza freccia.
- All'apertura: nel largo "Per te" aperto, gli altri chiusi; nello stretto
  tutti chiusi. Lo stato aperto/chiuso vive solo nella pagina.

### Anteprima dei sottotitoli (decisione 5)

`SubtitlePreview(scale)`: riquadro 16:9 con uno sfondo dipinto (sfumature
calde, nessuna immagine), la frase `settingsSubtitlePreviewSample` in bianco
semibold con contorno nero, grande come nel player: `55 * altezza / 720 *
scale` (la `sub-font-size` predefinita di mpv a 720 righe). Si aggiorna
mentre si cambia la dimensione. Usata su PC/web e sulla TV.

### Discord (decisione 6)

"Mostra il titolo" e "Mostra la locandina" rientrate di 20 px sotto la
prima voce (dipendono da lei, come oggi restano disattivate).

### Account (decisione 7)

- Tessera: a sinistra un tagliando di 120 px (sfondo `surfaceHigh`, filo
  tratteggiato a destra) con l'avatar da 76 cerchiato d'oro e un "+" in
  basso a destra: toccarlo apre il dialogo dell'immagine (tooltip "Cambia
  immagine"; il bottone "Cambia immagine" sparisce). A destra il nome in
  Bebas 30, il tag "Admin" se serve, e i bottoni Cambia password,
  Autorizza un dispositivo, Cambia profilo. Nello stretto il tagliando va
  sopra.
- "Quick Connect" diventa "Autorizza un dispositivo" (stessa chiave
  `settings-quick-connect`).
- Sotto: la riga "Mostra agli amici cosa guardo", poi i contatti per il
  recupero come oggi, poi "Esci" da solo, bottone secondario con testo e
  bordo `error`.

## TV (decisione 8)

Sulla TV `SettingsScreen` mostra un altro corpo, `TvSettingsBody`. Fuori
dalla TV niente cambia per questa parte.

- Sinistra: titolo in Bebas 34 e un elenco largo 440 di righe alte 46
  (`TvFocusable`), con etichette di gruppo muted 14: Aggiornamento (solo se
  c'è), App (Lingua dell'app), Riproduzione (Qualità dello streaming, Avvia
  il prossimo episodio, Salta intro e riassunti), Audio e sottotitoli
  (Lingua dell'audio, Lingua dei sottotitoli, Quando mostrarli, Dimensione
  dei sottotitoli), Info (Versione). Su e Giù si muovono solo nell'elenco.
- Riga: nome a sinistra, valore attuale a destra (oro col focus), "›" se
  apre delle scelte. Gli interruttori cambiano con OK.
- Destra: per la riga col focus, il nome in Bebas 26, la spiegazione a 18 px
  e il "dove si salva" ("Vale solo su questa TV" o "Salvate sul tuo account:
  valgono in tutti i client Jellyfin"). Per le righe dei sottotitoli c'è
  anche l'anteprima piccola.
- Scelte: una rotta a tutto schermo con il pannello da destra largo 300
  (opzioni alte 44, pallino oro sulla scelta attuale, focus iniziale lì).
  Su e Giù scelgono, OK conferma e chiude, Indietro chiude senza cambiare;
  il focus torna sulla riga. Per la dimensione dei sottotitoli il resto
  dello schermo è l'anteprima, che segue l'opzione col focus.
- Aggiornamento: prima riga, bordo e testo oro. Pronto: OK installa. In
  download: la percentuale come valore. Il permesso mancante va nella
  spiegazione a destra.
- Niente "Decodifica hardware" sulla TV.
- Lingue di riproduzione non caricate: le tre righe mostrano "…"; errore:
  una riga "Non caricate, riprova" che con OK rilegge.
- Indietro (`goBack`) non si gestisce nei tasti: lo fa il `PopScope` della
  rotta (gotcha Fire TV).

## Testi nuovi (it / en)

`settingsSectionPlayback` Riproduzione / Playback · `settingsSectionSubtitles`
Audio e sottotitoli / Audio and subtitles · `settingsSectionApp` App / App ·
`settingsScopeDevice` Questo PC / This PC (web: Questo dispositivo / This
device; TV: Questa TV / This TV) · `settingsScopeAccount` Il tuo account /
Your account · `settingsScopeJellyfin` Il tuo account, in tutti i client
Jellyfin / Your account, in every Jellyfin client · `settingsSubtitleSizeHint`
Solo su questo PC / Only on this PC · `settingsLanguageApp` Lingua dell'app /
App language · `settingsQualityHint` Più bassa se la connessione scatta /
Lower it if playback stutters · `settingsHardwareDecodingHint` Spegnila se il
video si vede a scatti o con colori sbagliati / Turn it off if video stutters
or shows wrong colours · `notifPrefsGroupCount` {on} di {total} attive / {on}
of {total} on · `settingsSubtitlePreview` Anteprima dei sottotitoli /
Subtitle preview · `settingsSubtitlePreviewSample` Ci vediamo dopo il secondo
tempo. / See you after the second half. · `settingsQuickConnect` diventa
Autorizza un dispositivo / Authorize a device · testi TV: spiegazioni per
ogni riga, "Indietro per chiudere", "Non caricate, riprova".

## Test

Ogni decisione ha i suoi test widget; i test di oggi si aggiornano dove
cambiano testi o struttura, le chiavi esistenti restano. TV: focus Su/Giù
nell'elenco, OK su un interruttore, pannello delle scelte (OK cambia, Indietro
no, il focus torna alla riga), niente decodifica hardware.

## Fuori

Ricerca nelle impostazioni, conferma su Esci, stile dei sottotitoli (colore,
contorno), impostazioni nuove.

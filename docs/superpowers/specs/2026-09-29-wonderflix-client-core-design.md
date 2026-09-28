# WonderFlix — Spec A: client core per Windows

- **Data:** 2026-09-29
- **Stato:** approvato in brainstorming, in attesa di revisione finale
- **Ambito:** Spec A di 2. Lo Spec B (watch party / visione sincronizzata) è separato e viene dopo.

## 1. Obiettivo

Client desktop Windows per il server Jellyfin "WonderFlix", che sostituisce Jellyfin Desktop per gli utenti del server:

- riproduzione affidabile (niente schermo nero, sottotitoli in sync);
- accesso con solo login (l'indirizzo del server è incorporato);
- interfaccia nuova con identità WonderFlix (Noir & Oro);
- stesso comportamento del client ufficiale per minutaggi, stato "visto" e preferiti (tutto salvato sul server);
- aggiornamenti automatici da GitHub Releases, con release obbligatorie.

### Problemi del client attuale da risolvere

| Problema segnalato | Causa probabile | Risposta nel design |
|---|---|---|
| Video che ogni tanto non parte | Negoziazione PlaybackInfo/profilo, errori non gestiti | Profilo dispositivo ampio (mpv), ripiego automatico in transcodifica, errori chiari |
| Sottotitoli fuori sync | Sottotitoli bruciati durante il transcode, sottotitoli esterni su HLS | Direct play di default, sottotitoli disegnati localmente da libass, tracce esterne caricate a parte, ritardo ±0,1 s |

### Server di riferimento

Jellyfin **10.11.9**, un solo indirizzo pubblico HTTPS.

## 2. Perimetro

### Incluso (v1)

- Tipi di contenuto: **Film** e **Serie TV**.
- Login con password (sessione sempre ricordata) e **Quick Connect**.
- Home, catalogo Film/Serie, dettaglio film/serie, pagina attore, ricerca, **La mia lista** (preferiti).
- Player completo (sezione 7), con salta intro/crediti, trickplay, capitoli e prossimo episodio.
- **Trailer**: locali nel player, remoti (YouTube) nel browser.
- **Discord Rich Presence**.
- Interfaccia in **italiano e inglese** (lingua di Windows, modificabile nelle impostazioni).
- Aggiornamenti automatici da GitHub con release obbligatorie.
- Installer Inno Setup, senza firma del codice.

### Escluso da v1 (idee future)

- Profili "Chi guarda?" (più utenti sullo stesso PC).
- Collezioni / saghe.
- Download per la visione offline.
- Output HDR vero (in v1 media_kit converte l'HDR in SDR).
- Firma del codice (pipeline già predisposta).
- Musica, TV in diretta, libri, foto.
- Plugin che estendono l'interfaccia di jellyfin-web: non supportati per scelta. Le loro funzioni chiave (salta intro, trickplay) sono rifatte in modo nativo con le API. I plugin solo lato server funzionano normalmente.
- Pannello di amministrazione: resta su jellyfin-web dal browser.

## 3. Stack tecnologico

| Ambito | Scelta |
|---|---|
| UI | Flutter (desktop Windows), Dart |
| Video | `media_kit` (libmpv): decodifica, libass, hwdec `auto-safe` (d3d11va) |
| Stato | Riverpod |
| Routing | go_router |
| HTTP / API | client Dart-dio generato dallo spec OpenAPI di Jellyfin 10.11 (spec salvato nel repo) |
| Storage segreto | `flutter_secure_storage` (Gestore credenziali di Windows) |
| Preferenze locali | `shared_preferences` |
| Localizzazione | `flutter gen-l10n`, file ARB `it` / `en` |
| Icone | set vettoriale unico (Lucide o Material Symbols Rounded). **Nessuna emoji nell'interfaccia.** |
| Font | Bebas Neue (titoli), Inter (testo), inclusi negli asset |
| Installer | Inno Setup, installazione per utente senza UAC |
| CI/CD | GitHub Actions |

Scartati: Electron/Tauri (player HTML5 = stessi limiti di jellyfin-web; mpv dietro la webview fragile su Windows) e Qt/QML (sviluppo UI più lento). Fork di Fladder scartato: si usa solo come riferimento.

## 4. Architettura

Quattro strati. Ogni strato usa solo quello sotto.

1. **Schermate (UI):** Login, Home, Catalogo, Dettaglio, Attore, Ricerca, La mia lista, Player, Impostazioni, Aggiornamento. Contengono solo presentazione e leggono lo stato tramite provider Riverpod.
2. **Servizi (nessuna UI, testabili da soli):**
   - `AuthService`: login con password o Quick Connect, ripristino del token, logout, gestione del 401.
   - `LibraryRepository`: home, catalogo, dettagli, ricerca, persone, preferiti, visto/non visto.
   - `PlaybackService`: PlaybackInfo, scelta tra direct play e transcodifica, mappatura delle tracce, report dell'avanzamento, ripiego.
   - `SegmentsService`: MediaSegments (intro, riassunto, crediti, anteprima).
   - `ServerEvents`: WebSocket di sessione (`UserDataChanged`, `LibraryChanged`, keep-alive). È la base anche per lo Spec B.
   - `DiscordPresence`
   - `UpdateService`
   - `SettingsStore`
3. **Infrastruttura:** `JellyfinClient` (generato), `VideoEngine` (interfaccia sopra media_kit), `SecureStorage`, IPC Discord (named pipe `\\.\pipe\discord-ipc-N`), logger.
4. **AppConfig (build-time):** valori iniettati con `--dart-define-from-file=config/wonderflix.json`.

```json
{
  "serverUrl": "https://…",
  "githubRepo": "owner/repo",
  "discordAppId": "…",
  "supportUrl": "https://discord.gg/…"
}
```

`config/wonderflix.json` è in `.gitignore`. Nel repo c'è solo `config/wonderflix.example.json`. In CI il file viene generato dai Secrets.

### Identità verso il server

Ogni richiesta invia `Authorization: MediaBrowser Client="WonderFlix", Device="<nome PC>", DeviceId="<uuid stabile per installazione>", Version="<versione app>", Token="<token>"`. Nella dashboard di Jellyfin le sessioni risultano come "WonderFlix – <nome PC>".

### `VideoEngine`

Interfaccia nostra sopra media_kit. Espone apri (URL, header, posizione iniziale), play/pausa, salto, velocità, volume, tracce (con `ff-index`), aggiunta di sottotitoli esterni, ritardo dei sottotitoli, e gli stream di posizione, buffering, fine ed errore. Serve a:

- testare player e servizi senza libmpv (implementazione finta);
- dare allo Spec B un controllo preciso del player (posizione, velocità) senza dipendere da media_kit.

## 5. Avvio e login

### Sequenza di avvio

1. Viene avviato in parallelo `UpdateService.check()`. Se c'è un aggiornamento **obbligatorio**, si mostra la schermata di aggiornamento bloccante (sezione 9).
2. Se c'è un token salvato, lo si verifica con `GET /Users/Me`:
   - 200: si va alla Home;
   - 401: il token viene cancellato e si torna al Login con il messaggio "Sessione scaduta, accedi di nuovo".
3. Se il server non è raggiungibile: schermata "WonderFlix non è raggiungibile" con pulsante *Riprova* e nuovo tentativo automatico ogni 15 s. Il token **non** viene cancellato.

### Login con password

- Chiamata: `POST /Users/AuthenticateByName`.
- La sessione è sempre ricordata: il token viene salvato nel Gestore credenziali.
- Gli errori vengono mostrati come messaggi chiari: credenziali errate, utente disabilitato, server irraggiungibile.

### Quick Connect

1. `GET /QuickConnect/Enabled`: se la funzione è disattivata, la scheda non viene mostrata.
2. `POST /QuickConnect/Initiate` restituisce il codice e il segreto. Il codice viene mostrato in grande (Bebas, oro).
3. Ogni 3 s: `GET /QuickConnect/Connect?secret=…`.
4. Quando lo stato è `Authenticated`: `POST /Users/AuthenticateWithQuickConnect`.
5. Se il codice scade o il segreto non è più valido, se ne genera uno nuovo in automatico.

**Prerequisito sul server:** Quick Connect deve essere attivo (Dashboard → Generale).

### Altro

- **"Password dimenticata?"** apre `supportUrl`. Jellyfin non ha il recupero password via email.
- **Logout** (dalle Impostazioni): `POST /Sessions/Logout`, poi il token viene cancellato e si torna al Login.

## 6. Navigazione e schermate

- **Barra superiore (ovunque):** logo · Home · Film · Serie · La mia lista · Cerca · avatar (menu con Impostazioni ed Esci).
- **Indietro:** Esc, Alt+←, tasto "indietro" del mouse.

### Home

- **In evidenza:** contenuti aggiunti di recente, sfondo a tutta larghezza che ruota ogni 8 s.
- **Continua a guardare:** `/UserItems/Resume`, film ed episodi.
- **Prossimi episodi:** `/Shows/NextUp`.
- **Film aggiunti di recente** e **Serie aggiunte di recente:** `/Items/Latest`.
- **La mia lista.**

### Catalogo Film / Serie

- Griglia di poster caricata a pagine da 100 durante lo scorrimento.
- Ordinamento: titolo, data di aggiunta, anno, voto.
- Filtri: genere, anno, visto/non visto.
- Tutte le librerie dello stesso tipo (`movies` / `tvshows`) vengono unite in un'unica vista.

### Dettaglio film

- Sfondo e logo del titolo (se manca, il titolo in Bebas Neue).
- Metadati: anno, durata, classificazione, voto, generi.
- Azioni: **Riproduci / Riprendi da mm:ss / Ricomincia**, Trailer, La mia lista, Visto/Non visto.
- Righe: cast (con link alla pagina attore) e "Simili" (`/Items/{id}/Similar`).

### Dettaglio serie

Come il dettaglio film, con in più:

- schede per le stagioni;
- elenco episodi con miniatura, avanzamento e segno di visto;
- il pulsante principale propone l'episodio corretto ("Riprendi S1:E4" o "Riproduci S1:E5").

### Pagina attore

Foto, biografia e filmografia limitata ai contenuti presenti sul server.

### Ricerca

Parte da sola dopo 300 ms senza digitazione. Risultati raggruppati in Film, Serie e Persone.

### Trailer

- Se ci sono trailer locali (`/Items/{id}/LocalTrailers`), si riproducono nel player.
- Altrimenti, il primo `RemoteTrailers` si apre nel browser predefinito.

### Qualità trasversali

- **Immagini:** segnaposto blurhash (forniti da Jellyfin) e cache su disco.
- **Stati di schermata:** scheletro durante il caricamento, errore con *Riprova*.
- **Aggiornamento dei dati:** gli eventi WebSocket aggiornano visto/preferiti modificati da altri dispositivi.
- **Finestra:** dimensione e posizione ricordate; una sola istanza dell'app.

### Tema Noir & Oro

| Token | Valore | Uso |
|---|---|---|
| `bg` | `#0A0A0A` | sfondo |
| `surface` | `#121212` | pannelli, menu |
| `surfaceHigh` | `#1B1B1B` | input, card |
| `border` | `#262626` | bordi |
| `gold` | `#D4A64A` | accenti: pulsante primario, voce di menu attiva, avanzamento, focus |
| `cream` | `#F2EAD3` | testo principale |
| `creamMuted` | `#F2EAD3` al 60% | testo secondario |
| `error` | `#C8463C` | errori |

- Titoli in Bebas Neue, testo in Inter.
- L'oro è usato solo come accento, mai come sfondo di grandi superfici.

## 7. Player

### Avvio della riproduzione

1. `POST /Items/{id}/PlaybackInfo` con:
   - un `DeviceProfile` che accetta in direct play tutti i container e i codec;
   - `MaxStreamingBitrate` impostato dalla qualità scelta;
   - `SubtitleProfiles`: `External` per i formati testuali (srt, ass, ssa, vtt, sub), `Embed` per tutto il resto;
   - indici di audio e sottotitoli scelti secondo le preferenze dell'utente salvate **sul server** (`AudioLanguagePreference`, `SubtitleLanguagePreference`, `SubtitleMode`).
2. **Direct play:** `/Videos/{id}/stream?static=true&mediaSourceId=…`.
   - Il token viaggia nell'header `http-header-fields` di mpv, non nell'URL.
   - La posizione di ripresa viene passata come `start` all'apertura, non come salto successivo.
3. **Sottotitoli:**
   - Tracce interne al file: si selezionano in mpv facendo corrispondere lo `Index` dello stream Jellyfin con la proprietà `ff-index` della traccia mpv.
   - Tracce esterne (`IsExternal`): si caricano con `sub-add` dal `DeliveryUrl`.
   - Il rendering è sempre fatto da libass.
4. **Transcodifica** (solo come ripiego o se l'utente sceglie una qualità ridotta):
   - si usa il `TranscodingUrl` HLS;
   - i sottotitoli testuali restano esterni;
   - solo i sottotitoli grafici (PGS/VobSub) vengono bruciati nel video.

### Report dell'avanzamento (minutaggi e stato "visto")

- `POST /Sessions/Playing` all'avvio, con `PlaySessionId`, `MediaSourceId`, indici delle tracce e `PlayMethod`.
- `POST /Sessions/Playing/Progress` ogni 10 s e subito a ogni pausa, ripresa, salto o cambio traccia.
- `POST /Sessions/Playing/Stopped` con `PositionTicks` alla fine del video, all'uscita dal player e alla chiusura della finestra (attesa massima 2 s).
- Lo stato "visto" lo decide il server, secondo la sua configurazione (di default oltre il 90%).
- In caso di crash si perdono al massimo 10 s di avanzamento.

### Gestione degli errori

- **Errore in direct play:** un solo nuovo tentativo automatico in transcodifica (`EnableDirectPlay=false`, `EnableDirectStream=false`), con l'avviso "Il server sta convertendo questo video".
- **Buffering:** indicatore di caricamento.
- **401:** si torna al Login.
- **Altri errori:** messaggio chiaro con *Riprova* e *Torna indietro*. L'errore viene scritto nel log.

### Controlli

- L'overlay si nasconde dopo 3 s di inattività del mouse.
- In alto: indietro, titolo, episodio.
- Barra di avanzamento:
  - parte già scaricata;
  - tacche dei capitoli;
  - anteprime **trickplay** al passaggio del mouse (`/Videos/{id}/Trickplay/{width}/{index}.jpg`, tile).
- In basso: indietro/avanti di 10 s, play/pausa, volume, tempo trascorso/totale, menu **Audio e sottotitoli** (con **ritardo sottotitoli ±0,1 s**), episodio successivo, schermo intero.
- Tutte le icone sono vettoriali: nessuna emoji.

### Tastiera

| Tasto | Azione |
|---|---|
| Spazio | play/pausa |
| ← / → | −10 s / +10 s |
| ↑ / ↓ | volume |
| F | schermo intero |
| M | muto |
| G / H | ritardo sottotitoli −0,1 s / +0,1 s |
| N | episodio successivo |
| Esc | esce dallo schermo intero; se già in finestra, esce dal player |

### Intro, crediti e prossimo episodio

- `GET /MediaSegments/{itemId}` restituisce i segmenti `Intro`, `Recap`, `Outro` e `Preview`.
- Durante un segmento Intro o Recap compare il pulsante **"Salta intro"** (o "Salta riassunto").
- Impostazione "salta automaticamente": spenta di default.
- La scheda **"Prossimo episodio"** compare all'inizio del segmento Outro oppure, se il segmento manca, negli ultimi 30 s.
  - Ha un conto alla rovescia di 10 s e si può annullare.
  - La riproduzione automatica si può disattivare.

### Integrazione con Windows

- Tasti multimediali e pannello media di Windows (SMTC).
- Salvaschermo e sospensione bloccati durante la riproduzione.
- Decodifica hardware `auto-safe`, disattivabile.

### Impostazioni del player

- Qualità: *Originale* (predefinita), 20, 8 o 4 Mbps.
- Salto automatico dell'intro.
- Riproduzione automatica del prossimo episodio.
- Dimensione dei sottotitoli.
- Decodifica hardware.
- Lingue di audio e sottotitoli (scritte nella configurazione utente sul server).

## 8. Discord Rich Presence

- **Prerequisito:** un'app "WonderFlix" creata sul Discord Developer Portal, con l'asset `logo`. Il suo ID va in `discordAppId`.
- **Durante la riproduzione:** attività di tipo *Watching*.
  - `details`: il titolo;
  - `state`: "S1:E4 · titolo dell'episodio" per le serie, l'anno per i film;
  - timestamp di inizio e fine, per la barra di avanzamento di Discord;
  - immagine grande: il poster (URL dell'immagine sul server) oppure il logo;
  - pulsante "Entra in WonderFlix" che apre `supportUrl`.
- **In pausa:** stato "In pausa", senza timestamp.
- **Fuori dal player:** l'attività viene cancellata.
- **Discord non avviato:** nuovo tentativo silenzioso ogni 30 s.
- **Impostazioni:** *mostra attività*, *mostra titolo*, *mostra poster* (tutte attive di default).
  - Il poster rende visibile l'indirizzo del server agli amici su Discord. Se *mostra poster* è spento, si usa il logo.

## 9. Aggiornamenti e distribuzione

### Installer

- Inno Setup, installazione in `%LocalAppData%\Programs\WonderFlix` senza UAC.
- Collegamenti su Start e Desktop, programma di disinstallazione.
- Supporta l'installazione silenziosa (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`) e riapre l'app al termine.

### Pipeline di release (GitHub Actions, `release.yml`)

1. Si attiva con un tag `vX.Y.Z`.
2. Genera `config/wonderflix.json` dai Secrets.
3. Esegue `flutter build windows --release --dart-define-from-file=…`.
4. Esegue Inno Setup, che produce `WonderFlix-Setup-X.Y.Z.exe` e `WonderFlix-Setup-X.Y.Z.exe.sha256`.
5. Passaggio di firma presente ma disattivato.
6. Crea la GitHub Release come **bozza** e ci carica i file. La pubblicazione è manuale (sezione 10).

**Vincolo:** le release devono stare su un **repository pubblico**, perché l'app le legge senza token.

### Controllo degli aggiornamenti (`UpdateService`)

1. All'avvio e poi ogni 6 h: `GET https://api.github.com/repos/{githubRepo}/releases/latest`. Questa chiamata esclude già bozze e pre-release.
2. Confronta la versione trovata con quella installata (semver).
3. Se la versione è più nuova:
   - scarica l'installer in `%TEMP%` in background;
   - verifica lo SHA-256;
   - mostra la barra "Aggiornamento pronto: *Riavvia ora*" con le note di rilascio (markdown).
4. Al clic su *Riavvia ora*: avvia l'installer in modalità silenziosa e chiude l'app. L'installer la riapre al termine.
5. **Mai durante la riproduzione:** se l'aggiornamento è pronto mentre si guarda un video, la barra compare alla fine.
6. **Errori** (rete, hash non valido): nuovo tentativo al controllo successivo, registrato nel log, senza disturbare l'utente.

### Aggiornamenti obbligatori

- Le note della release più recente possono contenere il marcatore `<!-- wonderflix:min-version=X.Y.Z -->`.
- Se la versione installata è **minore** di `min-version`, l'app mostra una schermata bloccante: note di rilascio, avanzamento del download, pulsante *Aggiorna ora*.
- Se il blocco scatta durante la riproduzione, la schermata compare alla fine del video.
- Si usa una versione minima, e non un flag "obbligatoria" sulla singola release, perché così anche chi ha saltato una release obbligatoria resta bloccato dalle release successive.

## 10. Procedura di release

Da riportare anche in `docs/RELEASING.md`.

1. Aggiorna la versione in `pubspec.yaml`.
2. Esegui la checklist dei test manuali (sezione 12) su una build locale.
3. Crea il tag e fai push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Attendi la fine di `release.yml`. La release viene creata come **bozza**.
5. Scrivi le note di rilascio nella bozza.
6. **Solo se la release è obbligatoria** (cambiamenti di compatibilità con il server, bug gravi): aggiungi alle note la riga `<!-- wonderflix:min-version=X.Y.Z -->`, dove `X.Y.Z` è la versione minima ancora accettata (di solito quella che stai pubblicando). La riga non è visibile nelle note mostrate.
7. Pubblica la bozza. Da questo momento i client la vedono.
8. Per i test interni: pubblica come **pre-release**. I client la ignorano.
9. **Ricorda:** il marcatore viene letto **solo dall'ultima release pubblicata**. Se una release successiva deve mantenere il blocco, riporta la stessa riga `min-version` (o una più alta) anche nelle sue note.

## 11. Log e supporto

- File di log a rotazione in `%LocalAppData%\WonderFlix\logs` (5 file da 2 MB).
- I log non contengono mai token, password o l'header `Authorization`.
- Pulsante **"Copia diagnostica"** nelle Impostazioni: copia negli appunti versione dell'app, versione di Windows, versione del server, impostazioni del player e ultimi 50 errori.

## 12. Struttura del progetto e test

```
lib/
  main.dart
  app/            router, tema, icone, localizzazione
  config/         AppConfig
  core/           client HTTP con header di autenticazione, storage, logger, errori
  features/
    auth/ home/ library/ detail/ person/ search/ favorites/
    player/ settings/ update/ discord/
packages/
  jellyfin_api/   client generato da OpenAPI (spec 10.11 salvato nel repo)
assets/brand/     logo, banner, icona .ico
assets/fonts/     Bebas Neue, Inter
l10n/             app_it.arb, app_en.arb
installer/        wonderflix.iss
config/           wonderflix.example.json
.github/workflows ci.yml, release.yml
docs/             RELEASING.md, specs, plans
```

### Test automatici (`ci.yml`: `flutter analyze` + `flutter test` a ogni push e PR)

**Unit test:**
- `PlaybackService`: scelta tra direct play e transcodifica, ripiego una sola volta, mappatura `Index` ↔ `ff-index`, sottotitoli esterni.
- Report dell'avanzamento: tempi (ogni 10 s, eventi, stop) con orologio finto.
- `AuthService`: ripristino del token, 401, logout.
- Quick Connect: attesa dell'approvazione, scadenza e rigenerazione del codice.
- `UpdateService`: confronto semver, lettura di `min-version`, esclusione delle pre-release, verifica SHA-256.
- `SegmentsService`: quale pulsante mostrare in base alla posizione.

**Widget test:**
- Form di login (entrambe le schede).
- Overlay del player con un `VideoEngine` finto.
- Righe della Home.
- Stati di caricamento ed errore.

### Checklist dei test manuali (prima di ogni release, su un utente di prova)

- MKV con sottotitoli ASS interni, PGS interni e SRT esterni: resa corretta e sincronizzata.
- Ripresa dal minutaggio; stato "visto" sincronizzato con jellyfin-web.
- Ripiego sulla transcodifica (forzato).
- Salta intro, prossimo episodio, trickplay.
- Login con password e con Quick Connect; sessione scaduta.
- Aggiornamento da una versione precedente; aggiornamento obbligatorio.
- Discord Rich Presence attiva e disattivata.

## 13. Note per lo Spec B (watch party)

Non fa parte di questo spec. Serve come promemoria di cosa lo Spec A deve rendere possibile.

- Jellyfin ha già **SyncPlay** lato server. Il comportamento lamentato (il video che va avanti o indietro da solo) viene dalle correzioni di sincronizzazione del client (SkipToSync/SpeedToSync) e da come vengono propagati i salti.
- Da definire nello Spec B: regole precise sui salti nel gruppo (chi può saltare, cosa vedono gli altri) e la strategia di correzione (preferire piccoli aggiustamenti di velocità ai salti).
- Lo Spec A fornisce: `VideoEngine` con controllo preciso di posizione e velocità, `ServerEvents` (WebSocket), un player con overlay estendibile.

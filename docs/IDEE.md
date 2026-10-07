# WonderFlix — lista di idee

Le idee per i prossimi spec, in nessun ordine. All'inizio di uno spec l'utente sceglie da qui; finito, l'idea esce dalla lista (le fatte sono in fondo).

**Escluso per scelta dell'utente**, da non riproporre:
- entrare in un watch party da Discord o con un collegamento `wonderflix://`;
- nella coda del party, la ripetizione e lo svuotamento (Spec H §5);
- HDR vero (oggi media_kit converte in SDR) e firma del codice (deciso all'inizio dello Spec K).

## 1. Versione web

Stesso client nel browser, usato da tutti con il protocollo WonderFlix, watch party compreso. La logica di sincronizzazione è in Dart puro (`lib/core/syncplay/`).
- **Da cercare:** video con `<video>` invece di libmpv e ricorso alla transcodifica HLS; sottotitoli ASS/PGS senza libass; CORS e dove salvare il token; precisione di `currentTime`/`playbackRate` per il `DriftCorrector`; cosa non esiste sul web (SMTC, Discord, installer, `window_manager`, `dart:ffi`); hosting e configurazione.
- È lo spec più grosso.

## 2. Altre piattaforme: Smart TV, Android, iOS, macOS, Linux

Rifare l'app perché si possa usare anche su Smart TV (Fire TV Stick e simili, cioè Android TV / Fire OS), telefoni e tablet Android e iOS, macOS e Linux. Ha molto in comune con la versione web (idea 1): in entrambi i casi le parti legate a Windows vanno separate dal resto.
- **Cosa c'è già:** Flutter gira su tutte queste piattaforme, e media_kit (libmpv) ha i pacchetti per Android, iOS, macOS e Linux; client Jellyfin, SyncPlay, watch party e plugin non dipendono da Windows.
- **Cosa è solo Windows oggi:** `media_kit_libs_windows_video`, `smtc_windows` (pannello multimediale), `window_manager` e `screen_retriever` (solo desktop), la pipe di Discord e la preferenza delle animazioni via `dart:ffi` (`windows_discord_pipe.dart`, `windows_animation_pref.dart`), installer e aggiornamenti da GitHub (`installer/`, `docs/RELEASING.md`), il runner `windows/`.
- **Da cercare:**
  - **TV:** interfaccia da divano con il telecomando (D-pad: focus visibile e navigazione su ogni schermata, niente passaggio del mouse, tasti indietro/play), testi più grandi, prestazioni sui chip delle chiavette, decodifica hardware e HDR; distribuzione (Amazon Appstore, Google Play per Android TV, o installazione manuale dell'APK);
  - **telefoni e tablet:** tocco al posto del mouse (passaggio del mouse, anteprime, menu), schermi piccoli e verticali, player a tutto schermo con i gesti, controlli multimediali di sistema e riproduzione in background, picture-in-picture;
  - **iOS e macOS:** account sviluppatore Apple, un Mac per compilare e firmare, notarizzazione, App Store o TestFlight;
  - **Linux:** pacchetto (AppImage, Flatpak), MPRIS al posto dell'SMTC;
  - **aggiornamenti:** l'aggiornamento automatico di oggi vale solo per Windows; sulle altre piattaforme lo fanno gli store, o serve un controllo con link;
  - **Discord Rich Presence** sulle altre piattaforme desktop (pipe Unix) e cosa fare sui dispositivi mobili;
  - pipeline di build e prove per ogni piattaforma.
- **Da chiarire:** quali piattaforme prima (per esempio Fire TV e Android insieme, dato che sono quasi lo stesso codice); stessa app con implementazioni per piattaforma o app separata per la TV; se fare insieme alla versione web il lavoro di separazione dalle parti di Windows.

## 3. Funzioni escluse dallo Spec A

- Profili "Chi guarda?" (più utenti sullo stesso PC): in corso, Spec K.
- Collezioni e saghe (`BoxSet`): in corso, Spec K.
- Download per la visione offline.

## 4. Rifinitura per la v1.0.0

La v1.0.0 è la prima release per gli amici. Raccoglierebbe:
- le prove mai fatte sul server: rete staccata, salvaschermo, trailer locali, tasti multimediali fisici;
- la misura delle prestazioni con `--profile` su un PC modesto;
- prima esecuzione e richiesta d'accesso, firma del codice;
- i punti aperti minori: menu delle modalità con testo ingrandito, attese di 2 s senza indicatore, nome del gruppo che non cambia con il titolo, remux che risulta "Transcode", `WriteFile` sincrono sulla pipe di Discord.

## Fatte

- Spec D — rinnovo del player (app 0.4.0).
- Spec E — watch party con nomi, chat e reazioni (plugin 1.0.0, app 0.5.0).
- Spec F — amici e party privati (plugin 1.1.0, app 0.6.0).
- Spec G — cassetta delle notifiche (plugin 1.2.0, app 0.7.0).
- Spec H — coda del watch party (plugin 1.3.0, app 0.8.0).
- Spec I — richieste con Seerr (plugin 1.4.0, app 0.9.0).
- Spec J — dashboard admin (app 0.10.0).

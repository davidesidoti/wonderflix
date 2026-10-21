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

- Download per la visione offline.

## 4. Rifinitura per la v1.0.0

La v1.0.0 è la prima release per gli amici. Raccoglierebbe:
- le prove mai fatte sul server: rete staccata, salvaschermo, trailer locali, tasti multimediali fisici;
- la misura delle prestazioni con `--profile` su un PC modesto;
- prima esecuzione e richiesta d'accesso, firma del codice;
- i punti aperti minori: menu delle modalità con testo ingrandito, attese di 2 s senza indicatore, nome del gruppo che non cambia con il titolo, remux che risulta "Transcode", `WriteFile` sincrono sulla pipe di Discord.

## 8. Serate programmate

Un party con data e ora, per esempio "Venerdì 21:00 — Il Padrino". Gli amici ricevono l'invito e rispondono sì/no/forse; il promemoria arriva nella cassetta (e su Discord) 15 minuti prima, e all'ora fissata il party è già aperto con il titolo pronto.
- **Cosa c'è già:** party privati, coda, cassetta, collegamento Discord, servizi a orario nel plugin (`NewTitlesHostedService`, `ContactReminderHostedService`).
- **Da cercare:** dove si vedono le serate in arrivo; fusi orari; cosa succede se l'organizzatore non si presenta; modifica e annullamento con avviso a chi ha detto sì; serate ricorrenti (ogni venerdì) o solo singole.
- Medio.


## 10. Stile dei sottotitoli

Oggi si può cambiare solo la dimensione (`subtitleScale`). Si aggiungono carattere, colore, contorno, sfondo e posizione, con l'anteprima dal vivo, salvati per profilo. Il download dei sottotitoli mancanti, anche dal player, è arrivato con la Spec R (app 0.18.0).
- **Da cercare:** quali opzioni di libmpv valgono anche per i sottotitoli ASS (che hanno il loro stile) e PGS (immagini); per il download, la ricerca remota di Jellyfin (`/Items/{id}/RemoteSearch/Subtitles/{lingua}`), che richiede un plugin di sottotitoli sul server (OpenSubtitles) e forse un permesso dell'utente.
- Piccolo, medio con il download.

## 11. Timer e "Stai ancora guardando?"

Il timer di spegnimento ferma la riproduzione dopo N minuti o a fine episodio. Dopo 3 episodi di fila senza toccare nulla, l'app chiede se stai ancora guardando, così una serie non gira tutta la notte segnando episodi come visti.
- **Da cercare:** comportamento nei watch party (probabilmente spento); se mettere in pausa il PC o solo il player; numero di episodi modificabile nelle impostazioni.
- Piccolo.

## 12. Telecomando dal telefono

WonderFlix diventa un dispositivo controllabile dall'app Jellyfin ufficiale sul telefono: "Riproduci su WonderFlix", pausa, avanti, volume, cambio dei sottotitoli. Non è Chromecast: il telefono manda solo i comandi, il video lo riproduce il PC.
- **Cosa c'è già:** la connessione WebSocket agli eventi del server (`server_events.dart`).
- **Da cercare:** dichiarare le capacità della sessione (`SupportsMediaControl`, comandi supportati); gestire i messaggi `Play`, `Playstate` e `GeneralCommand`; cosa fare se arriva un comando durante un watch party; con quali app funziona davvero (Jellyfin per Android/iOS, Findroid, jellyfin-web).
- Medio.

## 13. WonderFlix Wrapped

Un riepilogo mensile o annuale: ore guardate, generi preferiti, serie finite, titolo più rivisto, con chi hai fatto più party. A fine anno arriva nella cassetta come notifica.
- **Da cercare:** il server tiene solo l'ultima visione di ogni titolo, quindi serve che il plugin registri le visioni (o usare il plugin Playback Reporting, se installato); da quando partono i dati; privacy (solo per sé o condivisibile con gli amici).
- Medio. Lo storico delle visioni serve anche all'idea 14.

## 14. Cronologia

Tutto quello che si è visto, con la data, i filtri (film, serie, mese) e "segna come non visto".
- **Cosa c'è già:** `LastPlayedDate` e `PlayCount` di Jellyfin per ogni titolo.
- **Da cercare:** con i soli dati del server ogni titolo compare una volta, all'ultima visione; per lo storico completo serve il registro del plugin dell'idea 13.
- Piccolo/medio.

## 16. Calendario delle uscite

I prossimi episodi delle serie che si seguono, giorno per giorno, con un avviso nella cassetta quando arrivano sul server.
- **Cosa c'è già (Spec M):** il plugin legge il calendario di Sonarr e di Radarr (`Upcoming/Series`, `Upcoming/Movies`, con il collegamento alle serie della libreria); la Home ha le righe "Serie in arrivo" (7 giorni) e "Film in arrivo".
- **Da cercare:** da dove prendere le date: `/Shows/Upcoming` di Jellyfin (se il server conosce gli episodi futuri) oppure il calendario di Sonarr, direttamente o attraverso il plugin; quali serie contano come "seguite" (La mia lista, guardate di recente); legame con l'avviso dei nuovi titoli che c'è già (`NewTitlesHostedService`).
- Medio.

## Fatte

- Spec D — rinnovo del player (app 0.4.0).
- Spec E — watch party con nomi, chat e reazioni (plugin 1.0.0, app 0.5.0).
- Spec F — amici e party privati (plugin 1.1.0, app 0.6.0).
- Spec G — cassetta delle notifiche (plugin 1.2.0, app 0.7.0).
- Spec H — coda del watch party (plugin 1.3.0, app 0.8.0).
- Spec I — richieste con Seerr (plugin 1.4.0, app 0.9.0).
- Spec J — dashboard admin (app 0.10.0).
- Spec K — saghe e profili (plugin 1.5.0, app 0.11.0).
- Spec L — recupero e cambio della password (plugin 1.6.0, app 0.12.0).
- Spec M — Home su misura (plugin 1.7.0, app 0.13.0).
- Spec N — consigli tra amici (plugin 1.8.0, app 0.14.0).
- Spec O — cosa guardano gli amici (plugin 1.9.0, app 0.15.0).
- Spec P — match del film (plugin 1.10.0, app 0.16.0).
- Spec Q — voti degli amici (plugin 1.11.0, app 0.17.0).
- Spec R — segnalazioni, sottotitoli e strumenti admin dei metadati (plugin 1.12.0, app 0.18.0 e 0.19.0).

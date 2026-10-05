# WonderFlix — lista di idee

Le idee per i prossimi spec, in nessun ordine. All'inizio di uno spec l'utente sceglie da qui; finito, l'idea esce dalla lista (le fatte sono in fondo).

**Escluso per scelta dell'utente**, da non riproporre:
- entrare in un watch party da Discord o con un collegamento `wonderflix://`;
- nella coda del party, la ripetizione e lo svuotamento (Spec H §5).

## 1. Dashboard e azioni da admin dentro WonderFlix

Oggi l'amministrazione passa dalla Dashboard di Jellyfin nel browser, e così le funzioni admin del plugin (annunci, "Invia ora" delle novità). L'idea è averle nell'app, solo per gli utenti amministratori.
- **Da cercare:**
  - chi è admin: `Policy.IsAdministrator` dell'utente, già nella sessione;
  - cosa serve davvero all'utente, tra: sessioni attive e chi sta guardando (`/Sessions`), utenti e permessi (`/Users`, policy), aggiornamento delle librerie (`/Library/Refresh`), attività pianificate (`/ScheduledTasks`), registro attività (`/System/ActivityLog/Entries`), info e riavvio del server (`/System/Info`, `/System/Restart`), log, plugin;
  - le funzioni admin del plugin WonderFlix Watch Party: annunci, `Inbox/NewTitles` e "Invia ora";
  - conferme per le azioni distruttive o che interrompono la visione (riavvio con qualcuno che guarda, come si fa oggi a mano con il log).
- **Da chiarire:** pannello in una pagina sua o dentro il profilo; solo lettura (stato) o anche azioni; cosa resta nella Dashboard web.

## 2. Integrazione di Seerr

Seerr (l'erede di Overseerr e Jellyseerr) gira già sul server Ultra.cc (`~/.apps/seerr`), collegato a Jellyfin, con l'accesso tramite le credenziali di Jellyfin acceso. L'idea è chiedere film e serie che mancano direttamente dall'app.
- **Da cercare:**
  - API di Seerr (`/api/v1`): accesso dell'utente con le credenziali Jellyfin (`POST /api/v1/auth/jellyfin`, cookie di sessione) invece della chiave API dell'admin; ricerca, scoperta, richieste e il loro stato, quote, permessi;
  - dove sta nell'app: titoli che non ci sono nei risultati della ricerca con "Richiedi", una pagina "Richieste" con lo stato, stagioni scelte per le serie;
  - avviso quando un titolo richiesto arriva: notifiche di Seerr (webhook) verso la cassetta delle notifiche del plugin, o il riepilogo delle novità che c'è già;
  - indirizzo di Seerr nella configurazione dell'app (`--dart-define-from-file`) e CORS se un giorno c'è la versione web.
- **Da chiarire:** chi può chiedere (tutti o solo alcuni), richieste da approvare o automatiche, cosa vede chi non ha un account Seerr.

## 3. Versione web

Stesso client nel browser, usato da tutti con il protocollo WonderFlix, watch party compreso. La logica di sincronizzazione è in Dart puro (`lib/core/syncplay/`).
- **Da cercare:** video con `<video>` invece di libmpv e ricorso alla transcodifica HLS; sottotitoli ASS/PGS senza libass; CORS e dove salvare il token; precisione di `currentTime`/`playbackRate` per il `DriftCorrector`; cosa non esiste sul web (SMTC, Discord, installer, `window_manager`, `dart:ffi`); hosting e configurazione.
- È lo spec più grosso.

## 4. Funzioni escluse dallo Spec A

- Profili "Chi guarda?" (più utenti sullo stesso PC).
- Collezioni e saghe (`BoxSet`).
- Download per la visione offline.
- HDR vero (oggi media_kit converte in SDR).
- Firma del codice (pipeline già predisposta, `docs/RELEASING.md`).

## 5. Rifinitura per la v1.0.0

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

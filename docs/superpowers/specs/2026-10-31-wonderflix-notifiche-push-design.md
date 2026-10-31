# WonderFlix — Spec V: notifiche push

- **Data:** 2026-10-31
- **Stato:** approvata il 2026-10-31; realizzata con i piani 31a (plugin 1.17.0) e 31b (app 0.26.0), da provare a mano.
- **Ambito:** idea 15 di `docs/IDEE.md` ("Notifiche push sulla web app"), allargata al PC.
- **Ricerca:** ricognizione del codice fatta in sessione. Le cose che servono sono riportate qui sotto.

I percorsi `lib/…`, `web/…` sono dentro `app/`; i percorsi `Hub/…`, `Downloads/…`, `Space/…`, `Account/…`, `Api/…` sono dentro `plugin/Jellyfin.Plugin.WonderFlixWatchParty/`.

## 1. Perché e per chi

Sul telefono l'utente usa WonderFlix come web app aggiunta alla Home (decisione del 2026-10-31: niente app nativa su iPhone, vedi idea 2 di `docs/IDEE.md`). Oggi scopre le cose solo aprendo l'app. I momenti che ha raccontato:
- come utente: un titolo che ha chiesto è disponibile, una richiesta è stata accettata;
- come admin: una richiesta nuova da approvare, un download che ha bisogno di lui, una segnalazione nuova, e in generale "la maggior parte delle cose" che richiedono un suo intervento.

Oggi:
- la **cassetta** (`Hub/InboxService.cs`) è il punto dove nascono le notifiche, ma arriva solo alle sessioni dell'app aperte (evento `InboxChanged` sul WebSocket di Jellyfin);
- il **bot Discord** e l'email servono solo per i messaggi dell'account (codici di recupero, verifica dei contatti, "password cambiata"), non come notifiche;
- gli eventi operativi da admin (download, spazio, server) finiscono solo nei log o nelle schede che l'app ricarica ogni 60 s.

Le push di iOS arrivano anche ad app chiusa e telefono bloccato, ma solo a una web app aggiunta alla Home: è il motivo per cui la web app rende più dell'app nativa gratuita (AltStore), dove le push non ci sono.

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- **Telefono** (web app sulla Home, iPhone e Android) e **sito nel browser del PC** (Chrome/Edge): notifiche push vere, che arrivano anche con l'app chiusa e il telefono bloccato (sul PC finché il browser è in esecuzione).
- **App Windows:** notifiche di Windows solo mentre l'app è aperta, anche ridotta a icona (decisione dell'utente).
- Ogni voce che entra nella cassetta diventa anche una notifica, più gli eventi nuovi del §4.3.
- Preferenze nelle impostazioni: un interruttore per tipo di notifica, per utente (decisione dell'utente).
- Toccando la notifica si apre la schermata giusta.

**Non obiettivi**
- App nativa iOS, profili di configurazione (`.mobileconfig`) e icona della Home: decisi il 2026-10-31, restano fuori.
- App Windows attiva a finestra chiusa (area di notifica, avvio con Windows): l'utente ha scelto "solo quando è aperta".
- Notifiche per: download avviato o importato, torrent tolti in automatico dopo il seed, operazione dello spazio completata, nuovo utente. Escluse per non fare rumore (scelta di Claude, l'utente ha approvato la lista).
- Il numero sull'icona (badge) della web app.
- Discord ed email come canali di notifica.
- Push "silenziose" per aggiornare dati in background (iOS non le permette).
- Il pulsante "Installa" su Android Chrome (`beforeinstallprompt`): utile, ma è un'altra cosa.

**Anti-obiettivi** (sarebbe un fallimento anche se funziona)
- **Raffiche.** Un download bloccato che notifica a ogni giro del servizio, il disco pieno che notifica ogni 5 minuti, dieci push per dieci titoli nuovi. Ogni evento notifica una volta sola quando succede (§4.4).
- **Notifiche alla persona sbagliata.** Un evento da admin a un utente normale; un telefono che continua a ricevere le notifiche di un account dopo che lì si è usciti.
- **Dati sensibili nella notifica.** Niente ApiKey, token, codici di recupero, indirizzi email o percorsi del seedbox nel contenuto della push: passa dai server di Apple, Google e Microsoft.
- **Cassetta rotta.** Le push sono un'aggiunta: se l'invio fallisce, la voce nella cassetta resta e niente si blocca.

## 3. Vincoli

- **iOS:**
  - le push arrivano solo alla web app aggiunta alla Home (iOS 16.4 o successivo), non a una scheda del browser;
  - il permesso si chiede solo dopo un tocco dell'utente, dentro la web app;
  - ogni push ricevuta deve mostrare una notifica visibile, altrimenti iOS revoca l'iscrizione;
  - l'iPhone dell'utente ha iOS 27.2.
- **Sito:** servito da nginx sul seedbox sotto `/wonderflix/` (e `/wonderflix-prova/` per le prove), con gli header `Cross-Origin-Opener-Policy: same-origin` e `Cross-Origin-Embedder-Policy: credentialless` (servono a skwasm), configurazione in `app/deploy/`. Il service worker deve funzionare con quel percorso e quegli header. Il sito vero e quello di prova parlano con lo stesso plugin: sono due iscrizioni diverse, e va bene.
- **Flutter 3.47.5** (fissato in CI). Il service worker è un file JavaScript nostro in `web/`: il builder controlla che non vada in conflitto con quello che `flutter_bootstrap.js` registra da sé (se lo fa ancora).
- **Plugin:** net9.0, compila contro Jellyfin 10.11.0 e i test girano contro 10.11.9. Le API di Jellyfin cambiano anche nelle patch (vedi `CLAUDE.md`). Nei DTO, i campi nullable che devono esserci sempre vogliono `JsonIgnore(Condition = Never)`.
- **Niente servizi a pagamento.** Web Push con chiavi VAPID va direttamente ai servizi push di Apple, Google e Microsoft; il seedbox deve poterli raggiungere in HTTPS (da verificare con una prova).
- **Lingue:** l'app è in italiano e inglese, e la lingua si sceglie nell'app, per dispositivo (`lib/features/settings/locale_controller.dart`). Le notifiche usano la lingua scelta nell'app su quel dispositivo.

## 4. Come funziona (deciso)

### 4.1 Canali

- **Web (telefono e PC):** Web Push standard con chiavi VAPID.
  - Il plugin genera la coppia di chiavi VAPID una volta e la tiene nella sua configurazione; la chiave pubblica si legge da un endpoint (scelta di Claude).
  - Il sito ha un service worker che riceve la push, mostra la notifica e al tocco apre o porta in primo piano la web app sulla rotta giusta.
- **App Windows:** quando arriva `InboxChanged` dal WebSocket (oggi ricarica già la cassetta), le voci nuove diventano notifiche di Windows.
  - Solo le voci arrivate mentre l'app è aperta: all'avvio e alla riconnessione non escono notifiche per voci vecchie (scelta di Claude).
  - Al clic la finestra torna in primo piano sulla rotta giusta.
- **Più dispositivi:** la notifica arriva a tutti i dispositivi iscritti dell'utente, anche se in quel momento uno ha l'app aperta (scelta di Claude: la regola più semplice).

### 4.2 Iscrizione di un dispositivo

- Nelle impostazioni, sezione **Notifiche**, sul web c'è "Attiva notifiche su questo dispositivo". Lo stato è sempre chiaro:
  - **attive** (con "Disattiva");
  - **da attivare** (pulsante);
  - **permesso negato** (con come riattivarlo dalle impostazioni del telefono o del browser);
  - **non disponibili qui**: su iPhone fuori dalla web app, spiega di aggiungere il sito alla Home; nei browser senza push, lo dice e basta.
- L'iscrizione (endpoint e chiavi del browser) va al plugin legata all'utente e al dispositivo, con la lingua scelta nell'app. Se la lingua cambia, il plugin la aggiorna.
- **All'uscita dall'account** sul dispositivo, l'iscrizione si cancella dal plugin (scelta di Claude, per l'anti-obiettivo "persona sbagliata").
- **Accesso tolto senza uscire** (scelta di Claude, stesso anti-obiettivo): sessione revocata dalla dashboard di Jellyfin, token scaduto, password cambiata col recupero, utente disattivato.
  - Ogni iscrizione è legata al dispositivo Jellyfin (`DeviceId`) da cui è stata fatta.
  - Prima di ogni invio il plugin controlla che quel dispositivo abbia ancora un accesso valido per quell'utente, che l'utente sia attivo e, per gli eventi admin, che sia ancora admin.
  - Se il controllo non passa, la push non parte e l'iscrizione si cancella.
  - Il builder sceglie l'API di Jellyfin per il controllo, verificandola su 10.11.0.
- Il plugin cancella da sé le iscrizioni che il servizio push dichiara scadute (risposte 404/410).
- L'app Windows non ha iscrizioni: le preferenze valgono anche lì.

### 4.3 Cosa notifica

Ogni evento qui sotto entra nella **cassetta** e diventa **anche** una notifica. Gli eventi nuovi (segnati "nuovo") entrano nella cassetta come gli altri, così li vede anche chi non ha attivato le push (scelta di Claude).

**Per tutti**
- Una tua richiesta è disponibile (`RequestAvailable`, c'è già).
- **Nuovo:** una tua richiesta è stata accettata. **Nuovo:** una tua richiesta è stata rifiutata.
  - Oggi `Hub/RequestWebhookHandler.cs` tratta solo `MEDIA_AVAILABLE` e `MEDIA_PENDING` e scarta gli altri tipi. Si aggiungono i tipi di Seerr per approvata (anche in automatico) e rifiutata.
  - Seerr manda il webhook anche quando si approva dall'app WonderFlix, quindi basta il webhook. Va abilitato in Seerr per i tipi nuovi: istruzioni nel README del plugin.
- Inviti al watch party e al match, consigli degli amici, titoli nuovi, annunci dell'admin, promemoria del contatto, segnalazione risolta: ci sono già nella cassetta.

**Per gli admin** (a tutti gli admin)
- Nuova richiesta da approvare (`RequestPending`, c'è già: va a chi può approvare in Seerr) e nuova segnalazione (`ReportPending`, c'è già).
- **Nuovo — download che ti richiedono:**
  - nessun risultato o punteggio sotto il minimo (`NeedsYou` con `NothingFound` / `BelowMinScore`, `Downloads/DownloadService.Search.cs`);
  - grab rifiutato (`GrabRefused`);
  - ricerca fallita (`SearchFailed`);
  - import bloccato da fare a mano (`ImportBlocked`, `Downloads/DownloadService.cs`), e lo stesso per un Alleggerisci bloccato (`Space/SpaceService.Lighten.cs`);
  - download fermo e tolto dalla coda (`Downloads/DownloadService.cs`).
- **Nuovo — spazio:**
  - operazione dello spazio fallita (`Failed`, `Space/SpaceService.cs`);
  - disco quasi pieno: la quota del seedbox (`Space/QuotaFile.cs`) supera una soglia. La soglia si imposta dagli admin nella scheda Spazio, predefinita al 90% usato (scelta di Claude).
- **Nuovo — sicurezza** (`Account/PasswordRecovery.cs`), senza codici né contatti nel testo. Le regole sono scelte di Claude: la richiesta di recupero non richiede il login, e chiunque potrebbe usarla per mandare push agli admin.
  - **Recupero avviato:** solo per un utente che esiste ed è attivo. I nomi sconosciuti o disattivati non notificano. Il recupero avviato da un admin per un utente (`SendForAdminAsync`) non notifica.
  - **Recupero bloccato:** quando scatta un blocco per troppe richieste, per utente o generale, e quando scatta un blocco per troppi codici sbagliati, se esiste. Una notifica per blocco.
- **Nuovo — server:** Jellyfin chiede un riavvio (`HasPendingRestart`, che oggi l'app legge solo nella striscia admin).

### 4.4 Una notifica per evento

- I download notificano quando **entrano** in uno stato o motivo della lista, non a ogni giro del servizio. Se escono e ci rientrano, notificano di nuovo.
- Il disco quasi pieno notifica quando la quota **supera** la soglia, e di nuovo solo dopo essere tornata sotto.
- Il riavvio richiesto notifica quando passa da no a sì.
- Il blocco del recupero notifica una volta per blocco.
- Gli eventi che oggi raccolgono più cose in una voce della cassetta (per esempio i titoli nuovi) fanno una notifica sola per voce.
- **Voci aggiornate o ricreate** (scelta di Claude). Notifica solo una voce **nuova** della cassetta. Gli aggiornamenti di una voce che c'è già non notificano: `UpsertInvite`, `UpsertRecommendation`, e il promemoria del contatto che `Account/ContactReminders.cs` cancella e riscrive a ogni giro.
  - Il promemoria del contatto notifica quindi una volta, alla prima voce.
  - Un invito allo stesso party già nella cassetta non notifica di nuovo.
  - Non basta agganciare la push a `NotifyAsync` di `InboxService`, che parte anche per gli aggiornamenti.

### 4.4b Voci admin che si chiudono da sole

Stessa regola che c'è già per `ReportPending`, che sparisce da tutte le cassette quando la segnalazione si chiude (`RemoveReportEntriesAsync`). È una scelta di Claude.
- **Spariscono quando il problema è risolto:**
  - il download che richiedeva l'admin esce da quello stato (sistemato, rifatto o tolto);
  - il disco torna sotto la soglia;
  - il riavvio richiesto non c'è più.
- **Restano come storico:** operazione dello spazio fallita e eventi di sicurezza.
- Una notifica già mostrata sul telefono resta lì: non si ritira.

### 4.5 Preferenze

- Sezione **Notifiche** nelle impostazioni, con un interruttore per tipo di notifica. Tutti accesi all'inizio (scelta di Claude).
- Le preferenze sono per utente, salvate nel plugin, e valgono su tutti i suoi dispositivi e sull'app Windows (scelta di Claude).
- Ognuno vede gli interruttori dei tipi che può ricevere (scelta di Claude):
  - gli eventi admin solo gli admin;
  - "nuova richiesta da approvare" chi può approvare in Seerr, anche se non è admin di Jellyfin.
- Un interruttore spento ferma la push e la notifica di Windows. La voce nella cassetta resta (scelta di Claude: la cassetta è lo storico).
- Il builder decide come raggruppare gli interruttori, purché ogni tipo del §4.3 sia controllabile.

### 4.6 Contenuto e tocco

- La notifica ha un titolo e una riga di testo nella lingua del dispositivo, per esempio "Richiesta accettata — Dune: Parte due" o "Download da sistemare — Severance S02".
- Al tocco si apre la schermata dell'oggetto: la richiesta, la scheda Download o Spazio della dashboard admin, la segnalazione, il watch party, il titolo, la cassetta. Se la rotta esatta non c'è, si apre la cassetta.

## 5. Prove

- **Plugin:** test per l'archivio delle iscrizioni, l'invio (con un servizio push finto, comprese le risposte 404/410), il filtro delle preferenze e dei ruoli, ogni evento nuovo del §4.3 e la regola "una volta per evento" del §4.4.
- **App:** test per la sezione Notifiche (stati del §4.2, interruttori per ruolo) e per le notifiche di Windows (nessuna notifica per le voci vecchie all'avvio).
- **A mano** (sul sito di prova `/wonderflix-prova/` e con l'app Windows), da aggiungere alla checklist di `docs/RELEASING.md`:
  - iPhone con la web app sulla Home: attivazione, push con app chiusa e telefono bloccato, tocco che apre la schermata giusta, uscita dall'account che ferma le push;
  - Chrome o Edge sul PC: le stesse prove con la scheda chiusa;
  - app Windows aperta e ridotta a icona: notifica e clic;
  - preferenze: un tipo spento non arriva;
  - un evento admin per tipo, provocato a mano dove si può.

## 6. Lasciato al builder

- Libreria .NET per Web Push (cifratura del contenuto e firma VAPID) e pacchetto Flutter per le notifiche di Windows.
- Come il service worker si integra con la build web di Flutter.
- Formato del contenuto della push e dove nascono i testi (plugin o service worker), purché rispettino la lingua del dispositivo e il §2 (niente dati sensibili).
- Dove salvare iscrizioni e preferenze nel plugin, seguendo i file JSON che il plugin usa già (`inbox.json`, `downloads.json`, …).
- Nomi dei tipi nuovi della cassetta, endpoint e testi delle voci nella cassetta.
- In che ordine costruire, con un vincolo: il piano **comincia con una prova** delle due cose che possono cambiare il design (scelta di Claude).
  - **Il tocco su un pulsante Flutter basta a iOS per chiedere il permesso?** Se no, va bene un pulsante HTML vero sopra la tela di Flutter, solo per quel passo.
  - **Il seedbox raggiunge i servizi push di Apple, Google e Microsoft?** Se no, il lavoro si ferma e si torna dall'utente, perché ogni alternativa (un servizio esterno) va decisa con lui.

## 7. Fatto quando

- Sull'iPhone dell'utente, con la web app sulla Home, una richiesta accettata e un download bloccato arrivano come notifica con l'app chiusa, e il tocco apre la schermata giusta.
- Sul PC, la stessa cosa dal sito in Chrome o Edge, e dall'app Windows aperta.
- Ogni tipo del §4.3 si può spegnere dalle impostazioni, e quando è spento non arriva.
- Le prove del §5 passano e la checklist di `docs/RELEASING.md` è aggiornata.

## 8. Decisioni dei piani

Piano 31a (parte plugin, plugin 1.17.0):
1. **Web Push scritto a mano** con le primitive di .NET, provato con il vettore di esempio di RFC 8291 §5. Niente librerie esterne: il plugin si distribuisce come dll singola.
2. **I testi delle push nascono nel plugin**, in it/en, nella lingua salvata con l'iscrizione. Il service worker dell'app mostra solo quello che riceve.
3. **"Download fermo" è uno storico** (§4.4b): è un evento, non uno stato in cui il download resta.
4. **La soglia del disco sta nella configurazione del plugin** (`QuotaAlertPercent`), nella sezione Spazio di `configPage.html`, dove ci sono già le altre impostazioni dello spazio. Nell'app non c'è una pagina di impostazioni dello spazio.
5. **Profili sullo stesso dispositivo:** l'iscrizione è per coppia (endpoint, utente). Ogni profilo attiva le sue; uscire da un profilo toglie solo le sue.

Esito del Task 1 (prove dei due rischi):
- il seedbox raggiunge i servizi push: `web.push.apple.com` risponde 405, `fcm.googleapis.com` 404, `wns2-par02p.notify.windows.com` 404 (la rete non è un ostacolo);
- la prova su iOS 27.2 è riuscita (il permesso è chiesto da un pulsante Flutter, risposta "granted", `PushManager` presente): l'app usa un normale pulsante Flutter.

Scelte fatte durante la costruzione:
- le iscrizioni si accettano solo da host dei servizi push dei browser (Apple, `googleapis.com`, `notify.windows.com`, Mozilla);
- l'avviso `RecoveryBlocked` tace per la finestra del limite dopo aver avvisato, perché la finestra del limitatore scorre.

Piano 31b (parte app, app 0.26.0):
- un DELETE fallito all'uscita dall'account disiscrive comunque il browser e cancella tutte le chiavi salvate su quel dispositivo;
- le notifiche di Windows usano l'AppUserModelID dell'installer `it.wonderflix.WonderFlix` (`ShortcutPolicy.ignore`);
- le notifiche di Windows annunciano solo le voci nuove, come la push.

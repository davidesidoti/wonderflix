# WonderFlix Watch Party (plugin di Jellyfin)

Plugin del server Jellyfin per il watch party di WonderFlix (spec E,
`docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md`):
dice chi ha agito, porta la chat e le reazioni tra i membri di un gruppo
SyncPlay e tiene la lista amici (spec F,
`docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md`)
e la cassetta delle notifiche (spec G,
`docs/superpowers/specs/2026-10-03-wonderflix-notifiche-design.md`). Dalla
1.3.0 dice anche chi ha cambiato la coda del gruppo (spec H,
`docs/superpowers/specs/2026-10-04-wonderflix-coda-party-design.md`).
Dalla 1.4.0 fa da tramite verso Seerr per chiedere film e serie dall'app
(spec I, `docs/superpowers/specs/2026-10-05-wonderflix-seerr-design.md`).
Dalla 1.5.0 dà le saghe (le collezioni di Jellyfin) e le immagini degli
altri utenti (spec K,
`docs/superpowers/specs/2026-10-07-wonderflix-saghe-profili-design.md`).
Dalla 1.6.0 porta il recupero della password con un codice su Discord o per
email (spec L,
`docs/superpowers/specs/2026-10-09-wonderflix-recupero-password-design.md`).
Dalla 1.7.0 dà la Home dell'admin (quali righe vede ogni utente nella Home
dell'app) e le uscite in arrivo da Sonarr e Radarr (spec M,
`docs/superpowers/specs/2026-10-10-wonderflix-home-su-misura-design.md`).
Dalla 1.8.0 tiene i consigli tra amici: un utente consiglia un film o una serie ai suoi amici, che lo trovano nella cassetta e nella riga "Consigliati per te" della Home (spec N, `docs/superpowers/specs/2026-10-12-wonderflix-consigli-design.md`).
Dalla 1.9.0 mostra agli amici cosa si sta guardando in WonderFlix e i titoli visti negli ultimi 30 giorni, con un interruttore per non mostrarlo (spec O, `docs/superpowers/specs/2026-10-13-wonderflix-cosa-guardano-amici-design.md`).
Dalla 1.10.0 c'è il match del film: gli amici in una sala votano sì o no su una pila di titoli e partono in un party privato con quelli che piacciono a tutti (spec P, `docs/superpowers/specs/2026-10-14-wonderflix-match-film-design.md`).
Senza il plugin WonderFlix funziona lo stesso, con gli avvisi
anonimi, senza saghe, con le iniziali al posto delle immagini, senza il
recupero della password, con la Home nell'ordine predefinito e senza le
uscite in arrivo.

- Jellyfin **10.11.x** (net9.0, `targetAbi` 10.11.0.0). Per Jellyfin 12 serve
  una build nuova (net10.0).
- Le impostazioni stanno nella pagina del plugin nella Dashboard (menu
  laterale, sotto Plugin): **Notify new titles** (accesa di default), Seerr, il
  recupero della password e Sonarr e Radarr. La stessa pagina manda
  un **annuncio** a tutti e, con **Send now**, il riepilogo dei nuovi titoli in
  attesa. Endpoint sotto `/WonderFlixWatchParty`; gli eventi arrivano ai client
  come `GeneralCommand` `SendString` con la chiave `WonderFlixWatchParty`.
- **Dati:** amicizie e richieste stanno in
  `plugins/configurations/WonderFlixWatchParty/friends.json` (non nella
  cartella del plugin, che cambia a ogni versione). Un file illeggibile
  diventa `friends.json.bad` e il plugin riparte vuoto.
- **Notifiche:** la cassetta di ogni utente (inviti ai watch party, annunci,
  nuovi titoli) sta in `plugins/configurations/WonderFlixWatchParty/inbox.json`:
  30 giorni, al massimo 100 voci per utente. Un file illeggibile diventa
  `inbox.json.bad`. **Nuovi titoli:** i film e gli episodi aggiunti alla
  libreria si raccolgono in un'ondata che si chiude dopo 15 minuti senza novità
  (al massimo 2 ore); ogni utente riceve i film che può vedere e gli episodi
  delle serie che segue (La mia lista, o un episodio visto o iniziato).
  Se un fornitore di metadati continua a fallire, i titoli senza metadati
  tengono ferma l'ondata fino a 2 ore (poi partono con quello che hanno, ma
  solo agli utenti senza limiti sui contenuti, come con **Send now**).
  Prima di spostare una libreria in un altro percorso spegni **Notify new
  titles**: ogni titolo sembrerebbe nuovo. L'impostazione sta in
  `plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml`.
- **Party:** l'app registra ogni gruppo con la sua modalità (pubblico, solo
  amici, privato con codice) e chiede al plugin l'elenco già filtrato
  (`GET Parties`). I party stanno in RAM e spariscono con i gruppi SyncPlay.
- **Seerr (dalla 1.4.0):** nella pagina del plugin si mettono l'indirizzo di
  Seerr (come lo vede il server Jellyfin) e la sua chiave API; **Test
  connection** li prova. Con indirizzo e chiave `GET Info` annuncia
  `requests` e l'app mostra le richieste. Il plugin agisce in Seerr per
  conto dell'utente (`X-API-User`) e crea l'account Seerr mancante alla
  prima richiesta. Il **webhook** di Seerr (indirizzo, modello JSON con il
  segreto e i tipi "Request Pending Approval" e "Request Available"
  sono nella stessa pagina) porta nella cassetta "Ora disponibile" a chi ha
  chiesto il titolo e "Nuova richiesta" a chi può approvare. Indirizzo,
  chiave e segreto stanno nella configurazione del plugin, leggibile solo
  dagli admin.
- **Saghe (dalla 1.5.0):** `GET Collections` dà le collezioni di Jellyfin che
  l'utente vede, ognuna con i soli film che vede (le sue librerie e il
  controllo parentale, come `GET /Items`); una collezione senza film visibili
  non compare. Non si salva niente: si legge da Jellyfin a ogni chiamata.
- **Immagini degli utenti (dalla 1.5.0):**
  `GET Users/Avatars?ids=<id,…>&names=<nome,…>` dà id, nome e tag
  dell'immagine dei soli utenti chiesti (al massimo 100 voci, gli utenti
  disattivati no); con id e tag l'app legge l'immagine da `/UserImage`. Un
  nome si cerca senza badare alle maiuscole. **Rischio accettato:** una
  ricerca per nome conferma che un account esiste, anche nascosto. È basso:
  `/Users/Public` elenca già gli utenti non nascosti, e la ricerca degli amici
  trova i nomi per sottostringa.
- **Recupero della password (dalla 1.6.0):** ogni utente collega e verifica
  il suo Discord o la sua email (`Account/Contacts`, con la password attuale e
  un codice a 6 cifre mandato lì: chi ha solo una sessione aperta non può
  cambiare i contatti). Chi dimentica la password chiede un codice dal login
  (`Account/Recovery`, senza accesso: la risposta non dice se l'account
  esiste) e sceglie la password nuova; tutte le sue sessioni si chiudono.
  Gli admin non possono usarlo (possono collegare i contatti, per la
  prova). Nella pagina del plugin: token del bot e id
  del server Discord, server SMTP (STARTTLS, di solito 587), mittente, ogni
  quanti giorni il promemoria nella cassetta a chi non ha contatti (0:
  spento) e **Send a test**. Il bot: Discord Developer Portal → l'app →
  Bot (il token, "Server Members Intent" acceso), poi l'invito nel server
  con lo scope `bot`, senza permessi. I contatti stanno in
  `plugins/configurations/WonderFlixWatchParty/contacts.json` (un file
  illeggibile diventa `contacts.json.bad`); i codici solo in memoria (10
  minuti, 5 tentativi). Gli endpoint dell'admin stanno sotto
  `Account/Admin`.
- **Home (dalla 1.7.0):** `GET Home/Layout` dà la Home dell'admin (gli id
  delle righe accese, in ordine; `null` se mai impostata), `POST Home/Layout`
  la cambia (solo admin, dall'app; gli id sconosciuti si scartano). Le uscite
  in arrivo: `GET Upcoming/Series` (episodi entro N giorni dal calendario di
  Sonarr, non ancora scaricati, con la serie di Jellyfin se l'utente la vede)
  e `GET Upcoming/Movies` (film con l'uscita digitale entro N giorni, da
  Radarr); rispondono sempre 200, con `Error` (`NotConfigured`,
  `Unauthorized`, `Unreachable`) se qualcosa non va. Le risposte restano in
  memoria 15 minuti (gli errori 1 minuto). Nella pagina del plugin: indirizzo
  (con l'UrlBase, es. `https://host/sonarr`) e chiave di Sonarr e Radarr, i
  giorni e **Test connection** (`POST Upcoming/Test`, solo admin). Le chiavi
  non lasciano il server; le immagini sono gli indirizzi pubblici di TVDB e TMDB.
- **Consigli (dalla 1.8.0):** `GET Recommendations/Targets?itemId=` dà gli
  amici attivi con online e accesso al titolo; `POST Recommendations`
  `{ItemId, To, Message}` consiglia un film o una serie (messaggio fino a 200
  caratteri, fino a 50 amici, 30 destinatari all'ora; chi non è amico o non
  vede il titolo si salta) e crea la voce `Recommendation` nella cassetta;
  `GET Recommendations` dà i consigli ricevuti ancora validi (escono quelli
  visti dopo il consiglio, quelli che l'utente non vede più, quelli di chi
  non è più amico e quelli di più di 60 giorni); `DELETE
  Recommendations/{itemId}` è "Non mi interessa". I dati stanno in
  `recommendations.json`, accanto a `inbox.json`. All'avvio la riga
  `recommended` si accende una volta sola nella Home dell'admin già salvata
  (`HomeRowsSeen`).
- **Cosa guardano gli amici (dalla 1.9.0):** in `GET Friends` ogni amico
  online fuori da un party può avere `NowPlaying` (film o episodio di una
  sessione WonderFlix; mai se chi guarda non può vedere il titolo o l'amico
  è in un party). `GET Friends/{userId}/NowPlaying` dà la posizione per
  "Guarda insieme" (409 se non vale). Il plugin registra le visioni
  WonderFlix oltre 5 minuti (film o serie, 30 giorni, 100 per utente) in
  `activity.json`; `GET Activity/FriendsWatched` dà la riga "Visti dagli
  amici" (titoli degli amici che chi chiama vede e non ha mai visto, al
  massimo 30). `GET`/`PUT Activity/Settings` `{ShareActivity}` è
  "Mostra agli amici cosa guardo" (acceso di default; spento cancella le
  visioni). Gli amici rileggono a inizio e fine di ogni riproduzione. All'avvio
  la riga `friendsWatched` si accende una volta sola nella Home dell'admin già
  salvata (`HomeRowsSeen`).
- **Match del film (dalla 1.10.0):** le sale stanno in memoria, una per
  utente, al massimo 8 membri. `POST Match` apre una sala; chi l'ha aperta
  invita amici (`POST Match/{roomId}/Invites`, avviso `MatchInvite` e voce
  nella cassetta), gli invitati entrano con `POST Match/{roomId}/Join`
  finché è in attesa. `POST Match/{roomId}/Start` `{Type, Duration, Genre,
  Rating}` (`Rating` dalla 1.10.1: `any`, `good` voto 7 o più, `bad` voto 5
  o meno; assente vale `any`) pesca 30 titoli a caso che nessun membro ha visto o iniziato e che tutti
  possono vedere; `POST Match/{roomId}/Votes` `{ItemId, Yes}` vota in ordine;
  un match è un titolo a cui tutti hanno detto sì, i quasi match arrivano a
  fine pila; `POST Match/{roomId}/More` pesca altri 30 titoli.
  `POST Match/{roomId}/Party` `{GroupId}` dà ai membri l'accesso al party
  privato di chi ha aperto e chiude la sala. Lo stato (`GET Match/{roomId}`
  e l'avviso `MatchUpdated`, al più ogni 250 ms) ha i conteggi, mai i voti
  dei singoli. Un membro senza sessioni WonderFlix per 60 s esce; se esce
  chi ha aperto, o dopo un'ora senza voti, la sala si chiude. I 409 hanno
  `{Reason}`.
- **Funzioni:** `GET Info` annuncia quello che il plugin sa fare; dalla 1.5.0
  ci sono sempre anche `collections` e `avatars`, dalla 1.6.0 anche
  `account`, dalla 1.7.0 anche `home`, dalla 1.8.0 anche `recommendations`, dalla 1.9.0 anche `friendsActivity`, dalla 1.10.0 anche `match`; `upcomingSeries` e `upcomingMovies`
  solo con Sonarr e Radarr configurati. Gli endpoint delle saghe e delle
  immagini sono aperti a ogni utente che ha fatto l'accesso. Quelli di
  `account` dipendono dalla rotta: `Account/Contacts` per ogni utente che ha
  fatto l'accesso (con la password attuale per cambiare i contatti),
  `Account/Recovery` senza accesso, `Account/Admin` solo per gli admin. Quelli
  di `Home` e `Upcoming` sono aperti a ogni utente che ha fatto l'accesso,
  tranne le scritture (`POST Home/Layout`, `POST Upcoming/Test`), solo per gli
  admin. Quelli di `Recommendations` hanno la stessa policy degli amici. Quelli di `Activity` hanno la stessa policy degli amici. Quelli di `Match` hanno la stessa policy degli amici.

## Installazione dal repository

1. Dashboard → Plugin → Repository → **+**: nome a piacere, URL
   `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/jellyfin-plugin-watch-party/manifest.json`.
2. Catalogo → **WonderFlix Watch Party** → Installa.
3. Riavvia Jellyfin.

## Installazione a mano (prove)

1. Dalla root del repository: `bash jellyfin-plugin-watch-party/pack.sh 1.10.0`.
   Crea `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.10.0.0/`
   con la dll e `meta.json`.
2. Copia la cartella dentro `plugins/` della cartella dati di Jellyfin (su
   Ultra.cc via SFTP).
3. Riavvia Jellyfin. In Dashboard → Plugin compare "WonderFlix Watch Party",
   attivo.

Prima di installare dal Catalogo togli la cartella copiata a mano.

## Sviluppo

- Test: `dotnet test jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty.Tests`.
- Versioni di Jellyfin: il plugin è compilato contro Jellyfin 10.11.0 (il
  minimo), i test girano con quella del server (10.11.9). Jellyfin ha tolto
  `IUserManager.Users` in una patch 10.11.x, quindi i membri che sono cambiati
  si cercano a runtime (`Server/UserListing.cs`). Anche
  `IUserManager.ChangePassword` ha cambiato firma (`User` nella 10.11.0,
  `Guid` nella 10.11.9): `Server/PasswordChanging.cs`. Quando si aggiorna il
  server, si alzano i pacchetti `Jellyfin.Controller` e `Jellyfin.Model` del
  progetto di test a quella versione.
- Release: tag `watch-party-plugin-vX.Y.Z` → il workflow
  `watch-party-plugin.yml` pubblica una **pre-release** con lo zip e il suo
  MD5. Mai "latest": l'app legge `releases/latest` per i propri
  aggiornamenti. Poi si aggiunge la versione a `manifest.json`.

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
- **Funzioni:** `GET Info` annuncia quello che il plugin sa fare; dalla 1.5.0
  ci sono sempre anche `collections` e `avatars`, dalla 1.6.0 anche
  `account`, dalla 1.7.0 anche `home`; `upcomingSeries` e `upcomingMovies`
  solo con Sonarr e Radarr configurati. Gli endpoint delle saghe e delle
  immagini sono aperti a ogni utente che ha fatto l'accesso. Quelli di
  `account` dipendono dalla rotta: `Account/Contacts` per ogni utente che ha
  fatto l'accesso (con la password attuale per cambiare i contatti),
  `Account/Recovery` senza accesso, `Account/Admin` solo per gli admin. Quelli
  di `Home` e `Upcoming` sono aperti a ogni utente che ha fatto l'accesso,
  tranne le scritture (`POST Home/Layout`, `POST Upcoming/Test`), solo per gli
  admin.

## Installazione dal repository

1. Dashboard → Plugin → Repository → **+**: nome a piacere, URL
   `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/jellyfin-plugin-watch-party/manifest.json`.
2. Catalogo → **WonderFlix Watch Party** → Installa.
3. Riavvia Jellyfin.

## Installazione a mano (prove)

1. Dalla root del repository: `bash jellyfin-plugin-watch-party/pack.sh 1.7.0`.
   Crea `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.7.0.0/`
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

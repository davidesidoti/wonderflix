# Pubblicare una versione di WonderFlix

L'app controlla gli aggiornamenti su `https://api.github.com/repos/davidesidoti/wonderflix/releases/latest`: vede solo le release **pubblicate**, mai le bozze né le pre-release.

## Una volta sola: i Secrets

Il repository deve essere **pubblico**: l'app legge le release senza token, e con un repository privato GitHub risponde 404 e l'app non si aggiorna mai.

Su GitHub: *Settings → Secrets and variables → Actions → New repository secret*.

| Secret | Valore | Obbligatorio |
|---|---|---|
| `WONDERFLIX_SERVER_URL` | indirizzo https del server Jellyfin | sì |
| `WONDERFLIX_DISCORD_APP_ID` | Application ID dell'app Discord | no (senza, niente Rich Presence) |
| `WONDERFLIX_SUPPORT_URL` | link di "Scrivi all'admin" nell'accesso e nel recupero della password (es. invito Discord) | no |
| `WONDERFLIX_ACCESS_REQUEST_URL` | link del pulsante "Chiedi l'accesso" su Discord (es. `https://discord.com/users/<id>`) | no |

`githubRepo` non serve: la pipeline usa il repository stesso.

Firma del codice (per ora spenta in `release.yml`): `WONDERFLIX_SIGNING_CERT` (certificato `.pfx` in base64) e `WONDERFLIX_SIGNING_PASSWORD`, poi togli `if: ${{ false }}` dai due passaggi di firma.

Prima di accenderla: passare i Secrets via `env:` invece che nello script, usare il percorso completo di `signtool.exe` del Windows Kit, cancellare `cert.pfx` a fine job e firmare anche il disinstallatore (`SignTool=` in `app/installer/wonderflix.iss`).

## Procedura

1. Aggiorna `version:` in `app/pubspec.yaml` (es. `0.1.1`) e fai commit su `main`.
2. Esegui la **checklist dei test manuali** (sotto) su una build locale.
3. Crea il tag e fai push:
   ```bash
   git tag v0.1.1
   git push origin v0.1.1
   ```
   Il tag deve essere esattamente `v` + la versione di `app/pubspec.yaml`, altrimenti la pipeline si ferma.
4. Attendi la fine di **Release** in *Actions*: la pipeline crea una GitHub Release in **bozza** con `WonderFlix-Setup-0.1.1.exe` e il suo `.sha256`. Se la rilanci sullo stesso tag (*Re-run jobs*), la release esiste già: la pipeline sostituisce solo i due file (`gh release upload --clobber`), note e stato restano.
5. Scrivi le note di rilascio nella bozza (markdown: l'app le mostra così).
6. **Solo se l'aggiornamento è obbligatorio** (compatibilità col server, bug gravi): aggiungi alle note la riga
   ```
   <!-- wonderflix:min-version=0.1.1 -->
   ```
   dove `0.1.1` è la versione minima ancora accettata (di solito quella che stai pubblicando). La riga non compare nelle note mostrate nell'app.
7. Pubblica la bozza. Da questo momento le app installate la trovano (all'avvio o entro 6 ore).
8. Per le prove interne pubblica come **pre-release**: le app la ignorano. Ma **qualsiasi tag** aggiorna anche il sito per tutti gli utenti (il job `web` non guarda se è una bozza o una pre-release): un tag di prova pubblica il sito.
9. **Ricorda:** il marcatore si legge **solo nell'ultima release pubblicata**. Se una release successiva deve mantenere il blocco, riporta la stessa riga `min-version` (o una più alta).

## Come si aggiorna l'app

- Controllo all'avvio e ogni 6 ore (solo nelle build release).
- Se c'è una versione più nuova: scarica l'installer in `%TEMP%\WonderFlix`, verifica lo SHA-256, mostra "Aggiornamento pronto" con le note. *Riavvia ora* installa in silenzio e riapre l'app.
- Obbligatorio: schermata bloccante con avanzamento e *Aggiorna ora*.
- Mai durante la riproduzione: la barra o la schermata compaiono alla fine del video.
- Errori (rete, hash non valido): solo nel log (`%LocalAppData%\WonderFlix\logs`), nuovo tentativo al controllo successivo.

## Installazione

- Per utente, senza permessi di amministratore: `%LocalAppData%\Programs\WonderFlix`.
- Collegamenti su Start e Desktop; disinstallazione da *Impostazioni → App*.
- La disinstallazione toglie il programma. Log, preferenze e credenziali restano (log in `%LocalAppData%\WonderFlix`, profili e token in `%AppData%\it.wonderflix\WonderFlix\flutter_secure_storage.dat`, un file cifrato con DPAPI).

## Checklist dei test manuali

Prima di ogni release, su un utente di prova:

- [ ] MKV con sottotitoli ASS interni, PGS interni e SRT esterni: resa corretta e sincronizzata.
- [ ] Ripresa dal minutaggio; stato "visto" sincronizzato con jellyfin-web.
- [ ] Ripiego sulla transcodifica (forzato: `--dart-define=wfBreakDirectPlay=true`).
- [ ] Salta intro, prossimo episodio, trickplay.
- [ ] Login con password e con Quick Connect; sessione scaduta.
- [ ] Profili: aggiornamento dalla 0.10 senza rifare l'accesso (la sessione diventa il primo profilo, con il suo nome nel menu).
- [ ] "Chi guarda?" al riavvio con più profili, nella lingua dell'ultimo usato; un profilo si apre con un clic o con Invio.
- [ ] Aggiungi profilo con password e con Quick Connect; "Annulla" torna a "Chi guarda?"; con 5 profili "Aggiungi profilo" non c'è più.
- [ ] Cambia profilo dal menu dell'avatar e dalle Impostazioni; lingua, sottotitoli e Discord restano quelli di ogni profilo.
- [ ] Cambio di profilo in un watch party: conferma, uscita dal gruppo, "Chi guarda?".
- [ ] Profilo scaduto: attenuato in "Chi guarda?", "Accedi di nuovo" con il nome già scritto.
- [ ] Gestisci profili → Rimuovi; "Esci" dall'ultimo profilo porta all'accesso.
- [ ] Server giù aprendo un profilo da "Chi guarda?": "Riprova" riapre quel profilo.
- [ ] Immagine del profilo da Impostazioni ("Cambia immagine") e da "Gestisci profili" (matita, spenta su un profilo scaduto): un avatar della galleria, un file dal PC con il ritaglio (rotella e cursore; una foto girata del telefono si vede dritta) e "Rimuovi immagine". L'immagine cambia nel menu, in Impostazioni, in "Chi guarda?" e in jellyfin-web.
- [ ] Dal PC: un file oltre 20 MB dà "Immagine troppo grande", un file che non è un'immagine "Immagine non valida".
- [ ] Le immagini degli altri (con il plugin 1.5.0): amici e richieste, inviti, party (fila, menu, chat), richiesta d'amicizia, sessioni dell'admin; chi non ha un'immagine resta con l'iniziale.
- [ ] Con un plugin senza la funzione `avatars` (1.4.0): solo iniziali per gli altri, nessun errore.
- [ ] Impostazioni → Account (in cima): "Cambia password" con la password attuale sbagliata ("Password attuale sbagliata") e giusta (avviso; questo PC resta dentro, jellyfin-web deve rientrare).
- [ ] Contatti per il recupero (plugin 1.6.0): collega Discord (password sbagliata, nome sbagliato, codice sbagliato, codice giusto) ed email; "Rimanda il codice" dopo 60 s; "Scollega" con la password.
- [ ] "Password dimenticata?" nell'accesso con un account di prova non admin con un contatto: il codice arriva, la password nuova fa entrare, arriva l'avviso "password cambiata"; un nome inesistente ha la stessa risposta.
- [ ] Promemoria "Proteggi il tuo account" nella cassetta per un utente senza contatti; il clic apre Impostazioni.
- [ ] Amministrazione → Utenti (plugin 1.6.0): righe con "Admin"/"Disattivato" e le icone dei contatti; sulla propria riga niente "Imposta password"; "Imposta password" a un account di prova (le sue sessioni si chiudono), "Invia codice di recupero" (arriva, e con "Ho già un codice" fa cambiare la password), "Scollega contatti".
- [ ] Amministrazione → WonderFlix → "Recupero password": Discord ed email, utenti con un contatto, promemoria, "Invia prova a me" con l'esito per canale.
- [ ] Home (plugin 1.7.0): Serie in arrivo e Film in arrivo con i clic (scheda della serie o pagina Seerr); Perché hai visto X, Le mie richieste, Continua la saga.
- [ ] Impostazioni → Home: sposta (trascinando, con le frecce, con Alt+↑/↓) e nascondi righe, la Home cambia; "Ripristina la Home predefinita"; il link "Personalizza la Home" in fondo alla Home.
- [ ] Amministrazione → WonderFlix → "Home per tutti": spegni e riaccendi una riga, cambia l'ordine, "Salva"; "Ripristina" con la conferma. "Sonarr e Radarr": "Prova collegamento".
- [ ] "Cosa guardo stasera?" (il dado sul carosello): filtri, "Un altro", "Riproduci" e "Dettagli"; i filtri restano riaprendo.
- [ ] "Match del film" (con due istanze): sala, inviti, voti (gesto, ✗/✓, ←/→), "È un match!", fine pila e "Altri 30 titoli", avvio del party e ingresso dell'altro membro.
- [ ] "Voti degli amici" (plugin 1.11.0, con due istanze): nel post-play del party il voto e "Salta"; la scoperta per tutti votato, per tempo scaduto (2 min) e con il pulsante; il conto di 15 s e la pillola "Voti del party" (apre il pannello a lato); l'uscita dal party durante la votazione; il voto dalla scheda di film e serie (per stagione) con la riga degli amici; la cancellazione di un commento da Amministrazione → WonderFlix → "Commenti degli utenti".
- [ ] Segnalazioni e sottotitoli (plugin 1.12.0, un admin e due utenti di prova, uno con la spunta sottotitoli): (1) un utente segnala un episodio, gli admin ricevono la notifica e l'utente con la spunta no; (2) l'admin apre la notifica, usa "Cerca sottotitoli", scarica un sottotitolo italiano e la traccia compare, poi "Sistemato" con nota e la notifica arriva all'utente; (3) l'utente con la spunta cerca e scarica dal player senza fermarlo e non vede le voci admin; (5) "Non sistemabile" con nota: arriva la notifica giusta. Da guardare anche: la transcodifica non si disturba quando si scarica un sottotitolo a metà video.
- [ ] Strumenti admin dei metadati (app 0.19.0, un admin e un utente non admin): (4) l'admin reidentifica un film (con un campo bloccato a mano: la casella "Sblocca i campi modificati a mano"), modifica un titolo e aggiorna i metadati, e verifica che il titolo bloccato resti; cambia locandina e sfondo (lo sfondo nuovo diventa il primo; un file oltre 10 MB viene rifiutato). Il non admin non vede le voci. Da guardare: la griglia delle immagini nella finestra vera, e che lo sfondo nuovo vada davvero in prima posizione (se il primo sfondo non è un file locale resta in fondo).
- [ ] Calendario delle uscite (app 0.20.0, plugin 1.13.0): sul server vero il mese di oggi e quello dopo, con le serie di Sonarr e i film di Radarr; un film già scaricato segnato in verde; clic su una serie della libreria e su un film da richiedere; frecce e Invio sulla griglia, "+n" e l'elenco del giorno. Pagina Richieste: un film approvato non ancora uscito in digitale ("In attesa dell'uscita" con le date) e una serie con il prossimo episodio. Con un plugin senza la funzione `calendar`: niente voce "Calendario" e nessun errore.
- [ ] Amministrazione → Download (app 0.23.0, plugin 1.14.0, un admin e un utente non admin): la scheda si vede solo all'admin e solo con il plugin 1.14.0 (con un plugin precedente non c'è). Una ricerca di un film mostra la scelta di WonderFlix evidenziata con il perché e gli scarti in grigio con il motivo. "Scarica" chiede conferma per una release con punteggio non migliore. "Cambia" toglie il download precedente da qBittorrent e scarica la nuova. "Va bene così" toglie il titolo da "Da ripassare". Layout stretto (finestra stretta o sito dal telefono): la scheda e la ricerca si leggono senza scorrere in orizzontale.
- [ ] Download, migliori episodi (app 0.24.0, plugin 1.15.0, un admin): la ricerca di una stagione senza un pack conveniente mostra in cima il riquadro "Migliori episodi", un singolo per episodio mancante (o "nessun file valido"), e con un pack scelto il riquadro non c'è. "Scarica tutti" parte una volta sola, mostra "Scarico 3/N", spegne i pulsanti, chiede conferma una volta se qualche episodio non verrebbe importato; alla fine lo SnackBar dice quanti sono partiti, e la pagina resta aperta se qualcuno è fallito. Layout stretto: il riquadro si legge senza scorrere in orizzontale.
- [ ] Sito web nel browser: login; un titolo HEVC in copia (TranscodeReasons solo audio); sottotitoli PGS, ASS e SRT; cambio traccia audio; Esc esce dal tutto schermo; chiudere la scheda ferma la sessione.
- [ ] Sito dal telefono (iPhone, sul sito di prova; vedi "Sito di prova"): barra in basso e "Altro" con tutte le voci; anteprima di una card tenendo premuto; un episodio con i controlli al tocco (tocco mostra/nasconde, doppio tocco ai lati salta di 10 s); salti e tracce; ricerca di un sottotitolo (e scaricamento); una richiesta; ogni scheda dell'Admin; Amici e Notifiche come pagina; un watch party con il sito sul PC; la tastiera sui campi (login, ricerca, chat: il campo resta visibile); rotazione verticale/orizzontale a metà video; tacca e barra home non coprono barre e controlli. Il gesto indietro del telefono su una finestra aperta come pagina (per esempio i sottotitoli) oggi chiude anche la pagina sotto: limite noto, non un errore nuovo.
- [ ] Aggiornamento da una versione precedente; aggiornamento obbligatorio.
- [ ] Discord Rich Presence attiva e disattivata.
- [ ] Pannello media di Windows con il nome "WonderFlix" (app installata).
- [ ] "Copia diagnostica" e cartella dei log.

## Sito web

Lo stesso tag `vX.Y.Z` fa partire anche il job `web` di **Release**, dopo quello Windows (`needs: release`: se Windows fallisce il sito non esce; il tag lo controlla già quel job): compila il sito (`flutter build web --wasm`, base `/wonderflix/`) con la stessa configurazione dei Secrets e lo copia con `rsync` in `~/wonderflix-web` sul server. Prima i file, poi `index.html`; i file che non esistono più vengono tolti. Il sito è su `https://hashvps.proton.usbx.me/wonderflix/` e non ha bozza: va online appena il job finisce, anche se la release di Windows resta in bozza.

**Secrets del sito** (oltre a quelli sopra):

| Secret | Valore |
|---|---|
| `WONDERFLIX_DEPLOY_SSH_KEY` | chiave privata SSH (senza passphrase) usata solo per il deploy |
| `WONDERFLIX_DEPLOY_KNOWN_HOSTS` | riga di `known_hosts` del server (`ssh-keyscan -t ed25519 46.232.210.229`) |

La chiave pubblica sta in `~/.ssh/authorized_keys` dell'utente `hashvps` sul server, vincolata a `command="/usr/bin/rrsync /home/hashvps/wonderflix-web"` (con `restrict`): può solo copiare file in quella cartella. Per rigenerarla: `ssh-keygen -t ed25519 -N "" -f deploy_key`, nella riga di `authorized_keys` sostituisci solo la parte `ssh-ed25519 AAAA…` con il contenuto di `deploy_key.pub`, lasciando il prefisso `restrict,command="/usr/bin/rrsync /home/hashvps/wonderflix-web"`, aggiorna il Secret con la privata (`gh secret set WONDERFLIX_DEPLOY_SSH_KEY < deploy_key`) e cancella i due file locali.

**Rimettere una versione vecchia:** in *Actions* apri il run di **Release** del tag precedente e premi *Re-run* sul solo job `web`. Ricompila e ricopia quella versione.

**nginx:** la conf del sito (file statici, `.wasm` e `.mjs` con il tipo giusto) è in `app/deploy/wonderflix.conf`; va in `~/.apps/nginx/proxy.d/` sul server, poi `app-nginx restart`.

## Sito di prova

Ogni tag pubblica il sito per tutti, quindi la build di un ramo si prova su un percorso separato dello stesso server: `https://hashvps.proton.usbx.me/wonderflix-prova/` (file in `~/wonderflix-web-prova/`). È la stessa origine del sito vero, quindi il login di Jellyfin funziona. Per lo stesso motivo condivide con il sito pubblicato anche il `localStorage` (login e impostazioni): entrare o cambiare un'impostazione qui vale anche là.

1. Build (da `app/`), con la base del percorso di prova:
   ```bash
   flutter build web --wasm --base-href /wonderflix-prova/ --dart-define-from-file=config/wonderflix.json
   ```
2. Copia (prima tutto tranne `index.html`, poi `index.html`; i file che non esistono più vengono tolti):
   ```bash
   rsync -a --delete --exclude index.html build/web/ ultra:~/wonderflix-web-prova/
   rsync -a build/web/index.html ultra:~/wonderflix-web-prova/
   ```
   Da Git Bash su Windows: la build va lanciata con `MSYS_NO_PATHCONV=1`, altrimenti `/wonderflix-prova/` diventa un percorso di Windows. E lì `rsync` non c'è: si copia con `tar` in una cartella nuova che poi prende il posto della vecchia:
   ```bash
   tar czf - -C build/web . | ssh ultra 'rm -rf ~/wonderflix-web-prova.new && mkdir ~/wonderflix-web-prova.new && tar xzf - -C ~/wonderflix-web-prova.new && rm -rf ~/wonderflix-web-prova && mv ~/wonderflix-web-prova.new ~/wonderflix-web-prova'
   ```
3. **Solo la prima volta:** copia `app/deploy/wonderflix-prova.conf` in `~/.apps/nginx/proxy.d/wonderflix-prova.conf` sul server e `app-nginx restart`. Le copie successive non toccano nginx.

La conf ha gli stessi header del sito vero (COOP/COEP, `no-cache`, `.wasm`, `.mjs`, niente log). Il sito di prova non è collegato ai tag: va aggiornato a mano.

## Plugin "WonderFlix Watch Party"

Il plugin del server (cartella `plugin/`, spec E) ha versioni e release sue, separate dall'app.

1. Aggiorna `<Version>` in `plugin/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj` (es. `1.0.1`) e fai commit su `main`. Il workflow compila con la versione del tag: tienila uguale a quella del csproj.
   I test del plugin girano con le dll della versione di Jellyfin del server
   (oggi 10.11.9, nel progetto di test), il plugin si compila contro la
   10.11.0: Jellyfin cambia API anche nelle patch. Quando il server si
   aggiorna, alza `Jellyfin.Controller`/`Jellyfin.Model` nel progetto di test
   e rilancia i test. Amicizie e richieste stanno in
   `plugins/configurations/WonderFlixWatchParty/friends.json`.
   La cassetta delle notifiche sta in
   `plugins/configurations/WonderFlixWatchParty/inbox.json` e l'impostazione
   dei nuovi titoli in
   `plugins/configurations/Jellyfin.Plugin.WonderFlixWatchParty.xml`. I
   contatti per il recupero della password stanno in
   `plugins/configurations/WonderFlixWatchParty/contacts.json`, le sue
   impostazioni (bot Discord, SMTP, promemoria) nello stesso XML: un
   aggiornamento del plugin non le tocca.
2. Prova a mano sul server (README del plugin: `pack.sh` e copia via SFTP nei `plugins/` di Jellyfin). Finita la prova, la cartella copiata va tolta prima del passo 6.
3. Crea il tag e fai push:
   ```bash
   git tag watch-party-plugin-v1.0.1
   git push origin watch-party-plugin-v1.0.1
   ```
4. Il workflow **Watch party plugin** pubblica una **pre-release** con `wonderflix-watch-party_1.0.1.zip` e `.zip.md5`. È sempre pre-release e mai "latest": l'app legge `releases/latest` per i propri aggiornamenti.
5. Aggiungi la versione in cima a `versions` in `plugin/manifest.json` e fai push su `main`:
   ```json
   {
     "version": "1.0.1.0",
     "changelog": "…",
     "targetAbi": "10.11.0.0",
     "sourceUrl": "https://github.com/davidesidoti/wonderflix/releases/download/watch-party-plugin-v1.0.1/wonderflix-watch-party_1.0.1.zip",
     "checksum": "<contenuto del file .md5>",
     "timestamp": "2026-10-02T12:00:00Z"
   }
   ```
6. Sul server: prima togli da `plugins/` un'eventuale cartella copiata a mano (passo 2), poi Dashboard → Plugin → Catalogo → aggiorna (o installa) **WonderFlix Watch Party** e riavvia Jellyfin (su Ultra.cc: `app-jellyfin restart`).

Il repository dei plugin si aggiunge una volta sola: Dashboard → Plugin → Repository → **+**, URL `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/plugin/manifest.json`.

**Jellyfin 12:** serve una build nuova (net10.0, `targetAbi` `12.0.0.0`) prima di aggiornare il server.

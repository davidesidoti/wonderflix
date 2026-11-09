# Migrazione del seedbox (novembre 2026)

Ultra.cc sposta il servizio `hashvps` da **proton** (`hashvps.proton.usbx.me`, SSH `46.232.210.229`) a un server nuovo. Iniziata il 2026-11-07, durata stimata 36 ore. Quando finisce, le app sul vecchio server si fermano: da lì WonderFlix è giù finché non si fanno i passi qui sotto.

Ultra.cc copia contenuti, app supportate, impostazioni e torrent, ma non riscrive gli indirizzi dentro le configurazioni. Non copia le app "custom" (vedi in fondo).

## Com'è andata (2026-11-09)

Consegnato alle 18:45, dopo circa 50 ore. Ultra.cc ha copiato home, dati delle app e cron, e ha già aggiornato Seerr, i client qBittorrent e le applicazioni di Prowlarr. Ma:
- **ha cambiato tutte le porte**: Jellyfin 20752, Sonarr 20776, Radarr 20777, Prowlarr 20774, qBittorrent 20791, Seerr 45761, il nostro nginx **20790** (la 17540 sul server nuovo è di un altro utente). Lo script legge le porte da `proxy.d` e da `sites-available/default`;
- ha rigenerato `proxy.d`: `wonderflix.conf` e `wonderflix-prova.conf` (copiati da `app/deploy/`) e i timeout lunghi di `jellyfin.conf`/`sonarr.conf`/`radarr.conf` sono stati rimessi a mano (copie `*.bak-migrazione`);
- non ha copiato `~/.ssh/authorized_keys` (la chiave del PC l'ha aggiunta l'utente con la password, la chiave di deploy è stata copiata da proton) né i servizi in `~/.config/systemd/user/`: `jfa-go`, `identitycrisis` e `unit3dprep` rimessi a mano (con i loro `proxy.d`) e fermati su proton. Gli altri servizi custom no.
- `identitycrisis`: il redirect OAuth di Discord nel `.env` ora punta ad aiko, va cambiato anche nel portale sviluppatori di Discord.

## Durante la migrazione

- Niente da cambiare: il vecchio server funziona finché non viene spento.
- Consiglio della mail: meno si scarica, più corta è la copia finale. Se vuoi accorciare il fermo, verso la fine metti in pausa i torrent in qBittorrent (non i seed).
- Non fare deploy del plugin né tag `v*` in questi giorni: andrebbero sul server vecchio.

## Quando arriva il servizio nuovo

Dalla UCP servono due cose: il **nome nuovo** (`hashvps.<server>.usbx.me`) e l'**IP SSH nuovo**. Sotto li chiamo `NUOVO_HOST` e `NUOVO_IP`. Dalla mail "Access Info" del 2026-11-07 (piano Bronze): `NUOVO_HOST` = `hashvps.aiko.usbx.me`, `NUOVO_IP` = `149.40.59.140`.

### 1. Accesso SSH dal PC

- `~/.ssh/config`, blocco `Host ultra`: `HostName NUOVO_IP`.
- Prima connessione: `ssh ultra` chiede di accettare la nuova impronta (o togli quella vecchia con `ssh-keygen -R 46.232.210.229`).

### 2. Server: app accese e porte

- `ssh ultra 'uptime; ls ~/.apps'`. Se un'app è giù: `app-<nome> start` (jellyfin, sonarr, radarr, prowlarr, seerr, qbittorrent).
- Le porte dovrebbero restare le stesse; controlla con `ss -ltnp` che ci siano 17502 (Jellyfin), 17526 (Sonarr), 17527 (Radarr), 17524 (Prowlarr), 17540 (nginx), 17541 (qBittorrent), 42511 (Seerr). Se una cambia, va corretta a mano in `CLAUDE.md` e nella config del plugin (`SonarrUrl`/`RadarrUrl` usano la 17540).
- `curl -s 127.0.0.1:17502/jellyfin/health` deve dire `Healthy` (l'avvio può durare fino a 25 min).

### 3. Server: indirizzi nelle configurazioni

Lo script [`aggiorna_indirizzi.py`](aggiorna_indirizzi.py) cambia `hashvps.proton.usbx.me`, `hashvps.vapor.usbx.me` (residuo di una migrazione vecchia: la notifica "Jellyfin" di Sonarr e Radarr puntava lì fino al 2026-11-07, quando è stata portata su proton) e `46.232.210.229` in:

- config del plugin WonderFlix: `SeerrUrl`, `SonarrUrl`, `RadarrUrl`, `SpaceQbitUrl`;
- Seerr `settings.json`: collegamento a Jellyfin, Sonarr, Radarr e il webhook verso il plugin;
- Sonarr e Radarr: client qBittorrent e notifica Jellyfin;
- Prowlarr: le due applicazioni (Sonarr, Radarr) e il client qBittorrent.

Alla fine controlla anche: IP a cui si lega qBittorrent, cron della quota, `rrsync`, chiave di deploy, cartelle del sito. Provato a secco su proton il 2026-11-07.

Da Git Bash, nella radice del repo:

```bash
ssh ultra 'python3 -I - --new-host NUOVO_HOST --new-ip NUOVO_IP' < docs/migrazione/aggiorna_indirizzi.py
```

Se l'elenco torna, spegni Jellyfin e Seerr (i loro file si riscrivono solo da spenti; prima controlla che nessuno stia guardando, come da `CLAUDE.md`) e applica:

```bash
ssh ultra 'app-jellyfin stop; app-seerr stop'
```

```bash
ssh ultra 'python3 -I - --new-host NUOVO_HOST --new-ip NUOVO_IP --apply' < docs/migrazione/aggiorna_indirizzi.py
```

```bash
ssh ultra 'app-seerr start; app-jellyfin start'
```

Rilanciato senza `--apply`, non deve più trovare niente da cambiare. Copie dei file vecchi: `*.bak-migrazione`.

Se i controlli finali dicono:
- **qBittorrent si lega a un IP che non è della macchina**: con qBittorrent spento, cambia `Session\InterfaceAddress` e `Connection\InterfaceAddress` in `~/.config/qBittorrent/qBittorrent.conf` con l'IP giusto (chiedi a Ultra.cc quale, di solito lo impostano loro), e aggiorna l'IP di `aria2c --interface` in `CLAUDE.md`.
- **cron della quota manca**: `crontab -e` e rimetti
  `*/10 * * * * quota -w > /home/hashvps/.config/wonderflix-quota.tmp && mv /home/hashvps/.config/wonderflix-quota.tmp /home/hashvps/.config/wonderflix-quota.txt`
- **rrsync o la chiave di deploy mancano**: vedi "Secrets del sito" in `docs/RELEASING.md`.

### 4. Prove sul server nuovo

- Log di Jellyfin: `WonderFlix Watch Party "X" avviato`.
- Sonarr, Radarr, Prowlarr: Impostazioni → Download Clients / Connect / Apps, "Test" su ognuno.
- Seerr: Impostazioni → Jellyfin e Servizi, "Test"; poi una richiesta di prova deve arrivare nelle Richieste dell'app.
- App (dal PC, con la build del passo 6): login, home, un episodio, Download, Spazio → scansione.

### 5. GitHub

```bash
gh secret set WONDERFLIX_SERVER_URL --body "https://NUOVO_HOST/jellyfin"
```

```bash
ssh-keyscan -t ed25519 NUOVO_IP | gh secret set WONDERFLIX_DEPLOY_KNOWN_HOSTS
```

L'impronta ed25519 di `149.40.59.140` presa il 2026-11-09 (SSH già acceso, login non ancora accettato) è `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG/3imBwJx…`: alla consegna il valore di `ssh-keyscan` deve iniziare così.

### 6. Repo

Già pronto nel ramo `migrazione-aiko` (preparato il 2026-11-09, da mergiare dopo la prova): `release.yml` (rsync su `149.40.59.140`), `docs/RELEASING.md`, `docs/INSTALLAZIONE-TV.md`, `docs/IDEE.md`, il commento di `tv_update_tile.dart`, versione 0.35.2 con la riga di checklist.

Da fare alla consegna:
- `app/config/wonderflix.json` (locale, non versionato, anche nel checkout principale): `serverUrl`. Nel worktree è ancora quello vecchio, così la build di prova punta al server giusto solo dopo il cambio.
- `CLAUDE.md` del checkout principale (le righe con gli IP sono modifiche locali non committate): IP in `SonarrUrl`/`RadarrUrl` e `aria2c --interface`; eventuali porte cambiate.
- Memoria di Claude (`ultra-ssh`, `wonderflix-progress`).
- **Codice di Downloader**: il vecchio `3453481` (aftv.news) porta a `hashvps.proton.usbx.me/wonderflix/tv.apk` e non si può modificare. Il codice nuovo `8025402` (http://aftv.news/8025402, creato il 2026-11-09) porta a `https://hashvps.aiko.usbx.me/wonderflix/tv.apk`. È già nel ramo: `tvDownloaderCode` (`tv_update_tile.dart`), `update_gate_test.dart`, `docs/INSTALLAZIONE-TV.md`, `note-rilascio-0.35.2.md`. Le TV con la 0.35.1 mostrano ancora il codice vecchio: lì serve scrivere l'indirizzo in Downloader.

### 7. Nuova versione dell'app (obbligatoria)

L'indirizzo del server è dentro l'exe e l'APK: le app installate continuano a cercare `hashvps.proton.usbx.me` e smettono di funzionare quando proton si spegne. Il controllo aggiornamenti passa da GitHub e c'è anche nella schermata di login, quindi basta una release:

- 0.35.2 è già nel ramo; dopo merge e CI verde, tag `v0.35.2`;
- note pronte in [`note-rilascio-0.35.2.md`](note-rilascio-0.35.2.md), con `<!-- wonderflix:min-version=0.35.2 -->`: chi apre la vecchia app vede subito "Aggiorna ora";
- il job `web` pubblica il sito (e `tv.apk`) sul server nuovo.

### 8. Cosa cambia per gli utenti del sito

L'indirizzo nuovo è un'altra origine:
- sito: `https://NUOVO_HOST/wonderflix/` (va comunicato, per esempio su Discord);
- login di nuovo (il `localStorage` era legato al vecchio indirizzo);
- iPhone: togliere dalla Home la vecchia icona e riaggiungere quella nuova;
- notifiche push: vanno riattivate dal sito nuovo. Le iscrizioni vecchie il plugin le toglie da solo quando il servizio push risponde 404/410.

## Non WonderFlix: app custom sul vecchio server

La mail dice che le app costruite a mano vanno ricostruite. Servizi utente (`~/.config/systemd/user/`) che non sono app di Ultra.cc: `identitycrisis`, `instashopping`, `jfa-go`, `unit3dprep`, `unit3dprep-web`, `unit3dwebup`, `redis` (`qui` e `filebrowser` sono anche in `~/.apps`, quindi dovrebbero essere app supportate; `qbittorrent` gira da `~/bin/qbittorrent-nox`). Dopo la migrazione: `systemctl --user status <nome>` per ognuno.

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

Prima di accenderla: passare i Secrets via `env:` invece che nello script, usare il percorso completo di `signtool.exe` del Windows Kit, cancellare `cert.pfx` a fine job e firmare anche il disinstallatore (`SignTool=` in `installer/wonderflix.iss`).

## Procedura

1. Aggiorna `version:` in `pubspec.yaml` (es. `0.1.1`) e fai commit su `main`.
2. Esegui la **checklist dei test manuali** (sotto) su una build locale.
3. Crea il tag e fai push:
   ```bash
   git tag v0.1.1
   git push origin v0.1.1
   ```
   Il tag deve essere esattamente `v` + la versione di `pubspec.yaml`, altrimenti la pipeline si ferma.
4. Attendi la fine di **Release** in *Actions*: la pipeline crea una GitHub Release in **bozza** con `WonderFlix-Setup-0.1.1.exe` e il suo `.sha256`. Se la rilanci sullo stesso tag (*Re-run jobs*), la release esiste già: la pipeline sostituisce solo i due file (`gh release upload --clobber`), note e stato restano.
5. Scrivi le note di rilascio nella bozza (markdown: l'app le mostra così).
6. **Solo se l'aggiornamento è obbligatorio** (compatibilità col server, bug gravi): aggiungi alle note la riga
   ```
   <!-- wonderflix:min-version=0.1.1 -->
   ```
   dove `0.1.1` è la versione minima ancora accettata (di solito quella che stai pubblicando). La riga non compare nelle note mostrate nell'app.
7. Pubblica la bozza. Da questo momento le app installate la trovano (all'avvio o entro 6 ore).
8. Per le prove interne pubblica come **pre-release**: le app la ignorano.
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
- [ ] Aggiornamento da una versione precedente; aggiornamento obbligatorio.
- [ ] Discord Rich Presence attiva e disattivata.
- [ ] Pannello media di Windows con il nome "WonderFlix" (app installata).
- [ ] "Copia diagnostica" e cartella dei log.

## Plugin "WonderFlix Watch Party"

Il plugin del server (cartella `jellyfin-plugin-watch-party/`, spec E) ha versioni e release sue, separate dall'app.

1. Aggiorna `<Version>` in `jellyfin-plugin-watch-party/Jellyfin.Plugin.WonderFlixWatchParty/Jellyfin.Plugin.WonderFlixWatchParty.csproj` (es. `1.0.1`) e fai commit su `main`. Il workflow compila con la versione del tag: tienila uguale a quella del csproj.
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
5. Aggiungi la versione in cima a `versions` in `jellyfin-plugin-watch-party/manifest.json` e fai push su `main`:
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

Il repository dei plugin si aggiunge una volta sola: Dashboard → Plugin → Repository → **+**, URL `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/jellyfin-plugin-watch-party/manifest.json`.

**Jellyfin 12:** serve una build nuova (net10.0, `targetAbi` `12.0.0.0`) prima di aggiornare il server.

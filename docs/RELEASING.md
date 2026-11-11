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

**APK della TV:** `WONDERFLIX_ANDROID_KEYSTORE` (il `.jks` in base64) e `WONDERFLIX_ANDROID_KEYSTORE_PASSWORD` (obbligatori: senza, il job `android` fallisce e non esce mai un APK firmato con la chiave di debug). Li crea una volta sola `bash app/android/create_release_key.sh` dalla checkout principale: genera `app/android/wonderflix-release.jks` e `app/android/key.properties` (entrambi gitignored), carica i due Secrets con `gh` e non stampa mai la password. Salva i due file nel gestore di password: con una chiave nuova Android rifiuta l'aggiornamento e ogni TV va disinstallata e reinstallata.

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
4. Attendi la fine di **Release** in *Actions*: la pipeline crea una GitHub Release in **bozza** con `WonderFlix-Setup-0.1.1.exe` e il suo `.sha256`; poi il job `android` aggiunge `WonderFlix-TV-0.1.1.apk` (armeabi-v7a + arm64-v8a, firmato con la chiave di rilascio) e il suo `.sha256`. Se la rilanci sullo stesso tag (*Re-run jobs*), la release esiste già: la pipeline sostituisce solo i file (`gh release upload --clobber`), note e stato restano. Se `android` fallisce, la bozza resta senza APK: non pubblicarla finché il job non è verde (le TV non vedrebbero l'aggiornamento), e il sito non esce.
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
- [ ] Quick Connect (app 0.34.0): codice generato sulla TV confermato da Impostazioni → Account su Windows/web; codice sbagliato; Quick Connect spento.
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
- [ ] Amministrazione → Spazio (app 0.25.0, plugin 1.16.0, un admin): quota e divisione; Cancellare con i segnali e la scheda del titolo (Tienilo con la rotellina, Elimina con conferma e passi dal vivo); Alleggerisci con la barra del download fino alla sparizione della riga; Pulizia nei suoi gruppi; selezione in blocco con "Tieni selezionati" ed "Elimina selezionati" (panoramica e passi di tutti). Con un plugin senza la funzione `space` la scheda non c'è.
- [ ] Notifiche push (app 0.26.0, plugin 1.17.0): (1) iPhone con la web app dalla Home (sito di prova): attiva in Impostazioni → Notifiche, push con app chiusa e telefono bloccato, il tocco apre la schermata giusta, uscendo dall'account le push si fermano; (2) Chrome/Edge sul PC con la scheda chiusa: le stesse prove; (3) app Windows aperta e ridotta a icona: notifica e clic; la notifica deve comparire anche nell'app installata con l'installer e avviata dal collegamento del menu Start, e il pannello media (SMTC) mostra ancora WonderFlix; (4) preferenze: un tipo spento non arriva; (5) un evento admin per tipo, provocato a mano dove si può; (6) webhook di Seerr con i tre tipi nuovi spuntati.
- [ ] Download, "Serve te" (app 0.27.0, plugin 1.18.0, un admin): ogni riga "Serve te" ha la frase con i numeri e i suoi pulsanti (il consigliato pieno). "Scarica il migliore intanto" su "solo file con punteggio basso" e su "nessun file valido" con file troppo piccoli; "Va bene, aspetto" (riga in attesa "senza avvisi", la notifica sparisce); "Importa comunque" e "Scarta e cerca un altro" su un import bloccato, con il messaggio di Sonarr/Radarr. In download: barra con percentuale e tempo stimato; un torrent fermo sui metadati mostra da quanto e "Scarta e cerca un altro" (dopo 6 ore si sostituisce da solo). "Cerca ora": "Ricerca avviata", in coda e ricerca in corso con la barra animata, poi l'esito. Da ripassare: "Cerca un upgrade" solo sui titoli monitorati, il titolo passa in attesa e cerca. Con il plugin 1.17.0: i pulsanti di prima, nessun errore.
- [ ] Ricerca in background (app 0.28.0, plugin 1.19.0, un admin, dal sito di prova su iPhone e dall'app Windows): la ricerca di una stagione anime (minuti su Sonarr) mostra barra, "Ricerca su Sonarr in corso · m:ss" e la riga di aiuto, poi i risultati con i "Migliori episodi" pieni; chiudendo la pagina a metà e riaprendo la ricerca è ancora in corso o i risultati sono pronti; "Ricerca di nuovo" ne fa una nuova; senza rete "Connessione persa, riprovo…" e dopo tre errori "Riprova". Con il plugin 1.18.0: la ricerca di prima, nessun errore. Immagini su iPhone: le locandine di Download, Spazio, Calendario e delle righe "in arrivo" si vedono anche scorrendo una lista lunga; i loghi trasparenti restano in basso a sinistra.
- [ ] Ricerca su MIRCrew (app 0.29.0, plugin 1.20.0, un admin): una ricerca senza risultati validi (o con solo scarti) mostra "Cerca su MIRCrew", che apre la ricerca di MIRCrew nel browser col titolo (serie senza stagione ed episodio, film senza anno); il pulsante c'è anche sulle righe "Serve te" "Nessuna release trovata" e "Sotto il punteggio minimo". Un magnet aggiunto a mano in qUI con la categoria di Sonarr/Radarr compare in download e la voce si chiude all'import. Campo "External search link" vuoto nella pagina del plugin: nessun pulsante. Con il plugin 1.19.0: nessun pulsante, nessun errore.
- [ ] Download senza titolo (un admin, con un torrent nella categoria di Sonarr dal nome che Sonarr non abbina): dopo l'import fallito compare in "Senza titolo" sotto "Serve te", con nome, servizio, peso e messaggio; non conta in "Serve te" e non manda notifiche. "Rimuovi" chiede conferma: "Annulla" non tocca niente, confermando torrent e file spariscono da qBittorrent e la riga esce. Un import rifiutato di un titolo in libreria (`importPending` + warning) va in "Serve te" dopo circa 15 minuti, con "Scarta" consigliato. Con un plugin senza la funzione: nessuna sezione, nessun errore.
- [ ] Torrent già in qBittorrent (app 0.30.0, plugin 1.22.0, un admin): scegli dalla ricerca una release di un torrent già completo in qBittorrent. Al posto di "rifiutato" compare il dialogo con il nome del torrent; "Annulla" non cambia nulla; "Importa" dà "Import avviato" e i file del titolo scelto sostituiscono quelli in libreria, il torrent resta in seed con i suoi file e il giro non riscarica. Prova anche un film con un torrent di un solo file.
- [ ] Già al minimo (app 0.31.0, plugin 1.23.0, un admin): da Spazio → Alleggerisci, la riga uguale al file attuale dice "È il file che hai già", senza oro e senza Scarica; "Niente di più leggero con punteggio N o più" compare solo se non c'è niente di più leggero (di una stagione contano i pack interi). "Già al minimo" chiude la pagina: il titolo esce da Alleggerire e compare in Tenuti con l'etichetta; "Rimuovi" lo riporta. Un file di peso diverso al calcolo dopo lo fa tornare da solo. Con un plugin precedente il pulsante dà "Questo titolo non c'è più: ricalcola", nessun altro errore.
- [ ] Selezione degli orfani (app 0.32.0, un admin): da Spazio → Pulizia → File orfani, "Seleziona" mette le caselle (non sulle righe con altri collegamenti) e la pagina non torna in cima. "Seleziona tutti" prende anche le righe oltre "Mostra altri"; Maiusc con un tocco sceglie l'intervallo dall'ultima riga toccata, nei due sensi. "Elimina selezionati" mostra i percorsi e il totale; "Annulla" non tocca niente, confermando la finestra dei passi dice "N file" e i file spariscono dalla lista. Entrare in questa selezione esce da quella di "Cancellare", e viceversa.
- [ ] Ordine di "In attesa" (app 0.32.1, un admin): in Download, nella sezione "In attesa", vengono prima le voci in download, poi le ricerche in corso, poi quelle in coda, poi le altre; tra un aggiornamento e l'altro le righe si spostano solo se cambia il loro stato.
- [ ] Avanzamento della coda (app 0.36.0, un admin, su PC e Fire TV): Admin → Download con la coda piena: riquadro in cima con "cercati / totale", barra, fine stimata e ricerche all'ora; "In pausa" con i download automatici spenti; "Stima in calcolo…" appena partita; sparisce a coda vuota. Su TV il riquadro non prende il focus. Con un plugin precedente: nessun riquadro, nessun errore.
- [ ] Precedenza alle ricerche manuali (app 0.37.0, plugin 1.26.0, un admin, con la coda automatica piena): una ricerca manuale mostra "In attesa: sta finendo una ricerca automatica (…)" finché quella non finisce, poi "Ricerca su Sonarr in corso" da 0:00; nel frattempo nessuna nuova ricerca automatica parte e il riquadro della coda dice "In pausa: ricerca manuale in corso"; finita la ricerca manuale la coda riparte. Con il plugin 1.25.0: tutto come prima.
- [ ] Scarica subito (app 0.38.0, plugin 1.27.0, un admin, con la coda automatica piena e una ricerca in corso): nella scheda Download il campo restringe tutte le sezioni; una serie appena aggiunta mostra "Non è in lista", "Aggiorna ora" la fa comparire senza avviare altre ricerche; "Scarica subito" la porta davanti: nel log è la prima ricerca dopo quella in corso. Con il plugin 1.26.0: il filtro funziona, i due pulsanti non compaiono.
- [ ] Trailer (app 0.39.0, plugin 1.28.0): Colony da Windows, iPhone e Fire Stick parte dentro l'app; un titolo con trailer Jellyfin; un titolo senza; dopo un'ora il file non è più sul seedbox.
- [ ] Ricerca a mano di una stagione anime (app 0.40.0, plugin 1.29.0, Prowlarr configurato): i risultati arrivano da Prowlarr in pochi secondi, i motivi di scarto sono brevi; "Cerca con Sonarr" rifà la ricerca; Alleggerisci finisce.
- [ ] Togliere dalle righe della Home (app 0.35.0, su PC e Fire TV): la × nell'anteprima di una card di "Prossimi episodi" toglie la serie subito, "Annulla" la rimette; "Togli da Prossimi episodi" nel "⋯" della serie (anche dalla TV) la toglie e la voce diventa "Rimetti in Prossimi episodi". Guardato un episodio di una serie tolta, la serie torna; riaprendo l'app le serie tolte restano tolte, anche su un altro dispositivo. In "Continua a guardare" la × (o "Togli da Continua a guardare" nel "⋯" di film, episodio o serie) toglie il titolo, "Annulla" rimette il minuto di prima; tolto, il titolo non è più nemmeno in jellyfin-web e "visto" non cambia. La riga "Prossimi episodi" non si accorcia togliendo qualche serie.
- [ ] Sito web nel browser: login; un titolo HEVC in copia (TranscodeReasons solo audio); sottotitoli PGS, ASS e SRT; cambio traccia audio; Esc esce dal tutto schermo; chiudere la scheda ferma la sessione.
- [ ] Sito dal telefono (iPhone, sul sito di prova; vedi "Sito di prova"): barra in basso e "Altro" con tutte le voci; anteprima di una card tenendo premuto; un episodio con i controlli al tocco (tocco mostra/nasconde, doppio tocco ai lati salta di 10 s); salti e tracce; ricerca di un sottotitolo (e scaricamento); una richiesta; ogni scheda dell'Admin; Amici e Notifiche come pagina; un watch party con il sito sul PC; la tastiera sui campi (login, ricerca, chat: il campo resta visibile); rotazione verticale/orizzontale a metà video; tacca e barra home non coprono barre e controlli. Il gesto indietro del telefono su una finestra aperta come pagina (per esempio i sottotitoli) oggi chiude anche la pagina sotto: limite noto, non un errore nuovo.
- [ ] Aggiornamento da una versione precedente; aggiornamento obbligatorio.
- [ ] TV col telecomando (app 0.34.0, Fire TV): avvio sulla Home col focus sul carosello; Sinistra apre la barra laterale e Su/Giù non la chiudono; Destra sull'ultimo pulsante e ⏪/⏩ cambiano diapositiva; tornando da un titolo o dal player il focus resta sulla card (anche se la riga è cambiata); pagina del titolo con la riga delle stagioni nella prima schermata; Cerca, Film/Serie, Stasera, La mia lista, Richieste; player di "2012" (OK, ±10 s, Audio e sottotitoli, Indietro) ed episodio successivo; Indietro nei pannelli del login e su "Chi guarda?"; doppio Indietro dalla Home esce.
- [ ] TV, installazione (Fire TV senza WonderFlix e, quando c'è, una TV Google TV / Android TV; istruzioni di `docs/INSTALLAZIONE-TV.md`): Downloader con il codice (o con l'indirizzo `hashvps.aiko.usbx.me/wonderflix/tv.apk`) scarica e installa l'ultima versione; ingresso con Quick Connect.
- [ ] TV, aggiornamento da Impostazioni (dalla build più bassa con la chiave di rilascio, vedi "Prima release con l'APK"): sotto la versione "WonderFlix X.Y.Z disponibile" e "Aggiorna" raggiungibile col telecomando, nessun banner. La prima volta si aprono le impostazioni "Installa app sconosciute" e Impostazioni spiega cosa fare; negato il permesso o tornati indietro, "Aggiorna" si ripreme e le impostazioni non si riaprono da sole. Concesso, "Aggiorna" apre l'installer di Android; "Annulla" lascia l'app usabile; confermando, l'installer finisce su "Fatto"/"Apri" (l'app non si riapre da sola) e con "Apri" WonderFlix è aggiornato e ancora dentro.
- [ ] TV, versione in Impostazioni (app 0.35.1, Fire TV): da "Quando mostrare i sottotitoli" Giù porta alla versione (bordo oro) e la pagina scorre fino in fondo, con l'aggiornamento sotto se c'è; con un aggiornamento pronto un altro Giù arriva su "Aggiorna".
- [ ] Server nuovo (app 0.35.2, PC, sito e Fire TV): l'app entra su `hashvps.aiko.usbx.me`: home, un episodio, Download, Spazio. Una 0.35.1 installata mostra subito l'aggiornamento obbligatorio, anche dalla schermata di login, sul PC e sulla TV. Il codice di Downloader porta al `tv.apk` del server nuovo; il sito risponde su `https://hashvps.aiko.usbx.me/wonderflix/`.
- [ ] TV, aggiornamento obbligatorio (`min-version` sopra la versione installata): schermata bloccante con "Aggiorna ora" a fuoco, la riga per reinstallare con Downloader; senza rete "Riprova" a fuoco. Un APK firmato con un'altra chiave (una build di debug sopra): Android rifiuta, l'app resta sulla schermata con il pulsante attivo.
- [ ] Discord Rich Presence attiva e disattivata.
- [ ] Admin → Utenti → ⋮ → "Associa Discord": cerca, anteprima, associa; poi il recupero di quell'utente arriva su quel Discord. "Associa email": lo stesso con l'indirizzo.
- [ ] Dashboard → "Other Discord server IDs" con il server degli amici (bot invitato lì): un utente che è solo in quel server collega Discord da Impostazioni, e "Associa Discord" lo trova.
- [ ] Pannello media di Windows con il nome "WonderFlix" (app installata).
- [ ] "Copia diagnostica" e cartella dei log.

## Sito web

Lo stesso tag `vX.Y.Z` fa partire anche il job `web` di **Release**, dopo quelli di Windows e della TV (`needs: [release, android]`: se uno dei due fallisce il sito non esce; il tag lo controllano già quei job): compila il sito (`flutter build web --wasm`, base `/wonderflix/`) con la stessa configurazione dei Secrets e lo copia con `rsync` in `~/wonderflix-web` sul server. Prima i file, poi `index.html`; i file che non esistono più vengono tolti. Il sito è su `https://hashvps.aiko.usbx.me/wonderflix/` e non ha bozza: va online appena il job finisce, anche se la release di Windows resta in bozza.

Il job `web` copia anche l'APK della TV (artefatto `wonderflix-tv` del job `android`) come `build/web/tv.apk`, prima del primo `rsync`: l'indirizzo fisso `https://hashvps.aiko.usbx.me/wonderflix/tv.apk` (quello del codice di Downloader) dà sempre l'ultima versione taggata. Diventa pubblico al tag, appena il job `web` finisce, anche se la release di GitHub è ancora in bozza: chi installa con Downloader prende già quella versione (le TV già installate no, finché la release non è pubblicata).

**Secrets del sito** (oltre a quelli sopra):

| Secret | Valore |
|---|---|
| `WONDERFLIX_DEPLOY_SSH_KEY` | chiave privata SSH (senza passphrase) usata solo per il deploy |
| `WONDERFLIX_DEPLOY_KNOWN_HOSTS` | riga di `known_hosts` del server (`ssh-keyscan -t ed25519 149.40.59.140`) |

La chiave pubblica sta in `~/.ssh/authorized_keys` dell'utente `hashvps` sul server, vincolata a `command="/usr/bin/rrsync /home/hashvps/wonderflix-web"` (con `restrict`): può solo copiare file in quella cartella. Per rigenerarla: `ssh-keygen -t ed25519 -N "" -f deploy_key`, nella riga di `authorized_keys` sostituisci solo la parte `ssh-ed25519 AAAA…` con il contenuto di `deploy_key.pub`, lasciando il prefisso `restrict,command="/usr/bin/rrsync /home/hashvps/wonderflix-web"`, aggiorna il Secret con la privata (`gh secret set WONDERFLIX_DEPLOY_SSH_KEY < deploy_key`) e cancella i due file locali.

**Rimettere una versione vecchia:** in *Actions* apri il run di **Release** del tag precedente e premi *Re-run* sul solo job `web`. Ricompila e ricopia quella versione (con il `tv.apk` dell'artefatto di quel run, finché GitHub lo conserva: 90 giorni). Su un tag fino a `v0.33.0` il workflow è quello vecchio, senza `tv.apk`: l'`rsync --delete` toglie `tv.apk` dal sito e Downloader dà 404 finché non si rilancia `web` su un tag con l'APK.

**nginx:** la conf del sito (file statici, `.wasm` e `.mjs` con il tipo giusto, `tv.apk` come `application/vnd.android.package-archive` senza cache) è in `app/deploy/wonderflix.conf`; va in `~/.apps/nginx/proxy.d/` sul server, poi `app-nginx restart`. La CI copia solo i file del sito, non la conf: quando `wonderflix.conf` cambia (come per `tv.apk`), copiala a mano al rilascio (fine riga LF), controlla con `/usr/sbin/nginx -t -p $HOME/.apps/nginx/ -c nginx.conf` e ricarica.

**Prima release con l'APK (prova):** prima di taggarla, sul Fire Stick deve esserci una build con la chiave di rilascio e una versione più bassa: da `app/`, con `key.properties` e `wonderflix-release.jks` in `app/android/`, metti a mano `version: 0.33.99` in `pubspec.yaml` (non committarlo), `flutter build apk --release --dart-define-from-file=config/wonderflix.json`, installa `build/app/outputs/flutter-apk/app-release.apk` con adb e rimetti `pubspec.yaml`. La release da provare deve essere almeno la `0.34.0` (il versionCode della 0.33.99 è 33099: una 0.33.x più alta non basta). Dopo la pubblicazione della release, la TV deve vederla e aggiornarsi da Impostazioni (la prima volta chiede il permesso di installare app).

## Sito di prova

Ogni tag pubblica il sito per tutti, quindi la build di un ramo si prova su un percorso separato dello stesso server: `https://hashvps.aiko.usbx.me/wonderflix-prova/` (file in `~/wonderflix-web-prova/`). È la stessa origine del sito vero, quindi il login di Jellyfin funziona. Per lo stesso motivo condivide con il sito pubblicato anche il `localStorage` (login e impostazioni): entrare o cambiare un'impostazione qui vale anche là.

1. Build (da `app/`), con la base del percorso di prova:
   ```bash
   flutter build web --wasm --base-href /wonderflix-prova/ --pwa-strategy=none --dart-define-from-file=config/wonderflix.json
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

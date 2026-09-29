# Pubblicare una versione di WonderFlix

L'app controlla gli aggiornamenti su `https://api.github.com/repos/davidesidoti/wonderflix/releases/latest`: vede solo le release **pubblicate**, mai le bozze né le pre-release.

## Una volta sola: i Secrets

Il repository deve essere **pubblico**: l'app legge le release senza token, e con un repository privato GitHub risponde 404 e l'app non si aggiorna mai.

Su GitHub: *Settings → Secrets and variables → Actions → New repository secret*.

| Secret | Valore | Obbligatorio |
|---|---|---|
| `WONDERFLIX_SERVER_URL` | indirizzo https del server Jellyfin | sì |
| `WONDERFLIX_DISCORD_APP_ID` | Application ID dell'app Discord | no (senza, niente Rich Presence) |
| `WONDERFLIX_SUPPORT_URL` | link di "Password dimenticata?" (es. invito Discord) | no |
| `WONDERFLIX_ACCESS_REQUEST_URL` | link del pulsante "Chiedi l'accesso" su Discord (es. `https://discord.com/users/<id>`) | no |

`githubRepo` non serve: la pipeline usa il repository stesso.

Firma del codice (per ora spenta in `release.yml`): `WONDERFLIX_SIGNING_CERT` (certificato `.pfx` in base64) e `WONDERFLIX_SIGNING_PASSWORD`, poi togli `if: ${{ false }}` dai due passaggi di firma.

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
- La disinstallazione toglie il programma. Log, preferenze e credenziali restano (log in `%LocalAppData%\WonderFlix`, credenziali nel Gestore credenziali di Windows).

## Checklist dei test manuali

Prima di ogni release, su un utente di prova:

- [ ] MKV con sottotitoli ASS interni, PGS interni e SRT esterni: resa corretta e sincronizzata.
- [ ] Ripresa dal minutaggio; stato "visto" sincronizzato con jellyfin-web.
- [ ] Ripiego sulla transcodifica (forzato: `--dart-define=wfBreakDirectPlay=true`).
- [ ] Salta intro, prossimo episodio, trickplay.
- [ ] Login con password e con Quick Connect; sessione scaduta.
- [ ] Aggiornamento da una versione precedente; aggiornamento obbligatorio.
- [ ] Discord Rich Presence attiva e disattivata.
- [ ] Pannello media di Windows con il nome "WonderFlix" (app installata).
- [ ] "Copia diagnostica" e cartella dei log.

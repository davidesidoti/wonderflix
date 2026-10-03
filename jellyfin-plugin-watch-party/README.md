# WonderFlix Watch Party (plugin di Jellyfin)

Plugin del server Jellyfin per il watch party di WonderFlix (spec E,
`docs/superpowers/specs/2026-10-02-wonderflix-watch-party-sociale-design.md`):
dice chi ha agito, porta la chat e le reazioni tra i membri di un gruppo
SyncPlay e tiene la lista amici (spec F,
`docs/superpowers/specs/2026-10-03-wonderflix-amici-party-privati-design.md`).
Senza il plugin WonderFlix funziona lo stesso, con gli avvisi
anonimi.

- Jellyfin **10.11.x** (net9.0, `targetAbi` 10.11.0.0). Per Jellyfin 12 serve
  una build nuova (net10.0).
- Nessuna configurazione. Endpoint sotto `/WonderFlixWatchParty`; gli eventi
  arrivano ai client come `GeneralCommand` `SendString` con la chiave
  `WonderFlixWatchParty`.
- **Dati:** amicizie e richieste stanno in
  `plugins/configurations/WonderFlixWatchParty/friends.json` (non nella
  cartella del plugin, che cambia a ogni versione). Un file illeggibile
  diventa `friends.json.bad` e il plugin riparte vuoto.
- **Party:** l'app registra ogni gruppo con la sua modalità (pubblico, solo
  amici, privato con codice) e chiede al plugin l'elenco già filtrato
  (`GET Parties`). I party stanno in RAM e spariscono con i gruppi SyncPlay.

## Installazione dal repository

1. Dashboard → Plugin → Repository → **+**: nome a piacere, URL
   `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/jellyfin-plugin-watch-party/manifest.json`.
2. Catalogo → **WonderFlix Watch Party** → Installa.
3. Riavvia Jellyfin.

## Installazione a mano (prove)

1. Dalla root del repository: `bash jellyfin-plugin-watch-party/pack.sh 1.1.0`.
   Crea `jellyfin-plugin-watch-party/artifacts/WonderFlix Watch Party_1.1.0.0/`
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
  si cercano a runtime (`Server/UserListing.cs`). Quando si aggiorna il
  server, si alzano i pacchetti `Jellyfin.Controller` e `Jellyfin.Model` del
  progetto di test a quella versione.
- Release: tag `watch-party-plugin-vX.Y.Z` → il workflow
  `watch-party-plugin.yml` pubblica una **pre-release** con lo zip e il suo
  MD5. Mai "latest": l'app legge `releases/latest` per i propri
  aggiornamenti. Poi si aggiunge la versione a `manifest.json`.

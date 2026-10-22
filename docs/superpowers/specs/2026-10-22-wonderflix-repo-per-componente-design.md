# WonderFlix — Progetto 1a: repo organizzata per componente

- **Data:** 2026-10-22
- **Stato:** approvata il 2026-10-22; **realizzata** il 2026-10-22 con il piano 26 (`docs/superpowers/plans/2026-10-22-wonderflix-26-repo-per-componente.md`), CI verde sulla PR #11, provata dall'utente.
- **Ambito:** progetto 1a dell'idea 1 di `docs/IDEE.md` ("Versione web"). Prepara la repo per il progetto 1b (sito web) senza scrivere codice per il web.

## 1. Obiettivo

Oggi la radice della repo è il progetto Flutter, con il plugin di Jellyfin in una sottocartella (`jellyfin-plugin-watch-party/`). Con il sito web in arrivo, l'utente vuole "tutto in ordine nelle sue sottocartelle dedicate": una cartella per componente, con tutti gli installer e le build sempre in quest'unica repo.

Una cartella per **componente**, non per piattaforma: Flutter produce Windows e web dallo stesso codice, quindi il sito del progetto 1b nascerà dentro la cartella dell'app (`app/web/`, accanto ad `app/windows/`).

## 2. Obiettivi, non obiettivi, anti-obiettivi

**Obiettivi**
- La radice contiene solo quello che riguarda tutta la repo.
- Ogni file spostato conserva la storia (`git mv`).
- Tutto quello che dipende dai percorsi funziona come prima: analisi, test, build Windows, installer, CI, release dell'app e del plugin, catalogo dei plugin di Jellyfin.

**Non obiettivi**
- Niente codice per il web, niente `app/web/`.
- Nessuna modifica al codice Dart o C#, nessuna nuova versione di app o plugin, nessuna release.
- Le spec e i piani vecchi in `docs/superpowers/` non si toccano: raccontano lo stato di allora.
- La CI dell'app continua a girare a ogni push, come oggi: nessun nuovo filtro sui percorsi.

**Anti-obiettivi** (sarebbe un fallimento anche se "funziona")
- Il server Jellyfin non vede più gli aggiornamenti del plugin.
- La prossima release (tag `v*` o `watch-party-plugin-v*`) si rompe per un percorso dimenticato nei workflow.
- Una cartella o un file lasciati a metà alla radice (per esempio una `config/` vuota, un `.gitignore` con regole che non valgono più).

## 3. Struttura nuova (decisa)

I nomi `app/` e `plugin/` sono una scelta di Claude: l'utente non aveva preferenze, solo il desiderio di ordine.

```
/
├── .github/            (ISSUE_TEMPLATE, workflows)
├── docs/               (IDEE.md, RELEASING.md, reference/, superpowers/)
├── app/                ← progetto Flutter
│   ├── lib/  test/  windows/  assets/  l10n/
│   ├── config/         (wonderflix.example.json)
│   ├── installer/      (wonderflix.iss)
│   ├── pubspec.yaml  pubspec.lock  analysis_options.yaml  l10n.yaml  .metadata
│   └── .gitignore      (regole di Flutter)
├── plugin/             ← ex jellyfin-plugin-watch-party/, contenuto uguale
│   ├── Jellyfin.Plugin.WonderFlixWatchParty/  …Tests/
│   ├── manifest.json  meta.template.json  pack.sh  README.md  .gitignore
├── .gitignore          (solo regole di tutta la repo)
├── LICENSE
└── README.md
```

- `installer/` va dentro `app/` perché impacchetta la build dell'app e non ha senso senza.
- `docs/` resta alla radice, compreso `docs/RELEASING.md` (che parla di app e plugin).

## 4. Cosa cambia per ogni file

Le regole sotto sono decise; i dettagli di scrittura sono lasciati a chi costruisce.

### 4.1 File che non cambiano contenuto

Tutti i percorsi interni sono relativi alla loro cartella e si spostano insieme:
- `installer/wonderflix.iss` usa `..\build\…`, `..\windows\…`, `..\dist`: da `app/installer/` puntano ad `app/build`, `app/windows`, `app/dist`. Va aggiornato solo il commento in testa ("dalla root del repository" → "dalla cartella `app/`").
- `pack.sh` usa `$here`: cambia solo il commento d'uso (`bash plugin/pack.sh 1.13.0`).
- `l10n.yaml`, `analysis_options.yaml`, `config/wonderflix.example.json`: nessun percorso da cambiare.
- I test Dart che leggono `l10n/app_*.arb` con percorsi relativi funzionano perché `flutter test` gira da `app/`.

### 4.2 `.gitignore`

Si divide in due:
- **`app/.gitignore`**: le regole di Flutter/Dart/IntelliJ/simboli, `config/wonderflix.json`, `lib/l10n/gen/`, `/build/`, `/coverage/`, `/dist/` (ora relative ad `app/`).
- **`.gitignore` alla radice**: `.superpowers/`, `.claude/worktrees/`, e le voci "Miscellaneous" generiche (`*.log`, `.DS_Store`, …).

`windows/.gitignore` e il `.gitignore` del plugin si spostano con le loro cartelle.

### 4.3 Workflow (`.github/workflows/`)

- **`ci.yml`:** `defaults.run.working-directory: app`. Il resto uguale.
- **`release.yml`:** `defaults.run.working-directory: app` per tutti i passi `run`. Il passo `actions/upload-artifact` non usa `working-directory`, quindi il suo `path` diventa `app/dist/*`. Il commento in testa e i messaggi d'errore che citano `pubspec.yaml` restano validi.
- **`watch-party-plugin.yml`:** filtri dei percorsi `plugin/**`, `working-directory: plugin` nei due job, e nella nota della pre-release `plugin/manifest.json`.

### 4.4 Manifest del plugin e catalogo di Jellyfin

Il plugin è installato **solo sul server dell'utente** (risposta dell'utente). Quindi non serve tenere vivo il vecchio indirizzo:
- il manifest si sposta in `plugin/manifest.json`, nuovo URL `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/plugin/manifest.json`;
- i `sourceUrl` dentro il manifest puntano alle release di GitHub, non ai percorsi della repo: restano uguali;
- **dopo il push su `main`** (prima il nuovo indirizzo non esiste), Claude cambia l'URL del repository dei plugin sul Jellyfin di ultra.cc (`ssh ultra`, lavoro sul server già autorizzato), poi controlla che il Catalog mostri WonderFlix Watch Party 1.13.0 senza errori. Come cambiarlo (API `/Repositories` di Jellyfin o Dashboard) è lasciato a chi costruisce.

### 4.5 Documenti

- **`README.md` alla radice:** resta la pagina principale su GitHub. Si aggiunge una breve sezione "Struttura" (`app/` e `plugin/`, una riga ciascuna) e i comandi esistenti si aggiornano: `config/` → `app/config/`, comandi `flutter …` da lanciare dentro `app/`.
- **`plugin/README.md`:** URL del manifest, comandi `pack.sh` e `dotnet test` con i percorsi nuovi.
- **`docs/RELEASING.md`:** tutti i percorsi che servono per fare una release (csproj, manifest, URL del repository, `installer/wonderflix.iss`, eventuali comandi locali).
- **`docs/IDEE.md`:** l'idea 1a passa tra le fatte; nelle idee aperte i percorsi `installer/` e `windows/` diventano `app/installer/` e `app/windows/`. I percorsi `lib/…` si possono lasciare con una riga in testa che spiega che sono dentro `app/` (scelta di chi costruisce).

## 5. Dopo il merge, sulla checkout principale

I file fuori da git non si spostano con `git mv`. Sulla checkout principale (`C:\Users\sidot\Documents\Github\wonderflix`):
- `config/wonderflix.json` (contiene l'indirizzo vero del server) va spostato in `app/config/wonderflix.json` **nello stesso passo del merge**: dopo il merge il `.gitignore` alla radice non lo ignora più, e resterebbe lì pronto a finire in un commit per sbaglio. Senza lo spostamento, inoltre, la build locale non trova la configurazione;
- le cartelle generate alla radice (`build/`, `.dart_tool/`, `flutter_*.log`) diventano inutili e si possono cancellare; se ne ricreano di nuove dentro `app/`.

Nel worktree di lavoro serve lo stesso file: va copiato da lì in `app/config/wonderflix.json` per la build di prova.

## 6. Verifica (fatto quando)

1. Da `app/`: `flutter pub get`, `flutter gen-l10n`, `flutter analyze` senza problemi, `flutter test` tutto verde.
2. Da `app/`: `flutter build windows --release --dart-define-from-file=config/wonderflix.json` produce `app/build/windows/x64/runner/Release/wonderflix.exe`.
3. Da `plugin/`: `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` tutto verde; `bash pack.sh 1.13.0` crea la cartella in `plugin/artifacts/`.
4. Workflow: riletti riga per riga contro la struttura nuova; `ci.yml` e `watch-party-plugin.yml` verdi in una run vera sulla PR (§7); `release.yml` non si può provare senza un tag: si verifica a lettura e compilando l'installer in locale (§7).
5. `git status` pulito dopo build e test (le cartelle generate sono ignorate dalle regole nuove).
6. L'utente prova l'app compilata dal worktree.
7. Dopo il push su `main`: l'URL del repository dei plugin è cambiato sul server e il Catalog funziona (§4.4).

## 7. Decisi con l'utente

- **Run vera dei workflow prima del merge, con una PR** (sì dell'utente). `ci.yml` e `watch-party-plugin.yml` partono sui push solo per `main`, quindi serve una PR. Il merge resta comunque locale (merge del ramo su `main` e push, come sempre), non con il pulsante di GitHub: uno "squash" fonderebbe i `git mv` in un solo commit. Quando i commit arrivano su `main`, GitHub segna la PR come unita da sola.
- **Prova dell'installer in locale** (sì dell'utente): si installa Inno Setup 6.7.1, la stessa versione della CI, e si compila `app/installer/wonderflix.iss` da `app/` dopo la build release. L'installer deve finire in `app/dist/`.

## 8. Lasciato a chi costruisce

- Ordine dei commit e loro suddivisione (purché ogni `git mv` sia un rename riconosciuto da git).
- Il testo esatto delle sezioni dei README e di `RELEASING.md`.
- Come cambiare l'URL del repository sul server (§4.4).

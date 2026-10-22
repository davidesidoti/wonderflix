# Piano 26 — Repo organizzata per componente (progetto 1a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** spostare il progetto Flutter in `app/` e il plugin in `plugin/` con `git mv`, aggiornando tutto quello che dipende dai percorsi.

**Architecture:** solo spostamenti e configurazione: nessuna riga di Dart o C# cambia. I percorsi interni di `.iss`, `pack.sh` e `l10n.yaml` sono relativi alla loro cartella e restano validi; cambiano `.gitignore`, i tre workflow e i documenti.

**Tech Stack:** Flutter 3.47.5, .NET 9, GitHub Actions, Inno Setup 6.7.1.

**Spec:** `docs/superpowers/specs/2026-10-22-wonderflix-repo-per-componente-design.md`

## Global Constraints

- Ogni spostamento con `git mv`, così git lo riconosce come rename (`git log --follow` mostra la storia).
- Nessuna modifica a codice Dart/C#, a `pubspec.yaml` (versione 0.20.0), al csproj (1.13.0) o al contenuto di `manifest.json`.
- `docs/superpowers/specs/` e `docs/superpowers/plans/` vecchi non si toccano.
- Nessun codice per il web, nessuna cartella `app/web/`.
- Documenti in italiano, codice e commenti YAML/shell come sono (in italiano, come oggi).
- Commit solo a nome dell'utente: nessuna riga `Co-Authored-By`, nessun "Generated with Claude Code", nessuna parola `closes`/`fixes` nei messaggi.
- La build si fa sempre con `--dart-define-from-file=config/wonderflix.json`.
- Mai `taskkill` per nome dell'immagine (per esempio `taskkill /IM wonderflix.exe`): solo per PID di un processo avviato da sé.

## Review Focus

1. **File ignorati che diventano visibili:** dopo lo spostamento, `git status` deve restare pulito con `app/build/`, `app/.dart_tool/`, `app/lib/l10n/gen/`, `app/config/wonderflix.json`, `app/dist/`, `plugin/artifacts/`, `plugin/**/bin|obj` presenti. Verifica nel Task 1 (passo 5) e nel Task 3 (passo 4).
2. **Upload dell'installer nella release:** `actions/upload-artifact` ignora `working-directory`, quindi il path deve essere `app/dist/*`. Verifica a lettura nel Task 2 e con l'installer vero nel Task 3.
3. **La CI del plugin non parte sulla PR:** i filtri `paths` devono valere per i file spostati in `plugin/`. Verifica con la run vera nel Task 5.
4. **Configurazione con l'indirizzo vero lasciata alla radice** della checkout principale dopo il merge: si sposta nello stesso passo (Task 5).
5. **Catalogo plugin di Jellyfin senza manifest:** l'URL si cambia solo dopo il push su `main` (Task 5).

---

### Task 1: Spostare app e plugin, dividere `.gitignore`

**Files:**
- Move: `lib/ test/ windows/ assets/ l10n/ config/ installer/ pubspec.yaml pubspec.lock analysis_options.yaml l10n.yaml .metadata` → `app/`
- Move: `jellyfin-plugin-watch-party/` → `plugin/`
- Create: `app/.gitignore`
- Modify: `.gitignore`, `app/installer/wonderflix.iss:2` (commento), `plugin/pack.sh:4-5` (commento)

**Interfaces:**
- Produces: la struttura della spec §3. I task seguenti lanciano Flutter da `app/` e dotnet da `plugin/`.

- [ ] **Step 1: `git mv`** dei file e cartelle sopra (crea `app/` prima; il plugin con `git mv jellyfin-plugin-watch-party plugin`). Commit separato dal resto, solo rename, così git li riconosce al 100%.

- [ ] **Step 2: dividere `.gitignore`.** In `app/.gitignore` vanno: `config/wonderflix.json`, `lib/l10n/gen/`, le sezioni "IntelliJ related", "Flutter/Dart/Pub related" (`/build/` e `/coverage/` restano con la `/` iniziale, ora relativa ad `app/`), "Symbolication / obfuscation", e `/dist/` con il suo commento (`installer/wonderflix.iss`). Alla radice restano: `.superpowers/`, "Miscellaneous", `.claude/worktrees/`. Nessuna regola duplicata.

- [ ] **Step 3: commenti d'uso.** `wonderflix.iss` riga 2: "dalla cartella `app/` del repository". `pack.sh`: "Uso, dalla root del repository: `bash plugin/pack.sh 1.0.0`".

- [ ] **Step 4: configurazione per la build.** Copia `C:\Users\sidot\Documents\Github\wonderflix\config\wonderflix.json` in `app/config/wonderflix.json` del worktree (file ignorato, non va in commit).

- [ ] **Step 5: verifica.** Da `app/`:
  `flutter pub get` → ok; `flutter gen-l10n` → ok; `flutter analyze` → "No issues found!"; `flutter test` → "All tests passed!";
  `flutter build windows --release --dart-define-from-file=config/wonderflix.json` → esiste `app/build/windows/x64/runner/Release/wonderflix.exe`.
  Da `plugin/`: `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release` → tutti passati; `bash pack.sh 1.13.0` → stampa `…/plugin/artifacts/WonderFlix Watch Party_1.13.0.0`.
  Alla radice: `git status --short` → vuoto (a parte le modifiche non ancora in commit di questo task). `git check-ignore -v app/config/wonderflix.json app/build app/lib/l10n/gen plugin/artifacts` → ognuno ignorato da una regola.

- [ ] **Step 6: commit** di `.gitignore`, `app/.gitignore`, `.iss`, `pack.sh`: `chore: split gitignore and update usage comments for app/ and plugin/`.

### Task 2: Workflow

**Files:**
- Modify: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `.github/workflows/watch-party-plugin.yml`

**Interfaces:**
- Consumes: struttura del Task 1.

- [ ] **Step 1: `ci.yml`.** Aggiungi al job `test` `defaults: run: working-directory: app`. Nient'altro.

- [ ] **Step 2: `release.yml`.** Aggiungi al job `release` `defaults: run: working-directory: app`. In `actions/upload-artifact` `path: app/dist/*`. Tutti gli altri percorsi (`pubspec.yaml`, `config/wonderflix.json`, `build\windows\…`, `installer\wonderflix.iss`, `dist\…`) restano relativi e corretti.

- [ ] **Step 3: `watch-party-plugin.yml`.** `paths`: `'plugin/**'` al posto di `'jellyfin-plugin-watch-party/**'` (push e pull_request); `working-directory: plugin` nei due job; nota della pre-release: `plugin/manifest.json`.

- [ ] **Step 4: verifica a lettura.** `grep -rn "jellyfin-plugin-watch-party" .github` → nessun risultato. Rileggi ogni passo `run` e `uses` di `release.yml` contro la struttura nuova: ogni percorso esiste partendo da `app/` (per i `run`) o dalla radice (per gli `uses`).

- [ ] **Step 5: commit** `ci: run workflows from app/ and plugin/`.

### Task 3: Installer in locale

**Interfaces:**
- Consumes: build release del Task 1, step "Inno Setup" e "Installer" di `release.yml`.

- [ ] **Step 1: installare Inno Setup 6.7.1** (consenso dell'utente già dato): `winget install --id JRSoftware.InnoSetup --version 6.7.1 -e` (oppure `choco install innosetup --version=6.7.1 -y` se winget non ha quella versione). Verifica: esiste `C:\Program Files (x86)\Inno Setup 6\ISCC.exe`.

- [ ] **Step 2: compilare come fa la release**, da `app/`, dopo la build del Task 1: `& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" "/DAppVersion=0.20.0" installer\wonderflix.iss` → codice 0.

- [ ] **Step 3: risultato.** Esiste `app/dist/WonderFlix-Setup-0.20.0.exe` e non esiste una `dist/` alla radice.

- [ ] **Step 4: ignorati.** `git status --short` → vuoto. Nessun commit in questo task.

### Task 4: Documenti

**Files:**
- Modify: `README.md`, `plugin/README.md`, `docs/RELEASING.md`, `docs/IDEE.md`, `docs/superpowers/specs/2026-10-22-wonderflix-repo-per-componente-design.md` (riga "Stato")

- [ ] **Step 1: `README.md`.** Nuova sezione "Struttura" prima di "Sviluppo": `app/` (app Flutter: Windows oggi, web in futuro; installer in `app/installer/`), `plugin/` (plugin Jellyfin "WonderFlix Watch Party", vedi `plugin/README.md`), `docs/`. In "Sviluppo": i comandi si lanciano da `app/`, e la configurazione è `app/config/wonderflix.example.json` → `app/config/wonderflix.json`.

- [ ] **Step 2: `plugin/README.md`.** URL del manifest `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/plugin/manifest.json`; `bash plugin/pack.sh 1.12.0` e `plugin/artifacts/…`; `dotnet test plugin/Jellyfin.Plugin.WonderFlixWatchParty.Tests`.

- [ ] **Step 3: `docs/RELEASING.md`.** `pubspec.yaml` → `app/pubspec.yaml`; `installer/wonderflix.iss` → `app/installer/wonderflix.iss`; cartella, csproj e manifest del plugin sotto `plugin/`; URL del repository dei plugin come nel passo 2. Verifica: `grep -n "jellyfin-plugin-watch-party\|\`installer/\|\`config/\|\`pubspec" docs/RELEASING.md` → solo percorsi con `app/` o `plugin/` davanti.

- [ ] **Step 4: `docs/IDEE.md`.** In "Fatte": "Progetto 1a — repo organizzata per componente (`app/`, `plugin/`)". Nella sezione 1 il paragrafo 1a diventa una riga "Fatto il 2026-10-22, vedi spec …". Nell'idea 2: `installer/` → `app/installer/`, runner `windows/` → `app/windows/`. Sotto l'intestazione del file una riga: "I percorsi `lib/…`, `test/…` sono dentro `app/`."

- [ ] **Step 5: verifica.** `grep -rn "jellyfin-plugin-watch-party" --include=*.md . | grep -v docs/superpowers` → nessun risultato.

- [ ] **Step 6: commit** `docs: paths for app/ and plugin/`.

### Task 5: PR, prova dell'utente, merge, catalogo

- [ ] **Step 1: PR per la CI.** Push del ramo e PR verso `main` (titolo "Repo organizzata per componente (app/, plugin/)"). Attendi le run: **CI** e **Watch party plugin** verdi. Se una fallisce, si corregge sul ramo.

- [ ] **Step 2: prova dell'utente** con l'exe compilato nel Task 1 (`app/build/windows/x64/runner/Release/wonderflix.exe`) o con l'installer del Task 3. Si va avanti solo con il suo ok.

- [ ] **Step 3: merge locale e configurazione**, nella checkout principale `C:\Users\sidot\Documents\Github\wonderflix` in un unico passo: `git merge --ff-only` del ramo su `main` (o merge normale se non è fast-forward, mai squash), poi `config/wonderflix.json` → `app/config/wonderflix.json`. Verifica: `git status --short` senza `config/`. Le cartelle generate alla radice (`build/`, `.dart_tool/`, `flutter_*.log`) si cancellano. Poi `git push origin main`: la PR risulta unita da sola.

- [ ] **Step 4: catalogo dei plugin.** Su `ssh ultra`, nel Jellyfin: il repository dei plugin con l'URL vecchio diventa `https://raw.githubusercontent.com/davidesidoti/wonderflix/main/plugin/manifest.json` (API `GET`/`POST /Repositories` con una chiave admin, o file di configurazione + `app-jellyfin restart`). Verifica: `curl -s` del nuovo URL restituisce il manifest; il Catalog elenca WonderFlix Watch Party 1.13.0.

- [ ] **Step 5: stato della spec**: "Realizzata il 2026-10-22 (piano 26)", commit e push su `main`.

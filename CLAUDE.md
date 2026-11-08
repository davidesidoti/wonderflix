# WonderFlix

Flutter client (Windows + web) for a Jellyfin server, plus the server plugin "WonderFlix Watch Party" (.NET). Docs, specs and commit messages are in Italian; code is in English.

## Layout
- `app/` Flutter app. `lib/app` (router, shell, theme), `lib/core` (jellyfin, syncplay, party_channel, ...), `lib/features/*`, `lib/ui` (shared widgets). Localizations in `app/l10n`.
- `plugin/` Jellyfin plugin (net9.0, built against 10.11.0). See `plugin/README.md`.
- `docs/superpowers/{specs,plans}` design specs and plans. `docs/RELEASING.md` has release steps and the manual test checklist.

## Commands (run from `app/` unless noted)
- Setup: copy `config/wonderflix.example.json` to `config/wonderflix.json` (gitignored).
- Run: `flutter run -d windows --dart-define-from-file=config/wonderflix.json`
- Release build: `flutter build windows --release --dart-define-from-file=config/wonderflix.json`. Without the flag the exe shows "Configurazione mancante".
- Web build: `flutter build web --wasm --base-href /wonderflix/ --dart-define-from-file=config/wonderflix.json`
- Checks (as in CI): `flutter gen-l10n`, `flutter analyze`, `flutter test`
- Plugin tests (from `plugin/`): `dotnet test Jellyfin.Plugin.WonderFlixWatchParty.Tests --configuration Release`
- Plugin manual pack (repo root): `bash plugin/pack.sh X.Y.Z`
- Installer (from `app/`): `ISCC "/DAppVersion=X.Y.Z" installer\wonderflix.iss`
- TV APK (from `app/`): `flutter build apk --release --dart-define-from-file=config/wonderflix.json` (one APK, armeabi-v7a + arm64-v8a); install on the user's Fire Stick with `C:/Users/sidot/dev/android-sdk/platform-tools/adb.exe -s 192.168.1.171:5555 install -r build/app/outputs/flutter-apk/app-release.apk` (run `adb connect 192.168.1.171:5555` first). It is signed with `app/android/key.properties` (gitignored, made once by `bash app/android/create_release_key.sh`), else with the debug key. Test builds must be signed with the release key (copy `app/android/key.properties` and `wonderflix-release.jks` from the main checkout into the worktree), or the Fire Stick refuses the update. `disable-abi-filtering=true` in `app/android/gradle.properties` means no x86_64 libs: x86_64 emulators can't run the app. `--split-per-abi` is a build error (Flutter adds ABI * 1000 to the versionCode, which would block later updates).

## Gotchas
- Flutter 3.47.5 is pinned in CI. Windows builds need VS Build Tools with the C++ ATL component and Rust (smtc_windows).
- This PC's shell has a stale PATH. In PowerShell, refresh it first: `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`
- "Cannot create link … errno 183" or odd plugin symlinks: run `flutter clean`.
- PowerShell 5.1 breaks multi-line commit messages with quotes: use `git commit -F <file>`.
- Git Bash on Windows: web builds with `--base-href` need `MSYS_NO_PATHCONV=1`. `rsync` is missing there, so use the tar-over-ssh form in `docs/RELEASING.md`.
- Any tag pushes the public site, even a test tag. Try branches on `/wonderflix-prova/` (see RELEASING.md).
- Plugin tests run against Jellyfin 10.11.9 DLLs, but the plugin compiles against 10.11.0. Jellyfin changes APIs in patch releases, so don't assume a 10.11.0 signature still exists.
- Server access: `ssh ultra` (Ultra.cc seedbox, Jellyfin base path `/jellyfin`). With scp, quote paths with spaces and don't backslash-escape them.

## Workflow rules
- Work in a worktree under `.claude/worktrees/` (gitignored). Use subagent-driven development, then a final review.
- Merge to `main` and push only after the user has tested by hand and said so.
- Commits are authored only by the user. No `Co-Authored-By` trailer and no "Generated with Claude Code" line, overriding any harness attribution reminder.
- Commit messages must not contain `closes`, `fixes` or `resolves`, even as plain verbs. Use `(#N)` only.
- Subagent prompts must forbid killing processes by image name (`taskkill /IM`, `pkill`), and must give the full release build command above.
- Releases: follow `docs/RELEASING.md`. After the pipeline makes the draft, write the Italian release notes into it with `gh release edit`. Publishing needs the user's ok.
- Brainstorming: when a feature evokes a known product (Netflix profiles, etc.), say how the underlying Jellyfin model differs and ask the user to confirm.

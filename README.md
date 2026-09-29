# WonderFlix

Client desktop Windows per il server Jellyfin WonderFlix.

## Sviluppo

Requisiti: Flutter 3.47.x (stable) con Visual Studio Build Tools (workload "Desktop development with C++" + componente "C++ ATL", richiesto da flutter_secure_storage).

1. Copia `config/wonderflix.example.json` in `config/wonderflix.json` e inserisci l'indirizzo del server (il file è in `.gitignore`).
2. Avvia:

   ```bash
   flutter run -d windows --dart-define-from-file=config/wonderflix.json
   ```

Test: `flutter test` · Analisi: `flutter analyze` · Localizzazioni: `flutter gen-l10n`

Design: `docs/superpowers/specs/` · Piani: `docs/superpowers/plans/`

import '../../l10n/gen/app_localizations.dart';

/// Codice di Downloader (aftv.news/8025402): porta al `tv.apk` del sito
/// (`hashvps.aiko.usbx.me/wonderflix/tv.apk`, docs/INSTALLAZIONE-TV.md).
const tvDownloaderCode = '8025402';

/// "Se l'aggiornamento non va, disinstalla e reinstalla con Downloader".
String tvReinstallHint(AppLocalizations l) =>
    l.tvUpdateReinstallCode(tvDownloaderCode);

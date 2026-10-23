import 'dart:js_interop';

import 'browser_name.dart';

@JS('navigator.userAgent')
external String get _userAgent;

/// Nel browser non c'è un nome del PC: si usa quello del browser.
String hostName() => describeBrowser(_userAgent);

/// Nel browser non ci sono variabili d'ambiente (niente profili di sviluppo).
Map<String, String> environment() => const {};

String systemDescription() => _userAgent;

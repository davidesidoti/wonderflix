import 'dart:io';

/// Nome del PC.
String hostName() => Platform.localHostname;

Map<String, String> environment() => Platform.environment;

/// Versione di Windows, per il log di avvio e la diagnostica.
String systemDescription() => Platform.operatingSystemVersion;

/// Android TV / Fire TV: lì non ci sono finestra, libmpv né SMTC.
bool get isAndroidTv => Platform.isAndroid;

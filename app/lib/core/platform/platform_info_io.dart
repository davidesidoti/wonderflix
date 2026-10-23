import 'dart:io';

/// Nome del PC.
String hostName() => Platform.localHostname;

Map<String, String> environment() => Platform.environment;

/// Versione di Windows, per il log di avvio e la diagnostica.
String systemDescription() => Platform.operatingSystemVersion;

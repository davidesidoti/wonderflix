import '../jellyfin/api_exception.dart';

/// L'interruttore di un tipo di notifica per l'utente (spec V §4.2).
class NotificationTypePref {
  const NotificationTypePref({required this.type, required this.enabled});

  /// Uno dei tipi della cassetta (`DiskAlmostFull`, ...), anche uno che
  /// l'app non conosce.
  final String type;
  final bool enabled;

  /// `Type` ed `Enabled` ci devono essere: meglio un errore che un
  /// interruttore inventato.
  factory NotificationTypePref.fromJson(Map<String, dynamic> json) {
    final (type, enabled) = (json['Type'], json['Enabled']);
    if (type is! String || enabled is! bool) {
      throw const ServerErrorException(null);
    }
    return NotificationTypePref(type: type, enabled: enabled);
  }
}

/// Risposta di `GET Notifications`: la chiave pubblica VAPID e i tipi che
/// l'utente può scegliere, nell'ordine della pagina delle preferenze.
class NotificationsInfo {
  const NotificationsInfo({required this.vapidPublicKey, required this.types});

  factory NotificationsInfo.fromJson(Map<String, dynamic> json) {
    final key = json['VapidPublicKey'];
    final types = json['Types'];
    if (key is! String || types is! List) throw const ServerErrorException(null);
    return NotificationsInfo(
      vapidPublicKey: key,
      types: [
        for (final raw in types)
          NotificationTypePref.fromJson(raw as Map<String, dynamic>),
      ],
    );
  }

  final String vapidPublicKey;
  final List<NotificationTypePref> types;
}

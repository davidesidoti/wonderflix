/// Identità del client inviata a Jellyfin in ogni richiesta.
class ClientInfo {
  const ClientInfo({
    required this.client,
    required this.device,
    required this.deviceId,
    required this.version,
  });

  final String client;
  final String device;
  final String deviceId;
  final String version;

  /// Lo stesso client con il DeviceId di un profilo (spec K §9.2).
  ClientInfo copyWith({String? deviceId}) => ClientInfo(
        client: client,
        device: device,
        deviceId: deviceId ?? this.deviceId,
        version: version,
      );
}

String _clean(String value) => value
    .replaceAll(RegExp(r'[",\r\n]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Header `Authorization` nel formato `MediaBrowser ...` atteso da Jellyfin.
String buildAuthorizationHeader(ClientInfo info, {String? token}) {
  final parts = <String>[
    'Client="${_clean(info.client)}"',
    'Device="${_clean(info.device)}"',
    'DeviceId="${_clean(info.deviceId)}"',
    'Version="${_clean(info.version)}"',
    if (token != null) 'Token="$token"',
  ];
  return 'MediaBrowser ${parts.join(', ')}';
}

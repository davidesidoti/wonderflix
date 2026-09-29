import 'package:wonderflix/core/jellyfin/client_info.dart';

const testClientInfo = ClientInfo(
  client: 'WonderFlix',
  device: 'PC-TEST',
  deviceId: 'dev-test',
  version: '0.0.1',
);

final testServerUrl = Uri.parse('https://media.example.com');

import 'package:wonderflix/core/jellyfin/auth_models.dart';
import 'package:wonderflix/core/jellyfin/client_info.dart';

const testClientInfo = ClientInfo(
  client: 'WonderFlix',
  device: 'PC-TEST',
  deviceId: 'dev-test',
  version: '0.0.1',
);

final testServerUrl = Uri.parse('https://media.example.com');

const testUser = JellyfinUser(id: 'u1', name: 'Mario');

Map<String, dynamic> authResultJson({String token = 'tok-1'}) => {
      'User': {'Id': 'u1', 'Name': 'Mario', 'PrimaryImageTag': 'img1'},
      'AccessToken': token,
      'ServerId': 'srv',
    };

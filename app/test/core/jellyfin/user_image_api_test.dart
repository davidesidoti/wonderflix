import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/jellyfin_http.dart';
import 'package:wonderflix/core/jellyfin/user_image_api.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_data.dart';

void main() {
  late FakeAdapter adapter;
  late UserImageApi api;

  setUp(() {
    adapter = FakeAdapter((_) => const FakeResponse(204));
    api = UserImageApi(JellyfinHttp(
        baseUrl: testServerUrl, clientInfo: testClientInfo, adapter: adapter));
  });

  test('carica l\'immagine in base64, con il suo tipo', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 250]);

    await api.upload('u1', ImageUpload(bytes, 'image/png'));

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/UserImage');
    expect(request.queryParameters, {'userId': 'u1'});
    expect(request.data, base64Encode(bytes));
    expect(request.contentType, 'image/png');
  });

  test('toglie l\'immagine', () async {
    await api.remove('u1');

    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.path, '/UserImage');
    expect(request.queryParameters, {'userId': 'u1'});
  });

  test('senza permesso 403, con un token scaduto 401', () async {
    adapter.handler = (_) => const FakeResponse(403);
    await expectLater(
        api.upload('u1', ImageUpload(Uint8List(1), 'image/jpeg')),
        throwsA(isA<ForbiddenException>()));

    adapter.handler = (_) => const FakeResponse(401);
    await expectLater(api.remove('u1'), throwsA(isA<UnauthorizedException>()));
  });
}

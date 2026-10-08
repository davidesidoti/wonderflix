import 'dart:convert';
import 'dart:typed_data';

import 'jellyfin_http.dart';

/// Un'immagine da caricare: i byte e il loro tipo (`image/png`, `image/jpeg`).
class ImageUpload {
  const ImageUpload(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

/// L'immagine di un utente su Jellyfin (spec K §10.4). Gli errori sono
/// `ApiException`: 403 senza il permesso di cambiarla, 401 con un token che
/// non vale più.
class UserImageApi {
  UserImageApi(this._http);

  final JellyfinHttp _http;

  /// Jellyfin vuole il corpo in base64 e il tipo nel `Content-Type`
  /// (`ImageController.PostUserImage` di 10.11.9, come jellyfin-web).
  Future<void> upload(String userId, ImageUpload image) => _http.post(
        '/UserImage',
        query: {'userId': userId},
        body: base64Encode(image.bytes),
        contentType: image.contentType,
      );

  Future<void> remove(String userId) =>
      _http.delete('/UserImage', query: {'userId': userId});
}

import 'package:wonderflix/core/storage/profile_store.dart';
import 'package:wonderflix/features/auth/profiles_state.dart';

/// `ProfileStore` in memoria.
class MemoryProfileStore implements ProfileStore {
  MemoryProfileStore([this.book = const ProfileBook()]);

  ProfileBook book;
  int writes = 0;

  @override
  Future<ProfileBook> read() async => book;

  @override
  Future<ProfileBook> write(ProfileBook book) async {
    writes++;
    return this.book = book;
  }
}

/// Un profilo di prova: token `tok-<id>` e DeviceId `dev-<id>` se non dati.
StoredProfile testProfile({
  String userId = 'u1',
  String name = 'Mario',
  String? token,
  String? deviceId,
  String? imageTag,
  bool expired = false,
}) =>
    StoredProfile(
      userId: userId,
      name: name,
      accessToken: token ?? 'tok-$userId',
      deviceId: deviceId ?? 'dev-$userId',
      imageTag: imageTag,
      expired: expired,
    );

/// I profili per l'interfaccia, fissi.
class FixedProfiles extends ProfilesController {
  FixedProfiles(this.initial);

  final ProfilesState initial;

  @override
  ProfilesState build() => initial;
}

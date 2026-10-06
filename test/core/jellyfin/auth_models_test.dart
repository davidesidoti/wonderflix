import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/auth_models.dart';

void main() {
  JellyfinUser user(Object? access) => JellyfinUser.fromJson({
        'Id': 'u1',
        'Name': 'Mario',
        if (access != null) 'Policy': {'SyncPlayAccess': access},
      });

  test('SyncPlayAccess dalla policy dell\'utente', () {
    expect(user('CreateAndJoinGroups').syncPlayAccess,
        SyncPlayAccess.createAndJoin);
    expect(user('JoinGroups').syncPlayAccess, SyncPlayAccess.joinOnly);
    expect(user('None').syncPlayAccess, SyncPlayAccess.none);
  });

  test('senza policy o con un valore sconosciuto: accesso completo', () {
    expect(user(null).syncPlayAccess, SyncPlayAccess.createAndJoin);
    expect(user('Boh').syncPlayAccess, SyncPlayAccess.createAndJoin);
    expect(const JellyfinUser(id: 'u1', name: 'Mario').syncPlayAccess,
        SyncPlayAccess.createAndJoin);
  });

  test('cosa permette ciascun valore', () {
    expect(SyncPlayAccess.createAndJoin.canCreate, isTrue);
    expect(SyncPlayAccess.createAndJoin.canJoin, isTrue);
    expect(SyncPlayAccess.joinOnly.canCreate, isFalse);
    expect(SyncPlayAccess.joinOnly.canJoin, isTrue);
    expect(SyncPlayAccess.none.canCreate, isFalse);
    expect(SyncPlayAccess.none.canJoin, isFalse);
  });

  test('IsAdministrator dalla policy: vero, falso o assente', () {
    JellyfinUser admin(Object? value) => JellyfinUser.fromJson({
          'Id': 'u1',
          'Name': 'Mario',
          'Policy': {'IsAdministrator': ?value},
        });

    expect(admin(true).isAdministrator, isTrue);
    expect(admin(false).isAdministrator, isFalse);
    expect(admin(null).isAdministrator, isFalse);
    expect(admin('true').isAdministrator, isFalse,
        reason: 'solo un booleano vero');
    expect(JellyfinUser.fromJson({'Id': 'u1', 'Name': 'Mario'}).isAdministrator,
        isFalse);
    expect(const JellyfinUser(id: 'u1', name: 'Mario').isAdministrator, isFalse);
  });

  test('due utenti con gli stessi campi sono uguali', () {
    JellyfinUser build({
      String id = 'u1',
      String name = 'Mario',
      String? tag = 'tag1',
      SyncPlayAccess access = SyncPlayAccess.joinOnly,
      bool admin = true,
    }) =>
        JellyfinUser(
          id: id,
          name: name,
          primaryImageTag: tag,
          syncPlayAccess: access,
          isAdministrator: admin,
        );

    final user = build();
    expect(build(), user);
    expect(build().hashCode, user.hashCode);
    expect(build(id: 'u2'), isNot(user));
    expect(build(name: 'Luigi'), isNot(user));
    expect(build(tag: null), isNot(user));
    expect(build(tag: 'tag2'), isNot(user));
    expect(build(access: SyncPlayAccess.none), isNot(user));
    expect(build(admin: false), isNot(user));
  });
}

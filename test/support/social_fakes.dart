import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/misc.dart';
import 'package:wonderflix/core/jellyfin/server_events.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/core/social/social_models.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';
import 'package:wonderflix/features/watch_party/watch_party_providers.dart';

import 'fake_session_controller.dart';
import 'test_data.dart';

/// Plugin finto per gli amici. Di default è assente ([info] lancia 404).
class FakeSocialApi implements SocialApi {
  /// Risposta di [info]; `null` = plugin assente (404).
  SocialPluginInfo? pluginInfo;

  /// Errore di [info], se valorizzato (prima di [pluginInfo]).
  SocialFailure? infoFailure;

  FriendsSnapshot snapshot = FriendsSnapshot.empty;

  /// Risultati di [search], per testo cercato.
  final searchResults = <String, List<UserSearchResult>>{};

  /// Errore della prossima chiamata (tranne [info]); poi si azzera.
  SocialFailure? nextFailure;

  /// Se valorizzato, [info], [friends] e [search] aspettano che si completi
  /// (la risposta è quella del momento della chiamata).
  Completer<void>? infoGate;
  Completer<void>? friendsGate;
  Completer<void>? searchGate;

  /// Chiamate in ordine: `info`, `friends`, `search lui`, `request u2`, …
  final calls = <String>[];

  /// Plugin presente con [features].
  void install({Set<String> features = const {PluginFeatures.friends}}) =>
      pluginInfo = SocialPluginInfo(version: '1.1.0', features: features);

  void _fail() {
    final failure = nextFailure;
    if (failure == null) return;
    nextFailure = null;
    throw SocialException(failure);
  }

  @override
  Future<SocialPluginInfo> info() async {
    calls.add('info');
    final failure = infoFailure;
    final info = pluginInfo;
    await infoGate?.future;
    if (failure != null) throw SocialException(failure);
    if (info == null) {
      throw const SocialException(SocialFailure.unavailable);
    }
    return info;
  }

  @override
  Future<FriendsSnapshot> friends() async {
    calls.add('friends');
    // Come la risposta vera, un oggetto nuovo a ogni chiamata (chi
    // confronta gli snapshot se ne accorge anche se il contenuto è uguale).
    final result = FriendsSnapshot(
      friends: snapshot.friends,
      incoming: snapshot.incoming,
      outgoing: snapshot.outgoing,
    );
    await friendsGate?.future;
    _fail();
    return result;
  }

  @override
  Future<List<UserSearchResult>> search(String query) async {
    calls.add('search $query');
    final result = searchResults[query] ?? const <UserSearchResult>[];
    await searchGate?.future;
    _fail();
    return result;
  }

  @override
  Future<void> request(String userId) async {
    calls.add('request $userId');
    _fail();
  }

  @override
  Future<void> accept(String userId) async {
    calls.add('accept $userId');
    _fail();
  }

  @override
  Future<void> decline(String userId) async {
    calls.add('decline $userId');
    _fail();
  }

  @override
  Future<void> cancel(String userId) async {
    calls.add('cancel $userId');
    _fail();
  }

  @override
  Future<void> remove(String userId) async {
    calls.add('remove $userId');
    _fail();
  }
}

/// Funzioni del plugin fisse, senza chiamate.
class FakeSocialAvailability extends SocialAvailability {
  FakeSocialAvailability([this.initial = const SocialFeatures(friends: true)]);

  final SocialFeatures initial;

  @override
  SocialFeatures build() => initial;

  @override
  Future<void> refresh() async {}

  void set(SocialFeatures features) => state = features;
}

FriendEntry testFriend(String userId, String name, {bool online = false}) =>
    FriendEntry(userId: userId, name: name, online: online);

PersonEntry testPerson(String userId, String name) =>
    PersonEntry(userId: userId, name: name);

UserSearchResult testSearchResult(String userId, String name,
        [FriendRelation relation = FriendRelation.none]) =>
    UserSearchResult(userId: userId, name: name, relation: relation);

/// Come arriva dal WebSocket una richiesta di amicizia.
PartyChannelReceived friendRequestReceived(String userId, String name) =>
    PartyChannelReceived(jsonEncode({
      'Protocol': 1,
      'Type': 'FriendRequest',
      'FromUserId': userId,
      'FromName': name,
    }));

PartyChannelReceived friendsChangedReceived() => PartyChannelReceived(
    jsonEncode({'Protocol': 1, 'Type': 'FriendsChanged'}));

/// Provider per i test degli amici: utente [testUser] collegato, eventi del
/// WebSocket da [events], plugin [api], funzioni [features]. Con
/// `session: false` la sessione la sovrascrive il test (es. `AppShell`).
List<Override> socialTestOverrides(
  FakeSocialApi api, {
  Stream<ServerEvent> events = const Stream.empty(),
  SocialFeatures features = const SocialFeatures(friends: true),
  bool session = true,
}) =>
    [
      if (session)
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
      watchPartyEventsProvider.overrideWithValue(events),
      socialApiProvider.overrideWithValue(api),
      socialAvailabilityProvider
          .overrideWith(() => FakeSocialAvailability(features)),
    ];

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/profile_store.dart';

/// I profili del PC e quello attivo, per l'interfaccia e le preferenze (spec
/// K §9). Li aggiorna `SessionController` a ogni cambio: chi li legge non
/// crea il controller della sessione.
class ProfilesState {
  const ProfilesState({this.book = const ProfileBook(), this.activeUserId});

  final ProfileBook book;

  /// Il profilo aperto; `null` in "Chi guarda?" e nell'accesso.
  final String? activeUserId;

  /// Il profilo di cui valgono le preferenze (spec K §9.6): quello aperto,
  /// altrimenti l'ultimo usato (la lingua di "Chi guarda?", spec K §9.4).
  String? get preferenceUserId => activeUserId ?? book.lastUserId;
}

class ProfilesController extends Notifier<ProfilesState> {
  @override
  ProfilesState build() => const ProfilesState();

  void set(ProfilesState next) => state = next;
}

final profilesProvider =
    NotifierProvider<ProfilesController, ProfilesState>(ProfilesController.new);

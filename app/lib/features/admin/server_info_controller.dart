import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/admin_models.dart';
import '../auth/session_controller.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';

/// Le informazioni del server, rilette ogni 60 s (spec J §9.2). A ogni
/// lettura (all'apertura della pagina e ogni 60 s) rilegge anche l'utente:
/// le letture della pagina non chiedono di essere admin e non danno 403, e
/// chi perde i permessi va scoperto così (spec J §12).
class ServerInfoController extends AdminTabController<ServerInfo> {
  static const every = Duration(seconds: 60);

  @override
  Duration get interval => every;

  @override
  Future<ServerInfo> fetch() {
    unawaited(ref.read(sessionControllerProvider.notifier).refreshUser());
    return ref.read(adminApiProvider).serverInfo();
  }
}

final serverInfoControllerProvider =
    NotifierProvider.autoDispose<ServerInfoController, AdminData<ServerInfo>>(
        ServerInfoController.new);

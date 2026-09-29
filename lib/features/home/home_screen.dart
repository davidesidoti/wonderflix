import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../auth/session_controller.dart';

/// Home provvisoria: il Piano 2 la sostituisce con righe e catalogo.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final name = session is SessionSignedIn ? session.user.name : '';
    return Center(
      child: Text(AppLocalizations.of(context).homeWelcome(name),
          style: WfText.display(56)),
    );
  }
}

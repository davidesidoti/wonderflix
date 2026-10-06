import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_dialog.dart';
import 'admin_providers.dart';
import 'session_labels.dart';

/// Chiede conferma del riavvio (spec J §9.2); `true` solo con "Riavvia".
Future<bool> showRestartDialog(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final confirmed = await showWfDialog<bool>(
    context,
    semanticLabel: l.adminRestartTitle,
    builder: (_) => const RestartDialog(),
  );
  return confirmed ?? false;
}

/// La conferma del riavvio: all'apertura rilegge le sessioni e dice chi sta
/// guardando, così i dati sono freschi.
class RestartDialog extends ConsumerStatefulWidget {
  const RestartDialog({super.key});

  @override
  ConsumerState<RestartDialog> createState() => _RestartDialogState();
}

class _RestartDialogState extends ConsumerState<RestartDialog> {
  late final Future<List<SessionEntry>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = ref.read(adminApiProvider).sessions();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.adminRestartTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        FutureBuilder<List<SessionEntry>>(
          future: _sessions,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2));
            }
            final sessions = snapshot.data;
            if (sessions == null) return Text(l.adminRestartUnknown);
            final viewers = [
              for (final session in sessions)
                if (session.nowPlaying != null) session,
            ];
            if (viewers.isEmpty) return Text(l.adminRestartNobody);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.adminRestartViewers(viewers.length)),
                const SizedBox(height: 8),
                for (final viewer in viewers)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text(
                        l.adminViewer(viewer.userName,
                            nowPlayingTitle(l, viewer.nowPlaying!)),
                        style: const TextStyle(color: WfColors.creamMuted)),
                  ),
                const SizedBox(height: 8),
                Text(l.adminRestartInterrupts),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.adminCancel),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: WfColors.error,
                foregroundColor: WfColors.cream,
                // Il tema chiede la larghezza piena: in una riga non entra.
                minimumSize: const Size(0, 44),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.adminRestart),
            ),
          ],
        ),
      ],
    );
  }
}

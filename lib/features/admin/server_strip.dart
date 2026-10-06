import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../auth/session_controller.dart';
import 'admin_providers.dart';
import 'admin_tab_controller.dart';
import 'admin_widgets.dart';
import 'restart_controller.dart';
import 'restart_dialog.dart';

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

/// La striscia in cima alla pagina Amministrazione: nome e versione del
/// server, "Riavvio necessario" e Riavvia.
class ServerStrip extends ConsumerWidget {
  const ServerStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(serverInfoControllerProvider);
    final info = data.value;
    final error = data.error;
    final updatedAt = data.updatedAt;
    final Widget title;
    if (info != null) {
      final os = info.operatingSystem;
      title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(info.name.isEmpty ? 'Jellyfin' : info.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          Text(
              os == null
                  ? l.adminServerVersion(info.version)
                  : l.adminServerVersionOs(info.version, os),
              style: const TextStyle(color: WfColors.creamMuted)),
        ],
      );
    } else if (error != null) {
      title = Row(
        children: [
          Flexible(
            child: Text(describeError(l, error),
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => unawaited(
                ref.read(serverInfoControllerProvider.notifier).refresh()),
            child: Text(l.retry),
          ),
        ],
      );
    } else {
      title = const Align(
          alignment: Alignment.centerLeft,
          child: SkeletonBox(width: 220, height: 20));
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WfColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WfColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.server, color: WfColors.gold),
              const SizedBox(width: 12),
              Expanded(child: title),
              const SizedBox(width: 16),
              const RestartArea(),
            ],
          ),
          if (info?.hasPendingRestart ?? false) ...[
            const SizedBox(height: 12),
            Row(
              key: const Key('pending-restart'),
              children: [
                const Icon(LucideIcons.triangleAlert,
                    size: 16, color: WfColors.gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${l.adminPendingRestart}: ',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: l.adminPendingRestartHint),
                  ])),
                ),
              ],
            ),
          ],
          if (data.stale && updatedAt != null) AdminStaleNote(updatedAt: updatedAt),
        ],
      ),
    );
  }
}

/// Riavvia, l'attesa del ritorno, oppure "non risponde ancora" con
/// Ricontrolla.
class RestartArea extends ConsumerWidget {
  const RestartArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return switch (ref.watch(restartControllerProvider)) {
      RestartPhase.idle => WfButton.secondary(
          label: l.adminRestart,
          icon: LucideIcons.rotateCw,
          onPressed: () => unawaited(_restart(context, ref)),
        ),
      RestartPhase.sending || RestartPhase.waiting => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
                dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(l.adminRestarting),
          ],
        ),
      RestartPhase.timedOut => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.adminRestartTimedOut,
                style: const TextStyle(color: WfColors.gold)),
            const SizedBox(width: 12),
            WfButton.secondary(
              label: l.adminRestartRecheck,
              icon: LucideIcons.refreshCw,
              onPressed: () => unawaited(_report(context,
                  ref.read(restartControllerProvider.notifier).recheck())),
            ),
          ],
        ),
    };
  }

  Future<void> _restart(BuildContext context, WidgetRef ref) async {
    final confirmed = await showRestartDialog(context);
    if (!confirmed || !context.mounted) return;
    await _report(
        context, ref.read(restartControllerProvider.notifier).restart());
  }

  /// L'avviso alla fine: "Jellyfin è tornato" o "Riavvio non riuscito". Il
  /// tempo scaduto si vede nella striscia; una pagina chiusa non avvisa.
  Future<void> _report(
      BuildContext context, Future<RestartOutcome> pending) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final text = switch (await pending) {
      RestartOutcome.back => l.adminRestartBack,
      RestartOutcome.failed => l.adminRestartFailed,
      RestartOutcome.timedOut || RestartOutcome.cancelled => null,
    };
    if (text != null) messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}

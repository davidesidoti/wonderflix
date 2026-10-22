import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';
import 'session_labels.dart';
import 'sessions_controller.dart';

/// La scheda Sessioni (spec J §9.3): chi guarda, chi è collegato, i watch
/// party.
class SessionsTab extends ConsumerStatefulWidget {
  const SessionsTab({super.key});

  @override
  ConsumerState<SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends ConsumerState<SessionsTab> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(sessionsControllerProvider);
    final snapshot = data.value;
    if (snapshot == null) {
      final error = data.error;
      if (error == null) return const LoadingView();
      return ErrorView(
        error: error,
        onRetry: () =>
            unawaited(ref.read(sessionsControllerProvider.notifier).refresh()),
      );
    }
    final now = clock.now();
    final updatedAt = data.updatedAt;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      children: [
        if (data.stale && updatedAt != null) AdminStaleNote(updatedAt: updatedAt),
        AdminSectionTitle(title: l.adminSessionsPlaying),
        if (snapshot.playing.isEmpty)
          AdminEmptyText(text: l.adminSessionsNobodyPlaying)
        else
          for (final session in snapshot.playing)
            PlayingSessionCard(
                key: ValueKey('playing-${session.id}'), session: session),
        AdminSectionTitle(title: l.adminSessionsIdle),
        if (snapshot.idle.isEmpty)
          AdminEmptyText(text: l.adminSessionsNobodyIdle)
        else
          for (final session in snapshot.idle)
            IdleSessionRow(
                key: ValueKey('idle-${session.id}'), session: session, now: now),
        AdminSectionTitle(title: l.adminSessionsParties),
        if (snapshot.parties.isEmpty)
          AdminEmptyText(text: l.adminSessionsNoParties)
        else
          for (final party in snapshot.parties)
            PartyRow(key: ValueKey('party-${party.id}'), party: party),
      ],
    );
  }
}

/// Una sessione che sta riproducendo: locandina, utente, titolo,
/// avanzamento e metodo.
class PlayingSessionCard extends ConsumerWidget {
  const PlayingSessionCard({super.key, required this.session});

  static const posterWidth = 64.0;
  static const posterHeight = 96.0;

  /// Larghezza della locandina chiesta al server (il doppio, per gli schermi
  /// ad alta densità).
  static const _posterRequestWidth = 128;

  final SessionEntry session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final item = session.nowPlaying!;
    final position = session.position;
    // Una durata a zero (Jellyfin la dà così quando non la conosce) vale
    // come nessuna durata.
    final runtime = switch (item.runtime) {
      final value? when value > Duration.zero => value,
      _ => null,
    };
    final progress = runtime == null
        ? 0.0
        : (position.inMilliseconds / runtime.inMilliseconds).clamp(0.0, 1.0);
    final method = displayMethod(session);
    final methodLabel = displayMethodLabel(l, method);
    final transcode =
        method == DisplayMethod.transcode ? session.transcode : null;
    final transcodeText =
        transcode == null ? null : transcodeLine(l, transcode);
    final reasonsText = transcode == null || transcode.reasons.isEmpty
        ? null
        : transcodeReasons(l, transcode.reasons);
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WfColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WfColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: posterWidth,
              height: posterHeight,
              child: WfImage(
                image: ref.watch(imageUrlsProvider).primaryOf(item.imageItemId,
                    maxWidth: _posterRequestWidth),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminUserLine(
                    name: session.userName,
                    detail: sessionDevice(session),
                    userId: session.userId,
                    imageTag: session.userImageTag),
                const SizedBox(height: 8),
                Text(nowPlayingTitle(l, item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (session.isPaused) ...[
                      Icon(LucideIcons.pause,
                          key: Key('session-paused-${session.id}'),
                          size: 14,
                          color: WfColors.creamMuted),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        color: WfColors.gold,
                        backgroundColor: WfColors.surfaceHigh,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                        runtime == null
                            ? formatClock(position)
                            : '${formatClock(position)} / ${formatClock(runtime)}',
                        style: muted),
                  ],
                ),
                if (methodLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(methodLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: method == DisplayMethod.transcode
                            ? WfColors.gold
                            : WfColors.cream,
                      )),
                ],
                if (transcodeText != null || reasonsText != null) ...[
                  const SizedBox(height: 4),
                  if (transcodeText != null) Text(transcodeText, style: muted),
                  if (reasonsText != null) Text(reasonsText, style: muted),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una sessione collegata senza riprodurre.
class IdleSessionRow extends StatelessWidget {
  const IdleSessionRow({super.key, required this.session, required this.now});

  final SessionEntry session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final last = session.lastActivity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: AdminUserLine(
                name: session.userName,
                detail: sessionDevice(session),
                userId: session.userId,
                imageTag: session.userImageTag),
          ),
          if (last != null)
            Text(l.adminActive(adminTimeLabel(last, now, l)),
                style: const TextStyle(color: WfColors.creamMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

/// Un watch party in corso: nome, stato e partecipanti.
class PartyRow extends StatelessWidget {
  const PartyRow({super.key, required this.party});

  final PartyGroup party;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = partyStateLabel(l, party.state);
    const muted = TextStyle(color: WfColors.creamMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(LucideIcons.users, size: 18, color: WfColors.gold),
          const SizedBox(width: 10),
          Flexible(
            child: Text(party.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (state != null) ...[
            const SizedBox(width: 10),
            Text(state, style: muted),
          ],
          const SizedBox(width: 16),
          Expanded(
            child: Text(party.participants.join(', '),
                overflow: TextOverflow.ellipsis, style: muted),
          ),
        ],
      ),
    );
  }
}

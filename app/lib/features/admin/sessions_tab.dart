import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'admin_kit.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';
import 'session_labels.dart';
import 'sessions_controller.dart';

/// La scheda Sessioni (spec J §9.3): chi guarda, chi è collegato, i watch
/// party.
class SessionsTab extends ConsumerStatefulWidget {
  const SessionsTab({super.key, this.header});

  /// La striscia del server, nel layout stretto: scorre con l'elenco.
  final Widget? header;

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
      if (error == null) {
        return adminTabState(context, widget.header, const LoadingView());
      }
      return adminTabState(
        context,
        widget.header,
        ErrorView(
          error: error,
          onRetry: () => unawaited(
              ref.read(sessionsControllerProvider.notifier).refresh()),
        ),
      );
    }
    final now = clock.now();
    final updatedAt = data.updatedAt;
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
          adminSideMargin(context), 0, adminSideMargin(context), 40),
      children: [
        if (widget.header case final header?)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: header),
        if (data.stale && updatedAt != null) AdminStaleNote(updatedAt: updatedAt),
        AdminTabTitle(title: l.adminTabSessions),
        AdminSectionTitle(
            title: l.adminSessionsPlaying, count: snapshot.playing.length),
        if (snapshot.playing.isEmpty)
          AdminEmptyText(text: l.adminSessionsNobodyPlaying)
        else
          // Largo: due sale per riga; stretto: una.
          LayoutBuilder(builder: (context, constraints) {
            final width = FormFactor.of(context).compact
                ? constraints.maxWidth
                : (constraints.maxWidth - 14) / 2;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final (index, session) in snapshot.playing.indexed)
                  SizedBox(
                    width: width,
                    child: PlayingSessionCard(
                        key: ValueKey('playing-${session.id}'),
                        session: session,
                        number: index + 1),
                  ),
              ],
            );
          }),
        AdminSectionTitle(
            title: l.adminSessionsIdle, count: snapshot.idle.length),
        if (snapshot.idle.isEmpty)
          AdminEmptyText(text: l.adminSessionsNobodyIdle)
        else
          Wrap(
            spacing: 22,
            runSpacing: 8,
            children: [
              for (final session in snapshot.idle)
                IdleSessionRow(
                    key: ValueKey('idle-${session.id}'),
                    session: session,
                    now: now),
            ],
          ),
        AdminSectionTitle(
            title: l.adminSessionsParties, count: snapshot.parties.length),
        if (snapshot.parties.isEmpty)
          AdminEmptyText(text: l.adminSessionsNoParties)
        else
          for (final party in snapshot.parties)
            PartyRow(key: ValueKey('party-${party.id}'), party: party),
      ],
    );
  }
}

/// Una sessione che sta riproducendo: la sala, con lo sfondo del titolo.
class PlayingSessionCard extends ConsumerWidget {
  const PlayingSessionCard(
      {super.key, required this.session, required this.number});

  static const height = 170.0;

  /// "Sala N": l'ordine della sessione nello snapshot, da 1.
  final int number;
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
        ? null
        : (position.inMilliseconds / runtime.inMilliseconds).clamp(0.0, 1.0);
    final method = displayMethod(session);
    final methodLabel = displayMethodLabel(l, method);
    final isTranscode = method == DisplayMethod.transcode;
    final transcode = isTranscode ? session.transcode : null;
    final transcodeText =
        transcode == null ? null : transcodeLine(l, transcode);
    final reasonsText = transcode == null || transcode.reasons.isEmpty
        ? null
        : transcodeReasons(l, transcode.reasons);
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 13);
    Widget oneLine(String text) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
      height: height,
      color: WfColors.surfaceHigh,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WfColors.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          WfImage(
            image: ref.watch(imageUrlsProvider).backdropOf(
                item.seriesId ?? item.itemId,
                maxWidth: 960),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  WfColors.bg.withValues(alpha: 0.95),
                  WfColors.bg.withValues(alpha: 0.95),
                  WfColors.bg.withValues(alpha: 0.2),
                ],
                stops: [0, 0.25, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Row(
                    children: [
                      Text(l.adminSessionsSala(number),
                          style: WfText.display(15, color: WfColors.gold)),
                      const Spacer(),
                      if (session.isPaused) ...[
                        Icon(LucideIcons.pause,
                            key: Key('session-paused-${session.id}'),
                            size: 14,
                            color: WfColors.creamMuted),
                        const SizedBox(width: 8),
                      ],
                      if (methodLabel != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: isTranscode
                                ? WfColors.gold.withValues(alpha: 0.18)
                                : WfColors.cream.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            child: Text(methodLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isTranscode
                                      ? WfColors.gold
                                      : WfColors.cream,
                                )),
                          ),
                        ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(nowPlayingTitle(l, item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WfText.display(26)),
                    const SizedBox(height: 4),
                    AdminUserLine(
                        name: session.userName,
                        detail: sessionDevice(session),
                        userId: session.userId,
                        imageTag: session.userImageTag),
                    const SizedBox(height: 6),
                    FilmStripBar(progress: progress),
                    const SizedBox(height: 4),
                    oneLine(runtime == null
                        ? formatClock(position)
                        : '${formatClock(position)} / ${formatClock(runtime)}'),
                    if (transcodeText != null) oneLine(transcodeText),
                    if (reasonsText != null) oneLine(reasonsText),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Una sessione collegata senza riprodurre: una riga compatta.
class IdleSessionRow extends StatelessWidget {
  const IdleSessionRow({super.key, required this.session, required this.now});

  final SessionEntry session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final last = session.lastActivity;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dentro un Wrap la riga non ha larghezza: la prende dal contenuto.
          Flexible(
            child: IntrinsicWidth(
              child: AdminUserLine(
                  name: session.userName,
                  detail: sessionDevice(session),
                  userId: session.userId,
                  imageTag: session.userImageTag),
            ),
          ),
          if (last != null) ...[
            const SizedBox(width: 10),
            Text(l.adminActive(adminTimeLabel(last, now, l)),
                style: const TextStyle(color: WfColors.creamMuted, fontSize: 13)),
          ],
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/social/recommendation_models.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/rune_limit.dart';
import '../../ui/shell_side_panel.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import '../watch_party/party_badge.dart';

final _log = Logger('social');

/// Amici al massimo in un consiglio: i destinatari sono 30 all'ora (piano
/// 20b, decisione 4).
const recommendMaxRecipients = 30;

/// Lunghezza massima del messaggio (spec N §6.2).
const recommendMessageMax = 200;

/// Il titolo da consigliare (spec N §7.2).
class RecommendSubject {
  const RecommendSubject({required this.itemId, required this.name});

  final String itemId;
  final String name;
}

/// Il titolo del pannello "Consiglia a…": lo imposta chi lo apre.
class RecommendSubjectController extends Notifier<RecommendSubject?> {
  @override
  RecommendSubject? build() => null;

  void set(RecommendSubject? subject) => state = subject;
}

final recommendSubjectProvider =
    NotifierProvider<RecommendSubjectController, RecommendSubject?>(
        RecommendSubjectController.new);

/// Apre il pannello per [subject] (spec N §7.2).
void openRecommendPanel(WidgetRef ref, RecommendSubject subject) {
  ref.read(recommendSubjectProvider.notifier).set(subject);
  ref.read(shellPanelProvider.notifier).open(ShellPanel.recommend);
}

/// Gli amici a cui si può consigliare il titolo, letti all'apertura.
final recommendTargetsProvider = FutureProvider.autoDispose
    .family<List<RecommendationTarget>, String>((ref, itemId) =>
        ref.watch(socialApiProvider).recommendationTargets(itemId));

/// Online prima, poi per nome (come il pannello Amici); chi non può vedere
/// il titolo in fondo.
List<RecommendationTarget> sortTargets(List<RecommendationTarget> targets) =>
    [...targets]..sort((a, b) {
        if (a.canSee != b.canSee) return a.canSee ? -1 : 1;
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 13);

/// Il pannello "Consiglia a…" (spec N §7.2): titolo, amici con la casella,
/// messaggio facoltativo, Invia.
class RecommendPanel extends ConsumerStatefulWidget {
  const RecommendPanel({super.key, required this.subject});

  final RecommendSubject subject;

  /// Lato della locandina in alto (2:3).
  static const posterWidth = 40.0;
  static const posterHeight = 60.0;

  @override
  ConsumerState<RecommendPanel> createState() => _RecommendPanelState();
}

class _RecommendPanelState extends ConsumerState<RecommendPanel> {
  final _message = TextEditingController();
  final _closeFocus = FocusNode(debugLabel: 'recommend-close');
  final _selected = <String>{};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Come negli altri pannelli: `autofocus` nella shell vera non basta.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _closeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _message.dispose();
    _closeFocus.dispose();
    super.dispose();
  }

  void _toggle(String userId) => setState(() {
        if (!_selected.remove(userId) &&
            _selected.length < recommendMaxRecipients) {
          _selected.add(userId);
        }
      });

  Future<void> _send() async {
    if (_sending || _selected.isEmpty) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = _message.text.trim();
    setState(() => _sending = true);
    var notice = l.recommendNotSent;
    var close = false;
    try {
      final sent = await ref.read(socialApiProvider).recommend(
          widget.subject.itemId, _selected.toList(), text.isEmpty ? null : text);
      close = sent > 0;
      notice = sent > 0 ? l.recommendSent(sent) : l.recommendNotSent;
    } on SocialException catch (error) {
      _log.info('consiglio non inviato: ${error.failure.name}');
      notice = error.failure == SocialFailure.rateLimited
          ? l.recommendRateLimited
          : l.recommendNotSent;
    } catch (error) {
      _log.info('consiglio non inviato: ${error.runtimeType}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (close && mounted) ref.read(shellPanelProvider.notifier).close();
    messenger?.showSnackBar(SnackBar(content: Text(notice)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final subject = widget.subject;
    final targets = ref.watch(recommendTargetsProvider(subject.itemId));
    return Material(
      key: const Key('recommend-panel'),
      color: WfColors.surface,
      elevation: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.recommendPanelTitle,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  focusNode: _closeFocus,
                  tooltip: l.friendsClose,
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () => ref.read(shellPanelProvider.notifier).close(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: RecommendPanel.posterWidth,
                    height: RecommendPanel.posterHeight,
                    child: WfImage(
                        image: ref.watch(imageUrlsProvider).primaryOf(subject.itemId)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(subject.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WfColors.cream, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Expanded(
            child: targets.when(
              // Mentre carica il pannello resta vuoto (come gli altri).
              loading: () => const SizedBox.shrink(),
              error: (error, _) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.recommendTargetsError, style: _mutedStyle),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(recommendTargetsProvider(subject.itemId)),
                      style: TextButton.styleFrom(foregroundColor: WfColors.gold),
                      child: Text(l.retry),
                    ),
                  ],
                ),
              ),
              data: (list) => _targets(l, sortTargets(list)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _message,
                  maxLength: recommendMessageMax,
                  inputFormatters: [capRunes(recommendMessageMax)],
                  minLines: 1,
                  maxLines: 3,
                  // Invio non va a capo: il plugin toglie comunque gli a capo.
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                      hintText: l.recommendMessageHint, isDense: true),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: WfButton.primary(
                    label: l.recommendSend,
                    icon: LucideIcons.send,
                    onPressed: _sending || _selected.isEmpty
                        ? null
                        : () => unawaited(_send()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _targets(AppLocalizations l, List<RecommendationTarget> targets) {
    final full = _selected.length >= recommendMaxRecipients;
    if (targets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(l.recommendNoFriends, style: _mutedStyle),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (full)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(l.recommendMaxReached(recommendMaxRecipients),
                style: _mutedStyle),
          ),
        for (final target in targets)
          CheckboxListTile(
            key: ValueKey('recommend-target-${target.userId}'),
            value: _selected.contains(target.userId),
            onChanged: !target.canSee ||
                    (full && !_selected.contains(target.userId))
                ? null
                : (_) => _toggle(target.userId),
            controlAffinity: ListTileControlAffinity.trailing,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            secondary: Stack(
              clipBehavior: Clip.none,
              children: [
                MemberAvatar(name: target.name, userId: target.userId),
                if (target.online)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: WfColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: WfColors.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(target.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: target.canSee ? WfColors.cream : WfColors.creamMuted)),
            subtitle: target.canSee
                ? null
                : Text(l.recommendCannotSee,
                    style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
          ),
      ],
    );
  }
}

/// Il pannello si vede: aperto, con la funzione e un titolo.
final recommendPanelVisibleProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(shellPanelProvider) == ShellPanel.recommend &&
    ref.watch(socialAvailabilityProvider.select((f) => f.recommendations)) &&
    ref.watch(recommendSubjectProvider) != null);

/// Pannello "Consiglia a…" sopra la shell e la barra, nel contenitore comune
/// dei pannelli laterali (spec N §7.2).
class RecommendPanelHost extends ConsumerWidget {
  const RecommendPanelHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Funzione sparita a pannello aperto: si chiude davvero.
    ref.listen(recommendPanelVisibleProvider, (_, visible) {
      if (!visible && ref.read(shellPanelProvider) == ShellPanel.recommend) {
        ref.read(shellPanelProvider.notifier).close();
      }
    });
    final subject = ref.watch(recommendSubjectProvider);
    return ShellSidePanel(
      open: ref.watch(recommendPanelVisibleProvider),
      onClose: () => ref.read(shellPanelProvider.notifier).close(),
      scrimKey: const Key('recommend-panel-scrim'),
      child: subject == null
          ? const SizedBox.shrink()
          // Un titolo nuovo: un pannello nuovo (scelte e messaggio vuoti).
          : RecommendPanel(key: ValueKey(subject.itemId), subject: subject),
    );
  }
}

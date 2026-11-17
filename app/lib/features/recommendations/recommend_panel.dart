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
import '../../ui/form_factor.dart';
import '../../ui/rune_limit.dart';
import '../../ui/panel_header.dart';
import '../../ui/shell_side_panel.dart';
import '../../ui/skeletons.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/tv_text_field_frame.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';

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
void openRecommendPanel(
    BuildContext context, WidgetRef ref, RecommendSubject subject) {
  ref.read(recommendSubjectProvider.notifier).set(subject);
  openShellPanel(context, ref, ShellPanel.recommend);
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
  final _messageFocus = FocusNode(debugLabel: 'recommend-message');
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'recommend-search');
  final _firstTarget = FocusNode(debugLabel: 'recommend-first-target');
  final _selected = <String>{};
  bool _sending = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    // Come negli altri pannelli: `autofocus` nella shell vera non basta.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focused = _focusStart();
    });
  }

  /// L'elenco arriva dopo l'apertura: il fuoco passa al primo amico.
  void _retryFocus() {
    if (_focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focused) _focused = _focusStart();
    });
  }

  /// Come [focusPanelStart], ma dove partirebbe dal primo controllo parte
  /// dal primo amico: sopra la griglia c'è "Scegli gli online".
  bool _focusStart() {
    final form = FormFactor.of(context);
    if ((form.tv || (form.compact && !form.touch)) &&
        _firstTarget.context != null) {
      _firstTarget.requestFocus();
      return true;
    }
    return focusPanelStart(context, _closeFocus);
  }

  @override
  void dispose() {
    _message.dispose();
    _closeFocus.dispose();
    _messageFocus.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _firstTarget.dispose();
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
    _retryFocus();
    return Material(
      key: const Key('recommend-panel'),
      color: WfColors.surface,
      elevation: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            title: l.recommendPanelTitle,
            closeTooltip: l.friendsClose,
            closeFocusNode: _closeFocus,
            onClose: () => ref.read(shellPanelProvider.notifier).close(),
            subtitle: Row(
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
              loading: () => const PanelRowsSkeleton(),
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
                TvTextFieldFrame(
                  focusNode: _messageFocus,
                  child: TextField(
                    controller: _message,
                    focusNode: _messageFocus,
                    maxLength: recommendMessageMax,
                    inputFormatters: [capRunes(recommendMessageMax)],
                    minLines: 1,
                    maxLines: 3,
                    // Invio non va a capo: il plugin toglie comunque gli a capo.
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                        hintText: l.recommendMessageHint, isDense: true),
                    // Il conto solo quando mancano 20 caratteri o meno.
                    buildCounter: (context,
                            {required currentLength,
                            required isFocused,
                            required maxLength}) =>
                        maxLength! - currentLength > 20
                            ? null
                            : Text('$currentLength/$maxLength',
                                style: const TextStyle(
                                    color: WfColors.creamMuted,
                                    fontSize: 12,
                                    fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: WfButton.primary(
                    label: l.recommendSendTo(_selected.length),
                    icon: LucideIcons.send,
                    onPressed: _sending || _selected.isEmpty
                        ? null
                        : () => unawaited(_send()),
                  ),
                ),
                if (_selected.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text(l.recommendPickOne,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 12.5)),
                ],
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
    final query = _search.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? targets
        : [
            for (final t in targets)
              if (t.name.toLowerCase().contains(query)) t
          ];
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TvTextFieldFrame(
                  focusNode: _searchFocus,
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l.recommendSearchHint,
                      isDense: true,
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('recommend-pick-online'),
                onPressed: () => _pickOnline(shown),
                style: TextButton.styleFrom(foregroundColor: WfColors.gold),
                child: Text(l.recommendPickOnline),
              ),
            ],
          ),
        ),
        if (full)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(l.recommendMaxReached(recommendMaxRecipients),
                style: _mutedStyle),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 88,
              // Avatar e margini fissi, nome e stato crescono col testo.
              mainAxisExtent: 70 + scaler.scale(13) * 1.3 + scaler.scale(11.5) * 1.3,
            ),
            itemCount: shown.length,
            itemBuilder: (context, i) => _cell(l, shown[i], full,
                focusNode: i == 0 && shown[i].canSee ? _firstTarget : null),
          ),
        ),
      ],
    );
  }

  /// Accende gli online che possono vederlo, fino al limite.
  void _pickOnline(List<RecommendationTarget> shown) => setState(() {
        for (final t in shown) {
          if (_selected.length >= recommendMaxRecipients) break;
          if (t.online && t.canSee) _selected.add(t.userId);
        }
      });

  Widget _cell(AppLocalizations l, RecommendationTarget target, bool full,
      {FocusNode? focusNode}) {
    final selected = _selected.contains(target.userId);
    final enabled = target.canSee && (selected || !full);
    final status = !target.canSee
        ? l.recommendCannotSee
        : (target.online ? l.friendsOnline : l.friendsOffline);
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      label: target.name,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: TvFocusBorder(
          child: InkWell(
            key: ValueKey('recommend-target-${target.userId}'),
            focusNode: focusNode,
            borderRadius: BorderRadius.circular(6),
            onTap: enabled ? () => _toggle(target.userId) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
              child: Column(
                children: [
                  SizedBox.square(
                    dimension: 52,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: selected ? WfColors.gold : Colors.transparent,
                                width: 2),
                          ),
                          alignment: Alignment.center,
                          child: UserAvatar.lookup(
                              userId: target.userId,
                              name: target.name,
                              size: 48,
                              muted: true),
                        ),
                        if (selected)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              key: ValueKey('recommend-check-${target.userId}'),
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                  color: WfColors.gold, shape: BoxShape.circle),
                              child: const Icon(LucideIcons.check,
                                  size: 12, color: WfColors.bg),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ExcludeSemantics(
                    child: Text(target.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: WfColors.cream, fontSize: 13, height: 1.3)),
                  ),
                  Text(status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: target.online && target.canSee
                              ? WfColors.online
                              : WfColors.creamMuted,
                          fontSize: 11.5,
                          height: 1.3)),
                ],
              ),
            ),
          ),
        ),
      ),
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
    // Nel layout stretto il pannello è una pagina ([ShellPanelPage]).
    if (FormFactor.of(context).compact) return const SizedBox.shrink();
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

/// Il pannello come pagina nel layout stretto. Senza titolo (pagina
/// ricaricata) la rotta torna alla Home prima di arrivare qui.
class RecommendPanelPage extends ConsumerWidget {
  const RecommendPanelPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(recommendSubjectProvider);
    return ShellPanelPage(
      panel: ShellPanel.recommend,
      child: subject == null
          ? const SizedBox.shrink()
          : RecommendPanel(key: ValueKey(subject.itemId), subject: subject),
    );
  }
}

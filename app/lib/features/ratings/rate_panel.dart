import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/rating_models.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/shell_side_panel.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../social/social_providers.dart';
import 'friend_ratings_row.dart';
import 'rating_widgets.dart';

final _log = Logger('ratings');

/// Il titolo da votare dalla scheda (spec Q §7.1): [title] è il nome mostrato
/// ("Serie · Stagione 2" per una stagione), [mine] il voto di adesso.
class RateSubject {
  const RateSubject({required this.item, required this.title, this.mine});

  final JellyfinItem item;
  final String title;
  final MyRating? mine;
}

/// Il titolo del pannello del voto: lo imposta chi lo apre.
class RateSubjectController extends Notifier<RateSubject?> {
  @override
  RateSubject? build() => null;

  void set(RateSubject? subject) => state = subject;
}

final rateSubjectProvider =
    NotifierProvider<RateSubjectController, RateSubject?>(
        RateSubjectController.new);

/// Apre il pannello del voto per [subject].
void openRatePanel(BuildContext context, WidgetRef ref, RateSubject subject) {
  ref.read(rateSubjectProvider.notifier).set(subject);
  openShellPanel(context, ref, ShellPanel.rate);
}

/// Locandina (2:3) in alto.
const _posterWidth = 80.0;
const _posterHeight = 120.0;

/// Il pannello per votare dalla scheda: numeri, commento, Salva e, se c'è
/// già un voto, "Togli il mio voto".
class RatePanel extends ConsumerStatefulWidget {
  const RatePanel({super.key, required this.subject});

  final RateSubject subject;

  @override
  ConsumerState<RatePanel> createState() => _RatePanelState();
}

class _RatePanelState extends ConsumerState<RatePanel> {
  late final _comment =
      TextEditingController(text: widget.subject.mine?.comment ?? '');
  final _closeFocus = FocusNode(debugLabel: 'rate-close');
  late int? _score = widget.subject.mine?.score;
  bool _busy = false;
  String? _error;

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
    _comment.dispose();
    _closeFocus.dispose();
    super.dispose();
  }

  /// Salva o toglie il voto: una sola chiamata alla volta. Riuscito, chiude il
  /// pannello e rilegge i voti; altrimenti il motivo resta nel pannello.
  Future<void> _run(Future<void> Function(SocialApi api) call) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final ref = this.ref;
    final itemId = widget.subject.item.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call(ref.read(socialApiProvider));
      if (!mounted) return;
      ref.read(shellPanelProvider.notifier).close();
      ref.invalidate(itemRatingsProvider(itemId));
      return;
    } on SocialException catch (error) {
      _log.info('voto non salvato: ${error.failure.name}');
      _error = error.failure == SocialFailure.rateLimited
          ? l.ratingTooMany
          : l.ratingNotSaved;
    } catch (error) {
      _log.info('voto non salvato: ${error.runtimeType}');
      _error = l.ratingNotSaved;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final subject = widget.subject;
    final score = _score;
    return Material(
      key: const Key('rate-panel'),
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
                  child: Text(l.ratingYourVote,
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: _posterWidth,
                    height: _posterHeight,
                    child: WfImage(
                        image: ref.watch(imageUrlsProvider).poster(subject.item)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(subject.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WfColors.cream, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: RatingScorePicker(
              selected: score,
              enabled: !_busy,
              onSelect: (n) => setState(() => _score = n),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: RatingCommentField(
              controller: _comment,
              onSubmitted: score == null || _busy ? null : _save,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(_error!,
                  style: const TextStyle(color: WfColors.error, fontSize: 13)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: WfButton.primary(
                label: l.ratingSave,
                icon: LucideIcons.check,
                onPressed: score == null || _busy ? null : _save,
              ),
            ),
          ),
          if (subject.mine != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: WfButton.secondary(
                  label: l.ratingRemove,
                  icon: LucideIcons.trash2,
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          _run((api) => api.deleteRating(subject.item.id))),
                ),
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }

  void _save() {
    final score = _score;
    if (score == null) return;
    final text = _comment.text.trim();
    unawaited(_run((api) =>
        api.rate(widget.subject.item.id, score, text.isEmpty ? null : text)));
  }
}

/// Il pannello si vede: aperto, con la funzione e un titolo.
final ratePanelVisibleProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(shellPanelProvider) == ShellPanel.rate &&
    ref.watch(socialAvailabilityProvider.select((f) => f.ratings)) &&
    ref.watch(rateSubjectProvider) != null);

/// Pannello del voto sopra la shell e la barra, nel contenitore comune dei
/// pannelli laterali.
class RatePanelHost extends ConsumerWidget {
  const RatePanelHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Funzione sparita a pannello aperto: si chiude davvero.
    ref.listen(ratePanelVisibleProvider, (_, visible) {
      if (!visible && ref.read(shellPanelProvider) == ShellPanel.rate) {
        ref.read(shellPanelProvider.notifier).close();
      }
    });
    // Nel layout stretto il pannello è una pagina ([ShellPanelPage]).
    if (FormFactor.of(context).compact) return const SizedBox.shrink();
    final subject = ref.watch(rateSubjectProvider);
    return ShellSidePanel(
      open: ref.watch(ratePanelVisibleProvider),
      onClose: () => ref.read(shellPanelProvider.notifier).close(),
      scrimKey: const Key('rate-panel-scrim'),
      child: subject == null
          ? const SizedBox.shrink()
          // Un titolo nuovo: un pannello nuovo (voto e commento da capo).
          : RatePanel(key: ValueKey(subject.item.id), subject: subject),
    );
  }
}

/// Il pannello come pagina nel layout stretto. Senza titolo (pagina
/// ricaricata) la rotta torna alla Home prima di arrivare qui.
class RatePanelPage extends ConsumerWidget {
  const RatePanelPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(rateSubjectProvider);
    return ShellPanelPage(
      panel: ShellPanel.rate,
      child: subject == null
          ? const SizedBox.shrink()
          : RatePanel(key: ValueKey(subject.item.id), subject: subject),
    );
  }
}

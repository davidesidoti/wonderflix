import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';

/// Quanto resta in vista "È un match!" se nessuno lo chiude prima.
const matchCelebrationDuration = Duration(seconds: 2);

/// Larghezza della locandina nello strato.
const _posterWidth = 220.0;

/// Lo strato "È un match!" (spec P §7.3): la locandina e il testo in oro.
/// Dopo [matchCelebrationDuration], o a un tasto o un clic, chiama [onDone]
/// una volta sola.
class MatchCelebration extends ConsumerStatefulWidget {
  const MatchCelebration(
      {super.key, required this.id, required this.item, required this.onDone});

  /// L'id del match: dà la chiave anche se il titolo non è ancora arrivato.
  final String id;

  /// `null` = titolo non più disponibile: resta il solo testo.
  final JellyfinItem? item;
  final VoidCallback onDone;

  @override
  ConsumerState<MatchCelebration> createState() => _MatchCelebrationState();
}

class _MatchCelebrationState extends ConsumerState<MatchCelebration> {
  late final Timer _timer;
  final _focus = FocusNode(debugLabel: 'match-celebration');

  /// Chi aveva il focus (il mazzo): lo riprende alla chiusura.
  FocusNode? _previous;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(matchCelebrationDuration, _finish);
    _previous = FocusManager.instance.primaryFocus;
    // Il mazzo ha già il focus e l'autofocus non lo toglie: va chiesto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _focus.dispose();
    final previous = _previous;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (previous.context?.mounted ?? false) previous.requestFocus();
      });
    }
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _timer.cancel();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = widget.item;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.handled;
        _finish();
        return KeyEventResult.handled;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: WfMotion.of(context).duration(WfMotion.medium),
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: ColoredBox(
            color: WfColors.bg.withValues(alpha: 0.9),
            child: Center(
              key: Key('match-celebration-${widget.id}'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item != null)
                    SizedBox(
                      width: _posterWidth,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: WfImage(
                              image: ref.watch(imageUrlsProvider).poster(item)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(l.matchItsAMatch,
                      style: WfText.display(48).copyWith(color: WfColors.gold)),
                  if (item != null) ...[
                    const SizedBox(height: 8),
                    Text(item.name, style: const TextStyle(fontSize: 18)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

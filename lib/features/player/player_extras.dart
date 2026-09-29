import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';

/// Ricostruisce [builder] solo quando cambia il valore che [select] ricava
/// dalla posizione del video (la posizione cambia molte volte al secondo).
class PositionSelector<T> extends StatefulWidget {
  const PositionSelector({
    super.key,
    required this.engine,
    required this.select,
    required this.builder,
  });

  final VideoEngine engine;
  final T Function(Duration position) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<PositionSelector<T>> createState() => _PositionSelectorState<T>();
}

class _PositionSelectorState<T> extends State<PositionSelector<T>> {
  late T _value;
  StreamSubscription<Duration>? _subscription;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.engine.position);
    _subscription = widget.engine.positionStream.listen((position) {
      final value = widget.select(position);
      if (value != _value) setState(() => _value = value);
    });
  }

  @override
  void didUpdateWidget(PositionSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // [select] può dipendere da dati arrivati dopo (es. i segmenti).
    _value = widget.select(widget.engine.position);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// Scheda "Prossimo episodio": con [countdown] parte da sola dopo
/// [countdownFrom] secondi di riproduzione (il conto si ferma in pausa e
/// durante il caricamento).
class NextEpisodeCard extends ConsumerStatefulWidget {
  const NextEpisodeCard({
    super.key,
    required this.episode,
    required this.countdown,
    required this.onPlay,
    required this.onCancel,
    this.paused = false,
  });

  final JellyfinItem episode;
  final bool countdown;

  /// Video in pausa o in caricamento: il conto alla rovescia è fermo.
  final bool paused;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  static const countdownFrom = 10;

  @override
  ConsumerState<NextEpisodeCard> createState() => _NextEpisodeCardState();
}

class _NextEpisodeCardState extends ConsumerState<NextEpisodeCard> {
  int _left = NextEpisodeCard.countdownFrom;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.countdown) {
      // Un solo timer: i secondi in pausa non contano.
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (widget.paused) return;
        if (_left <= 1) {
          timer.cancel();
          widget.onPlay();
        } else {
          setState(() => _left--);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final episode = widget.episode;
    return Material(
      color: WfColors.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.playerNextEpisodeTitle.toUpperCase(),
                  style: WfText.display(20, color: WfColors.gold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: WfImage(
                            image: ref.watch(imageUrlsProvider).landscape(episode)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cardSubtitle(episode) ?? episode.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (widget.countdown) ...[
                const SizedBox(height: 8),
                Text(l.playerNextEpisodeIn(_left),
                    style: const TextStyle(color: WfColors.creamMuted)),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  WfButton.primary(
                      label: l.playerPlayNow,
                      icon: LucideIcons.play,
                      onPressed: widget.onPlay),
                  WfButton.secondary(
                      label: l.playerCancel,
                      icon: LucideIcons.x,
                      onPressed: widget.onCancel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

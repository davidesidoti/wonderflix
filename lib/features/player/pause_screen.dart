import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';

/// "Anno · durata · generi" della schermata di pausa: al massimo due
/// generi, si omette ciò che manca.
String pauseScreenMeta(JellyfinItem item) {
  final runtime = item.runtime;
  return [
    if (item.productionYear != null) '${item.productionYear}',
    if (runtime != null) formatRuntime(runtime),
    ...item.genres.take(2),
  ].join(' · ');
}

/// Schermata "Stai guardando" sopra il fermo immagine (spec D §11): entra
/// sfumando con il testo che sale, esce in fretta. Non prende clic (un clic
/// sul film lo riprende). Nascosta, non è nell'albero.
class PauseScreen extends StatefulWidget {
  const PauseScreen({super.key, required this.item, required this.visible});

  final JellyfinItem item;
  final bool visible;

  /// Di quanto sale il testo entrando.
  static const textRise = 16.0;

  /// Larghezza massima del testo a sinistra.
  static const textWidth = 560.0;

  /// Margine del testo dal bordo sinistro.
  static const textInset = 64.0;

  @override
  State<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends State<PauseScreen> {
  /// Nell'albero: mostrata o mentre sfuma via.
  late bool _present = widget.visible;

  @override
  void didUpdateWidget(PauseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) _present = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const SizedBox.shrink();
    final motion = WfMotion.of(context);
    final visible = widget.visible;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: const Key('pause-screen'),
        tween: Tween(begin: 0, end: visible ? 1 : 0),
        duration: visible ? motion.duration(WfMotion.slow) : WfMotion.fast,
        curve: visible ? WfMotion.emphasized : WfMotion.accelerate,
        onEnd: () {
          if (!widget.visible && mounted) setState(() => _present = false);
        },
        builder: (context, t, text) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _PauseShade(),
              Positioned(
                left: PauseScreen.textInset,
                right: PauseScreen.textInset,
                top: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(
                        0,
                        motion.isReduced
                            ? 0
                            : (1 - t) * PauseScreen.textRise),
                    child: text,
                  ),
                ),
              ),
              const Positioned(right: 32, bottom: 32, child: _PausedBadge()),
            ],
          ),
        ),
        child: _PauseText(item: widget.item),
      ),
    );
  }
}

/// Sfumatura nera da sinistra sopra il fermo immagine.
class _PauseShade extends StatelessWidget {
  const _PauseShade();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              WfColors.bg.withValues(alpha: 0.88),
              WfColors.bg.withValues(alpha: 0.6),
              WfColors.bg.withValues(alpha: 0.15),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
      );
}

class _PausedBadge extends StatelessWidget {
  const _PausedBadge();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.pause, size: 18, color: WfColors.gold),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context).playerFeedbackPaused,
              style: const TextStyle(color: WfColors.creamMuted)),
        ],
      );
}

/// "STAI GUARDANDO", logo (o titolo), episodio, dati e trama.
class _PauseText extends ConsumerWidget {
  const _PauseText({required this.item});

  final JellyfinItem item;

  /// Spazio per il logo.
  static const logoHeight = 120.0;
  static const logoWidth = 420.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final logo = ref.watch(imageUrlsProvider).logo(item);
    final episode = item.kind == ItemKind.episode ? cardSubtitle(item) : null;
    final meta = pauseScreenMeta(item);
    final overview = item.overview;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: PauseScreen.textWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.playerWatching.toUpperCase(),
            style: const TextStyle(
                color: WfColors.gold,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          if (logo != null)
            SizedBox(
              height: logoHeight,
              width: logoWidth,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: WfImage(
                    image: logo, fit: BoxFit.contain, fallbackIcon: null),
              ),
            )
          else
            Text(cardTitle(item).toUpperCase(),
                maxLines: 2, style: WfText.display(64)),
          if (episode != null) ...[
            const SizedBox(height: 12),
            Text(episode,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(meta, style: const TextStyle(color: WfColors.creamMuted)),
          ],
          if (overview != null) ...[
            const SizedBox(height: 16),
            Text(overview,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.45)),
          ],
        ],
      ),
    );
  }
}

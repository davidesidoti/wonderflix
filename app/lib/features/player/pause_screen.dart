import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/genre_labels.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/video/video_engine.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'player_keys.dart';

/// "Anno · durata · generi" della schermata di pausa: al massimo due
/// generi, si omette ciò che manca.
String pauseScreenMeta(JellyfinItem item) {
  final runtime = item.runtime;
  return [
    if (item.productionYear != null) '${item.productionYear}',
    if (runtime != null) formatRuntime(runtime),
    ...displayGenres(item.genres),
  ].join(' · ');
}

/// Schermata "Stai guardando" sopra il fermo immagine (spec D §11): entra
/// sfumando con il testo che sale, esce in fretta. Prende clic solo su
/// "Riprendi" (un clic altrove arriva al film, che riprende). Nascosta, non
/// è nell'albero.
class PauseScreen extends StatefulWidget {
  const PauseScreen({
    super.key,
    required this.item,
    required this.visible,
    required this.engine,
    required this.onResume,
  });

  final JellyfinItem item;
  final bool visible;

  /// Posizione e durata della riga in basso: in pausa non cambiano.
  final VideoEngine engine;
  final VoidCallback onResume;

  /// Di quanto sale il testo entrando.
  static const textRise = 16.0;

  /// Larghezza massima del testo a sinistra.
  static const textWidth = 560.0;

  /// Margine del testo dal bordo sinistro.
  static const textInset = 64.0;

  /// Margine del testo nel layout stretto (spec §4.5).
  static const compactTextInset = 24.0;

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
    final form = FormFactor.of(context);
    final compact = form.compact && !form.tv;
    // I tasti esistono solo con la tastiera.
    final keys = !form.tv && !form.touch;
    final keysCard = keys && !form.compact;
    final inset =
        compact ? PauseScreen.compactTextInset : PauseScreen.textInset;
    return IgnorePointer(
      ignoring: !visible,
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
              const IgnorePointer(child: _PauseShade()),
              Positioned(
                left: inset,
                // Il testo non va sotto la scheda dei tasti.
                right: keysCard
                    ? PauseScreen.textInset + PlayerKeysCard.width + 32
                    : inset,
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
              if (keysCard)
                const Positioned(
                    right: PauseScreen.textInset,
                    top: 96,
                    child: IgnorePointer(child: PlayerKeysCard())),
              Positioned(
                left: inset,
                right: inset,
                bottom: compact ? 16 : 40,
                child: IgnorePointer(child: _PauseProgress(widget.engine)),
              ),
            ],
          ),
        ),
        child: _PauseText(
            item: widget.item,
            compact: compact,
            keys: keys,
            onResume: widget.onResume),
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

/// "23:12 ━━━━──── resta 28:48": posizione, barra sottile e tempo che
/// resta (finché la durata non c'è, niente resto).
class _PauseProgress extends StatelessWidget {
  const _PauseProgress(this.engine);

  final VideoEngine engine;

  static const _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final position = engine.position;
    final duration = engine.duration;
    final known = duration > Duration.zero;
    final left =
        known && duration > position ? duration - position : Duration.zero;
    return Row(
      children: [
        const Icon(LucideIcons.pause, size: 16, color: WfColors.gold),
        const SizedBox(width: 14),
        Text(formatClock(position),
            style: const TextStyle(
                color: WfColors.cream, fontSize: 12.5, fontFeatures: _tabular)),
        const SizedBox(width: 14),
        Expanded(
          child: SizedBox(
            height: 3,
            child: ColoredBox(
              color: WfColors.cream.withValues(alpha: 0.15),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: known
                    ? (position.inMilliseconds / duration.inMilliseconds)
                        .clamp(0.0, 1.0)
                    : 0,
                child: const ColoredBox(color: WfColors.gold),
              ),
            ),
          ),
        ),
        if (known) ...[
          const SizedBox(width: 14),
          Text(AppLocalizations.of(context).playerPauseLeft(formatClock(left)),
              style: const TextStyle(
                  color: WfColors.creamMuted,
                  fontSize: 12.5,
                  fontFeatures: _tabular)),
        ],
      ],
    );
  }
}

/// "Stai guardando", logo (o titolo), episodio, dati, trama e "Riprendi".
class _PauseText extends ConsumerWidget {
  const _PauseText({
    required this.item,
    required this.compact,
    required this.keys,
    required this.onResume,
  });

  final JellyfinItem item;

  /// Accanto a "Riprendi" anche "oppure Spazio".
  final bool keys;
  final VoidCallback onResume;

  /// Layout stretto: logo e testo più piccoli, meno righe.
  final bool compact;

  /// Spazio per il logo.
  static const logoHeight = 120.0;
  static const logoWidth = 420.0;
  static const compactLogoHeight = 64.0;
  static const compactLogoWidth = 240.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final logo = ref.watch(imageUrlsProvider).logo(item);
    final episode = item.kind == ItemKind.episode ? cardSubtitle(item) : null;
    final meta = pauseScreenMeta(item);
    final overview = item.overview;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
          Text(
            l.playerWatching,
            style: const TextStyle(
                color: WfColors.gold, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (logo != null)
            SizedBox(
              height: compact ? compactLogoHeight : logoHeight,
              width: compact ? compactLogoWidth : logoWidth,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: WfImage(
                    image: logo, fit: BoxFit.contain, fallbackIcon: null),
              ),
            )
          else
            Text(cardTitle(item).toUpperCase(),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: WfText.display(compact ? 32 : 64)),
          if (episode != null) ...[
            const SizedBox(height: 12),
            Text(episode,
                maxLines: compact ? 1 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
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
                maxLines: compact ? 3 : 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.45)),
          ],
      ],
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: PauseScreen.textWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Solo "Riprendi" prende i clic.
          IgnorePointer(child: info),
          SizedBox(height: compact ? 16 : 26),
          Wrap(
            key: const Key('pause-resume'),
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              WfButton.primary(
                  label: l.playerResume,
                  icon: LucideIcons.play,
                  onPressed: onResume),
              if (keys)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.playerResumeOr,
                        style: const TextStyle(color: WfColors.creamMuted)),
                    const SizedBox(width: 6),
                    KeyCap(l.playerKeySpace),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

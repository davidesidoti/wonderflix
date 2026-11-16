import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/backdrop_image.dart';
import '../../ui/form_factor.dart';
import '../../ui/states.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../playback/play_launcher.dart';
import 'ask_parts.dart';
import 'ask_sentence.dart';
import 'tonight_controller.dart';
import 'tonight_logic.dart';

/// Larghezza della finestra (in TV [tonightTvDialogWidth]).
const tonightDialogWidth = 760.0;
const tonightTvDialogWidth = 680.0;

/// Larghezza della locandina del titolo proposto (in TV
/// [tonightTvPosterWidth]).
const tonightPosterWidth = 172.0;
const tonightTvPosterWidth = 140.0;

/// Altezza dello spazio del titolo proposto, quella della locandina 2:3:
/// resta la stessa mentre si pesca, così la finestra non salta.
const tonightPickHeight = tonightPosterWidth * 3 / 2;

/// Altezza della locandina nello stretto, dove è larga quanto la pagina.
const tonightCompactPosterHeight = 330.0;

/// Altezza del fondale in cima alla finestra.
const tonightBackdropHeight = 300.0;

/// Quanti titoli tiene "Già proposti".
const tonightHistoryMax = 3;

/// Quello che si è scelto nella finestra.
sealed class TonightChoice {
  const TonightChoice(this.item);

  final JellyfinItem item;
}

class TonightPlay extends TonightChoice {
  const TonightPlay(super.item);
}

class TonightDetails extends TonightChoice {
  const TonightDetails(super.item);
}

Future<TonightChoice?> showTonightDialog(BuildContext context) =>
    showWfDialog<TonightChoice>(
      context,
      maxWidth: FormFactor.of(context).tv
          ? tonightTvDialogWidth
          : tonightDialogWidth,
      // Il fondale arriva ai bordi: i margini li mette la finestra.
      padding: EdgeInsets.zero,
      // Sulla TV (960 px logici, "stretto") la finestra resta una finestra.
      fullPageWhenCompact: !FormFactor.of(context).tv,
      semanticLabel: AppLocalizations.of(context).tonightButton,
      builder: (_) => const TonightDialog(),
    );

/// Apre la finestra e fa quello che si è scelto con il [context] di chi l'ha
/// aperta: quello della finestra chiusa non può più navigare (decisione 7
/// del piano 19c). Dev'essere un contesto che resta montato a finestra aperta
/// (quello della Home, non quello del pulsante: il carosello che arriva dopo
/// può sostituire il pulsante), altrimenti la scelta si perde.
Future<void> openTonight(BuildContext context, WidgetRef ref) async {
  final choice = await showTonightDialog(context);
  if (!context.mounted) return;
  switch (choice) {
    case TonightPlay(:final item):
      await playItem(context, ref, item);
    case TonightDetails(:final item):
      openItem(context, item);
    case null:
      break;
  }
}

/// "Cosa guardo stasera?" con il dado (spec M §8.4). Il pulsante non apre la
/// finestra da solo: lo fa [onPressed], di chi lo mette (la Home, con il suo
/// contesto), perché il pulsante può essere smontato a finestra aperta.
class TonightButton extends StatelessWidget {
  const TonightButton({
    super.key,
    required this.onPressed,
    this.short = false,
    this.small = false,
  });

  final VoidCallback onPressed;

  /// "Stasera?" invece di "Cosa guardo stasera?" (tra i pulsanti del
  /// carosello in TV).
  final bool short;

  /// Piccolo, per l'intestazione di Stasera.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return WfButton.secondary(
      key: const Key('tonight-button'),
      label: short ? l.tonightButtonShort : l.tonightButton,
      icon: LucideIcons.dices,
      small: small,
      onPressed: onPressed,
    );
  }
}

/// La finestra (spec §4): la frase dei filtri, il titolo proposto con il suo
/// fondale, "Già proposti" e i pulsanti.
class TonightDialog extends ConsumerStatefulWidget {
  const TonightDialog({super.key});

  @override
  ConsumerState<TonightDialog> createState() => _TonightDialogState();
}

class _TonightDialogState extends ConsumerState<TonightDialog> {
  /// Giri del dado di "Un altro": uno a ogni pescata.
  var _spins = 0;

  /// "Già proposti", dal più vecchio: vive solo con la finestra.
  final _history = <JellyfinItem>[];

  TonightController get _controller =>
      ref.read(tonightControllerProvider.notifier);

  JellyfinItem? get _current => ref.read(tonightControllerProvider).pick.value;

  /// Mette [item] in fondo a "Già proposti"; il più vecchio esce.
  void _remember(JellyfinItem item) {
    _history
      ..removeWhere((seen) => seen.id == item.id)
      ..add(item);
    if (_history.length > tonightHistoryMax) _history.removeAt(0);
  }

  /// Il titolo in vista va in "Già proposti" solo se c'è: un errore o
  /// "nessun titolo" non aggiungono nulla.
  void _another() {
    final current = _current;
    setState(() {
      _spins++;
      if (current != null) _remember(current);
    });
    unawaited(_controller.another());
  }

  void _restore(JellyfinItem item) {
    final current = _current;
    setState(() {
      _history.removeWhere((seen) => seen.id == item.id);
      if (current != null) _remember(current);
    });
    _controller.restore(item);
  }

  /// I titoli di prima non rispettano più i filtri nuovi.
  void _filters(TonightFilters next) {
    if (next != ref.read(tonightControllerProvider).filters) {
      setState(_history.clear);
    }
    unawaited(_controller.setFilters(next));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final form = FormFactor.of(context);
    final tv = form.tv;
    // Nello stretto la finestra è una pagina: scorre tutta.
    final compact = form.compact && !tv;
    final state = ref.watch(tonightControllerProvider);
    final filters = state.filters;
    final pick = state.pick.value;
    final loading = state.pick.isLoading;
    final history = [
      for (final item in _history)
        if (item.id != pick?.id) item,
    ];
    final slotHeight = compact
        ? tonightCompactPosterHeight
        : tv
        ? tonightTvPosterWidth * 3 / 2
        : tonightPickHeight;
    final slot = switch (state.pick) {
      AsyncData(value: final item?) => _TonightPick(
        item: item,
        compact: compact,
        tv: tv,
      ),
      AsyncData() => _TonightMessage(
        text: l.tonightEmpty,
        action: filters.isDefault ? null : l.tonightClearFilters,
        onAction: () => _filters(TonightFilters.defaults),
      ),
      AsyncError(:final error) => _TonightMessage(
        text: describeError(l, error),
        action: l.retry,
        onAction: _another,
      ),
      _ => SkeletonBox(height: slotHeight),
    };
    final another = WfButton.secondary(
      key: const Key('tonight-another'),
      label: l.tonightAnother,
      icon: LucideIcons.dices,
      iconWidget: AnimatedRotation(
        key: const Key('tonight-dice'),
        turns: _spins.toDouble(),
        duration: motion.isReduced ? Duration.zero : WfMotion.slow,
        curve: WfMotion.emphasized,
        child: const Icon(LucideIcons.dices, size: 18),
      ),
      // In TV resta attivo mentre pesca: all'apertura deve prendere il focus.
      autofocus: tv,
      onPressed: loading ? (tv ? () {} : null) : _another,
    );
    final details = WfButton.secondary(
      key: const Key('tonight-details'),
      label: l.actionDetails,
      icon: LucideIcons.info,
      onPressed: pick == null
          ? null
          : () => Navigator.of(context).pop(TonightDetails(pick)),
    );
    final play = WfButton.primary(
      key: const Key('tonight-play'),
      label: l.actionPlay,
      icon: LucideIcons.play,
      onPressed: pick == null
          ? null
          : () => Navigator.of(context).pop(TonightPlay(pick)),
    );
    final header = Row(
      children: [
        const Icon(LucideIcons.dices, size: 20, color: WfColors.gold),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            l.tonightButton,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: WfColors.creamMuted,
            ),
          ),
        ),
      ],
    );
    final seen = history.isEmpty
        ? null
        : _TonightHistory(items: history, onTap: _restore);

    if (compact) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 12),
            AskSentence(
              filters: filters,
              voice: AskVoice.tonight,
              onChanged: _filters,
              fontSize: 18,
            ),
            const SizedBox(height: 18),
            if (state.pick case AsyncData(value: _?))
              slot
            else
              SizedBox(height: slotHeight, child: slot),
            if (seen != null) ...[const SizedBox(height: 16), seen],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: another),
                const SizedBox(width: 10),
                Expanded(child: play),
              ],
            ),
            const SizedBox(height: 10),
            details,
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: tonightBackdropHeight,
          child: _TonightWash(item: pick),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 14),
              AskSentence(
                filters: filters,
                voice: AskVoice.tonight,
                onChanged: _filters,
              ),
              const SizedBox(height: 22),
              // Nelle finestre basse lo spazio si accorcia e il testo scorre:
              // la frase e i pulsanti restano sempre in vista.
              Flexible(
                child: SizedBox(height: slotHeight, child: slot),
              ),
              const SizedBox(height: 22),
              DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: WfColors.border)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: seen,
                        ),
                      ),
                      another,
                      details,
                      play,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Il fondale del titolo in cima alla finestra: al 35%, sfumato verso il
/// basso, cambia in dissolvenza.
class _TonightWash extends ConsumerWidget {
  const _TonightWash({required this.item});

  final JellyfinItem? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    final item = this.item;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: WfMotion.of(context).isReduced
            ? Duration.zero
            : WfMotion.slow,
        layoutBuilder: (current, previous) =>
            Stack(fit: StackFit.expand, children: [...previous, ?current]),
        child: item == null
            ? const SizedBox.shrink()
            : Opacity(
                key: ValueKey(item.id),
                opacity: 0.35,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Colors.transparent],
                  ).createShader(rect),
                  child: BackdropImage(
                    backdrop: urls.backdrop(item),
                    fallback: urls.poster(item),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Il titolo proposto: locandina, perché, nome, dati e trama. Entra salendo
/// in dissolvenza; con le animazioni ridotte è subito in vista.
class _TonightPick extends ConsumerWidget {
  const _TonightPick({
    required this.item,
    required this.compact,
    required this.tv,
  });

  final JellyfinItem item;
  final bool compact;
  final bool tv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    final poster = ClipRRect(
      key: const Key('tonight-poster'),
      borderRadius: BorderRadius.circular(compact ? 10 : 8),
      child: WfImage(image: urls.poster(item)),
    );
    final text = _TonightPickText(
      item: item,
      nameSize: compact || tv ? 38 : 46,
      overviewLines: tv ? 3 : 4,
    );
    final Widget content = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: tonightCompactPosterHeight, child: poster),
              const SizedBox(height: 14),
              text,
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x8C000000),
                      blurRadius: 34,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: tv ? tonightTvPosterWidth : tonightPosterWidth,
                  child: poster,
                ),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: SingleChildScrollView(primary: false, child: text),
              ),
            ],
          );
    // La chiave: ogni titolo entra da capo e riparte dall'inizio del testo.
    return TweenAnimationBuilder<double>(
      key: ValueKey('tonight-pick-${item.id}'),
      tween: Tween(begin: WfMotion.of(context).isReduced ? 1 : 0, end: 1),
      duration: WfMotion.slow,
      curve: WfMotion.emphasized,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: content,
    );
  }
}

class _TonightPickText extends StatelessWidget {
  const _TonightPickText({
    required this.item,
    required this.nameSize,
    required this.overviewLines,
  });

  final JellyfinItem item;
  final double nameSize;
  final int overviewLines;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rating = item.communityRating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.kind == ItemKind.series ? l.tonightWhySeries : l.tonightWhyMovie,
          style: const TextStyle(
            color: WfColors.gold,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: WfText.display(nameSize),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              tonightMeta(l, item),
              style: const TextStyle(color: WfColors.creamMuted),
            ),
            if (rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.star, size: 14, color: WfColors.gold),
                  const SizedBox(width: 4),
                  Text(
                    rating.toStringAsFixed(1),
                    style: const TextStyle(
                      color: WfColors.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (item.overview case final overview?) ...[
          const SizedBox(height: 10),
          Text(
            overview,
            maxLines: overviewLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.55),
          ),
        ],
      ],
    );
  }
}

/// "Già proposti": le locandine piccole dei titoli di prima; un clic ne
/// rimette uno.
class _TonightHistory extends ConsumerWidget {
  const _TonightHistory({required this.items, required this.onTap});

  final List<JellyfinItem> items;
  final ValueChanged<JellyfinItem> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Flexible(
          child: Text(
            AppLocalizations.of(context).tonightHistory,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: WfColors.creamMuted, fontSize: 12),
          ),
        ),
        for (final item in items)
          Tooltip(
            message: item.name,
            // Il bordo sta fuori dall'InkWell: segue il focus dei discendenti.
            child: TvFocusBorder(
              borderRadius: BorderRadius.circular(3),
              child: InkWell(
                key: Key('tonight-history-${item.id}'),
                borderRadius: BorderRadius.circular(3),
                onTap: () => onTap(item),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    width: 26,
                    height: 39,
                    child: WfImage(image: urls.poster(item, maxWidth: 80)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Nessun titolo, o un errore: il messaggio e, se c'è, un'azione.
class _TonightMessage extends StatelessWidget {
  const _TonightMessage({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String? action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final label = action;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: WfColors.creamMuted),
          ),
          if (label != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(label)),
          ],
        ],
      ),
    );
  }
}

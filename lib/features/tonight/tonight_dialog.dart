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
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../catalog/catalog_filters_bar.dart';
import '../library/library_providers.dart';
import '../playback/play_launcher.dart';
import 'tonight_controller.dart';
import 'tonight_logic.dart';

/// Larghezza della finestra.
const tonightDialogWidth = 720.0;

/// Altezza dello spazio del titolo proposto: resta la stessa mentre si
/// pesca, così la finestra non salta.
const tonightPickHeight = 360.0;

/// Altezza dello sfondo del titolo proposto.
const tonightBackdropHeight = 200.0;

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
      maxWidth: tonightDialogWidth,
      semanticLabel: AppLocalizations.of(context).tonightButton,
      builder: (_) => const TonightDialog(),
    );

/// Apre la finestra e fa quello che si è scelto con il [context] di chi l'ha
/// aperta: quello della finestra chiusa non può più navigare (decisione 7
/// del piano 19c).
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

/// "Cosa guardo stasera?" con il dado (spec M §8.4).
class TonightButton extends ConsumerWidget {
  const TonightButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => WfButton.secondary(
        key: const Key('tonight-button'),
        label: AppLocalizations.of(context).tonightButton,
        icon: LucideIcons.dices,
        onPressed: () => unawaited(openTonight(context, ref)),
      );
}

/// La finestra (spec M §8.4): filtri, il titolo proposto, Riproduci,
/// Dettagli e "Un altro".
class TonightDialog extends ConsumerStatefulWidget {
  const TonightDialog({super.key});

  @override
  ConsumerState<TonightDialog> createState() => _TonightDialogState();
}

class _TonightDialogState extends ConsumerState<TonightDialog> {
  /// Giri del dado: uno a ogni "Un altro".
  var _spins = 0;

  TonightController get _controller =>
      ref.read(tonightControllerProvider.notifier);

  void _another() {
    setState(() => _spins++);
    unawaited(_controller.another());
  }

  void _filters(TonightFilters next) =>
      unawaited(_controller.setFilters(next));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final motion = WfMotion.of(context);
    final state = ref.watch(tonightControllerProvider);
    final filters = state.filters;
    final genres = ref.watch(tonightGenresProvider(filters.type)).value ??
        const <String>[];
    // Un genere che non c'è più torna a "Tutti i generi" (decisione 8 del
    // piano 19c).
    ref.listen(tonightGenresProvider(filters.type), (_, next) {
      final current = ref.read(tonightControllerProvider).filters;
      final list = next.value;
      final genre = current.genre;
      if (genre != null && list != null && !list.contains(genre)) {
        _filters(current.copyWith(genre: null));
      }
    });
    final pick = state.pick.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AnimatedRotation(
              key: const Key('tonight-dice'),
              turns: _spins.toDouble(),
              duration: motion.isReduced ? Duration.zero : WfMotion.slow,
              curve: WfMotion.emphasized,
              child: const Icon(LucideIcons.dices,
                  size: 24, color: WfColors.gold),
            ),
            const SizedBox(width: 12),
            Text(l.tonightButton,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<TonightType>(
              key: const Key('tonight-type'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: TonightType.movies,
                    label: Text(l.tonightTypeMovies)),
                ButtonSegment(
                    value: TonightType.series,
                    label: Text(l.tonightTypeSeries)),
                ButtonSegment(
                    value: TonightType.both, label: Text(l.tonightTypeBoth)),
              ],
              selected: {filters.type},
              onSelectionChanged: (selection) =>
                  _filters(filters.copyWith(type: selection.first)),
            ),
            SegmentedButton<TonightDuration>(
              key: const Key('tonight-duration'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: TonightDuration.any,
                    label: Text(l.tonightDurationAny)),
                ButtonSegment(
                    value: TonightDuration.under90,
                    label: Text(l.tonightDuration90)),
                ButtonSegment(
                    value: TonightDuration.under120,
                    label: Text(l.tonightDuration120)),
              ],
              selected: {filters.duration},
              // La durata vale solo per i film (spec M §8.4).
              onSelectionChanged: filters.type == TonightType.series
                  ? null
                  : (selection) =>
                      _filters(filters.copyWith(duration: selection.first)),
            ),
            FilterPicker<String?>(
              value: filters.genre,
              items: {
                null: l.catalogAllGenres,
                for (final genre in genres) genre: genre,
              },
              onChanged: (genre) => _filters(filters.copyWith(genre: genre)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Nelle finestre basse lo spazio si accorcia e il titolo scorre: i
        // filtri e i pulsanti restano sempre in vista.
        Flexible(
          child: SizedBox(
            height: tonightPickHeight,
            child: switch (state.pick) {
              AsyncData(value: final item?) => _TonightPick(item: item),
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
              _ => const SkeletonBox(height: tonightPickHeight),
            },
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            WfButton.secondary(
              key: const Key('tonight-another'),
              label: l.tonightAnother,
              icon: LucideIcons.dices,
              onPressed: state.pick.isLoading ? null : _another,
            ),
            WfButton.secondary(
              key: const Key('tonight-details'),
              label: l.actionDetails,
              icon: LucideIcons.info,
              onPressed: pick == null
                  ? null
                  : () => Navigator.of(context).pop(TonightDetails(pick)),
            ),
            WfButton.primary(
              key: const Key('tonight-play'),
              label: l.actionPlay,
              icon: LucideIcons.play,
              onPressed: pick == null
                  ? null
                  : () => Navigator.of(context).pop(TonightPlay(pick)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Il titolo proposto: sfondo, titolo, dati, voto e trama.
class _TonightPick extends ConsumerWidget {
  const _TonightPick({required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final rating = item.communityRating;
    const muted = TextStyle(color: WfColors.creamMuted);
    // La chiave: ogni titolo riparte dall'inizio, senza la posizione del
    // precedente.
    return SingleChildScrollView(
      key: ValueKey('tonight-pick-${item.id}'),
      primary: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: tonightBackdropHeight,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BackdropImage(
                      backdrop: urls.backdrop(item), fallback: urls.poster(item)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [WfColors.bg, Colors.transparent],
                        stops: [0, 0.6],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Text(item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WfText.display(32)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(tonightMeta(l, item), style: muted),
              if (rating != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.star, size: 14, color: WfColors.gold),
                    const SizedBox(width: 4),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: WfColors.gold, fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
          if (item.overview case final overview?) ...[
            const SizedBox(height: 8),
            Text(overview, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// Nessun titolo, o un errore: il messaggio e, se c'è, un'azione.
class _TonightMessage extends StatelessWidget {
  const _TonightMessage(
      {required this.text, required this.action, required this.onAction});

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
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WfColors.creamMuted)),
          if (label != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(label)),
          ],
        ],
      ),
    );
  }
}

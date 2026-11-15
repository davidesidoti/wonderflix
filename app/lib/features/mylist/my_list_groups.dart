import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../app/navigation.dart';
import '../../ui/form_factor.dart';
import '../../ui/landscape_card.dart';
import '../../ui/poster_card.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import 'my_list_removal.dart';
import 'my_list_view.dart';

/// Il prossimo episodio di ogni serie iniziata, con chiave
/// `jellyfinIdKey(seriesId)`: una sola lettura per tutte le card di Da
/// continuare (spec §8.2).
final myListNextUpProvider =
    FutureProvider.autoDispose<Map<String, JellyfinItem>>((ref) async {
      ref.watch(libraryRevisionProvider);
      final episodes = await ref
          .watch(libraryApiProvider)
          .nextUp(
            ref.watch(currentUserIdProvider),
            limit: 100,
            enableResumable: true,
          );
      return {
        for (final e in episodes)
          if (e.seriesId case final id?) jellyfinIdKey(id): e,
      };
    });

/// La riga sotto una card di Da continuare. Film: "Riprendi da 52 min, ne
/// restano 66". Serie: "S2:E3, 5 episodi da vedere" ("S1:E8, l'ultimo"), solo
/// "5 episodi da vedere" finché [next] non c'è, con "Nuovo episodio, "
/// davanti se l'ultimo è arrivato da meno di 7 giorni.
String? myListResumeLine(
  AppLocalizations l,
  JellyfinItem item,
  UserItemData data,
  JellyfinItem? next,
) {
  if (item.kind != ItemKind.series) {
    final runtime = item.runTimeTicks;
    if (runtime == null) return null;
    final position = data.playbackPositionTicks;
    final left = (ticksToDuration(runtime - position).inSeconds / 60)
        .ceil()
        .clamp(1, 1 << 30);
    return l.myListResumeFrom(ticksToDuration(position).inMinutes, left);
  }
  final unplayed = data.unplayedItemCount ?? 0;
  final toWatch = l.catalogSeriesToWatch(unplayed);
  final code = next == null ? null : episodeCode(next);
  final line = code == null
      ? toWatch
      : '$code, ${unplayed == 1 ? l.myListLastOne : toWatch}';
  final added = item.dateLastMediaAdded;
  final fresh =
      added != null && clock.now().difference(added) < const Duration(days: 7);
  return fresh ? '${l.myListNewEpisode}, $line' : line;
}

/// I gruppi della pagina (spec §6), già filtrati e ordinati in [view]. Un
/// gruppo vuoto non compare; Visti si apre con [onToggleWatched].
List<Widget> myListGroupSlivers(
  BuildContext context, {
  required MyListView view,
  required double side,
  required bool watchedOpen,
  required VoidCallback onToggleWatched,
}) {
  final l = AppLocalizations.of(context);
  Widget box(Widget child) => SliverPadding(
    padding: EdgeInsets.symmetric(horizontal: side),
    sliver: SliverToBoxAdapter(child: child),
  );
  return [
    if (view.resume.isNotEmpty)
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GroupTitle(l.myListGroupResume, view.resume.length),
            _ResumeCards(items: view.resume),
          ],
        ),
      ),
    if (view.start.isNotEmpty) ...[
      box(_GroupTitle(l.myListGroupStart, view.start.length)),
      _posterGrid(view.start, side, 'mylist.start'),
    ],
    if (view.watched.isNotEmpty) ...[
      box(
        _WatchedHeader(
          items: view.watched,
          removable: view.removableWatched,
          open: watchedOpen,
          onToggle: onToggleWatched,
        ),
      ),
      if (watchedOpen) _posterGrid(view.watched, side, 'mylist.watched'),
    ],
    const SliverToBoxAdapter(child: SizedBox(height: 32)),
  ];
}

/// La griglia del catalogo: stesse colonne e stessa altezza delle celle.
Widget _posterGrid(List<JellyfinItem> items, double side, String source) =>
    SliverPadding(
      padding: EdgeInsets.fromLTRB(side, 0, side, 8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) => SliverGrid(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 24,
            crossAxisSpacing: 16,
            mainAxisExtent: catalogCellExtent(
              constraints.crossAxisExtent,
              MediaQuery.textScalerOf(context),
            ),
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => LayoutBuilder(
              builder: (context, cell) => MyListRemovable(
                item: items[i],
                imageHeight: cell.maxWidth * 3 / 2,
                child: PosterCard(
                  item: items[i],
                  heroSource: '$source.$i',
                  catalogStyle: true,
                ),
              ),
            ),
            childCount: items.length,
          ),
        ),
      ),
    );

/// "Da iniziare 4": il nome in crema, il conteggio al 50%.
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title, this.count);

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: WfColors.cream,
      fontSize: FormFactor.of(context).compact ? 15 : 17,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text(title, style: style),
          Text(
            '$count',
            style: style.copyWith(color: WfColors.cream.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

/// Le card 16:9 di Da continuare: vanno a capo, o in colonna a tutta
/// larghezza nello stretto.
class _ResumeCards extends StatelessWidget {
  const _ResumeCards({required this.items});

  final List<JellyfinItem> items;

  @override
  Widget build(BuildContext context) {
    final form = FormFactor.of(context);
    final column = form.compact && !form.tv;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          for (final (i, item) in items.indexed)
            _ResumeCard(
              item: item,
              heroSource: 'mylist.resume.$i',
              width: column ? constraints.maxWidth : 300,
            ),
        ];
        return column
            ? Column(spacing: 16, children: cards)
            : Wrap(spacing: 16, runSpacing: 20, children: cards);
      },
    );
  }
}

class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({
    required this.item,
    required this.heroSource,
    required this.width,
  });

  final JellyfinItem item;
  final String heroSource;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Solo le serie leggono il prossimo episodio: senza serie, nessuna
    // richiesta.
    final series = item.kind == ItemKind.series;
    final nextUp = series ? ref.watch(myListNextUpProvider).value : null;
    final next = nextUp?[jellyfinIdKey(item.id)];
    return MyListRemovable(
      item: item,
      imageHeight: width * 9 / 16,
      // Come il cartellone: finché il prossimo episodio non arriva, la
      // serie apre la scheda.
      onPlay: () => series && nextUp == null
          ? openItem(context, item)
          : unawaited(playItem(context, ref, item)),
      child: LandscapeCard(
        item: item,
        heroSource: heroSource,
        width: width,
        subtitle: myListResumeLine(
          AppLocalizations.of(context),
          item,
          watchUserData(ref, item),
          next,
        ),
      ),
    );
  }
}

/// Testata di Visti: freccia, titolo e conteggio aprono e chiudono il
/// gruppo; da chiuso, le prime 6 locandine in piccolo (decorative).
class _WatchedHeader extends ConsumerWidget {
  const _WatchedHeader({
    required this.items,
    required this.removable,
    required this.open,
    required this.onToggle,
  });

  final List<JellyfinItem> items;

  /// `MyListView.removableWatched`: senza, niente "Togli i visti".
  final List<JellyfinItem> removable;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tv = FormFactor.of(context).tv;
    final urls = ref.watch(imageUrlsProvider);
    final toggle = TvFocusable(
      onActivate: onToggle,
      child: Semantics(
        button: true,
        expanded: open,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            // Sulla TV il focus è di TvFocusable.
            canRequestFocus: !tv,
            onTap: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 18,
                  color: WfColors.cream,
                ),
                const SizedBox(width: 6),
                _GroupTitle(l.myListGroupWatched, items.length),
              ],
            ),
          ),
        ),
      ),
    );
    final header = Wrap(
      spacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        toggle,
        if (!open)
          ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                for (final item in items.take(6))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      width: 30,
                      height: 45,
                      child: WfImage(
                        image: urls.poster(item, maxWidth: 90),
                        fallbackIcon: null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
    if (removable.isEmpty) return header;
    return Row(
      children: [
        Expanded(child: header),
        TextButton.icon(
          onPressed: () => unawaited(_removeWatched(context, ref)),
          icon: const Icon(LucideIcons.heartOff, size: 16),
          label: Text(l.myListRemoveWatched),
        ),
      ],
    );
  }

  /// Fuori dalla TV toglie subito (c'è Annulla); in TV l'Annulla della
  /// SnackBar non si raggiunge in tempo, quindi prima chiede conferma.
  Future<void> _removeWatched(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final count = removable.length;
    if (FormFactor.of(context).tv) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l.myListRemoveWatchedConfirm(count)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.myListRemoveConfirm),
            ),
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.myListCancel),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    await removeFromMyList(
      context,
      ref,
      removable,
      message: l.myListRemovedWatched(count),
    );
  }
}

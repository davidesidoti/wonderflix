import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/match_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';

/// Larghezza della locandina di una voce.
const _posterWidth = 48.0;

/// La colonna dei match (spec P §7.3): i match nell'ordine di uscita, sotto i
/// quasi match con "N su M". Con [onChoose] le voci si possono scegliere come
/// primo titolo del party ([chosen] dice "Parte per primo").
class MatchColumn extends StatelessWidget {
  const MatchColumn({
    super.key,
    required this.state,
    required this.titles,
    this.chosen,
    this.onChoose,
  });

  final MatchState state;
  final Map<String, JellyfinItem?> titles;
  final String? chosen;
  final ValueChanged<String>? onChoose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(l.matchMatches),
        if (state.matches.isEmpty)
          Text(l.matchNoMatches,
              style: const TextStyle(color: WfColors.creamMuted)),
        for (final id in state.matches) _Entry(id: id, item: titles[id], column: this),
        if (state.nearMatches.isNotEmpty) ...[
          const SizedBox(height: 24),
          _heading(l.matchNearMatches),
          for (final near in state.nearMatches)
            _Entry(
                id: near.itemId,
                item: titles[near.itemId],
                column: this,
                subtitle: l.matchYesOf(near.yes, near.of)),
        ],
      ],
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      );
}

class _Entry extends ConsumerWidget {
  const _Entry(
      {required this.id, required this.item, required this.column, this.subtitle});

  final String id;
  final JellyfinItem? item;
  final MatchColumn column;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final item = this.item;
    final isChosen = column.chosen == id;
    final onChoose = column.onChoose;
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: _posterWidth,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: WfImage(
                    image: item == null
                        ? null
                        : ref.watch(imageUrlsProvider).poster(item)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item?.name ?? '',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(color: WfColors.creamMuted)),
                if (isChosen)
                  Text(l.matchPlaysFirst,
                      style: const TextStyle(color: WfColors.gold)),
              ],
            ),
          ),
        ],
      ),
    );
    return KeyedSubtree(
      key: Key('match-column-$id'),
      child: onChoose == null
          ? body
          : InkWell(onTap: () => onChoose(id), child: body),
    );
  }
}

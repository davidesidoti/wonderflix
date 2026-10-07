import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import 'collections_providers.dart';

/// Righe "Fa parte di" della scheda di un film (spec K §8.3): una per ogni
/// saga del film con almeno [minSagaSize] titoli, dalla più piccola alla
/// più grande. Senza saghe non mostra nulla.
class CollectionRows extends ConsumerWidget {
  const CollectionRows({super.key, required this.itemId});

  final String itemId;

  /// Una saga con un titolo solo non ha altri titoli da proporre.
  static const minSagaSize = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sagas = [
      for (final saga in ref.watch(collectionsByItemProvider)[
              jellyfinIdKey(itemId)] ??
          const <CollectionSummary>[])
        if (saga.size >= minSagaSize) saga,
    ];
    if (sagas.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final saga in sagas)
          _SagaRow(key: ValueKey(saga.id), saga: saga, itemId: itemId),
      ],
    );
  }
}

/// I titoli di una saga in ordine di uscita; finché carica, o se non si
/// leggono, la riga non c'è (come "Simili").
class _SagaRow extends ConsumerWidget {
  const _SagaRow({super.key, required this.saga, required this.itemId});

  final CollectionSummary saga;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(collectionItemsProvider(saga.id)).value ??
        const <JellyfinItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final current = jellyfinIdKey(itemId);
    return MediaRow(
      title: l.collectionPartOf(saga.name),
      onTitleTap: () => openCollection(context, saga.id),
      height: 300,
      itemCount: items.length,
      // Le card volano con la riga, come "Simili".
      animateEntrance: true,
      itemBuilder: (context, i) {
        final item = items[i];
        final isCurrent = jellyfinIdKey(item.id) == current;
        // Il film aperto non si riapre: né clic, né anteprima, né volo.
        return PosterCard(
          item: item,
          width: 160,
          heroSource: isCurrent ? null : 'saga.${saga.id}.$i',
          markLabel: isCurrent ? l.collectionThisMovie : null,
          openable: !isCurrent,
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'collection_card.dart';

/// Sezione "Saghe" della ricerca (spec K §8.5): le saghe il cui nome
/// contiene il testo cercato, prese dall'elenco in cache, senza chiamate.
class SagasSearchSection extends StatelessWidget {
  const SagasSearchSection({super.key, required this.sagas});

  /// Quante saghe al massimo.
  static const maxResults = 12;

  final List<CollectionSummary> sagas;

  @override
  Widget build(BuildContext context) {
    if (sagas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).collectionsTab,
              style: WfText.display(26)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 24,
            children: [
              for (final saga in sagas)
                CollectionCard(
                    key: ValueKey(saga.id), collection: saga, width: 150),
            ],
          ),
        ],
      ),
    );
  }
}

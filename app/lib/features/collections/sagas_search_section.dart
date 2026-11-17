import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/poster_card.dart';
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
    final form = FormFactor.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).collectionsTab,
              style: WfText.display(form.tv ? 22 : (form.compact ? 26 : 30))),
          const SizedBox(height: 12),
          // La griglia del catalogo: le celle sono alte come quelle dei titoli.
          LayoutBuilder(
            builder: (context, constraints) => GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 16,
                mainAxisSpacing: 24,
                mainAxisExtent: catalogCellExtent(
                    constraints.maxWidth, MediaQuery.textScalerOf(context)),
              ),
              children: [
                for (final saga in sagas)
                  CollectionCard(key: ValueKey(saga.id), collection: saga),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

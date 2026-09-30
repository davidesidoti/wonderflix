import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/hero_launch.dart';
import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/media_row.dart';
import '../../ui/poster_card.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import 'detail_providers.dart';

/// Le card delle righe della scheda volano dentro appena la riga compare,
/// solo con le animazioni complete.
Duration? _rowEntrance(BuildContext context) =>
    WfMotion.of(context).isReduced ? null : Duration.zero;

class CastRow extends ConsumerWidget {
  const CastRow({super.key, required this.people});

  final List<PersonRef> people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    // Solo il cast: regista, sceneggiatore e produttore non sono attori.
    final cast = people
        .where((p) => p.type == null || p.type == 'Actor' || p.type == 'GuestStar')
        .toList();
    if (cast.isEmpty) return const SizedBox.shrink();
    return MediaRow(
      title: AppLocalizations.of(context).detailCast,
      height: 170,
      itemCount: cast.length,
      entranceDelay: _rowEntrance(context),
      itemBuilder: (context, i) {
        final person = cast[i];
        final role = person.role;
        // Unica per l'istanza della pagina (vedi WfHeroScope).
        final source = WfHeroScope.source(context, 'cast.$i');
        return GestureDetector(
          onTap: () => openPerson(context, person, heroSource: source),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              width: 110,
              child: Column(
                children: [
                  WfHero(
                    tag: WfHeroTag(person.id, source),
                    // Cerchio (90 px): il volo lo trasforma negli angoli
                    // della foto della persona.
                    borderRadius: BorderRadius.circular(45),
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: WfImage(
                          image: urls.person(person),
                          fallbackIcon: LucideIcons.user),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(person.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                  if (role != null && role.isNotEmpty)
                    Text(role,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: WfColors.creamMuted)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Riga "Simili": se il caricamento fallisce non mostra nulla (non è essenziale).
class SimilarRow extends ConsumerWidget {
  const SimilarRow({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(similarProvider(itemId)).value ?? const <JellyfinItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return MediaRow(
      title: AppLocalizations.of(context).detailSimilar,
      height: 300,
      itemCount: items.length,
      entranceDelay: _rowEntrance(context),
      itemBuilder: (context, i) => PosterCard(
        item: items[i],
        width: 160,
        heroSource: 'similar.$i',
      ),
    );
  }
}

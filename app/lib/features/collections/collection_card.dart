import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/social/collections_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';

/// Card di una saga (vista "Saghe", ricerca): locandina, nome, numero di
/// film (spec K §8.4). Il clic apre la pagina della saga. Senza anteprima al
/// passaggio del mouse: l'anteprima è dei titoli.
class CollectionCard extends ConsumerStatefulWidget {
  const CollectionCard({super.key, required this.collection, this.width});

  final CollectionSummary collection;

  /// `null`: la larghezza disponibile (griglie).
  final double? width;

  @override
  ConsumerState<CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends ConsumerState<CollectionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final collection = widget.collection;
    final tag = collection.primaryImageTag;
    final image = tag == null
        ? null
        : ref.watch(imageUrlsProvider).primaryWithTag(collection.id, tag);
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () => openCollection(context, collection.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: AnimatedContainer(
                  duration: WfMotion.fast,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _hover ? WfColors.gold : Colors.transparent,
                        width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child:
                        WfImage(image: image, fallbackIcon: LucideIcons.layers),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(collection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
              Text(l.collectionFilmCount(collection.size),
                  style:
                      const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

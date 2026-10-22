import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/backdrop_image.dart';
import '../library/library_providers.dart';
import '../tonight/tonight_logic.dart';

/// La carta di un titolo da votare: sfondo, titolo, dati e trama (come la
/// proposta di "Cosa guardo stasera?").
class MatchCard extends ConsumerWidget {
  const MatchCard({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final overview = item.overview;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropImage(backdrop: urls.backdrop(item), fallback: urls.poster(item)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [WfColors.bg, Colors.transparent],
                stops: [0.1, 0.8],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WfText.display(32)),
                const SizedBox(height: 4),
                Text(tonightMeta(l, item),
                    style: const TextStyle(color: WfColors.creamMuted)),
                if (overview != null) ...[
                  const SizedBox(height: 8),
                  Text(overview, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_image.dart';
import '../library/library_providers.dart';
import '../tonight/tonight_logic.dart';

/// La carta verticale di un titolo da votare (spec §5.4): locandina sfumata
/// in basso, nome, dati e trama su 3 righe.
class MatchCard extends ConsumerWidget {
  const MatchCard({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final overview = item.overview;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          WfImage(image: ref.watch(imageUrlsProvider).poster(item)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  WfColors.bg,
                  WfColors.bg.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
                stops: const [0, 0.34, 0.6],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: WfText.display(34).copyWith(height: 0.9)),
                const SizedBox(height: 6),
                Text(tonightMeta(l, item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: WfColors.creamMuted, fontSize: 12)),
                if (overview != null) ...[
                  const SizedBox(height: 6),
                  Text(overview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, height: 1.45)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

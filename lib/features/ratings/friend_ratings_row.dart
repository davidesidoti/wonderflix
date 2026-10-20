import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/rating_models.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/media_row.dart';
import '../../ui/user_avatar.dart';
import '../library/user_data.dart';
import '../social/social_providers.dart';
import 'rating_widgets.dart';

final _log = Logger('ratings');

/// I voti degli amici su un titolo (`GET Ratings`), per id.
final itemRatingsProvider =
    FutureProvider.autoDispose.family<ItemRatings, String>(
        (ref, itemId) => ref.watch(socialApiProvider).itemRatings(itemId));

/// Altezza della riga, card comprese.
const _rowHeight = 128.0;

/// Larghezza di una card e del riquadro della media.
const _cardWidth = 220.0;

/// "Voti degli amici" nella scheda di un film o di una stagione (spec Q §7.1).
/// Il tocco su "Vota" o sul proprio voto chiama [onRate] (il pannello lo apre
/// chi usa la riga).
class FriendRatingsRow extends ConsumerWidget {
  const FriendRatingsRow(
      {super.key, required this.item, this.title, this.onRate});

  final JellyfinItem item;

  /// Di default "Voti degli amici".
  final String? title;
  final ValueChanged<ItemRatings>? onRate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(socialAvailabilityProvider.select((f) => f.ratings))) {
      return const SizedBox.shrink();
    }
    // Segnare il titolo come visto cambia chi può votare: si rilegge.
    ref.listen(userDataOverridesProvider.select((m) => m[item.id]?.played),
        (_, _) => ref.invalidate(itemRatingsProvider(item.id)));
    ref.listen(itemRatingsProvider(item.id), (_, next) {
      final error = next.error;
      if (error == null) return;
      _log.info(
          'voti non letti: ${error is SocialException ? error.failure.name : error.runtimeType}');
    });
    final data = ref.watch(itemRatingsProvider(item.id)).value;
    if (data == null || (data.friends.isEmpty && !data.canRate)) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final mine = data.mine;
    return MediaRow(
      title: title ?? l.ratingFriendsRow,
      height: _rowHeight,
      itemCount: data.friends.length + 1,
      trailing: mine == null && !data.canRate
          ? null
          : TextButton.icon(
              key: const Key('friend-ratings-action'),
              onPressed: onRate == null ? null : () => onRate!(data),
              icon: Icon(mine == null ? LucideIcons.star : LucideIcons.pencil,
                  size: 16, color: WfColors.gold),
              label: Text(
                  mine == null ? l.ratingVote : l.ratingMine(mine.score),
                  style: const TextStyle(color: WfColors.gold)),
            ),
      itemBuilder: (context, i) => i == 0
          ? _AverageBox(data: data)
          : _FriendCard(rating: data.friends[i - 1]),
    );
  }
}

class _AverageBox extends StatelessWidget {
  const _AverageBox({required this.data});

  final ItemRatings data;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final average = data.average;
    return _Box(
      key: const Key('friend-ratings-average'),
      child: average == null
          ? Center(
              child: Text(l.ratingNoFriendsYet,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: WfColors.creamMuted)))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(formatRatingAverage(average, l.localeName),
                    style: WfText.display(40, color: WfColors.gold)),
                const SizedBox(height: 6),
                Text(l.ratingFriendsCount(data.count),
                    style: const TextStyle(color: WfColors.creamMuted)),
              ],
            ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({required this.rating});

  final FriendRating rating;

  @override
  Widget build(BuildContext context) {
    final comment = rating.comment;
    return _Box(
      key: Key('friend-rating-${rating.userId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            UserAvatar.lookup(
                userId: rating.userId, name: rating.name, size: 32, muted: true),
            const SizedBox(width: 8),
            Expanded(
                child: Text(rating.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${rating.score}',
                style: WfText.display(24, color: WfColors.gold)),
          ]),
          if (comment != null) ...[
            const SizedBox(height: 8),
            Expanded(
              child: Tooltip(
                message: comment,
                child: Text(comment,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: WfColors.creamMuted)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: _cardWidth,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WfColors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: WfColors.border),
        ),
        child: child,
      );
}

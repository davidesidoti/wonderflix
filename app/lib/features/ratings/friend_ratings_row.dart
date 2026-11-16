import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/rating_models.dart';
import '../../core/social/social_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/media_row.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
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

/// I voti di [itemId] se la riga si mostra (funzione attiva, dati arrivati,
/// amici o `canRate`), altrimenti `null`.
ItemRatings? _watchRatings(WidgetRef ref, String itemId) {
  if (!ref.watch(socialAvailabilityProvider.select((f) => f.ratings))) {
    return null;
  }
  // Segnare il titolo come visto cambia chi può votare: si rilegge.
  ref.listen(
    userDataOverridesProvider.select((m) => m[itemId]?.played),
    (_, _) => ref.invalidate(itemRatingsProvider(itemId)),
  );
  ref.listen(itemRatingsProvider(itemId), (_, next) {
    final error = next.error;
    if (error == null) return;
    _log.info(
      'voti non letti: ${error is SocialException ? error.failure.name : error.runtimeType}',
    );
  });
  final data = ref.watch(itemRatingsProvider(itemId)).value;
  if (data == null || (data.friends.isEmpty && !data.canRate)) return null;
  return data;
}

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
    final data = _watchRatings(ref, item.id);
    if (data == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final mine = data.mine;
    return MediaRow(
      title: title ?? l.ratingFriendsRow,
      height: _rowHeight,
      itemCount: data.friends.length + 1,
      trailing: mine == null && !data.canRate
          ? null
          : WfButton.secondary(
              key: const Key('friend-ratings-action'),
              small: true,
              label: mine == null ? l.ratingVote : l.ratingMine(mine.score),
              icon: mine == null ? LucideIcons.star : LucideIcons.pencil,
              gold: mine != null,
              onPressed: onRate == null ? null : () => onRate!(data),
            ),
      itemBuilder: (context, i) => i == 0
          ? _AverageBox(data: data)
          : _FriendCard(rating: data.friends[i - 1]),
    );
  }
}

/// I voti della stagione scelta in una riga bassa sotto le schede. Sulla TV
/// niente pulsante né focus: si vota con "Vota" della testata.
class SeasonRatingsStrip extends ConsumerWidget {
  const SeasonRatingsStrip({
    super.key,
    required this.season,
    required this.title,
    this.onRate,
  });

  final JellyfinItem season;
  final String title;
  final ValueChanged<ItemRatings>? onRate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = _watchRatings(ref, season.id);
    if (data == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final compact = form.compact && !form.tv;
    final average = data.average;
    final mine = data.mine;
    final info = <Widget>[
      Text(
        title,
        style: const TextStyle(fontSize: 12.5, color: WfColors.creamMuted),
      ),
      if (average == null)
        Text(
          l.ratingNoFriendsYet,
          style: const TextStyle(color: WfColors.creamMuted),
        )
      else ...[
        Text(
          formatRatingAverage(average, l.localeName),
          key: const Key('friend-ratings-average'),
          style: WfText.display(28, color: WfColors.gold),
        ),
        Text(
          l.ratingFriendsCount(data.count),
          style: const TextStyle(color: WfColors.creamMuted),
        ),
      ],
      for (final f in data.friends) _FriendPill(rating: f),
    ];
    final button = form.tv || (mine == null && !data.canRate)
        ? null
        : WfButton.secondary(
            key: const Key('friend-ratings-action'),
            small: true,
            gold: mine != null,
            label: mine == null ? l.ratingRateSeason : l.ratingMine(mine.score),
            icon: LucideIcons.star,
            onPressed: onRate == null ? null : () => onRate!(data),
          );
    return Container(
      margin: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WfColors.surface)),
      ),
      child: compact
          ? Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [...info, ?button],
            )
          : Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: info,
                  ),
                ),
                if (button != null) ...[const SizedBox(width: 12), button],
              ],
            ),
    );
  }
}

class _FriendPill extends StatelessWidget {
  const _FriendPill({required this.rating});

  final FriendRating rating;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('friend-rating-${rating.userId}'),
    padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
    decoration: BoxDecoration(
      color: WfColors.surfaceHigh,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: WfColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UserAvatar.lookup(
          userId: rating.userId,
          name: rating.name,
          size: 24,
          muted: true,
        ),
        const SizedBox(width: 6),
        Text(rating.name, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        Text(
          '${rating.score}',
          style: WfText.display(18, color: WfColors.gold),
        ),
      ],
    ),
  );
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

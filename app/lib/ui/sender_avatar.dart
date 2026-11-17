import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../features/library/library_providers.dart';
import 'user_avatar.dart';
import 'wf_image.dart';

const _cornerOverhang = 4.0;

/// L'avatar di chi manda una notifica (spec §7): in basso a destra, sporgente,
/// la locandina del titolo o, senza, un simbolo del tipo di voce.
///
/// Per i lettori di schermo è decorativo: il nome è nella frase accanto.
class SenderAvatar extends StatelessWidget {
  const SenderAvatar({
    super.key,
    required this.name,
    this.userId,
    this.posterItemId,
    this.badge,
    this.size = 40,
  });

  final String name;
  final String? userId;
  final String? posterItemId;
  final IconData? badge;
  final double size;

  @override
  Widget build(BuildContext context) => _Overlaid(
        size: size,
        posterItemId: posterItemId,
        badge: badge,
        child: UserAvatar.lookup(
            userId: userId, name: name, size: size, muted: true),
      );
}

/// Il cerchio delle voci del sistema (spazio, riavvio, download): un'icona
/// oro, rossa con [alarm].
class SystemAvatar extends StatelessWidget {
  const SystemAvatar({
    super.key,
    required this.icon,
    this.alarm = false,
    this.posterItemId,
    this.size = 40,
  });

  final IconData icon;
  final bool alarm;
  final String? posterItemId;
  final double size;

  @override
  Widget build(BuildContext context) => _Overlaid(
        size: size,
        posterItemId: posterItemId,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: WfColors.surfaceHigh,
            border: alarm ? Border.all(color: WfColors.error) : null,
          ),
          child: Icon(icon,
              size: 18, color: alarm ? WfColors.error : WfColors.gold),
        ),
      );
}

class _Overlaid extends StatelessWidget {
  const _Overlaid({
    required this.size,
    required this.child,
    this.posterItemId,
    this.badge,
  });

  final double size;
  final Widget child;
  final String? posterItemId;
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    final poster = posterItemId;
    final icon = badge;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (poster != null)
              Positioned(
                  right: -_cornerOverhang,
                  bottom: -_cornerOverhang,
                  child: _Poster(itemId: poster))
            else if (icon != null)
              Positioned(
                  right: -_cornerOverhang,
                  bottom: -_cornerOverhang,
                  child: Container(
                    key: const Key('sender-badge'),
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: WfColors.surfaceHigh),
                    child: Icon(icon, size: 11, color: WfColors.gold),
                  )),
          ],
        ),
      ),
    );
  }
}

class _Poster extends ConsumerWidget {
  const _Poster({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        key: const Key('sender-poster'),
        width: 18,
        height: 27,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: WfColors.surface, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: WfImage(image: ref.watch(imageUrlsProvider).primaryOf(itemId)),
      );
}

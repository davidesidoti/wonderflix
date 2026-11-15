import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/json_fields.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../library/my_list_added.dart';
import '../library/user_data.dart';
import 'my_list_screen.dart';

/// Toglie [items] dalla lista (spec §9) e mostra per 5 s [message] con
/// Annulla, che rimette i cuori con le date di aggiunta di prima. Se qualcuno
/// non si toglie, l'avviso dice quanti.
Future<void> removeFromMyList(
  BuildContext context,
  WidgetRef ref,
  List<JellyfinItem> items, {
  required String message,
}) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  // La card tolta sparisce subito, e con lei `ref`: Annulla usa il container.
  final container = ProviderScope.containerOf(context, listen: false);
  final overrides = ref.read(userDataOverridesProvider.notifier);
  // Le date prima di togliere: togliendo si cancellano. Si aspettano anche
  // se in lettura, o da rileggere: se no Annulla le perderebbe. Ogni id c'è,
  // `null` per chi non ne aveva una: Annulla non gliela inventa.
  final added =
      await container.read(myListAddedProvider.notifier).fresh() ?? const {};
  final dates = {for (final i in items) i.id: added[jellyfinIdKey(i.id)]};
  final failed = await overrides.setFavorites(items, favorite: false);
  // Non tolti anche i saltati (una richiesta già in corso).
  final removed = [
    for (final i in items)
      if (!failed.contains(i) && !overrides.effective(i).isFavorite) i,
  ];
  if (removed.isEmpty && failed.isEmpty) return;
  messenger?.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 5),
      // Con un'azione la SnackBar resterebbe finché non la si tocca.
      persist: false,
      content: Text(
        failed.isEmpty ? message : l.myListRemoveFailed(failed.length),
      ),
      action: removed.isEmpty
          ? null
          : SnackBarAction(
              label: l.actionUndo,
              onPressed: () => unawaited(() async {
                final notRestored = await overrides.setFavorites(
                  removed,
                  favorite: true,
                  addedAt: dates,
                );
                if (notRestored.isNotEmpty) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(l.myListRestoreFailed(notRestored.length)),
                    ),
                  );
                }
                // Una lista ricaricata intanto non ha più i titoli.
                container.invalidate(favoritesProvider);
              }()),
            ),
    ),
  );
}

/// Avvolge una card della pagina: col mouse sopra o col focus dentro, il
/// cuore in alto a destra dell'immagine e, con [onPlay], il play in basso a
/// destra (alta [imageHeight]). Sul touch e in TV la card resta com'è.
class MyListRemovable extends ConsumerStatefulWidget {
  const MyListRemovable({
    super.key,
    required this.item,
    required this.child,
    required this.imageHeight,
    this.onPlay,
    this.playTooltip,
  });

  final JellyfinItem item;
  final Widget child;
  final double imageHeight;
  final VoidCallback? onPlay;

  /// Il tooltip del play; senza, "Riproduci".
  final String? playTooltip;

  @override
  ConsumerState<MyListRemovable> createState() => _MyListRemovableState();
}

class _MyListRemovableState extends ConsumerState<MyListRemovable> {
  bool _hover = false;
  bool _focused = false;

  static const _gap = 8.0;
  static const _playSize = 40.0;

  @override
  Widget build(BuildContext context) {
    final form = FormFactor.of(context);
    if (form.touch || form.tv) return widget.child;
    final l = AppLocalizations.of(context);
    final item = widget.item;
    final onPlay = widget.onPlay;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_hover || _focused) ...[
              Positioned(
                top: _gap,
                right: _gap,
                child: IconButton(
                  tooltip: l.myListRemoveTooltip,
                  onPressed: () => unawaited(
                    removeFromMyList(context, ref, [
                      item,
                    ], message: l.myListRemoved(item.name)),
                  ),
                  style: IconButton.styleFrom(
                    // Senza i 48 px di Material: il bordo è quello visibile.
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size.square(36),
                    fixedSize: const Size.square(36),
                    backgroundColor: WfColors.bg.withValues(alpha: 0.75),
                    foregroundColor: WfColors.gold,
                  ),
                  icon: const Icon(LucideIcons.heart, size: 18),
                ),
              ),
              if (onPlay != null)
                Positioned(
                  top: widget.imageHeight - _gap - _playSize,
                  right: _gap,
                  child: IconButton(
                    tooltip: widget.playTooltip ?? l.actionPlay,
                    onPressed: onPlay,
                    style: IconButton.styleFrom(
                      // Senza i 48 px di Material: il bordo è quello visibile.
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: const Size.square(_playSize),
                      fixedSize: const Size.square(_playSize),
                      backgroundColor: WfColors.gold,
                      foregroundColor: WfColors.bg,
                    ),
                    icon: const Icon(LucideIcons.play, size: 18),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

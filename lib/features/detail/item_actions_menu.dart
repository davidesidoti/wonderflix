import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import '../admin/admin_providers.dart';
import '../reports/reports_providers.dart';
import '../social/social_providers.dart';
import 'media_info_dialog.dart';

/// Le voci del menu "⋯" di un titolo (spec R §7.2). Il piano 24c ne aggiunge
/// altre.
enum ItemAction { report, mediaInfo, subtitles }

/// Lato del bottone: lo stesso di `WfIconToggle`.
const _buttonSize = 44.0;
const _iconSize = 20.0;

/// Le voci per un [kind] e per i permessi, a gruppi (tutti, sottotitoli,
/// admin) e senza i gruppi vuoti; fra un gruppo e l'altro il menu mette un
/// separatore. Il gruppo admin è vuoto finché non arrivano gli strumenti dei
/// metadati (piano 24c).
List<List<ItemAction>> itemActionGroups({
  required ItemKind kind,
  required bool reports,
  required bool canManageSubtitles,
  required bool isAdmin,
}) {
  final isFile = kind == ItemKind.movie || kind == ItemKind.episode;
  final groups = <List<ItemAction>>[
    [
      if (reports &&
          (isFile || kind == ItemKind.series || kind == ItemKind.season))
        ItemAction.report,
      if (isFile) ItemAction.mediaInfo,
    ],
    [if (canManageSubtitles && isFile) ItemAction.subtitles],
    const [],
  ];
  return [
    for (final group in groups)
      if (group.isNotEmpty) group,
  ];
}

String _label(AppLocalizations l, ItemAction action) => switch (action) {
      ItemAction.report => l.reportDialogTitle,
      ItemAction.mediaInfo => l.mediaInfoTitle,
      ItemAction.subtitles => l.subtitlesDialogTitle,
    };

/// Il bottone "⋯" di un titolo: film, serie, stagione o episodio. Senza voci
/// da mostrare non c'è.
class ItemActionsButton extends ConsumerWidget {
  const ItemActionsButton({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = itemActionGroups(
      kind: item.kind,
      reports: ref.watch(socialAvailabilityProvider.select((f) => f.reports)),
      canManageSubtitles: ref.watch(canManageSubtitlesProvider),
      isAdmin: ref.watch(isAdminProvider),
    );
    if (groups.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return SizedBox.square(
      dimension: _buttonSize,
      child: PopupMenuButton<ItemAction>(
        tooltip: l.itemActionsMenu,
        padding: EdgeInsets.zero,
        icon: const Icon(LucideIcons.ellipsis,
            size: _iconSize, color: WfColors.cream),
        popUpAnimationStyle: wfPopUpAnimation(context),
        onSelected: (action) => _run(context, action),
        itemBuilder: (context) => [
          for (final (i, group) in groups.indexed) ...[
            if (i > 0) const PopupMenuDivider(),
            for (final action in group)
              PopupMenuItem<ItemAction>(
                  value: action, child: Text(_label(l, action))),
          ],
        ],
      ),
    );
  }

  void _run(BuildContext context, ItemAction action) {
    switch (action) {
      case ItemAction.report:
        break; // Task 4: showReportDialog(context, item).
      case ItemAction.mediaInfo:
        showMediaInfoDialog(context, item);
      case ItemAction.subtitles:
        break; // Task 5: showSubtitlesDialog(context, itemId: item.id, title: item.name).
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import '../admin/admin_providers.dart';
import '../item_edit/edit_metadata_dialog.dart';
import '../item_edit/identify_dialog.dart';
import '../item_edit/images_dialog.dart';
import '../item_edit/refresh_metadata_dialog.dart';
import '../reports/report_dialog.dart';
import '../reports/reports_providers.dart';
import '../social/social_providers.dart';
import '../subtitles/subtitles_dialog.dart';
import 'media_info_dialog.dart';

/// Le voci del menu "⋯" di un titolo (spec R §7.2). Le ultime quattro sono
/// solo per gli admin.
enum ItemAction {
  report,
  mediaInfo,
  subtitles,
  editMetadata,
  identify,
  refresh,
  images,
}

/// Lato del bottone: lo stesso di `WfIconToggle`.
const _buttonSize = 44.0;
const _iconSize = 20.0;

/// Le voci per un [kind] e per i permessi, a gruppi (tutti, sottotitoli,
/// admin) e senza i gruppi vuoti; fra un gruppo e l'altro il menu mette un
/// separatore. Il gruppo admin sono gli strumenti dei metadati (spec R
/// §7.8–7.11).
List<List<ItemAction>> itemActionGroups({
  required ItemKind kind,
  required bool reports,
  required bool canManageSubtitles,
  required bool isAdmin,
}) {
  final isFile = kind == ItemKind.movie || kind == ItemKind.episode;
  final isTitle = kind == ItemKind.movie || kind == ItemKind.series;
  final groups = <List<ItemAction>>[
    [
      if (reports &&
          (isFile || kind == ItemKind.series || kind == ItemKind.season))
        ItemAction.report,
      if (isFile) ItemAction.mediaInfo,
    ],
    [if (canManageSubtitles && isFile) ItemAction.subtitles],
    [
      if (isAdmin &&
          (isTitle || kind == ItemKind.season || kind == ItemKind.episode)) ...[
        ItemAction.editMetadata,
        if (isTitle) ItemAction.identify,
        ItemAction.refresh,
        ItemAction.images,
      ],
    ],
  ];
  return [
    for (final group in groups)
      if (group.isNotEmpty) group,
  ];
}

String _label(AppLocalizations l, ItemAction action) => switch (action) {
      ItemAction.report => l.itemActionReport,
      ItemAction.mediaInfo => l.itemActionMediaInfo,
      ItemAction.subtitles => l.itemActionSubtitles,
      ItemAction.editMetadata => l.itemActionEditMetadata,
      ItemAction.identify => l.itemActionIdentify,
      ItemAction.refresh => l.itemActionRefresh,
      ItemAction.images => l.itemActionImages,
    };

/// Voce in più del menu "⋯", in cima: un'azione della testata che nel
/// layout stretto non ha un pulsante suo.
typedef ExtraItemAction = ({String label, VoidCallback onSelected});

/// Il bottone "⋯" di un titolo: film, serie, stagione o episodio. Senza voci
/// da mostrare non c'è.
class ItemActionsButton extends ConsumerWidget {
  const ItemActionsButton(
      {super.key, required this.item, this.extra = const []});

  final JellyfinItem item;
  final List<ExtraItemAction> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = itemActionGroups(
      kind: item.kind,
      reports: ref.watch(socialAvailabilityProvider.select((f) => f.reports)),
      canManageSubtitles: ref.watch(canManageSubtitlesProvider),
      isAdmin: ref.watch(isAdminProvider),
    );
    if (groups.isEmpty && extra.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return SizedBox.square(
      dimension: _buttonSize,
      // Il valore è un'[ItemAction] o una voce di [extra]: scelta a menu
      // chiuso, così un'azione che apre una pagina non viene chiusa con lui.
      child: PopupMenuButton<Object>(
        tooltip: l.itemActionsMenu,
        padding: EdgeInsets.zero,
        icon: const Icon(LucideIcons.ellipsis,
            size: _iconSize, color: WfColors.cream),
        popUpAnimationStyle: wfPopUpAnimation(context),
        onSelected: (value) {
          switch (value) {
            case ItemAction action:
              _run(context, action);
            case (label: _, :final VoidCallback onSelected):
              onSelected();
          }
        },
        itemBuilder: (context) => [
          for (final entry in extra)
            PopupMenuItem<Object>(value: entry, child: Text(entry.label)),
          for (final (i, group) in groups.indexed) ...[
            if (i > 0 || extra.isNotEmpty) const PopupMenuDivider(),
            for (final action in group)
              PopupMenuItem<Object>(
                  value: action, child: Text(_label(l, action))),
          ],
        ],
      ),
    );
  }

  void _run(BuildContext context, ItemAction action) {
    switch (action) {
      case ItemAction.report:
        unawaited(showReportDialog(context, item));
      case ItemAction.mediaInfo:
        showMediaInfoDialog(context, item);
      case ItemAction.subtitles:
        unawaited(
            showSubtitlesDialog(context, itemId: item.id, title: item.name));
      case ItemAction.editMetadata:
        unawaited(
            showEditMetadataDialog(context, itemId: item.id, kind: item.kind));
      case ItemAction.identify:
        unawaited(
            showIdentifyDialog(context, itemId: item.id, kind: item.kind));
      case ItemAction.refresh:
        unawaited(showRefreshMetadataDialog(context, itemId: item.id));
      case ItemAction.images:
        unawaited(showImagesDialog(context, itemId: item.id, kind: item.kind));
    }
  }
}

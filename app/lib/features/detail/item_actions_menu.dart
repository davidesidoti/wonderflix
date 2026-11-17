import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';
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

/// Le voci per un [kind] e per i permessi, a gruppi ("Controlla e segnala" e
/// "Admin") e senza i gruppi vuoti. Il gruppo admin sono gli strumenti dei
/// metadati (spec R §7.8–7.11).
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
      if (canManageSubtitles && isFile) ItemAction.subtitles,
    ],
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
typedef ExtraItemAction = ({
  String label,
  IconData icon,
  VoidCallback onSelected,
});

IconData _icon(ItemAction action) => switch (action) {
  ItemAction.report => LucideIcons.flag,
  ItemAction.mediaInfo => LucideIcons.info,
  ItemAction.subtitles => LucideIcons.captions,
  ItemAction.editMetadata => LucideIcons.pencil,
  ItemAction.identify => LucideIcons.scanSearch,
  ItemAction.refresh => LucideIcons.refreshCw,
  ItemAction.images => LucideIcons.image,
};

const _groupHeaderHeight = 32.0;
const _dividerHeight = 16.0;
const _menuPadding = 16.0;

/// Altezza prevista del menu, per aprirlo sopra il ⋯ se sotto non ci sta:
/// [groups] gruppi (con quello delle voci in più), [rows] voci in tutto.
double itemActionsMenuHeight({
  required int groups,
  required int rows,
  required bool tv,
}) =>
    _menuPadding +
    groups * _groupHeaderHeight +
    (groups - 1) * _dividerHeight +
    rows * (tv ? 44 : kMinInteractiveDimension);

/// Voce del menu su TV: il bordo di focus avvolge l'intera voce; la prima
/// voce prende il focus all'apertura.
class _TvEntry extends PopupMenuEntry<Object> {
  const _TvEntry({required this.item, required this.first});

  final PopupMenuItem<Object> item;
  final bool first;

  @override
  double get height => item.height;

  @override
  bool represents(Object? value) => item.represents(value);

  @override
  State<_TvEntry> createState() => _TvEntryState();
}

class _TvEntryState extends State<_TvEntry> {
  @override
  void initState() {
    super.initState();
    if (widget.first) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scope = FocusScope.of(context);
        if (scope.focusedChild == null) scope.nextFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) => TvFocusBorder(child: widget.item);
}

/// Il bottone "⋯" di un titolo: film, serie, stagione o episodio. Senza voci
/// da mostrare non c'è.
class ItemActionsButton extends ConsumerWidget {
  const ItemActionsButton({
    super.key,
    required this.item,
    this.extra = const [],
    this.tvOnly = false,
  });

  final JellyfinItem item;
  final List<ExtraItemAction> extra;

  /// Sulla TV: solo "Segnala un problema" e "Info tecniche", senza sottotitoli
  /// né strumenti dei metadati.
  final bool tvOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = itemActionGroups(
      kind: item.kind,
      reports: ref.watch(socialAvailabilityProvider.select((f) => f.reports)),
      canManageSubtitles: !tvOnly && ref.watch(canManageSubtitlesProvider),
      isAdmin: !tvOnly && ref.watch(isAdminProvider),
    );
    if (groups.isEmpty && extra.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return SizedBox.square(
      dimension: _buttonSize,
      child: IconButton(
        tooltip: l.itemActionsMenu,
        padding: EdgeInsets.zero,
        icon: const Icon(
          LucideIcons.ellipsis,
          size: _iconSize,
          color: WfColors.cream,
        ),
        onPressed: () => unawaited(_open(context, l, groups)),
      ),
    );
  }

  /// Il valore scelto è un'[ItemAction] o una voce di [extra]: l'azione parte
  /// a menu chiuso, così una finestra che apre non viene chiusa con lui.
  Future<void> _open(
    BuildContext context,
    AppLocalizations l,
    List<List<ItemAction>> groups,
  ) async {
    final tv = FormFactor.of(context).tv;
    // (nome del gruppo, voci): "La tua visione" prima, poi i gruppi.
    final sections = <(String, List<(Object, IconData, String)>)>[
      if (extra.isNotEmpty)
        (
          l.itemActionsGroupMine,
          [for (final e in extra) (e, e.icon, e.label)],
        ),
      for (final group in groups)
        (
          group.first == ItemAction.editMetadata
              ? l.itemActionsGroupAdmin
              : l.itemActionsGroupCheck,
          [for (final a in group) (a, _icon(a), _label(l, a))],
        ),
    ];
    final rows = sections.fold(0, (n, s) => n + s.$2.length);
    final height = tv ? 44.0 : kMinInteractiveDimension;
    var first = true;
    PopupMenuEntry<Object> entry(Object value, IconData icon, String label) {
      final item = PopupMenuItem<Object>(
        value: value,
        height: height,
        child: Row(
          children: [
            Icon(icon, size: 18, color: WfColors.creamMuted),
            const SizedBox(width: 12),
            Flexible(child: Text(label)),
          ],
        ),
      );
      if (!tv) return item;
      final tvEntry = _TvEntry(item: item, first: first);
      first = false;
      return tvEntry;
    }

    final value = await showMenu<Object>(
      context: context,
      useRootNavigator: true,
      // Più largo del 280 predefinito: sulla TV una voce non va a capo.
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 360),
      popUpAnimationStyle: wfPopUpAnimation(context),
      position: menuPositionBelow(
        context,
        estimatedHeight: itemActionsMenuHeight(
          groups: sections.length,
          rows: rows,
          tv: tv,
        ),
      ),
      items: [
        for (final (i, (name, entries)) in sections.indexed) ...[
          if (i > 0) const PopupMenuDivider(),
          PopupMenuItem<Object>(
            enabled: false,
            height: _groupHeaderHeight,
            child: Semantics(
              header: true,
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: WfColors.creamMuted,
                ),
              ),
            ),
          ),
          for (final (value, icon, label) in entries)
            entry(value, icon, label),
        ],
      ],
    );
    if (!context.mounted) return;
    switch (value) {
      case ItemAction action:
        _run(context, action);
      case (label: _, icon: _, :final VoidCallback onSelected):
        onSelected();
    }
  }

  void _run(BuildContext context, ItemAction action) {
    switch (action) {
      case ItemAction.report:
        unawaited(showReportDialog(context, item));
      case ItemAction.mediaInfo:
        showMediaInfoDialog(context, item);
      case ItemAction.subtitles:
        unawaited(
          showSubtitlesDialog(context, itemId: item.id, title: item.name),
        );
      case ItemAction.editMetadata:
        unawaited(
          showEditMetadataDialog(context, itemId: item.id, kind: item.kind),
        );
      case ItemAction.identify:
        unawaited(
          showIdentifyDialog(context, itemId: item.id, kind: item.kind),
        );
      case ItemAction.refresh:
        unawaited(showRefreshMetadataDialog(context, item: item));
      case ItemAction.images:
        unawaited(showImagesDialog(context, itemId: item.id, kind: item.kind));
    }
  }
}

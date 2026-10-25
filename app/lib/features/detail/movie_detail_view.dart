import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/motion.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/staggered_entrance.dart';
import '../collections/collection_rows.dart';
import '../library/user_data.dart';
import '../ratings/friend_ratings_row.dart';
import '../ratings/rate_panel.dart';
import '../playback/play_launcher.dart';
import '../reports/reports_banner.dart';
import 'detail_header.dart';
import 'detail_rows.dart';
import 'header_parallax.dart';
import 'primary_action.dart';

/// Scheda di un film (usata anche per un episodio aperto direttamente).
class MovieDetailView extends ConsumerWidget {
  const MovieDetailView({
    super.key,
    required this.item,
    this.controller,
    this.entranceDelay = Duration.zero,
    this.headerKey,
  });

  final JellyfinItem item;

  /// Scroll della pagina (lo segue anche lo sfondo della scheda).
  final ScrollController? controller;

  /// Attesa prima dell'entrata scaglionata (a volo Hero finito).
  final Duration entranceDelay;

  /// Chiave della testata: nel layout stretto dice quando il titolo va
  /// nella barra (`barTitleVisible`).
  final GlobalKey? headerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = watchUserData(ref, item);
    final action = primaryActionFor(item, userData);
    final page = StaggerGroup(
      count: detailEntranceCount,
      delay: entranceDelay,
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          DetailHeader(
              key: headerKey,
              item: item,
              primary: action,
              controller: controller),
          // Fuori dalle StaggerItem: detailEntranceCount non cambia.
          if (item.kind == ItemKind.movie) ReportsBanner(titleId: item.id),
          // Un episodio aperto da solo non ha la riga (si vota la stagione).
          if (item.kind == ItemKind.movie)
            StaggerItem(
              index: 5,
              child: FriendRatingsRow(
                item: item,
                onRate: (r) => openRatePanel(context,
                    ref, RateSubject(item: item, title: item.name, mine: r.mine)),
              ),
            ),
          if (item.people.isNotEmpty)
            StaggerItem(index: 6, child: CastRow(people: item.people)),
          StaggerItem(index: 7, child: CollectionRows(itemId: item.id)),
          StaggerItem(index: 8, child: SimilarRow(itemId: item.id)),
        ],
      ),
    );
    final scroll = controller;
    // Senza controller (vista montata da sola nei test) niente titolo nella
    // barra.
    if (scroll == null) return page;
    final l = AppLocalizations.of(context);
    final reduced = WfMotion.of(context).isReduced;
    final compactHeader = FormFactor.of(context).compact ? headerKey : null;
    return ShellHeaderPublisher(
      controller: scroll,
      visibleAt: (offset) => barTitleVisible(offset,
          reduced: reduced, compactHeader: compactHeader),
      header: ShellHeader(
        title: item.name,
        actionLabel: primaryActionLabel(l, action),
        onAction: () => unawaited(playItem(context, ref, action.target)),
      ),
      child: page,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../../ui/staggered_entrance.dart';
import '../library/user_data.dart';
import 'detail_header.dart';
import 'detail_rows.dart';
import 'primary_action.dart';

/// Scheda di un film (usata anche per un episodio aperto direttamente).
class MovieDetailView extends ConsumerWidget {
  const MovieDetailView({
    super.key,
    required this.item,
    this.controller,
    this.entranceDelay = Duration.zero,
  });

  final JellyfinItem item;

  /// Scroll della pagina (lo segue anche lo sfondo della scheda).
  final ScrollController? controller;

  /// Attesa prima dell'entrata scaglionata (a volo Hero finito).
  final Duration entranceDelay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = watchUserData(ref, item);
    return StaggerGroup(
      count: detailEntranceCount,
      delay: entranceDelay,
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          DetailHeader(
              item: item,
              primary: primaryActionFor(item, userData),
              controller: controller),
          if (item.people.isNotEmpty)
            StaggerItem(index: 5, child: CastRow(people: item.people)),
          StaggerItem(index: 6, child: SimilarRow(itemId: item.id)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/item_models.dart';
import '../library/user_data.dart';
import 'detail_header.dart';
import 'detail_rows.dart';
import 'primary_action.dart';

/// Scheda di un film (usata anche per un episodio aperto direttamente).
class MovieDetailView extends ConsumerWidget {
  const MovieDetailView({super.key, required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userData = watchUserData(ref, item);
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        DetailHeader(item: item, primary: primaryActionFor(item, userData)),
        if (item.people.isNotEmpty) CastRow(itemId: item.id, people: item.people),
        SimilarRow(itemId: item.id),
      ],
    );
  }
}

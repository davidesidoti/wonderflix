import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/library_providers.dart';
import 'wf_image.dart';

/// La locandina 36×54 nella testa delle finestre su un titolo.
class DialogItemPoster extends ConsumerWidget {
  const DialogItemPoster({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      width: 36,
      height: 54,
      child: WfImage(image: ref.watch(imageUrlsProvider).primaryOf(itemId)),
    ),
  );
}

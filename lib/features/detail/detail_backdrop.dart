import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/hero_launch.dart';
import '../../core/jellyfin/item_models.dart';
import '../../ui/backdrop_image.dart';
import '../library/library_providers.dart';

/// Sfondo della scheda, dietro al contenuto. Segue lo scroll della pagina
/// (nel piano 6b diventerà la parallasse). Mentre la scheda carica usa le
/// immagini di [launch]: è la destinazione del volo Hero, e deve esserci
/// dal primo fotogramma (spec C §6.2).
class DetailBackdrop extends ConsumerWidget {
  const DetailBackdrop({
    super.key,
    required this.item,
    required this.launch,
    required this.controller,
  });

  /// `null` mentre la scheda carica.
  final JellyfinItem? item;
  final HeroLaunch? launch;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(imageUrlsProvider);
    final current = item;
    // Stesso URL della card (`openItem` usa `urls.backdrop`): all'arrivo dei
    // dati l'immagine non cambia.
    final image = BackdropImage(
      backdrop: current != null ? urls.backdrop(current) : launch?.image,
      fallback: current != null ? urls.poster(current) : launch?.fallback,
    );
    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, controller.hasClients ? -controller.offset : 0),
          child: child,
        ),
        child: WfHero(tag: launch?.tag, child: image),
      ),
    );
  }
}

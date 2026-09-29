import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import '../playback/play_launcher.dart';

/// Titoli in evidenza a tutta larghezza; cambia ogni 8 secondi.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.items});

  final List<JellyfinItem> items;

  static const interval = Duration(seconds: 8);

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(HeroCarousel.interval, (_) => _next());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (!_controller.hasClients) return;
    final next = (_index + 1) % widget.items.length;
    _controller.animateToPage(next,
        duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 460,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _HeroSlide(item: widget.items[i]),
          ),
          Positioned(
            right: 32,
            bottom: 20,
            child: Row(
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  Container(
                    width: i == _index ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: i == _index ? WfColors.gold : WfColors.creamMuted,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSlide extends ConsumerWidget {
  const _HeroSlide({required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final logo = urls.logo(item);
    final runtime = item.runtime;
    final seasons = item.childCount;
    final meta = [
      if (item.productionYear != null) '${item.productionYear}',
      if (item.kind == ItemKind.movie && runtime != null) formatRuntime(runtime),
      if (item.kind == ItemKind.series && seasons != null) l.detailSeasons(seasons),
      ...item.genres.take(2),
    ].join(' · ');

    return Stack(
      fit: StackFit.expand,
      children: [
        WfImage(image: urls.backdrop(item)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [WfColors.bg, Color(0xCC0A0A0A), Colors.transparent],
              stops: [0, 0.35, 0.75],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [WfColors.bg, Colors.transparent],
              stops: [0, 0.45],
            ),
          ),
        ),
        Positioned(
          left: 32,
          bottom: 48,
          width: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (logo != null)
                SizedBox(
                  height: 110,
                  width: 420,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: WfImage(image: logo, fit: BoxFit.contain),
                  ),
                )
              else
                Text(item.name.toUpperCase(),
                    maxLines: 2, style: WfText.display(56)),
              const SizedBox(height: 10),
              Text(meta, style: const TextStyle(color: WfColors.creamMuted)),
              if (item.overview != null) ...[
                const SizedBox(height: 10),
                Text(item.overview!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(height: 1.45)),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  WfButton.primary(
                    label: l.actionPlay,
                    icon: LucideIcons.play,
                    onPressed: () => playItem(context, item),
                  ),
                  WfButton.secondary(
                    label: l.actionDetails,
                    icon: LucideIcons.info,
                    onPressed: () => openItem(context, item),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

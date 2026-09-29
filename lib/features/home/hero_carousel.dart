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
    _startTimer();
  }

  @override
  void didUpdateWidget(HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length == widget.items.length) return;
    _startTimer();
    final last = widget.items.length - 1;
    if (last >= 0 && _index > last) {
      _index = last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(last);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = widget.items.length > 1
        ? Timer.periodic(HeroCarousel.interval, (_) => _next())
        : null;
  }

  void _goTo(int page) {
    if (!_controller.hasClients) return;
    _controller.animateToPage(page,
        duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
  }

  void _next() {
    // La Home è coperta da un'altra pagina: niente animazioni nascoste.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (widget.items.isEmpty) return;
    _goTo((_index + 1) % widget.items.length);
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
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      key: ValueKey('hero-dot-$i'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _goTo(i),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(3, 8, 3, 8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: i == _index ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color:
                                i == _index ? WfColors.gold : WfColors.creamMuted,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
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

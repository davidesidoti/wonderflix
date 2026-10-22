import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/error_text.dart';
import '../app/theme.dart';
import '../l10n/gen/app_localizations.dart';
import 'shimmer.dart';

/// Blocco dello scheletro; sotto un [WfShimmer] lo attraversa l'onda.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = 6});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shimmer = WfShimmer.maybeOf(context);
    if (shimmer == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: WfColors.surfaceHigh,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: Builder(
        builder: (context) => CustomPaint(
          key: shimmerPaintKey,
          painter: ShimmerBlockPainter(
            animation: shimmer.animation,
            shimmerBox: shimmer.box,
            selfBox: () => context.mounted
                ? context.findRenderObject() as RenderBox?
                : null,
            radius: radius,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
            width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
}

/// Errore di caricamento con messaggio localizzato e pulsante "Riprova".
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.circleAlert, color: WfColors.gold, size: 40),
            const SizedBox(height: 16),
            Text(describeError(l, error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(l.retry)),
          ],
        ),
      ),
    );
  }
}

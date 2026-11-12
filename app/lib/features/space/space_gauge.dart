import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'space_labels.dart';

/// Film, serie, anime, solo torrent, altro: dal più chiaro al più scuro.
/// Le sole sfumature fuori da `WfColors`.
const spaceGaugeColors = [
  Color(0xFFD4A64A),
  Color(0xFFB9893A),
  Color(0xFF8C6A33),
  Color(0xFF5E4A2A),
  Color(0xFF3E342A),
];

/// La barra dello spazio: un segmento d'oro per tipo e la legenda sotto.
/// Con [totalBytes] il resto fino al totale è `surfaceHigh`; senza, la barra
/// è la somma delle [parts] (5 voci, nell'ordine di [spaceGaugeColors]).
class SpaceGauge extends StatelessWidget {
  const SpaceGauge({super.key, required this.parts, this.totalBytes});

  final List<(String, int)> parts;
  final int? totalBytes;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sum = parts.fold(0, (s, p) => s + p.$2);
    final total = totalBytes;
    final rest = total == null || total <= sum ? 0 : total - sum;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            key: const ValueKey('space-gauge-bar'),
            height: 22,
            child: ColoredBox(
              color: WfColors.surfaceHigh,
              child: Row(
                children: [
                  for (var i = 0; i < parts.length; i++)
                    // Flex 0 sarebbe un figlio senza spazio: un segmento vuoto non c'è.
                    if (parts[i].$2 > 0)
                      Expanded(
                        key: ValueKey('space-gauge-$i'),
                        flex: parts[i].$2,
                        child: ColoredBox(
                          color: spaceGaugeColors[i % spaceGaugeColors.length],
                        ),
                      ),
                  if (rest > 0)
                    Expanded(
                      key: const ValueKey('space-gauge-rest'),
                      flex: rest,
                      child: const ColoredBox(color: WfColors.surfaceHigh),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (var i = 0; i < parts.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: spaceGaugeColors[i % spaceGaugeColors.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const SizedBox.square(dimension: 10),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l.spaceBreakdownItem(parts[i].$1, spaceGb(l, parts[i].$2)),
                    style: const TextStyle(
                      color: WfColors.creamMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

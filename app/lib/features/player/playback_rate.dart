import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';

/// Velocità di riproduzione che il player offre.
const playbackRates = [0.75, 1.0, 1.25, 1.5, 2.0];

/// "0,75×", "1×", "1,5×": niente zeri in coda.
String formatRate(double rate, String decimalSeparator) {
  final text = rate
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'\.?0+$'), '')
      .replaceFirst('.', decimalSeparator);
  return '$text×';
}

/// Menu delle velocità ancorato a [anchor]; la scelta in corso ha la spunta
/// oro.
Future<void> showSpeedMenu(
  BuildContext anchor, {
  required double rate,
  required ValueChanged<double> onSelected,
}) async {
  final separator = AppLocalizations.of(anchor).decimalSeparator;
  final picked = await showMenu<double>(
    context: anchor,
    position: menuPositionBelow(anchor,
        estimatedHeight: playbackRates.length * kMinInteractiveDimension),
    popUpAnimationStyle: wfPopUpAnimation(anchor),
    items: [
      for (final value in playbackRates)
        PopupMenuItem<double>(
          key: ValueKey('rate-$value'),
          value: value,
          child: Row(
            children: [
              Expanded(child: Text(formatRate(value, separator))),
              if (value == rate)
                const Icon(Icons.check, size: 18, color: WfColors.gold),
            ],
          ),
        ),
    ],
  );
  if (picked != null) onSelected(picked);
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/downloads/download_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import 'download_labels.dart';

const _bytesPerGb = 1000000000;

/// Una release sul righello dei pesi.
class RulerMark {
  const RulerMark({
    required this.sizeBytes,
    required this.score,
    this.isChoice = false,
  });

  final int sizeBytes, score;
  final bool isChoice;
}

/// Le tacche da mostrare: per le stagioni solo i pack interi
/// (`fullSeason != false`, come `hasLighter`), perché `current.sizeBytes` è la
/// stagione intera; [] sotto le 2.
List<RulerMark> rulerMarks(DownloadSearch search) {
  final marks = [
    for (final c in search.candidates)
      if (search.kind != DownloadKind.season || c.release.fullSeason != false)
        RulerMark(
          sizeBytes: c.release.sizeBytes,
          score: c.release.score,
          isChoice: c.isChoice,
        ),
  ];
  return marks.length < 2 ? const [] : marks;
}

/// L'altezza di ogni tacca: 14 + 50 × (score − min) / (max − min); punteggi
/// tutti uguali, altezza piena.
List<double> rulerHeights(List<RulerMark> marks) {
  if (marks.isEmpty) return const [];
  final lo = marks.map((m) => m.score).reduce(math.min);
  final hi = marks.map((m) => m.score).reduce(math.max);
  return [
    for (final m in marks) hi == lo ? 64.0 : 14 + 50 * (m.score - lo) / (hi - lo),
  ];
}

/// "Libera {gb}": null senza file attuale, se la scelta non pesa meno, o per
/// una stagione se la scelta non è un pack intero.
int? freedBytes(DownloadSearch search) {
  final current = search.current;
  final choice = search.candidates.where((c) => c.isChoice).firstOrNull;
  if (current == null || choice == null) return null;
  if (search.kind == DownloadKind.season &&
      choice.release.fullSeason == false) {
    return null;
  }
  final freed = current.sizeBytes - choice.release.sizeBytes;
  return freed > 0 ? freed : null;
}

/// GB/ora: solo film con runtimeMinutes > 0, altrimenti null.
double? gbPerHour(DownloadSearch search, int sizeBytes) =>
    search.kind == DownloadKind.movie && search.runtimeMinutes > 0
        ? sizeBytes / _bytesPerGb / (search.runtimeMinutes / 60)
        : null;

/// "5,3 GB/ora".
String gbPerHourLabel(AppLocalizations l, double rate) =>
    l.downloadsGbPerHour(NumberFormat('0.0', l.localeName).format(rate));

/// Il righello "Pesi a confronto": una tacca per release alla posizione del
/// suo peso, alta quanto il punteggio; la scelta in oro, il file attuale in
/// crema.
class WeightRuler extends StatelessWidget {
  const WeightRuler({super.key, required this.marks, this.currentBytes});

  final List<RulerMark> marks;
  final int? currentBytes;

  static const _pad = 16.0;
  static const _axis = 24.0;
  static const _flagWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labels = FormFactor.of(context).compact ? 3 : 5;
    final heights = rulerHeights(marks);
    final current = currentBytes;
    final top = [...marks.map((m) => m.sizeBytes), ?current].fold(0, math.max);
    // Pesi tutti a zero: tutto a sinistra, niente divisioni per zero.
    double frac(int bytes) => top > 0 ? bytes / top : 0;
    final gb = NumberFormat('0.#', l.localeName);
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 11);

    return Container(
      // Le etichette della scelta e del file stanno sopra il riquadro.
      margin: const EdgeInsets.only(top: 30),
      height: 96,
      decoration: BoxDecoration(
        color: WfColors.surface,
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final width = math.max(0.0, box.maxWidth - 2 * _pad);
        double xOf(int bytes) => _pad + frac(bytes) * width;

        Widget tick(double x, double h, Color color, double w) => Positioned(
              left: x - w / 2,
              bottom: _axis,
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(2)),
                ),
              ),
            );

        // Un'etichetta larga _flagWidth centrata su x, dentro il riquadro.
        Widget flag(double x, double bottom, String text, Color color) =>
            Positioned(
              left: (x - _flagWidth / 2)
                  .clamp(0.0, math.max(0.0, box.maxWidth - _flagWidth)),
              bottom: bottom,
              width: _flagWidth,
              child: Text(text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 11)),
            );

        final choiceIndex = marks.indexWhere((m) => m.isChoice);
        final choiceX = choiceIndex < 0 ? null : xOf(marks[choiceIndex].sizeBytes);
        final currentX = current == null ? null : xOf(current);
        // Etichette vicine: quella del file sale di una riga.
        final crowded = choiceX != null &&
            currentX != null &&
            (choiceX - currentX).abs() < _flagWidth;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _pad,
              right: _pad,
              bottom: _axis,
              child: Container(height: 1, color: WfColors.border),
            ),
            for (var i = 0; i < labels; i++)
              Positioned(
                left: _pad + width * i / (labels - 1),
                bottom: 6,
                child: FractionalTranslation(
                  translation: Offset(
                      i == 0 ? 0 : (i == labels - 1 ? -1 : -0.5), 0),
                  child: Text(
                      l.downloadsGb(
                          gb.format(top * i / (labels - 1) / _bytesPerGb)),
                      style: muted),
                ),
              ),
            for (var i = 0; i < marks.length; i++)
              if (!marks[i].isChoice)
                tick(xOf(marks[i].sizeBytes), heights[i], WfColors.creamMuted,
                    3),
            if (currentX != null) ...[
              tick(currentX, 64, WfColors.cream, 3),
              flag(currentX, _axis + 64 + (crowded ? 18 : 4),
                  l.downloadsRulerCurrent(formatGb(l, current!)),
                  WfColors.cream),
            ],
            if (choiceX != null) ...[
              tick(choiceX, heights[choiceIndex], WfColors.gold, 5),
              flag(choiceX, _axis + heights[choiceIndex] + 4,
                  l.downloadsRulerChoice(
                      formatGb(l, marks[choiceIndex].sizeBytes)),
                  WfColors.gold),
            ],
          ],
        );
      }),
    );
  }
}

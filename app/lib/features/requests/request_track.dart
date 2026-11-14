import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';
import 'request_labels.dart';

/// Il percorso di una richiesta in corso: [current] è la tappa attuale (0–3),
/// [half] la rende mezza piena ("In parte"), [fill] è quanto della linea è oro,
/// in tappe (2,42 = due tappe e il 42% verso la terza), [labels] sono le
/// quattro etichette (spec §5.4).
typedef RequestTrackModel = ({
  int current,
  bool half,
  double fill,
  List<String> labels,
});

/// Il percorso per lo stato della richiesta; null per gli stati che non sono
/// in corso (arrivata, rifiutata, non riuscita, tolta, non trovata).
RequestTrackModel? requestTrackModel(MediaRequest request, AppLocalizations l) {
  final labels = [
    l.requestsStepRequested,
    l.requestsStepApproved,
    l.requestsStepComing,
    l.requestsStepOnWonderflix,
  ];
  switch (request.status) {
    case RequestStatus.pending:
      labels[1] = l.requestsStepToApprove;
      return (current: 1, half: false, fill: 1, labels: labels);
    case RequestStatus.approved:
      return (current: 2, half: false, fill: 2, labels: labels);
    case RequestStatus.awaitingRelease:
      labels[2] = l.requestsStepNotReleased;
      return (current: 2, half: false, fill: 2, labels: labels);
    case RequestStatus.downloading:
      return (
        current: 2,
        half: false,
        fill: 2 + (request.progress?.clamp(0.0, 1.0) ?? 0),
        labels: labels,
      );
    case RequestStatus.partial:
      labels[3] = l.requestsStepPartial;
      return (current: 3, half: true, fill: 3, labels: labels);
    case RequestStatus.available ||
        RequestStatus.declined ||
        RequestStatus.failed ||
        RequestStatus.removed ||
        RequestStatus.notFound:
      return null;
  }
}

/// La riga sotto il percorso (spec §5.4); [RequestDatePart.upcoming] = in oro.
/// Vuota per gli stati che non hanno un percorso.
List<RequestDatePart> requestTrackDetail(
  MediaRequest request,
  DateTime now,
  AppLocalizations l,
) {
  RequestDatePart plain(String text) => (text: text, upcoming: false);
  switch (request.status) {
    case RequestStatus.pending:
      return [plain(l.requestsDetailPending)];
    case RequestStatus.approved:
      return [plain(l.requestsDetailApproved)];
    case RequestStatus.downloading:
      final progress = request.progress;
      return [
        plain(
          progress == null
              ? l.requestsDetailDownloading
              : l.requestsDetailPercent(
                  (progress.clamp(0.0, 1.0) * 100).round(),
                ),
        ),
      ];
    case RequestStatus.awaitingRelease:
      return requestDateParts(request, now, l);
    case RequestStatus.partial:
      final parts = requestDateParts(request, now, l);
      return parts.isEmpty ? [plain(l.requestsDetailPartial)] : parts;
    case RequestStatus.available ||
        RequestStatus.declined ||
        RequestStatus.failed ||
        RequestStatus.removed ||
        RequestStatus.notFound:
      return const [];
  }
}

const _todoDot = Color(0xFF333333);
const _dot = 12.0;
const _labelStyle = TextStyle(fontSize: 11.5, height: 1.2);

/// I quattro punti uniti da una linea, con le etichette se [labels], e sotto
/// la riga del dettaglio. Senza etichette (telefono) il dettaglio comincia
/// con la tappa attuale. [now] serve alle date (spec §5.4).
class RequestTrack extends StatelessWidget {
  const RequestTrack({
    super.key,
    required this.request,
    required this.now,
    this.labels = true,
  });

  final MediaRequest request;
  final DateTime now;
  final bool labels;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final model = requestTrackModel(request, l);
    if (model == null) return const SizedBox.shrink();
    final progress = request.status == RequestStatus.downloading
        ? request.progress
        : null;
    final semantics = l.requestsTrackSemantics(
      model.labels.take(model.current).join(', '),
      model.labels[model.current] +
          (progress == null
              ? ''
              : ', ${(progress.clamp(0.0, 1.0) * 100).round()}%'),
    );
    final motion = WfMotion.of(context);
    final lastStep = model.labels.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: semantics,
          excludeSemantics: true,
          child: SizedBox(
            height: labels ? 40 : _dot,
            child: LayoutBuilder(
              builder: (context, box) {
                final span = box.maxWidth - _dot;
                double x(int i) => _dot / 2 + span * i / lastStep;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Positioned(
                      left: _dot / 2,
                      right: _dot / 2,
                      top: 5,
                      height: 2,
                      child: ColoredBox(color: WfColors.border),
                    ),
                    Positioned(
                      left: _dot / 2,
                      top: 5,
                      height: 2,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: model.fill),
                        duration: motion.pick(
                          full: WfMotion.fast,
                          reduced: Duration.zero,
                        ),
                        builder: (context, fill, _) => SizedBox(
                          width: span * fill / lastStep,
                          child: const ColoredBox(color: WfColors.gold),
                        ),
                      ),
                    ),
                    for (var i = 0; i <= lastStep; i++) ...[
                      Positioned(
                        left: x(i) - _dot / 2,
                        top: 0,
                        child: _Dot(
                          done: i < model.current,
                          now: i == model.current && !model.half,
                          half: i == model.current && model.half,
                        ),
                      ),
                      if (labels)
                        _label(
                          model.labels[i],
                          i,
                          lastStep,
                          x(i),
                          done: i < model.current,
                          now: i == model.current,
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: labels ? 2 : 5),
          child: _detail(l, model),
        ),
      ],
    );
  }

  Widget _label(
    String text,
    int i,
    int last,
    double x, {
    required bool done,
    required bool now,
  }) {
    final label = Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: _labelStyle.copyWith(
        color: now
            ? WfColors.cream
            : done
            ? WfColors.creamMuted
            : WfColors.cream.withValues(alpha: .42),
        fontWeight: now ? FontWeight.w600 : null,
      ),
    );
    // La prima è allineata a sinistra, l'ultima a destra, le altre centrate.
    if (i == 0) return Positioned(left: 0, top: 18, child: label);
    if (i == last) return Positioned(right: 0, top: 18, child: label);
    return Positioned(
      left: x,
      top: 18,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: label,
      ),
    );
  }

  Widget _detail(AppLocalizations l, RequestTrackModel model) {
    const base = TextStyle(fontSize: 12.5, color: WfColors.creamMuted);
    const strong = TextStyle(
      color: WfColors.cream,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[
      if (!labels) ...[
        TextSpan(text: model.labels[model.current], style: strong),
        const TextSpan(text: ' · '),
      ],
    ];
    final parts = requestTrackDetail(request, now, l);
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' · '));
      final part = parts[i];
      final percent = request.status == RequestStatus.downloading
          ? RegExp(r'^\d+%').firstMatch(part.text)
          : null;
      if (percent == null) {
        spans.add(
          TextSpan(
            text: part.text,
            style: part.upcoming ? const TextStyle(color: WfColors.gold) : null,
          ),
        );
      } else {
        spans.add(TextSpan(text: percent[0], style: strong));
        spans.add(TextSpan(text: part.text.substring(percent.end)));
      }
    }
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: labels ? 1 : null,
      overflow: labels ? TextOverflow.ellipsis : TextOverflow.clip,
    );
  }
}

/// Un punto del percorso: fatto (oro pieno), attuale (anello oro con alone),
/// mezzo (metà oro, metà fondo) o da fare (grigio).
class _Dot extends StatelessWidget {
  const _Dot({required this.done, required this.now, required this.half});

  final bool done;
  final bool now;
  final bool half;

  @override
  Widget build(BuildContext context) {
    final ring = now || half;
    return Container(
      width: _dot,
      height: _dot,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: half
            ? null
            : done
            ? WfColors.gold
            : now
            ? WfColors.bg
            : _todoDot,
        gradient: half
            ? const LinearGradient(
                colors: [
                  WfColors.gold,
                  WfColors.gold,
                  WfColors.bg,
                  WfColors.bg,
                ],
                stops: [0, .5, .5, 1],
              )
            : null,
        border: ring ? Border.all(color: WfColors.gold, width: 2) : null,
        boxShadow: ring
            ? [
                BoxShadow(
                  color: WfColors.gold.withValues(alpha: .18),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import '../catalog/catalog_band.dart';
import '../detail/detail_providers.dart';
import '../library/item_labels.dart';
import '../library/user_data.dart';
import '../playback/play_launcher.dart';
import 'my_list_view.dart';

/// Altezza del cartellone (spec §12, §13). Con un pulsante ([action]) è più
/// alto del catalogo, così titolo, riga e pulsante restano sotto le schede:
/// 320 su desktop, 340 stretto, 190 sulla TV. Stretto si aggiunge il bordo
/// sicuro in alto, che abbassa le schede.
double myListBandHeight(BuildContext context, {required bool action}) {
  final form = FormFactor.of(context);
  if (form.tv) return action ? 190 : catalogBandHeight(context);
  if (!form.compact) return catalogBandHeight(context);
  return (action ? 340 : catalogBandHeight(context)) +
      MediaQuery.paddingOf(context).top;
}

/// "**8 titoli**: 1 da continuare, 4 da iniziare, 3 visti." (spec §5): il
/// conteggio della scheda in grassetto crema, poi i gruppi non vuoti.
TextSpan myListBandLine(AppLocalizations l, MyListTab tab, MyListView view) {
  final count = switch (tab) {
    MyListTab.all => l.catalogCount(view.tabCount),
    MyListTab.movies => l.myListBandMovies(view.tabCount),
    MyListTab.series => l.myListBandSeries(view.tabCount),
  };
  final groups = [
    if (view.resumeCount > 0) l.myListToResume(view.resumeCount),
    if (view.startCount > 0) l.myListToStart(view.startCount),
    if (view.watchedCount > 0) l.myListWatchedCount(view.watchedCount),
  ];
  return TextSpan(
    children: [
      TextSpan(
        text: count,
        style: const TextStyle(
          color: WfColors.cream,
          fontWeight: FontWeight.w600,
        ),
      ),
      TextSpan(text: groups.isEmpty ? '.' : ': ${groups.join(', ')}.'),
    ],
  );
}

/// Il pulsante oro col titolo di punta e la frase accanto (sotto nelle
/// finestre strette): "Riprendi" / "Riproduci" e "Da dove eri rimasto: **Titolo**".
class MyListBandAction extends ConsumerWidget {
  const MyListBandAction({
    super.key,
    required this.hero,
    required this.resuming,
    this.autofocus = false,
  });

  final JellyfinItem hero;

  /// `view.resumeCount > 0`: "Da dove eri rimasto:" invece di "Il prossimo:".
  final bool resuming;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final isSeries = hero.kind == ItemKind.series;
    final data = watchUserData(ref, hero);
    // Finché l'episodio non arriva la serie mostra "Riproduci", e il
    // pulsante apre la scheda.
    final episodeState = isSeries
        ? ref.watch(seriesNextEpisodeProvider(hero.id))
        : null;
    final episode = episodeState?.value;
    final code = episode == null ? null : episodeCode(episode);
    final target = episode ?? hero;
    final started = watchUserData(ref, target).playbackPositionTicks > 0;
    final label = switch ((code, started)) {
      (final code?, true) => l.actionResumeEpisode(code),
      (final code?, false) => l.actionPlayEpisode(code),
      (null, true) when !isSeries => l.previewResume,
      _ => l.actionPlay,
    };

    final runtime = hero.runTimeTicks;
    final tail = [
      if (!isSeries && started && runtime != null)
        l.myListMinutesLeft(
          // Per eccesso: con 30 s al termine ne restano "1".
          (ticksToDuration(runtime - data.playbackPositionTicks).inSeconds / 60)
              .ceil()
              .clamp(1, 1 << 30),
        ),
      ?code,
      if (isSeries && data.unplayedItemCount == 1) l.myListLastEpisode,
    ];

    final button = WfButton.primary(
      label: label,
      icon: LucideIcons.play,
      autofocus: autofocus,
      onPressed: () => isSeries && !(episodeState?.hasValue ?? false)
          ? openItem(context, hero)
          : unawaited(playItem(context, ref, hero)),
    );
    final phrase = _Phrase(
      lead: resuming ? l.myListWhereYouLeft : l.myListUpNext,
      name: hero.name,
      tail: tail.isEmpty ? '' : ', ${tail.join(', ')}',
      onTap: () => openItem(context, hero),
    );
    // Sulla TV (960 px, compatta) ci stanno in una riga.
    return form.compact && !form.tv
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [button, const SizedBox(height: 10), phrase],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              button,
              const SizedBox(width: 16),
              Flexible(child: phrase),
            ],
          );
  }
}

/// "[lead] **[name]**[tail]": il nome in grassetto si clicca.
class _Phrase extends StatefulWidget {
  const _Phrase({
    required this.lead,
    required this.name,
    required this.tail,
    required this.onTap,
  });

  final String lead, name, tail;
  final VoidCallback onTap;

  @override
  State<_Phrase> createState() => _PhraseState();
}

class _PhraseState extends State<_Phrase> {
  late final _tap = TapGestureRecognizer()..onTap = () => widget.onTap();

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '${widget.lead} '),
        TextSpan(
          text: widget.name,
          recognizer: _tap,
          mouseCursor: SystemMouseCursors.click,
          style: const TextStyle(
            color: WfColors.cream,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(text: widget.tail),
      ],
    ),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: WfColors.creamMuted, fontSize: 14),
  );
}

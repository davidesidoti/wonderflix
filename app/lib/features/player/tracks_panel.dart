import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/media_labels.dart';
import '../../core/jellyfin/playback_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/staggered_entrance.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'playback_rate.dart';
import 'player_commands.dart';
import 'player_keys.dart';
import 'player_settings.dart';
import 'player_side_panel_host.dart';

/// Nome di una traccia nei menu: quello preparato dal server, se c'è.
String trackLabel(AppLocalizations l, MediaStreamInfo stream) =>
    stream.displayTitle ??
    stream.title ??
    stream.language ??
    l.playerTrack(stream.index);

/// Riga sotto il nome della traccia: "AC-3 5.1 · predefinita",
/// "SRT · esterno".
String trackDetail(AppLocalizations l, MediaStreamInfo stream) {
  final format = [
    codecLabel(stream.codec),
    stream.channelLayout ?? channelsLabel(stream.channels) ?? '',
  ].where((part) => part.isNotEmpty).join(' ');
  final title = stream.title;
  return [
    if (format.isNotEmpty) format,
    if (title != null && title.isNotEmpty) title,
    if (stream.isDefault) l.playerTrackDefault,
    if (stream.isForced) l.playerTrackForced,
    if (stream.kind == StreamKind.subtitle)
      stream.isExternal ? l.playerTrackExternal : l.playerTrackEmbedded,
  ].join(' · ');
}

/// "+0,3 s", "0,0 s", "-1,2 s".
String formatSubtitleDelay(Duration delay, String decimalSeparator) {
  final tenths = (delay.inMilliseconds / 100).round();
  final sign = tenths > 0 ? '+' : (tenths < 0 ? '-' : '');
  final value = tenths.abs();
  return '$sign${value ~/ 10}$decimalSeparator${value % 10} s';
}

/// Pannello "Audio e sottotitoli" (spec §4.3): in testa il titolo su cui
/// agisce, poi tracce audio, sottotitoli, ritardo, dimensione e velocità; le
/// voci entrano scaglionate.
class TracksPanel extends ConsumerWidget {
  const TracksPanel({
    super.key,
    required this.audio,
    required this.subtitles,
    required this.audioIndex,
    required this.subtitleIndex,
    required this.subtitleDelay,
    required this.subtitleScale,
    required this.onAudio,
    required this.onSubtitle,
    required this.onDelayStep,
    required this.onSubtitleScale,
    required this.onClose,
    this.onSearchSubtitles,
    this.item,
    this.rate = 1,
    this.onRate,
  });

  final List<MediaStreamInfo> audio;
  final List<MediaStreamInfo> subtitles;
  final int? audioIndex;
  final int? subtitleIndex;
  final Duration subtitleDelay;

  /// Uno di `subtitleScaleOptions`.
  final double subtitleScale;
  final ValueChanged<int> onAudio;

  /// `null` = nessun sottotitolo.
  final ValueChanged<int?> onSubtitle;
  final ValueChanged<Duration> onDelayStep;
  final ValueChanged<double> onSubtitleScale;
  final VoidCallback onClose;

  /// "Cerca sottotitoli" sotto le tracce; `null` = niente bottone (chi non
  /// gestisce i sottotitoli).
  final VoidCallback? onSearchSubtitles;

  /// Il titolo in riproduzione, nella testa.
  final JellyfinItem? item;

  /// Velocità in corso.
  final double rate;

  /// `null` = Guarda insieme: la velocità resta 1× (il gruppo la usa per
  /// recuperare gli scarti).
  final ValueChanged<double>? onRate;

  /// Larghezza del pannello, e la parte della finestra che può occupare al
  /// massimo.
  static const width = PlayerSidePanelHost.defaultWidth;
  static const maxWidthFraction = PlayerSidePanelHost.defaultMaxWidthFraction;

  /// Distanza tra l'entrata di una voce e la successiva.
  static const itemStagger = Duration(milliseconds: 40);

  /// Quante voci entrano scaglionate, al massimo: con molte tracce le altre
  /// compaiono subito, così l'entrata dura al più circa 0,75 s (11 distanze
  /// più la durata di una voce) invece di allungarsi con la lista.
  static const staggeredItems = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final tv = form.tv;
    final compact = form.compact && !tv;
    final party = onRate == null;
    final shownRate = party ? 1.0 : rate;
    String name(MediaStreamInfo stream) =>
        trackLanguageName(stream.language, l.localeName) ??
        trackLabel(l, stream);
    final item = this.item;
    final head = Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WfColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.playerAudioAndSubtitles,
                  style: WfText.display(30),
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x),
                tooltip: l.playerClosePanel,
                color: WfColors.cream,
                constraints: compact
                    ? const BoxConstraints.tightFor(width: 44, height: 44)
                    : null,
                onPressed: onClose,
              ),
            ],
          ),
          if (item != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      width: 64,
                      height: 36,
                      child: WfImage(
                        image: ref.watch(imageUrlsProvider).landscape(item),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cardTitle(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (cardSubtitle(item) case final subtitle?)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: WfColors.creamMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    final items = <Widget>[
      // Le distanze stanno dentro le voci (non ci sono distanziatori): ogni
      // voce dello scaglionamento è una cosa vera, e il tetto conta bene.
      _SectionTitle(l.playerAudio),
      for (final stream in audio)
        _TrackTile(
          label: name(stream),
          detail: trackDetail(l, stream),
          selected: stream.index == audioIndex,
          onTap: () => onAudio(stream.index),
        ),
      _SectionTitle(l.playerSubtitles, top: 16),
      _TrackTile(
        label: l.playerSubtitlesOff,
        selected: subtitleIndex == null,
        onTap: () => onSubtitle(null),
      ),
      for (final stream in subtitles)
        _TrackTile(
          label: name(stream),
          detail: trackDetail(l, stream),
          selected: stream.index == subtitleIndex,
          onTap: () => onSubtitle(stream.index),
        ),
      if (onSearchSubtitles case final onSearch?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: WfButton.secondary(
              label: l.playerSearchSubtitles,
              icon: LucideIcons.search,
              onPressed: onSearch,
            ),
          ),
        ),
      // Sulla TV il ritardo non funziona (piano 1).
      if (!tv) ...[
        _SectionTitle(
          l.playerSubtitleDelay,
          top: 16,
          trailing: form.touch
              ? null
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [KeyCap('G'), SizedBox(width: 4), KeyCap('H')],
                ),
        ),
        _DelayRow(delay: subtitleDelay, onDelayStep: onDelayStep),
      ],
      _SectionTitle(
        l.playerSubtitleSizeValue(subtitleScaleLabel(l, subtitleScale)),
        top: 16,
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final scale in subtitleScaleOptions)
            Semantics(
              container: true,
              button: true,
              selected: scale == subtitleScale,
              label: subtitleScaleLabel(l, scale),
              excludeSemantics: true,
              child: _Chip(
                key: ValueKey('subtitle-scale-$scale'),
                width: 46,
                selected: scale == subtitleScale,
                onTap: () => onSubtitleScale(scale),
                label: 'Aa',
                fontSize: math.max(10, 20 * scale),
              ),
            ),
        ],
      ),
      _SectionTitle(l.playerSpeed, top: 16),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in playbackRates)
                _Chip(
                  key: ValueKey('playback-rate-$value'),
                  selected: value == shownRate,
                  onTap: party ? null : () => onRate!(value),
                  label: formatRate(value, l.decimalSeparator),
                ),
            ],
          ),
          if (party)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                l.playerSpeedPartyNote,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: WfColors.creamMuted,
                ),
              ),
            ),
        ],
      ),
    ];
    final content = Material(
      color: WfColors.surface.withValues(alpha: 0.94),
      child: DecoratedBox(
        // Nello stretto il bordo lo mette l'host, che lo apre come foglio.
        decoration: BoxDecoration(
          border: compact
              ? null
              : const Border(left: BorderSide(color: WfColors.border)),
        ),
        child: Column(
          children: [
            head,
            Expanded(
              child: StaggerGroup(
                count: math.min(items.length, staggeredItems),
                stagger: itemStagger,
                itemDuration: WfMotion.medium,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  children: [
                    for (var i = 0; i < items.length; i++)
                      StaggerItem(index: i, child: items[i]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return PanelWheelBarrier(child: content);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.top = 0, this.trailing});

  final String title;

  /// Spazio sopra il titolo, per staccarlo da ciò che lo precede.
  final double top;

  /// A destra del titolo (i tasti).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: WfColors.creamMuted,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.label,
    this.detail = '',
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  // Sulla TV il focus è del TvFocusable, non dell'InkWell; quello della
  // traccia scelta lo prende all'apertura (vale il primo, l'audio). La riga è
  // larga quanto il pannello: col focus cresce poco, sennò ne esce.
  @override
  Widget build(BuildContext context) {
    final form = FormFactor.of(context);
    final minHeight = form.tv ? 52.0 : (form.compact ? 48.0 : 44.0);
    return TvFocusable(
      autofocus: selected,
      onActivate: onTap,
      focusScale: 1.03,
      child: Material(
        color: selected
            ? WfColors.gold.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          canRequestFocus: !form.tv,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: form.tv ? 14 : null,
                            color: selected ? WfColors.gold : WfColors.cream,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        if (detail.isNotEmpty)
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: WfColors.creamMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selected)
                    const _PopIn(
                      child: Icon(
                        LucideIcons.check,
                        size: 16,
                        color: WfColors.gold,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La spunta compare con un piccolo rimbalzo (con le animazioni ridotte
/// solo sfumando).
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = WfMotion.of(context).isReduced;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: WfMotion.fast,
      curve: reduced ? WfMotion.standard : WfMotion.bounce,
      builder: (context, t, child) => reduced
          ? Opacity(opacity: t.clamp(0.0, 1.0), child: child)
          : Transform.scale(scale: t, child: child),
      child: child,
    );
  }
}

class _DelayRow extends StatelessWidget {
  const _DelayRow({required this.delay, required this.onDelayStep});

  final Duration delay;
  final ValueChanged<Duration> onDelayStep;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StepButton(
              icon: LucideIcons.minus,
              tooltip: l.playerSubtitlesEarlier,
              onPressed: () => onDelayStep(-subtitleDelayStep),
            ),
            SizedBox(
              width: 70,
              child: Text(
                formatSubtitleDelay(delay, l.decimalSeparator),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _StepButton(
              icon: LucideIcons.plus,
              tooltip: l.playerSubtitlesLater,
              onPressed: () => onDelayStep(subtitleDelayStep),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            l.playerSubtitleDelayHint,
            style: const TextStyle(fontSize: 11.5, color: WfColors.creamMuted),
          ),
        ),
      ],
    );
  }
}

/// − e + del ritardo: pulsanti del kit, 44×38.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: WfButtonFeedback(
      enabled: true,
      child: Material(
        color: WfColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: WfColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 44,
            height: 38,
            child: Icon(icon, size: 18, color: WfColors.cream),
          ),
        ),
      ),
    ),
  );
}

/// Una pastiglia (dimensione o velocità): bordo e testo oro se scelta;
/// senza [onTap] è spenta.
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.width,
    this.fontSize,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final double? width;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final chip = Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: TvFocusable(
        onActivate: onTap,
        child: InkWell(
          onTap: onTap,
          canRequestFocus: !FormFactor.of(context).tv,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: WfMotion.fast,
            width: width,
            height: 40,
            padding: EdgeInsets.symmetric(horizontal: width == null ? 12 : 0),
            decoration: BoxDecoration(
              color: selected ? WfColors.gold.withValues(alpha: 0.1) : null,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? WfColors.gold : WfColors.border,
              ),
            ),
            // Larga quanto il testo (con `alignment` riempirebbe la fila).
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  color: selected ? WfColors.gold : WfColors.creamMuted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Spenta (in un party): le altre scelte si vedono appena.
    return onTap == null && !selected
        ? Opacity(opacity: 0.4, child: chip)
        : chip;
  }
}

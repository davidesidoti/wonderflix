import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/media_info_models.dart';
import '../../core/jellyfin/media_labels.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/dialog_item_poster.dart';
import '../../ui/form_factor.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_dialog_parts.dart';
import '../admin/admin_providers.dart';
import '../library/item_labels.dart';
import '../reports/reports_providers.dart';

/// "Info tecniche" di un film o di un episodio (spec R §7.4).
Future<void> showMediaInfoDialog(BuildContext context, JellyfinItem item) {
  final l = AppLocalizations.of(context);
  final tv = FormFactor.of(context).tv;
  final body = GlobalKey();
  return showWfDialog<void>(
    context,
    maxWidth: 640,
    fullPageWhenCompact: !tv,
    semanticLabel: l.mediaInfoTitle,
    compactTitle: l.mediaInfoTitle,
    builder: (_) => KeyedSubtree(
      key: body,
      child: _MediaInfoContent(item: item),
    ),
    footer: (_) => _MediaInfoFooter(body: body, tv: tv),
  );
}

/// Di quanto Su e Giù scorrono il corpo in TV.
const _tvScrollStep = 80.0;

/// Da qui la dimensione si mostra in GB, sotto in MB.
const _bytesPerGb = 1000000000;
const _bytesPerMb = 1000000;
const _bitsPerMbps = 1000000;

/// Solo "Chiudi". In TV ha il focus e Su/Giù scorrono il corpo finché c'è
/// da scorrere; poi i tasti vanno alla navigazione (pastiglie, Riprova).
class _MediaInfoFooter extends StatelessWidget {
  const _MediaInfoFooter({required this.body, required this.tv});

  final GlobalKey body;
  final bool tv;

  /// Scorre il corpo di [delta] se c'è ancora strada; `false` se è già in
  /// fondo (o in cima): il tasto passa alla navigazione normale.
  bool _scroll(double delta) {
    final context = body.currentContext;
    final position = context == null
        ? null
        : Scrollable.maybeOf(context)?.position;
    if (position == null) return false;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return false;
    unawaited(
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final footer = WfDialogFooter(
      primary: WfButton.secondary(
        label: MaterialLocalizations.of(context).closeButtonLabel,
        icon: LucideIcons.x,
        autofocus: tv,
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
    if (!tv) return footer;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        final delta = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowDown => _tvScrollStep,
          LogicalKeyboardKey.arrowUp => -_tvScrollStep,
          _ => null,
        };
        return delta != null && _scroll(delta)
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      },
      child: footer,
    );
  }
}

class _MediaInfoContent extends ConsumerStatefulWidget {
  const _MediaInfoContent({required this.item});

  final JellyfinItem item;

  @override
  ConsumerState<_MediaInfoContent> createState() => _MediaInfoContentState();
}

class _MediaInfoContentState extends ConsumerState<_MediaInfoContent> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = widget.item;
    final info = ref.watch(itemMediaInfoProvider(item.id));
    final versions = info.value?.versions ?? const <MediaVersion>[];
    final selected = math.min(_selected, math.max(0, versions.length - 1));
    final Widget content;
    if (info.isLoading) {
      content = const Center(child: LoadingView());
    } else if (info.hasError) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.mediaInfoError,
            style: const TextStyle(color: WfColors.creamMuted),
          ),
          const SizedBox(height: 12),
          WfButton.secondary(
            label: l.retry,
            icon: LucideIcons.refreshCw,
            onPressed: () => ref.invalidate(itemMediaInfoProvider(item.id)),
          ),
        ],
      );
    } else if (versions.isEmpty) {
      content = Text(
        l.mediaInfoUnavailable,
        style: const TextStyle(color: WfColors.creamMuted),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (versions.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, version) in versions.indexed)
                  ChoiceChip(
                    label: Text(version.name ?? version.id),
                    selected: i == selected,
                    onSelected: (_) => setState(() => _selected = i),
                  ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          _VersionBody(version: versions[selected]),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WfDialogHeader(
          title: l.mediaInfoTitle,
          subtitle: itemContextLine(l, item),
          leading: DialogItemPoster(itemId: item.id),
        ),
        const SizedBox(height: 16),
        content,
      ],
    );
  }
}

/// I quattro gruppi di una versione; quelli senza niente si saltano.
class _VersionBody extends ConsumerWidget {
  const _VersionBody({required this.version});

  final MediaVersion version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = l.localeName;
    final tv = FormFactor.of(context).tv;
    // Il nome del file è per l'admin, e in TV non serve.
    final fileName = ref.watch(isAdminProvider) && !tv
        ? version.fileName
        : null;
    final decimal = NumberFormat('0.0', locale);
    final size = version.size;
    final bitrate = version.bitrate;
    final video = version.video;
    final tiles = <(String, String)>[
      if (version.container != null)
        (l.mediaInfoFormat, version.container!.toUpperCase()),
      if (size != null)
        (
          l.mediaInfoSize,
          size >= _bytesPerGb
              ? '${decimal.format(size / _bytesPerGb)} GB'
              : '${decimal.format(size / _bytesPerMb)} MB',
        ),
      if (version.duration != null)
        (l.mediaInfoDuration, formatRuntime(version.duration!)),
      if (bitrate != null)
        (l.mediaInfoBitrate, '${decimal.format(bitrate / _bitsPerMbps)} Mbps'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fileName != null || tiles.isNotEmpty)
          _Group(
            icon: LucideIcons.file,
            title: l.mediaInfoFile,
            children: [
              if (fileName != null) _FileNameRow(fileName: fileName),
              if (tiles.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, value) in tiles)
                      _Tile(label: label, value: value),
                  ],
                ),
            ],
          ),
        if (video != null)
          _Group(
            icon: LucideIcons.monitor,
            title: l.mediaInfoVideo,
            children: [_Line(_videoLine(video, locale))],
          ),
        if (version.audio.isNotEmpty)
          _Group(
            icon: LucideIcons.audioLines,
            title: l.mediaInfoAudioCount(version.audio.length),
            children: [
              for (final track in version.audio)
                _Line(
                  _join([
                    _language(track.language, locale),
                    [
                      if (track.codec != null) codecLabel(track.codec),
                      channelsLabel(track.channels),
                    ].whereType<String>().join(' '),
                  ]),
                  tags: [if (track.isDefault) l.mediaInfoDefault],
                ),
            ],
          ),
        if (version.subtitles.isNotEmpty)
          _Group(
            icon: LucideIcons.captions,
            title: l.mediaInfoSubtitlesCount(version.subtitles.length),
            children: [
              for (final track in version.subtitles)
                _Line(
                  _join([
                    _language(track.language, locale),
                    if (track.codec != null) codecLabel(track.codec),
                  ]),
                  tags: [
                    track.isExternal
                        ? l.mediaInfoExternal
                        : l.mediaInfoEmbedded,
                    if (track.isForced) l.subtitlesForced,
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

String? _language(String? code, String locale) =>
    code == null ? null : languageName(code, locale);

/// Le parti piene unite da " · "; un trattino se non ce n'è nessuna.
String _join(List<String?> parts) {
  final text = parts.where((p) => p != null && p.isNotEmpty).join(' · ');
  return text.isEmpty ? '—' : text;
}

/// "HEVC · 4K (3840×2160) · HDR10 · 23,976 fps".
String _videoLine(VideoTrack video, String locale) {
  final width = video.width;
  final height = video.height;
  final dimensions = width != null && height != null ? '$width×$height' : null;
  final label = resolutionLabel(width);
  final fps = video.fps;
  return _join([
    if (video.codec != null) codecLabel(video.codec),
    label != null && dimensions != null
        ? '$label ($dimensions)'
        : label ?? dimensions,
    video.range,
    if (fps != null) '${NumberFormat('0.###', locale).format(fps)} fps',
  ]);
}

class _Group extends StatelessWidget {
  const _Group({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: WfColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: WfColors.creamMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

/// Una riga di testo con le sue targhette ("Predefinita", "File esterno").
class _Line extends StatelessWidget {
  const _Line(this.text, {this.tags = const []});

  final String text;
  final List<String> tags;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(text),
        for (final tag in tags)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: WfColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                tag,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: WfColors.creamMuted,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: WfColors.surfaceHigh,
      border: Border.all(color: WfColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: WfColors.creamMuted),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

/// Il nome del file con "Copia".
class _FileNameRow extends StatefulWidget {
  const _FileNameRow({required this.fileName});

  final String fileName;

  @override
  State<_FileNameRow> createState() => _FileNameRowState();
}

class _FileNameRowState extends State<_FileNameRow> {
  Timer? _reset;
  bool _copied = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.fileName)));
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(widget.fileName)),
          const SizedBox(width: 12),
          // Il riscontro sta nel pulsante: uno snackbar finirebbe sotto il velo.
          WfButton.secondary(
            label: _copied ? l.mediaInfoCopied : l.mediaInfoCopy,
            icon: _copied ? LucideIcons.check : LucideIcons.copy,
            small: true,
            onPressed: _copy,
          ),
        ],
      ),
    );
  }
}

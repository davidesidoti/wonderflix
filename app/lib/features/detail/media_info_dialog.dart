import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/media_info_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/wf_dialog.dart';
import '../admin/admin_providers.dart';
import '../library/item_labels.dart';
import '../reports/reports_providers.dart';

/// "Info tecniche" di un film o di un episodio (spec R §7.4).
Future<void> showMediaInfoDialog(BuildContext context, JellyfinItem item) =>
    showWfDialog<void>(
      context,
      maxWidth: 560,
      semanticLabel: AppLocalizations.of(context).mediaInfoTitle,
      builder: (_) => _MediaInfoContent(item: item),
    );

/// Larghezza della colonna delle etichette.
const _labelWidth = 120.0;

/// Da qui la dimensione si mostra in GB, sotto in MB.
const _bytesPerGb = 1000000000;
const _bytesPerMb = 1000000;
const _bitsPerMbps = 1000000;

class _MediaInfoContent extends ConsumerWidget {
  const _MediaInfoContent({required this.item});

  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final info = ref.watch(itemMediaInfoProvider(item.id));
    final isAdmin = ref.watch(isAdminProvider);
    final versions = info.value?.versions ?? const <MediaVersion>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.mediaInfoTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(item.name, style: const TextStyle(color: WfColors.creamMuted)),
        const SizedBox(height: 16),
        Flexible(
          child: info.isLoading
              ? const Center(child: LoadingView())
              : versions.isEmpty
                  ? Text(l.mediaInfoUnavailable,
                      style: const TextStyle(color: WfColors.creamMuted))
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, version) in versions.indexed) ...[
                            if (i > 0) const SizedBox(height: 20),
                            _VersionSection(
                              version: version,
                              titled: versions.length > 1,
                              showFile: isAdmin,
                            ),
                          ],
                        ],
                      ),
                    ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
        ),
      ],
    );
  }
}

class _VersionSection extends StatelessWidget {
  const _VersionSection(
      {required this.version, required this.titled, required this.showFile});

  final MediaVersion version;
  final bool titled;
  final bool showFile;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final decimal = NumberFormat('0.0', locale);
    final size = version.size;
    final bitrate = version.bitrate;
    final video = version.video;
    final fps = NumberFormat('0.##', locale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (titled)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l.mediaInfoVersion(version.name ?? version.id),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        if (version.container != null)
          _Row(l.mediaInfoContainer, version.container!),
        if (size != null)
          _Row(
              l.mediaInfoSize,
              size >= _bytesPerGb
                  ? '${decimal.format(size / _bytesPerGb)} GB'
                  : '${decimal.format(size / _bytesPerMb)} MB'),
        if (version.duration != null)
          _Row(l.mediaInfoDuration, formatRuntime(version.duration!)),
        if (bitrate != null)
          _Row(l.mediaInfoBitrate,
              '${decimal.format(bitrate / _bitsPerMbps)} Mbps'),
        if (showFile && version.fileName != null)
          _Row(l.mediaInfoFile, version.fileName!),
        if (video != null)
          _Row(
              l.mediaInfoVideo,
              [
                video.codec,
                if (video.width != null && video.height != null)
                  '${video.width}×${video.height}',
                video.range,
                if (video.fps != null) '${fps.format(video.fps)} fps',
              ].whereType<String>().join(' · ')),
        for (final track in version.audio)
          _Row(
              l.mediaInfoAudio,
              [
                track.language,
                track.codec,
                if (track.channels != null)
                  l.mediaInfoChannels(track.channels!),
                if (track.isDefault) l.mediaInfoDefault,
              ].whereType<String>().join(' · ')),
        for (final track in version.subtitles)
          _Row(
              l.mediaInfoSubtitles,
              [
                track.language,
                track.codec,
                track.isExternal ? l.subtitlesExternal : l.subtitlesEmbedded,
                if (track.isForced) l.subtitlesForced,
              ].whereType<String>().join(' · ')),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _labelWidth,
              child: Text(label,
                  style: const TextStyle(color: WfColors.creamMuted)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

import 'package:intl/intl.dart';

import '../../core/jellyfin/admin_models.dart';
import '../../l10n/gen/app_localizations.dart';

/// Bit in un megabit.
const _bitsPerMegabit = 1000000;

/// Come si vede una riproduzione nella scheda Sessioni (spec J §9.3).
enum DisplayMethod { direct, remux, transcode, unknown }

/// `DirectPlay` è sempre diretta. Con `TranscodingInfo` decide lui: video e
/// audio diretti sono un remux (anche se il client dichiara `Transcode`),
/// altrimenti è una transcodifica. Senza, decide il metodo dichiarato.
DisplayMethod displayMethod(SessionEntry session) {
  if (session.playMethod == PlayMethod.directPlay) return DisplayMethod.direct;
  final transcode = session.transcode;
  if (transcode != null) {
    return transcode.isVideoDirect && transcode.isAudioDirect
        ? DisplayMethod.remux
        : DisplayMethod.transcode;
  }
  return switch (session.playMethod) {
    PlayMethod.directStream => DisplayMethod.remux,
    PlayMethod.transcode => DisplayMethod.transcode,
    _ => DisplayMethod.unknown,
  };
}

String? displayMethodLabel(AppLocalizations l, DisplayMethod method) =>
    switch (method) {
      DisplayMethod.direct => l.adminMethodDirect,
      DisplayMethod.remux => l.adminMethodRemux,
      DisplayMethod.transcode => l.adminMethodTranscode,
      DisplayMethod.unknown => null,
    };

/// "Dune (2021)", "Lost · S1:E3 · Pilota", oppure il nome.
String nowPlayingTitle(AppLocalizations l, NowPlaying item) {
  switch (item.kind) {
    case NowPlayingKind.movie:
      final year = item.year;
      return year == null ? item.name : l.adminMovieYear(item.name, '$year');
    case NowPlayingKind.episode:
      final series = item.seriesName;
      if (series == null) return item.name;
      final episode = item.episodeNumber;
      if (episode == null) return l.adminEpisodeNoCode(series, item.name);
      final season = item.seasonNumber;
      final code = season == null ? 'E$episode' : 'S$season:E$episode';
      return l.adminEpisodeTitle(series, code, item.name);
    case NowPlayingKind.other:
      return item.name;
  }
}

/// "Jellyfin Android TV · FireTV Soggiorno" (solo le parti note).
String sessionDevice(SessionEntry session) =>
    [session.client, session.deviceName].whereType<String>().join(' · ');

/// "→ H264 1080p · AAC · 8,2 Mbps · Software": cosa si transcodifica, il
/// bitrate e, se si transcodifica il video, l'accelerazione. `null` se non
/// c'è niente da dire.
String? transcodeLine(AppLocalizations l, TranscodeInfo info) {
  final parts = <String>[];
  final video = info.videoCodec;
  if (!info.isVideoDirect && video != null) {
    final height = info.height;
    parts.add(height == null
        ? video.toUpperCase()
        : '${video.toUpperCase()} ${height}p');
  }
  final audio = info.audioCodec;
  if (!info.isAudioDirect && audio != null) parts.add(audio.toUpperCase());
  final bitrate = info.bitrate;
  if (bitrate != null && bitrate > 0) {
    parts.add(l.adminBitrate(
        NumberFormat('0.0', l.localeName).format(bitrate / _bitsPerMegabit)));
  }
  if (!info.isVideoDirect) {
    parts.add(hardwareLabel(l, info.hardwareAcceleration));
  }
  return parts.isEmpty ? null : '→ ${parts.join(' · ')}';
}

/// Nome dell'accelerazione hardware; senza, "Software".
String hardwareLabel(AppLocalizations l, String? type) =>
    switch (type?.toLowerCase()) {
      null || 'none' => l.adminSoftware,
      'qsv' => 'Intel QSV',
      'nvenc' => 'NVIDIA NVENC',
      'amf' => 'AMD AMF',
      'vaapi' => 'VA-API',
      'videotoolbox' => 'VideoToolbox',
      'v4l2m2m' => 'V4L2',
      'rkmpp' => 'Rockchip MPP',
      _ => type!,
    };

/// I motivi della transcodifica tradotti, senza doppioni; uno sconosciuto
/// resta come lo scrive Jellyfin.
String transcodeReasons(AppLocalizations l, List<String> reasons) =>
    {for (final reason in reasons) _reasonLabel(l, reason)}.join(', ');

String _reasonLabel(AppLocalizations l, String reason) => switch (reason) {
      'ContainerNotSupported' => l.adminReasonContainer,
      'VideoCodecNotSupported' ||
      'VideoCodecTagNotSupported' =>
        l.adminReasonVideoCodec,
      'AudioCodecNotSupported' ||
      'AudioProfileNotSupported' =>
        l.adminReasonAudioCodec,
      'SubtitleCodecNotSupported' => l.adminReasonSubtitles,
      'VideoProfileNotSupported' => l.adminReasonVideoProfile,
      'VideoLevelNotSupported' => l.adminReasonVideoLevel,
      'VideoResolutionNotSupported' => l.adminReasonResolution,
      'VideoBitDepthNotSupported' => l.adminReasonBitDepth,
      'VideoRangeTypeNotSupported' => l.adminReasonVideoRange,
      'AudioChannelsNotSupported' => l.adminReasonAudioChannels,
      'ContainerBitrateExceedsLimit' ||
      'VideoBitrateNotSupported' ||
      'AudioBitrateNotSupported' =>
        l.adminReasonBitrate,
      'AudioIsExternal' => l.adminReasonExternalAudio,
      'VideoFramerateNotSupported' => l.adminReasonFramerate,
      'AudioSampleRateNotSupported' => l.adminReasonSampleRate,
      'AudioBitDepthNotSupported' => l.adminReasonAudioBitDepth,
      'SecondaryAudioNotSupported' => l.adminReasonSecondaryAudio,
      'InterlacedVideoNotSupported' => l.adminReasonInterlaced,
      'RefFramesNotSupported' => l.adminReasonRefFrames,
      'AnamorphicVideoNotSupported' => l.adminReasonAnamorphic,
      'StreamCountExceedsLimit' => l.adminReasonStreamCount,
      'DirectPlayError' => l.adminReasonDirectPlayError,
      'UnknownVideoStreamInfo' ||
      'UnknownAudioStreamInfo' =>
        l.adminReasonUnknownStream,
      _ => reason,
    };

/// Lo stato di un watch party; `null` se Jellyfin ne dice uno sconosciuto.
String? partyStateLabel(AppLocalizations l, PartyState state) =>
    switch (state) {
      PartyState.playing => l.adminPartyPlaying,
      PartyState.paused => l.adminPartyPaused,
      PartyState.waiting => l.adminPartyWaiting,
      PartyState.idle => l.adminPartyIdle,
      PartyState.unknown => null,
    };

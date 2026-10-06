/// Risposte di Jellyfin 10.11.9 per la pagina Amministrazione. `System/Info`
/// è quella vera del server (2026-10-06) senza percorsi né id; le sessioni e
/// i party seguono lo schema OpenAPI 10.11.9 (`SessionInfoDto`,
/// `GroupInfoDto`).
final serverInfoJson = <String, dynamic>{
  'OperatingSystemDisplayName': '',
  'HasPendingRestart': false,
  'IsShuttingDown': false,
  'SupportsLibraryMonitor': true,
  'WebSocketPortNumber': 8096,
  'CompletedInstallations': <Object>[],
  'CanSelfRestart': true,
  'CanLaunchWebBrowser': false,
  'HasUpdateAvailable': false,
  'SystemArchitecture': 'X64',
  'ServerName': 'WonderFlix',
  'Version': '10.11.9',
  'ProductName': 'Jellyfin Server',
  'OperatingSystem': '',
  'StartupWizardCompleted': true,
};

/// Quattro sessioni:
/// - s1: viviroby su FireTV, un episodio transcodificato (video e audio);
/// - s2: lucia, un film in pausa, dichiarato `Transcode` ma con video e audio
///   diretti (un remux);
/// - s3: davide.sidoti su WonderFlix, collegato senza riprodurre;
/// - s4: la chiave API di Seerr, senza utente (da scartare).
final sessionsJson = <Map<String, dynamic>>[
  {
    'PlayState': {
      'PositionTicks': 7540000000,
      'CanSeek': true,
      'IsPaused': false,
      'IsMuted': false,
      'VolumeLevel': 100,
      'PlayMethod': 'Transcode',
      'RepeatMode': 'RepeatNone',
    },
    'Id': 's1',
    'UserId': '6a48860fd4d94124b1890173d68c9de3',
    'UserName': 'viviroby',
    'Client': 'Jellyfin Android TV',
    'DeviceName': 'FireTV Soggiorno',
    'DeviceId': 'd1',
    'ApplicationVersion': '0.19.10',
    'LastActivityDate': '2026-10-06T07:53:20.8580665Z',
    'NowPlayingItem': {
      'Name': 'Pilota',
      'Id': 'e1',
      'Type': 'Episode',
      'SeriesName': 'Lost',
      'SeriesId': 'ser1',
      'ParentIndexNumber': 1,
      'IndexNumber': 3,
      'ProductionYear': 2004,
      'RunTimeTicks': 25560000000,
    },
    'TranscodingInfo': {
      'AudioCodec': 'aac',
      'VideoCodec': 'h264',
      'Container': 'ts',
      'IsVideoDirect': false,
      'IsAudioDirect': false,
      'Bitrate': 8200000,
      'Width': 1920,
      'Height': 1080,
      'AudioChannels': 2,
      'HardwareAccelerationType': 'none',
      'TranscodeReasons': ['VideoCodecNotSupported', 'AudioCodecNotSupported'],
    },
    'IsActive': true,
    'SupportsMediaControl': true,
    'SupportsRemoteControl': true,
  },
  {
    'PlayState': {
      'PositionTicks': 36000000000,
      'CanSeek': true,
      'IsPaused': true,
      'PlayMethod': 'Transcode',
    },
    'Id': 's2',
    'UserId': 'b1c2d3e4f5a64b7c8d9e0f1a2b3c4d5e',
    'UserName': 'lucia',
    'Client': 'Jellyfin Web',
    'DeviceName': 'Chrome',
    'LastActivityDate': '2026-10-06T08:05:00.0000000Z',
    'NowPlayingItem': {
      'Name': 'Dune',
      'Id': 'm1',
      'Type': 'Movie',
      'ProductionYear': 2021,
      'RunTimeTicks': 93720000000,
    },
    'TranscodingInfo': {
      'AudioCodec': 'eac3',
      'VideoCodec': 'hevc',
      'Container': 'mp4',
      'IsVideoDirect': true,
      'IsAudioDirect': true,
      'Bitrate': 21000000,
      'HardwareAccelerationType': 'none',
      'TranscodeReasons': ['ContainerNotSupported'],
    },
    'IsActive': true,
  },
  {
    'PlayState': {'CanSeek': false, 'IsPaused': false, 'IsMuted': false},
    'Id': 's3',
    'UserId': 'ab8240c5fc1649e186f662fa00ca0fb0',
    'UserName': 'davide.sidoti',
    'Client': 'WonderFlix',
    'DeviceName': 'nocturne',
    'LastActivityDate': '2026-10-06T08:10:00.0000000Z',
    'IsActive': true,
  },
  {
    'PlayState': {'CanSeek': false, 'IsPaused': false},
    'Id': 's4',
    'UserId': '00000000000000000000000000000000',
    'Client': 'Seerr',
    'DeviceName': 'Seerr',
    'LastActivityDate': '2026-10-06T08:09:00.0000000Z',
    'IsActive': true,
  },
];

/// Un watch party in corso.
final partyGroupsJson = <Map<String, dynamic>>[
  {
    'GroupId': 'g1',
    'GroupName': 'Serata Lost',
    'State': 'Playing',
    'Participants': ['viviroby', 'Mario'],
    'LastUpdatedAt': '2026-10-06T08:00:00.0000000Z',
  },
];

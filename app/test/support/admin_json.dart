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

/// Le librerie vere del server (2026-10-06, senza i percorsi), con Movies in
/// scansione.
final librariesJson = <Map<String, dynamic>>[
  {
    'Name': 'Movies',
    'Locations': ['/media/movies'],
    'CollectionType': 'movies',
    'ItemId': 'f137a2dd21bbc1b99aa5c0f6bf02a805',
    'PrimaryImageItemId': 'f137a2dd21bbc1b99aa5c0f6bf02a805',
    'RefreshProgress': 42.5,
    'RefreshStatus': 'Active',
  },
  {
    'Name': 'Collezioni2',
    'CollectionType': 'boxsets',
    'ItemId': '14c252b1242828441caab72deed35f64',
    'RefreshStatus': 'Idle',
  },
  {
    'Name': 'Anime',
    'ItemId': '0c41907140d802bb58430fed7e2cd79e',
    'RefreshStatus': 'Idle',
  },
  {
    'Name': 'Shows',
    'CollectionType': 'tvshows',
    'ItemId': 'a656b907eb3a73532e40e44b968d0225',
    'RefreshStatus': 'Idle',
  },
];

/// Attività vere del server (nomi, chiavi e categorie del 2026-10-06), in
/// ordine di nome come le dà Jellyfin. Gli stati sono vari per i test: Auto
/// Collections in corso, il webhook in arresto, Trakt non riuscita, il
/// Keyframe annullato, SkipMe mai eseguita.
final tasksJson = <Map<String, dynamic>>[
  {
    'Name': 'Aggiorna i plugin',
    'State': 'Idle',
    'Id': 't-plugins',
    'Key': 'PluginUpdates',
    'Category': 'Applicazione',
    'Description': 'Scarica e installa gli aggiornamenti dei plugin.',
    'IsHidden': false,
    'Triggers': <Object>[],
    'LastExecutionResult': {
      'StartTimeUtc': '2026-10-05T22:23:40.0000000Z',
      'EndTimeUtc': '2026-10-05T22:23:46.5083784Z',
      'Status': 'Completed',
      'Name': 'Aggiorna i plugin',
      'Key': 'PluginUpdates',
      'Id': 't-plugins',
    },
  },
  {
    'Name': 'Auto Collections',
    'State': 'Running',
    'CurrentProgressPercentage': 37.5,
    'Id': 't-autocol',
    'Key': 'AutoCollections',
    'Category': 'Auto Collections',
    'Description': 'Aggiorna le collezioni automatiche.',
  },
  {
    'Name': 'Estrattore di Keyframe',
    'State': 'Idle',
    'Id': 't-keyframe',
    'Key': 'KeyframeExtraction',
    'Category': 'Libreria',
    'LastExecutionResult': {
      'StartTimeUtc': '2026-09-13T12:10:00.0000000Z',
      'EndTimeUtc': '2026-09-13T12:18:18.6587334Z',
      'Status': 'Cancelled',
    },
  },
  {
    'Name': 'Export library to trakt.tv',
    'State': 'Idle',
    'Id': 't-trakt',
    'Key': 'TraktSyncLibraryTask',
    'Category': 'Trakt',
    'LastExecutionResult': {
      'StartTimeUtc': '2026-05-28T15:40:00.0000000Z',
      'EndTimeUtc': '2026-05-28T15:49:54.8292125Z',
      'Status': 'Failed',
      'ErrorMessage':
          'Response status code does not indicate success: 401 (Unauthorized).',
    },
  },
  {
    'Name': 'Ottimizza database',
    'State': 'Idle',
    'Id': 't-optimize',
    'Key': 'OptimizeDatabaseTask',
    'Category': 'Manutenzione',
    'LastExecutionResult': {
      'StartTimeUtc': '2026-10-06T04:21:48.0000000Z',
      'EndTimeUtc': '2026-10-06T04:24:48.5097924Z',
      'Status': 'Completed',
    },
  },
  {
    'Name': 'Scansione della libreria',
    'State': 'Idle',
    'Id': 't-scan',
    'Key': 'RefreshLibrary',
    'Category': 'Libreria',
    'Description': 'Analizza la cartella dei media per trovare file nuovi.',
    'LastExecutionResult': {
      'StartTimeUtc': '2026-10-05T03:40:00.0000000Z',
      'EndTimeUtc': '2026-10-05T03:47:36.9500309Z',
      'Status': 'Completed',
    },
  },
  {
    'Name': 'Sync SkipMe.db Segment Database',
    'State': 'Idle',
    'Id': 't-skipme',
    'Key': 'SkipMeDbSync',
    'Category': 'Intro Skipper',
  },
  {
    'Name': 'Webhook Item Added Notifier',
    'State': 'Cancelling',
    'CurrentProgressPercentage': 90.0,
    'Id': 't-webhook',
    'Key': 'WebhookItemAdded',
    'Category': 'Libreria',
  },
];

/// Una pagina del registro, con voci come quelle vere (2026-10-06): IP di
/// documentazione, nomi di prova.
final activityJson = <String, dynamic>{
  'Items': [
    {
      'Id': 12134,
      'Name': 'anna si è disconnesso da FireTV Soggiorno',
      'ShortOverview': 'Indirizzo IP: 203.0.113.7',
      'Type': 'SessionEnded',
      'Date': '2026-10-06T03:39:07.1141718Z',
      'UserId': '6a48860fd4d94124b1890173d68c9de3',
      'Severity': 'Information',
    },
    {
      'Id': 12130,
      'Name': 'anna ha riprodotto Lost - Pilota su FireTV Soggiorno',
      'Type': 'VideoPlayback',
      'ItemId': 'e1',
      'Date': '2026-10-06T03:10:00.0000000Z',
      'UserId': '6a48860fd4d94124b1890173d68c9de3',
      'Severity': 'Information',
    },
    {
      'Id': 12125,
      'Name': 'WonderFlix Watch Party è stato Installato',
      'ShortOverview': 'Versione 1.4.0.0',
      'Type': 'PluginInstalled',
      'Date': '2026-10-05T22:21:46.9886084Z',
      'UserId': '00000000000000000000000000000000',
      'Severity': 'Information',
    },
    {
      'Id': 11950,
      'Name': 'Attività Esporta su trakt.tv non riuscita',
      'Type': 'ScheduledTaskFailed',
      'Date': '2026-10-04T18:00:00.0000000Z',
      'UserId': '00000000000000000000000000000000',
      'Severity': 'Warning',
    },
    {
      'Id': 11904,
      'Name': 'Tentativo di accesso fallito da marco',
      'ShortOverview': 'Indirizzo IP: 203.0.113.9',
      'Overview': 'Nome utente o password non validi.',
      'Type': 'AuthenticationFailed',
      'Date': '2026-10-04T14:06:19.8344887Z',
      'UserId': '00000000000000000000000000000000',
      'Severity': 'Error',
    },
  ],
  'TotalRecordCount': 12134,
  'StartIndex': 0,
};

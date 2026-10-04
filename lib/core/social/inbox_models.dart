import 'dart:collection';
import 'dart:math' as math;

import 'package:logging/logging.dart';

final _log = Logger('social');

/// Una voce della cassetta delle notifiche (spec G §6.2).
sealed class InboxEntry {
  const InboxEntry({
    required this.id,
    required this.seq,
    required this.createdAt,
    required this.read,
  });

  final String id;

  /// Progressivo per utente: cresce a ogni voce nuova o aggiornata.
  final int seq;

  /// In UTC.
  final DateTime createdAt;

  /// Già letta secondo il plugin.
  final bool read;
}

/// Un amico ci ha invitato in un watch party (spec G §6.5).
final class InviteEntry extends InboxEntry {
  const InviteEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    required this.groupId,
    required this.fromName,
    required this.title,
    this.imageItemId,
  });

  final String groupId;
  final String fromName;
  final String title;

  /// La locandina (la serie, per un episodio); `null` se il plugin non l'ha.
  final String? imageItemId;
}

/// Un annuncio dell'admin (spec G §6.7).
final class AnnouncementEntry extends InboxEntry {
  const AnnouncementEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    required this.text,
  });

  final String text;
}

/// Un film nuovo (spec G §6.6).
class NewTitleMovie {
  const NewTitleMovie({required this.itemId, required this.name, this.year});

  factory NewTitleMovie.fromJson(Map<String, dynamic> json) => NewTitleMovie(
        itemId: json['ItemId'] as String,
        name: json['Name'] as String,
        year: (json['Year'] as num?)?.toInt(),
      );

  final String itemId;
  final String name;
  final int? year;
}

/// Un episodio nuovo: stagione e numero, se Jellyfin li conosce.
class NewTitleEpisode {
  const NewTitleEpisode({this.season, this.episode});

  factory NewTitleEpisode.fromJson(Map<String, dynamic> json) =>
      NewTitleEpisode(
        season: (json['Season'] as num?)?.toInt(),
        episode: (json['Episode'] as num?)?.toInt(),
      );

  final int? season;
  final int? episode;
}

/// Una serie seguita con i suoi episodi nuovi; la riga apre la serie.
class NewTitleSeries {
  const NewTitleSeries({
    required this.seriesId,
    required this.name,
    required this.episodes,
  });

  factory NewTitleSeries.fromJson(Map<String, dynamic> json) => NewTitleSeries(
        seriesId: json['SeriesId'] as String,
        name: json['Name'] as String,
        episodes: [
          for (final raw in json['Episodes'] as List? ?? const [])
            NewTitleEpisode.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final String seriesId;
  final String name;
  final List<NewTitleEpisode> episodes;
}

/// Gli episodi come intervalli per stagione (spec G §7.6): `S3 E1–E10`,
/// `S3 E1–E4, E6`, più stagioni unite da ` · ` (`S2 E10 · S3 E1–E3`).
/// `null` se manca anche un solo numero (chi mostra la riga scrive allora
/// "N episodi nuovi") o se non ci sono episodi.
String? formatEpisodeRanges(List<NewTitleEpisode> episodes) {
  if (episodes.isEmpty ||
      episodes.any((e) => e.season == null || e.episode == null)) {
    return null;
  }
  final bySeason = SplayTreeMap<int, SplayTreeSet<int>>();
  for (final episode in episodes) {
    (bySeason[episode.season!] ??= SplayTreeSet<int>()).add(episode.episode!);
  }
  return [
    for (final MapEntry(key: season, value: numbers) in bySeason.entries)
      'S$season ${_episodeRuns(numbers.toList())}',
  ].join(' · ');
}

/// Numeri ordinati e senza doppioni come `E1–E4, E6`.
String _episodeRuns(List<int> numbers) {
  final runs = <String>[];
  var start = numbers.first;
  var previous = start;
  for (final number in numbers.skip(1)) {
    if (number == previous + 1) {
      previous = number;
      continue;
    }
    runs.add(_episodeRun(start, previous));
    start = previous = number;
  }
  runs.add(_episodeRun(start, previous));
  return runs.join(', ');
}

String _episodeRun(int first, int last) =>
    first == last ? 'E$first' : 'E$first–E$last';

/// Il riepilogo di un'ondata di nuovi titoli (spec G §6.6): film che
/// l'utente può vedere ed episodi delle serie che segue.
final class NewTitlesEntry extends InboxEntry {
  const NewTitlesEntry({
    required super.id,
    required super.seq,
    required super.createdAt,
    required super.read,
    this.movies = const [],
    this.series = const [],
    this.more = 0,
  });

  final List<NewTitleMovie> movies;
  final List<NewTitleSeries> series;

  /// Film e serie oltre il tetto delle righe del plugin.
  final int more;

  /// Episodi in tutto.
  int get episodeCount =>
      series.fold(0, (count, s) => count + s.episodes.length);
}

/// Una voce di `GET Inbox`; `null` se il tipo non lo conosciamo (es. le
/// voci di una versione più nuova del plugin).
InboxEntry? inboxEntryFromJson(Map<String, dynamic> json) {
  final id = json['Id'] as String;
  final seq = (json['Seq'] as num).toInt();
  final createdAt = DateTime.parse(json['CreatedAt'] as String).toUtc();
  final read = json['Read'] as bool? ?? false;
  return switch (json['Type']) {
    'Invite' => InviteEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        groupId: json['GroupId'] as String,
        fromName: json['FromName'] as String,
        title: json['Title'] as String,
        imageItemId: json['ImageItemId'] as String?,
      ),
    'Announcement' => AnnouncementEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        text: json['Text'] as String,
      ),
    'NewTitles' => NewTitlesEntry(
        id: id,
        seq: seq,
        createdAt: createdAt,
        read: read,
        movies: [
          for (final raw in json['Movies'] as List? ?? const [])
            NewTitleMovie.fromJson(raw as Map<String, dynamic>),
        ],
        series: [
          for (final raw in json['Series'] as List? ?? const [])
            NewTitleSeries.fromJson(raw as Map<String, dynamic>),
        ],
        more: (json['More'] as num?)?.toInt() ?? 0,
      ),
    _ => null,
  };
}

/// Risposta di `GET Inbox`: le voci dalla più recente e quante non lette.
class InboxSnapshot {
  const InboxSnapshot({this.entries = const [], this.unread = 0});

  factory InboxSnapshot.fromJson(Map<String, dynamic> json) {
    final entries = <InboxEntry>[];
    for (final raw in json['Entries'] as List? ?? const []) {
      try {
        final entry = inboxEntryFromJson(raw as Map<String, dynamic>);
        if (entry != null) entries.add(entry);
      } on Object catch (error) {
        // Una voce malformata non deve rompere tutta la cassetta: si salta.
        // Nel log solo il tipo dell'errore, mai il contenuto.
        _log.info('voce della cassetta non valida: ${error.runtimeType}');
      }
    }
    return InboxSnapshot(
      entries: entries,
      // Non si usa l'`Unread` del server: conta anche le voci di tipi che
      // l'app non conosce (es. un plugin più nuovo), che qui non ci sono e
      // che `markRead(maxSeq)` non può coprire perché vede solo le voci
      // lette: il pallino resterebbe acceso per sempre. Si contano solo le
      // voci che l'utente può vedere e quindi segnare lette.
      unread: entries.where((e) => !e.read).length,
    );
  }

  static const empty = InboxSnapshot();

  final List<InboxEntry> entries;
  final int unread;

  /// Il Seq più alto (0 se vuota): fin lì si segna letto.
  int get maxSeq => entries.fold(0, (max, e) => math.max(max, e.seq));

  /// Tutto letto. Le voci restano come sono: chi apre il pannello decide
  /// quali hanno il pallino.
  InboxSnapshot markedRead() => InboxSnapshot(entries: entries, unread: 0);

  /// Senza la voce [id]; se era non letta il conto scende.
  InboxSnapshot without(String id) {
    final removed = entries.where((e) => e.id == id).toList();
    if (removed.isEmpty) return this;
    return InboxSnapshot(
      entries: [
        for (final e in entries)
          if (e.id != id) e,
      ],
      unread: math.max(0, unread - removed.where((e) => !e.read).length),
    );
  }
}

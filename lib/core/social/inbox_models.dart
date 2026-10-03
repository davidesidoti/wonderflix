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

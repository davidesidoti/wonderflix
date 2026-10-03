import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/inbox_models.dart';

import '../../support/social_fakes.dart';

void main() {
  test('voci della cassetta: invito, annuncio; i tipi sconosciuti si saltano',
      () {
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'i1',
          'Seq': 3,
          'Type': 'Invite',
          'CreatedAt': '2026-10-03T20:00:00.1234567+00:00',
          'Read': false,
          'GroupId': 'g1',
          'FromName': 'Luigi',
          'Title': 'Dune',
          'ImageItemId': 'm1',
        },
        {
          'Id': 'n1',
          'Seq': 2,
          'Type': 'NewTitles',
          'CreatedAt': '2026-10-03T19:00:00+00:00',
          'Read': false,
        },
        {
          'Id': 'a1',
          'Seq': 1,
          'Type': 'Announcement',
          'CreatedAt': '2026-10-03T18:00:00+02:00',
          'Read': true,
          'Text': 'Stasera manutenzione',
        },
      ],
      'Unread': 2,
    });

    expect(snapshot.entries, hasLength(2));
    // Il `Unread: 2` del server conta anche la voce di tipo sconosciuto, che
    // l'app non mostra e non può segnare letta: vale solo l'invito.
    expect(snapshot.unread, 1);
    expect(snapshot.maxSeq, 3);
    final invite = snapshot.entries.first as InviteEntry;
    expect(invite.id, 'i1');
    expect(invite.seq, 3);
    expect(invite.read, isFalse);
    expect(invite.groupId, 'g1');
    expect(invite.fromName, 'Luigi');
    expect(invite.title, 'Dune');
    expect(invite.imageItemId, 'm1');
    expect(invite.createdAt, DateTime.utc(2026, 10, 3, 20, 0, 0, 123, 456));
    final announcement = snapshot.entries.last as AnnouncementEntry;
    expect(announcement.text, 'Stasera manutenzione');
    expect(announcement.read, isTrue);
    expect(announcement.createdAt, DateTime.utc(2026, 10, 3, 16));
  });

  test('una voce malformata si salta, le altre restano', () {
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'i1',
          'Seq': 3,
          'Type': 'Invite',
          'CreatedAt': '2026-10-03T20:00:00+00:00',
          'GroupId': 'g1',
          'FromName': 'Luigi',
        },
        {
          'Id': 'a0',
          'Seq': 2,
          'Type': 'Announcement',
          'CreatedAt': 'non una data',
          'Text': 'Stasera manutenzione',
        },
        {
          'Id': 'a2',
          'Seq': 4,
          'Type': 'Announcement',
          'CreatedAt': '2026-10-03T18:00:00+00:00',
          'Text': 7,
        },
        {
          'Id': 'a1',
          'Seq': 1,
          'Type': 'Announcement',
          'CreatedAt': '2026-10-03T18:00:00+00:00',
          'Text': 'Stasera manutenzione',
        },
      ],
      'Unread': 4,
    });

    expect(snapshot.entries.map((e) => e.id), ['a1']);
    expect(snapshot.unread, 1);
    expect(snapshot.maxSeq, 1);
  });

  test('cassetta vuota; invito senza locandina', () {
    expect(InboxSnapshot.fromJson(const {}).entries, isEmpty);
    expect(InboxSnapshot.fromJson(const {}).unread, 0);
    expect(InboxSnapshot.empty.maxSeq, 0);
    final snapshot = InboxSnapshot.fromJson({
      'Entries': [
        {
          'Id': 'i1',
          'Seq': 1,
          'Type': 'Invite',
          'CreatedAt': '2026-10-03T20:00:00+00:00',
          'GroupId': 'g1',
          'FromName': 'Luigi',
          'Title': 'Dune',
        },
      ],
      'Unread': 1,
    });
    final invite = snapshot.entries.single as InviteEntry;
    expect(invite.imageItemId, isNull);
    expect(invite.read, isFalse);
  });

  test('tutto letto; senza una voce', () {
    final snapshot = InboxSnapshot(entries: [
      testInvite(id: 'i1', seq: 2),
      testAnnouncement(id: 'a1', seq: 1, read: true),
    ], unread: 1);

    expect(snapshot.markedRead().unread, 0);
    expect(snapshot.markedRead().entries, hasLength(2));
    final without = snapshot.without('i1');
    expect(without.entries.map((e) => e.id), ['a1']);
    expect(without.unread, 0);
    expect(snapshot.without('a1').unread, 1);
    expect(identical(snapshot.without('x'), snapshot), isTrue);
  });
}

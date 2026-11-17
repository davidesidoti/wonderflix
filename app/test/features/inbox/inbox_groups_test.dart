import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/inbox/inbox_groups.dart';

import '../../support/social_fakes.dart';

void main() {
  test('Server: download, spazio, riavvio, recupero, richieste in attesa', () {
    expect(isServerEntry(testRequestPending()), isTrue);
    final t = DateTime.utc(2026, 11, 16);
    expect(
      isServerEntry(
        RestartPendingEntry(id: 'x', seq: 1, createdAt: t, read: false),
      ),
      isTrue,
    );
    expect(
      isServerEntry(
        DiskAlmostFullEntry(
          id: 'd',
          seq: 1,
          createdAt: t,
          read: false,
          percent: 95,
        ),
      ),
      isTrue,
    );
    expect(
      isServerEntry(
        ReportPendingEntry(
          id: 'p',
          seq: 1,
          createdAt: t,
          read: false,
          reportId: 'r',
          fromName: 'Garg',
          itemId: 'm1',
          title: 'Dune',
        ),
      ),
      isTrue,
    );
    expect(isServerEntry(testInvite()), isFalse);
    expect(isServerEntry(testRequestAvailable()), isFalse);
    expect(isServerEntry(testRecommendationEntry()), isFalse);
  });
}

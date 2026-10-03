import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/shell_panels.dart';
import 'package:wonderflix/core/social/inbox_models.dart';
import 'package:wonderflix/features/friends/friends_controller.dart';
import 'package:wonderflix/features/inbox/inbox_controller.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../support/social_fakes.dart';

void main() {
  test('un pannello alla volta: aprirne uno chiude l\'altro', () async {
    final api = FakeSocialApi()
      ..inboxSnapshot =
          InboxSnapshot(entries: [testAnnouncement(seq: 4)], unread: 1);
    final c = ProviderContainer.test(
        overrides: socialTestOverrides(api,
            features: const SocialFeatures(friends: true, inbox: true)));
    c.listen(shellPanelProvider, (_, _) {});
    c.listen(inboxControllerProvider, (_, _) {});
    c.listen(friendsControllerProvider, (_, _) {});
    await pumpEventQueue();
    api.calls.clear();
    final panels = c.read(shellPanelProvider.notifier);

    panels.open(ShellPanel.friends);
    expect(c.read(shellPanelProvider), ShellPanel.friends);
    await pumpEventQueue();
    expect(api.calls, contains('friends'), reason: 'aprire Amici li rilegge');

    panels.open(ShellPanel.inbox);
    expect(c.read(shellPanelProvider), ShellPanel.inbox);
    expect(c.read(inboxControllerProvider).unread, 0);
    expect(c.read(inboxControllerProvider).highlighted, {'a1'});
    await pumpEventQueue();
    expect(api.calls, contains('read 4'));

    panels.toggle(ShellPanel.friends);
    expect(c.read(shellPanelProvider), ShellPanel.friends);
    expect(c.read(inboxControllerProvider).highlighted, isEmpty,
        reason: 'chiudere Notifiche toglie i pallini');

    panels.toggle(ShellPanel.friends);
    expect(c.read(shellPanelProvider), ShellPanel.none);
  });
}

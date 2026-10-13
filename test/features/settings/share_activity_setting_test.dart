import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/social/social_api.dart';
import 'package:wonderflix/features/auth/session_controller.dart';
import 'package:wonderflix/features/settings/account_settings_section.dart';
import 'package:wonderflix/features/settings/share_activity_setting.dart';
import 'package:wonderflix/features/social/social_providers.dart';

import '../../support/account_fakes.dart';
import '../../support/fake_session_controller.dart';
import '../../support/pump_app.dart';
import '../../support/social_fakes.dart';
import '../../support/test_data.dart';

void main() {
  late FakeSocialApi api;

  setUp(() => api = FakeSocialApi());

  Future<void> pumpSetting(WidgetTester tester) async {
    await pumpApp(
      tester,
      const Scaffold(body: ShareActivitySetting()),
      overrides: socialTestOverrides(api,
          features: const SocialFeatures(friends: true, friendsActivity: true)),
    );
    await tester.pump();
  }

  SwitchListTile tile(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byKey(const Key('share-activity')));

  testWidgets('acceso dal plugin, con il testo sotto', (tester) async {
    await pumpSetting(tester);
    expect(api.calls, contains('activitySettings'));
    expect(find.text('Mostra agli amici cosa guardo'), findsOneWidget);
    expect(
        find.text('Gli amici vedono il titolo che stai guardando e quelli che '
            'hai visto negli ultimi 30 giorni in WonderFlix'),
        findsOneWidget);
    expect(tile(tester).value, isTrue);
  });

  testWidgets('spento e riacceso: salva subito', (tester) async {
    await pumpSetting(tester);
    await tester.tap(find.byKey(const Key('share-activity')));
    await tester.pump();
    expect(api.calls, contains('setActivity false'));
    expect(tile(tester).value, isFalse);
    await tester.tap(find.byKey(const Key('share-activity')));
    await tester.pump();
    expect(api.calls, contains('setActivity true'));
    expect(tile(tester).value, isTrue);
  });

  testWidgets('salvataggio non riuscito: torna com\'era e lo dice',
      (tester) async {
    api.shareActivityFailure = SocialFailure.network;
    await pumpSetting(tester);
    await tester.tap(find.byKey(const Key('share-activity')));
    await tester.pump();
    await tester.pump();
    expect(tile(tester).value, isTrue);
    expect(find.text('Impostazione non salvata'), findsOneWidget);
  });

  testWidgets('lettura non riuscita: il messaggio e Riprova', (tester) async {
    api.nextFailure = SocialFailure.network;
    await pumpSetting(tester);
    expect(find.text('Impossibile caricare l\'impostazione'), findsOneWidget);
    expect(find.byKey(const Key('share-activity')), findsNothing);
    await tester.tap(find.byKey(const Key('share-activity-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('share-activity')), findsOneWidget);
  });

  testWidgets('in Account senza la funzione: niente interruttore',(tester) async {
    Future<void> pumpAccount(SocialFeatures features) => pumpApp(
          tester,
          const Scaffold(
              body: SingleChildScrollView(child: AccountSettingsSection())),
          overrides: [
            sessionControllerProvider.overrideWith(
                () => FakeSessionController(const SessionSignedIn(testUser))),
            ...accountTestOverrides(FakeAccountApi(), available: false),
            ...socialTestOverrides(api, features: features, session: false),
          ],
        );

    await pumpAccount(const SocialFeatures(friends: true));
    await tester.pump();
    expect(find.byType(ShareActivitySetting), findsNothing);
    expect(api.calls, isNot(contains('activitySettings')));
  });

  testWidgets('in Account con la funzione c\'è l\'interruttore',
      (tester) async {
    await pumpApp(
      tester,
      const Scaffold(
          body: SingleChildScrollView(child: AccountSettingsSection())),
      overrides: [
        sessionControllerProvider.overrideWith(
            () => FakeSessionController(const SessionSignedIn(testUser))),
        ...accountTestOverrides(FakeAccountApi(), available: false),
        ...socialTestOverrides(api,
            features:
                const SocialFeatures(friends: true, friendsActivity: true),
            session: false),
      ],
    );
    await tester.pump();
    expect(find.byType(ShareActivitySetting), findsOneWidget);
  });
}

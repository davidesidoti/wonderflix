import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/hero_launch.dart';
import 'package:wonderflix/app/motion.dart';
import 'package:wonderflix/core/jellyfin/image_urls.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/features/detail/detail_providers.dart';
import 'package:wonderflix/features/detail/item_detail_screen.dart';
import 'package:wonderflix/features/person/person_screen.dart';
import 'package:wonderflix/ui/backdrop_image.dart';
import 'package:wonderflix/ui/smooth_scroll.dart';
import 'package:wonderflix/ui/states.dart';

import '../../support/pump_app.dart';

void main() {
  const launch = HeroLaunch(
    tag: WfHeroTag('m1', 'home.latest.0'),
    image: ImageRef('https://media.example.com/Items/m1/Images/Backdrop/0'),
    title: 'Dune',
  );

  testWidgets('scheda in caricamento: sfondo e Hero già presenti',
      (tester) async {
    final pending = Completer<JellyfinItem>();
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1', launch: launch)),
      overrides: [itemProvider('m1').overrideWith((ref) => pending.future)],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag, launch.tag);
    expect(find.byType(BackdropImage), findsOneWidget);
    expect(find.byType(LoadingView), findsOneWidget);
  });

  testWidgets('scheda in caricamento senza volo: solo l\'indicatore',
      (tester) async {
    final pending = Completer<JellyfinItem>();
    await pumpApp(
      tester,
      const Scaffold(body: ItemDetailScreen(itemId: 'm1')),
      overrides: [itemProvider('m1').overrideWith((ref) => pending.future)],
      motion: MotionLevel.full,
    );
    expect(find.byType(Hero), findsNothing);
    expect(find.byType(BackdropImage), findsNothing);
    expect(find.byType(LoadingView), findsOneWidget);
  });

  testWidgets('persona in caricamento: foto (Hero) e nome già presenti',
      (tester) async {
    final pending = Completer<JellyfinItem>();
    const personLaunch = HeroLaunch(
      tag: WfHeroTag('p9', 'cast.m1.0'),
      image: ImageRef('https://media.example.com/Items/p9/Images/Primary'),
      title: 'Zendaya',
    );
    await pumpApp(
      tester,
      const Scaffold(body: PersonScreen(personId: 'p9', launch: personLaunch)),
      overrides: [itemProvider('p9').overrideWith((ref) => pending.future)],
      motion: MotionLevel.full,
    );
    expect(tester.widget<Hero>(find.byType(Hero)).tag, personLaunch.tag);
    expect(find.text('ZENDAYA'), findsOneWidget);
    expect(find.byType(LoadingView), findsOneWidget);
    final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    expect(scroll.controller, isA<SmoothScrollController>());
  });
}

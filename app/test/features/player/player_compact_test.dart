import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/library/item_labels.dart';
import 'package:wonderflix/features/player/pause_screen.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_extras.dart';
import 'package:wonderflix/features/player/player_overlay.dart';
import 'package:wonderflix/features/player/player_side_panel_host.dart';
import 'package:wonderflix/features/player/post_play.dart';
import 'package:wonderflix/features/player/queue_panel/queue_panel.dart';
import 'package:wonderflix/features/ratings/rating_round_controller.dart';
import 'package:wonderflix/features/ratings/rating_round_panel.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/form_factor.dart';

import '../../support/library_fakes.dart';
import '../../support/playback_fakes.dart';
import '../../support/pump_app.dart';
import '../../support/rating_fakes.dart';

/// Player nel layout stretto (spec §4.5): controlli, pannelli, post-play,
/// pausa e scheda del prossimo episodio a misura di telefono.
void main() {
  final l = lookupAppLocalizations(const Locale('it'));
  const phoneSizes = [Size(390, 844), Size(844, 390)];

  final episode = testItem(
    id: 'e4',
    name: 'Un titolo di episodio molto lungo che non entra in una riga',
    kind: ItemKind.episode,
    seriesName: 'Una serie con un nome lunghissimo che non entra mai',
    index: 4,
    seasonIndex: 1,
    overview: 'Walter e Jesse devono liberarsi di un corpo. ' * 6,
    genres: const ['Dramma', 'Crimine'],
    year: 2008,
  );

  /// I controlli con tutti i comandi possibili (party, episodio prima e
  /// dopo, guarda insieme): ogni comando registra il suo nome in `calls`.
  Future<List<String>> pumpOverlay(
    WidgetTester tester,
    Size size, {
    bool touch = true,
    bool chatUnread = false,
  }) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: PlayerOverlay(
          view: PlayerViewState(
            status: PlayerStatus.ready,
            playing: true,
            item: episode,
          ),
          engine: FakeVideoEngine(),
          fullscreen: false,
          onBack: () => calls.add('back'),
          onTogglePlay: () => calls.add('play'),
          onSeekBy: (offset) => calls.add('seek ${offset.inSeconds}'),
          onSeekTo: (_) {},
          onVolume: (_) {},
          onToggleMute: () => calls.add('mute'),
          onToggleTracks: () => calls.add('tracks'),
          onToggleFullscreen: () => calls.add('fullscreen'),
          onNextEpisode: () => calls.add('next'),
          onPrevious: () => calls.add('previous'),
          partyQueue: true,
          partyBadge: const SizedBox(width: 80, height: 32),
          onWatchTogether: (_) => calls.add('together'),
          onToggleChat: () => calls.add('chat'),
          chatUnread: chatUnread,
          onToggleReactions: () => calls.add('reactions'),
          reactionsLink: LayerLink(),
          onToggleQueue: () => calls.add('queue'),
        ),
      ),
      surfaceSize: size,
      touch: touch,
    );
    return calls;
  }

  for (final size in phoneSizes) {
    final name = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets(
      'stretto: controlli senza overflow, con play al centro ($name)',
      (tester) async {
        final calls = await pumpOverlay(tester, size);
        expect(find.text(cardTitle(episode)), findsOneWidget);
        expect(tester.takeException(), isNull);

        final play = tester.getRect(find.byTooltip(l.playerPause));
        expect(play.center.dx, closeTo(size.width / 2, 1));
        expect(play.center.dy, closeTo(size.height / 2, 1));
        expect(play.width, 64);
        final rewind = tester.getRect(find.byTooltip(l.playerRewind));
        final forward = tester.getRect(find.byTooltip(l.playerForward));
        expect(rewind.center.dy, closeTo(play.center.dy, 1));
        expect(rewind.right, lessThanOrEqualTo(play.left));
        expect(forward.left, greaterThanOrEqualTo(play.right));

        // Ogni pulsante visibile è almeno 44×44 e dentro lo schermo.
        for (final element in find.byType(IconButton).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.width, greaterThanOrEqualTo(minTouchTarget));
          expect(rect.height, greaterThanOrEqualTo(minTouchTarget));
          expect(Offset.zero & size, _contains(rect));
        }

        await tester.tap(find.byTooltip(l.playerPause));
        await tester.tap(find.byTooltip(l.playerRewind));
        await tester.tap(find.byTooltip(l.playerForward));
        expect(calls, ['play', 'seek -10', 'seek 10']);
      },
    );

    testWidgets('stretto: ogni comando del player è raggiungibile ($name)', (
      tester,
    ) async {
      final calls = await pumpOverlay(tester, size);
      final commands = {
        l.playerAudioAndSubtitles: 'tracks',
        l.partyQueueOpen: 'queue',
        l.partyChatOpen: 'chat',
        l.partyReactionsOpen: 'reactions',
        l.watchPartyWatchTogether: 'together',
        l.playerPreviousInQueue: 'previous',
        l.playerNextInQueue: 'next',
        l.playerFullscreen: 'fullscreen',
        l.playerMute: 'mute',
        l.navBack: 'back',
      };
      var inMenu = 0;
      for (final MapEntry(key: tooltip, value: call) in commands.entries) {
        final button = find.byTooltip(tooltip);
        if (button.evaluate().isNotEmpty) {
          await tester.tap(button);
        } else {
          inMenu++;
          await tester.tap(find.byTooltip(l.playerMoreControls));
          await tester.pumpAndSettle();
          await tester.tap(find.text(tooltip));
          await tester.pumpAndSettle();
        }
        expect(calls.last, call, reason: tooltip);
      }
      if (size.width < 400) {
        expect(inMenu, greaterThan(0), reason: 'in verticale non entrano');
      }
    });
  }

  testWidgets('stretto col mouse: resta il volume, senza overflow', (
    tester,
  ) async {
    for (final size in phoneSizes) {
      await pumpOverlay(tester, size, touch: false);
      expect(tester.takeException(), isNull, reason: '$size');
      // In verticale non c'è posto: resta il muto.
      expect(
        find.byKey(const Key('volume-slider')),
        size.width < 480 ? findsNothing : findsOneWidget,
        reason: '$size',
      );
    }
  });

  testWidgets('stretto col mouse in orizzontale: volume e tutte le icone, '
      'allineate a destra', (tester) async {
    await pumpOverlay(tester, const Size(844, 390), touch: false);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('volume-slider')), findsOneWidget);
    expect(find.byTooltip(l.playerMoreControls), findsNothing);
    final right = find
        .byType(IconButton)
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)).right)
        .reduce((a, b) => a > b ? a : b);
    expect(right, closeTo(844 - 12, 0.5));
  });

  testWidgets('stretto: la chat nel menu ⋯ porta il puntino sul ⋯', (
    tester,
  ) async {
    // In verticale la chat non entra nella riga.
    const size = Size(390, 844);
    await pumpOverlay(tester, size, chatUnread: true);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('player-chat-button')), findsNothing);
    Finder dotOnMore() => find.descendant(
      of: find.byKey(const Key('player-more-controls')),
      matching: find.byKey(const Key('player-chat-unread')),
    );
    expect(dotOnMore(), findsOneWidget);

    await pumpOverlay(tester, size);
    expect(dotOnMore(), findsNothing);
  });

  testWidgets('largo (1440×900): niente menu ⋯ né play al centro', (
    tester,
  ) async {
    await pumpOverlay(tester, const Size(1440, 900));
    expect(find.byTooltip(l.playerMoreControls), findsNothing);
    final play = tester.getRect(find.byTooltip(l.playerPause));
    expect(play.center.dy, greaterThan(800));
  });

  testWidgets(
    'stretto: il pannello tracce si apre dal basso a tutta larghezza',
    (tester) async {
      for (final size in phoneSizes) {
        await pumpApp(
          tester,
          const PlayerSidePanelHost(
            open: true,
            panel: ColoredBox(key: Key('panel'), color: Colors.red),
          ),
          surfaceSize: size,
          touch: true,
        );
        final panel = tester.getRect(find.byKey(const Key('panel')));
        expect(panel.width, size.width);
        expect(panel.bottom, size.height);
        expect(panel.height, lessThanOrEqualTo(size.height * 0.7 + 0.01));
      }
    },
  );

  for (final size in phoneSizes) {
    final name = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets('stretto: la coda vera nel foglio dal basso, senza overflow '
        '($name)', (tester) async {
      final items = <String, JellyfinItem?>{
        for (var i = 1; i <= 12; i++)
          'e$i': testItem(
            id: 'e$i',
            name: 'Un episodio dal titolo piuttosto lungo numero $i',
            kind: ItemKind.episode,
            seriesName: 'Una serie con un nome lunghissimo',
            seriesId: 's1',
            index: i,
            seasonIndex: 1,
          ),
      };
      await pumpApp(
        tester,
        Scaffold(
          body: PlayerSidePanelHost(
            open: true,
            panel: QueuePanel(
              queue: PlayQueue(
                reason: 'NewPlaylist',
                lastUpdate: DateTime.utc(2026, 10, 4, 10),
                entries: [
                  for (var i = 1; i <= 12; i++)
                    PlayQueueEntry(itemId: 'e$i', playlistItemId: 'p$i'),
                ],
                playingIndex: 2,
                startPosition: Duration.zero,
                isPlaying: true,
                shuffled: false,
              ),
              items: items,
              onJump: (_) {},
              onRemove: (_) {},
              onMove: (_, _) {},
              onShuffle: (_) {},
              onClose: () {},
              onAddTitles: () {},
            ),
          ),
        ),
        surfaceSize: size,
        touch: true,
      );
      await tester.pumpAndSettle();
      expect(find.text(l.partyQueueTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byType(QueuePanel)).width, size.width);
    });

    for (final revealed in [false, true]) {
      final phase = revealed ? 'risultati' : 'voto';
      testWidgets('stretto: il voto vero nel foglio dal basso, senza overflow '
          '($name, $phase)', (tester) async {
        final voters = [
          {'UserId': 'u1', 'Name': 'Mario', 'Status': 'Voted'},
          {'UserId': 'u2', 'Name': 'Luigi', 'Status': 'Voted'},
          {'UserId': 'u3', 'Name': 'Peach', 'Status': 'Waiting'},
        ];
        final round = revealed
            ? testRatingRound(
                phase: 'Revealed',
                average: 7.5,
                voters: voters,
                results: [
                  {
                    'UserId': 'u2',
                    'Name': 'Luigi',
                    'Score': 9,
                    'Comment': 'Capolavoro assoluto, da rivedere subito ' * 3,
                  },
                  {'UserId': 'u1', 'Name': 'Mario', 'Score': 6},
                ],
              )
            : testRatingRound(voters: voters);
        await pumpApp(
          tester,
          Scaffold(
            body: PlayerSidePanelHost(
              open: true,
              panel: RatingRoundPanel(onClose: () {}),
            ),
          ),
          overrides: [
            ratingRoundProvider.overrideWith(
              () => _Rating(
                RatingRoundView(
                  round: round,
                  playlistItemId: 'p1',
                  userId: 'u1',
                  source: testItem(name: 'Il Padrino'),
                ),
              ),
            ),
          ],
          surfaceSize: size,
          touch: true,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('rating-panel')), findsOneWidget);
        expect(find.textContaining('Il Padrino'), findsWidgets);
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byKey(const Key('rating-panel'))).width,
          size.width,
        );
      });
    }
  }

  testWidgets('largo: il pannello resta a destra', (tester) async {
    await pumpApp(
      tester,
      const PlayerSidePanelHost(
        open: true,
        panel: ColoredBox(key: Key('panel'), color: Colors.red),
      ),
    );
    expect(
      tester.getRect(find.byKey(const Key('panel'))),
      const Rect.fromLTWH(1440 - 360, 0, 360, 900),
    );
  });

  for (final size in phoneSizes) {
    final name = '${size.width.toInt()}×${size.height.toInt()}';
    for (final rating in [false, true]) {
      testWidgets(
        'stretto: post-play con video sopra e informazioni sotto, senza '
        'overflow ($name${rating ? ', con il voto' : ''})',
        (tester) async {
          await pumpApp(
            tester,
            Scaffold(
              body: Stack(
                children: [
                  PostPlayFrame(
                    active: true,
                    child: const ColoredBox(
                      key: Key('film'),
                      color: Color(0xFF00FF00),
                    ),
                  ),
                  PostPlayLayer(
                    episode: episode,
                    countdown: false,
                    paused: false,
                    showImage: !rating,
                    onPlay: () {},
                    onWatchCredits: () {},
                  ),
                  if (rating)
                    Positioned.fromRect(
                      rect: postPlaySideRect(size, compact: true),
                      child: const ColoredBox(
                        key: Key('rating'),
                        color: Colors.blue,
                      ),
                    ),
                ],
              ),
            ),
            surfaceSize: size,
            touch: true,
          );
          await tester.pumpAndSettle();
          expect(find.text('PROSSIMO EPISODIO'), findsOneWidget);
          expect(tester.takeException(), isNull);

          final film = tester.getRect(find.byKey(const Key('film')));
          final eyebrow = tester.getRect(find.text('PROSSIMO EPISODIO'));
          final play = tester.getRect(find.byType(PlayNowButton));
          expect(eyebrow.top, greaterThan(film.bottom));
          expect(Offset.zero & size, _contains(play));
          expect(find.byKey(const Key('post-play-image')), findsNothing);
          if (rating) {
            final panel = tester.getRect(find.byKey(const Key('rating')));
            expect(panel.top, greaterThan(film.bottom));
            expect(panel.overlaps(play), isFalse);
            expect(panel.overlaps(eyebrow), isFalse);
          }
        },
      );
    }

    testWidgets('stretto: schermata di pausa senza overflow ($name)', (
      tester,
    ) async {
      await pumpApp(
        tester,
        // Nel player sta dentro uno `Scaffold` (lo stile del testo).
        Scaffold(body: PauseScreen(item: episode, visible: true)),
        surfaceSize: size,
        touch: true,
      );
      await tester.pumpAndSettle();
      expect(find.text(l.playerWatching.toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Testo ridimensionato: margine stretto, titolo su una riga.
      expect(
        tester.getTopLeft(find.text(l.playerWatching.toUpperCase())).dx,
        PauseScreen.compactTextInset,
      );
      final title = find.text(cardTitle(episode).toUpperCase());
      expect(tester.getSize(title).height, lessThan(48));
    });

    testWidgets('stretto: la scheda del prossimo episodio sta nello schermo '
        '($name)', (tester) async {
      await pumpApp(
        tester,
        Stack(
          children: [
            Positioned(
              right: 16,
              bottom: 150,
              child: NextEpisodeCard(
                episode: episode,
                label: 'PROSSIMO EPISODIO',
                countdown: false,
                paused: false,
                onPlay: () {},
                onCancel: () {},
              ),
            ),
          ],
        ),
        surfaceSize: size,
        touch: true,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(NextEpisodeCard));
      expect(card.left, greaterThanOrEqualTo(16));
      expect(card.width, lessThanOrEqualTo(380));
    });
  }
}

/// `rect` è tutto dentro il rettangolo atteso (mezzo punto di tolleranza).
Matcher _contains(Rect rect) => predicate<Rect>(
  (outer) =>
      outer.inflate(0.5).contains(rect.topLeft) &&
      outer.inflate(0.5).contains(rect.bottomRight),
  'contains $rect',
);

/// La votazione del party ferma su una vista data.
class _Rating extends RatingRoundController {
  _Rating(this.view);

  final RatingRoundView view;

  @override
  RatingRoundView? build() => view;
}

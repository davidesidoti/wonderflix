import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/core/jellyfin/item_models.dart';
import 'package:wonderflix/core/syncplay/syncplay_models.dart';
import 'package:wonderflix/features/library/item_labels.dart';
import 'package:wonderflix/features/player/pause_screen.dart';
import 'package:wonderflix/features/player/player_controller.dart';
import 'package:wonderflix/features/player/player_extras.dart';
import 'package:wonderflix/features/player/player_overlay.dart';
import 'package:wonderflix/features/player/player_side_panel_host.dart';
import 'package:wonderflix/features/player/post_play.dart';
import 'package:wonderflix/features/player/seek_bar.dart';
import 'package:wonderflix/features/player/queue_panel/queue_panel.dart';
import 'package:wonderflix/features/ratings/rating_round_controller.dart';
import 'package:wonderflix/features/ratings/rating_round_panel.dart';
import 'package:wonderflix/l10n/gen/app_localizations.dart';
import 'package:wonderflix/ui/form_factor.dart';
import 'package:wonderflix/ui/wf_buttons.dart';

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
    bool party = true,
    double textScale = 1,
    ValueChanged<double>? onRate,
  }) async {
    final calls = <String>[];
    await pumpApp(
      tester,
      Scaffold(
        body: Builder(builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: PlayerOverlay(
          view: PlayerViewState(
            status: PlayerStatus.ready,
            playing: true,
            item: episode,
          ),
          engine: FakeVideoEngine(),
          fullscreen: false,
          onBack: () => calls.add('back'),
          backLabel: 'Torna alla scheda',
          onTogglePlay: () => calls.add('play'),
          onSeekBy: (offset) => calls.add('seek ${offset.inSeconds}'),
          onSeekTo: (_) {},
          onVolume: (_) {},
          onToggleMute: () => calls.add('mute'),
          onToggleTracks: () => calls.add('tracks'),
          onToggleFullscreen: () => calls.add('fullscreen'),
          onNextEpisode: () => calls.add('next'),
          onPrevious: () => calls.add('previous'),
          partyQueue: party,
          partyBadge: const SizedBox(width: 80, height: 32),
          onWatchTogether: (_) => calls.add('together'),
          onToggleChat: party ? () => calls.add('chat') : null,
          chatUnread: chatUnread,
          onToggleReactions: party ? () => calls.add('reactions') : null,
          reactionsLink: LayerLink(),
          onToggleQueue: party ? () => calls.add('queue') : null,
          onRate: onRate,
        ),
        )),
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
        expect(play.width, PlayerOverlay.centerPlaySize);
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
      final buttons = {
        l.playerAudioAndSubtitles: 'tracks',
        l.playerNextInQueue: 'next',
        l.watchPartyWatchTogether: 'together',
      };
      for (final MapEntry(key: label, value: call) in buttons.entries) {
        await tester.tap(find.widgetWithText(WfButton, label));
        expect(calls.last, call, reason: label);
      }
      final menu = {
        l.partyChatOpen: 'chat',
        l.partyReactionsOpen: 'reactions',
        l.partyQueueOpen: 'queue',
        l.playerPreviousInQueue: 'previous',
        l.playerFullscreen: 'fullscreen',
        l.playerMute: 'mute',
      };
      for (final MapEntry(key: label, value: call) in menu.entries) {
        await tester.tap(find.widgetWithText(WfButton, l.playerMore));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(calls.last, call, reason: label);
      }
      await tester.tap(find.byTooltip(l.playerBackToDetail));
      expect(calls.last, 'back');
    });

    testWidgets('telefono: nessun overflow col testo a 1,3 ($name)', (
      tester,
    ) async {
      await pumpOverlay(tester, size, textScale: 1.3);
      expect(tester.takeException(), isNull);
      for (final element in find.byType(WfButton).evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(Offset.zero & size, _contains(rect));
      }
    });
  }

  testWidgets('telefono: titolo Bebas, trio 52/68, quattro pulsanti con la '
      'parola', (tester) async {
    await pumpOverlay(tester, const Size(390, 780), party: false);
    expect(tester.takeException(), isNull);
    expect(
        tester.widget<Text>(find.text(cardTitle(episode))).style?.fontFamily,
        WfText.display(26).fontFamily);
    expect(tester.getSize(find.byTooltip(l.playerPause)).width, 68);
    expect(tester.getSize(find.byTooltip(l.playerRewind)).width, 52);
    for (final label in [
      l.playerAudioAndSubtitles,
      l.playerNextEpisode,
      l.watchPartyWatchTogether,
      l.playerMore,
    ]) {
      final button = find.widgetWithText(WfButton, label);
      expect(button, findsOneWidget, reason: label);
      // Alto 44; una parola lunga va a capo (il font dei test è largo).
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44),
          reason: label);
    }
    // Due colonne, "Altro" per ultimo.
    final tracks = tester
        .getRect(find.widgetWithText(WfButton, l.playerAudioAndSubtitles));
    final more = tester.getRect(find.widgetWithText(WfButton, l.playerMore));
    expect(more.left, greaterThan(tracks.right));
    expect(more.top, greaterThan(tracks.bottom));
    expect(tester.getSize(find.byType(SeekBar)).height, 44);
    expect(find.byKey(const Key('volume-slider')), findsNothing);
    expect(find.byTooltip(l.playerMute), findsNothing, reason: 'è in Altro');
  });

  testWidgets('telefono: Altro tiene il resto, Velocità fuori dal party', (
    tester,
  ) async {
    await pumpOverlay(tester, const Size(390, 780));
    await tester.tap(find.widgetWithText(WfButton, l.playerMore));
    await tester.pumpAndSettle();
    for (final label in [
      l.partyChatOpen,
      l.partyReactionsOpen,
      l.partyQueueOpen,
      l.playerPreviousInQueue,
      l.playerFullscreen,
      l.playerMute,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text(l.playerSpeed), findsNothing, reason: 'nel party 1×');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final rates = <double>[];
    await pumpOverlay(tester, const Size(390, 780),
        party: false, onRate: rates.add);
    await tester.tap(find.widgetWithText(WfButton, l.playerMore));
    await tester.pumpAndSettle();
    expect(find.text(l.partyChatOpen), findsNothing);
    expect(find.text(l.playerPreviousEpisode), findsOneWidget);
    await tester.tap(find.text(l.playerSpeed));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1,5×'));
    await tester.pumpAndSettle();
    expect(rates, [1.5]);
  });

  testWidgets('stretto col mouse: niente cursore del volume, senza overflow', (
    tester,
  ) async {
    for (final size in phoneSizes) {
      await pumpOverlay(tester, size, touch: false);
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.byKey(const Key('volume-slider')), findsNothing);
      expect(
          tester.getSize(find.byType(SeekBar)).height, SeekBar.defaultHeight);
    }
  });

  testWidgets('stretto: la chat in Altro porta il puntino su Altro', (
    tester,
  ) async {
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

  testWidgets('largo (1440×900): niente Altro né play al centro', (
    tester,
  ) async {
    await pumpOverlay(tester, const Size(1440, 900));
    expect(find.text(l.playerMore), findsNothing);
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
      const Rect.fromLTWH(1440 - 380, 0, 380, 900),
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
          expect(find.text('Prossimo episodio'), findsOneWidget);
          expect(tester.takeException(), isNull);

          final film = tester.getRect(find.byKey(const Key('film')));
          final eyebrow = tester.getRect(find.text('Prossimo episodio'));
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
        Scaffold(body: PauseScreen(
            item: episode,
            visible: true,
            engine: FakeVideoEngine(),
            onResume: () {})),
        surfaceSize: size,
        touch: true,
      );
      await tester.pumpAndSettle();
      expect(find.text(l.playerWatching), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Testo ridimensionato: margine stretto, titolo su una riga.
      expect(
        tester.getTopLeft(find.text(l.playerWatching)).dx,
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
                label: 'Prossimo episodio',
                countdown: false,
                paused: false,
                onPlay: () {},
                onWatchCredits: () {},
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

  // La Fire Stick è a 960×540: stretta, ma non è un telefono (spec §3.5).
  const tvSize = Size(960, 540);

  testWidgets('TV: il pannello Audio e sottotitoli è laterale', (tester) async {
    await pumpApp(
      tester,
      const PlayerSidePanelHost(
        open: true,
        panel: ColoredBox(key: Key('panel'), color: Colors.red),
      ),
      surfaceSize: tvSize,
      tv: true,
    );
    expect(
      tester.getRect(find.byKey(const Key('panel'))),
      const Rect.fromLTWH(960 - 380, 0, 380, 540),
    );
  });

  testWidgets('stretto fuori dalla TV: il pannello è un foglio dal basso',
      (tester) async {
    await pumpApp(
      tester,
      const PlayerSidePanelHost(
        open: true,
        panel: ColoredBox(key: Key('panel'), color: Colors.red),
      ),
      surfaceSize: const Size(390, 780),
      touch: true,
    );
    final sheet = tester.getRect(find.byKey(const Key('panel-sheet')));
    expect(sheet.height,
        closeTo(780 * PlayerSidePanelHost.compactHeightFraction, 1));
    final panel = tester.getRect(find.byKey(const Key('panel')));
    expect(panel.width, 390);
    expect(panel.bottom, 780);
    // Il pannello sta sotto la maniglia.
    expect(panel.top,
        greaterThan(tester.getRect(find.byKey(const Key('panel-sheet-handle'))).bottom));
  });

  testWidgets("TV: il post-play mostra l'immagine dell'episodio, senza trama",
      (tester) async {
    await pumpApp(
      tester,
      Scaffold(
        body: PostPlayLayer(
          episode: episode,
          countdown: false,
          paused: false,
          showImage: true,
          onPlay: () {},
          onWatchCredits: () {},
        ),
      ),
      surfaceSize: tvSize,
      tv: true,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('post-play-image')), findsOneWidget);
    expect(find.text(episode.overview!), findsNothing);
    final play = tester.getRect(find.byType(PlayNowButton));
    expect(Offset.zero & tvSize, _contains(play));
  });

  testWidgets('TV: la pausa usa le misure del desktop', (tester) async {
    await pumpApp(
      tester,
      Scaffold(body: PauseScreen(
            item: episode,
            visible: true,
            engine: FakeVideoEngine(),
            onResume: () {})),
      surfaceSize: tvSize,
      tv: true,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text(l.playerWatching)).dx,
      PauseScreen.textInset,
    );
  });
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

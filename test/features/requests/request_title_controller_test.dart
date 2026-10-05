import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/requests/requests_api.dart';
import 'package:wonderflix/core/requests/requests_models.dart';
import 'package:wonderflix/features/requests/request_title_controller.dart';

import '../../support/requests_fakes.dart';

void main() {
  late FakeRequestsApi api;
  const movieKey = (type: RequestMediaType.movie, tmdbId: 693134, language: 'it');
  const seriesKey = (type: RequestMediaType.tv, tmdbId: 90228, language: 'it');

  ProviderContainer makeContainer() {
    final container = ProviderContainer.test(
        overrides: requestsTestOverrides(api), retry: (_, _) => null);
    container.listen(requestTitleControllerProvider(movieKey), (_, _) {});
    container.listen(requestTitleControllerProvider(seriesKey), (_, _) {});
    return container;
  }

  setUp(() {
    api = FakeRequestsApi()
      ..titles[693134] = testDetails()
      ..titles[90228] = testDetails(
        tmdbId: 90228,
        title: 'Dune: Prophecy',
        type: RequestMediaType.tv,
        seasons: const [
          SeasonInfo(seasonNumber: 1, episodeCount: 6, status: TitleStatus.available),
          SeasonInfo(seasonNumber: 2, episodeCount: 8),
          SeasonInfo(seasonNumber: 3, episodeCount: 8),
        ],
      );
  });

  test('carica la scheda e sceglie le stagioni che si possono chiedere', () async {
    final container = makeContainer();
    await pumpEventQueue();

    final state = container.read(requestTitleControllerProvider(seriesKey));
    expect(state.details!.title, 'Dune: Prophecy');
    expect(state.selected, {2, 3});
    expect(api.calls, contains('title:tv:90228'));
  });

  test('caselle: solo le stagioni da chiedere, e "Tutte"', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(seriesKey).notifier);
    RequestTitleState state() =>
        container.read(requestTitleControllerProvider(seriesKey));

    controller.toggleSeason(1);
    expect(state().selected, {2, 3});
    controller.toggleSeason(2);
    expect(state().selected, {3});
    controller.toggleAll();
    expect(state().selected, {2, 3});
    controller.toggleAll();
    expect(state().selected, isEmpty);
  });

  test('richiesta di una serie con le stagioni scelte, poi ricarica', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(seriesKey).notifier);
    controller.toggleSeason(3);

    final outcome = await controller.submit();
    await pumpEventQueue();

    expect(outcome, RequestOutcome.sent);
    expect(api.created.single.seasons, [2]);
    expect(api.calls.where((c) => c == 'title:tv:90228'), hasLength(2));
    expect(container.read(requestTitleControllerProvider(seriesKey)).sending,
        isFalse);
  });

  test('un film approvato da solo', () async {
    api.createdStatus = RequestStatus.approved;
    final container = makeContainer();
    await pumpEventQueue();

    final outcome = await container
        .read(requestTitleControllerProvider(movieKey).notifier)
        .submit();

    expect(outcome, RequestOutcome.approved);
    expect(api.created.single.seasons, isNull);
  });

  test('gli errori diventano esiti per l\'avviso', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(movieKey).notifier);

    Future<RequestOutcome?> withFailure(RequestsFailure failure) async {
      api.createFailure = failure;
      final outcome = await controller.submit();
      await pumpEventQueue();
      return outcome;
    }

    expect(await withFailure(RequestsFailure.alreadyRequested),
        RequestOutcome.alreadyRequested);
    expect(await withFailure(RequestsFailure.nothingToRequest),
        RequestOutcome.alreadyRequested);
    expect(await withFailure(RequestsFailure.quotaExceeded), RequestOutcome.quota);
    expect(await withFailure(RequestsFailure.accountUnavailable),
        RequestOutcome.account);
    expect(await withFailure(RequestsFailure.blocklisted),
        RequestOutcome.blocklisted);
    expect(await withFailure(RequestsFailure.noPermission),
        RequestOutcome.noPermission);
    expect(await withFailure(RequestsFailure.seerrUnavailable),
        RequestOutcome.failed);
  });

  test('niente da mandare: nessuna richiesta', () async {
    api.titles[693134] = testDetails(status: TitleStatus.pending);
    final container = makeContainer();
    await pumpEventQueue();
    final series =
        container.read(requestTitleControllerProvider(seriesKey).notifier);
    series.toggleAll();

    expect(await series.submit(), isNull);
    expect(
        await container
            .read(requestTitleControllerProvider(movieKey).notifier)
            .submit(),
        isNull);
    expect(api.created, isEmpty);
  });

  test('un secondo clic durante l\'invio non manda niente', () async {
    final gate = api.createGate = Completer<void>();
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(movieKey).notifier);

    final first = controller.submit();
    expect(container.read(requestTitleControllerProvider(movieKey)).sending,
        isTrue);
    expect(await controller.submit(), isNull);
    gate.complete();

    expect(await first, RequestOutcome.sent);
    expect(api.created, hasLength(1));
  });

  test('Richiedi resta bloccato finché la ricarica dopo la richiesta non finisce',
      () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(movieKey).notifier);
    RequestTitleState state() =>
        container.read(requestTitleControllerProvider(movieKey));
    final reload = api.titleGate = Completer<void>();

    final first = controller.submit();
    await pumpEventQueue();
    // La richiesta è partita e la ricarica è in attesa.
    expect(api.created, hasLength(1));
    expect(api.calls.where((c) => c == 'title:movie:693134'), hasLength(2));
    expect(state().sending, isTrue);
    expect(await controller.submit(), isNull);
    expect(api.created, hasLength(1));

    reload.complete();
    expect(await first, RequestOutcome.sent);
    expect(state().sending, isFalse);
  });

  test('una ricarica che finisce durante un invio tiene il blocco', () async {
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(movieKey).notifier);
    RequestTitleState state() =>
        container.read(requestTitleControllerProvider(movieKey));
    final gate = api.createGate = Completer<void>();

    final first = controller.submit();
    expect(state().sending, isTrue);
    await controller.load();
    expect(state().sending, isTrue);
    expect(await controller.submit(), isNull);

    gate.complete();
    expect(await first, RequestOutcome.sent);
    expect(state().sending, isFalse);
    expect(api.created, hasLength(1));
  });

  test('una pagina chiusa prima del primo caricamento non fa niente', () async {
    final container = ProviderContainer(
        overrides: requestsTestOverrides(api), retry: (_, _) => null);
    container.read(requestTitleControllerProvider(movieKey));
    container.dispose();

    await pumpEventQueue();

    expect(api.calls, isNot(contains('title:movie:693134')));
  });

  test('errore al primo caricamento; una ricarica fallita tiene la scheda',
      () async {
    api.failure = RequestsFailure.seerrUnavailable;
    final container = makeContainer();
    await pumpEventQueue();
    final controller =
        container.read(requestTitleControllerProvider(movieKey).notifier);
    expect(container.read(requestTitleControllerProvider(movieKey)).error,
        isA<RequestsException>());

    api.failure = null;
    await controller.load();
    expect(container.read(requestTitleControllerProvider(movieKey)).details,
        isNotNull);

    api.failure = RequestsFailure.network;
    await controller.load();
    final state = container.read(requestTitleControllerProvider(movieKey));
    expect(state.details, isNotNull);
    expect(state.error, isNull);
  });
}

import 'package:wonderflix/core/trailers/trailers_api.dart';

/// Plugin finto: `start` risponde [startResult], ogni `status` il prossimo
/// di [statuses] (l'ultimo si ripete).
class FakeTrailersApi implements TrailersApi {
  TrailerStatus startResult = const TrailerStatus('k1', TrailerState.ready);
  List<TrailerStatus> statuses = const [];
  int statusCalls = 0;

  /// Risposta di `Info`: `false` come un plugin vecchio (404).
  bool availableResult = true;
  final List<TrailerSubject> availableCalls = [];

  @override
  Future<bool> available(TrailerSubject s) async {
    availableCalls.add(s);
    return availableResult;
  }

  @override
  Future<TrailerStatus> start(TrailerSubject s) async => startResult;

  @override
  Future<TrailerStatus> status(String key) async {
    final i = statusCalls++;
    return statuses[i < statuses.length ? i : statuses.length - 1];
  }

  @override
  String streamUrl(String key) => 'https://media.example.com/$key/Stream';
}

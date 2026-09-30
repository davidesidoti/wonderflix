import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/syncplay/start_lag.dart';

void main() {
  const ms = Duration(milliseconds: 1);

  test('parte da zero e si corregge di metà di ogni misura', () {
    final lag = StartLag();
    expect(lag.value, Duration.zero);
    lag.record(ms * 400);
    expect(lag.value, ms * 200);
    lag.record(ms * 200);
    expect(lag.value, ms * 300);
    lag.record(ms * -100);
    expect(lag.value, ms * 250);
  });

  test('resta tra 0 e 1 s', () {
    final lag = StartLag();
    lag.record(ms * -500);
    expect(lag.value, Duration.zero);
    lag.record(const Duration(seconds: 5));
    expect(lag.value, StartLag.max);
    expect(StartLag.max, const Duration(seconds: 1));
  });
}

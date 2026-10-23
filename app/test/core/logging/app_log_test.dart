import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wonderflix/core/logging/app_log.dart';
import 'package:wonderflix/core/logging/rotating_file_sink.dart';

void main() {
  test('formato: data, livello, nome, messaggio, errore', () {
    final text = formatLogRecord(
        LogRecord(Level.WARNING, 'ciao', 'player', StateError('boom')));
    expect(
        text,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} '
            r'WARNING \[player\] ciao\n  Bad state: boom$')));
  });

  test('scrive nel file senza segreti', () {
    final temp = Directory.systemTemp.createTempSync('wf_applog_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final log = AppLog(sink: RotatingFileSink(temp));
    log.add(LogRecord(Level.INFO, 'header Token="segreto"', 'http'));
    final written = File('${temp.path}${Platform.pathSeparator}wonderflix.log')
        .readAsStringSync();
    expect(written, contains('Token="***"'));
    expect(written, isNot(contains('segreto')));
    expect(written, endsWith('\n'));
  });

  test('console del browser: da INFO in su, senza segreti', () {
    final lines = <(Level, String)>[];
    final log = AppLog(console: (level, text) => lines.add((level, text)));
    log.add(LogRecord(Level.FINE, 'dettaglio', 'a'));
    log.add(LogRecord(Level.INFO, 'header Token="segreto"', 'http'));
    log.add(LogRecord(Level.SEVERE, 'rotto', 'a'));
    expect(lines.map((line) => line.$1), [Level.INFO, Level.SEVERE]);
    expect(lines.first.$2, contains('Token="***"'));
    expect(lines.first.$2, isNot(contains('segreto')));
  });

  test('ultimi errori: solo avvisi ed errori, al massimo maxRecentErrors', () {
    final log = AppLog(maxRecentErrors: 2);
    log.add(LogRecord(Level.INFO, 'info', 'a'));
    log.add(LogRecord(Level.WARNING, 'primo', 'a'));
    log.add(LogRecord(Level.SEVERE, 'secondo', 'a'));
    log.add(LogRecord(Level.WARNING, 'terzo', 'a'));
    expect(log.recentErrors, hasLength(2));
    expect(log.recentErrors.first, contains('secondo'));
    expect(log.recentErrors.last, contains('terzo'));
  });

  test('attach riceve i messaggi di tutti i Logger', () async {
    final log = AppLog()..attach();
    addTearDown(log.detach);
    Logger('discord').severe('non collegato');
    await Future<void>.delayed(Duration.zero);
    expect(log.recentErrors.single, contains('[discord] non collegato'));
  });
}

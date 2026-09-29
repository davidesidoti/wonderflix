import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'redact.dart';
import 'rotating_file_sink.dart';

/// Registro dell'app: riceve i messaggi di tutti i `Logger`, li scrive nel
/// file a rotazione (senza segreti) e tiene in memoria gli ultimi avvisi ed
/// errori per la diagnostica.
class AppLog {
  AppLog({this.sink, this.echo = false, this.maxRecentErrors = 50});

  final RotatingFileSink? sink;

  /// Ripete i messaggi nella console (in debug).
  final bool echo;
  final int maxRecentErrors;

  final _recentErrors = ListQueue<String>();
  StreamSubscription<LogRecord>? _subscription;

  /// Ultimi avvisi ed errori, dal più vecchio, già senza segreti.
  List<String> get recentErrors => List.unmodifiable(_recentErrors);

  /// Inizia ad ascoltare `Logger.root` (tutti i livelli).
  void attach() {
    Logger.root.level = Level.ALL;
    _subscription ??= Logger.root.onRecord.listen(add);
  }

  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void add(LogRecord record) {
    final text = redactSecrets(formatLogRecord(record));
    sink?.write('$text\n');
    if (echo) debugPrint(text);
    if (record.level >= Level.WARNING) {
      _recentErrors.addLast(text);
      while (_recentErrors.length > maxRecentErrors) {
        _recentErrors.removeFirst();
      }
    }
  }
}

/// `2026-09-29 21:15:03.042 WARNING [player] messaggio`, con errore e stack
/// trace sulle righe seguenti.
String formatLogRecord(LogRecord record) {
  final t = record.time;
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
  final buffer = StringBuffer(
      '$time ${record.level.name} [${record.loggerName}] ${record.message}');
  if (record.error != null) buffer.write('\n  ${record.error}');
  if (record.stackTrace != null) buffer.write('\n${record.stackTrace}');
  return buffer.toString();
}

/// `%LocalAppData%\WonderFlix\logs` (la cartella temporanea, se la variabile
/// manca).
Directory logsDirectory() {
  final base = Platform.environment['LOCALAPPDATA'];
  final root = base == null || base.isEmpty ? Directory.systemTemp.path : base;
  return Directory('$root\\WonderFlix\\logs');
}

/// Sovrascritto in `main()` con il registro collegato al file. Di default
/// (test) tiene solo gli errori in memoria.
final appLogProvider = Provider<AppLog>((ref) => AppLog());

final logsDirectoryProvider = Provider<Directory>((ref) => logsDirectory());

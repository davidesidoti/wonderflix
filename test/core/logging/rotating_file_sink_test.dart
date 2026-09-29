import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/logging/rotating_file_sink.dart';

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('wf_logs_');
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  String read(String name) =>
      File('${temp.path}${Platform.pathSeparator}$name').readAsStringSync();
  bool exists(String name) =>
      File('${temp.path}${Platform.pathSeparator}$name').existsSync();

  test('crea la cartella e aggiunge in coda', () {
    final dir = Directory('${temp.path}${Platform.pathSeparator}logs');
    final sink = RotatingFileSink(dir);
    sink.write('uno\n');
    sink.write('due\n');
    expect(sink.current.readAsStringSync(), 'uno\ndue\n');
    expect(sink.current.path, endsWith('wonderflix.log'));
  });

  test('ruota oltre la dimensione massima e tiene al massimo maxFiles file',
      () {
    final sink = RotatingFileSink(temp, maxBytes: 10, maxFiles: 3);
    sink.write('aaaaaaaa\n');
    sink.write('bbbbbbbb\n');
    sink.write('cccccccc\n');
    sink.write('dddddddd\n');
    expect(read('wonderflix.log'), 'dddddddd\n');
    expect(read('wonderflix.1.log'), 'cccccccc\n');
    expect(read('wonderflix.2.log'), 'bbbbbbbb\n');
    expect(exists('wonderflix.3.log'), isFalse);
  });

  test('una riga più lunga del massimo si scrive comunque', () {
    final sink = RotatingFileSink(temp, maxBytes: 4);
    sink.write('riga lunga\n');
    expect(read('wonderflix.log'), 'riga lunga\n');
  });

  test('non lancia se la cartella non si può creare', () {
    final blocker = File('${temp.path}${Platform.pathSeparator}blocco')
      ..writeAsStringSync('x');
    final sink = RotatingFileSink(Directory(blocker.path));
    expect(() => sink.write('ciao\n'), returnsNormally);
  });
}

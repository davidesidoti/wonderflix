import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/jellyfin/api_exception.dart';
import 'package:wonderflix/core/jellyfin/json_fields.dart';

void main() {
  final json = <String, dynamic>{
    'text': 'ciao',
    'empty': '',
    'int': 3,
    'double': 2.6,
    'date': '2026-10-06T03:39:07.1141718Z',
    'ticks': 7540000000,
    'map': {'a': 1},
    'list': ['x', '', 4, 'y'],
    'csv': 'a, b,,c',
  };

  test('campi semplici: tipo sbagliato o mancante → null', () {
    expect(jsonString(json, 'text'), 'ciao');
    expect(jsonString(json, 'empty'), isNull);
    expect(jsonString(json, 'int'), isNull);
    expect(jsonInt(json, 'int'), 3);
    expect(jsonInt(json, 'double'), 3);
    expect(jsonInt(json, 'text'), isNull);
    expect(jsonDouble(json, 'int'), 3.0);
    expect(jsonDouble(json, 'double'), 2.6);
    expect(jsonDouble(json, 'missing'), isNull);
    expect(jsonDate(json, 'date'), DateTime.parse('2026-10-06T03:39:07.114171Z'));
    expect(jsonDate(json, 'text'), isNull);
    expect(jsonTicks(json, 'ticks'), const Duration(minutes: 12, seconds: 34));
    expect(jsonMap(json['map']), {'a': 1});
    expect(jsonMap(json['list']), isNull);
    expect(jsonStrings(json['list']), ['x', 'y']);
    expect(jsonStrings(json['csv']), ['a', 'b', 'c']);
    expect(jsonStrings(json['int']), isEmpty);
  });

  test('elenchi: voci scartate saltate, corpo sbagliato → errore', () {
    String? name(Map<String, dynamic> item) => jsonString(item, 'Name');
    expect(
        jsonList([
          {'Name': 'a'},
          {'Altro': 1},
          'no',
          {'Name': 'b'},
        ], name),
        ['a', 'b']);
    expect(() => jsonList({'Items': <Object>[]}, name),
        throwsA(isA<ServerErrorException>()));
  });

  test('id vuoti di Jellyfin', () {
    expect(isEmptyJellyfinId('00000000000000000000000000000000'), isTrue);
    expect(isEmptyJellyfinId('00000000-0000-0000-0000-000000000000'), isTrue);
    expect(isEmptyJellyfinId('ab8240c5fc1649e186f662fa00ca0fb0'), isFalse);
  });
}

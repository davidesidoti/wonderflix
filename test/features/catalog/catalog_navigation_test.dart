import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/features/catalog/catalog_navigation.dart';

void main() {
  test('la vista dall\'indirizzo: le saghe solo con view=sagas', () {
    expect(CatalogView.parse('sagas'), CatalogView.sagas);
    expect(CatalogView.parse('titles'), CatalogView.titles);
    expect(CatalogView.parse(null), CatalogView.titles);
    expect(CatalogView.parse('altro'), CatalogView.titles);
  });
}

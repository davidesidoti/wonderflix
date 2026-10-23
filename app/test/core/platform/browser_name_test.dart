import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/core/platform/browser_name.dart';

void main() {
  const chrome =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36';

  test('riconosce il browser dallo user agent', () {
    expect(describeBrowser('$chrome Edg/141.0.0.0'), 'Edge');
    expect(describeBrowser(chrome), 'Chrome');
    expect(
      describeBrowser(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:144.0) '
        'Gecko/20100101 Firefox/144.0',
      ),
      'Firefox',
    );
    expect(
      describeBrowser(
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 '
        'Safari/605.1.15',
      ),
      'Safari',
    );
    expect(describeBrowser(''), 'Browser');
  });
}

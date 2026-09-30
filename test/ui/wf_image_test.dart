import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wonderflix/app/theme.dart';
import 'package:wonderflix/ui/wf_image.dart';

const _hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

void main() {
  testWidgets('segnaposto: grigio del tema mentre decodifica, mai azzurro',
      (tester) async {
    await tester.pumpWidget(const ImagePlaceholder(blurHash: _hash));
    expect(tester.widget<BlurHash>(find.byType(BlurHash)).color,
        WfColors.surfaceHigh);
  });

  testWidgets('dentro TransparentPlaceholders il segnaposto è trasparente',
      (tester) async {
    await tester.pumpWidget(const TransparentPlaceholders(
      child: Column(children: [
        Expanded(child: ImagePlaceholder(blurHash: _hash)),
        Expanded(child: ImagePlaceholder(icon: Icons.movie)),
      ]),
    ));
    expect(find.byType(BlurHash), findsNothing);
    expect(find.byType(ColoredBox), findsNothing);
    expect(find.byType(Icon), findsNothing);
  });
}

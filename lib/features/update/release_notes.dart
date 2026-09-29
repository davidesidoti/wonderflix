import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Note di rilascio in markdown. I link si aprono nel browser.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) => MarkdownBody(
        data: markdown,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
        onTapLink: (text, href, title) {
          final uri = href == null ? null : Uri.tryParse(href);
          if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
            unawaited(launchUrl(uri));
          }
        },
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell_panels.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../requests/request_labels.dart';

/// Il titolo di una voce delle richieste, con le stagioni se ci sono:
/// "Brothers (2026), stagioni 1–2". Senza titolo da Seerr, "Titolo non
/// disponibile".
String inboxRequestTitle(AppLocalizations l, String title, List<int> seasons) {
  final name = title.isEmpty ? l.requestsUnknownTitle : title;
  return seasons.isEmpty
      ? name
      : l.inboxRequestTitleSeasons(name, seasons.length, formatSeasonList(seasons));
}

/// L'icona tonda delle voci delle richieste (spec I §9.6).
class InboxRequestIcon extends StatelessWidget {
  const InboxRequestIcon({super.key, required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
            color: WfColors.surfaceHigh, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: WfColors.gold),
      );
}

/// Il testo di una voce delle richieste: il clic chiude il pannello e
/// poi [onOpen] apre la scheda o la pagina Richieste.
class InboxRequestContent extends ConsumerWidget {
  const InboxRequestContent({
    super.key,
    required this.text,
    required this.time,
    required this.onOpen,
  });

  final String text;
  final String time;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: () {
          ref.read(shellPanelProvider.notifier).close();
          onOpen();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  style: const TextStyle(
                      color: WfColors.cream, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(time,
                  style: const TextStyle(color: WfColors.creamMuted, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

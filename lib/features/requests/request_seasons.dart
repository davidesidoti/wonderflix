import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import 'request_title_controller.dart';
import 'requests_providers.dart';
import 'season_picker.dart';

/// La serie della libreria ha stagioni che si possono chiedere (spec I
/// §9.3). La scheda di Seerr si carica in silenzio, e solo con la funzione
/// e se l'utente può chiedere; un errore vale "no".
final seasonsToRequestProvider =
    Provider.autoDispose.family<bool, RequestTitleKey>((ref, key) {
  if (!ref.watch(requestsAvailableProvider)) return false;
  if (!(ref.watch(requestsMeProvider).value?.canRequest ?? false)) return false;
  final details = ref.watch(requestTitleControllerProvider(key)).details;
  return details != null && details.requestableSeasons.isNotEmpty;
});

/// Apre "Richiedi stagioni" (spec I §9.3) e mostra l'esito come avviso.
Future<void> showRequestSeasonsDialog(
    BuildContext context, RequestTitleKey key, String title) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await showWfDialog<RequestOutcome>(context,
      semanticLabel: l.requestsMoreSeasons,
      builder: (_) => RequestSeasonsDialog(titleKey: key, title: title));
  if (outcome != null) {
    messenger.showSnackBar(SnackBar(content: Text(requestOutcomeText(l, outcome))));
  }
}

/// Le stagioni con le caselle, Annulla e Richiedi: lo stesso controller
/// della scheda da richiedere (decisione 7 del piano 15b).
class RequestSeasonsDialog extends ConsumerWidget {
  const RequestSeasonsDialog({super.key, required this.titleKey, required this.title});

  /// Altezza massima dell'elenco delle stagioni; oltre scorre.
  static const _seasonsMaxHeight = 360.0;

  /// Altezza del segnaposto mentre la scheda di Seerr si carica.
  static const _loadingHeight = 120.0;

  final RequestTitleKey titleKey;

  /// Il nome della serie nella libreria.
  final String title;

  Future<void> _submit(BuildContext context, RequestTitleController controller) async {
    final outcome = await controller.submit();
    if (context.mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final provider = requestTitleControllerProvider(titleKey);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final details = state.details;
    if (details == null) {
      return const SizedBox(height: _loadingHeight, child: LoadingView());
    }
    final chosen = state.selected.length;
    final all = chosen == details.requestableSeasons.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.requestsMoreSeasons,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: WfColors.creamMuted)),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _seasonsMaxHeight),
          child: SingleChildScrollView(
            child: SeasonPicker(
              seasons: details.seasons,
              selected: state.selected,
              enabled: !state.sending,
              onToggle: controller.toggleSeason,
              onToggleAll: controller.toggleAll,
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Un `Wrap` e non un `Row`: "Richiedi 12 stagioni" è lungo, e con un
        // carattere grande i pulsanti vanno a capo invece di uscire dalla
        // finestra.
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.requestsCancel),
              ),
              WfButton.primary(
                // Le stagioni da chiedere sono già tutte scelte: Invio chiede.
                autofocus: true,
                label: all ? l.requestsRequest : l.requestsRequestSeasons(chosen),
                icon: LucideIcons.plus,
                onPressed: state.sending || chosen == 0
                    ? null
                    : () => unawaited(_submit(context, controller)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

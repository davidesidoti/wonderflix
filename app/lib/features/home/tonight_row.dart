import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/card_preview.dart';
import '../../ui/form_factor.dart';
import '../../ui/media_row.dart';
import '../../ui/ticket_card.dart';
import '../library/user_data.dart';
import '../match/match_entry.dart';
import '../tonight/tonight_dialog.dart';
import 'home_rows_logic.dart';
import 'home_sections.dart';
import 'next_up_hidden.dart';
import 'resume_removal.dart';

/// Quanto il biglietto sale col mouse sopra: la riga gli lascia quest'aria.
const _ticketLift = 3.0;

/// I biglietti di Stasera come li mostra la Home: senza i titoli tolti da
/// Continua a guardare (punto di ripresa tornato a 0) e senza le serie tolte
/// da Prossimi episodi, ognuna delle due parti al massimo [homeRowLimit].
List<TonightTicket> watchTonightTickets(
  WidgetRef ref, {
  required List<JellyfinItem> resume,
  required List<JellyfinItem> nextUp,
}) {
  // Solo le modifiche: Jellyfin manda qui titoli con un punto di ripresa.
  final changed = ref.watch(userDataOverridesProvider);
  final hidden = ref.watch(nextUpHiddenProvider).value ?? const {};
  return tonightTickets(
    resume: [
      for (final item in resume)
        if (changed[item.id]?.playbackPositionTicks != 0) item,
    ].take(homeRowLimit).toList(),
    nextUp: [
      for (final episode in nextUp)
        if (!hiddenFromNextUp(hidden, episode)) episode,
    ].take(homeRowLimit).toList(),
  );
}

/// "Stasera" (spec §6): Continua a guardare e Prossimi episodi in una riga
/// di biglietti, con Match e "Cosa guardo stasera?" nell'intestazione (non
/// in TV, dove "Stasera?" sta nel carosello).
class TonightRow extends ConsumerWidget {
  const TonightRow({
    super.key,
    required this.resume,
    required this.nextUp,
    required this.onTonight,
    required this.onMatch,
    required this.animateEntrance,
    this.autofocusFirst = false,
  });

  final List<JellyfinItem> resume;
  final List<JellyfinItem> nextUp;
  final VoidCallback onTonight;
  final VoidCallback onMatch;

  /// Vedi `MediaRow.animateEntrance`.
  final bool animateEntrance;

  /// Il primo biglietto prende il focus (TV).
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final tickets = watchTonightTickets(ref, resume: resume, nextUp: nextUp);
    if (tickets.isEmpty) return const SizedBox.shrink();
    return MediaRow(
      title: l.homeTonight,
      count: l.homeTonightCount(tickets.length),
      titleSize: 26,
      topSpacing: 28,
      trailing: form.tv
          ? null
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!form.compact)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      l.homeUndecided,
                      style: const TextStyle(
                        color: WfColors.creamMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                MatchButton(onPressed: onMatch, small: true),
                TonightButton(onPressed: onTonight, small: true),
              ],
            ),
      height: ticketSize(context).height + _ticketLift,
      itemCount: tickets.length,
      animateEntrance: animateEntrance,
      itemBuilder: (context, i) {
        final ticket = tickets[i];
        final item = ticket.item;
        // La chiave dice a `MediaRow` (TV) quando al posto c'è un altro biglietto.
        return Padding(
          key: ValueKey('tonight-${item.id}'),
          padding: const EdgeInsets.only(top: _ticketLift),
          child: TicketCard(
            key: ValueKey(
              ticket.resumed ? 'resume-${item.id}' : 'next-up-${item.id}',
            ),
            item: item,
            resumed: ticket.resumed,
            heroSource: 'home.tonight.$i',
            autofocus: autofocusFirst && i == 0,
            previewExtra: CardPreviewExtra(
              dismissTooltip: ticket.resumed ? l.resumeHide : l.nextUpHide,
              onDismiss: () => unawaited(
                ticket.resumed
                    ? removeFromResume(context, ref, item)
                    : hideFromNextUp(context, ref, item),
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/social/match_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/wf_buttons.dart';
import 'match_queue.dart';
import 'match_ticket.dart';

/// Larghezza della colonna dei match sul desktop.
const matchColumnWidth = 360.0;

/// Larghezza dei biglietti nella fila dello stretto.
const _stripTicketWidth = 250.0;

const _muted = TextStyle(color: WfColors.creamMuted, fontSize: 12);

/// I match come biglietti (spec §5.5): i match nell'ordine di uscita, sotto i
/// quasi match al 75% con "1 sì su 2". Con [onChoose] (chi ha aperto) un clic
/// sceglie il primo titolo del party: [chosen], altrimenti quello che
/// `matchPartyOrder` mette in testa, ha "Parte per primo"; sotto "Avvia il
/// party con n titoli", spento se [onStartParty] è `null`.
/// Nello stretto i biglietti stanno in una fila orizzontale.
class MatchColumn extends StatelessWidget {
  const MatchColumn({
    super.key,
    required this.state,
    required this.titles,
    this.chosen,
    this.onChoose,
    this.onStartParty,
  });

  final MatchState state;
  final Map<String, JellyfinItem?> titles;
  final String? chosen;
  final ValueChanged<String>? onChoose;
  final VoidCallback? onStartParty;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final compact = FormFactor.of(context).compact;
    final width = compact ? _stripTicketWidth : matchColumnWidth;
    final party = matchPartyOrder(state, first: chosen);
    // Chi non ha aperto non sa quale partirà: nessun "Parte per primo".
    final first = onChoose == null ? null : party.firstOrNull;

    Widget ticket(String id, {String? note}) => MatchTicket(
      key: Key('match-column-$id'),
      id: id,
      item: titles[id],
      chosen: first == id,
      note: note,
      width: width,
      onTap: onChoose == null ? null : () => onChoose!(id),
    );

    Widget list(List<Widget> tickets) => compact
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, t) in tickets.indexed)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                    child: t,
                  ),
              ],
            ),
          )
        : Column(
            children: [
              for (final t in tickets)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: t),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(l.matchLikedByAll, style: WfText.display(26)),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  state.matches.isEmpty
                      ? l.matchNoMatches
                      : l.matchCount(state.matches.length),
                  style: _muted,
                ),
              ),
            ],
          ),
        ),
        if (state.matches.isNotEmpty)
          list([for (final id in state.matches) ticket(id)]),
        if (state.nearMatches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Text(
              l.matchNearMatches,
              style: _muted.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Opacity(
            opacity: 0.75,
            child: list([
              for (final near in state.nearMatches)
                ticket(near.itemId, note: l.matchNearOf(near.yes, near.of)),
            ]),
          ),
        ],
        if (onChoose != null && party.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: compact ? double.infinity : matchColumnWidth,
            height: 44,
            child: WfButton.primary(
              key: const Key('match-start-party'),
              label: l.matchStartPartyWith(party.length),
              icon: LucideIcons.play,
              onPressed: onStartParty,
            ),
          ),
        ],
      ],
    );
  }
}

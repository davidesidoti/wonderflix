import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/syncplay/party_mode.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import '../social/social_providers.dart';
import 'party_mode_labels.dart';
import 'party_mode_preference.dart';
import 'watch_party_actions.dart';
import 'watch_party_session.dart';

/// Larghezza del menu delle modalità: con Inter la spiegazione più lunga
/// (quella del privato, ~295 px) sta su una riga.
const partyModeMenuWidth = 380.0;

/// Altezza di una voce del menu: titolo sopra, spiegazione sotto.
const _itemHeight = 64.0;

/// Spazio sopra e sotto le voci (quello di Material 3, qui esplicito: entra
/// nell'altezza prevista del menu).
const _menuVerticalPadding = 8.0;

/// Altezza prevista del menu, per aprirlo sopra il pulsante quando sotto non
/// ci sta. Con testi più grandi (o una spiegazione su due righe) il menu è
/// un po' più alto e copre appena il bordo del pulsante.
final partyModeMenuHeight =
    PartyMode.values.length * _itemHeight + 2 * _menuVerticalPadding;

/// Menu delle modalità ancorato a [anchor] (spec F §9.1): l'ultima usata ha
/// il bordo oro. Se sotto il pulsante non c'è posto (nel player) si apre
/// sopra. `null` se si chiude senza scegliere.
Future<PartyMode?> showPartyModeMenu(BuildContext anchor,
    {required PartyMode last}) {
  final l = AppLocalizations.of(anchor);
  return showMenu<PartyMode>(
    context: anchor,
    position: menuPositionBelow(anchor, estimatedHeight: partyModeMenuHeight),
    popUpAnimationStyle: wfPopUpAnimation(anchor),
    constraints: const BoxConstraints(
        minWidth: partyModeMenuWidth, maxWidth: partyModeMenuWidth),
    menuPadding: const EdgeInsets.symmetric(vertical: _menuVerticalPadding),
    items: [
      for (final mode in PartyMode.values)
        PopupMenuItem<PartyMode>(
          key: Key('party-mode-${mode.wire}'),
          value: mode,
          height: _itemHeight,
          child: _ModeTile(l: l, mode: mode, selected: mode == last),
        ),
    ],
  );
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.l, required this.mode, required this.selected});

  final AppLocalizations l;
  final PartyMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        key: selected ? const Key('party-mode-selected') : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected ? WfColors.gold : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(partyModeIcon(mode),
                size: 20, color: selected ? WfColors.gold : WfColors.cream),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(partyModeLabel(l, mode),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(partyModeHint(l, mode),
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// "Guarda insieme" (spec F §9.1–9.2). Con la funzione `parties` del plugin
/// e fuori da un gruppo chiede la modalità con un menu ancorato a
/// [menuAnchor] (di default [context]) e la ricorda; dentro un gruppo, senza
/// plugin o finché le sue funzioni non sono note fa come prima. `false` se
/// si annulla o non riesce.
///
/// [onStarting] si chiama quando la richiesta parte davvero (scelta la
/// modalità, o subito senza menu). Il punto di partenza è [startAt], se
/// c'è, letto in quel momento (nel player il video va avanti mentre si
/// sceglie); altrimenti [start].
Future<bool> watchTogether(
  BuildContext context,
  WidgetRef ref,
  JellyfinItem item, {
  Duration start = Duration.zero,
  ValueGetter<Duration>? startAt,
  BuildContext? menuAnchor,
  VoidCallback? onStarting,
}) async {
  PartyMode? mode;
  if (_partiesAvailable(ref) && !ref.read(watchPartySessionProvider).inGroup) {
    mode = await showPartyModeMenu(menuAnchor ?? context,
        last: ref.read(partyModePreferenceProvider));
    if (mode == null || !context.mounted) return false;
    unawaited(ref.read(partyModePreferenceProvider.notifier).set(mode));
  }
  if (!context.mounted) return false;
  onStarting?.call();
  return startWatchParty(context, ref, item,
      start: startAt?.call() ?? start, mode: mode);
}

/// Se le funzioni del plugin non si possono leggere, come senza plugin.
/// Finché non sono note `parties` è `false`.
bool _partiesAvailable(WidgetRef ref) {
  try {
    return ref.read(socialAvailabilityProvider).parties;
  } on Object {
    return false;
  }
}

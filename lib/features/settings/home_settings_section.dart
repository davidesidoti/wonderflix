import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../home/home_layout.dart';
import '../home/home_rows_editing.dart';
import '../home/home_rows_editor.dart';
import '../home/home_user_editor.dart';
import '../requests/requests_providers.dart';
import '../social/social_providers.dart';

/// Il valore di `/settings?section=` che apre la sezione Home (spec M §8.5).
const homeSettingsSection = 'home';

/// Quanto si attenua l'elenco mentre si rilegge: non si può toccare.
const _busyOpacity = 0.5;

/// "Personalizza la Home": Impostazioni, sulla sezione Home.
void openHomeSettings(BuildContext context) =>
    context.go('/settings?section=$homeSettingsSection');

/// Impostazioni → Home (spec M §8.5): le righe accese dall'admin, da
/// spostare e nascondere, salvate da sole; "Ripristina la Home predefinita".
class HomeSettingsSection extends ConsumerWidget {
  const HomeSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final editor = ref.watch(homeUserEditorProvider);
    final features = ref.watch(socialAvailabilityProvider);
    final me = ref.watch(requestsMeProvider);
    const muted = TextStyle(color: WfColors.creamMuted, fontSize: 12.5);
    final value = editor.value;
    // Si rilegge con il vecchio elenco ancora in mano: si vede, ma non è più
    // quello che si può modificare (il controller non salverebbe niente).
    final busy = editor.isLoading;
    final Widget body;
    if (editor.hasError) {
      // Anche una rilettura fallita: lo stato tiene il vecchio elenco, ma il
      // controller non lo modifica più, quindi non lo si mostra come attivo.
      body = Row(
        children: [
          Flexible(child: Text(describeError(l, editor.error!), style: muted)),
          TextButton(
            onPressed: () => ref.invalidate(homeUserEditorProvider),
            child: Text(l.retry),
          ),
        ],
      );
    } else if (value == null) {
      body = const SkeletonBox(width: 320, height: 20);
    } else {
      // Finché `/Me` non risponde, o se non si legge, non si sa se l'account
      // Seerr c'è: "Le mie richieste" non ha un motivo (decisione 14 del
      // piano 19c).
      final seerrAccount =
          me.isLoading || me.hasError || (me.value?.hasAccount ?? false);
      final notifier = ref.read(homeUserEditorProvider.notifier);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
            key: const Key('home-rows-list'),
            ignoring: busy,
            child: Opacity(
              opacity: busy ? _busyOpacity : 1,
              child: HomeRowsEditor(
                entries: [
                  for (final row in value.rows)
                    HomeRowsEditorEntry(
                      kind: row,
                      on: !value.hidden.contains(row),
                      // Finché le funzioni del plugin non sono note nessuna
                      // riga ha un motivo: sarebbero tutti sbagliati.
                      unavailable: features.known
                          ? homeRowGateReason(
                              l,
                              homeRowGate(row, features,
                                  seerrAccount: seerrAccount))
                          : null,
                    ),
                ],
                onMove: notifier.move,
                onToggle: notifier.setVisible,
              ),
            ),
          ),
          if (value.saveFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.homeRowsSaveFailed,
                  key: const Key('home-rows-save-failed'),
                  style: const TextStyle(color: WfColors.error)),
            ),
          const SizedBox(height: 12),
          WfButton.secondary(
            key: const Key('home-rows-reset'),
            label: l.homeRowsReset,
            icon: LucideIcons.rotateCcw,
            onPressed: value.canReset && !busy
                ? () => unawaited(notifier.reset())
                : null,
          ),
          const SizedBox(height: 8),
          Text(l.homeRowsAllPcs, style: muted),
        ],
      );
    }
    // L'`Align` toglie la larghezza fissa che la `Column` delle sezioni (con
    // `stretch`) darebbe a questo blocco: senza, il suo tetto non varrebbe.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: body,
      ),
    );
  }
}

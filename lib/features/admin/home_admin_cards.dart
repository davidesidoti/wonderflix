import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/social/home_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../home/home_layout.dart';
import '../home/home_providers.dart';
import '../home/home_rows_editing.dart';
import '../home/home_rows_editor.dart';
import '../social/social_providers.dart';
import 'admin_action_button.dart';
import 'admin_confirm_dialog.dart';
import 'admin_widgets.dart';

/// La bozza della card "Home per tutti" (spec M §8.6).
@immutable
class AdminHomeState {
  const AdminHomeState(
      {required this.saved, required this.rows, required this.on});

  factory AdminHomeState.fromSaved(List<String>? saved) => AdminHomeState(
      saved: saved, rows: adminEditorRows(saved), on: adminEditorOn(saved));

  /// La Home dell'admin sul server; `null`: mai impostata.
  final List<String>? saved;

  /// Tutte le righe, nell'ordine dell'elenco.
  final List<HomeRowKind> rows;

  /// Le righe accese per tutti.
  final Set<HomeRowKind> on;

  /// Diversa da quella salvata: "Salva" si accende.
  bool get dirty =>
      !listEquals(adminRowsToSave(rows, on), adminRowsEffective(saved));

  /// "Ripristina" serve se la Home è impostata o cambiata.
  bool get canReset => saved != null || dirty;

  AdminHomeState copyWith({List<HomeRowKind>? rows, Set<HomeRowKind>? on}) =>
      AdminHomeState(saved: saved, rows: rows ?? this.rows, on: on ?? this.on);
}

/// Legge la Home dell'admin una volta e tiene la bozza finché non si salva.
/// Non si rilegge da sola come le altre card: cancellerebbe le modifiche
/// (decisione 12 del piano 19c).
class AdminHomeEditor extends AsyncNotifier<AdminHomeState> {
  @override
  Future<AdminHomeState> build() async =>
      AdminHomeState.fromSaved(await ref.watch(homeApiProvider).layout());

  void move(HomeRowKind row, int to) =>
      _edit((state) => state.copyWith(rows: moveRow(state.rows, row, to)));

  void setOn(HomeRowKind row, bool on) => _edit((state) => state.copyWith(
      on: on ? {...state.on, row} : ({...state.on}..remove(row))));

  void _edit(AdminHomeState Function(AdminHomeState) change) {
    final current = state.value;
    if (current != null) state = AsyncData(change(current));
  }

  /// "Salva": le righe accese, nell'ordine dell'elenco. Un errore lo mostra
  /// il pulsante, e la bozza resta.
  Future<void> save() async {
    final current = state.value;
    if (current == null) return;
    _saved(await ref
        .read(homeApiProvider)
        .setLayout(adminRowsToSave(current.rows, current.on)));
  }

  /// "Ripristina la Home predefinita" per tutti: si salva `null`.
  Future<void> reset() async =>
      _saved(await ref.read(homeApiProvider).setLayout(null));

  void _saved(List<String>? saved) {
    if (!ref.mounted) return;
    state = AsyncData(AdminHomeState.fromSaved(saved));
    // Anche la Home dell'admin, tenuta 5 minuti, cambia subito.
    ref.invalidate(homeAdminRowsProvider);
  }
}

final adminHomeEditorProvider =
    AsyncNotifierProvider.autoDispose<AdminHomeEditor, AdminHomeState>(
        AdminHomeEditor.new);

/// "Home per tutti" (spec M §8.6): l'admin accende, spegne e ordina le
/// righe della Home di tutti.
class HomeForEveryoneCard extends ConsumerStatefulWidget {
  const HomeForEveryoneCard({super.key});

  @override
  ConsumerState<HomeForEveryoneCard> createState() =>
      _HomeForEveryoneCardState();
}

class _HomeForEveryoneCardState extends ConsumerState<HomeForEveryoneCard>
    with AutomaticKeepAliveClientMixin {
  /// Scorrendo la scheda la card resta montata: la bozza non si perde.
  @override
  bool get wantKeepAlive => true;

  Future<void> _reset() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showAdminConfirmDialog(
      context,
      title: l.homeRowsReset,
      message: l.adminHomeResetConfirm,
      confirmLabel: l.homeRowsReset,
    );
    if (!confirmed || !mounted) return;
    await ref.read(adminHomeEditorProvider.notifier).reset();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final features = ref.watch(socialAvailabilityProvider);
    return AdminCard(
      title: l.adminHomeTitle,
      icon: LucideIcons.layoutList,
      child: !features.known
          ? const SkeletonBox(width: 240, height: 20)
          : !features.home
              ? Text(l.adminNeedsPlugin170,
                  style: const TextStyle(color: WfColors.creamMuted))
              : _editor(l, features),
    );
  }

  Widget _editor(AppLocalizations l, SocialFeatures features) {
    final data = ref.watch(adminHomeEditorProvider);
    final value = data.value;
    if (value == null) {
      return data.hasError
          ? AdminCardError(
              error: data.error!,
              onRetry: () => ref.invalidate(adminHomeEditorProvider))
          : const SkeletonBox(width: 240, height: 20);
    }
    final editor = ref.read(adminHomeEditorProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeRowsEditor(
          lockUnavailable: false,
          entries: [
            for (final row in value.rows)
              HomeRowsEditorEntry(
                kind: row,
                on: value.on.contains(row),
                // Per tutti contano solo le fonti del plugin, non l'account
                // Seerr di chi guarda (decisione 12 del piano 19c).
                unavailable: homeRowGateReason(
                    l, homeRowGate(row, features, seerrAccount: true)),
              ),
          ],
          onMove: editor.move,
          onToggle: editor.setOn,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AdminActionButton(
              key: const Key('admin-home-save'),
              label: l.adminHomeSave,
              icon: LucideIcons.save,
              onPressed: value.dirty ? editor.save : null,
            ),
            AdminActionButton(
              key: const Key('admin-home-reset'),
              label: l.homeRowsReset,
              icon: LucideIcons.rotateCcw,
              onPressed: value.canReset ? _reset : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// L'esito della prova di un servizio (spec M §8.6, §10).
String arrTestLabel(AppLocalizations l, ArrTestResult result) {
  if (!result.configured) return l.adminArrNotConfigured;
  if (result.ok) return l.adminArrOk(result.version ?? '?');
  return switch (result.error) {
    UpcomingError.notConfigured => l.adminArrNotConfigured,
    UpcomingError.unauthorized => l.adminArrUnauthorized,
    _ => l.adminArrUnreachable,
  };
}

/// "Sonarr e Radarr" (spec M §8.6): configurati o no, e la prova del
/// collegamento con l'esito.
class ArrCard extends ConsumerStatefulWidget {
  const ArrCard({super.key});

  @override
  ConsumerState<ArrCard> createState() => _ArrCardState();
}

class _ArrCardState extends ConsumerState<ArrCard>
    with AutomaticKeepAliveClientMixin {
  /// L'esito dell'ultima prova.
  ArrTestResults? _result;

  /// Con un esito da mostrare la card resta montata scorrendo.
  @override
  bool get wantKeepAlive => _result != null;

  Future<void> _test() async {
    final result = await ref.read(homeApiProvider).testArr();
    if (!mounted) return;
    setState(() => _result = result);
    updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = AppLocalizations.of(context);
    final features = ref.watch(socialAvailabilityProvider);
    final Widget child;
    if (!features.known) {
      child = const SkeletonBox(width: 240, height: 20);
    } else if (!features.home) {
      child = Text(l.adminNeedsPlugin170,
          style: const TextStyle(color: WfColors.creamMuted));
    } else {
      final result = _result;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _service(l, 'Sonarr',
              key: const Key('arr-sonarr'),
              configured: features.upcomingSeries,
              result: result?.sonarr),
          const SizedBox(height: 6),
          _service(l, 'Radarr',
              key: const Key('arr-radarr'),
              configured: features.upcomingMovies,
              result: result?.radarr),
          const SizedBox(height: 12),
          AdminActionButton(
            key: const Key('arr-test'),
            label: l.adminSeerrTest,
            icon: LucideIcons.link,
            onPressed: _test,
          ),
        ],
      );
    }
    return AdminCard(
        title: l.adminArrTitle, icon: LucideIcons.calendarClock, child: child);
  }

  /// Prima della prova si sa solo se è configurato (decisione 13 del piano
  /// 19c); dopo, l'esito.
  Widget _service(AppLocalizations l, String name,
      {required Key key, required bool configured, ArrTestResult? result}) {
    final (text, color) = switch (result) {
      null => configured
          ? ('', WfColors.cream)
          : (l.adminArrNotConfigured, WfColors.creamMuted),
      final tested when tested.ok => (arrTestLabel(l, tested), WfColors.cream),
      final tested when !tested.configured =>
        (arrTestLabel(l, tested), WfColors.creamMuted),
      final tested => (arrTestLabel(l, tested), WfColors.error),
    };
    return Row(
      key: key,
      children: [
        SizedBox(
          width: 80,
          child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ],
    );
  }
}

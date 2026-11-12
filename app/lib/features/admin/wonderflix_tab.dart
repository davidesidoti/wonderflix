import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/social/home_models.dart';
import '../../core/social/plugin_admin_api.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import '../social/social_providers.dart';
import 'admin_action_button.dart';
import 'admin_confirm_dialog.dart';
import 'admin_kit.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';
import 'home_admin_cards.dart';
import 'rating_comments_card.dart';
import 'reports_card.dart';
import 'wonderflix_controllers.dart';
import 'wonderflix_labels.dart';

/// Le integrazioni con la loro spia: cliccandola si apre sotto la fila la card
/// di oggi (Sonarr e Radarr condividono `ArrCard`).
enum Integration { sonarr, radarr, seerr }

/// La scheda WonderFlix (spec J §9.6, spec L §9.6, spec M §8.6): la fila delle
/// spie delle integrazioni, poi annuncio, novità, Home per tutti e il resto
/// in ordine di urgenza. Ogni card ha il suo stato: se una non carica, le
/// altre funzionano. Il recupero della password sta in Utenti: quella scheda
/// c'è proprio con la funzione `account` che il recupero richiede.
class WonderflixTab extends ConsumerStatefulWidget {
  const WonderflixTab({super.key, this.header});

  /// La striscia del server, nel layout stretto: scorre con l'elenco.
  final Widget? header;

  @override
  ConsumerState<WonderflixTab> createState() => _WonderflixTabState();
}

class _WonderflixTabState extends ConsumerState<WonderflixTab> {
  final _scroll = SmoothScrollController();

  /// La spia aperta: una sola alla volta.
  Integration? _open;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // In ordine di urgenza; nel largo vanno alternate sulle due colonne.
    const cards = <Widget>[
      ReportsCard(),
      AnnouncementCard(),
      NewTitlesCard(),
      RatingCommentsCard(),
      HomeForEveryoneCard(),
    ];
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(
          adminSideMargin(context), 0, adminSideMargin(context), 40),
      children: [
        if (widget.header case final header?)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: header),
        AdminTabTitle(title: l.adminTabWonderflix),
        const SizedBox(height: 14),
        IntegrationLamps(
          open: _open,
          onToggle: (i) => setState(() => _open = _open == i ? null : i),
        ),
        const SizedBox(height: 12),
        if (_open case final open?)
          open == Integration.seerr ? const SeerrCard() : const ArrCard(),
        if (FormFactor.of(context).compact)
          const Column(children: cards)
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Column(children: [
                for (var i = 0; i < cards.length; i += 2) cards[i]
              ])),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(children: [
                for (var i = 1; i < cards.length; i += 2) cards[i]
              ])),
            ],
          ),
      ],
    );
  }
}

/// La fila delle spie: Sonarr, Radarr, Seerr. Non configurato: spenta;
/// configurato: accesa; dopo la prova, l'esito (rossa col motivo se fallita).
class IntegrationLamps extends ConsumerWidget {
  const IntegrationLamps(
      {super.key, required this.open, required this.onToggle});

  final Integration? open;
  final void Function(Integration) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final features = ref.watch(socialAvailabilityProvider);
    final arr = ref.watch(arrTestResultProvider);
    final seerr = ref.watch(seerrAdminControllerProvider);
    final seerrTest = ref.watch(seerrTestResultProvider);

    (LampState, String) arrLamp(bool configured, ArrTestResult? tested) =>
        tested == null
            ? configured
                ? (LampState.ok, l.adminArrConfigured)
                : (LampState.off, l.adminArrNotConfigured)
            : (
                !tested.configured
                    ? LampState.off
                    : tested.ok
                        ? LampState.ok
                        : LampState.broken,
                arrTestLabel(l, tested),
              );

    // Plugin più vecchio della 1.4.0: niente card e niente spia.
    final seerrStatus = seerr.value?.status;
    final hasSeerr = seerr.value == null || seerrStatus != null;
    final (LampState, String?) seerrLamp = seerrStatus == null
        ? seerr.error != null
            ? (LampState.broken, l.adminSeerrUnavailable)
            : (LampState.off, null)
        : !seerrStatus.configured
            ? (LampState.off, l.adminArrNotConfigured)
            : seerrTest == null
                ? (LampState.ok, l.adminArrConfigured)
                : (
                    seerrTest.ok ? LampState.ok : LampState.broken,
                    seerrTestLabel(l, seerrTest),
                  );

    final (sonarrState, sonarrText) =
        arrLamp(features.upcomingSeries, arr?.sonarr);
    final (radarrState, radarrText) =
        arrLamp(features.upcomingMovies, arr?.radarr);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: WfColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Wrap(
          children: [
            _lamp(Integration.sonarr, 'Sonarr', sonarrState, sonarrText),
            _lamp(Integration.radarr, 'Radarr', radarrState, radarrText),
            if (hasSeerr)
              _lamp(Integration.seerr, 'Seerr', seerrLamp.$1, seerrLamp.$2),
          ],
        ),
      ),
    );
  }

  Widget _lamp(Integration which, String name, LampState state, String? text) {
    final selected = open == which;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: Key('lamp-${which.name}'),
        borderRadius: BorderRadius.circular(4),
        onTap: () => onToggle(which),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: selected ? WfColors.surfaceHigh : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Lo stato anche a parole, non solo nel colore.
              WfLamp(state: state, label: text == null ? name : '$name: $text'),
              const SizedBox(width: 8),
              ExcludeSemantics(
                child: Text(name,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: state == LampState.off
                            ? WfColors.creamMuted
                            : WfColors.cream)),
              ),
              if (state == LampState.broken && text != null) ...[
                const SizedBox(width: 6),
                // Su un telefono il motivo lungo si accorcia, non sborda.
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: WfColors.error)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// L'annuncio a tutti: testo con il contatore, conferma, esito.
class AnnouncementCard extends ConsumerStatefulWidget {
  const AnnouncementCard({super.key});

  @override
  ConsumerState<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends ConsumerState<AnnouncementCard> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAdminConfirmDialog(
      context,
      title: l.adminAnnouncement,
      message: l.adminAnnouncementConfirm,
      confirmLabel: l.adminSend,
    );
    if (!confirmed || !mounted) return;
    try {
      // Come il plugin: il testo si accorcia ai lati.
      final recipients = await ref
          .read(inboxAdminControllerProvider.notifier)
          .announce(_text.text.trim());
      messenger.showSnackBar(
          SnackBar(content: Text(l.adminAnnouncementSent(recipients))));
      // La scheda può essere cambiata mentre l'annuncio partiva: il campo non
      // c'è più.
      if (mounted) _text.clear();
    } on ServerErrorException catch (error) {
      if (error.statusCode != 400) rethrow;
      // Come `AdminActionButton`: se la scheda non c'è più, l'avviso non ha
      // più senso (comparirebbe su un'altra pagina).
      if (mounted) {
        messenger
            .showSnackBar(SnackBar(content: Text(l.adminAnnouncementInvalid)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Il controller è `autoDispose` e l'annuncio lo usa solo con `read`:
    // senza un ascoltatore potrebbe sparire prima della rilettura (e della
    // rilettura dell'utente dopo un 403) che seguono l'azione. Finora lo
    // teneva vivo la card Novità; così la card regge anche da sola.
    ref.listen(inboxAdminControllerProvider, (_, _) {});
    return AdminCard(
      title: l.adminAnnouncement,
      icon: LucideIcons.megaphone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('announcement-text'),
            controller: _text,
            minLines: 2,
            maxLines: 4,
            maxLength: PluginAdminApi.announcementMaxLength,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _text,
            builder: (context, value, _) => AdminActionButton(
              label: l.adminAnnouncementSend,
              icon: LucideIcons.send,
              onPressed: value.text.trim().isEmpty ? null : _send,
            ),
          ),
        ],
      ),
    );
  }
}

/// Le novità: interruttore, titoli in attesa, "Invia ora".
class NewTitlesCard extends ConsumerStatefulWidget {
  const NewTitlesCard({super.key});

  @override
  ConsumerState<NewTitlesCard> createState() => _NewTitlesCardState();
}

class _NewTitlesCardState extends ConsumerState<NewTitlesCard> {
  /// Il valore che si sta scrivendo: intanto l'interruttore è fermo lì.
  bool? _writing;

  Future<void> _toggle(bool value) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(inboxAdminControllerProvider.notifier);
    setState(() => _writing = value);
    try {
      // L'azione finisce dopo la rilettura (`act`): l'interruttore non torna
      // indietro per un attimo.
      await controller.setNotifyNewTitles(value);
    } on Object catch (error) {
      // Come `AdminActionButton`: con la scheda cambiata nel frattempo,
      // niente avviso.
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
      }
    } finally {
      if (mounted) setState(() => _writing = null);
    }
  }

  Future<void> _sendNow() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sent =
        await ref.read(inboxAdminControllerProvider.notifier).sendNewTitles();
    messenger.showSnackBar(SnackBar(content: Text(newTitlesSentLabel(l, sent))));
  }

  /// Il numero in attesa in grande, il resto della frase com'è.
  Widget _pending(AppLocalizations l, NewTitlesStatus status) {
    const muted = TextStyle(color: WfColors.creamMuted);
    final label = newTitlesStatusLabel(l, status);
    final number = '${status.pending}';
    // shortcut: il numero si stacca solo se la frase inizia con lui (così è
    // in it e en); altrimenti resta la frase intera, da riguardare se si
    // aggiunge una lingua.
    if (!status.enabled || status.pending == 0 || !label.startsWith(number)) {
      return Text(label, style: muted);
    }
    return Text.rich(TextSpan(children: [
      TextSpan(text: number, style: WfText.display(26)),
      TextSpan(text: label.substring(number.length), style: muted),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(inboxAdminControllerProvider);
    final status = data.value;
    final error = data.error;
    final updatedAt = data.updatedAt;
    final Widget child;
    if (status == null) {
      child = error != null
          ? AdminCardError(
              error: error,
              onRetry: () => unawaited(
                  ref.read(inboxAdminControllerProvider.notifier).refresh()))
          : const SkeletonBox(width: 240, height: 20);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l.adminNewTitlesNotify)),
              Switch(
                key: const Key('notify-new-titles'),
                value: _writing ?? status.enabled,
                onChanged:
                    _writing != null ? null : (value) => unawaited(_toggle(value)),
              ),
            ],
          ),
          _pending(l, status),
          if (data.stale && updatedAt != null)
            AdminStaleNote(updatedAt: updatedAt),
          const SizedBox(height: 12),
          AdminActionButton(
            label: l.adminNewTitlesSendNow,
            icon: LucideIcons.send,
            onPressed: status.enabled && status.pending > 0 ? _sendNow : null,
          ),
        ],
      );
    }
    return AdminCard(
        title: l.adminNewTitles, icon: LucideIcons.sparkles, child: child);
  }
}

/// Seerr nel plugin: ultimo evento del webhook e "Prova collegamento". Con
/// un plugin più vecchio della 1.4.0 non c'è.
class SeerrCard extends ConsumerStatefulWidget {
  const SeerrCard({super.key});

  @override
  ConsumerState<SeerrCard> createState() => _SeerrCardState();
}

class _SeerrCardState extends ConsumerState<SeerrCard> {
  Future<void> _test() async {
    // Letto prima dell'attesa: l'esito va alla spia anche se la card si chiude.
    final notifier = ref.read(seerrTestResultProvider.notifier);
    notifier.set(await ref.read(seerrAdminControllerProvider.notifier).test());
  }

  String _lastEvent(AppLocalizations l, SeerrAdminStatus status) {
    final at = status.lastEventAt;
    if (at == null) return l.adminSeerrNoEvents;
    final type = status.lastEventType;
    return l.adminSeerrLastEvent(adminTimeLabel(at, clock.now(), l),
        type == null ? '—' : seerrEventLabel(l, type));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final data = ref.watch(seerrAdminControllerProvider);
    final value = data.value;
    final error = data.error;
    final updatedAt = data.updatedAt;
    const muted = TextStyle(color: WfColors.creamMuted);
    if (value != null && value.status == null) return const SizedBox.shrink();
    final status = value?.status;
    final result = ref.watch(seerrTestResultProvider);
    final Widget child;
    if (status == null) {
      child = error != null
          ? AdminCardError(
              error: error,
              onRetry: () => unawaited(
                  ref.read(seerrAdminControllerProvider.notifier).refresh()))
          : const SkeletonBox(width: 240, height: 20);
    } else if (!status.configured) {
      child = Text(l.adminSeerrNotConfigured, style: muted);
    } else {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_lastEvent(l, status), style: muted),
          const SizedBox(height: 12),
          Row(
            children: [
              AdminActionButton(
                label: l.adminSeerrTest,
                icon: LucideIcons.link,
                onPressed: _test,
              ),
              if (result != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(seerrTestLabel(l, result),
                      style: TextStyle(
                          color: result.ok ? WfColors.cream : WfColors.error)),
                ),
              ],
            ],
          ),
        ],
      );
    }
    // Come la card Novità: se l'ultima lettura è fallita ma ci sono i dati di
    // prima, si dice che non sono aggiornati. La `Column` c'è sempre, così
    // `child` non cambia posto quando la nota compare (e un'azione in corso,
    // come "Prova collegamento", non perde il suo stato).
    return AdminCard(
      title: l.adminSeerr,
      icon: LucideIcons.listChecks,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          if (data.stale && updatedAt != null)
            AdminStaleNote(updatedAt: updatedAt),
        ],
      ),
    );
  }
}

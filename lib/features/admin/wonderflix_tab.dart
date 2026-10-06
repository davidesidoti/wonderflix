import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/social/plugin_admin_api.dart';
import '../../core/social/plugin_admin_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/smooth_scroll.dart';
import '../../ui/states.dart';
import 'admin_action_button.dart';
import 'admin_confirm_dialog.dart';
import 'admin_time.dart';
import 'admin_widgets.dart';
import 'wonderflix_controllers.dart';
import 'wonderflix_labels.dart';

/// La scheda WonderFlix (spec J §9.6): annuncio, novità, Seerr. Ogni card
/// ha il suo stato: se una non carica, le altre funzionano.
class WonderflixTab extends StatefulWidget {
  const WonderflixTab({super.key});

  @override
  State<WonderflixTab> createState() => _WonderflixTabState();
}

class _WonderflixTabState extends State<WonderflixTab> {
  final _scroll = SmoothScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 40),
        children: const [AnnouncementCard(), NewTitlesCard(), SeerrCard()],
      );
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
      messenger
          .showSnackBar(SnackBar(content: Text(l.adminAnnouncementInvalid)));
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
      messenger.showSnackBar(SnackBar(content: Text(describeError(l, error))));
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
          Text(newTitlesStatusLabel(l, status),
              style: const TextStyle(color: WfColors.creamMuted)),
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
  /// L'esito dell'ultima prova, sotto il pulsante.
  SeerrTestResult? _result;

  Future<void> _test() async {
    final result = await ref.read(seerrAdminControllerProvider.notifier).test();
    if (mounted) setState(() => _result = result);
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
    final result = _result;
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

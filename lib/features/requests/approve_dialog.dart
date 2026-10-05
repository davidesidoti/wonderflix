import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/requests/requests_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import 'requests_providers.dart';

/// I server di Radarr (film) o Sonarr (serie) per la finestra Approva.
final requestServicesProvider = FutureProvider.autoDispose
    .family<List<ServiceOption>, RequestMediaType>(
        (ref, type) => ref.watch(requestsApiProvider).services(type));

/// Apre la finestra Approva (spec I §9.5): la scelta, o `null` se annullata.
Future<ApproveChoice?> showApproveDialog(
    BuildContext context, MediaRequest request) {
  final l = AppLocalizations.of(context);
  return showWfDialog<ApproveChoice>(
    context,
    semanticLabel: l.requestsApproveTitle(_requestTitle(l, request)),
    builder: (_) => ApproveDialog(request: request),
  );
}

/// Il titolo della richiesta, o il testo per un titolo che manca.
String _requestTitle(AppLocalizations l, MediaRequest request) =>
    request.title.isEmpty ? l.requestsUnknownTitle : request.title;

/// Approva con il server "Predefinito" (decide Seerr, anche per gli anime)
/// oppure con un server, un profilo e una cartella scelti (spec I §9.5).
class ApproveDialog extends ConsumerStatefulWidget {
  const ApproveDialog({super.key, required this.request});

  final MediaRequest request;

  @override
  ConsumerState<ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends ConsumerState<ApproveDialog> {
  /// Il valore del menu per "Predefinito": gli id dei server partono da 0.
  static const _defaultServer = -1;

  int _serverId = _defaultServer;
  int? _profileId;
  String? _folder;

  /// Se la scelta di partenza è già stata fatta con i server arrivati.
  bool _seeded = false;

  void _selectServer(List<ServiceOption> servers, int? serverId) =>
      setState(() => _applyServer(servers, serverId));

  /// Sceglie il server con il suo profilo e la sua cartella predefiniti.
  void _applyServer(List<ServiceOption> servers, int? serverId) {
    _serverId = serverId ?? _defaultServer;
    final server = servers.where((s) => s.id == serverId).firstOrNull;
    if (server == null) {
      _profileId = null;
      _folder = null;
      return;
    }
    final profiles = server.profiles.map((p) => p.id).toList();
    _profileId = profiles.contains(server.defaultProfileId)
        ? server.defaultProfileId
        : profiles.firstOrNull;
    _folder = server.rootFolders.contains(server.defaultRootFolder)
        ? server.defaultRootFolder
        : server.rootFolders.firstOrNull;
  }

  /// La scelta; `null` se manca il profilo o la cartella di un server scelto.
  ApproveChoice? get _choice {
    if (_serverId == _defaultServer) return ApproveChoice.defaults;
    final profileId = _profileId;
    final folder = _folder;
    if (profileId == null || folder == null) return null;
    return ApproveChoice(serverId: _serverId, profileId: profileId, rootFolder: folder);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final request = widget.request;
    final title = _requestTitle(l, request);
    final services = ref.watch(requestServicesProvider(request.mediaType));
    final servers = services.value ?? const <ServiceOption>[];
    final defaultServer = servers.where((s) => s.isDefault).firstOrNull;
    // Una volta, quando i server arrivano (e prima che l'utente possa
    // scegliere): se nessuno è il predefinito, con "Predefinito" Seerr
    // approverebbe senza mandare niente a Radarr o Sonarr, quindi si parte
    // dal primo server. "Predefinito" resta tra le voci.
    if (!_seeded && services.hasValue) {
      _seeded = true;
      if (servers.isNotEmpty && defaultServer == null) {
        _applyServer(servers, servers.first.id);
      }
    }
    final server = servers.where((s) => s.id == _serverId).firstOrNull;
    final choice = _choice;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.requestsApproveTitle(title),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        if (services.isLoading && !services.hasValue)
          const SkeletonBox(height: 48)
        else ...[
          _Field(
            label: l.requestsServer,
            child: DropdownButton<int>(
              key: const Key('approve-server'),
              isExpanded: true,
              value: _serverId,
              dropdownColor: WfColors.surfaceHigh,
              items: [
                DropdownMenuItem(
                  value: _defaultServer,
                  child: _MenuLabel(defaultServer == null
                      ? l.requestsServerDefaultPlain
                      : l.requestsServerDefault(defaultServer.name)),
                ),
                for (final option in servers)
                  DropdownMenuItem(
                      value: option.id, child: _MenuLabel(option.name)),
              ],
              onChanged: (value) => _selectServer(servers, value),
            ),
          ),
          if (services.hasError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l.requestsServersUnavailable,
                  style: const TextStyle(color: WfColors.creamMuted, fontSize: 13)),
            ),
          if (server != null) ...[
            const SizedBox(height: 12),
            _Field(
              label: l.requestsProfile,
              child: DropdownButton<int>(
                key: const Key('approve-profile'),
                isExpanded: true,
                value: _profileId,
                dropdownColor: WfColors.surfaceHigh,
                items: [
                  for (final profile in server.profiles)
                    DropdownMenuItem(
                        value: profile.id, child: _MenuLabel(profile.name)),
                ],
                onChanged: (value) => setState(() => _profileId = value),
              ),
            ),
            const SizedBox(height: 12),
            _Field(
              label: l.requestsFolder,
              child: DropdownButton<String>(
                key: const Key('approve-folder'),
                isExpanded: true,
                value: _folder,
                dropdownColor: WfColors.surfaceHigh,
                items: [
                  for (final folder in server.rootFolders)
                    DropdownMenuItem(value: folder, child: _MenuLabel(folder)),
                ],
                onChanged: (value) => setState(() => _folder = value),
              ),
            ),
          ],
        ],
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.requestsCancel),
            ),
            const SizedBox(width: 12),
            WfButton.primary(
              // "Predefinito" è già scelto: Invio approva.
              autofocus: true,
              label: l.requestsApprove,
              icon: LucideIcons.check,
              onPressed: choice == null ? null : () => Navigator.of(context).pop(choice),
            ),
          ],
        ),
      ],
    );
  }
}

/// La voce di un menu: una riga sola, con i puntini se il nome è lungo.
class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
}

/// Un menu con la sua etichetta sopra.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: WfColors.creamMuted, fontSize: 12.5)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/media_info_models.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../../core/subtitles/subtitle_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_confirm_dialog.dart';
import '../../ui/wf_dialog.dart';
import '../admin/admin_providers.dart';
import '../auth/password_login_form.dart';
import '../reports/reports_providers.dart';
import 'subtitle_file_picker.dart';
import 'subtitles_controller.dart';

/// Larghezza della finestra.
const _dialogWidth = 640.0;

/// Lato della rotella di un'operazione in corso.
const _spinnerSize = 20.0;

/// Cerca, scarica, carica ed elimina i sottotitoli di un titolo (spec R
/// §7.5). [onTrackAdded] si chiama quando una traccia nuova compare, se la
/// finestra è ancora aperta. Prende id e titolo, non un `JellyfinItem`, così
/// la aprono allo stesso modo il menu, il riquadro admin e il player.
Future<void> showSubtitlesDialog(
  BuildContext context, {
  required String itemId,
  required String title,
  VoidCallback? onTrackAdded,
}) => showWfDialog<void>(
  context,
  maxWidth: _dialogWidth,
  semanticLabel: AppLocalizations.of(context).subtitlesDialogTitle,
  builder: (_) => _SubtitlesDialog(
    itemId: itemId,
    title: title,
    onTrackAdded: onTrackAdded,
  ),
);

class _SubtitlesDialog extends ConsumerStatefulWidget {
  const _SubtitlesDialog({
    required this.itemId,
    required this.title,
    this.onTrackAdded,
  });

  final String itemId;
  final String title;
  final VoidCallback? onTrackAdded;

  @override
  ConsumerState<_SubtitlesDialog> createState() => _SubtitlesDialogState();
}

class _SubtitlesDialogState extends ConsumerState<_SubtitlesDialog> {
  /// Le caselle valgono per il prossimo caricamento.
  bool _forced = false;
  bool _hearingImpaired = false;

  SubtitlesController get _controller =>
      ref.read(subtitlesControllerProvider(widget.itemId).notifier);

  void _added(bool added) {
    if (added && mounted) widget.onTrackAdded?.call();
  }

  Future<void> _upload() async {
    final l = AppLocalizations.of(context);
    final controller = _controller;
    final forced = _forced;
    final hearingImpaired = _hearingImpaired;
    final file = await ref.read(subtitleFilePickerProvider)(
      l.subtitlesFileTypes,
    );
    if (file == null || !mounted) return;
    _added(
      await controller.upload(
        file,
        forced: forced,
        hearingImpaired: hearingImpaired,
      ),
    );
  }

  Future<void> _delete(SubtitleTrack track) async {
    final l = AppLocalizations.of(context);
    final controller = _controller;
    final confirmed = await showWfConfirmDialog(
      context,
      title: l.subtitlesDeleteTitle,
      message: l.subtitlesDeleteMessage,
      confirmLabel: l.subtitlesDelete,
      cancelLabel: l.adminCancel,
    );
    if (confirmed && mounted) await controller.delete(track);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(subtitlesControllerProvider(widget.itemId));
    final busy = state.searching || state.busyId != null || state.uploading;
    final results = state.results;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.subtitlesDialogTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            widget.title,
            style: const TextStyle(color: WfColors.creamMuted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l.subtitlesLanguage,
                style: const TextStyle(color: WfColors.creamMuted),
              ),
              DropdownButton<String>(
                value: state.language,
                dropdownColor: WfColors.surfaceHigh,
                underline: const SizedBox.shrink(),
                onChanged: busy
                    ? null
                    : (code) => _controller.setLanguage(code!),
                items: [
                  for (final language in playbackLanguages.entries)
                    DropdownMenuItem(
                      value: language.key,
                      child: Text(language.value),
                    ),
                ],
              ),
              WfButton.secondary(
                label: l.subtitlesSearch,
                icon: LucideIcons.search,
                onPressed: busy ? null : () => unawaited(_controller.search()),
              ),
              WfButton.secondary(
                label: l.subtitlesUpload,
                icon: LucideIcons.upload,
                onPressed: busy ? null : () => unawaited(_upload()),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Le caselle valgono per il caricamento, a destra sotto il bottone.
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 16,
              children: [
                _Check(
                  label: l.subtitlesForced,
                  value: _forced,
                  onChanged: (value) => setState(() => _forced = value),
                ),
                _Check(
                  label: l.subtitlesHearingImpaired,
                  value: _hearingImpaired,
                  onChanged: (value) =>
                      setState(() => _hearingImpaired = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Con l'avviso "waiting" la rotella è già nell'avviso.
          if (state.searching ||
              (state.uploading && state.notice != SubtitlesNotice.waiting))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: _Spinner(key: ValueKey('subtitles-progress'))),
            ),
          if (results != null && results.isEmpty)
            Text(
              l.subtitlesNoResults,
              style: const TextStyle(color: WfColors.creamMuted),
            )
          else if (results != null)
            for (final subtitle in results)
              _ResultRow(
                key: ValueKey('subtitle-${subtitle.id}'),
                subtitle: subtitle,
                busy: busy,
                downloading: state.busyId == subtitle.id,
                onDownload: () async =>
                    _added(await _controller.download(subtitle)),
              ),
          _NoticeLine(state: state),
          const SizedBox(height: 16),
          Text(
            l.subtitlesExisting,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _ExistingTracks(itemId: widget.itemId, busy: busy, onDelete: _delete),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
      ],
    ),
  );
}

/// Un sottotitolo trovato: nome (a capo), dettagli, etichette e "Scarica".
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.subtitle,
    required this.busy,
    required this.downloading,
    required this.onDownload,
  });

  final RemoteSubtitle subtitle;
  final bool busy;
  final bool downloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rating = subtitle.communityRating;
    final downloads = subtitle.downloadCount;
    final details = [
      subtitle.providerName,
      subtitle.format,
      if (rating != null) '★ ${rating.toStringAsFixed(1)}',
      if (downloads != null) l.subtitlesDownloads(downloads),
    ].where((part) => part.isNotEmpty).join(' · ');
    const small = TextStyle(fontSize: 12, color: WfColors.creamMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subtitle.name),
                if (details.isNotEmpty) Text(details, style: small),
                Wrap(
                  spacing: 10,
                  children: [
                    if (subtitle.isHashMatch)
                      Text(
                        l.subtitlesHashMatch,
                        style: small.copyWith(color: WfColors.online),
                      ),
                    if (subtitle.hearingImpaired)
                      Text(l.subtitlesHearingImpaired, style: small),
                    if (subtitle.forced) Text(l.subtitlesForced, style: small),
                    if (subtitle.machineTranslated)
                      Text(l.subtitlesMachineTranslated, style: small),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (downloading)
            const _Spinner()
          else if (subtitle.isHashMatch)
            WfButton.primary(
              label: l.subtitlesDownload,
              icon: LucideIcons.download,
              onPressed: busy ? null : onDownload,
            )
          else
            WfButton.secondary(
              label: l.subtitlesDownload,
              icon: LucideIcons.download,
              onPressed: busy ? null : onDownload,
            ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: _spinnerSize,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

/// Lo stato dell'ultima operazione, sopra le tracce.
class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.state});

  final SubtitlesState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const padding = EdgeInsets.only(top: 12);
    return switch (state.notice) {
      SubtitlesNotice.none => const SizedBox.shrink(),
      SubtitlesNotice.waiting => Padding(
        padding: padding,
        child: Row(
          children: [
            const _Spinner(),
            const SizedBox(width: 12),
            Expanded(child: Text(l.subtitlesWaiting)),
          ],
        ),
      ),
      SubtitlesNotice.trackAdded => Padding(
        padding: padding,
        child: Text(
          l.subtitlesTrackAdded,
          style: const TextStyle(color: WfColors.online),
        ),
      ),
      SubtitlesNotice.trackSoon => Padding(
        padding: padding,
        child: Text(
          l.subtitlesTrackSoon,
          style: const TextStyle(color: WfColors.creamMuted),
        ),
      ),
      final failure => Padding(
        padding: padding,
        child: ErrorBanner(switch (failure) {
          SubtitlesNotice.downloadFailed => l.subtitlesDownloadFailed,
          SubtitlesNotice.uploadFailed => l.subtitlesUploadFailed,
          SubtitlesNotice.fileTooLarge => l.subtitlesFileTooLarge,
          SubtitlesNotice.noPermission => l.reportNoPermission,
          _ => describeError(l, state.error ?? const Object()),
        }),
      ),
    };
  }
}

/// Le tracce di sottotitoli già nel titolo, con "Elimina" per l'admin sulle
/// esterne.
class _ExistingTracks extends ConsumerWidget {
  const _ExistingTracks({
    required this.itemId,
    required this.busy,
    required this.onDelete,
  });

  final String itemId;
  final bool busy;
  final ValueChanged<SubtitleTrack> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final isAdmin = ref.watch(isAdminProvider);
    return ref
        .watch(itemMediaInfoProvider(itemId))
        .when(
          skipLoadingOnReload: true,
          loading: () => const _Spinner(),
          error: (error, _) => Text(
            describeError(l, error),
            style: const TextStyle(color: WfColors.creamMuted),
          ),
          data: (info) {
            // Più versioni dello stesso file possono ripetere un indice.
            final seen = <int>{};
            final tracks = [
              for (final version in info.versions)
                for (final track in version.subtitles)
                  if (seen.add(track.index)) track,
            ];
            if (tracks.isEmpty) {
              return Text(
                l.subtitlesNone,
                style: const TextStyle(color: WfColors.creamMuted),
              );
            }
            return Column(
              children: [
                for (final track in tracks)
                  Padding(
                    key: ValueKey('track-${track.index}'),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              track.language ?? '—',
                              if (track.codec != null) track.codec!,
                              track.isExternal
                                  ? l.subtitlesExternal
                                  : l.subtitlesEmbedded,
                            ].join(' · '),
                          ),
                        ),
                        if (isAdmin && track.isExternal)
                          TextButton.icon(
                            onPressed: busy ? null : () => onDelete(track),
                            icon: const Icon(LucideIcons.trash2, size: 16),
                            label: Text(l.subtitlesDelete),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
  }
}

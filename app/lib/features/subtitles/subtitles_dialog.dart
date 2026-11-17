import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/media_info_models.dart';
import '../../core/jellyfin/media_labels.dart';
import '../../core/jellyfin/user_config_api.dart';
import '../../core/subtitles/subtitle_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/dialog_item_poster.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_confirm_dialog.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_dialog_parts.dart';
import '../admin/admin_providers.dart';
import '../auth/password_login_form.dart';
import '../reports/reports_providers.dart';
import 'subtitle_file_picker.dart';
import 'subtitles_controller.dart';

/// Larghezza della finestra.
const _dialogWidth = 960.0;

/// Da questa larghezza del corpo il riquadro del caricamento sta a destra.
const _sideBySideWidth = 720.0;

/// Larghezza del riquadro del caricamento, a destra.
const _uploadPanelWidth = 270.0;

/// Larghezza del menu della lingua.
const _languageFieldWidth = 190.0;

/// Lato della rotella di un'operazione in corso.
const _spinnerSize = 20.0;

const _small = TextStyle(fontSize: 12, color: WfColors.creamMuted);

/// Cerca, scarica, carica ed elimina i sottotitoli di un titolo (spec R
/// §7.5, revisione §6.8). [title] è la riga sotto il titolo della finestra
/// ("L'Istituto · S1:E4 La scatola"); vuota, niente riga. [onTrackAdded] si
/// chiama quando una traccia nuova compare, se la finestra è ancora aperta.
/// Prende id e titolo, non un `JellyfinItem`, così la aprono allo stesso
/// modo il menu, il riquadro admin e il player.
Future<void> showSubtitlesDialog(
  BuildContext context, {
  required String itemId,
  required String title,
  VoidCallback? onTrackAdded,
}) {
  final l = AppLocalizations.of(context);
  return showWfDialog<void>(
    context,
    maxWidth: _dialogWidth,
    semanticLabel: l.subtitlesDialogTitle,
    compactTitle: l.subtitlesDialogTitle,
    builder: (_) => _SubtitlesDialog(
      itemId: itemId,
      title: title,
      onTrackAdded: onTrackAdded,
    ),
    footer: (_) => _Footer(itemId: itemId),
  );
}

/// Chiudi, e a sinistra l'errore dell'ultima azione (scarico, caricamento,
/// eliminazione). Spento mentre si scarica o si carica.
class _Footer extends ConsumerWidget {
  const _Footer({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(subtitlesControllerProvider(itemId));
    final error = switch (state.notice) {
      SubtitlesNotice.downloadFailed => l.subtitlesDownloadFailed,
      SubtitlesNotice.uploadFailed => l.subtitlesUploadFailed,
      SubtitlesNotice.fileTooLarge => l.subtitlesFileTooLarge,
      SubtitlesNotice.noPermission => l.reportNoPermission,
      SubtitlesNotice.error => describeError(l, state.error ?? const Object()),
      _ => null,
    };
    final busy = state.busyId != null || state.uploading;
    return WfDialogFooter(
      note: error,
      noteIsError: error != null,
      busy: busy,
      // `maybePop`: passa dal `PopScope` del corpo.
      primary: WfButton.secondary(
        label: MaterialLocalizations.of(context).closeButtonLabel,
        icon: LucideIcons.x,
        onPressed: busy ? null : () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    // Dopo il primo build: Riverpod non accetta scritture durante initState.
    unawaited(Future.microtask(_controller.searchOnOpen));
  }

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
      title: codecLabel(track.codec).isEmpty
          ? l.subtitlesDeleteTrackTitleNoCodec(_trackLanguage(track, l))
          : l.subtitlesDeleteTrackTitle(
              _trackLanguage(track, l),
              codecLabel(track.codec),
            ),
      message: l.subtitlesDeleteMessage,
      confirmLabel: l.subtitlesDelete,
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
    );
    if (confirmed && mounted) await controller.delete(track);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(subtitlesControllerProvider(widget.itemId));
    final busy = state.searching || state.busyId != null || state.uploading;
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExistingTracks(itemId: widget.itemId, busy: busy, onDelete: _delete),
        const SizedBox(height: 24),
        _SearchSection(
          state: state,
          busy: busy,
          onLanguage: (code) => unawaited(_controller.setLanguage(code)),
          onDownload: (subtitle) async =>
              _added(await _controller.download(subtitle)),
        ),
        _NoticeLine(
          state: state,
          onRetry: () => unawaited(_controller.search()),
        ),
      ],
    );
    final language = languageName(state.language, l.localeName);
    final upload = _UploadPanel(
      // In italiano la lingua in mezzo alla frase va minuscola.
      language: l.localeName.startsWith('it')
          ? language.toLowerCase()
          : language,
      forced: _forced,
      hearingImpaired: _hearingImpaired,
      onForced: (value) => setState(() => _forced = value),
      onHearingImpaired: (value) => setState(() => _hearingImpaired = value),
      onUpload: busy ? null : () => unawaited(_upload()),
    );
    // La ricerca si può lasciare a metà: bloccano solo scarico e caricamento.
    return PopScope(
      canPop: state.busyId == null && !state.uploading,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WfDialogHeader(
            title: l.subtitlesDialogTitle,
            subtitle: widget.title.isEmpty ? null : widget.title,
            leading: DialogItemPoster(itemId: widget.itemId),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth >= _sideBySideWidth
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: main),
                      const SizedBox(width: 28),
                      SizedBox(width: _uploadPanelWidth, child: upload),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [main, const SizedBox(height: 24), upload],
                  ),
          ),
        ],
      ),
    );
  }
}

/// "Italiano", o "—" senza lingua.
String _trackLanguage(SubtitleTrack track, AppLocalizations l) {
  final name = languageName(track.language, l.localeName);
  return name.isEmpty ? '—' : name;
}

/// Il titolo di una sezione con il suo conteggio accanto.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.count});

  final String title;
  final String? count;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(title, style: WfText.display(20)),
      if (count != null) ...[
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            count!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _small,
          ),
        ),
      ],
    ],
  );
}

/// "Cerca" col conteggio e la lingua; la ricerca parte da sola.
class _SearchSection extends StatelessWidget {
  const _SearchSection({
    required this.state,
    required this.busy,
    required this.onLanguage,
    required this.onDownload,
  });

  final SubtitlesState state;
  final bool busy;
  final ValueChanged<String> onLanguage;
  final ValueChanged<RemoteSubtitle> onDownload;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final results = state.results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SectionTitle(
                title: l.subtitlesSearch,
                count: results == null
                    ? null
                    : l.subtitlesResultCount(results.length),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: _languageFieldWidth,
              child: DropdownButtonFormField<String>(
                // La lingua può cambiare da sola (la preferenza arriva dopo).
                key: ValueKey(state.language),
                initialValue: state.language,
                isExpanded: true,
                dropdownColor: WfColors.surfaceHigh,
                decoration: InputDecoration(labelText: l.subtitlesLanguage),
                onChanged: busy ? null : (code) => onLanguage(code!),
                items: [
                  for (final language in playbackLanguages.entries)
                    DropdownMenuItem(
                      value: language.key,
                      child: Text(language.value),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Con l'avviso "waiting" la rotella è già nell'avviso.
        if (state.preparing ||
            state.searching ||
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
              onDownload: () => onDownload(subtitle),
            ),
      ],
    );
  }
}

/// "Carica un file": il suo riquadro con le opzioni che valgono solo qui.
class _UploadPanel extends StatelessWidget {
  const _UploadPanel({
    required this.language,
    required this.forced,
    required this.hearingImpaired,
    required this.onForced,
    required this.onHearingImpaired,
    required this.onUpload,
  });

  final String language;
  final bool forced;
  final bool hearingImpaired;
  final ValueChanged<bool> onForced;
  final ValueChanged<bool> onHearingImpaired;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      key: const ValueKey('subtitles-upload'),
      decoration: BoxDecoration(
        color: WfColors.surfaceHigh,
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.subtitlesUploadTitle, style: WfText.display(20)),
            const SizedBox(height: 6),
            Text(
              l.subtitlesUploadHint(language),
              style: const TextStyle(
                fontSize: 12.5,
                color: WfColors.creamMuted,
              ),
            ),
            const SizedBox(height: 12),
            _Check(
              label: l.subtitlesForced,
              hint: l.subtitlesForcedHint,
              value: forced,
              onChanged: onForced,
            ),
            _Check(
              label: l.subtitlesHearingImpaired,
              hint: l.subtitlesHearingImpairedHint,
              value: hearingImpaired,
              onChanged: onHearingImpaired,
            ),
            const SizedBox(height: 16),
            WfButton.secondary(
              label: l.subtitlesUpload,
              icon: LucideIcons.upload,
              onPressed: onUpload,
            ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(4),
    child: Row(
      children: [
        Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(hint, style: _small),
            ],
          ),
        ),
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
      codecLabel(subtitle.format),
      if (rating != null)
        '★ ${NumberFormat('0.0', l.localeName).format(rating)}',
      if (downloads != null) l.subtitlesDownloads(downloads),
    ].where((part) => part.isNotEmpty).join(' · ');
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
                if (details.isNotEmpty) Text(details, style: _small),
                Wrap(
                  spacing: 10,
                  children: [
                    if (subtitle.isHashMatch)
                      Text(
                        l.subtitlesHashMatch,
                        style: _small.copyWith(color: WfColors.online),
                      ),
                    if (subtitle.hearingImpaired)
                      Text(l.subtitlesHearingImpaired, style: _small),
                    if (subtitle.forced) Text(l.subtitlesForced, style: _small),
                    if (subtitle.machineTranslated)
                      Text(l.subtitlesMachineTranslated, style: _small),
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

/// Lo stato dell'ultima operazione, sotto i risultati.
class _NoticeLine extends StatelessWidget {
  const _NoticeLine({required this.state, required this.onRetry});

  final SubtitlesState state;

  /// "Riprova" di una ricerca non riuscita.
  final VoidCallback onRetry;

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
      SubtitlesNotice.searchFailed => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: ErrorBanner(
                describeError(l, state.error ?? const Object()),
              ),
            ),
            const SizedBox(width: 12),
            WfButton.secondary(
              label: l.retry,
              icon: LucideIcons.refreshCw,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
      // Gli errori delle azioni stanno nel piede.
      _ => const SizedBox.shrink(),
    };
  }
}

/// "Tracce presenti" col numero: lingua, e sotto codec e dove sta. Per
/// l'admin "Elimina…" sulle esterne; quelle nel video dicono che non si può.
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
    final info = ref.watch(itemMediaInfoProvider(itemId));
    // Più versioni dello stesso file possono ripetere un indice.
    final seen = <int>{};
    final tracks = [
      for (final version in info.value?.versions ?? const <MediaVersion>[])
        for (final track in version.subtitles)
          if (seen.add(track.index)) track,
    ];
    final Widget body = info.when(
      skipLoadingOnReload: true,
      loading: () => const _Spinner(),
      error: (error, _) => Text(
        describeError(l, error),
        style: const TextStyle(color: WfColors.creamMuted),
      ),
      data: (_) => tracks.isEmpty
          ? Text(
              l.subtitlesNone,
              style: const TextStyle(color: WfColors.creamMuted),
            )
          : Column(
              children: [
                for (final track in tracks)
                  Padding(
                    key: ValueKey('track-${track.index}'),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _trackLanguage(track, l),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                [
                                  codecLabel(track.codec),
                                  track.isExternal
                                      ? l.subtitlesExternal
                                      : l.subtitlesEmbedded,
                                ].where((p) => p.isNotEmpty).join(' · '),
                                style: _small,
                              ),
                            ],
                          ),
                        ),
                        if (isAdmin && track.isExternal)
                          TextButton.icon(
                            onPressed: busy ? null : () => onDelete(track),
                            icon: const Icon(LucideIcons.trash2, size: 16),
                            label: Text(l.subtitlesDeleteTrack),
                          )
                        else if (isAdmin)
                          Text(l.subtitlesCannotDelete, style: _small),
                      ],
                    ),
                  ),
              ],
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: l.subtitlesExisting,
          count: info.hasValue ? '${tracks.length}' : null,
        ),
        const SizedBox(height: 8),
        body,
      ],
    );
  }
}

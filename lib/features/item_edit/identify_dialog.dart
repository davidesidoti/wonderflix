import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/jellyfin/item_edit_models.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/jellyfin_http.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_image.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import '../library/library_providers.dart';
import 'item_edit_providers.dart';

/// Larghezza della finestra.
const _dialogWidth = 720.0;

/// Lato della rotella di caricamento.
const _spinnerSize = 28.0;

/// Locandina di un risultato.
const _posterWidth = 60.0;
const _posterHeight = 90.0;

/// Righe di trama mostrate per ogni risultato.
const _overviewLines = 3;

/// Identifica un film o una serie cercandolo nei provider (spec R §7.9).
/// Prende l'id e rilegge da sola, così la apre anche il riquadro delle
/// segnalazioni. I testi dei provider sono sempre testo semplice.
Future<void> showIdentifyDialog(
  BuildContext context, {
  required String itemId,
  required ItemKind kind,
}) => showWfDialog<void>(
  context,
  maxWidth: _dialogWidth,
  semanticLabel: AppLocalizations.of(context).identifyTitle,
  builder: (_) => _IdentifyDialog(itemId: itemId, kind: kind),
);

class _IdentifyDialog extends ConsumerStatefulWidget {
  const _IdentifyDialog({required this.itemId, required this.kind});

  final String itemId;
  final ItemKind kind;

  @override
  ConsumerState<_IdentifyDialog> createState() => _IdentifyDialogState();
}

class _IdentifyDialogState extends ConsumerState<_IdentifyDialog> {
  final _name = TextEditingController();
  final _year = TextEditingController();
  final _tmdb = TextEditingController();
  final _imdb = TextEditingController();
  final _tvdb = TextEditingController();

  Map<String, dynamic>? _raw;
  Object? _loadError;

  /// `null` finché non si è cercato.
  List<RemoteSearchResult>? _results;
  RemoteSearchResult? _chosen;
  bool _searching = false;
  bool _busy = false;
  bool _unlock = true;
  bool _replaceImages = true;
  String? _error;

  bool get _isSeries => widget.kind == ItemKind.series;

  /// Il titolo ha campi bloccati: l'identificazione non li sovrascriverebbe.
  bool get _hasLocks {
    final raw = _raw;
    if (raw == null) return false;
    return raw['LockData'] == true ||
        (raw['LockedFields'] as List?)?.isNotEmpty == true;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_name, _year, _tmdb, _imdb, _tvdb]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(itemEditApiProvider);
    final userId = ref.read(currentUserIdProvider);
    try {
      final raw = await api.rawItem(userId, widget.itemId);
      if (!mounted) return;
      final ids = raw['ProviderIds'];
      String id(String key) => ids is Map ? '${ids[key] ?? ''}' : '';
      setState(() {
        _raw = raw;
        _name.text = raw['Name'] as String? ?? '';
        _year.text = '${raw['ProductionYear'] ?? ''}';
        _tmdb.text = id('Tmdb');
        _imdb.text = id('Imdb');
        _tvdb.text = id('Tvdb');
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  /// Il nome o un id bastano per cercare.
  bool get _canSearch =>
      [_name, _tmdb, _imdb, if (_isSeries) _tvdb].any((c) => c.text.trim().isNotEmpty);

  /// Un 403 vuol dire che il permesso è cambiato: l'utente si rilegge.
  String _failure(
    AppLocalizations l,
    Future<void> Function() refreshUser,
    Object error,
  ) {
    if (error is ForbiddenException) {
      unawaited(refreshUser());
      return l.editNoPermission;
    }
    return describeError(l, error);
  }

  Future<void> _search() async {
    if (_searching || _busy || !_canSearch) return;
    final api = ref.read(itemEditApiProvider);
    final session = ref.read(sessionControllerProvider.notifier);
    final l = AppLocalizations.of(context);
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await api.searchRemote(
        widget.kind,
        itemId: widget.itemId,
        name: _name.text.trim(),
        year: int.tryParse(_year.text.trim()),
        providerIds: {
          'Tmdb': _tmdb.text,
          'Imdb': _imdb.text,
          if (_isSeries) 'Tvdb': _tvdb.text,
        },
      );
      if (mounted) setState(() => _results = results);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = _failure(l, session.refreshUser, error));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _apply() async {
    final chosen = _chosen;
    final raw = _raw;
    if (_busy || chosen == null || raw == null) return;
    final api = ref.read(itemEditApiProvider);
    // Letti prima delle attese: la finestra può chiudersi nel frattempo.
    final session = ref.read(sessionControllerProvider.notifier);
    final revision = ref.read(libraryRevisionProvider.notifier);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    // Un timeout vale "Jellyfin sta ancora lavorando" solo durante Apply, non
    // durante lo sblocco che lo precede.
    var applying = false;
    try {
      if (_hasLocks && _unlock) {
        // Si rimanda la Map letta, con i soli blocchi tolti.
        await api.updateItem(widget.itemId, {
          ...raw,
          'LockData': false,
          'LockedFields': <String>[],
        });
      }
      applying = true;
      await api.applyIdentify(
        widget.itemId,
        chosen,
        replaceAllImages: _replaceImages,
      );
      revision.bump();
      messenger?.showSnackBar(SnackBar(content: Text(l.identifyDone)));
      if (mounted) navigator.pop();
    } on ServerUnreachableException catch (error) {
      if (!applying) {
        if (mounted) setState(() => _error = describeError(l, error));
      } else {
        // Jellyfin può aver finito dopo: la scheda si rilegge lo stesso.
        revision.bump();
        messenger?.showSnackBar(
          SnackBar(content: Text(l.identifyStillWorking)),
        );
        if (mounted) navigator.pop();
      }
    } on Object catch (error) {
      // Anche un 502/503/504 del gateway (nginx) dopo un Apply lungo vale
      // "Jellyfin sta ancora lavorando".
      if (applying &&
          error is ServerErrorException &&
          restartGatewayStatuses.contains(error.statusCode)) {
        revision.bump();
        messenger?.showSnackBar(
          SnackBar(content: Text(l.identifyStillWorking)),
        );
        if (mounted) navigator.pop();
      } else if (mounted) {
        setState(() => _error = _failure(l, session.refreshUser, error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final Widget body;
    if (_raw == null) {
      body = _loadError != null
          ? ErrorBanner(describeError(l, _loadError!))
          : const Center(
              child: SizedBox.square(
                dimension: _spinnerSize,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
    } else {
      body = _chosen == null ? _searchPanel(l) : _confirm(l, _chosen!);
    }
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.identifyTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            body,
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(_error!),
            ],
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                TextButton(
                  // Nella conferma "Annulla" torna ai risultati.
                  onPressed: _busy
                      ? null
                      : () => _chosen == null
                            ? Navigator.of(context).pop()
                            : setState(() {
                                _chosen = null;
                                _error = null;
                              }),
                  child: Text(
                    MaterialLocalizations.of(context).cancelButtonLabel,
                  ),
                ),
                if (_chosen != null)
                  WfButton.primary(
                    label: l.identifyApply,
                    icon: LucideIcons.check,
                    onPressed: _busy ? null : () => unawaited(_apply()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    double? width,
  }) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      enabled: !_searching,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => unawaited(_search()),
    ),
  );

  /// I campi della ricerca e i risultati.
  Widget _searchPanel(AppLocalizations l) {
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _field(_name, l.identifyName, width: 240),
            _field(_year, l.identifyYear, width: 90),
            _field(_tmdb, l.identifyTmdb, width: 130),
            _field(_imdb, l.identifyImdb, width: 130),
            if (_isSeries) _field(_tvdb, l.identifyTvdb, width: 130),
            WfButton.primary(
              label: l.identifySearch,
              icon: LucideIcons.search,
              onPressed: _searching || !_canSearch
                  ? null
                  : () => unawaited(_search()),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_searching)
          const Center(
            child: SizedBox.square(
              dimension: _spinnerSize,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (results != null && results.isEmpty)
          Text(
            l.identifyNoResults,
            style: const TextStyle(color: WfColors.creamMuted),
          )
        else if (results != null)
          for (final result in results) _resultRow(result),
      ],
    );
  }

  Widget _resultRow(RemoteSearchResult result) {
    final image = result.imageUrl;
    final year = result.year;
    final provider = result.provider;
    final overview = result.overview;
    final details = [
      if (year != null) '$year',
      if (provider != null && provider.isNotEmpty) provider,
    ].join(' · ');
    return InkWell(
      onTap: () => setState(() => _chosen = result),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _posterWidth,
              height: _posterHeight,
              child: image == null
                  ? null
                  : WfImage(image: ImageRef(image)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      style: const TextStyle(color: WfColors.creamMuted),
                    ),
                  if (overview != null && overview.isNotEmpty)
                    Text(
                      overview,
                      maxLines: _overviewLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// La conferma del risultato scelto, nella stessa finestra.
  Widget _confirm(AppLocalizations l, RemoteSearchResult chosen) {
    final year = chosen.year;
    final label = year == null ? chosen.name : '${chosen.name} ($year)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _replaceImages
              ? l.identifyConfirm(label)
              : l.identifyConfirmNoImages(label),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(l.identifyReplaceImages),
          value: _replaceImages,
          onChanged: _busy
              ? null
              : (value) => setState(() => _replaceImages = value ?? false),
        ),
        if (_hasLocks)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l.identifyUnlock),
            value: _unlock,
            onChanged: _busy
                ? null
                : (value) => setState(() => _unlock = value ?? false),
          ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(l.identifyWorking)),
              ],
            ),
          ),
      ],
    );
  }
}

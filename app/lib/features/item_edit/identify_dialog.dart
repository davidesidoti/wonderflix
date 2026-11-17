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
import '../../ui/dialog_item_poster.dart';
import '../../ui/form_factor.dart';
import '../../ui/ticket_shape.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_dialog_parts.dart';
import '../../ui/wf_image.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'item_edit_providers.dart';

/// Larghezza della finestra.
const _dialogWidth = 1000.0;

/// Lato della rotella di caricamento.
const _spinnerSize = 28.0;

/// Locandina di un risultato e dei biglietti.
const _resultPoster = Size(48, 72);
const _ticketPoster = Size(88, 132);

/// Altezza dei biglietti; lo strappo sta subito dopo la locandina.
const _ticketHeight = 160.0;
const _ticketPadding = 14.0;
const _ticketTear = _ticketPadding * 2 + 88;

const _providerKeys = ['Tmdb', 'Imdb', 'Tvdb'];

/// Il risultato è l'abbinamento attuale di [item]: un id Tmdb, Imdb o Tvdb non
/// vuoto è uguale, senza distinguere maiuscole.
bool isCurrentMatch(Map<String, dynamic> item, RemoteSearchResult r) {
  final mine = item['ProviderIds'];
  final theirs = r.raw['ProviderIds'];
  if (mine is! Map || theirs is! Map) return false;
  for (final key in _providerKeys) {
    final a = '${mine[key] ?? ''}'.trim().toLowerCase();
    if (a.isNotEmpty && a == '${theirs[key] ?? ''}'.trim().toLowerCase()) {
      return true;
    }
  }
  return false;
}

/// I nomi dei `LockedFields` di [item]; un campo sconosciuto resta col suo
/// nome, così il conteggio torna.
List<String> lockedFieldLabels(
  AppLocalizations l,
  Map<String, dynamic> item,
) => [
  for (final field in (item['LockedFields'] as List? ?? const []))
    switch (field) {
      'Name' => l.editFieldName,
      'Overview' => l.editFieldOverview,
      'Genres' => l.editFieldGenres,
      'OfficialRating' => l.editFieldRating,
      _ => '$field',
    },
];

/// Identifica un film o una serie cercandolo nei provider (spec R §7.9,
/// revisione §6.5). Prende l'id e rilegge da sola, così la apre anche il
/// riquadro delle segnalazioni. I testi dei provider sono sempre testo
/// semplice.
Future<void> showIdentifyDialog(
  BuildContext context, {
  required String itemId,
  required ItemKind kind,
}) {
  final l = AppLocalizations.of(context);
  final host = GlobalKey();
  return showWfDialog<void>(
    context,
    maxWidth: _dialogWidth,
    semanticLabel: l.identifyTitle,
    compactTitle: l.identifyTitle,
    builder: (_) => _IdentifyDialog(key: host, itemId: itemId, kind: kind),
    footer: (_) => WfHostFooter(host: host),
  );
}

class _IdentifyDialog extends ConsumerStatefulWidget {
  const _IdentifyDialog({
    super.key,
    required this.itemId,
    required this.kind,
  });

  final String itemId;
  final ItemKind kind;

  @override
  ConsumerState<_IdentifyDialog> createState() => _IdentifyDialogState();
}

class _IdentifyDialogState extends ConsumerState<_IdentifyDialog>
    with WfFooterHost<_IdentifyDialog> {
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

  /// Spento di serie: i campi scritti a mano restano (spec §6.5).
  bool _unlock = false;
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

  /// Nello stretto (non TV) i biglietti vanno in una seconda pagina.
  bool get _narrow {
    final form = FormFactor.of(context);
    return form.compact && !form.tv;
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
      // La scelta vecchia non è più tra i risultati.
      if (mounted) {
        setState(() {
          _results = results;
          _chosen = null;
        });
      }
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
  Widget buildFooter(BuildContext context) {
    final l = AppLocalizations.of(context);
    final secondPage = _narrow && _chosen != null;
    return WfDialogFooter(
      note: _error ?? (_busy ? l.identifyWorking : null),
      noteIsError: _error != null,
      cancelLabel: secondPage
          ? l.navBack
          : MaterialLocalizations.of(context).cancelButtonLabel,
      // Nello stretto "Indietro" torna ai risultati; altrimenti chiude.
      onCancel: secondPage
          ? () {
              if (_busy) return;
              setState(() {
                _chosen = null;
                _error = null;
              });
            }
          : null,
      primary: WfButton.primary(
        label: l.identifyApply,
        icon: LucideIcons.check,
        iconWidget: _busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onPressed: _busy || _chosen == null ? null : () => unawaited(_apply()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final raw = _raw;
    final chosen = _chosen;
    final List<Widget> body;
    if (raw == null) {
      body = [
        if (_loadError != null)
          ErrorBanner(describeError(l, _loadError!))
        else
          const Center(
            child: SizedBox.square(
              dimension: _spinnerSize,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ];
    } else {
      body = [
        if (!_narrow || chosen == null) _searchPanel(l, raw),
        if (chosen != null) ...[
          const SizedBox(height: 20),
          _tickets(l, raw, chosen),
          const SizedBox(height: 12),
          _options(l, raw),
        ],
      ];
    }
    return PopScope(
      canPop: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WfDialogHeader(
            title: l.identifyTitle,
            subtitle: raw == null
                ? null
                : itemContextLine(l, JellyfinItem.fromJson(raw)),
            leading: DialogItemPoster(itemId: widget.itemId),
          ),
          const SizedBox(height: 20),
          ...body,
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    double? width,
    String? hint,
  }) => SizedBox(
    width: width,
    child: TextField(
      controller: controller,
      enabled: !_searching,
      decoration: InputDecoration(labelText: label, hintText: hint),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => unawaited(_search()),
    ),
  );

  /// I campi della ricerca e i risultati.
  Widget _searchPanel(AppLocalizations l, Map<String, dynamic> raw) {
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
            _field(_tmdb, l.identifyTmdb, width: 140),
            _field(_imdb, l.identifyImdb, width: 140, hint: l.identifyImdbHint),
            if (_isSeries) _field(_tvdb, l.identifyTvdb, width: 130),
            WfButton.secondary(
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
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final columns = _narrow ? 1 : 3;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final result in results)
                    SizedBox(
                      width: width,
                      child: _resultTile(l, result, isCurrentMatch(raw, result)),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _resultTile(
    AppLocalizations l,
    RemoteSearchResult result,
    bool current,
  ) {
    final image = result.imageUrl;
    final provider = result.provider;
    final details = [
      if (result.year != null) '${result.year}',
      if (provider != null && provider.isNotEmpty) provider,
    ].join(' · ');
    final selected = identical(result, _chosen);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? WfColors.gold.withValues(alpha: 0.1)
            : WfColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: selected ? WfColors.gold : WfColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy || _searching
              ? null
              : () => setState(() {
                  _chosen = result;
                  _error = null;
                }),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _poster(
                      image == null ? null : ImageRef(image),
                      _resultPoster,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            // Lascia posto alla spunta.
                            padding: const EdgeInsets.only(right: 20),
                            child: Text(
                              result.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (details.isNotEmpty)
                            Text(
                              details,
                              style: const TextStyle(
                                color: WfColors.creamMuted,
                                fontSize: 12,
                              ),
                            ),
                          if (current)
                            Container(
                              margin: const EdgeInsets.only(top: 5),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: WfColors.border,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                l.identifyCurrent,
                                style: const TextStyle(
                                  color: WfColors.creamMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Positioned(
                  right: 8,
                  top: 8,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: WfColors.gold,
                    child: Icon(
                      LucideIcons.check,
                      size: 13,
                      color: WfColors.bg,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// La locandina, o la sagoma se manca.
  Widget _poster(ImageRef? image, Size size) => SizedBox.fromSize(
    size: size,
    child: image != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: WfImage(image: image),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: WfColors.surfaceHigh,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: WfColors.border),
            ),
            child: const Icon(
              LucideIcons.image,
              size: 20,
              color: WfColors.creamMuted,
            ),
          ),
  );

  /// "Ora" (spento) e "Dopo" (oro), con in oro ciò che cambia.
  Widget _tickets(
    AppLocalizations l,
    Map<String, dynamic> raw,
    RemoteSearchResult chosen,
  ) {
    final kind = _isSeries ? l.dialogKindSeries : l.dialogKindMovie;
    final name = raw['Name'] as String? ?? '';
    final year = raw['ProductionYear'] as int?;
    final tags = raw['ImageTags'];
    final hasImage = tags is Map && tags['Primary'] != null;
    final currentPoster = hasImage
        ? ref.watch(imageUrlsProvider).primaryOf(widget.itemId)
        : null;
    final currentImages = hasImage ? l.identifyImages : l.identifyNoImages;
    final newImage = chosen.imageUrl;
    final newImages = _replaceImages && newImage != null;
    String yearKind(int? y) => [if (y != null) '$y', kind].join(' · ');

    final now = _ticket(
      label: l.identifyNow,
      poster: currentPoster,
      lines: [(name, false), (yearKind(year), false), (currentImages, false)],
      gold: false,
    );
    final after = _ticket(
      label: l.identifyAfter,
      poster: newImages ? ImageRef(newImage) : currentPoster,
      lines: [
        (chosen.name, chosen.name != name),
        (yearKind(chosen.year), chosen.year != year),
        (newImages ? l.identifyNewImages : currentImages, newImages),
      ],
      gold: true,
    );
    final arrow = Container(
      width: 38,
      height: 38,
      margin: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: WfColors.gold),
      ),
      child: Icon(
        _narrow ? LucideIcons.arrowDown : LucideIcons.arrowRight,
        size: 18,
        color: WfColors.gold,
      ),
    );
    if (_narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [now, Center(child: arrow), after],
      );
    }
    return Row(
      children: [
        Expanded(child: now),
        arrow,
        Expanded(child: after),
      ],
    );
  }

  /// Un biglietto: locandina, strappo e righe; la prima riga è il titolo.
  /// Le righe segnate vere (cambiano) sono in oro.
  Widget _ticket({
    required String label,
    required ImageRef? poster,
    required List<(String, bool)> lines,
    required bool gold,
  }) {
    final ticket = SizedBox(
      height: _ticketHeight,
      child: Stack(
        children: [
          ClipPath(
            clipper: const TicketClipper.vertical(_ticketTear),
            child: ColoredBox(
              color: WfColors.surfaceHigh,
              child: Padding(
                padding: const EdgeInsets.all(_ticketPadding),
                child: Row(
                  children: [
                    _poster(poster, _ticketPoster),
                    const SizedBox(width: _ticketPadding * 2),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: gold ? WfColors.gold : WfColors.creamMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            lines.first.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WfText.display(28).copyWith(
                              color: lines.first.$2 ? WfColors.gold : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (final (text, changed) in lines.skip(1))
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: changed
                                      ? WfColors.gold
                                      : WfColors.creamMuted,
                                  fontWeight: changed ? FontWeight.w600 : null,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Lo strappo (i mezzi cerchi sono ritagliati) e il bordo di "Dopo".
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: const TicketTearPainter.vertical(_ticketTear),
                child: gold
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: WfColors.gold),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
    return gold ? ticket : Opacity(opacity: 0.72, child: ticket);
  }

  /// "Sostituisci anche le immagini" e, con dei blocchi, lo sblocco.
  Widget _options(AppLocalizations l, Map<String, dynamic> raw) {
    final fields = lockedFieldLabels(l, raw);
    final replace = SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(l.identifyReplaceImages),
      subtitle: Text(l.identifyReplaceImagesHint),
      value: _replaceImages,
      onChanged: _busy ? null : (v) => setState(() => _replaceImages = v),
    );
    final unlock = _hasLocks
        ? SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              fields.isEmpty
                  ? l.identifyUnlockAll
                  : l.identifyUnlockFields(fields.length, fields.join(', ')),
            ),
            subtitle: Text(l.identifyUnlockHint),
            value: _unlock,
            onChanged: _busy ? null : (v) => setState(() => _unlock = v),
          )
        : null;
    if (_narrow || unlock == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [replace, ?unlock],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: replace),
        const SizedBox(width: 24),
        Expanded(child: unlock),
      ],
    );
  }
}

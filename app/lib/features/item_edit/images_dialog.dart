import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/jellyfin/item_edit_api.dart';
import '../../core/jellyfin/item_edit_models.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_image.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import '../detail/detail_providers.dart';
import '../library/library_providers.dart';
import 'item_edit_providers.dart';

/// Larghezza della finestra.
const _dialogWidth = 900.0;

/// Lato della rotella di caricamento.
const _spinnerSize = 28.0;

/// Dimensioni dell'immagine attuale e delle miniature: la locandina è 2:3,
/// sfondo ed episodio 16:9.
const _currentPosterHeight = 180.0;
const _currentWideHeight = 135.0;
const _cardPosterWidth = 120.0;
const _cardWideWidth = 240.0;

/// Le schede di un livello (spec R, decisione 22): film e serie locandina e
/// sfondo, stagioni solo locandina, episodi solo l'immagine (`Primary`).
List<EditImageType> imageTabsFor(ItemKind kind) => switch (kind) {
  ItemKind.movie || ItemKind.series => const [
    EditImageType.primary,
    EditImageType.backdrop,
  ],
  _ => const [EditImageType.primary],
};

/// Lo sfondo nuovo va in fondo (`ImageSaver`): con più di uno si porta
/// l'ultimo in prima posizione. `null` = niente da spostare.
int? backdropToMoveFirst(int backdropCount) =>
    backdropCount > 1 ? backdropCount - 1 : null;

/// Cambia locandina e sfondo di un titolo (spec R §7.11). Prende l'id e
/// rilegge da sola, così la apre anche il riquadro delle segnalazioni.
Future<void> showImagesDialog(
  BuildContext context, {
  required String itemId,
  required ItemKind kind,
}) => showWfDialog<void>(
  context,
  maxWidth: _dialogWidth,
  semanticLabel: AppLocalizations.of(context).imagesTitle,
  builder: (_) => _ImagesDialog(itemId: itemId, kind: kind),
);

class _ImagesDialog extends ConsumerStatefulWidget {
  const _ImagesDialog({required this.itemId, required this.kind});

  final String itemId;
  final ItemKind kind;

  @override
  ConsumerState<_ImagesDialog> createState() => _ImagesDialogState();
}

class _ImagesDialogState extends ConsumerState<_ImagesDialog> {
  late final _tabs = imageTabsFor(widget.kind);
  late EditImageType _type = _tabs.first;

  List<RemoteImage> _images = const [];
  int _total = 0;
  bool _allLanguages = false;
  bool _loadingGrid = false;
  Object? _gridError;

  /// Scarta la risposta di una lettura superata da un cambio di scheda o
  /// della casella delle lingue.
  int _generation = 0;

  /// Cosa sta girando: l'indirizzo dell'immagine scelta o [_uploadKey].
  /// `null` = nessuna operazione.
  String? _busyKey;
  String? _error;

  static const _uploadKey = '';

  bool get _busy => _busyKey != null;

  @override
  void initState() {
    super.initState();
    unawaited(_loadGrid());
  }

  /// Rilegge la griglia da capo, o aggiunge la pagina successiva con [more].
  Future<void> _loadGrid({bool more = false}) async {
    final api = ref.read(itemEditApiProvider);
    final session = ref.read(sessionControllerProvider.notifier);
    final generation = ++_generation;
    setState(() {
      if (!more) {
        _images = const [];
        _total = 0;
      }
      _loadingGrid = true;
      _gridError = null;
    });
    try {
      final page = await api.remoteImages(
        widget.itemId,
        _type,
        startIndex: more ? _images.length : 0,
        allLanguages: _allLanguages,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _images = [..._images, ...page.images];
        // Una pagina vuota con il totale più alto fermerebbe mai "Altre".
        _total = page.images.isEmpty ? _images.length : page.total;
      });
    } on Object catch (error) {
      if (error is ForbiddenException) unawaited(session.refreshUser());
      if (!mounted || generation != _generation) return;
      setState(() => _gridError = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingGrid = false);
      }
    }
  }

  void _selectTab(EditImageType type) {
    if (_busy || type == _type) return;
    _type = type;
    unawaited(_loadGrid());
  }

  /// Una sola operazione alla volta. [body] chiama [changed] appena Jellyfin
  /// ha cambiato qualcosa, così la scheda si rilegge anche se un passo
  /// successivo (lo spostamento dello sfondo) fallisce. [body] risponde
  /// `false` se non c'era niente da fare (scelta annullata): niente messaggio.
  Future<void> _guarded(
    String key,
    Future<bool> Function(ItemEditApi api, void Function() changed) body,
  ) async {
    if (_busy) return;
    final api = ref.read(itemEditApiProvider);
    // Letti prima dell'attesa: la finestra può chiudersi nel frattempo.
    final session = ref.read(sessionControllerProvider.notifier);
    final revision = ref.read(libraryRevisionProvider.notifier);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l = AppLocalizations.of(context);
    var didChange = false;
    var ok = false;
    setState(() {
      _busyKey = key;
      _error = null;
    });
    try {
      ok = await body(api, () => didChange = true);
    } on ForbiddenException {
      // Il permesso è cambiato: l'utente si rilegge.
      unawaited(session.refreshUser());
      if (mounted) setState(() => _error = l.editNoPermission);
    } on _FileTooLarge {
      if (mounted) setState(() => _error = l.imagesFileTooLarge);
    } on Object catch (error) {
      if (mounted) setState(() => _error = describeError(l, error));
    } finally {
      if (didChange) revision.bump();
      if (ok) messenger?.showSnackBar(SnackBar(content: Text(l.imagesSaved)));
      if (mounted) setState(() => _busyKey = null);
    }
  }

  /// Dopo uno sfondo nuovo: rilegge gli sfondi e porta l'ultimo in prima
  /// posizione.
  Future<void> _moveNewBackdropFirst(ItemEditApi api, String userId) async {
    if (_type != EditImageType.backdrop) return;
    final raw = await api.rawItem(userId, widget.itemId);
    final tags = raw['BackdropImageTags'];
    final last = backdropToMoveFirst(tags is List ? tags.length : 0);
    if (last != null) await api.moveBackdropFirst(widget.itemId, last);
  }

  void _use(RemoteImage image) {
    final type = _type;
    // Letto prima delle attese: la finestra può chiudersi nel frattempo.
    final userId = ref.read(currentUserIdProvider);
    unawaited(_guarded(image.url, (api, changed) async {
      await api.downloadImage(widget.itemId, type, image.url);
      changed();
      await _moveNewBackdropFirst(api, userId);
      return true;
    }));
  }

  void _upload() {
    final type = _type;
    final picker = ref.read(imageFilePickerProvider);
    final l = AppLocalizations.of(context);
    // Letto prima delle attese: la finestra può chiudersi nel frattempo.
    final userId = ref.read(currentUserIdProvider);
    unawaited(_guarded(_uploadKey, (api, changed) async {
      final file = await picker(l.imagesFileTypes);
      if (file == null) return false;
      // Il peso si controlla prima di leggere il file e di chiamare Jellyfin.
      if (file.length > maxImageFileBytes) throw _FileTooLarge();
      final bytes = await file.read();
      final mimeType = file.name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      await api.uploadImage(widget.itemId, type, bytes, mimeType: mimeType);
      changed();
      await _moveNewBackdropFirst(api, userId);
      return true;
    }));
  }

  ImageRef? _currentImage(JellyfinItem item) {
    final urls = ref.watch(imageUrlsProvider);
    return switch (_type) {
      EditImageType.backdrop =>
        item.backdropTags.isEmpty ? null : urls.backdrop(item),
      EditImageType.primary when item.imageTags['Primary'] == null => null,
      EditImageType.primary when widget.kind == ItemKind.episode =>
        urls.landscape(item),
      EditImageType.primary => urls.poster(item),
    };
  }

  String _tabLabel(AppLocalizations l, EditImageType type) => switch (type) {
    EditImageType.backdrop => l.imagesBackdrop,
    EditImageType.primary =>
      widget.kind == ItemKind.episode ? l.imagesEpisode : l.imagesPoster,
  };

  bool get _wide => _type == EditImageType.backdrop ||
      widget.kind == ItemKind.episode;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = ref.watch(itemProvider(widget.itemId));
    return PopScope(
      canPop: !_busy,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.imagesTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (_tabs.length > 1) ...[
              Wrap(
                spacing: 8,
                children: [
                  for (final type in _tabs)
                    ChoiceChip(
                      label: Text(_tabLabel(l, type)),
                      selected: type == _type,
                      onSelected: _busy ? null : (_) => _selectTab(type),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Text(
              l.imagesCurrent,
              style: const TextStyle(color: WfColors.creamMuted),
            ),
            const SizedBox(height: 8),
            _current(l, item),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                WfButton.secondary(
                  label: l.imagesUpload,
                  icon: LucideIcons.upload,
                  overlay: _busyKey == _uploadKey ? _spinner() : null,
                  onPressed: _busy ? null : _upload,
                ),
                InkWell(
                  onTap: _busy
                      ? null
                      : () {
                          setState(() => _allLanguages = !_allLanguages);
                          unawaited(_loadGrid());
                        },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _allLanguages,
                        onChanged: _busy
                            ? null
                            : (value) {
                                setState(() => _allLanguages = value ?? false);
                                unawaited(_loadGrid());
                              },
                      ),
                      Text(l.imagesAllLanguages),
                    ],
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(_error!),
            ],
            const SizedBox(height: 16),
            _grid(l),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(MaterialLocalizations.of(context).closeButtonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spinner() => const Center(
    child: SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );

  Widget _current(AppLocalizations l, AsyncValue<JellyfinItem> item) {
    final value = item.value;
    if (value == null) {
      return item.hasError
          ? ErrorBanner(describeError(l, item.error!))
          : const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox.square(
                dimension: _spinnerSize,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
    }
    final image = _currentImage(value);
    if (image == null) {
      return Text(l.imagesNone, style: const TextStyle(color: WfColors.cream));
    }
    final height = _wide ? _currentWideHeight : _currentPosterHeight;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: height,
        width: height * (_wide ? 16 / 9 : 2 / 3),
        child: WfImage(image: image),
      ),
    );
  }

  Widget _grid(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_gridError != null)
          ErrorBanner(_gridError is ForbiddenException
              ? l.editNoPermission
              : describeError(l, _gridError!))
        else if (!_loadingGrid && _images.isEmpty)
          Text(
            l.imagesNoResults,
            style: const TextStyle(color: WfColors.creamMuted),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [for (final image in _images) _card(l, image)],
        ),
        if (_loadingGrid)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox.square(
                dimension: _spinnerSize,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_images.isNotEmpty && _images.length < _total)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : () => unawaited(_loadGrid(more: true)),
              child: Text(l.imagesMore),
            ),
          ),
      ],
    );
  }

  Widget _card(AppLocalizations l, RemoteImage image) {
    final width = _wide ? _cardWideWidth : _cardPosterWidth;
    final details = [
      image.provider,
      if (image.width != null && image.height != null)
        '${image.width}×${image.height}',
      if (image.language != null && image.language!.isNotEmpty) image.language!,
      if (image.rating != null) image.rating!.toStringAsFixed(1),
    ].join(' · ');
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: _wide ? 16 / 9 : 2 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                WfImage(image: ImageRef(image.thumbnailUrl ?? image.url)),
                if (_busyKey == image.url)
                  ColoredBox(
                    color: WfColors.bg.withValues(alpha: 0.5),
                    child: _spinner(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            details,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: WfColors.creamMuted, fontSize: 12),
          ),
          TextButton(
            onPressed: _busy ? null : () => _use(image),
            child: Text(l.imagesUse),
          ),
        ],
      ),
    );
  }
}

/// Il file scelto supera [maxImageFileBytes]: si ferma nell'app.
class _FileTooLarge implements Exception {}

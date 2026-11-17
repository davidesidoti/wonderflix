import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/image_urls.dart';
import '../../core/jellyfin/item_edit_api.dart';
import '../../core/jellyfin/item_edit_models.dart';
import '../../core/jellyfin/item_models.dart';
import '../../core/jellyfin/media_labels.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/dialog_item_poster.dart';
import '../../ui/form_factor.dart';
import '../../ui/states.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../../ui/wf_dialog_parts.dart';
import '../../ui/wf_image.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import '../detail/detail_providers.dart';
import '../library/item_labels.dart';
import '../library/library_providers.dart';
import 'item_edit_providers.dart';

/// Larghezza della finestra.
const _dialogWidth = 900.0;

/// Larghezza dell'immagine attuale (fissa a sinistra) e delle miniature: la
/// locandina è 2:3, sfondo ed episodio 16:9.
const _currentWidth = 210.0;
const _cardPosterWidth = 120.0;
const _cardWideWidth = 240.0;

/// Segnaposto della griglia durante la lettura.
const _skeletonCount = 6;

/// "★ 5,3 · Italiano · 2000×3000": parti mancanti saltate, la lingua vuota è
/// "Senza testo".
String imageCandidateLine(
  AppLocalizations l,
  RemoteImage image,
  String locale,
) {
  final language = image.language;
  return [
    if ((image.rating ?? 0) > 0)
      '★ ${NumberFormat('0.0', locale).format(image.rating)}',
    language == null || language.isEmpty
        ? l.imagesNoText
        : languageName(language, locale),
    if (image.width != null && image.height != null)
      '${image.width}×${image.height}',
  ].join(' · ');
}

/// Le schede di un livello (spec R, decisione 22): film e serie locandina e
/// sfondo, stagioni solo locandina, episodi solo l'immagine (`Primary`).
List<EditImageType> imageTabsFor(ItemKind kind) => switch (kind) {
  ItemKind.movie ||
  ItemKind.series => const [EditImageType.primary, EditImageType.backdrop],
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
}) {
  final title = _title(AppLocalizations.of(context), kind);
  final host = GlobalKey();
  return showWfDialog<void>(
    context,
    maxWidth: _dialogWidth,
    semanticLabel: title,
    compactTitle: title,
    builder: (_) => _ImagesDialog(key: host, itemId: itemId, kind: kind),
    footer: (_) => WfHostFooter(host: host),
  );
}

String _title(AppLocalizations l, ItemKind kind) =>
    kind == ItemKind.episode ? l.imagesTitleEpisode : l.imagesTitle;

class _ImagesDialog extends ConsumerStatefulWidget {
  const _ImagesDialog({super.key, required this.itemId, required this.kind});

  final String itemId;
  final ItemKind kind;

  @override
  ConsumerState<_ImagesDialog> createState() => _ImagesDialogState();
}

class _ImagesDialogState extends ConsumerState<_ImagesDialog>
    with WfFooterHost {
  late final _tabs = imageTabsFor(widget.kind);
  late EditImageType _type = _tabs.first;

  List<RemoteImage> _images = const [];
  int _total = 0;
  bool _allLanguages = false;
  bool _loadingGrid = false;
  Object? _gridError;

  /// La candidata segnata: niente cambia finché non si conferma nel piede.
  RemoteImage? _chosen;

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
        _chosen = null;
        _error = null;
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
    unawaited(
      _guarded(image.url, (api, changed) async {
        await api.downloadImage(widget.itemId, type, image.url);
        changed();
        if (mounted) setState(() => _chosen = null);
        await _moveNewBackdropFirst(api, userId);
        return true;
      }),
    );
  }

  void _upload() {
    final type = _type;
    final picker = ref.read(imageFilePickerProvider);
    final l = AppLocalizations.of(context);
    // Letto prima delle attese: la finestra può chiudersi nel frattempo.
    final userId = ref.read(currentUserIdProvider);
    unawaited(
      _guarded(_uploadKey, (api, changed) async {
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
        // Una candidata ancora segnata sovrascriverebbe il file caricato.
        if (mounted) setState(() => _chosen = null);
        await _moveNewBackdropFirst(api, userId);
        return true;
      }),
    );
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
    EditImageType.primary => l.imagesPoster,
  };

  bool get _wide =>
      _type == EditImageType.backdrop || widget.kind == ItemKind.episode;

  double get _aspect => _wide ? 16 / 9 : 2 / 3;

  bool get _narrow {
    final form = FormFactor.of(context);
    return form.compact && !form.tv;
  }

  /// La chiave di `select` di [AppLocalizations.imagesConfirm].
  String get _kindKey => switch (_type) {
    EditImageType.backdrop => 'backdrop',
    EditImageType.primary when widget.kind == ItemKind.episode => 'episode',
    EditImageType.primary => 'poster',
  };

  @override
  Widget buildFooter(BuildContext context) {
    final l = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final chosen = _chosen;
    if (chosen == null) {
      return WfDialogFooter(
        note: _error,
        noteIsError: _error != null,
        primary: WfButton.secondary(
          label: material.closeButtonLabel,
          icon: LucideIcons.x,
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
      );
    }
    return WfDialogFooter(
      note: _error ?? l.imagesConfirm(_kindKey),
      noteIsError: _error != null,
      cancelLabel: material.cancelButtonLabel,
      onCancel: () {
        if (_busy) return;
        setState(() {
          _chosen = null;
          _error = null;
        });
      },
      primary: WfButton.primary(
        label: l.imagesUseThis(_kindKey),
        icon: LucideIcons.check,
        iconWidget: _busyKey == chosen.url
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onPressed: _busy ? null : () => _use(chosen),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = ref.watch(itemProvider(widget.itemId));
    final value = item.value;
    final current = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.imagesCurrent,
          style: const TextStyle(color: WfColors.creamMuted),
        ),
        const SizedBox(height: 8),
        _current(l, item),
      ],
    );
    final tools = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_tabs.length > 1)
          for (final type in _tabs)
            ChoiceChip(
              label: Text(_tabLabel(l, type)),
              selected: type == _type,
              onSelected: _busy ? null : (_) => _selectTab(type),
            ),
        InkWell(
          onTap: _busy ? null : _toggleLanguages,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _allLanguages,
                onChanged: _busy ? null : (_) => _toggleLanguages(),
              ),
              Text(l.imagesAllLanguages),
            ],
          ),
        ),
        WfButton.secondary(
          label: l.imagesUpload,
          icon: LucideIcons.upload,
          overlay: _busyKey == _uploadKey ? _spinner() : null,
          onPressed: _busy ? null : _upload,
        ),
      ],
    );
    final Widget body;
    if (_narrow) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          current,
          const SizedBox(height: 16),
          tools,
          const SizedBox(height: 16),
          _grid(l),
        ],
      );
    } else {
      // Finestra ad altezza fissa: la griglia scorre da sola, l'attuale resta.
      final height = math.min(560.0, MediaQuery.sizeOf(context).height - 200);
      body = SizedBox(
        height: math.max(240.0, height),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: _currentWidth, child: current),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tools,
                  const SizedBox(height: 16),
                  Expanded(child: SingleChildScrollView(child: _grid(l))),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return PopScope(
      canPop: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WfDialogHeader(
            title: _title(l, widget.kind),
            subtitle: value == null ? null : itemContextLine(l, value),
            leading: DialogItemPoster(itemId: widget.itemId),
          ),
          const SizedBox(height: 20),
          body,
        ],
      ),
    );
  }

  void _toggleLanguages() {
    setState(() => _allLanguages = !_allLanguages);
    unawaited(_loadGrid());
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
          : SkeletonBox(width: _currentWidth, height: _currentWidth / _aspect);
    }
    final image = _currentImage(value);
    if (image == null) {
      return Text(l.imagesNone, style: const TextStyle(color: WfColors.cream));
    }
    return SizedBox(
      width: _currentWidth,
      height: _currentWidth / _aspect,
      child: WfImage(image: image),
    );
  }

  Widget _grid(AppLocalizations l) {
    final width = _wide ? _cardWideWidth : _cardPosterWidth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_gridError != null)
          ErrorBanner(
            _gridError is ForbiddenException
                ? l.editNoPermission
                : describeError(l, _gridError!),
          )
        else if (!_loadingGrid && _images.isEmpty)
          Text(
            l.imagesNoResults,
            style: const TextStyle(color: WfColors.creamMuted),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (final image in _images) _card(l, image),
            if (_loadingGrid)
              for (var i = 0; i < _skeletonCount; i++)
                SkeletonBox(width: width, height: width / _aspect),
          ],
        ),
        if (!_loadingGrid && _images.isNotEmpty && _images.length < _total)
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
    final selected = identical(image, _chosen);
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _busy
              ? null
              : () => setState(() {
                  _chosen = image;
                  _error = null;
                }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: _aspect,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: selected
                        ? Border.all(color: WfColors.gold, width: 2)
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        WfImage(
                          image: ImageRef(image.thumbnailUrl ?? image.url),
                        ),
                        if (selected)
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: CircleAvatar(
                              radius: 11,
                              backgroundColor: WfColors.gold,
                              child: Icon(
                                LucideIcons.check,
                                size: 14,
                                color: WfColors.bg,
                              ),
                            ),
                          ),
                        if (_busyKey == image.url)
                          ColoredBox(
                            color: WfColors.bg.withValues(alpha: 0.5),
                            child: _spinner(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                imageCandidateLine(l, image, l.localeName),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WfColors.creamMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Il file scelto supera [maxImageFileBytes]: si ferma nell'app.
class _FileTooLarge implements Exception {}

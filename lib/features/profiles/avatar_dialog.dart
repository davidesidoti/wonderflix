import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/jellyfin/api_exception.dart';
import '../../core/jellyfin/user_image_api.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_dialog.dart';
import '../auth/password_login_form.dart';
import '../auth/session_controller.dart';
import '../social/avatars_provider.dart';
import 'avatar_cropper.dart';
import 'avatar_gallery.dart';
import 'avatar_image.dart';

/// Larghezza della finestra.
const _dialogWidth = 560.0;

/// Altezza delle schede: la galleria (4 righe) o il ritaglio con i pulsanti.
/// Nella finestra più piccola, con un errore, si stringono.
const _tabHeight = 380.0;

/// Spazio tra le linguette e il contenuto, dove compare l'indicatore del
/// caricamento: c'è sempre, così il contenuto non si sposta.
const _progressSlotHeight = 16.0;

/// Lato di un avatar nella galleria.
const _galleryTileSize = 56.0;

/// Spessore del bordo dell'avatar scelto.
const _selectedBorder = 3.0;

/// Spazio tra il bordo dell'avatar scelto e l'avatar.
const _selectedGap = 2.0;

/// Lato di una casella della galleria: l'avatar, lo spazio e il bordo.
const _galleryTileExtent =
    _galleryTileSize + 2 * (_selectedGap + _selectedBorder);

/// Avatar per riga nella galleria.
const _galleryColumns = 6;

/// Spazio tra le colonne della galleria.
const _galleryColumnGap = 12.0;

/// Spazio tra le righe della galleria: stretto, così le 4 righe stanno anche
/// nella finestra più piccola con un errore.
const _galleryRowGap = 4.0;

/// Lato del riquadro del ritaglio.
const _cropViewport = 240.0;

/// Lato dell'anteprima nella scheda "Rimuovi".
const _previewSize = 120.0;

/// Un file scelto: la dimensione si legge prima del contenuto.
class PickedAvatarFile {
  const PickedAvatarFile({required this.length, required this.read});

  final int length;
  final Future<Uint8List> Function() read;
}

/// Sceglie un'immagine dal PC; `null` se si annulla. [label] è il nome del
/// filtro nella finestra di Windows.
typedef AvatarFilePicker = Future<PickedAvatarFile?> Function(String label);

/// Con `file_selector` (nei test si sostituisce: apre una finestra di
/// sistema).
final avatarFilePickerProvider = Provider<AvatarFilePicker>((ref) => (label) async {
      final file = await openFile(acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: avatarFileExtensions),
      ]);
      if (file == null) return null;
      return PickedAvatarFile(length: await file.length(), read: file.readAsBytes);
    });

/// Il lavoro sulle immagini: isolate e `toImage`, che nei widget test si
/// sostituiscono.
class AvatarImageTools {
  const AvatarImageTools();

  Future<Uint8List> renderGallery(GalleryAvatar avatar) =>
      renderGalleryAvatar(avatar);

  Future<WorkingImage> prepare(Uint8List bytes) => prepareAvatarImage(bytes);

  Future<Uint8List> crop(WorkingImage image, CropArea area) =>
      cropAvatarImage(image.bytes, area);
}

final avatarImageToolsProvider =
    Provider<AvatarImageTools>((ref) => const AvatarImageTools());

/// Apre la finestra dell'immagine del profilo [userId] (spec K §10.1).
Future<void> showAvatarDialog(
  BuildContext context, {
  required String userId,
  required String name,
  required String? imageTag,
}) =>
    showWfDialog<void>(
      context,
      maxWidth: _dialogWidth,
      semanticLabel: AppLocalizations.of(context).profileImageTitle,
      builder: (context) =>
          AvatarDialog(userId: userId, name: name, imageTag: imageTag),
    );

/// La finestra dell'immagine del profilo (spec K §10.1): le schede Avatar,
/// Dal PC e Rimuovi. Mentre carica i pulsanti sono spenti e la finestra non
/// si chiude; riuscita, si chiude; con un errore resta aperta con il
/// messaggio.
class AvatarDialog extends ConsumerStatefulWidget {
  const AvatarDialog({
    super.key,
    required this.userId,
    required this.name,
    required this.imageTag,
  });

  final String userId;
  final String name;
  final String? imageTag;

  @override
  ConsumerState<AvatarDialog> createState() => _AvatarDialogState();
}

class _AvatarDialogState extends ConsumerState<AvatarDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  /// La scheda di prima: il messaggio d'errore era suo.
  int _tabIndex = 0;

  int? _selected;
  WorkingImage? _working;
  CropArea? _area;
  bool _busy = false;

  /// Un caricamento in corso: la finestra non si chiude. Mentre si prepara
  /// un'immagine dal PC sì ([_pick] si ferma da solo).
  bool _uploading = false;
  String? _error;

  AvatarImageTools get _tools => ref.read(avatarImageToolsProvider);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.index == _tabIndex) return;
    _tabIndex = _tabs.index;
    if (_error != null) setState(() => _error = null);
  }

  /// Chiude la finestra solo se è ancora quella in cima: chiusa da altro
  /// (o con un'altra finestra sopra), un `pop` toglierebbe quello che c'è
  /// sotto.
  void _close(ModalRoute<Object?>? route) {
    if (mounted && (route?.isCurrent ?? false)) Navigator.of(context).pop();
  }

  /// Prepara l'immagine (`null`: la toglie) e la manda al server.
  Future<void> _save(Future<ImageUpload?> Function() prepare) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final route = ModalRoute.of(context);
    // La finestra può sparire durante il caricamento (la sessione che
    // cambia), e `ref` non si usa più: la cache degli avatar si aggiorna lo
    // stesso.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _busy = true;
      _uploading = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(sessionControllerProvider.notifier)
          .setProfileImage(widget.userId, image: await prepare());
      if (user != null) {
        container
            .read(avatarDirectoryProvider)
            ?.remember(userId: user.id, name: user.name, tag: user.primaryImageTag);
        // Solo gli avatar di questo utente si rileggono (dalla cache).
        container
          ..invalidate(avatarImageProvider(AvatarLookup.byId(user.id)))
          ..invalidate(avatarImageProvider(AvatarLookup.byName(user.name)));
      }
      _close(route);
    } on UnauthorizedException {
      // Il profilo è scaduto: la finestra si chiude, e "Chi guarda?" lo
      // mostra con "Accedi di nuovo".
      _close(route);
    } on ForbiddenException {
      if (mounted) setState(() => _error = l.profileImageForbidden);
    } on Object {
      if (mounted) setState(() => _error = l.profileImageFailed);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploading = false;
        });
      }
    }
  }

  Future<void> _pick() async {
    final l = AppLocalizations.of(context);
    final file = await ref.read(avatarFilePickerProvider)(l.profileImageFiles);
    if (file == null || !mounted) return;
    if (file.length > maxAvatarFileBytes) {
      setState(() => _error = l.profileImageTooLarge);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final working = await _tools.prepare(await file.read());
      if (!mounted) return;
      setState(() {
        _working = working;
        _area = initialCropArea(
            Size(working.width.toDouble(), working.height.toDouble()),
            _cropViewport);
      });
    } on AvatarImageException catch (error) {
      if (mounted) {
        setState(() => _error = error.reason == AvatarImageError.tooLarge
            ? l.profileImageTooLarge
            : l.profileImageInvalid);
      }
    } on Object {
      if (mounted) setState(() => _error = l.profileImageInvalid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final error = _error;
    // Durante il caricamento Esc e il clic fuori non la chiudono.
    return PopScope(
      canPop: !_uploading,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.profileImageTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TabBar(controller: _tabs, tabs: [
            Tab(text: l.profileImageAvatars),
            Tab(text: l.profileImageFromPc),
            Tab(text: l.profilesRemove),
          ]),
          SizedBox(
            height: _progressSlotHeight,
            child: Center(child: _busy ? const LinearProgressIndicator() : null),
          ),
          if (error != null) ...[
            ErrorBanner(error),
            const SizedBox(height: 12),
          ],
          // Nella finestra più piccola, con un errore, le schede si
          // stringono.
          Flexible(
            child: SizedBox(
              height: _tabHeight,
              child: TabBarView(
                controller: _tabs,
                // Trascinare l'immagine nel ritaglio non deve cambiare scheda.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _galleryTab(l),
                  // Il ritaglio resta com'è quando si guarda un'altra scheda.
                  _KeepAlive(child: _fileTab(l)),
                  _removeTab(l),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _galleryTab(AppLocalizations l) {
    final selected = _selected;
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _galleryColumns,
              mainAxisExtent: _galleryTileExtent,
              crossAxisSpacing: _galleryColumnGap,
              mainAxisSpacing: _galleryRowGap,
            ),
            itemCount: galleryAvatars.length,
            itemBuilder: (context, i) => Center(
              child: _GalleryTile(
                key: ValueKey('gallery-$i'),
                avatar: galleryAvatars[i],
                label: l.profileImageGalleryItem(i + 1),
                selected: selected == i,
                onTap: _busy ? null : () => setState(() => _selected = i),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: WfButton.primary(
            label: l.profileImageUseAvatar,
            icon: LucideIcons.check,
            onPressed: _busy || selected == null
                ? null
                : () => unawaited(_save(() async => ImageUpload(
                    await _tools.renderGallery(galleryAvatars[selected]),
                    'image/png'))),
          ),
        ),
      ],
    );
  }

  Widget _fileTab(AppLocalizations l) {
    final working = _working;
    final area = _area;
    if (working == null) {
      return Center(
        child: WfButton.secondary(
          label: l.profileImageChoose,
          icon: LucideIcons.imagePlus,
          onPressed: _busy ? null : () => unawaited(_pick()),
        ),
      );
    }
    return Column(
      children: [
        AvatarCropper(
          key: ObjectKey(working),
          image: working,
          viewport: _cropViewport,
          // Serve solo al clic su "Usa questa": niente setState.
          onChanged: (next) => _area = next,
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Si stringe se non c'è posto: "Usa questa" resta intero.
            Flexible(
              child: TextButton(
                onPressed: _busy ? null : () => unawaited(_pick()),
                child: Text(l.profileImageChoose),
              ),
            ),
            const SizedBox(width: 12),
            WfButton.primary(
              label: l.profileImageUseFile,
              icon: LucideIcons.check,
              onPressed: _busy || area == null
                  ? null
                  : () => unawaited(_save(() async => ImageUpload(
                      await _tools.crop(working, _area!), 'image/jpeg'))),
            ),
          ],
        ),
      ],
    );
  }

  Widget _removeTab(AppLocalizations l) => Column(
        children: [
          const SizedBox(height: 24),
          UserAvatar(
            userId: widget.userId,
            name: widget.name,
            size: _previewSize,
            imageTag: widget.imageTag,
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: WfButton.secondary(
              label: l.profileImageRemove,
              icon: LucideIcons.trash2,
              onPressed: _busy || widget.imageTag == null
                  ? null
                  : () => unawaited(_save(() async => null)),
            ),
          ),
        ],
      );
}

/// Tiene viva una scheda quando non si vede.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Un avatar della galleria: si sceglie con un clic, il bordo dorato dice
/// quale. Per lo screen reader è un pulsante con il suo numero.
class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    super.key,
    required this.avatar,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final GalleryAvatar avatar;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        selected: selected,
        label: label,
        child: SizedBox.square(
          dimension: _galleryTileExtent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            focusColor: WfColors.gold.withValues(alpha: 0.18),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? WfColors.gold : Colors.transparent,
                  width: _selectedBorder,
                ),
              ),
              padding: const EdgeInsets.all(_selectedGap),
              child: GalleryAvatarView(avatar: avatar, size: _galleryTileSize),
            ),
          ),
        ),
      );
}

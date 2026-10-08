import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/theme.dart';
import '../features/library/library_providers.dart';
import '../features/social/avatars_provider.dart';
import 'wf_image.dart';

/// Dimensione dell'iniziale rispetto al diametro.
const _initialScale = 0.45;

/// L'immagine di un utente, o la sua iniziale (spec K §10.5).
///
/// - [UserAvatar.new]: il tag è già noto (l'utente aperto, un profilo
///   salvato, una sessione dell'admin); `null` vuol dire senza immagine.
/// - [UserAvatar.lookup]: il tag lo cerca [avatarImageProvider], per id o,
///   senza id, per nome (i membri del party).
///
/// L'immagine sta sopra l'iniziale, con il segnaposto trasparente: mentre si
/// carica, o se non si carica, si vede l'iniziale.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.name,
    required this.size,
    this.imageTag,
    this.muted = false,
  }) : _lookup = false;

  const UserAvatar.lookup({
    super.key,
    this.userId,
    required this.name,
    required this.size,
    this.muted = false,
  })  : imageTag = null,
        _lookup = true;

  final String? userId;
  final String name;

  /// Diametro.
  final double size;
  final String? imageTag;

  /// Iniziale dorata su grigio (party, amici, chat) invece che scura su oro.
  final bool muted;
  final bool _lookup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image =
        _lookup ? ref.watch(avatarImageProvider(_lookupKey)).value : _known;
    final initial = _Initial(name: name, size: size, muted: muted);
    if (image == null) return initial;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          initial,
          ClipOval(
            child: TransparentPlaceholders(
              child: WfImage(
                image: ref.watch(imageUrlsProvider).user(image.userId, image.tag),
                fallbackIcon: null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  AvatarLookup get _lookupKey {
    final id = userId;
    return id == null ? AvatarLookup.byName(name) : AvatarLookup.byId(id);
  }

  AvatarImage? get _known {
    final id = userId;
    final tag = imageTag;
    return id == null || tag == null ? null : AvatarImage(id, tag);
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name, required this.size, required this.muted});

  final String name;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: size / 2,
        backgroundColor: muted ? WfColors.surfaceHigh : WfColors.gold,
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(
            color: muted ? WfColors.gold : WfColors.bg,
            fontSize: size * _initialScale,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

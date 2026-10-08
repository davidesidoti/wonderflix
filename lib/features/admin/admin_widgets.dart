import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/error_text.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/user_avatar.dart';
import 'admin_time.dart';

/// Diametro dell'avatar di una riga utente.
const _adminAvatarSize = 28.0;

/// Titolo di una sezione di una scheda ("In riproduzione", "Collegati"…).
class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      );
}

/// Il testo di una sezione vuota.
class AdminEmptyText extends StatelessWidget {
  const AdminEmptyText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: WfColors.creamMuted));
}

/// Un utente: l'avatar, il nome e un dettaglio (client e dispositivo).
class AdminUserLine extends StatelessWidget {
  const AdminUserLine({
    super.key,
    required this.name,
    this.detail = '',
    this.userId,
    this.imageTag,
  });

  final String name;
  final String detail;

  /// Con [imageTag], l'immagine dell'utente (spec K §10.5): il tag lo dà
  /// Jellyfin con la sessione.
  final String? userId;
  final String? imageTag;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UserAvatar(
          userId: userId,
          name: name,
          size: _adminAvatarSize,
          imageTag: imageTag,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(detail,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: WfColors.creamMuted)),
          ),
        ],
      ],
    );
  }
}

/// "Dati non aggiornati · ultimo aggiornamento 12:03" (spec J §10).
class AdminStaleNote extends StatelessWidget {
  const AdminStaleNote({super.key, required this.updatedAt});

  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(LucideIcons.circleAlert, size: 14, color: WfColors.gold),
          const SizedBox(width: 8),
          Flexible(
            child: Text(l.adminStale(adminClockLabel(updatedAt, l)),
                style: const TextStyle(color: WfColors.gold, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Una card della pagina (scheda WonderFlix): titolo con l'icona e
/// contenuto.
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WfColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: WfColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: WfColors.gold),
                const SizedBox(width: 10),
                // Un titolo lungo si accorcia: non fa sbordare la riga.
                Flexible(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

/// L'errore di una card senza dati, con "Riprova".
class AdminCardError extends StatelessWidget {
  const AdminCardError({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        Flexible(
          child: Text(describeError(l, error),
              style: const TextStyle(color: WfColors.creamMuted)),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: onRetry, child: Text(l.retry)),
      ],
    );
  }
}

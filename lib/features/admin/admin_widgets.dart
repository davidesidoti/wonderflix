import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'admin_time.dart';

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

/// Un utente: l'iniziale in un cerchio, il nome e un dettaglio (client e
/// dispositivo).
class AdminUserLine extends StatelessWidget {
  const AdminUserLine({super.key, required this.name, this.detail = ''});

  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: WfColors.gold,
          child: Text(initial,
              style: const TextStyle(
                  color: WfColors.bg, fontWeight: FontWeight.w700, fontSize: 13)),
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

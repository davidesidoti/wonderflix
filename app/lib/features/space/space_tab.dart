import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../admin/admin_widgets.dart';

/// La scheda Spazio (spec U §8). Segnaposto: il contenuto arriva con il
/// Task 4.
class SpaceTab extends StatelessWidget {
  const SpaceTab({super.key, this.header});

  /// La striscia del server, nel layout stretto.
  final Widget? header;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.symmetric(horizontal: adminSideMargin(context)),
    children: [
      ?header,
      AdminSectionTitle(title: AppLocalizations.of(context).adminTabSpace),
    ],
  );
}

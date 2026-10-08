import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_confirm_dialog.dart';

/// Una conferma della pagina Amministrazione: titolo, messaggio, "Annulla"
/// e il pulsante [confirmLabel]. `true` solo con la conferma.
Future<bool> showAdminConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) =>
    showWfConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: AppLocalizations.of(context).adminCancel,
    );

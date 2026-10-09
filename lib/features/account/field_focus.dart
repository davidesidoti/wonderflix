import 'package:flutter/widgets.dart';

/// Dopo il frame, dà il fuoco a [focus] e seleziona tutto il testo di
/// [controller], se [state] è ancora montato. Per l'errore sotto un campo:
/// Invio nell'ultimo campo gli toglie il fuoco, e senza questo bisognerebbe
/// cliccare di nuovo; il testo selezionato si riscrive subito. Si aspetta il
/// frame perché il campo può tornare solo con la prossima costruzione (il
/// primo passo del collegamento).
void focusAndSelectAfterFrame(
  State<StatefulWidget> state,
  FocusNode focus,
  TextEditingController controller,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted) return;
    focus.requestFocus();
    controller.selection =
        TextSelection(baseOffset: 0, extentOffset: controller.text.length);
  });
}

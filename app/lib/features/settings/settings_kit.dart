import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';

/// Dove si salva un'impostazione.
enum SettingsScope {
  /// Solo su questo dispositivo (PC, browser o TV).
  device,

  /// Sul tuo account WonderFlix.
  account,

  /// Sul tuo account Jellyfin: vale in tutti i client.
  jellyfin,
}

const _mutedStyle = TextStyle(
  fontFamily: 'Inter',
  fontSize: 12,
  color: WfColors.creamMuted,
);

/// Il titolo di una sezione delle Impostazioni, con a destra dove si salva.
///
/// La [key] può essere una `GlobalKey`: la pagina la usa per scorrere alla
/// sezione.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle({super.key, required this.title, this.scope});

  final String title;
  final SettingsScope? scope;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scope = this.scope;
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 12),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // Il titolo tiene la sua larghezza: a stringersi è solo il "dove si
            // salva", il cui testo lungo (`jellyfin`) va a capo nello stretto.
            ConstrainedBox(
              // Al "dove si salva" restano almeno 96 px, anche con un titolo
              // più largo del solito (font grande).
              constraints: BoxConstraints(
                maxWidth: scope == null
                    ? box.maxWidth
                    : math.max(0, box.maxWidth - 12 - 96),
              ),
              child: Text(title, style: WfText.display(24)),
            ),
            if (scope != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        scope == SettingsScope.device
                            ? LucideIcons.monitor
                            : LucideIcons.cloud,
                        size: 13,
                        color: WfColors.creamMuted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(switch (scope) {
                          SettingsScope.device =>
                            FormFactor.of(context).tv
                                ? l.settingsScopeDeviceTv
                                : kIsWeb
                                ? l.settingsScopeDeviceWeb
                                : l.settingsScopeDevice,
                          SettingsScope.account => l.settingsScopeAccount,
                          SettingsScope.jellyfin => l.settingsScopeJellyfin,
                        }, textAlign: TextAlign.end, style: _mutedStyle),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Una riga di un [AdminList]: etichetta e aiuto a sinistra, [trailing] a
/// destra.
///
/// Con [wideTrailing] il controllo, nello stretto, va sotto l'etichetta
/// (bottoni segmentati, campi larghi). [indent] rientra la riga a sinistra:
/// per le voci che dipendono da quella sopra.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.hint,
    this.trailing,
    this.onTap,
    this.indent = 0,
    this.wideTrailing = false,
  });

  final String label;
  final String? hint;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double indent;
  final bool wideTrailing;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        if (hint != null) ...[
          const SizedBox(height: 3),
          Text(hint!, style: _mutedStyle.copyWith(height: 1.4)),
        ],
      ],
    );
    final stacked = wideTrailing && FormFactor.of(context).compact;
    // Un controllo largo (bottoni segmentati) non sfora mai: se non ci sta,
    // si rimpicciolisce (testo del sistema grande, lingua con parole lunghe).
    Widget fit(Widget child, Alignment alignment) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: child,
    );
    final content = trailing == null
        ? text
        : stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text,
              const SizedBox(height: 10),
              fit(trailing!, Alignment.centerLeft),
            ],
          )
        : wideTrailing
        ? LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 14),
                ConstrainedBox(
                  // All'etichetta restano almeno 120 px.
                  constraints: BoxConstraints(
                    maxWidth: math.max(0, box.maxWidth - 14 - 120),
                  ),
                  child: fit(trailing!, Alignment.centerRight),
                ),
              ],
            ),
          )
        : Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 14),
              trailing!,
            ],
          );
    // Il `Material` trasparente: la scia del tocco ha una tela dove
    // disegnarsi anche fuori da uno `Scaffold`.
    final row = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14 + indent, 11, 14, 11),
          child: ConstrainedBox(
            // Nello stretto ogni riga è un bersaglio da dito.
            constraints: BoxConstraints(
              minHeight: FormFactor.of(context).compact
                  ? minTouchTarget - 22
                  : 24,
            ),
            child: Align(alignment: Alignment.centerLeft, child: content),
          ),
        ),
      ),
    );
    // Una riga col controllo dentro (menu) ha già il suo bordo oro.
    return onTap == null ? row : TvFocusBorder(child: row);
  }
}

/// Una [SettingsRow] con un interruttore: tutta la riga lo attiva.
///
/// La [key] sta sullo `Switch`, non sulla riga. Con [onChanged] nullo la riga
/// è disattivata.
class SettingsSwitchRow extends StatelessWidget {
  // La chiave va sullo `Switch`, non sul widget: l'analizzatore non lo sa.
  // ignore: use_key_in_widget_constructors
  const SettingsSwitchRow({
    Key? key,
    required this.label,
    this.hint,
    required this.value,
    required this.onChanged,
    this.indent = 0,
  }) : _switchKey = key;

  final Key? _switchKey;
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    // Un solo controllo per chi legge lo schermo: etichetta, aiuto e stato.
    return MergeSemantics(
      child: Opacity(
        opacity: onChanged == null ? 0.45 : 1,
        child: SettingsRow(
          label: label,
          hint: hint,
          indent: indent,
          onTap: onChanged == null ? null : () => onChanged(!value),
          trailing: ExcludeFocus(
            // La riga prende già il focus: non due tappe per lo stesso comando.
            child: Switch(key: _switchKey, value: value, onChanged: onChanged),
          ),
        ),
      ),
    );
  }
}

/// Un menu a tendina da riga: riquadro con bordo, senza la linea sotto.
///
/// La [key] sta sul `DropdownButton`.
class SettingsDropdown<T> extends StatelessWidget {
  // La chiave va sul `DropdownButton`, non sul widget.
  // ignore: use_key_in_widget_constructors
  const SettingsDropdown({
    Key? key,
    required this.value,
    required this.items,
    required this.onChanged,
  }) : _dropdownKey = key;

  final Key? _dropdownKey;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) => TvFocusBorder(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: WfColors.surface,
        border: Border.all(color: WfColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            key: _dropdownKey,
            value: value,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';

/// Il nome di una sezione (lo stesso del suo titolo) dato l'id.
String settingsSectionLabel(AppLocalizations l, String id) => switch (id) {
  'account' => l.settingsAccount,
  'notifications' => l.settingsNotifications,
  'home' => l.settingsHome,
  'playback' => l.settingsSectionPlayback,
  'subtitles' => l.settingsSectionSubtitles,
  'app' => l.settingsSectionApp,
  'discord' => l.settingsDiscord,
  _ => l.settingsSupport,
};

IconData _icon(String id) => switch (id) {
  'account' => LucideIcons.user,
  'notifications' => LucideIcons.bell,
  'home' => LucideIcons.house,
  'playback' => LucideIcons.play,
  'subtitles' => LucideIcons.captions,
  'app' => LucideIcons.slidersHorizontal,
  'discord' => LucideIcons.messageCircle,
  _ => LucideIcons.lifeBuoy,
};

/// Il gruppo di una sezione: tra gruppi diversi la colonna mette un filo.
int _group(String id) => switch (id) {
  'account' || 'notifications' || 'home' => 0,
  'playback' || 'subtitles' => 1,
  _ => 2,
};

/// La colonna di sinistra dello schermo largo: titolo, una voce per sezione
/// visibile e in fondo la versione. Non scorre con la pagina.
class SettingsRail extends StatelessWidget {
  const SettingsRail({
    super.key,
    required this.sections,
    required this.current,
    required this.version,
    required this.onSelect,
  });

  static const width = 208.0;

  final List<String> sections;
  final String current;
  final String version;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: WfColors.surface,
        border: Border(right: BorderSide(color: WfColors.border)),
      ),
      // La versione sta in fondo alla colonna; con poca altezza (finestra
      // bassa) la colonna scorre.
      child: CustomScrollView(
        slivers: [
          // Il margine sta dentro il riempimento: fuori, la colonna
          // scorrerebbe sempre di quel margine.
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 20, 10, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                    child: Text(
                      l.menuSettings.toUpperCase(),
                      style: WfText.display(28),
                    ),
                  ),
                  for (var i = 0; i < sections.length; i++) ...[
                    if (i > 0 && _group(sections[i]) != _group(sections[i - 1]))
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 10,
                        ),
                        child: Divider(height: 1, color: WfColors.border),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _RailEntry(
                        id: sections[i],
                        selected: sections[i] == current,
                        onTap: () => onSelect(sections[i]),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 0),
                    child: Text(
                      l.settingsNavVersion(version),
                      style: const TextStyle(
                        color: WfColors.creamMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La fila di etichette dello schermo stretto, fissa sopra la pagina che
/// scorre: scorre in orizzontale e tiene in vista la voce accesa.
class SettingsSectionStrip extends StatefulWidget {
  const SettingsSectionStrip({
    super.key,
    required this.sections,
    required this.current,
    required this.onSelect,
  });

  final List<String> sections;
  final String current;
  final ValueChanged<String> onSelect;

  @override
  State<SettingsSectionStrip> createState() => _SettingsSectionStripState();
}

class _SettingsSectionStripState extends State<SettingsSectionStrip> {
  final _keys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _reveal(animate: false);
  }

  @override
  void didUpdateWidget(SettingsSectionStrip old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _reveal(animate: true);
  }

  /// La voce accesa torna in vista. Sulla striscia soltanto: è fuori dalla
  /// pagina che scorre, quindi `ensureVisible` non muove altro (nella pagina
  /// farebbe scorrere anche l'asse verticale).
  void _reveal({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[widget.current]?.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: animate
            ? WfMotion.of(context).duration(WfMotion.fast)
            : Duration.zero,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: WfColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final id in widget.sections) ...[
              _StripChip(
                key: _keys.putIfAbsent(id, GlobalKey.new),
                id: id,
                label: settingsSectionLabel(l, id),
                selected: id == widget.current,
                onTap: () => widget.onSelect(id),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailEntry extends StatefulWidget {
  const _RailEntry({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailEntry> createState() => _RailEntryState();
}

class _RailEntryState extends State<_RailEntry> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = widget.selected ? WfColors.cream : WfColors.creamMuted;
    return Semantics(
      selected: widget.selected,
      child: Stack(
        children: [
          Material(
            color: widget.selected ? WfColors.surfaceHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('settings-nav-${widget.id}'),
              onTap: widget.onTap,
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                foregroundDecoration: _focused
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.fromBorderSide(tvFocusSide),
                      )
                    : null,
                child: Row(
                  children: [
                    Icon(_icon(widget.id), size: 16, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        settingsSectionLabel(l, widget.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.selected)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 2,
              child: IgnorePointer(
                child: ColoredBox(
                  key: ValueKey('settings-nav-on-${widget.id}'),
                  color: WfColors.gold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StripChip extends StatelessWidget {
  const _StripChip({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? WfColors.gold : WfColors.creamMuted;
    return Semantics(
      selected: selected,
      child: InkWell(
        key: ValueKey('settings-nav-$id'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTouchTarget),
          child: Center(
            child: Container(
              key: selected ? ValueKey('settings-nav-on-$id') : null,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? WfColors.gold : WfColors.border,
                ),
              ),
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

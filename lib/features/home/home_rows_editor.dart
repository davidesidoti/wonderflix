import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import 'home_layout.dart';
import 'home_rows_editing.dart';

/// Una voce dell'elenco delle righe.
class HomeRowsEditorEntry {
  const HomeRowsEditorEntry(
      {required this.kind, required this.on, this.unavailable});

  final HomeRowKind kind;

  /// Interruttore acceso: la riga si vede (utente) o è accesa per tutti
  /// (admin).
  final bool on;

  /// Perché la riga non c'è (spec M §10); `null` se è disponibile.
  final String? unavailable;
}

/// L'elenco delle righe della Home (spec M §8.5, §8.6), uguale per
/// l'utente e per l'admin: maniglia per trascinare, nome, fonte, motivo se
/// la riga non c'è, interruttore. La voce selezionata ha due frecce per
/// spostarla; da tastiera Alt+↑ e Alt+↓.
class HomeRowsEditor extends StatefulWidget {
  const HomeRowsEditor({
    super.key,
    required this.entries,
    required this.onMove,
    required this.onToggle,
    this.lockUnavailable = true,
  });

  final List<HomeRowsEditorEntry> entries;

  /// [to] è la posizione finale, contata dopo aver tolto la riga.
  final void Function(HomeRowKind row, int to) onMove;

  final void Function(HomeRowKind row, bool on) onToggle;

  /// Modo utente: una riga non disponibile ha l'interruttore spento e
  /// fermo. Modo admin (`false`): si accende lo stesso, e comparirà quando
  /// la fonte c'è.
  final bool lockUnavailable;

  @override
  State<HomeRowsEditor> createState() => _HomeRowsEditorState();
}

class _HomeRowsEditorState extends State<HomeRowsEditor> {
  /// Tiene la tastiera sull'elenco dopo aver scelto una voce.
  final _focus = FocusNode(debugLabel: 'home-rows-editor');

  HomeRowKind? _selected;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _select(HomeRowKind row) {
    setState(() => _selected = row);
    _focus.requestFocus();
  }

  /// Sposta la voce selezionata di una posizione, su (-1) o giù (+1).
  void _step(int delta) {
    final row = _selected;
    if (row == null) return;
    final from = widget.entries.indexWhere((entry) => entry.kind == row);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= widget.entries.length) return;
    widget.onMove(row, to);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () =>
            _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () =>
            _step(1),
      },
      child: Focus(
        focusNode: _focus,
        child: ReorderableListView.builder(
          // Dentro la pagina che scorre: l'elenco è alto quanto le voci.
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: widget.entries.length,
          onReorderItem: (from, to) =>
              widget.onMove(widget.entries[from].kind, to),
          proxyDecorator: (child, index, animation) => Material(
            color: WfColors.surfaceHigh,
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            child: child,
          ),
          itemBuilder: (context, index) =>
              _entry(l, widget.entries[index], index),
        ),
      ),
    );
  }

  Widget _entry(AppLocalizations l, HomeRowsEditorEntry entry, int index) {
    final selected = entry.kind == _selected;
    final source = homeRowSource(l, entry.kind);
    final reason = entry.unavailable;
    final locked = widget.lockUnavailable && reason != null;
    const small = TextStyle(color: WfColors.creamMuted, fontSize: 12.5);
    return Material(
      key: ValueKey('home-rows-${entry.kind.id}'),
      color: selected ? WfColors.surfaceHigh : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _select(entry.kind),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(LucideIcons.gripVertical,
                      size: 18, color: WfColors.creamMuted),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(homeRowName(l, entry.kind),
                        style: TextStyle(
                            color: locked
                                ? WfColors.creamMuted
                                : WfColors.cream)),
                    if (source != null) Text(source, style: small),
                    if (reason != null)
                      Text(reason,
                          style: small.copyWith(color: WfColors.gold)),
                  ],
                ),
              ),
              if (selected) ...[
                IconButton(
                  key: const Key('home-rows-up'),
                  tooltip: l.homeRowsMoveUp,
                  icon: const Icon(LucideIcons.chevronUp, size: 18),
                  onPressed: index > 0 ? () => _step(-1) : null,
                ),
                IconButton(
                  key: const Key('home-rows-down'),
                  tooltip: l.homeRowsMoveDown,
                  icon: const Icon(LucideIcons.chevronDown, size: 18),
                  onPressed: index < widget.entries.length - 1
                      ? () => _step(1)
                      : null,
                ),
              ],
              Switch(
                key: ValueKey('home-rows-switch-${entry.kind.id}'),
                value: entry.on && !locked,
                onChanged:
                    locked ? null : (on) => widget.onToggle(entry.kind, on),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

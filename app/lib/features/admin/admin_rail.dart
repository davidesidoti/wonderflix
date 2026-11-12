import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import 'admin_counts.dart';
import 'admin_navigation.dart';
import 'server_strip.dart';

/// La colonna di sinistra dello schermo largo: il blocco del server e le voci
/// delle schede. Non scorre con il contenuto.
class AdminRail extends ConsumerWidget {
  const AdminRail({super.key, required this.tabs, required this.current});

  static const width = 208.0;

  final List<AdminTab> tabs;
  final AdminTab current;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        width: width,
        decoration: const BoxDecoration(
          color: WfColors.surface,
          border: Border(right: BorderSide(color: WfColors.border)),
        ),
        // Con poca altezza (finestra bassa, riavvio in corso) la colonna scorre.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 20, 10, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: ServerStrip(vertical: true),
              ),
              for (final tab in tabs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: _AdminTabEntry(
                      tab: tab, current: current, vertical: true),
                ),
            ],
          ),
        ),
      );
}

/// La fila delle schede dello schermo stretto: scorre in orizzontale.
class AdminTabStrip extends ConsumerWidget {
  const AdminTabStrip({super.key, required this.tabs, required this.current});

  final List<AdminTab> tabs;
  final AdminTab current;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in tabs) ...[
              _AdminTabEntry(tab: tab, current: current, vertical: false),
              const SizedBox(width: 6),
            ],
          ],
        ),
      );
}

/// Una voce: icona, nome e, se c'è qualcosa da guardare, il pallino con il
/// numero. [vertical] è la voce della colonna (barretta a sinistra), altrimenti
/// quella della fila (barretta sotto).
class _AdminTabEntry extends ConsumerStatefulWidget {
  const _AdminTabEntry({
    required this.tab,
    required this.current,
    required this.vertical,
  });

  final AdminTab tab;
  final AdminTab current;
  final bool vertical;

  @override
  ConsumerState<_AdminTabEntry> createState() => _AdminTabEntryState();
}

class _AdminTabEntryState extends ConsumerState<_AdminTabEntry> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final selected = widget.tab == widget.current;
    final count = adminTabCount(ref, widget.tab, current: widget.current);
    final compact = FormFactor.of(context).compact;
    final color = selected ? WfColors.cream : WfColors.creamMuted;
    const bar = 2.0;
    return Semantics(
      selected: selected,
      child: Stack(
        children: [
          Material(
            color: selected
                ? WfColors.surfaceHigh
                : widget.vertical
                    ? Colors.transparent
                    : WfColors.surface,
            borderRadius: BorderRadius.circular(4),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: ValueKey('admin-tab-${widget.tab.name}'),
              onTap: () => openAdmin(context, tab: widget.tab),
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: Container(
                key: _focused ? const ValueKey('admin-tab-focus') : null,
                constraints: BoxConstraints(
                    minHeight: compact ? minTouchTarget : 0),
                padding: EdgeInsets.symmetric(
                    horizontal: widget.vertical ? 10 : 12, vertical: 9),
                foregroundDecoration: _focused
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.fromBorderSide(tvFocusSide))
                    : null,
                child: Row(
                  mainAxisSize:
                      widget.vertical ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Icon(adminTabIcon(widget.tab), size: 16, color: color),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        adminTabLabel(l, widget.tab),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: color,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400),
                      ),
                    ),
                    if (widget.vertical) const Spacer(),
                    if (count != null) ...[
                      const SizedBox(width: 8),
                      _CountDot(count),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              left: 0,
              top: widget.vertical ? 0 : null,
              right: widget.vertical ? null : 0,
              bottom: 0,
              width: widget.vertical ? bar : null,
              height: widget.vertical ? null : bar,
              child: const IgnorePointer(
                  child: ColoredBox(color: WfColors.gold)),
            ),
        ],
      ),
    );
  }
}

class _CountDot extends StatelessWidget {
  const _CountDot(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
            color: WfColors.gold, borderRadius: BorderRadius.circular(8)),
        child: Text('$count',
            style: const TextStyle(
                color: WfColors.bg,
                fontSize: 10,
                height: 1.5,
                fontWeight: FontWeight.w700)),
      );
}

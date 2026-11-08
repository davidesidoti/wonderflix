import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/auth/session_controller.dart';
import '../features/requests/requests_providers.dart';
import '../l10n/gen/app_localizations.dart';
import '../ui/tv_focusable.dart';
import '../ui/user_avatar.dart';
import 'theme.dart';

/// Larghezza della barra laterale chiusa: solo le icone.
const tvSidebarCollapsedWidth = 72.0;

/// Larghezza della barra laterale col focus: icone e nomi.
const tvSidebarExpandedWidth = 220.0;

/// Rotta della voce "Stasera", che non cambia pagina ma apre una finestra.
const tvTonightEntry = 'tonight';

const _entryHeight = 48.0;

/// Larghezza della riga di una voce a barra aperta (barra meno i margini).
const _rowWidth = tvSidebarExpandedWidth - 16 - 32;

/// Barra laterale della TV: Cerca, Home, Film, Serie, Stasera, La mia lista,
/// Richieste (solo con Seerr) e in fondo l'avatar. Chiusa mostra le icone; si
/// allarga con i nomi quando una voce ha il focus. Sta sopra il contenuto
/// (lo allarga senza spostarlo).
///
/// [onSelect] riceve la rotta della voce o [tvTonightEntry].
class TvSidebar extends ConsumerStatefulWidget {
  const TvSidebar({
    super.key,
    required this.location,
    required this.onSelect,
    required this.onAccount,
    required this.onFocusContent,
  });

  /// Percorso della pagina corrente: la sua voce è in oro.
  final String location;
  final ValueChanged<String> onSelect;
  final VoidCallback onAccount;

  /// Destra dalla barra: il focus torna al contenuto.
  final VoidCallback onFocusContent;

  @override
  ConsumerState<TvSidebar> createState() => TvSidebarState();
}

class TvSidebarState extends ConsumerState<TvSidebar> {
  bool _expanded = false;

  /// Un nodo per voce, così il contenuto può riportare qui il focus.
  final _nodes = <String, FocusNode>{};

  FocusNode _node(String route) =>
      _nodes.putIfAbsent(route, () => FocusNode(debugLabel: 'tv-nav-$route'));

  /// Le voci dall'alto, avatar compreso: Su e Giù si muovono solo tra queste.
  var _order = <String>[];

  static const _account = 'account';

  /// Su e Giù: la voce sopra o sotto, fermandosi alla prima e all'ultima.
  /// La ricerca geometrica uscirebbe dalla barra e la chiuderebbe.
  bool _move(LogicalKeyboardKey key) {
    final step = key == LogicalKeyboardKey.arrowDown
        ? 1
        : key == LogicalKeyboardKey.arrowUp
        ? -1
        : 0;
    if (step == 0) return false;
    final i = _order.indexWhere((r) => _node(r).hasPrimaryFocus);
    if (i < 0) return false;
    _node(_order[(i + step).clamp(0, _order.length - 1)]).requestFocus();
    return true;
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Dà il focus alla voce della pagina [location], o alla prima.
  void focusEntryFor(String location) {
    final routes = [
      '/search', '/home', '/movies', '/series', '/mylist', '/requests', //
    ];
    final route = routes.firstWhere(
      location.startsWith,
      orElse: () => routes.first,
    );
    _node(route).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final user = ref.watch(
      sessionControllerProvider.select(
        (s) => s is SessionSignedIn ? s.user : null,
      ),
    );
    final entries = [
      (route: '/search', label: l.navSearch, icon: LucideIcons.search),
      (route: '/home', label: l.navHome, icon: LucideIcons.house),
      (route: '/movies', label: l.navMovies, icon: LucideIcons.film),
      (route: '/series', label: l.navSeries, icon: LucideIcons.tv),
      (route: tvTonightEntry, label: l.navTonight, icon: LucideIcons.dices),
      (route: '/mylist', label: l.navMyList, icon: LucideIcons.bookmark),
      // Solo con le richieste con Seerr.
      if (ref.watch(requestsAvailableProvider))
        (
          route: '/requests',
          label: l.navRequests,
          icon: LucideIcons.messageSquarePlus,
        ),
    ];
    _order = [for (final e in entries) e.route, if (user != null) _account];

    Widget item({
      required Key key,
      required String label,
      required VoidCallback onActivate,
      required Widget Function(Color color) icon,
      FocusNode? focusNode,
      bool selected = false,
    }) {
      final color = selected ? WfColors.gold : WfColors.cream;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TvFocusable(
          onActivate: onActivate,
          focusNode: focusNode,
          child: SizedBox(
            key: key,
            height: _entryHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Dà alla riga la larghezza piena anche mentre la barra si allarga:
              // il resto lo taglia la barra.
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: _rowWidth,
                  maxWidth: _rowWidth,
                  child: Row(
                    children: [
                      icon(color),
                      // Chiusa non ci sono testi (e mentre si allarga si
                      // accorciano da soli).
                      if (_expanded) ...[
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Focus(
      // Non prende il focus: sente solo se ce l'ha una delle voci.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _expanded = focused),
      // La barra copre l'inizio del contenuto: la ricerca geometrica lo
      // salterebbe, quindi Destra torna all'elemento che aveva il focus.
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        if (_move(event.logicalKey)) return KeyEventResult.handled;
        if (event.logicalKey != LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.ignored;
        }
        widget.onFocusContent();
        return KeyEventResult.handled;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: _expanded ? tvSidebarExpandedWidth : tvSidebarCollapsedWidth,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              WfColors.bg,
              WfColors.bg.withValues(alpha: _expanded ? 0.96 : 0.6),
            ],
          ),
        ),
        child: FocusTraversalGroup(
          child: Column(
            children: [
              const Spacer(),
              for (final e in entries)
                item(
                  key: Key('tv-nav-${e.route}'),
                  focusNode: _node(e.route),
                  label: e.label,
                  selected:
                      e.route != tvTonightEntry &&
                      widget.location.startsWith(e.route),
                  onActivate: () => widget.onSelect(e.route),
                  icon: (color) => Icon(e.icon, size: 24, color: color),
                ),
              const Spacer(),
              if (user != null)
                item(
                  key: const Key('tv-account'),
                  focusNode: _node(_account),
                  label: user.name,
                  onActivate: widget.onAccount,
                  icon: (_) => UserAvatar(
                    userId: user.id,
                    name: user.name,
                    size: 24,
                    imageTag: user.primaryImageTag,
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

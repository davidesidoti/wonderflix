import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/social/social_api.dart';
import '../../core/social/social_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/wf_menus.dart';
import '../social/social_providers.dart';
import '../watch_party/party_badge.dart';
import '../watch_party/watch_party_actions.dart';
import '../watch_party/watch_party_session.dart';
import 'friend_search.dart';
import 'friends_controller.dart';
import 'party_code_field.dart';

/// Pannello Amici aperto o chiuso (spec F §8.3). Non dipende da niente:
/// lo legge anche la gestione di Esc. Si azzera quando nessuno lo guarda
/// più (es. la shell smontata al logout).
class FriendsPanelController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Apre il pannello e rilegge gli amici.
  void open() {
    if (state) return;
    state = true;
    unawaited(ref.read(friendsControllerProvider.notifier).reload());
  }

  void close() => state = false;

  void toggle() => state ? close() : open();
}

final friendsPanelProvider =
    NotifierProvider.autoDispose<FriendsPanelController, bool>(
        FriendsPanelController.new);

/// Il pannello si vede: aperto e con la funzione amici del plugin.
final friendsPanelVisibleProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(friendsPanelProvider) &&
    ref.watch(socialAvailabilityProvider.select((f) => f.friends)));

/// Online prima, poi in ordine alfabetico (spec F §8.3).
List<FriendEntry> sortFriends(List<FriendEntry> friends) => [...friends]
  ..sort((a, b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

/// Esegue un'azione sugli amici; se non riesce lo dice con una snackbar
/// (spec F §8.1).
Future<void> runFriendAction(
    BuildContext context, Future<SocialFailure?> Function() action) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failure = await action();
  if (failure == null) return;
  messenger?.showSnackBar(SnackBar(
      content: Text(failure == SocialFailure.rateLimited
          ? l.friendsTooMany
          : l.friendsActionFailed)));
}

const _mutedStyle = TextStyle(color: WfColors.creamMuted, fontSize: 13);

/// Contenuto del pannello Amici (spec F §8.3): ricerca, "Ho un codice" (con
/// la funzione `parties` del plugin), richieste, amici.
class FriendsPanel extends ConsumerStatefulWidget {
  const FriendsPanel({super.key});

  /// Larghezza, e quota massima della finestra.
  static const width = 360.0;
  static const maxWidthFraction = 0.9;

  /// Per quanto resta "Conferma rimozione".
  static const removeConfirmFor = Duration(seconds: 4);

  @override
  ConsumerState<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends ConsumerState<FriendsPanel> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Il campo prende il fuoco all'apertura. `autofocus` non basta: nella
    // shell vera lo scope della pagina ha già un figlio col fuoco (il
    // navigatore annidato) e `autofocus` viene scartato.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final searching = ref.watch(friendSearchProvider.select((s) => s.active));
    return Material(
      key: const Key('friends-panel'),
      color: WfColors.surface,
      elevation: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.friendsTitle,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: l.friendsClose,
                  icon: const Icon(LucideIcons.x, size: 20),
                  onPressed: () =>
                      ref.read(friendsPanelProvider.notifier).close(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              key: const Key('friends-search'),
              controller: _search,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: l.friendsSearchHint,
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                isDense: true,
              ),
              onChanged: (text) =>
                  ref.read(friendSearchProvider.notifier).setQuery(text),
            ),
          ),
          if (!searching &&
              ref.watch(socialAvailabilityProvider.select((f) => f.parties)))
            const _PartyCodeEntry(),
          Expanded(
            child: searching ? const _SearchResults() : const _FriendLists(),
          ),
        ],
      ),
    );
  }
}

/// "Ho un codice" (spec F §9.4): un campo per entrare in un party privato.
class _PartyCodeEntry extends ConsumerStatefulWidget {
  const _PartyCodeEntry();

  @override
  ConsumerState<_PartyCodeEntry> createState() => _PartyCodeEntryState();
}

class _PartyCodeEntryState extends ConsumerState<_PartyCodeEntry> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _show() {
    setState(() => _open = true);
    // Il campo di ricerca ha già il focus: `autofocus` non basterebbe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  Future<void> _join() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final code = normalizePartyCode(_code.text);
    if (code.length != partyCodeLength) {
      setState(() => _error = l.partyCodeInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final groupId = await ref.read(socialApiProvider).joinByCode(code);
      if (!mounted) return;
      final joined = await joinWatchParty(context, ref, groupId);
      if (!mounted) return;
      setState(() => _busy = false);
      if (joined) ref.read(friendsPanelProvider.notifier).close();
    } on SocialException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.failure == SocialFailure.rateLimited
            ? l.partyCodeTooMany
            : l.partyCodeInvalid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_open) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 20, 4),
          child: TextButton.icon(
            onPressed: _show,
            icon: const Icon(LucideIcons.ticket, size: 16),
            label: Text(l.partyHaveCode),
            style: TextButton.styleFrom(foregroundColor: WfColors.gold),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('party-code-field'),
                  controller: _code,
                  focusNode: _focus,
                  inputFormatters: [PartyCodeFormatter()],
                  decoration: InputDecoration(
                      hintText: l.partyCodeHint, isDense: true),
                  onSubmitted: (_) => unawaited(_join()),
                ),
              ),
              const SizedBox(width: 8),
              _ActionButton(
                  label: l.partyCodeJoin, onPressed: () => unawaited(_join())),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!,
                  style:
                      const TextStyle(color: WfColors.error, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final search = ref.watch(friendSearchProvider);
    if (search.results.isEmpty) {
      if (search.searching) return const SizedBox.shrink();
      return _Note(switch (search.failure) {
        null => l.friendsSearchEmpty,
        SocialFailure.rateLimited => l.friendsTooMany,
        _ => l.friendsActionFailed,
      });
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final result in search.results)
          _PersonRow(
            key: ValueKey('search-${result.userId}'),
            name: result.name,
            trailing: _SearchAction(result: result),
          ),
      ],
    );
  }
}

/// Azione su un risultato della ricerca, secondo la relazione.
class _SearchAction extends ConsumerWidget {
  const _SearchAction({required this.result});

  final UserSearchResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final friends = ref.read(friendsControllerProvider.notifier);
    // Dopo l'azione la ricerca si ripete da sola: gli amici vengono riletti
    // e `FriendSearch` ascolta la lista (la relazione è cambiata).
    void run(Future<SocialFailure?> Function() action) =>
        unawaited(runFriendAction(context, action));
    final id = result.userId;
    return switch (result.relation) {
      FriendRelation.none => _ActionButton(
          label: l.friendsAdd, onPressed: () => run(() => friends.request(id))),
      FriendRelation.incoming => _ActionButton(
          label: l.friendsAccept,
          onPressed: () => run(() => friends.accept(id))),
      FriendRelation.outgoing => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.friendsSent, style: _mutedStyle),
            _ActionButton(
                label: l.friendsCancel,
                muted: true,
                onPressed: () => run(() => friends.cancel(id))),
          ],
        ),
      FriendRelation.friend => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.check, size: 16, color: WfColors.gold),
            const SizedBox(width: 4),
            Text(l.friendsAlready, style: _mutedStyle),
          ],
        ),
    };
  }
}

class _FriendLists extends ConsumerWidget {
  const _FriendLists();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final friendsState = ref.watch(friendsControllerProvider);
    final controller = ref.read(friendsControllerProvider.notifier);
    if (!friendsState.loaded) {
      // Mentre carica la prima volta il pannello resta vuoto.
      if (!friendsState.failed) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.friendsUnavailable, style: _mutedStyle),
            const SizedBox(height: 8),
            _ActionButton(
                label: l.retry, onPressed: () => unawaited(controller.reload())),
          ],
        ),
      );
    }
    final snapshot = friendsState.snapshot;
    final requests = snapshot.incoming.length + snapshot.outgoing.length;
    final friends = sortFriends(snapshot.friends);
    void run(Future<SocialFailure?> Function() action) =>
        unawaited(runFriendAction(context, action));
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (requests > 0) ...[
          _SectionTitle(l.friendsRequests(requests)),
          for (final person in snapshot.incoming)
            _PersonRow(
              key: ValueKey('incoming-${person.userId}'),
              name: person.name,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionButton(
                      label: l.friendsAccept,
                      onPressed: () =>
                          run(() => controller.accept(person.userId))),
                  _ActionButton(
                      label: l.friendsDecline,
                      muted: true,
                      onPressed: () =>
                          run(() => controller.decline(person.userId))),
                ],
              ),
            ),
          for (final person in snapshot.outgoing)
            _PersonRow(
              key: ValueKey('outgoing-${person.userId}'),
              name: person.name,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.friendsPending, style: _mutedStyle),
                  _ActionButton(
                      label: l.friendsCancel,
                      muted: true,
                      onPressed: () =>
                          run(() => controller.cancel(person.userId))),
                ],
              ),
            ),
        ],
        _SectionTitle(l.friendsTitle),
        if (friends.isEmpty)
          _Note(l.friendsEmpty)
        else
          for (final friend in friends)
            _FriendRow(key: ValueKey('friend-${friend.userId}'), friend: friend),
      ],
    );
  }
}

/// Un amico: ⋯ → "Rimuovi dagli amici" → "Conferma rimozione" per
/// [FriendsPanel.removeConfirmFor] (nell'app non ci sono dialoghi).
class _FriendRow extends ConsumerStatefulWidget {
  const _FriendRow({super.key, required this.friend});

  final FriendEntry friend;

  @override
  ConsumerState<_FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends ConsumerState<_FriendRow> {
  Timer? _confirm;

  @override
  void dispose() {
    _confirm?.cancel();
    super.dispose();
  }

  void _askConfirm() {
    _confirm?.cancel();
    setState(() {
      _confirm = Timer(FriendsPanel.removeConfirmFor, () {
        if (mounted) setState(() => _confirm = null);
      });
    });
  }

  void _remove() {
    _confirm?.cancel();
    setState(() => _confirm = null);
    unawaited(runFriendAction(
        context,
        () => ref
            .read(friendsControllerProvider.notifier)
            .remove(widget.friend.userId)));
  }

  /// Entra nel party dell'amico; riuscito, il pannello si chiude.
  Future<void> _join(String groupId) async {
    final joined = await joinWatchParty(context, ref, groupId);
    if (joined && mounted) ref.read(friendsPanelProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final friend = widget.friend;
    final Widget menu = _confirm != null
        ? _ActionButton(
            key: const Key('friend-remove-confirm'),
            label: l.friendsRemoveConfirm,
            danger: true,
            onPressed: _remove,
          )
        : PopupMenuButton<String>(
            tooltip: l.friendsMore,
            icon: const Icon(LucideIcons.ellipsis,
                size: 18, color: WfColors.creamMuted),
            popUpAnimationStyle: wfPopUpAnimation(context),
            onSelected: (_) => _askConfirm(),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                  value: 'remove', child: Text(l.friendsRemove)),
            ],
          );
    final party = friend.party;
    // La sessione del watch party si guarda solo se serve (test e app
    // senza party non la costruiscono).
    final inGroupId = party == null
        ? null
        : ref.watch(watchPartySessionProvider
            .select((s) => s.inGroup ? s.group?.id : null));
    final showJoin = party != null && !_sameGroup(party.groupId, inGroupId);
    return _PersonRow(
      name: friend.name,
      online: friend.online,
      subtitle: party == null ? null : l.friendsInParty(party.title),
      trailing: showJoin
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  key: Key('friend-join-${friend.userId}'),
                  label: l.watchPartyJoin,
                  onPressed: () => unawaited(_join(party.groupId)),
                ),
                menu,
              ],
            )
          : menu,
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    super.key,
    required this.name,
    required this.trailing,
    this.online,
    this.subtitle,
  });

  final String name;
  final Widget trailing;

  /// `null`: stato non mostrato (ricerca, richieste).
  final bool? online;

  /// Seconda riga sotto il nome (es. "Nel watch party: Dune").
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = online;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Semantics(
            label: status == null
                ? null
                : (status ? l.friendsOnline : l.friendsOffline),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                MemberAvatar(name: name),
                if (status == true)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      key: const Key('online-dot'),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: WfColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: WfColors.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: status == false
                            ? WfColors.creamMuted
                            : WfColors.cream)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: WfColors.creamMuted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.muted = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool muted;
  final bool danger;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: danger
              ? WfColors.error
              : muted
                  ? WfColors.creamMuted
                  : WfColors.gold,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        child: Text(label),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: WfColors.creamMuted, fontSize: 12, letterSpacing: 1)),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(text, style: _mutedStyle),
      );
}

/// Lo stesso gruppo, con o senza trattini e maiuscole.
bool _sameGroup(String a, String? b) =>
    b != null &&
    a.replaceAll('-', '').toLowerCase() == b.replaceAll('-', '').toLowerCase();

/// Pannello Amici sopra la shell e la barra (spec F §8.3): entra da destra
/// come "Audio e sottotitoli" (con le animazioni ridotte solo in
/// dissolvenza), il resto si scurisce. Esc, × e un clic sullo scuro lo
/// chiudono.
class FriendsPanelHost extends ConsumerStatefulWidget {
  const FriendsPanelHost({super.key});

  @override
  ConsumerState<FriendsPanelHost> createState() => _FriendsPanelHostState();
}

class _FriendsPanelHostState extends ConsumerState<FriendsPanelHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WfMotion.medium,
    reverseDuration: WfMotion.fast,
    value: ref.read(friendsPanelVisibleProvider) ? 1 : 0,
  );
  late final CurvedAnimation _progress = CurvedAnimation(
    parent: _controller,
    curve: WfMotion.emphasized,
    reverseCurve: WfMotion.accelerateReverse,
  );

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = WfMotion.of(context).duration(WfMotion.medium);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    // Prima la curva (si stacca dal controller), poi il controller.
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Esc chiude il pannello; `BackNavigationHandler` intanto non torna
  /// indietro di pagina. Con un menu aperto (es. ⋯ di un amico) Esc è del
  /// menu: lo chiude lui, il pannello resta.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
        !ref.read(friendsPanelVisibleProvider)) {
      return false;
    }
    ref.read(friendsPanelProvider.notifier).close();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(friendsPanelVisibleProvider, (_, visible) {
      if (visible) {
        _controller.forward();
      } else {
        _controller.reverse();
        // Funzione sparita a pannello aperto: si chiude davvero.
        ref.read(friendsPanelProvider.notifier).close();
      }
    });
    final reduced = WfMotion.of(context).isReduced;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(FriendsPanel.width,
            constraints.maxWidth * FriendsPanel.maxWidthFraction);
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            if (_controller.isDismissed) return const SizedBox.shrink();
            final t = _progress.value.clamp(0.0, 1.0);
            final closing = _controller.status == AnimationStatus.reverse;
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('friends-panel-scrim'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        ref.read(friendsPanelProvider.notifier).close(),
                    child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.54 * t)),
                  ),
                ),
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: width,
                  child: IgnorePointer(
                    ignoring: closing,
                    child: reduced
                        ? Opacity(opacity: t, child: const FriendsPanel())
                        : FractionalTranslation(
                            translation: Offset(1 - t, 0),
                            child: const FriendsPanel(),
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

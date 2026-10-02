import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/jellyfin/auth_models.dart';
import '../../core/jellyfin/server_events.dart';
import '../../core/party_channel/party_channel_api.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../auth/session_controller.dart';
import 'party_notices.dart';
import 'watch_party_providers.dart';
import 'watch_party_session.dart';

final _log = Logger('watchparty');

/// Il plugin "WonderFlix Watch Party" sul server (spec E §7.3).
enum PartyPluginAvailability {
  /// Non ancora chiesto.
  unknown,
  available,

  /// Assente, o con un protocollo che non parliamo.
  unavailable,
}

/// Esito di [PartyChannel.sendChat].
enum PartyChatSendResult { sent, rateLimited, failed }

/// Un messaggio della chat.
class PartyChatEntry {
  PartyChatEntry(this.event,
      {required this.mine, this.pending = false, String? key})
      : key = key ?? event.id;

  final PartyChatEvent event;

  /// Scritto dal nostro utente (anche da un altro PC): nome "Tu".
  final bool mine;

  /// Mandato da noi e non ancora confermato dal plugin.
  final bool pending;

  /// Identità del messaggio per l'interfaccia: l'`id` dell'evento; per i
  /// nostri messaggi quello locale anche dopo la conferma, così la bolla e
  /// la riga dello storico restano le stesse (spec E §9.4).
  final String key;
}

class PartyChannelState {
  const PartyChannelState({
    this.availability = PartyPluginAvailability.unknown,
    this.pluginVersion,
    this.active = false,
    this.messages = const [],
    this.unread = 0,
    this.sent = 0,
    this.received = 0,
  });

  final PartyPluginAvailability availability;
  final String? pluginVersion;

  /// Il canale funziona per il gruppo in cui siamo.
  final bool active;

  /// Storico della chat del gruppo, dal più vecchio; al massimo
  /// [PartyChannel.maxMessages].
  final List<PartyChatEntry> messages;

  /// Messaggi arrivati con la chat fuori dallo schermo (spec E §9.5).
  final int unread;

  /// Eventi mandati e ricevuti nel gruppo (diagnostica).
  final int sent;
  final int received;

  /// Con [clearPluginVersion] la versione torna `null` (plugin sparito).
  PartyChannelState copyWith({
    PartyPluginAvailability? availability,
    String? pluginVersion,
    bool clearPluginVersion = false,
    bool? active,
    List<PartyChatEntry>? messages,
    int? unread,
    int? sent,
    int? received,
  }) =>
      PartyChannelState(
        availability: availability ?? this.availability,
        pluginVersion:
            clearPluginVersion ? null : pluginVersion ?? this.pluginVersion,
        active: active ?? this.active,
        messages: messages ?? this.messages,
        unread: unread ?? this.unread,
        sent: sent ?? this.sent,
        received: received ?? this.received,
      );
}

typedef _Membership = ({String groupId, int rejoins});

_Membership? _membershipOf(WatchPartyState party) {
  final group = party.group;
  return party.inGroup && group != null
      ? (groupId: group.id, rejoins: party.rejoins)
      : null;
}

String _normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

/// Il canale del plugin "WonderFlix Watch Party" (spec E §7.3): entra nel
/// gruppo del plugin quando si entra in un gruppo SyncPlay, riceve gli
/// eventi degli altri e manda i nostri. Senza plugin resta spento e l'app
/// fa come prima.
///
/// Gli annunci ricevuti vanno agli avvisi ([PartyNotices.attribute]); chat e
/// reazioni restano qui per il player.
class PartyChannel extends Notifier<PartyChannelState> {
  static const maxMessages = 50;

  /// Attesa massima di `Info` chiesto dalla diagnostica.
  static const infoTimeout = Duration(seconds: 5);

  /// Id degli eventi già visti che si ricordano (doppioni dopo un rientro).
  static const _seenLimit = 200;

  // Creati una volta sola, come in [WatchPartySession]: chi si iscrive lo
  // fa una volta e resta iscritto anche se il canale si ricostruisce.
  final _reactions = StreamController<PartyReactionEvent>.broadcast();
  final _chat = StreamController<PartyChatEntry>.broadcast();

  final _seen = Queue<String>();
  final _seenIds = <String>{};
  JellyfinUser? _user;

  /// Gruppo del canale attivo; `null` = canale spento.
  String? _groupId;

  /// Gruppo del `Join` in corso: il server ci ha forse già registrati, e
  /// un evento può arrivare prima della risposta.
  String? _joiningGroupId;

  /// Cambia a ogni ingresso e uscita: un `Join` partito prima non vale più.
  int _generation = 0;

  /// Livelli chat del player montati (spec E §9.5).
  int _chatLayers = 0;

  int _localIds = 0;

  @override
  PartyChannelState build() {
    final userId = ref.watch(sessionControllerProvider
        .select((s) => s is SessionSignedIn ? s.user.id : null));
    final session = ref.read(sessionControllerProvider);
    _user = session is SessionSignedIn ? session.user : null;
    _groupId = null;
    _joiningGroupId = null;
    _generation++;
    _forgetSeen();
    if (userId == null) return const PartyChannelState();
    final subscription = ref.watch(watchPartyEventsProvider).listen(_onEvent);
    ref.onDispose(() => unawaited(subscription.cancel()));
    ref.listen<_Membership?>(
        watchPartySessionProvider.select(_membershipOf), _onMembership);
    // Il canale può nascere a gruppo già in corso: si entra appena finita la
    // build (lo stato non si cambia durante la build).
    final initial = _membershipOf(ref.read(watchPartySessionProvider));
    if (initial != null) {
      final generation = _generation;
      Future.microtask(() {
        if (ref.mounted && generation == _generation && _groupId == null) {
          unawaited(_join(initial.groupId));
        }
      });
    }
    return const PartyChannelState();
  }

  /// Reazioni da mostrare: degli altri e, subito, le nostre.
  Stream<PartyReactionEvent> get reactions => _reactions.stream;

  /// Messaggi nuovi: degli altri e i nostri appena mandati (`pending`).
  Stream<PartyChatEntry> get chatArrivals => _chat.stream;

  /// Manda un messaggio (spec E §9.4): compare subito come `pending`, e
  /// diventa confermato con la risposta del plugin. Se l'invio fallisce il
  /// messaggio sparisce.
  Future<PartyChatSendResult> sendChat(String text) async {
    final groupId = _groupId;
    final user = _user;
    final normalized = normalizeChatText(text);
    if (groupId == null ||
        user == null ||
        normalized.isEmpty ||
        chatTextLength(normalized) > maxChatLength) {
      return PartyChatSendResult.failed;
    }
    final local = PartyChatEntry(
      PartyChatEvent(
        id: 'local-${++_localIds}',
        groupId: groupId,
        userId: user.id,
        userName: user.name,
        sentAt: clock.now().toUtc(),
        text: normalized,
      ),
      mine: true,
      pending: true,
    );
    _addMessage(local);
    _chat.add(local);
    try {
      final stamped = await _send(groupId, PartyOutgoingChat(normalized));
      if (!ref.mounted || _groupId != groupId) return PartyChatSendResult.sent;
      _remember(stamped.id);
      final confirmed = PartyChatEntry(
          stamped is PartyChatEvent ? stamped : local.event,
          mine: true,
          key: local.key);
      state = state.copyWith(
        sent: state.sent + 1,
        messages: [
          for (final entry in state.messages)
            identical(entry, local) ? confirmed : entry,
        ],
      );
      return PartyChatSendResult.sent;
    } on PartyChannelException catch (error) {
      _log.info('messaggio del watch party non inviato: $error');
      if (ref.mounted) {
        state = state.copyWith(messages: [
          for (final entry in state.messages)
            if (!identical(entry, local)) entry,
        ]);
      }
      return error.failure == PartyChannelFailure.rateLimited
          ? PartyChatSendResult.rateLimited
          : PartyChatSendResult.failed;
    }
  }

  /// Manda una reazione: la nostra si vede subito, senza aspettare il
  /// plugin (spec E §10.4).
  void sendReaction(PartyReaction reaction) {
    final groupId = _groupId;
    final user = _user;
    if (groupId == null || user == null) return;
    _reactions.add(PartyReactionEvent(
      id: 'local-${++_localIds}',
      groupId: groupId,
      userId: user.id,
      userName: user.name,
      sentAt: clock.now().toUtc(),
      reaction: reaction,
    ));
    unawaited(_sendQuietly(PartyOutgoingReaction(reaction)));
  }

  /// Annuncia agli altri un'azione nostra sul gruppo (spec E §7.4).
  void announce(PartyAction action, {Duration? position}) {
    if (_groupId == null) return;
    unawaited(_sendQuietly(PartyOutgoingAction(action, position: position)));
  }

  /// Annuncia un'azione nata in `GroupAuthority` (pausa, ripresa, salto); le
  /// altre non si annunciano da qui.
  void announceMine(PartyNoticeKind kind, {Duration? position}) {
    final action = switch (kind) {
      PartyNoticeKind.paused => PartyAction.pause,
      PartyNoticeKind.resumed ||
      PartyNoticeKind.forcedResume =>
        PartyAction.unpause,
      PartyNoticeKind.seeked => PartyAction.seek,
      _ => null,
    };
    if (action != null) announce(action, position: position);
  }

  /// La chat è stata aperta: niente più non letti.
  void markRead() {
    if (state.unread != 0) state = state.copyWith(unread: 0);
  }

  /// Un livello chat del player è a schermo: i messaggi in arrivo non
  /// contano come non letti (spec E §9.5). Ogni chiamata va chiusa da
  /// [detachChatLayer] (durante un passaggio tra player sono due).
  void attachChatLayer() => _chatLayers++;

  void detachChatLayer() {
    if (_chatLayers > 0) _chatLayers--;
  }

  /// Per la diagnostica (spec E §13): se il plugin non risulta presente
  /// chiede `Info`, al massimo per [infoTimeout].
  Future<void> refreshInfo() async {
    if (state.availability == PartyPluginAvailability.available) return;
    try {
      final info =
          await ref.read(partyChannelApiProvider).info().timeout(infoTimeout);
      if (!ref.mounted) return;
      state = state.copyWith(
        availability: info.protocol == partyChannelProtocol
            ? PartyPluginAvailability.available
            : PartyPluginAvailability.unavailable,
        pluginVersion: info.version,
      );
    } on PartyChannelException catch (error) {
      if (ref.mounted && error.failure == PartyChannelFailure.unavailable) {
        state = state.copyWith(
            availability: PartyPluginAvailability.unavailable,
            clearPluginVersion: true);
      }
    } on Object catch (error) {
      _log.info('plugin del watch party non verificato: $error');
    }
  }

  void _onMembership(_Membership? previous, _Membership? next) {
    if (previous != null && previous.groupId != next?.groupId) {
      _leave(previous.groupId);
    }
    if (next != null) unawaited(_join(next.groupId));
  }

  /// Entra nel canale del gruppo (anche dopo un rientro): `Info` finché il
  /// plugin non risulta presente, poi `Join` con lo storico.
  Future<void> _join(String groupId) async {
    final generation = ++_generation;
    try {
      final api = ref.read(partyChannelApiProvider);
      if (state.availability != PartyPluginAvailability.available) {
        final info = await api.info();
        if (!ref.mounted || generation != _generation) return;
        if (info.protocol != partyChannelProtocol) {
          _log.warning('plugin del watch party ${info.version} con '
              'protocollo ${info.protocol}: canale spento');
          _deactivate(
              availability: PartyPluginAvailability.unavailable,
              version: info.version);
          return;
        }
        state = state.copyWith(
            availability: PartyPluginAvailability.available,
            pluginVersion: info.version);
      }
      _joiningGroupId = groupId;
      final history = await api.join(groupId);
      if (!ref.mounted || generation != _generation) return;
      _groupId = groupId;
      state = state.copyWith(active: true, messages: _merge(history));
      ref.read(partyNoticesProvider.notifier).setAttribution(true);
      _log.info('canale del watch party attivo '
          '(${history.length} messaggi nello storico)');
    } on PartyChannelException catch (error) {
      if (!ref.mounted || generation != _generation) return;
      _log.info('canale del watch party spento: $error');
      if (error.failure == PartyChannelFailure.unavailable) {
        _deactivatePluginGone();
      } else {
        _deactivate();
      }
    } on Object catch (error) {
      if (!ref.mounted || generation != _generation) return;
      _log.warning('canale del watch party non disponibile: $error');
      _deactivate();
    } finally {
      if (generation == _generation) _joiningGroupId = null;
    }
  }

  /// [groupId] è il gruppo del canale attivo o quello del `Join` in corso.
  bool _isChannelGroup(String groupId) {
    final id = _normalizeId(groupId);
    return [_groupId, _joiningGroupId]
        .any((group) => group != null && _normalizeId(group) == id);
  }

  /// Evento del nostro utente, anche da un altro PC (id confrontati come
  /// quelli dei gruppi).
  bool _isMine(PartyEvent event) {
    final user = _user;
    return user != null && _normalizeId(event.userId) == _normalizeId(user.id);
  }

  void _leave(String groupId) {
    _generation++;
    // Anche con il `Join` ancora in corso: il server ci ha forse già
    // registrati.
    final registered = _isChannelGroup(groupId);
    _groupId = null;
    _joiningGroupId = null;
    _forgetSeen();
    state = PartyChannelState(
        availability: state.availability, pluginVersion: state.pluginVersion);
    ref.read(partyNoticesProvider.notifier).setAttribution(false);
    if (!registered) return;
    unawaited(ref.read(partyChannelApiProvider).leave(groupId).catchError(
        (Object error) =>
            _log.info('uscita dal canale del watch party non inviata: $error')));
  }

  /// Canale spento per il gruppo corrente (plugin assente o sparito, errori).
  void _deactivate(
      {PartyPluginAvailability? availability,
      String? version,
      bool clearVersion = false}) {
    _groupId = null;
    if (!ref.mounted) return;
    state = state.copyWith(
        active: false,
        availability: availability,
        pluginVersion: version,
        clearPluginVersion: clearVersion);
    ref.read(partyNoticesProvider.notifier).setAttribution(false);
  }

  /// Il plugin non c'è (404): canale spento e versione dimenticata, così la
  /// diagnostica dice "assente".
  void _deactivatePluginGone() => _deactivate(
      availability: PartyPluginAvailability.unavailable, clearVersion: true);

  void _onEvent(ServerEvent event) {
    if (event is! PartyChannelReceived) return;
    if (_groupId == null && _joiningGroupId == null) return;
    final parsed = parsePartyEvent(event.payload);
    if (parsed == null ||
        !_isChannelGroup(parsed.groupId) ||
        !_remember(parsed.id)) {
      return;
    }
    state = state.copyWith(received: state.received + 1);
    switch (parsed) {
      case PartyActionEvent():
        ref.read(partyNoticesProvider.notifier).attribute(parsed);
      case PartyChatEvent():
        final entry = PartyChatEntry(parsed, mine: _isMine(parsed));
        _addMessage(entry);
        if (_chatLayers == 0) state = state.copyWith(unread: state.unread + 1);
        _chat.add(entry);
      case PartyReactionEvent():
        _reactions.add(parsed);
    }
  }

  /// `false` se l'evento [id] è già arrivato.
  bool _remember(String id) {
    if (!_seenIds.add(id)) return false;
    _seen.add(id);
    if (_seen.length > _seenLimit) _seenIds.remove(_seen.removeFirst());
    return true;
  }

  void _forgetSeen() {
    _seen.clear();
    _seenIds.clear();
  }

  /// Storico ricevuto unito ai messaggi presenti, senza doppioni, in ordine
  /// di invio; al massimo [maxMessages].
  List<PartyChatEntry> _merge(List<PartyChatEvent> history) {
    final byId = {for (final entry in state.messages) entry.event.id: entry};
    for (final event in history) {
      _remember(event.id);
      byId.putIfAbsent(
          event.id, () => PartyChatEntry(event, mine: _isMine(event)));
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.event.sentAt.compareTo(b.event.sentAt));
    return merged.length > maxMessages
        ? merged.sublist(merged.length - maxMessages)
        : merged;
  }

  void _addMessage(PartyChatEntry entry) {
    final messages = [...state.messages, entry];
    state = state.copyWith(
        messages: messages.length > maxMessages
            ? messages.sublist(messages.length - maxMessages)
            : messages);
  }

  /// Manda [event]. Con 409 (il plugin non trova la sessione) rientra nel
  /// canale e riprova una volta; con 404 il plugin è sparito e il canale si
  /// spegne (spec E §12).
  Future<PartyEvent> _send(String groupId, PartyOutgoing event) async {
    final api = ref.read(partyChannelApiProvider);
    try {
      try {
        return await api.send(groupId, event);
      } on PartyChannelException catch (error) {
        if (error.failure != PartyChannelFailure.sessionUnknown) rethrow;
        _log.info('il plugin non trova la sessione: rientro nel canale');
        final history = await api.join(groupId);
        if (ref.mounted && _groupId == groupId) {
          state = state.copyWith(messages: _merge(history));
        }
        return await api.send(groupId, event);
      }
    } on PartyChannelException catch (error) {
      if (error.failure == PartyChannelFailure.unavailable &&
          _groupId == groupId) {
        _log.warning('plugin del watch party sparito: canale spento');
        _deactivatePluginGone();
      }
      rethrow;
    }
  }

  /// Invio senza esito per chi chiama (reazioni, annunci): gli errori
  /// finiscono nel log.
  Future<void> _sendQuietly(PartyOutgoing event) async {
    final groupId = _groupId;
    if (groupId == null) return;
    try {
      await _send(groupId, event);
      if (ref.mounted) state = state.copyWith(sent: state.sent + 1);
    } on PartyChannelException catch (error) {
      _log.info('evento ${event.toJson()['Type']} del watch party non '
          'inviato: $error');
    }
  }
}

final partyChannelProvider =
    NotifierProvider<PartyChannel, PartyChannelState>(PartyChannel.new);

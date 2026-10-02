import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/party_channel/party_channel_models.dart';
import 'party_channel.dart';
import 'party_chat_bubble.dart';

/// Tiene il testo entro [maxChatLength] punti di codice, come il plugin.
/// Il `maxLength` di Flutter conta i grafemi: alcune emoji composte
/// supererebbero il limite del server.
class ChatLengthFormatter extends TextInputFormatter {
  const ChatLengthFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (chatTextLength(newValue.text) <= maxChatLength) return newValue;
    final text = String.fromCharCodes(newValue.text.runes.take(maxChatLength));
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// La chat del watch party nel player (spec E §9), in basso a sinistra.
/// Chiusa, i messaggi in arrivo compaiono come bolle che svaniscono; aperta,
/// il campo per scrivere con lo storico sopra. Apertura e chiusura le
/// decide chi la monta (`PlayerScreen`), con [onOpen] e [onClose].
class PartyChatLayer extends ConsumerStatefulWidget {
  const PartyChatLayer({
    super.key,
    required this.open,
    required this.onOpen,
    required this.onClose,
  });

  final bool open;

  /// Riapre la chat (un messaggio non inviato torna nel campo).
  final VoidCallback onOpen;

  /// Chiude la chat (Invio a campo vuoto, chiusura automatica).
  final VoidCallback onClose;

  /// Posizione nel player: margine dei controlli, appena sopra la loro zona
  /// (come "Salta intro" e la scheda del prossimo episodio a destra).
  static const left = 24.0;
  static const bottom = 150.0;

  /// Quanto resta una bolla.
  static const bubbleLifetime = Duration(seconds: 8);

  /// Bolle insieme al massimo.
  static const maxBubbles = 3;

  /// Chat aperta con il campo vuoto e senza attività: si chiude da sola.
  static const idleClose = Duration(seconds: 20);

  /// Altezza massima dello storico rispetto alla finestra.
  static const historyHeightFraction = 0.4;

  /// Il contatore dei caratteri compare da qui.
  static const counterFrom = 180;

  @override
  ConsumerState<PartyChatLayer> createState() => _PartyChatLayerState();
}

/// Una bolla: il messaggio (la `key` di `PartyChatEntry`), il suo conto
/// alla rovescia e se sta uscendo.
class _Bubble {
  _Bubble(this.key);

  final String key;
  bool leaving = false;
  Timer? timer;
}

class _PartyChatLayerState extends ConsumerState<PartyChatLayer> {
  /// Distanza dal fondo entro cui lo storico segue i messaggi nuovi.
  static const _stickToEndSlack = 24.0;

  late final PartyChannel _channel;
  late final StreamSubscription<PartyChatEntry> _arrivals;
  final _bubbles = <_Bubble>[];
  final _field = TextEditingController();
  final _fieldFocus = FocusNode(debugLabel: 'party-chat');
  final _scroll = ScrollController();
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _channel = ref.read(partyChannelProvider.notifier)..attachChatLayer();
    _arrivals = _channel.chatArrivals.listen(_onArrival);
    _field.addListener(_onTextChanged);
    if (widget.open) _onOpened();
  }

  @override
  void didUpdateWidget(PartyChatLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      _onOpened();
    } else {
      _onClosed();
    }
  }

  @override
  void dispose() {
    _channel.detachChatLayer();
    unawaited(_arrivals.cancel());
    _idleTimer?.cancel();
    for (final bubble in _bubbles) {
      bubble.timer?.cancel();
    }
    _field.dispose();
    _fieldFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onOpened() {
    // Lo storico prende il posto delle bolle.
    for (final bubble in _bubbles) {
      bubble.timer?.cancel();
    }
    _bubbles.clear();
    _restartIdle();
    // Dopo il fotogramma: qui si è dentro una build (lo stato dei provider
    // non si cambia, e il campo non esiste ancora).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.open) return;
      _channel.markRead();
      _fieldFocus.requestFocus();
      _jumpToEnd();
    });
  }

  void _onClosed() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _onArrival(PartyChatEntry entry) {
    if (!mounted) return;
    if (widget.open) {
      // Chat aperta: il messaggio è nello storico; si scende in fondo se si
      // era già in fondo.
      final atEnd = !_scroll.hasClients ||
          _scroll.position.extentAfter < _stickToEndSlack;
      setState(() {});
      if (atEnd) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
      return;
    }
    final bubble = _Bubble(entry.key);
    bubble.timer = Timer(PartyChatLayer.bubbleLifetime, () => _leave(bubble));
    setState(() {
      _bubbles.add(bubble);
      while (_bubbles.length > PartyChatLayer.maxBubbles) {
        _bubbles.removeAt(0).timer?.cancel();
      }
    });
  }

  void _leave(_Bubble bubble) {
    if (!mounted) return;
    setState(() => bubble.leaving = true);
  }

  void _remove(_Bubble bubble) {
    if (!mounted) return;
    setState(() => _bubbles.remove(bubble));
  }

  void _jumpToEnd() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  void _onTextChanged() {
    _restartIdle();
    if (mounted) setState(() {});
  }

  void _restartIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!widget.open) return;
    _idleTimer = Timer(PartyChatLayer.idleClose, () {
      if (mounted && widget.open && _field.text.trim().isEmpty) {
        widget.onClose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(partyChannelProvider.select((s) => s.messages));
    return widget.open
        ? _buildOpen(context, messages)
        : _buildBubbles(messages);
  }

  Widget _buildBubbles(List<PartyChatEntry> messages) {
    final byKey = {for (final entry in messages) entry.key: entry};
    // Le bolle non prendono i clic: sotto c'è il film.
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final bubble in _bubbles)
            if (byKey[bubble.key] case final entry?)
              AnimatedChatBubble(
                key: ValueKey('party-chat-bubble-${bubble.key}'),
                entry: entry,
                leaving: bubble.leaving,
                onGone: () => _remove(bubble),
              ),
        ],
      ),
    );
  }

  // Parte aperta: Task 5.
  Widget _buildOpen(BuildContext context, List<PartyChatEntry> messages) =>
      const SizedBox.shrink();
}

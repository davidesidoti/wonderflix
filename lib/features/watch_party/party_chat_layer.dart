import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/party_channel/party_channel_models.dart';
import '../../l10n/gen/app_localizations.dart';
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
    required this.focusNode,
    required this.onOpen,
    required this.onClose,
  });

  final bool open;

  /// Focus del campo. È di chi monta la chat (che lo crea e lo distrugge):
  /// `PlayerScreen` lo rimette a fuoco se un tasto arriva a chat aperta
  /// mentre il campo non ce l'ha (spec E §11).
  final FocusNode focusNode;

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

  /// Opacità del fondo dello storico.
  static const _historyAlpha = 0.55;

  late final PartyChannel _channel;
  late final StreamSubscription<PartyChatEntry> _arrivals;
  final _bubbles = <_Bubble>[];
  final _field = TextEditingController();
  final _scroll = ScrollController();
  Timer? _idleTimer;

  /// Esito dell'ultimo invio non riuscito: la riga rossa sotto il campo.
  PartyChatSendResult? _error;

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
      // Con un menu o un dialogo sopra il player il focus resta a loro:
      // chiusi, torna al player e il primo tasto lo riporta al campo.
      if (ModalRoute.isCurrentOf(context) ?? true) {
        widget.focusNode.requestFocus();
      }
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
    // Il tasto dopo un errore toglie la riga rossa.
    if (mounted) setState(() => _error = null);
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

  Future<void> _submit(String value) async {
    final text = normalizeChatText(value);
    _field.clear();
    if (text.isEmpty) {
      widget.onClose();
      return;
    }
    final result = await _channel.sendChat(text);
    if (!mounted || result == PartyChatSendResult.sent) return;
    // Non inviato: il testo torna nel campo (se intanto non se n'è scritto
    // altro) e la chat si riapre, con la riga rossa (spec E §9.4). La riga
    // si imposta dopo il testo: rimetterlo passa da `_onTextChanged`.
    if (_field.text.isEmpty) {
      _field.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    setState(() => _error = result);
    if (!widget.open) widget.onOpen();
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

  Widget _buildOpen(BuildContext context, List<PartyChatEntry> messages) {
    final l = AppLocalizations.of(context);
    final length = chatTextLength(_field.text);
    final error = _error;
    final maxHistory = MediaQuery.sizeOf(context).height *
        PartyChatLayer.historyHeightFraction;
    return Listener(
      // La rotella sopra la chat aperta non cambia il volume: scorre lo
      // storico (che, più interno, si registra prima) o non fa nulla.
      onPointerSignal: (event) => GestureBinding.instance.pointerSignalResolver
          .register(event, (_) {}),
      child: MouseRegion(
        onHover: (_) => _restartIdle(),
        child: SizedBox(
          width: PartyChatBubble.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (messages.isNotEmpty)
                Container(
                  key: const Key('party-chat-history'),
                  constraints: BoxConstraints(maxHeight: maxHistory),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: WfColors.bg.withValues(alpha: _historyAlpha),
                    borderRadius:
                        BorderRadius.circular(PartyChatBubble.radius),
                  ),
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: messages.length,
                    itemBuilder: (context, index) => Padding(
                      key: ValueKey('party-chat-line-${messages[index].key}'),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      child: PartyChatMessage(entry: messages[index]),
                    ),
                  ),
                ),
              const SizedBox(height: PartyChatBubble.gap),
              TextField(
                key: const Key('party-chat-field'),
                controller: _field,
                focusNode: widget.focusNode,
                style: partyChatTextStyle,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                inputFormatters: const [ChatLengthFormatter()],
                // Il campo resta a fuoco: Invio lo svuota e si continua a
                // scrivere.
                onEditingComplete: () {},
                onSubmitted: (value) => unawaited(_submit(value)),
                // Un clic sui controlli non gli toglie il focus; il clic sul
                // film chiude la chat (lo fa `PlayerScreen`).
                onTapOutside: (_) {},
                decoration:
                    InputDecoration(hintText: l.partyChatHint, isDense: true),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    error == PartyChatSendResult.rateLimited
                        ? l.partyChatTooMany
                        : l.partyChatNotSent,
                    style:
                        const TextStyle(color: WfColors.error, fontSize: 12),
                  ),
                )
              else if (length >= PartyChatLayer.counterFrom)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$length/$maxChatLength',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        color: WfColors.creamMuted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

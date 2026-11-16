import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_menus.dart';
import 'ask_parts.dart';
import 'tonight_controller.dart';
import 'tonight_logic.dart';

/// I filtri di Stasera e della sala del Match come una frase (spec §3): ogni
/// parola che si cambia apre un menu. Con [onChanged] `null` è sola lettura.
class AskSentence extends ConsumerWidget {
  const AskSentence({
    super.key,
    required this.filters,
    required this.voice,
    this.onChanged,
    this.fontSize = 21,
  });

  final TonightFilters filters;
  final AskVoice voice;
  final ValueChanged<TonightFilters>? onChanged;
  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final onChanged = this.onChanged;
    final genres = <String>[];
    if (onChanged != null) {
      // Un genere che non c'è più torna a "Tutti i generi" (decisione 8 del
      // piano 19c); vale anche per la sala del match.
      ref.listen(tonightGenresProvider(filters.type), (_, next) {
        final list = next.value;
        final genre = filters.genre;
        if (genre != null && list != null && !list.contains(genre)) {
          onChanged(filters.copyWith(genre: null));
        }
      });
      genres.addAll(
        ref.watch(tonightGenresProvider(filters.type)).value ?? const [],
      );
    }
    final style = TextStyle(
      fontSize: fontSize,
      height: 1.25,
      color: WfColors.creamMuted,
    );

    // Le parole della frase, ognuna un pezzo del Wrap: così va a capo come
    // un testo. La punteggiatura resta attaccata alla parola prima.
    final words = <Widget>[];
    var word = <Widget>[];
    void flush() {
      if (word.isEmpty) return;
      // La parola che si cambia può andare a capo dentro di sé (un genere
      // lungo nello stretto); la punteggiatura dopo di lei no.
      words.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final w in word) w is _Token ? Flexible(child: w) : w,
          ],
        ),
      );
      word = [];
    }

    for (final part in askParts(filters, voice, l)) {
      final slot = part.slot;
      if (slot == null) {
        for (final m in RegExp(r'\S+|\s+').allMatches(part.text)) {
          final chunk = m[0]!;
          // Stessa altezza delle parole sottolineate: la riga resta dritta.
          word.add(
            Padding(
              padding: const EdgeInsets.only(bottom: _underline),
              child: Text(chunk, style: style),
            ),
          );
          if (chunk.trim().isEmpty) flush();
        }
      } else {
        word.add(
          _Token(
            onChanged == null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: _underline),
                    child: Text(
                      part.text,
                      style: style.copyWith(color: WfColors.cream),
                    ),
                  )
                : _token(context, l, slot, part.text, style, genres, onChanged),
          ),
        );
      }
    }
    flush();
    return Wrap(
      runSpacing: fontSize * 0.35,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: words,
    );
  }

  /// Sottolineatura oro più lo spazio sopra.
  static const _underline = 4.0;

  static const _allGenres = Object();

  Widget _token(
    BuildContext context,
    AppLocalizations l,
    AskSlot slot,
    String text,
    TextStyle style,
    List<String> genres,
    ValueChanged<TonightFilters> onChanged,
  ) {
    final (Object current, List<Object> values) = switch (slot) {
      AskSlot.type => (filters.type, TonightType.values),
      AskSlot.duration => (filters.duration, TonightDuration.values),
      AskSlot.genre => (filters.genre ?? _allGenres, [_allGenres, ...genres]),
      AskSlot.rating => (filters.rating, TonightRating.values),
    };
    String label(Object value) =>
        askMenuLabel(slot, identical(value, _allGenres) ? null : value, l);
    return TvFocusBorder(
      borderRadius: BorderRadius.circular(2),
      child: PopupMenuButton<Object>(
        key: Key('ask-${slot.name}'),
        tooltip: '',
        popUpAnimationStyle: wfPopUpAnimation(context),
        position: PopupMenuPosition.under,
        onSelected: (value) {
          if (value == current) return;
          onChanged(switch (slot) {
            AskSlot.type => filters.copyWith(type: value as TonightType),
            AskSlot.duration => filters.copyWith(
              duration: value as TonightDuration,
            ),
            AskSlot.genre => filters.copyWith(
              genre: identical(value, _allGenres) ? null : value,
            ),
            AskSlot.rating => filters.copyWith(rating: value as TonightRating),
          });
        },
        itemBuilder: (context) => [
          for (final value in values)
            PopupMenuItem<Object>(
              value: value,
              child: Text(
                label(value),
                style: TextStyle(
                  color: value == current ? WfColors.gold : WfColors.cream,
                ),
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: WfColors.gold, width: 2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  text,
                  style: style.copyWith(
                    color: WfColors.cream,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                LucideIcons.chevronDown,
                size: 14,
                color: WfColors.gold,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Segna nel Wrap la parola che si cambia.
class _Token extends StatelessWidget {
  const _Token(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../core/jellyfin/item_models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../ui/form_factor.dart';
import '../../ui/tv_focusable.dart';
import '../../ui/wf_buttons.dart';
import '../../ui/wf_image.dart';
import '../home/hero_labels.dart';
import '../library/library_providers.dart';
import '../playback/play_launcher.dart';
import '../ratings/rating_widgets.dart';
import 'search_controller.dart' show PersonFacts;
import 'search_ranking.dart';

const _tabular = [FontFeature.tabularFigures()];
const _muted = TextStyle(color: WfColors.creamMuted);

/// [name] col pezzo di [highlightRange] sottolineato in oro.
Text highlightedName(
  String name,
  String term,
  TextStyle style, {
  int? maxLines,
  TextOverflow? overflow,
  TextAlign? textAlign,
}) {
  final range = highlightRange(name, term);
  if (range == null) {
    return Text(
      name,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
  final (start, end) = range;
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: name.substring(0, start)),
        TextSpan(
          text: name.substring(start, end),
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: WfColors.gold,
            decorationThickness: 2,
          ),
        ),
        TextSpan(text: name.substring(end)),
      ],
    ),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
  );
}

/// Il ruolo di una persona dal suo `Type` nel cast; `null` per gli altri.
/// Jellyfin non sa il genere della persona: niente "Attore"/"Attrice".
String? personRoleLabel(AppLocalizations l, String? type) => switch (type) {
  'Actor' || 'GuestStar' => l.searchRoleActor,
  'Director' => l.searchRoleDirector,
  'Writer' => l.searchRoleWriter,
  'Producer' => l.searchRoleProducer,
  'Composer' => l.searchRoleComposer,
  _ => null,
};

/// "Regia · Il cavaliere oscuro · 10 titoli", senza le parti che mancano.
String personFactsLine(AppLocalizations l, PersonFacts facts) => [
  ?personRoleLabel(l, facts.roleType),
  facts.knownFor.name,
  l.searchPersonTitles(facts.titles),
].join(' · ');

/// La carta del miglior risultato (spec §8.2): un titolo col fondale, o una
/// persona con la foto tonda.
class SearchBestCard extends ConsumerWidget {
  const SearchBestCard({
    super.key,
    required this.item,
    required this.term,
    this.facts,
    required this.onOpened,
  });

  final JellyfinItem item;
  final String term;

  /// I dati della persona, quando [item] è una persona.
  final PersonFacts? facts;

  /// Chiamata prima di ogni apertura (lo schermo salva il termine).
  final VoidCallback onOpened;

  void _open(BuildContext context) {
    onOpened();
    openItem(context, item, heroSource: 'search.best');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final urls = ref.watch(imageUrlsProvider);
    final compact = FormFactor.of(context).compact;
    final person = item.kind == ItemKind.person;
    final label = Text(
      l.searchBestLabel,
      style: const TextStyle(
        color: WfColors.gold,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );
    final name = highlightedName(
      item.name,
      term,
      WfText.display(compact ? 32 : 44),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final Widget content;
    if (person) {
      final facts = this.facts;
      content = Container(
        color: WfColors.surface,
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            _personPhoto(ref, item, 96),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  const SizedBox(height: 6),
                  name,
                  const SizedBox(height: 8),
                  // Una riga anche mentre i dati arrivano: la carta non salta.
                  Text(
                    facts == null ? ' ' : personFactsLine(l, facts),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _muted.copyWith(fontFeatures: _tabular),
                  ),
                  const SizedBox(height: 16),
                  WfButton.primary(
                    label: l.searchOpenDetails,
                    icon: LucideIcons.info,
                    onPressed: () => _open(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      final rating = item.communityRating;
      final overview = item.overview;
      // Alta almeno 240/280, di più se il testo non ci sta (nome su due
      // righe, testo grande).
      content = ConstrainedBox(
        constraints: BoxConstraints(minHeight: compact ? 240 : 280),
        child: Stack(
          alignment: Alignment.bottomLeft,
          children: [
            Positioned.fill(child: WfImage(image: urls.backdrop(item))),
            // Il velo da sinistra del carosello.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      WfColors.bg,
                      Color(0xCC0A0A0A),
                      Colors.transparent,
                    ],
                    stops: [0, 0.35, 0.75],
                  ),
                ),
              ),
            ),
            // Nello stretto il testo prende tutta la larghezza: velo dal basso.
            if (compact)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        WfColors.bg,
                        Color(0xBF0A0A0A),
                        Color(0x0D0A0A0A),
                      ],
                      stops: [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(16, 24, 16, 16)
                  : const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? double.infinity : 560,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    label,
                    const SizedBox(height: 6),
                    name,
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: [
                              item.kind == ItemKind.series
                                  ? l.navSeries
                                  : l.navMovies,
                              heroMeta(item, l),
                            ].where((part) => part.isNotEmpty).join(' · '),
                          ),
                          if (rating != null)
                            TextSpan(
                              text:
                                  '  ★ ${formatRatingAverage(rating, l.localeName)}',
                              style: const TextStyle(
                                color: WfColors.gold,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      style: _muted.copyWith(fontFeatures: _tabular),
                    ),
                    if (overview != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        overview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _muted.copyWith(height: 1.45),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        WfButton.primary(
                          label: l.actionPlay,
                          icon: LucideIcons.play,
                          onPressed: () {
                            onOpened();
                            unawaited(playItem(context, ref, item));
                          },
                        ),
                        WfButton.secondary(
                          label: l.searchOpenDetails,
                          icon: LucideIcons.info,
                          onPressed: () => _open(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: content,
    );
  }
}

/// La foto tonda di una persona.
Widget _personPhoto(WidgetRef ref, JellyfinItem person, double size) =>
    ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: WfImage(
          image: ref.watch(imageUrlsProvider).poster(person),
          fallbackIcon: LucideIcons.user,
        ),
      ),
    );

/// Le persone accanto al miglior risultato (desktop): al massimo sei righe.
class SearchPeopleList extends ConsumerWidget {
  const SearchPeopleList({
    super.key,
    required this.people,
    required this.facts,
    required this.term,
    required this.total,
    this.onSeeAll,
    required this.onOpened,
  });

  static const maxRows = 6;

  final List<JellyfinItem> people;

  /// I dati per id; `null` mentre arrivano.
  final Map<String, PersonFacts>? facts;
  final String term;
  final int total;
  final VoidCallback? onSeeAll;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final form = FormFactor.of(context);
    final onSeeAll = this.onSeeAll;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      l.searchPeople,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WfText.display(
                        form.tv ? 22 : (form.compact ? 26 : 30),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$total',
                    style: _muted.copyWith(
                      fontSize: 12.5,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
            if (onSeeAll != null && total > maxRows)
              TextButton(
                onPressed: onSeeAll,
                child: Text(l.searchSeeAllPeople),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (final person in people.take(maxRows))
          _PersonRow(
            key: ValueKey('person-${person.id}'),
            person: person,
            facts: facts?[person.id],
            term: term,
            onOpened: onOpened,
          ),
      ],
    );
  }
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({
    super.key,
    required this.person,
    required this.facts,
    required this.term,
    required this.onOpened,
  });

  final JellyfinItem person;
  final PersonFacts? facts;
  final String term;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final facts = this.facts;
    final role = facts == null ? null : personRoleLabel(l, facts.roleType);
    void open() {
      onOpened();
      openItem(context, person);
    }

    return TvFocusable(
      onActivate: open,
      child: InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          // Altezza fissa: le righe non saltano quando arrivano i dati.
          height: 60 * MediaQuery.textScalerOf(context).scale(1),
          child: Row(
            children: [
              _personPhoto(ref, person, 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    highlightedName(
                      person.name,
                      term,
                      const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Senza dati una riga vuota: il nome non si sposta.
                    Text.rich(
                      TextSpan(
                        children: [
                          if (facts == null) const TextSpan(text: ' '),
                          if (role != null) TextSpan(text: '$role · '),
                          if (facts != null)
                            TextSpan(
                              text: facts.knownFor.name,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _muted.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (facts != null) ...[
                const SizedBox(width: 12),
                Text(
                  l.searchPersonTitles(facts.titles),
                  style: _muted.copyWith(
                    fontSize: 12.5,
                    fontFeatures: _tabular,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Una persona nella fila del telefono e della TV: tondo 72, nome, titoli.
class SearchPersonTile extends ConsumerWidget {
  const SearchPersonTile({
    super.key,
    required this.person,
    this.facts,
    required this.term,
    required this.onOpened,
  });

  final JellyfinItem person;
  final PersonFacts? facts;
  final String term;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final facts = this.facts;
    void open() {
      onOpened();
      openItem(context, person);
    }

    return TvFocusable(
      onActivate: open,
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: open,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              width: 96,
              child: Column(
                children: [
                  _personPhoto(ref, person, 72),
                  const SizedBox(height: 8),
                  highlightedName(
                    person.name,
                    term,
                    const TextStyle(fontSize: 12.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    facts == null ? ' ' : l.searchPersonTitles(facts.titles),
                    style: _muted.copyWith(
                      fontSize: 11.5,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

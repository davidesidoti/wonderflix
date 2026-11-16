import 'package:flutter/widgets.dart';

import 'form_factor.dart';
import 'poster_card.dart' show catalogCellExtent;
import 'shimmer.dart';
import 'states.dart';

// Gli scheletri non scorrono (`NeverScrollableScrollPhysics`) e non prendono
// il controller principale della rotta (`primary: false`).

/// Riga di locandine (cast, "Simili") sotto la testata della scheda.
class DetailRowsSkeleton extends StatelessWidget {
  const DetailRowsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var row = 0; row < 2; row++) ...[
              const SkeletonBox(width: 200, height: 22),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                // Lista e non Row: in una finestra stretta le card escono
                // dal bordo invece di sbordare.
                child: ListView(
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                  for (var i = 0; i < 6; i++) ...[
                    const SkeletonBox(width: 130, height: 195),
                    const SizedBox(width: 16),
                  ],
                ]),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      );
}

/// Scheda del titolo in caricamento senza volo Hero: testata e righe.
class DetailSkeleton extends StatelessWidget {
  const DetailSkeleton({super.key, required this.headerHeight});

  final double headerHeight;

  @override
  Widget build(BuildContext context) => WfShimmer(
        child: ListView(
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: headerHeight,
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(32, 0, 32, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 420, height: 90),
                      SizedBox(height: 16),
                      SkeletonBox(width: 260, height: 14),
                      SizedBox(height: 12),
                      SkeletonBox(width: 560, height: 14),
                      SizedBox(height: 8),
                      SkeletonBox(width: 480, height: 14),
                      SizedBox(height: 20),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        SkeletonBox(width: 150, height: 44),
                        SizedBox(width: 12),
                        SkeletonBox(width: 150, height: 44),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
            const DetailRowsSkeleton(),
          ],
        ),
      );
}

/// Elenco degli episodi di una stagione.
class EpisodeListSkeleton extends StatelessWidget {
  const EpisodeListSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    // Come EpisodeTile: nello stretto miniatura da 120 e margini da 16.
    final compact = FormFactor.of(context).compact;
    return WfShimmer(
        child: Column(children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 32, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                      width: compact ? 120 : 200,
                      height: compact ? 68 : 112,
                      radius: 5),
                  SizedBox(width: compact ? 12 : 16),
                  const Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 240, height: 14),
                        SizedBox(height: 8),
                        SkeletonBox(width: 120, height: 12),
                        SizedBox(height: 10),
                        SkeletonBox(width: 420, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ]),
      );
  }
}

/// Griglia di locandine (Catalogo, La mia lista, filmografia): stessa
/// griglia delle pagine vere.
class PosterGridSkeleton extends StatelessWidget {
  const PosterGridSkeleton(
      {super.key,
      this.count = 12,
      this.shrinkWrap = false,
      this.catalogSide});

  final int count;

  /// `true` dentro un'altra lista (filmografia della persona).
  final bool shrinkWrap;

  /// Nel catalogo: il margine laterale della pagina, e celle alte come
  /// quelle delle card vere (`catalogCellExtent`), perché le righe non
  /// saltino all'arrivo dei dati.
  final double? catalogSide;

  @override
  Widget build(BuildContext context) {
    final side = catalogSide;
    Widget grid(double? cellExtent) => GridView.builder(
          primary: false,
          shrinkWrap: shrinkWrap,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(side ?? 32, 0, side ?? 32, 24),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 24,
            crossAxisSpacing: 16,
            childAspectRatio: 0.55,
            mainAxisExtent: cellExtent,
          ),
          itemCount: count,
          itemBuilder: (context, i) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SkeletonBox()),
              SizedBox(height: 8),
              SkeletonBox(width: 110, height: 12),
              SizedBox(height: 6),
              SkeletonBox(width: 40, height: 10),
            ],
          ),
        );
    return WfShimmer(
      child: side == null
          ? grid(null)
          : LayoutBuilder(
              builder: (context, constraints) => grid(catalogCellExtent(
                  constraints.maxWidth - 2 * side,
                  MediaQuery.textScalerOf(context)))),
    );
  }
}

/// Risultati della ricerca: una sezione di locandine.
class SearchResultsSkeleton extends StatelessWidget {
  const SearchResultsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => WfShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 140, height: 24),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 24,
              children: [
                for (var i = 0; i < 6; i++)
                  const SkeletonBox(width: 150, height: 225),
              ],
            ),
          ],
        ),
      );
}

/// Pagina della persona senza volo Hero: foto, nome, biografia.
class PersonSkeleton extends StatelessWidget {
  const PersonSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Come PersonScreen: nello stretto la foto sta sopra il nome.
    if (FormFactor.of(context).compact) {
      return const WfShimmer(
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 32, 32, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SkeletonBox(width: 140, height: 210, radius: 8),
              ),
              SizedBox(height: 16),
              SkeletonBox(height: 32),
              SizedBox(height: 16),
              SkeletonBox(height: 14),
              SizedBox(height: 8),
              SkeletonBox(height: 14),
              SizedBox(height: 8),
              SkeletonBox(height: 14),
            ],
          ),
        ),
      );
    }
    return const WfShimmer(
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, 32, 32, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 200, height: 300, radius: 8),
              SizedBox(width: 32),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 320, height: 44),
                  SizedBox(height: 16),
                  SkeletonBox(width: 520, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 480, height: 14),
                  SizedBox(height: 8),
                  SkeletonBox(width: 500, height: 14),
                ],
              ),
            ],
          ),
        ),
      );
  }
}

/// Righe di un pannello della shell (Amici, Notifiche, Consiglia) mentre
/// carica: un cerchio da 32 e due barre, come le righe vere.
class PanelRowsSkeleton extends StatelessWidget {
  const PanelRowsSkeleton({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) => WfShimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            children: [
              for (var i = 0; i < rows; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SkeletonBox(width: 32, height: 32, radius: 16),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 140, height: 14),
                            SizedBox(height: 8),
                            SkeletonBox(width: 90, height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

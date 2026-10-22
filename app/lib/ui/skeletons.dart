import 'package:flutter/widgets.dart';

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
                child: Row(children: [
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
  Widget build(BuildContext context) => WfShimmer(
        child: Column(children: [
          for (var i = 0; i < count; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 200, height: 112, radius: 5),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 240, height: 14),
                      SizedBox(height: 8),
                      SkeletonBox(width: 120, height: 12),
                      SizedBox(height: 10),
                      SkeletonBox(width: 420, height: 12),
                    ],
                  ),
                ],
              ),
            ),
        ]),
      );
}

/// Griglia di locandine (Catalogo, La mia lista, filmografia): stessa
/// griglia delle pagine vere.
class PosterGridSkeleton extends StatelessWidget {
  const PosterGridSkeleton({super.key, this.count = 12, this.shrinkWrap = false});

  final int count;

  /// `true` dentro un'altra lista (filmografia della persona).
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) => WfShimmer(
        child: GridView.builder(
          primary: false,
          shrinkWrap: shrinkWrap,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 24,
            crossAxisSpacing: 16,
            childAspectRatio: 0.55,
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
        ),
      );
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
  Widget build(BuildContext context) => const WfShimmer(
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

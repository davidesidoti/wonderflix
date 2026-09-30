import 'package:flutter/material.dart';

import '../core/jellyfin/image_urls.dart';
import '../ui/wf_image.dart';
import 'motion.dart';

/// Tag del volo Hero: il titolo e la card da cui parte (riga o griglia +
/// posizione, dentro l'istanza della pagina: [WfHeroScope.source]). Due
/// card dello stesso titolo nella stessa pagina non vanno in conflitto
/// (spec C §6.2).
@immutable
class WfHeroTag {
  const WfHeroTag(this.itemId, this.source);

  final String itemId;
  final String source;

  @override
  bool operator ==(Object other) =>
      other is WfHeroTag && other.itemId == itemId && other.source == source;

  @override
  int get hashCode => Object.hash(itemId, source);

  @override
  String toString() => 'WfHeroTag($itemId, $source)';
}

/// Istanza della pagina che contiene le card (la `pageKey` di go_router:
/// unica per ogni `push`; con `go` è il percorso, ma allora la pagina è
/// l'unica della pila). L'`HeroController` fa volare **tutti** i tag in
/// comune tra la pagina in cima e quella sotto: con le sorgenti legate
/// all'istanza, le card di una pagina X hanno tag di X, e la testata di X
/// ha il tag della card della pagina da cui è stata aperta. Due pagine
/// vicine hanno quindi in comune solo il tag del lancio, anche quando
/// mostrano gli stessi titoli (A → Simili B → Simili A′, A → cast →
/// filmografia A′).
class WfHeroScope extends InheritedWidget {
  const WfHeroScope({super.key, required this.id, required super.child});

  final String id;

  /// Sorgente [local] (es. `similar.3`) resa unica per la pagina. Senza
  /// scope (test che montano una schermata da sola) resta [local].
  static String source(BuildContext context, String local) {
    final id = context.dependOnInheritedWidgetOfExactType<WfHeroScope>()?.id;
    return id == null ? local : '$id|$local';
  }

  @override
  bool updateShouldNotify(WfHeroScope oldWidget) => oldWidget.id != id;
}

/// Dati passati alla pagina aperta da una card (`extra` di go_router): il
/// tag e le immagini già note, per disegnare subito la destinazione del volo
/// mentre la pagina carica.
@immutable
class HeroLaunch {
  const HeroLaunch({required this.tag, this.image, this.fallback, this.title});

  final WfHeroTag tag;

  /// Sfondo (scheda) o foto (persona).
  final ImageRef? image;

  /// Locandina, se manca lo sfondo.
  final ImageRef? fallback;
  final String? title;
}

/// Chiave dell'immagine in volo (per riconoscerla nei test).
const wfHeroFlightKey = ValueKey<String>('wf-hero-flight');

/// Volo con dissolvenza: parte dall'immagine della card e arriva a quella
/// della pagina (da una locandina 2:3 a uno sfondo 16:9). Gli angoli passano
/// da quelli della sorgente a quelli della destinazione (cerchio del cast →
/// foto della persona, card → sfondo senza angoli): i ritagli di [WfHero]
/// stanno dentro l'`Hero`, qui si tolgono e se ne disegna uno solo.
/// Tornando indietro fa il percorso inverso.
Widget wfHeroFlight(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final from = _WfHeroClip.split((fromHeroContext.widget as Hero).child);
  final to = _WfHeroClip.split((toHeroContext.widget as Hero).child);
  final push = direction == HeroFlightDirection.push;
  final card = push ? from : to;
  final page = push ? to : from;
  return AnimatedBuilder(
    key: wfHeroFlightKey,
    animation: animation,
    builder: (context, _) {
      final t = WfMotion.emphasized.transform(animation.value.clamp(0.0, 1.0));
      return ClipRRect(
        borderRadius: BorderRadius.lerp(card.radius, page.radius, t)!,
        // La card resta piena sotto; la pagina le sfuma sopra con i
        // segnaposto trasparenti: se lo sfondo non è ancora scaricato si
        // continua a vedere l'immagine del titolo.
        child: Stack(
          fit: StackFit.expand,
          children: [
            card.child,
            Opacity(
              opacity: t,
              child: TransparentPlaceholders(child: page.child),
            ),
          ],
        ),
      );
    },
  );
}

/// [Hero] con [wfHeroFlight], solo se c'è un tag e le animazioni sono
/// complete; altrimenti il solo [child]. Il ritaglio con [borderRadius] c'è
/// sempre (anche con le animazioni ridotte) e sta dentro l'`Hero`, così il
/// volo sa da che forma parte e a che forma arriva.
class WfHero extends StatelessWidget {
  const WfHero({
    super.key,
    required this.tag,
    this.borderRadius = cardRadius,
    required this.child,
  });

  /// Angoli dell'immagine delle card (locandina e orizzontale).
  static const cardRadius = BorderRadius.all(Radius.circular(5));

  final WfHeroTag? tag;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final heroTag = tag;
    final clipped = _WfHeroClip(borderRadius: borderRadius, child: child);
    if (heroTag == null || WfMotion.of(context).isReduced) return clipped;
    return Hero(
        tag: heroTag, flightShuttleBuilder: wfHeroFlight, child: clipped);
  }
}

/// Ritaglio di [WfHero]; [wfHeroFlight] lo riconosce e lo sostituisce con il
/// proprio.
class _WfHeroClip extends StatelessWidget {
  const _WfHeroClip({required this.borderRadius, required this.child});

  final BorderRadius borderRadius;
  final Widget child;

  /// Angoli e contenuto del figlio di un `Hero`: senza [_WfHeroClip] (un
  /// `Hero` qualunque) angoli retti.
  static ({BorderRadius radius, Widget child}) split(Widget heroChild) =>
      heroChild is _WfHeroClip
          ? (radius: heroChild.borderRadius, child: heroChild.child)
          : (radius: BorderRadius.zero, child: heroChild);

  @override
  Widget build(BuildContext context) => borderRadius == BorderRadius.zero
      ? child
      : ClipRRect(borderRadius: borderRadius, child: child);
}

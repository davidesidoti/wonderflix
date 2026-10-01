import 'package:flutter/widgets.dart';

/// Quanto si muove l'interfaccia (spec C §4.2).
enum MotionLevel { full, reduced }

/// Token di movimento: durate, curve e livello. I widget li leggono con
/// [WfMotion.of]; nessuna durata scritta a mano (il player escluso).
@immutable
class WfMotion {
  const WfMotion(this.level);

  final MotionLevel level;

  /// Dissolvenze brevi, uscite, tutto il movimento in modalità ridotta.
  static const fast = Duration(milliseconds: 150);

  /// Anteprima, sottolineatura della barra, scheletro → contenuto.
  static const medium = Duration(milliseconds: 300);

  /// Entrate di righe e card.
  static const slow = Duration(milliseconds: 450);

  /// Volo dell'immagine card → scheda.
  static const hero = Duration(milliseconds: 420);

  /// Diapositive del carosello.
  static const crossfade = Duration(milliseconds: 900);

  /// Ritardo tra elementi della stessa entrata.
  static const stagger = Duration(milliseconds: 60);

  /// Curva principale: entrate, voli, anteprima.
  static const Curve emphasized = Cubic(0.2, 0.8, 0.2, 1);

  /// Dissolvenze.
  static const Curve standard = Curves.easeInOut;

  /// Entrate "volanti" e apertura dell'anteprima, con un leggero rimbalzo.
  static const Curve bounce = Cubic(0.2, 0.9, 0.25, 1.2);

  /// Parti brevi che entrano o crescono: rallentano arrivando (pagina che
  /// entra nel "fade through", prima metà del "pop" di cuore e spunta).
  static const Curve decelerate = Curves.easeOut;

  /// Parti brevi che escono: accelerano andando via (pagina che esce nel
  /// "fade through").
  static const Curve accelerate = Curves.easeIn;

  /// [accelerate] per le uscite che fanno andare l'animazione all'indietro,
  /// da 1 a 0 (`switchOutCurve` di `AnimatedSwitcher`, `reverseCurve` di
  /// `CurvedAnimation`). Lì la curva si percorre al contrario: [accelerate]
  /// sembrerebbe rallentare (veloce all'inizio, lenta alla fine). Girata,
  /// l'uscita parte piano e accelera andando via, come vuole la spec D §6.1.
  static const Curve accelerateReverse = FlippedCurve(accelerate);

  bool get isReduced => level == MotionLevel.reduced;

  /// [full] con le animazioni complete, [reduced] con quelle ridotte.
  T pick<T>({required T full, required T reduced}) =>
      isReduced ? reduced : full;

  /// Durata di un effetto: con il livello ridotto diventa [fast].
  Duration duration(Duration full) => isReduced ? fast : full;

  /// Livello più vicino a [context]. Senza [WfMotionScope] (test che
  /// montano l'app a mano) è ridotto: niente animazioni lunghe o infinite.
  static WfMotion of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WfMotionScope>()?.motion ??
      const WfMotion(MotionLevel.reduced);

  @override
  bool operator ==(Object other) => other is WfMotion && other.level == level;

  @override
  int get hashCode => level.hashCode;

  @override
  String toString() => 'WfMotion(${level.name})';
}

/// Rende disponibile [WfMotion] a tutto l'albero sotto di sé.
class WfMotionScope extends InheritedWidget {
  const WfMotionScope({super.key, required this.motion, required super.child});

  final WfMotion motion;

  @override
  bool updateShouldNotify(WfMotionScope oldWidget) =>
      oldWidget.motion != motion;
}

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../ui/form_factor.dart';

/// Gli stati di una spia della cabina.
enum LampState { ok, attention, broken, off }

Color lampColor(LampState s) => switch (s) {
      LampState.ok => WfColors.online,
      LampState.attention => WfColors.gold,
      LampState.broken => WfColors.error,
      LampState.off => const Color(0xFF444444),
    };

/// Una spia: pallino con l'alone del suo colore (spenta: senza alone).
class WfLamp extends StatelessWidget {
  const WfLamp({
    super.key,
    required this.state,
    required this.label,
    this.size = 9,
  });

  final LampState state;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = lampColor(state);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: state == LampState.off
                ? null
                : [BoxShadow(color: color, blurRadius: size * 0.8)],
          ),
          child: SizedBox.square(dimension: size),
        ),
      ),
    );
  }
}

/// Il titolo di una scheda: il nome, il conteggio e le azioni a destra
/// (andate a capo nel layout stretto).
class AdminTabTitle extends StatelessWidget {
  const AdminTabTitle({
    super.key,
    required this.title,
    this.count,
    this.actions = const [],
  });

  final String title;
  final int? count;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final head = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: Text(title, style: WfText.display(30))),
        if (count != null) ...[
          const SizedBox(width: 10),
          Text('$count', style: _mutedStyle(13)),
        ],
      ],
    );
    if (actions.isEmpty) return head;
    if (FormFactor.of(context).compact) {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [head, ...actions],
      );
    }
    return Row(
      children: [
        Flexible(child: head),
        const Spacer(),
        Wrap(spacing: 8, children: actions),
      ],
    );
  }
}

/// Titolo di una sezione di una scheda ("In riproduzione", "Collegati"…).
class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle({
    super.key,
    required this.title,
    this.count,
    this.note,
    this.action,
  });

  final String title;
  final int? count;
  final String? note;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(child: Text(title, style: WfText.display(20))),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text('$count', style: _mutedStyle(12)),
            ],
            if (note != null) ...[
              const SizedBox(width: 8),
              Flexible(child: Text(note!, style: _mutedStyle(12))),
            ],
            if (action != null) ...[const Spacer(), action!],
          ],
        ),
      );
}

/// Un contenitore con il bordo e un filo da 1 px tra i figli.
class AdminList extends StatelessWidget {
  const AdminList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: WfColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  const SizedBox(
                    height: 1,
                    width: double.infinity,
                    // La chiave sta sul figlio: nella Column sarebbe duplicata.
                    child: ColoredBox(
                      key: ValueKey('admin-list-divider'),
                      color: WfColors.border,
                    ),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      );
}

/// Una barra a fotogrammi di pellicola; [progress] null = tutti vuoti.
class FilmStripBar extends StatelessWidget {
  const FilmStripBar({
    super.key,
    required this.progress,
    this.segments = 12,
    this.height = 6,
  });

  final double? progress;
  final int segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final value = progress ?? 0;
    // NaN (una divisione che non doveva esserci) vale zero fotogrammi.
    final filled = value.isNaN ? 0 : (value.clamp(0.0, 1.0) * segments).floor();
    return Row(
      children: [
        for (var i = 0; i < segments; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: Container(
              key: i < filled ? const ValueKey('film-strip-filled') : null,
              height: height,
              decoration: BoxDecoration(
                color: i < filled ? WfColors.gold : WfColors.border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

TextStyle _mutedStyle(double size) =>
    TextStyle(fontFamily: 'Inter', fontSize: size, color: WfColors.creamMuted);

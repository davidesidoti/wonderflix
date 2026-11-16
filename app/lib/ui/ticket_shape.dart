import 'package:flutter/material.dart';

/// Raggio dei mezzi cerchi dello strappo.
const ticketNotchRadius = 7.0;

/// La sagoma del biglietto: rettangolo arrotondato con i due mezzi cerchi
/// dello strappo tagliati via, così si vede il fondo qualunque sia.
/// [TicketClipper.vertical]: strappo verticale alla larghezza [at], tacche in
/// alto e in basso. [TicketClipper.horizontal]: strappo orizzontale
/// all'altezza [at], tacche a sinistra e a destra.
class TicketClipper extends CustomClipper<Path> {
  const TicketClipper.vertical(this.at, {this.radius = 8}) : _vertical = true;
  const TicketClipper.horizontal(this.at, {this.radius = 8})
      : _vertical = false;

  final double at;

  /// Raggio degli angoli.
  final double radius;
  final bool _vertical;

  @override
  Path getClip(Size size) {
    final notches = Path();
    for (final center in _vertical
        ? [Offset(at, 0), Offset(at, size.height)]
        : [Offset(0, at), Offset(size.width, at)]) {
      notches.addOval(Rect.fromCircle(center: center, radius: ticketNotchRadius));
    }
    return Path.combine(
      PathOperation.difference,
      Path()
        ..addRRect(RRect.fromRectAndRadius(
            Offset.zero & size, Radius.circular(radius))),
      notches,
    );
  }

  @override
  bool shouldReclip(TicketClipper old) =>
      old.at != at || old.radius != radius || old._vertical != _vertical;
}

/// La linea tratteggiata dello strappo, tra i due mezzi cerchi: verticale
/// alla larghezza [at], o orizzontale all'altezza [at].
class TicketTearPainter extends CustomPainter {
  const TicketTearPainter.vertical(this.at) : _vertical = true;
  const TicketTearPainter.horizontal(this.at) : _vertical = false;

  final double at;
  final bool _vertical;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF333333)
      ..strokeWidth = 1;
    final length = _vertical ? size.height : size.width;
    for (var d = 9.0; d + 4 < length - 7; d += 7) {
      canvas.drawLine(
        _vertical ? Offset(at + 0.5, d) : Offset(d, at + 0.5),
        _vertical ? Offset(at + 0.5, d + 4) : Offset(d + 4, at + 0.5),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(TicketTearPainter old) =>
      old.at != at || old._vertical != _vertical;
}

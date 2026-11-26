import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:folio/theme/folio_theme.dart';

enum FolioNavGlyph { home, movie, series, create, logs, settings, logout }

class FolioNavIcon extends StatelessWidget {
  const FolioNavIcon(this.glyph, {super.key, this.active = false});

  final FolioNavGlyph glyph;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = switch (glyph) {
      FolioNavGlyph.logout => FolioColors.danger,
      FolioNavGlyph.create || FolioNavGlyph.logs || FolioNavGlyph.settings => FolioColors.inkMuted,
      _ => FolioColors.copper,
    };
    final background = switch (glyph) {
      FolioNavGlyph.logout => const Color(0x1EE07A6B),
      FolioNavGlyph.create || FolioNavGlyph.logs || FolioNavGlyph.settings => const Color(0x0AFFFFFF),
      _ => active ? const Color(0x47D4A574) : const Color(0x1AD4A574),
    };
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: CustomPaint(
        size: const Size.square(20),
        painter: _SvgIconPainter(_paths(glyph), color),
      ),
    );
  }
}

List<String> _paths(FolioNavGlyph glyph) {
  return switch (glyph) {
    FolioNavGlyph.home => const [
      'M4 10.5L12 4l8 6.5V20a1 1 0 0 1-1 1h-5.5v-6h-3v6H5a1 1 0 0 1-1-1v-9.5z',
    ],
    FolioNavGlyph.series => const [
      'M5 8h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z',
      'M8 3l2.5 3M16 3l-2.5 3',
      'M8 12h8',
    ],
    FolioNavGlyph.movie => const [
      'M5 5h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z',
      'M8 5v14M16 5v14M3 10h18M3 14h18',
    ],
    FolioNavGlyph.create => const ['M12 5v14M5 12h14'],
    FolioNavGlyph.logs => const [
      'M6 3h9l3 3v15H6V3z',
      'M15 3v3h3',
      'M9 12h6',
      'M9 16h4',
    ],
    FolioNavGlyph.settings => const [
      'M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z',
      'M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H8a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V8c0 .7.4 1.3 1 1.5H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
    ],
    FolioNavGlyph.logout => const [
      'M10 7V5a2 2 0 0 1 2-2h7v18h-7a2 2 0 0 1-2-2v-2',
      'M15 12H4m0 0l3-3m-3 3l3 3',
    ],
  };
}

class _SvgIconPainter extends CustomPainter {
  const _SvgIconPainter(this.paths, this.color);

  final List<String> paths;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final source in paths) {
      canvas.drawPath(parseSvgPath(source), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SvgIconPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.paths != paths;
  }
}

Path parseSvgPath(String source) {
  final path = Path();
  final tokens = RegExp(r'[MmLlHhVvAaCcZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?').allMatches(source).map((match) => match.group(0)!).toList();
  var index = 0;
  var command = '';
  var current = Offset.zero;
  var start = Offset.zero;

  bool isCommand(String token) => token.length == 1 && RegExp(r'[A-Za-z]').hasMatch(token);
  double read() => double.parse(tokens[index++]);

  while (index < tokens.length) {
    if (isCommand(tokens[index])) command = tokens[index++];
    switch (command) {
      case 'M':
        current = Offset(read(), read());
        path.moveTo(current.dx, current.dy);
        start = current;
        command = 'L';
      case 'm':
        current += Offset(read(), read());
        path.moveTo(current.dx, current.dy);
        start = current;
        command = 'l';
      case 'L':
        current = Offset(read(), read());
        path.lineTo(current.dx, current.dy);
      case 'l':
        current += Offset(read(), read());
        path.lineTo(current.dx, current.dy);
      case 'H':
        current = Offset(read(), current.dy);
        path.lineTo(current.dx, current.dy);
      case 'h':
        current += Offset(read(), 0);
        path.lineTo(current.dx, current.dy);
      case 'V':
        current = Offset(current.dx, read());
        path.lineTo(current.dx, current.dy);
      case 'v':
        current += Offset(0, read());
        path.lineTo(current.dx, current.dy);
      case 'C':
        final c1 = Offset(read(), read());
        final c2 = Offset(read(), read());
        current = Offset(read(), read());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
      case 'c':
        final c1 = current + Offset(read(), read());
        final c2 = current + Offset(read(), read());
        current += Offset(read(), read());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
      case 'A':
      case 'a':
        final rx = read().abs();
        final ry = read().abs();
        final rotation = read() * math.pi / 180;
        final large = read() != 0;
        final sweep = read() != 0;
        final end = command == 'A' ? Offset(read(), read()) : current + Offset(read(), read());
        path.arcToPoint(end, radius: Radius.elliptical(rx, ry), rotation: rotation, largeArc: large, clockwise: sweep);
        current = end;
      case 'Z':
      case 'z':
        path.close();
        current = start;
      default:
        index = tokens.length;
    }
  }
  return path;
}

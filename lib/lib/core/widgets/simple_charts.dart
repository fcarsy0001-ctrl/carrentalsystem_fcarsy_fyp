
import 'dart:math' as math;

import 'package:flutter/material.dart';

class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.values,
    this.height = 120,
  });

  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarPainter(values: values, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxV = values.reduce(math.max);
    final paint = Paint()
      ..color = color.withOpacity(0.85)
      ..style = PaintingStyle.fill;

    final bg = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    // background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      bg,
    );

    final n = values.length;
    final gap = 4.0;
    final barW = math.max(2.0, (size.width - gap * (n + 1)) / n);
    final baseY = size.height - 10;


    for (int i = 0; i < n; i++) {
      final v = values[i];

      final h = (maxV == 0) ? 0.0 : (v / maxV) * (size.height - 22);
      final left = gap + i * (barW + gap);
      final rect = Rect.fromLTWH(left, baseY - h, barW, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

class SimpleLineChart extends StatelessWidget {
  const SimpleLineChart({
    super.key,
    required this.values,
    this.height = 140,
  });

  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LinePainter(values: values, color: Theme.of(context).colorScheme.secondary),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);

    final bg = Paint()
      ..color = color.withOpacity(0.10)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      bg,
    );

    final path = Path();
    final n = values.length;
    final padX = 12.0;
    final padY = 12.0;
    final w = math.max(1.0, size.width - padX * 2);
    final h = math.max(1.0, size.height - padY * 2);

    double norm(double v) {
      if (maxV == minV) return 0.5;
      return (v - minV) / (maxV - minV);
    }

    for (int i = 0; i < n; i++) {
      final x = padX + (i / math.max(1, n - 1)) * w;
      final y = padY + (1 - norm(values[i])) * h;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final line = Paint()
      ..color = color.withOpacity(0.9)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, line);

    // points
    final dot = Paint()..color = color.withOpacity(0.95);
    for (int i = 0; i < n; i++) {
      final x = padX + (i / math.max(1, n - 1)) * w;
      final y = padY + (1 - norm(values[i])) * h;
      canvas.drawCircle(Offset(x, y), 2.8, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

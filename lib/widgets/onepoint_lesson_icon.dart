import 'package:flutter/material.dart';
import '../config/onepoint_design.dart';

/// An outlined lesson card using the supplied design's white/lime icon style.
class OnepointLessonIcon extends StatelessWidget {
  const OnepointLessonIcon({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 26, height: 28, child: CustomPaint(painter: _LessonPainter()));
}

class _LessonPainter extends CustomPainter {
  const _LessonPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 4, 18, 21), const Radius.circular(4)),
        line);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(9, 2, 8, 5), const Radius.circular(2)),
        Paint()..color = OnepointDesign.background);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(9, 2, 8, 5), const Radius.circular(2)),
        line);
    canvas.drawLine(const Offset(9, 19), const Offset(17, 19), line);
    canvas.drawPath(
        Path()
          ..moveTo(11, 10)
          ..lineTo(16, 13)
          ..lineTo(11, 16)
          ..close(),
        Paint()..color = OnepointDesign.lime);
  }

  @override
  bool shouldRepaint(covariant _LessonPainter oldDelegate) => false;
}

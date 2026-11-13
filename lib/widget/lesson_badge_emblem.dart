import 'package:flutter/material.dart';

import '../config/signature_badge_palette.dart';

/// A coach's signature keeps the same visual identity across lesson awards.
class LessonBadgeEmblem extends StatelessWidget {
  final String identity;
  final String sport;
  final double size;
  final int? colorIndex;

  const LessonBadgeEmblem({
    super.key,
    required this.identity,
    required this.sport,
    this.size = 88,
    this.colorIndex,
  });

  Color get accent => signatureBadgeColor(colorIndex, legacyIdentity: identity);

  Widget _icon(IconData icon) => Icon(icon, color: accent, size: size * .31);

  Widget _emoji(String emoji) => Text(
        emoji,
        style: TextStyle(fontSize: size * .28, height: 1),
      );

  Widget _lineArt(_SportLineArt art) => SizedBox.square(
        dimension: size * .34,
        child: CustomPaint(
          painter: _SportLineArtPainter(art: art, color: accent),
        ),
      );

  Widget get _sportMark {
    final normalized = sport.trim();
    final mark = switch (normalized) {
      '축구' || '풋살' => _icon(Icons.sports_soccer),
      '농구' => _icon(Icons.sports_basketball),
      '테니스' => _lineArt(_SportLineArt.tennisRacket),
      '배드민턴' => _emoji('🏸'),
      '클라이밍' => _emoji('🧗'),
      '수영' => _icon(Icons.pool_rounded),
      '골프' => _lineArt(_SportLineArt.golfClub),
      '복싱' => _icon(Icons.sports_mma_rounded),
      '유도' || '주짓수' => _emoji('🥋'),
      '태권도' => _icon(Icons.sports_martial_arts_rounded),
      '필라테스' => _icon(Icons.sports_gymnastics_rounded),
      '요가' => _icon(Icons.self_improvement_rounded),
      '탁구' => _emoji('🏓'),
      '댄스' => _emoji('💃'),
      '크로스핏' => _lineArt(_SportLineArt.pullUp),
      '피겨' => _icon(Icons.ice_skating_rounded),
      '스키' => _icon(Icons.downhill_skiing_rounded),
      '헬스' => _icon(Icons.fitness_center_rounded),
      '야구' => _icon(Icons.sports_baseball),
      '러닝' || '육상' => _icon(Icons.directions_run),
      '배구' => _icon(Icons.sports_volleyball),
      _ => _icon(Icons.workspace_premium_rounded),
    };
    return KeyedSubtree(
      key: ValueKey('sport-mark-$normalized'),
      child: mark,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              margin: EdgeInsets.all(size * .02),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [accent.withValues(alpha: .2), Colors.transparent],
                ),
              ),
            ),
            Transform.rotate(
              angle: .785398,
              child: Container(
                width: size * .65,
                height: size * .65,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * .18),
                  border: Border.all(color: accent.withValues(alpha: .65)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: .3),
                      const Color(0xFF141F38)
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: size * .51,
              height: size * .51,
              decoration: BoxDecoration(
                color: const Color(0xFF10192A),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: .25)),
              ),
              child: Center(child: _sportMark),
            ),
            Positioned(
              bottom: size * .055,
              child: Container(
                padding: EdgeInsets.all(size * .035),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF10192A), width: 2),
                ),
                child: Icon(Icons.check_rounded,
                    size: size * .14, color: const Color(0xFF10192A)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SportLineArt { tennisRacket, golfClub, pullUp }

class _SportLineArtPainter extends CustomPainter {
  const _SportLineArtPainter({required this.art, required this.color});

  final _SportLineArt art;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * .075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (art) {
      case _SportLineArt.tennisRacket:
        _paintTennisRacket(canvas, size, stroke);
      case _SportLineArt.golfClub:
        _paintGolfClub(canvas, size, stroke);
      case _SportLineArt.pullUp:
        _paintPullUp(canvas, size, stroke);
    }
  }

  void _paintTennisRacket(Canvas canvas, Size size, Paint stroke) {
    final w = size.width;
    final h = size.height;
    canvas.save();
    canvas.translate(w * .36, h * .34);
    canvas.rotate(-.55);
    final head = Rect.fromCenter(
      center: Offset.zero,
      width: w * .43,
      height: h * .58,
    );
    canvas.drawOval(head, stroke);
    final strings = Paint()
      ..color = color.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * .025;
    canvas.drawLine(
        Offset(-w * .11, -h * .22), Offset(-w * .11, h * .22), strings);
    canvas.drawLine(
        Offset.zero - Offset(0, h * .26), Offset(0, h * .26), strings);
    canvas.drawLine(
        Offset(w * .11, -h * .22), Offset(w * .11, h * .22), strings);
    canvas.drawLine(
        Offset(-w * .16, -h * .1), Offset(w * .16, -h * .1), strings);
    canvas.drawLine(Offset(-w * .19, 0), Offset(w * .19, 0), strings);
    canvas.drawLine(Offset(-w * .16, h * .1), Offset(w * .16, h * .1), strings);
    canvas.restore();
    canvas.drawLine(Offset(w * .52, h * .53), Offset(w * .8, h * .87), stroke);
    canvas.drawCircle(Offset(w * .78, h * .2), w * .07, stroke);
  }

  void _paintGolfClub(Canvas canvas, Size size, Paint stroke) {
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w * .28, h * .12), Offset(w * .62, h * .72), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(w * .62, h * .72)
        ..lineTo(w * .83, h * .76)
        ..lineTo(w * .78, h * .88)
        ..lineTo(w * .58, h * .82),
      stroke,
    );
    canvas.drawCircle(Offset(w * .22, h * .82), w * .065, stroke);
    canvas.drawLine(Offset(w * .08, h * .92), Offset(w * .92, h * .92), stroke);
  }

  void _paintPullUp(Canvas canvas, Size size, Paint stroke) {
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w * .08, h * .1), Offset(w * .92, h * .1), stroke);
    canvas.drawLine(Offset(w * .3, h * .13), Offset(w * .44, h * .38), stroke);
    canvas.drawLine(Offset(w * .7, h * .13), Offset(w * .56, h * .38), stroke);
    canvas.drawCircle(Offset(w * .5, h * .34), w * .09, stroke);
    canvas.drawLine(Offset(w * .5, h * .44), Offset(w * .5, h * .7), stroke);
    canvas.drawLine(Offset(w * .5, h * .7), Offset(w * .33, h * .9), stroke);
    canvas.drawLine(Offset(w * .5, h * .7), Offset(w * .67, h * .9), stroke);
  }

  @override
  bool shouldRepaint(covariant _SportLineArtPainter oldDelegate) =>
      oldDelegate.art != art || oldDelegate.color != color;
}

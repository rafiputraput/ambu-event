// lib/widgets/painters.dart
import 'package:flutter/material.dart';

class TopWavePainter extends StatelessWidget {
  const TopWavePainter({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0, left: 0, right: 0,
      height: 120,
      child: CustomPaint(painter: WavePainter()),
    );
  }
}

class WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Blush lembut — bukan merah terang
    final paintBlush = Paint()
      ..color = const Color(0xFFEDD9D7)
      ..style = PaintingStyle.fill;
    final paintBg = Paint()
      ..color = const Color(0xFFF7F5F3)
      ..style = PaintingStyle.fill;

    final path1 = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 40)
      ..quadraticBezierTo(size.width * 0.25, 80, size.width * 0.5, 40)
      ..quadraticBezierTo(size.width * 0.75, 0, size.width, 40)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path1, paintBlush);

    final path2 = Path()
      ..moveTo(0, 55)
      ..quadraticBezierTo(size.width * 0.25, 95, size.width * 0.5, 55)
      ..quadraticBezierTo(size.width * 0.75, 15, size.width, 55)
      ..lineTo(size.width, 40)
      ..quadraticBezierTo(size.width * 0.75, 0, size.width * 0.5, 40)
      ..quadraticBezierTo(size.width * 0.25, 80, 0, 40)
      ..close();
    canvas.drawPath(path2, paintBg);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BottomCityPainter extends StatelessWidget {
  const BottomCityPainter({super.key});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: SizedBox(
        height: 130,
        width: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _building(38, 68, const Color(0xFFE8D5D3)),
            _building(46, 90, const Color(0xFFCFAEAB)),
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(width: 9, height: 9,
                    color: const Color(0xFFD4A0A0)),
                Container(width: 17, height: 70,
                    color: const Color(0xFFC4877E)),
                Container(width: 34, height: 9,
                    color: const Color(0xFFC4877E)),
                Container(width: 52, height: 26,
                    color: const Color(0xFFC4877E)),
              ],
            ),
            _building(46, 80, const Color(0xFFD9B8B5)),
            _building(38, 54, const Color(0xFFE8D5D3)),
          ],
        ),
      ),
    );
  }

  Widget _building(double width, double height, Color color) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.12)
      ..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += 30) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 30) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
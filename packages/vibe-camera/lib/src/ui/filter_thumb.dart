import 'package:flutter/material.dart';

import '../core/filters.dart';

/// What a look does, at a glance: a little painted scene (sky, sun, hills,
/// a face's warm tone) seen through the filter's own matrix. Used where no
/// frame of the clip exists yet (the camera's strip).
class VibeFilterThumb extends StatelessWidget {
  const VibeFilterThumb({super.key, required this.filter});
  final VibeFilter filter;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ColorFiltered(
      colorFilter: ColorFilter.matrix(filter.matrix),
      child: const CustomPaint(painter: _ScenePainter(), child: SizedBox.expand()),
    ),
  );
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final all = Offset.zero & size;
    // Sky: blue to a warm horizon.
    canvas.drawRect(
      all,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4F8DF5), Color(0xFFF7B267), Color(0xFFF4845F)],
          stops: [0, 0.62, 0.8],
        ).createShader(all),
    );
    // Sun.
    canvas.drawCircle(
      Offset(w * 0.68, h * 0.42),
      w * 0.15,
      Paint()..color = const Color(0xFFFFE08A),
    );
    // Far hills.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.66)
        ..quadraticBezierTo(w * 0.3, h * 0.5, w * 0.6, h * 0.64)
        ..quadraticBezierTo(w * 0.85, h * 0.74, w, h * 0.6)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = const Color(0xFF6B4E9B),
    );
    // Near meadow.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.82)
        ..quadraticBezierTo(w * 0.5, h * 0.7, w, h * 0.84)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = const Color(0xFF3FA36B),
    );
    // A person in the foreground: skin tones show warm and cool looks best.
    final cx = w * 0.32;
    canvas.drawPath(
      Path()
        ..moveTo(cx - w * 0.17, h)
        ..quadraticBezierTo(cx - w * 0.16, h * 0.8, cx, h * 0.79)
        ..quadraticBezierTo(cx + w * 0.16, h * 0.8, cx + w * 0.17, h)
        ..close(),
      Paint()..color = const Color(0xFFF2F2F2),
    );
    canvas.drawCircle(Offset(cx, h * 0.62), w * 0.105, Paint()..color = const Color(0xFF3B2A25));
    canvas.drawCircle(Offset(cx, h * 0.655), w * 0.085, Paint()..color = const Color(0xFFE8B49A));
  }

  @override
  bool shouldRepaint(_ScenePainter old) => false;
}

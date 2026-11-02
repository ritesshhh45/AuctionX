import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

double _seg(double t, double a, double b, [Curve curve = Curves.linear]) =>
    curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0).toDouble());

const _brandStyle = TextStyle(
  fontSize: 46,
  fontWeight: FontWeight.w900,
  fontStyle: FontStyle.italic,
  color: Colors.white,
  letterSpacing: -0.5,
  shadows: [Shadow(color: Color(0x88DDB65B), blurRadius: 18)],
);

/// Premium intro (about 2.8 s): stadium lights on, golden hammer strikes, emblem is revealed,
/// the BidLeague name shines in, then the logo zooms through into the app.
/// It sits on top of the already-loading app, so a slow start never delays the app.
class IntroSplash extends StatefulWidget {
  final VoidCallback onDone;
  const IntroSplash({super.key, required this.onDone});
  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

class _IntroSplashState extends State<IntroSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
    Future.delayed(const Duration(milliseconds: 3800), _finish); // safety net: never block the app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        // reduced motion: show the finished logo briefly, no movement
        _c.value = 0.72;
        Future.delayed(const Duration(milliseconds: 600), _finish);
      } else {
        _c.forward();
      }
    });
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _brand(double shine) => Row(mainAxisSize: MainAxisSize.min, children: [
        ShaderMask(
          shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE9A8), kGold, Color(0xFF9A6A1C)])
              .createShader(r),
          child: const Text('Bid', style: _brandStyle),
        ),
        ShaderMask(
          shaderCallback: (r) => LinearGradient(
            begin: Alignment(-1.5 + 3 * shine, -1),
            end: Alignment(-0.5 + 3 * shine, 1),
            colors: const [Color(0xFFD62828), Colors.white, Color(0xFFD62828)],
            stops: const [0.25, 0.5, 0.75],
          ).createShader(r),
          child: const Text('League', style: _brandStyle),
        ),
      ]);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final lights = _seg(t, 0.0, 0.14);
          final swing = _seg(t, 0.10, 0.27, Curves.easeInQuad);
          final hammerOut = 1 - _seg(t, 0.34, 0.50);
          final impact = _seg(t, 0.27, 0.52, Curves.easeOut);
          final reveal = _seg(t, 0.27, 0.50, Curves.easeOutBack);
          final name = _seg(t, 0.46, 0.66, Curves.easeOutCubic);
          final shine = _seg(t, 0.58, 0.84);
          final zoom = _seg(t, 0.80, 1.0, Curves.easeInCubic);
          final fade = 1 - _seg(t, 0.92, 1.0);
          final shake = (t > 0.27 && t < 0.36) ? math.sin(t * 900) * (0.36 - t) * 70 : 0.0;
          final glow = (120 * reveal.clamp(0.0, 1.0)).round();

          return Opacity(
            opacity: fade,
            child: Container(
              color: kBg,
              child: Stack(fit: StackFit.expand, children: [
                CustomPaint(painter: _StagePainter(lights: lights, impact: impact)),
                Transform.translate(
                  offset: Offset(shake, shake * 0.6),
                  child: Center(
                    child: Transform.scale(
                      scale: 1 + zoom * 9,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(
                          width: 260,
                          height: 260,
                          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                            Opacity(
                              opacity: reveal.clamp(0.0, 1.0).toDouble(),
                              child: Transform.scale(
                                scale: 0.55 + 0.45 * reveal,
                                child: Container(
                                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                                    BoxShadow(color: kGold.withAlpha(glow), blurRadius: 60, spreadRadius: 6),
                                  ]),
                                  child: Image.asset('assets/emblem.png', width: 230, height: 230),
                                ),
                              ),
                            ),
                            if (hammerOut > 0)
                              Positioned(
                                left: -40,
                                top: -50,
                                child: Opacity(
                                  opacity: hammerOut.clamp(0.0, 1.0).toDouble(),
                                  child: Transform.rotate(
                                    angle: 0.9 - 1.5 * swing,
                                    alignment: Alignment.bottomRight,
                                    child: Image.asset('assets/hammer.png', width: 170),
                                  ),
                                ),
                              ),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        Opacity(
                          opacity: name,
                          child: Transform.translate(offset: Offset(0, 18 * (1 - name)), child: _brand(shine)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}

class _StagePainter extends CustomPainter {
  final double lights, impact;
  _StagePainter({required this.lights, required this.impact});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF07070E), Color(0xFF1B0A12)],
        ).createShader(rect),
    );
    void glow(Offset c, double r, Color col) => canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [col.withAlpha((90 * lights).round()), col.withAlpha(0)])
                .createShader(Rect.fromCircle(center: c, radius: r)),
        );
    glow(Offset(size.width * 0.10, size.height * 0.08), size.width * 0.8, const Color(0xFFFFE2A0));
    glow(Offset(size.width * 0.92, size.height * 0.10), size.width * 0.8, const Color(0xFFFF4A4A));
    glow(Offset(size.width * 0.5, size.height * 0.98), size.width * 1.0, const Color(0xFFB3141E));

    final dot = Paint()
      ..color = Colors.white.withAlpha((210 * lights).round())
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 2; j++) {
        canvas.drawCircle(Offset(size.width * 0.05 + i * 14, size.height * 0.04 + j * 14), 4, dot);
        canvas.drawCircle(Offset(size.width * 0.95 - i * 14, size.height * 0.04 + j * 14), 4, dot);
      }
    }

    if (impact > 0 && impact < 1) {
      final c = size.center(Offset.zero);
      final a = ((1 - impact) * 255).round().clamp(0, 255);
      canvas.drawCircle(
        c,
        40 + impact * size.shortestSide * 0.7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - impact) + 1
          ..color = const Color(0xFFFFD87A).withAlpha(a),
      );
      canvas.drawCircle(
        c,
        20 + impact * size.shortestSide * 0.45,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFF5A5A).withAlpha(a),
      );
      final sp = Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFE9A8).withAlpha(a);
      for (var i = 0; i < 18; i++) {
        final ang = i * math.pi * 2 / 18 + 0.3;
        final r1 = 60 + impact * 170, r2 = r1 + 16 + 20 * (1 - impact);
        canvas.drawLine(c + Offset(math.cos(ang) * r1, math.sin(ang) * r1), c + Offset(math.cos(ang) * r2, math.sin(ang) * r2), sp);
      }
    }
  }

  @override
  bool shouldRepaint(_StagePainter o) => o.lights != lights || o.impact != impact;
}

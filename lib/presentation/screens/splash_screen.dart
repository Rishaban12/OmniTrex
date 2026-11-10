import 'package:flutter/material.dart';

import '../theme.dart';

/// Launch animation on the blob background:
/// logo pops in at the centre → slides left → "OmniTrex" appears letter by
/// letter → the swoosh draws underneath → the tagline fades up → [onDone].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  // Timeline (fractions of the 3.6 s controller).
  late final _logoIn = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.15, curve: Curves.easeOutBack));
  // Logo pop: fade 0→1 (no overshoot) and scale 0.4→1 with a little bounce.
  late final _logoFade = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.12, curve: Curves.easeOut));
  late final Animation<double> _logoScale = Tween(begin: 0.4, end: 1.0).animate(_logoIn);
  late final _slide = CurvedAnimation(parent: _c, curve: const Interval(0.18, 0.33, curve: Curves.easeInOutCubic));
  static const _lettersFrom = 0.33, _lettersTo = 0.58;
  late final _swoosh = CurvedAnimation(parent: _c, curve: const Interval(0.58, 0.73, curve: Curves.easeOutCubic));
  late final _tagline = CurvedAnimation(parent: _c, curve: const Interval(0.74, 0.88, curve: Curves.easeOut));

  static const _taglineText = 'Connect | Create | Grow';

  static const _lead = 'Omni', _accent = 'Trex';
  static const _logoSize = 84.0, _gap = 6.0, _fontSize = 36.0;
  static const _style = TextStyle(
    fontSize: _fontSize,
    fontWeight: FontWeight.w900,
    letterSpacing: -1,
    height: 1,
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0→1 visibility of letter [i] of [n] within the letters window.
  double _letter(int i, int n) {
    final span = (_lettersTo - _lettersFrom) / n;
    final start = _lettersFrom + span * i;
    return ((_c.value - start) / (span * 1.6)).clamp(0.0, 1.0);
  }

  Widget _letters(String text, int offset, int total, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, ch) in text.split('').indexed)
            Builder(builder: (_) {
              final t = Curves.easeOut.transform(_letter(offset + i, total));
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 10),
                  child: Text(ch, style: style.copyWith(color: color)),
                ),
              );
            }),
        ],
      );

  /// Name style resolved against the theme, so measuring and drawing use the
  /// same font family (a bare TextStyle would measure in the platform
  /// default font while Text draws in the theme font).
  late TextStyle style;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    style = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).merge(_style);
    // Measure the name so the final logo+name group is centred, and the logo
    // can start exactly in the middle of the screen. Letters are drawn one by
    // one (no kerning between them), so measure them one by one too; +1 px
    // absorbs sub-pixel rounding.
    final textWidth = (_lead + _accent).split('').fold<double>(
              0,
              (w, ch) => w +
                  (TextPainter(
                    text: TextSpan(text: ch, style: style),
                    textDirection: TextDirection.ltr,
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout())
                      .width,
            ) +
        1;
    final total = _lead.length + _accent.length;

    return Scaffold(
      body: BlobBackground(
        // Scales the whole lockup down on very narrow screens / large
        // accessibility text instead of overflowing.
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              // Own layer: only the logo/letters repaint per frame, not the
              // big blurred background blobs (expensive on budget GPUs).
              child: RepaintBoundary(
                child: AnimatedBuilder(
            animation: _c,
            // Logo built once; Fade/Scale transitions animate it without rebuilds.
            child: FadeTransition(
              opacity: _logoFade,
              child: ScaleTransition(
                scale: _logoScale,
                child: Image.asset(
                  'lib/data/static/logo.png',
                  width: _logoSize,
                  height: _logoSize,
                  // Decode at display size, not the 1254 px source.
                  cacheWidth: (_logoSize * MediaQuery.devicePixelRatioOf(context)).round(),
                ),
              ),
            ),
            builder: (context, logo) {
              final shift = (textWidth + _gap) / 2 * (1 - _slide.value);
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                Transform.translate(
                  offset: Offset(shift, 0),
                  child: logo,
                ),
                const SizedBox(width: _gap),
                // Letters sit a little low so they centre on the logo's ring.
                Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: SizedBox(
                    width: textWidth,
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        _letters(_lead, 0, total, ink),
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (r) => Wordmark.blueGradient.createShader(r),
                          child: _letters(_accent, _lead.length, total, Colors.white),
                        ),
                      ]),
                      // Swoosh draws left → right.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ClipRect(
                          child: SizedBox(
                            width: textWidth * _swoosh.value,
                            height: _fontSize * 0.3,
                            // Full-width swoosh, revealed by the growing clip.
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: textWidth,
                              maxWidth: textWidth,
                              child: const CustomPaint(
                                size: Size(double.infinity, _fontSize * 0.3),
                                painter: SwooshPainter(Wordmark.blueGradient),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                ]),
                const SizedBox(height: 8),
                // Tagline fades up under the logo + name.
                Opacity(
                  opacity: _tagline.value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - _tagline.value) * 12),
                    child: Text(
                      _taglineText,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: ink.withValues(alpha: 0.6),
                          ),
                    ),
                  ),
                ),
              ]);
            },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

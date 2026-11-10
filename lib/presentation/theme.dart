import 'package:flutter/material.dart';

/// Palette lifted from the onboarding illustrations.
class Palette {
  const Palette._();

  static const blue = Color(0xFF2F6BDE);
  static const yellow = Color(0xFFF6C343);
  static const coral = Color(0xFFF0695B);
  static const green = Color(0xFF5AAE7E);
  static const ink = Color(0xFF141414);
  static const paper = Color(0xFFFBF8F3);
  static const night = Color(0xFF151518);

  static const blueSoft = Color(0xFFDCE6FA);
  static const yellowSoft = Color(0xFFFCEFC6);
  static const coralSoft = Color(0xFFFBDAD4);
  static const greenSoft = Color(0xFFD6EEDF);

  /// MindNotes purple (from its illustration).
  static const purple = Color(0xFF8E5BD8);
  static const purpleSoft = Color(0xFFEADCFB);

  /// Light bright yellow for primary actions (Save, +).
  static const sunny = yellow;
  static const orange = Color(0xFFF57C00);
  /// Pastel fill for tiles and buttons; deepened in dark mode.
  static Color soft(Color base, Brightness b) {
    if (b == Brightness.dark) return base.withValues(alpha: 0.24);
    if (base == blue) return blueSoft;
    if (base == yellow) return yellowSoft;
    if (base == coral) return coralSoft;
    if (base == green) return greenSoft;
    if (base == purple) return purpleSoft;
    return base.withValues(alpha: 0.18);
  }
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.blue,
    brightness: brightness,
  ).copyWith(
    primary: Palette.blue,
    onPrimary: Colors.white,
    secondary: Palette.yellow,
    tertiary: Palette.green,
    error: Palette.coral,
    surface: dark ? Palette.night : Palette.paper,
    onSurface: dark ? const Color(0xFFF2EFEA) : Palette.ink,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -2, height: 0.95),
      displayMedium: text.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1),
      displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF212126) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: Palette.soft(Palette.blue, brightness),
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? Colors.white : Palette.ink,
        foregroundColor: dark ? Palette.ink : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: dark ? Colors.white : Palette.ink,
      foregroundColor: dark ? Palette.ink : Colors.white,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: scheme.surface),
    // Any SnackBar not built via showSnack still gets a pastel card.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.blueSoft,
      contentTextStyle: const TextStyle(color: Palette.ink, fontWeight: FontWeight.w600, fontSize: 15),
      actionTextColor: Palette.blue,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Palette.blue, width: 1.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Brand logotype: solid [lead] word, gradient [accent] word, and a curved
/// gradient swoosh underneath sized to the text (e.g. "Pocket"+"Plan",
/// "Omni"+"Trex").
class Wordmark extends StatelessWidget {
  const Wordmark(this.lead, this.accent,
      {super.key, this.fontSize = 24, this.gradient = coralGradient});
  final String lead, accent;
  final double fontSize;
  final Gradient gradient;

  static const coralGradient = LinearGradient(
    colors: [Color(0xFFFF7A6B), Color(0xFFFF9A4D)],
  );
  /// Salmon pink of the shopping-cart tile in the PocketPlan illustration.
  static const pinkGradient = LinearGradient(
    colors: [Color(0xFFFF8F87), Color(0xFFF2706A)],
  );

  /// Light → dark green for the "List" in DoList.
  static const greenGradient = LinearGradient(
    colors: [Color(0xFF7FD69A), Color(0xFF2E8B57)],
  );

  /// Purple for the "Notes" in MindNotes.
  static const purpleGradient = LinearGradient(
    colors: [Color(0xFFB088F0), Color(0xFF7E4FD0)],
  );

  /// Logo blue for the "Trex" in OmniTrex.
  static const blueGradient = LinearGradient(
    colors: [Color(0xFF3AABFF), Color(0xFF1E90FF)],
  );

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.8,
      height: 1,
    );
    return IntrinsicWidth(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(lead, style: style.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => gradient.createShader(r),
            child: Text(accent, style: style.copyWith(color: Colors.white)),
          ),
        ]),
        SizedBox(
          height: fontSize * 0.3,
          child: CustomPaint(painter: SwooshPainter(gradient)),
        ),
      ]),
    );
  }
}

class SwooshPainter extends CustomPainter {
  const SwooshPainter(this.gradient);
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    // Thin crescent: a gentle upward arc, thickest in the middle.
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.04, h * 0.95)
      ..quadraticBezierTo(w * 0.5, -h * 0.35, w * 0.98, h * 0.55)
      ..quadraticBezierTo(w * 0.5, h * 0.25, w * 0.04, h * 0.95)
      ..close();
    canvas.drawPath(path, Paint()..shader = gradient.createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(SwooshPainter old) => false;
}

/// Soft blurred pastel blobs, as in the SpeakSync splash.
class BlobBackground extends StatelessWidget {
  const BlobBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final o = b == Brightness.dark ? 0.16 : 0.55;
    Widget blob(Color c, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: o), c.withValues(alpha: 0)]),
          ),
        );
    // One blob per corner: yellow ↖, blue ↗, green ↙, orange ↘.
    return Stack(children: [
      Positioned(top: -60, left: -60, child: blob(Palette.yellow, 260)),
      Positioned(top: -60, right: -60, child: blob(Palette.blue, 260)),
      Positioned(bottom: -60, left: -60, child: blob(Palette.green, 260)),
      Positioned(bottom: -60, right: -60, child: blob(Palette.orange, 260)),
      Positioned.fill(child: child),
    ]);
  }
}

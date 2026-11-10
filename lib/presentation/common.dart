import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/db/app_database.dart';
import '../domain/entities/app_settings.dart';
import 'dolist_style.dart';
import 'providers.dart';
import 'theme.dart';

/// Currency formatter bound to the user's chosen currency.
final moneyProvider = Provider<Money>((ref) =>
    Money(ref.watch(settingsProvider.select((s) => s.currencyCode))));

class Money {
  Money(String code) : _fmt = _build(code);
  final NumberFormat _fmt;

  static NumberFormat _build(String code) {
    final c = Currency.byCode(code);
    return NumberFormat.currency(locale: c.locale, symbol: c.symbol, decimalDigits: 0);
  }

  String call(double v) {
    final s = _fmt.format(v.abs());
    return v < -0.5 ? '−$s' : s;
  }
}

/// Fixed icon palette; storing keys (not code points) keeps icon tree-shaking.
const categoryIcons = <String, IconData>{
  'food': Icons.restaurant,
  'travel': Icons.directions_car,
  'bills': Icons.receipt_long,
  'shopping': Icons.shopping_bag,
  'other': Icons.category,
  'health': Icons.local_hospital,
  'fun': Icons.movie,
  'groceries': Icons.local_grocery_store,
  'coffee': Icons.local_cafe,
  'education': Icons.school,
  'gift': Icons.card_giftcard,
  'home': Icons.home,
  'pets': Icons.pets,
  'fitness': Icons.fitness_center,
};

const categoryColors = <int>[
  0xFFF6C343, 0xFF2F6BDE, 0xFF5AAE7E, 0xFFF0695B, 0xFF8A94A6,
  0xFF7FA8F5, 0xFFE89A3C, 0xFF3FA7A0, 0xFFB86FD8, 0xFF141414,
];

IconData iconFor(String key) => categoryIcons[key] ?? Icons.category;

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.category, {super.key, this.size = 40});
  final CategoryRow? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(category?.color ?? 0xFF8A94A6);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
      child: Icon(category == null ? Icons.help_outline : iconFor(category!.icon),
          color: color, size: size * 0.5),
    );
  }
}

/// Circular progress ring; turns red once [progress] exceeds 1.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.progress, required this.child, this.size = 220});
  final double progress;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = progress > 1;
    final color = over
        ? scheme.error
        : progress > 0.8
            ? const Color(0xFFF6C343)
            : scheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress.clamp(0, 1).toDouble()),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _RingPainter(value, color, scheme.surfaceContainerHighest),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track);
  final double value;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, base..color = track);
    if (value > 0) {
      canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * value, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

String sourceLabel(String source) => switch (source) {
      'sms' => 'SMS',
      'notification' => 'UPI app',
      _ => 'Manual',
    };

int _snackCount = 0;

/// App-wide popup: a pastel card that cycles through the palette (yellow,
/// blue, coral, green, purple) so each message looks different. Pass
/// [style] to pin a colour (e.g. the to-do that was just ticked).
void showSnack(BuildContext context, String msg, {NoteStyle? style, IconData? icon}) {
  final s = style ?? NoteStyle.of(_snackCount++);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      elevation: 2,
      backgroundColor: s.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: s.tape, width: 1.5),
      ),
      content: Row(children: [
        Icon(icon ?? Icons.info_rounded, color: s.tape),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg, style: const TextStyle(color: Palette.ink, fontWeight: FontWeight.w600, fontSize: 15)),
        ),
      ]),
    ));
}

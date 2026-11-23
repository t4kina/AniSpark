import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../theme/app_motion.dart';
import '../utils/developers.dart';
import '../utils/translations.dart';

/// The seal beside an AniSpark developer's name, like a verified tick: an
/// eight-lobed violet seal with a white check that holds still while a
/// glint of light crosses it every few seconds. With animations reduced it
/// is just the seal.
class DevBadge extends StatefulWidget {
  const DevBadge({super.key, this.size = 18});

  /// Its width and height.
  final double size;

  /// One glint and the rest between glints.
  static const cycle = Duration(milliseconds: 3200);

  @override
  State<DevBadge> createState() => _DevBadgeState();
}

class _DevBadgeState extends State<DevBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: DevBadge.cycle);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _clock
        ..stop()
        ..value = 0;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider?>()?.language ?? 'English';
    return Semantics(
      label: tr('dev_badge', lang),
      image: true,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _SealPainter(_clock, still: AppMotion.reduced(context)),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  _SealPainter(this.clock, {required this.still}) : super(repaint: clock);

  final Animation<double> clock;
  final bool still;

  static const _top = Color(0xFFA99BFF);
  static const _bottom = Color(0xFF5B6CFF);

  /// The glint crosses during this part of each cycle.
  static const _glintFrom = 0.55;
  static const _glintTo = 0.85;

  /// A circle with eight more around its edge, in a 24 unit box.
  static Path _seal(double unit) {
    var seal = Path()..addOval(Rect.fromCircle(center: Offset(12 * unit, 12 * unit), radius: 8 * unit));
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final lobe = Offset(12 + 7.2 * math.cos(angle), 12 + 7.2 * math.sin(angle)) * unit;
      seal = Path.combine(PathOperation.union, seal, Path()..addOval(Rect.fromCircle(center: lobe, radius: 3.8 * unit)));
    }
    return seal;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final seal = _seal(unit);
    final box = Offset.zero & size;
    canvas.drawPath(
      seal,
      Paint()..shader = const LinearGradient(colors: [_top, _bottom], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(box),
    );

    final t = clock.value;
    if (!still && t >= _glintFrom && t <= _glintTo) {
      final progress = Curves.easeInOut.transform((t - _glintFrom) / (_glintTo - _glintFrom));
      final x = (-0.4 + 1.8 * progress) * size.width;
      canvas.save();
      canvas.clipPath(seal);
      canvas.translate(x, size.height / 2);
      canvas.rotate(25 * math.pi / 180);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: size.width * 0.18, height: size.height * 2),
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
      canvas.restore();
    }

    final check = Path()
      ..moveTo(8 * unit, 12.3 * unit)
      ..lineTo(10.6 * unit, 14.9 * unit)
      ..lineTo(16.2 * unit, 9.3 * unit);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3 * unit
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SealPainter oldDelegate) => oldDelegate.still != still || oldDelegate.clock != clock;
}

/// [name] in [style], followed by the developer seal when it is the name of
/// one of AniSpark's developers (see [isAniSparkDeveloper]).
class BadgedName extends StatelessWidget {
  const BadgedName(this.name, {super.key, this.style, this.maxLines = 1, this.badgeSize});

  final String name;
  final TextStyle? style;
  final int maxLines;

  /// The seal's size, when not [devBadgeSizeFor] the text's.
  final double? badgeSize;

  @override
  Widget build(BuildContext context) {
    final text = Text(name, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    if (!isAniSparkDeveloper(name)) return text;
    final fontSize = style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 14;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        SizedBox(width: fontSize * 0.3),
        DevBadge(size: badgeSize ?? devBadgeSizeFor(fontSize)),
      ],
    );
  }
}

/// The seal's size beside text of [fontSize].
double devBadgeSizeFor(double fontSize) => (fontSize * 1.05).roundToDouble();

/// The seal as a span to follow [name] inside a sentence of [fontSize], or
/// null when [name] is not a developer's.
InlineSpan? devBadgeSpan(String? name, {required double fontSize}) {
  if (!isAniSparkDeveloper(name)) return null;
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: EdgeInsets.only(left: fontSize * 0.3),
      child: DevBadge(size: devBadgeSizeFor(fontSize)),
    ),
  );
}

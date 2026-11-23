import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_layout.dart';
import '../../theme/app_motion.dart';

/// A thin bar of how far through a series someone is ([value] of [total]).
/// When the value changes the fill glides to its new length instead of
/// jumping there.
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.value, required this.total}) : assert(total > 0);

  final int value;
  final int total;

  static const height = 3.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: AppRadius.pillAll,
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: cs.surfaceContainerHighest,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: (value / total).clamp(0.0, 1.0)),
            duration: AppMotion.of(context, AppMotion.medium),
            curve: AppMotion.standard,
            builder: (_, fraction, child) => FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: fraction,
              child: child,
            ),
            child: ColoredBox(color: cs.primary, child: const SizedBox.expand()),
          ),
        ),
      ),
    );
  }
}

/// A tick that pops in when [value] changes, stays a moment and fades away:
/// the answer to "did that count?" after adding or taking away an episode.
/// It is green when the value went up and grey when it went down.
///
/// Put it right after the text it belongs to, in a row centred on its cross
/// axis. It always holds the same width and no height at all: the tick is
/// painted over the line, centred on it, so showing and going moves
/// nothing around it.
class ChangeTick extends StatefulWidget {
  const ChangeTick({super.key, required this.value, this.size = 14});

  final int value;
  final double size;

  /// From the pop to the end of the fade.
  static const duration = Duration(milliseconds: 1100);

  @override
  State<ChangeTick> createState() => _ChangeTickState();
}

class _ChangeTickState extends State<ChangeTick> with SingleTickerProviderStateMixin {
  // The shares of the run spent popping in and, at the end, fading out.
  static const _popUntil = 0.22;
  static const _fadeFrom = 0.72;
  static const _gap = AppSpace.xs;

  late final AnimationController _run = AnimationController(vsync: this, duration: ChangeTick.duration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _run.reset();
    });
  bool _wentUp = true;

  @override
  void didUpdateWidget(ChangeTick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    _wentUp = widget.value > oldWidget.value;
    _run.forward(from: 0);
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final colors = context.colors;
    return SizedBox(
      width: _gap + widget.size,
      height: 0,
      child: AnimatedBuilder(
        animation: _run,
        builder: (_, _) {
          if (_run.isDismissed) return const SizedBox.shrink();
          final t = _run.value;
          final scale = reduced || t >= _popUntil ? 1.0 : Curves.easeOutBack.transform(t / _popUntil);
          final opacity = t <= _fadeFrom ? 1.0 : 1 - (t - _fadeFrom) / (1 - _fadeFrom);
          // Taller than its box on purpose: it overflows evenly above and
          // below, which centres it on the line without widening the line.
          return OverflowBox(
            alignment: AlignmentDirectional.centerEnd,
            minWidth: widget.size,
            maxWidth: widget.size,
            minHeight: widget.size,
            maxHeight: widget.size,
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: widget.size,
                  color: _wentUp ? colors.success : colors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

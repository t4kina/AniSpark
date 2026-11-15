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

/// A tick that pops in when [value] goes up, stays a moment and fades away:
/// the answer to "did that count?" after adding an episode. Nothing is
/// there the rest of the time, nor when the value goes down.
///
/// It takes its room only while it shows, so put it last in its row.
class IncrementTick extends StatefulWidget {
  const IncrementTick({super.key, required this.value, this.size = 14});

  final int value;
  final double size;

  /// From the pop to the end of the fade.
  static const duration = Duration(milliseconds: 1100);

  @override
  State<IncrementTick> createState() => _IncrementTickState();
}

class _IncrementTickState extends State<IncrementTick> with SingleTickerProviderStateMixin {
  // The shares of the run spent popping in and, at the end, fading out.
  static const _popUntil = 0.22;
  static const _fadeFrom = 0.72;

  late final AnimationController _run = AnimationController(vsync: this, duration: IncrementTick.duration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _run.reset();
    });

  @override
  void didUpdateWidget(IncrementTick oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value > oldWidget.value) _run.forward(from: 0);
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final icon = Padding(
      padding: const EdgeInsetsDirectional.only(start: AppSpace.xs),
      child: Icon(Icons.check_circle_rounded, size: widget.size, color: context.colors.success),
    );
    return AnimatedBuilder(
      animation: _run,
      builder: (_, icon) {
        if (_run.isDismissed) return const SizedBox.shrink();
        final t = _run.value;
        final scale = reduced || t >= _popUntil ? 1.0 : Curves.easeOutBack.transform(t / _popUntil);
        final opacity = t <= _fadeFrom ? 1.0 : 1 - (t - _fadeFrom) / (1 - _fadeFrom);
        return Opacity(opacity: opacity, child: Transform.scale(scale: scale, child: icon));
      },
      child: icon,
    );
  }
}

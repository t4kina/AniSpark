import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../theme/app_motion.dart';
import '../../utils/haptics.dart';

/// What a [SwipeAction] shows behind its row on one side, and runs.
class SwipeActionSide {
  const SwipeActionSide({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTriggered,
  });

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTriggered;
}

/// A row that runs an action when swiped a little to one side, then springs
/// back to its place.
///
/// Past [threshold] of the row's width a haptic ticks and the action's icon
/// grows: letting go there (or flicking) runs it. Further out the row
/// resists, and the colour and icon behind it fade in as it's pulled.
class SwipeAction extends StatefulWidget {
  const SwipeAction({
    super.key,
    required this.child,
    this.startToEnd,
    this.endToStart,
    this.threshold = 0.25,
  });

  final Widget child;

  /// Swiping right.
  final SwipeActionSide? startToEnd;

  /// Swiping left.
  final SwipeActionSide? endToStart;

  /// Fraction of the row's width a swipe has to reach.
  final double threshold;

  @override
  State<SwipeAction> createState() => _SwipeActionState();
}

class _SwipeActionState extends State<SwipeAction> with SingleTickerProviderStateMixin {
  /// How much of a drag past the trigger point still moves the row.
  static const _resistance = 0.3;

  /// A flick this fast (px/s) runs the action short of the trigger point.
  static const _flingVelocity = 900.0;

  /// The row's offset, in pixels.
  late final AnimationController _offset = AnimationController.unbounded(vsync: this);
  double _width = 0;

  /// How far the finger has dragged, before the resistance.
  double _drag = 0;
  bool _armed = false;

  double get _triggerDistance => _width * widget.threshold;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  SwipeActionSide? _sideFor(double dx) => dx > 0 ? widget.startToEnd : (dx < 0 ? widget.endToStart : null);

  void _onDragStart(DragStartDetails _) {
    _offset.stop();
    _drag = _offset.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_width == 0) return;
    var drag = _drag + (details.primaryDelta ?? 0);
    // No side to swipe towards: the row stays put.
    if (_sideFor(drag) == null) drag = 0;
    _drag = drag;
    final limit = _triggerDistance;
    final distance = drag.abs();
    final shown = distance <= limit ? distance : limit + (distance - limit) * _resistance;
    _offset.value = shown * drag.sign;

    final armed = distance >= limit;
    if (armed != _armed) {
      setState(() => _armed = armed);
      if (armed) selectionHaptic();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final flung = velocity.abs() >= _flingVelocity && velocity.sign == _drag.sign;
    final side = _sideFor(_drag);
    if ((_armed || flung) && side != null) side.onTriggered();
    _settle(velocity);
  }

  void _settle([double velocity = 0]) {
    _drag = 0;
    if (_armed) setState(() => _armed = false);
    if (AppMotion.reduced(context)) {
      _offset.value = 0;
      return;
    }
    // A spring settles within a hair of its end; land exactly on it unless a
    // new drag took over.
    _offset.animateWith(SpringSimulation(AppMotion.snap, _offset.value, 0, velocity)).then((_) {
      if (mounted && _drag == 0) _offset.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.startToEnd;
    final end = widget.endToStart;
    return Semantics(
      customSemanticsActions: {
        if (start != null) CustomSemanticsAction(label: '+ ${start.label}'): start.onTriggered,
        if (end != null) CustomSemanticsAction(label: '− ${end.label}'): end.onTriggered,
      },
      child: LayoutBuilder(builder: (context, constraints) {
        _width = constraints.maxWidth;
        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _settle,
          child: AnimatedBuilder(
            animation: _offset,
            builder: (context, child) {
              final dx = _offset.value;
              final side = _sideFor(dx);
              return Stack(
                children: [
                  if (side != null)
                    Positioned.fill(
                      child: _SwipeBackground(
                        side: side,
                        fromStart: dx > 0,
                        progress: _triggerDistance == 0 ? 0 : (dx.abs() / _triggerDistance).clamp(0.0, 1.0),
                        armed: _armed,
                      ),
                    ),
                  Transform.translate(offset: Offset(dx, 0), child: child),
                ],
              );
            },
            child: widget.child,
          ),
        );
      }),
    );
  }
}

/// The colour and icon a row uncovers as it's swiped, fading in with
/// [progress] towards the trigger point; the icon grows once [armed].
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.side,
    required this.fromStart,
    required this.progress,
    required this.armed,
  });

  final SwipeActionSide side;
  final bool fromStart;
  final double progress;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final strong = side.color.withValues(alpha: 0.9 * progress);
    final clear = side.color.withValues(alpha: 0);
    const textStyle = TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14);
    final icon = AnimatedScale(
      scale: armed ? 1.25 : 1,
      duration: AppMotion.of(context, AppMotion.short),
      curve: AppMotion.standard,
      child: Icon(side.icon, color: Colors.white, size: 20),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: fromStart ? Alignment.centerLeft : Alignment.centerRight,
          end: fromStart ? Alignment.centerRight : Alignment.centerLeft,
          colors: [strong, clear],
          stops: const [0, 0.8],
        ),
      ),
      child: Align(
        alignment: fromStart ? Alignment.centerLeft : Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Opacity(
            opacity: progress,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: fromStart
                  ? [icon, const SizedBox(width: 6), Text(side.label, style: textStyle)]
                  : [Text(side.label, style: textStyle), const SizedBox(width: 6), icon],
            ),
          ),
        ),
      ),
    );
  }
}

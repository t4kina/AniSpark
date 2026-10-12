import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Fades [child] in and lifts it a few pixels, [index] steps after the first
/// item, so a freshly loaded list cascades in. Only the first [maxStaggered]
/// items take part. Later items, every item when motion is reduced, and
/// items an [EntranceGate] says are no longer fresh appear at once.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.index, required this.child});

  /// Delay between consecutive items.
  static const step = Duration(milliseconds: 40);

  /// Items from this index on appear without animating.
  static const maxStaggered = 8;

  /// How far (logical pixels) an item rises while fading in.
  static const lift = 12.0;

  final int index;
  final Widget child;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double> _progress = kAlwaysCompleteAnimation;
  Timer? _delay;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decided once, when the item first appears.
    if (_decided) return;
    _decided = true;
    final animate = widget.index < StaggeredEntrance.maxStaggered &&
        !AppMotion.reduced(context) &&
        EntranceGate.isFresh(context);
    if (!animate) return;
    final controller = AnimationController(vsync: this, duration: AppMotion.medium);
    _controller = controller;
    _progress = CurvedAnimation(parent: controller, curve: AppMotion.enter);
    final delay = StaggeredEntrance.step * widget.index;
    if (delay == Duration.zero) {
      controller.forward();
    } else {
      _delay = Timer(delay, controller.forward);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _progress,
      child: _controller == null
          ? widget.child
          : AnimatedBuilder(
              animation: _progress,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, StaggeredEntrance.lift * (1 - _progress.value)),
                child: child,
              ),
              child: widget.child,
            ),
    );
  }
}

/// Marks when a list got its data, so [StaggeredEntrance] items only play
/// their entrance right after a load, and not when a lazy list rebuilds an
/// item that scrolls back into view. Change [trigger] when new data arrives
/// (e.g. pass the list itself) to let the cascade play again.
class EntranceGate extends StatefulWidget {
  const EntranceGate({super.key, required this.trigger, required this.child});

  /// How long after new data its items may still animate in.
  static const window = Duration(milliseconds: 700);

  final Object? trigger;
  final Widget child;

  /// Whether items appearing now are part of a fresh load; true without a
  /// gate above [context].
  static bool isFresh(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_GateScope>()?.freshness.fresh ?? true;

  @override
  State<EntranceGate> createState() => _EntranceGateState();
}

class _Freshness {
  bool fresh = true;
}

class _EntranceGateState extends State<EntranceGate> {
  final _freshness = _Freshness();
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(EntranceGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger) _restart();
  }

  void _restart() {
    _freshness.fresh = true;
    _expiry?.cancel();
    // Flipped without a rebuild: items only read it when they first appear.
    _expiry = Timer(EntranceGate.window, () => _freshness.fresh = false);
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _GateScope(freshness: _freshness, child: widget.child);
}

class _GateScope extends InheritedWidget {
  const _GateScope({required this.freshness, required super.child});

  final _Freshness freshness;

  @override
  bool updateShouldNotify(_GateScope oldWidget) => false;
}

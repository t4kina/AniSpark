import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../theme/app_motion.dart';
import '../../utils/haptics.dart';

/// One tab of a [LiquidNavigationBar].
class LiquidDestination {
  const LiquidDestination({required this.icon, required this.selectedIcon, required this.label});

  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

/// The app's bottom [NavigationBar] with a "liquid" pill behind the selected
/// icon: on a tab change the pill's leading edge runs to the new tab first
/// and its trailing edge catches up, so it stretches like a drop and then
/// settles.
///
/// The pill can also be dragged: a finger sliding along the bar (straight
/// away or after holding) pulls the pill after it, stretched by how far it
/// trails, with a tick on each tab it crosses; letting go opens the tab
/// under the finger.
///
/// The pill is painted under a transparent NavigationBar, which keeps its
/// own layout, semantics and taps. It is placed on the icons' real boxes,
/// measured after layout, so it stays centred whatever the label height,
/// text scale or safe area.
class LiquidNavigationBar extends StatefulWidget {
  const LiquidNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<LiquidDestination> destinations;

  /// Key of the pill's [CustomPaint], for tests.
  static const pillKey = ValueKey('liquid-pill');

  @override
  State<LiquidNavigationBar> createState() => _LiquidNavigationBarState();
}

class _LiquidNavigationBarState extends State<LiquidNavigationBar> with TickerProviderStateMixin {
  // About Material 3's own indicator (64x32), a little narrower so five
  // tabs on a small phone keep a gap between neighbours.
  static const _pillSize = Size(60, 32);

  late final AnimationController _controller = AnimationController(vsync: this, value: 1);

  /// The icon currently shown for each tab (its icon or selected icon).
  final _icons = <int, BuildContext>{};

  /// Each tab's icon centre in this widget's coordinates, once laid out.
  List<Offset?> _centers = const [];

  /// Where the pill was when the selection last changed; null when it
  /// hasn't moved yet.
  Rect? _start;

  // ── Dragging ──
  late final Ticker _dragTicker = createTicker(_followFinger);
  Duration _lastTick = Duration.zero;
  final _dragFrame = ValueNotifier<int>(0);
  int? _pointer;
  Offset? _downAt;
  bool _dragging = false;

  /// The finger's x, and the pill's, which trails it.
  double _fingerX = 0;
  double _pillX = 0;

  /// The tab under the finger, for the tick when it changes.
  int? _hovered;

  /// Where a drag let go of the pill, so the move to the chosen tab starts
  /// there rather than from the previous tab.
  Rect? _releasedAt;

  @override
  void didUpdateWidget(LiquidNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    // Leave from wherever the pill is now, even halfway through a move.
    _start = _releasedAt ?? _pillRect(oldWidget.selectedIndex, _start, _controller.value);
    _releasedAt = null;
    _settle();
  }

  @override
  void dispose() {
    _dragTicker.dispose();
    _dragFrame.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Animates the pill from [_start] onto the selected tab.
  void _settle() {
    final duration = AppMotion.of(context, AppMotion.long);
    if (duration == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.duration = duration;
      _controller.forward(from: 0);
    }
  }

  void _register(int slot, BuildContext icon) => _icons[slot] = icon;

  void _unregister(int slot, BuildContext icon) {
    if (identical(_icons[slot], icon)) _icons.remove(slot);
  }

  void _measure(Duration _) {
    if (!mounted) return;
    final bar = context.findRenderObject();
    if (bar is! RenderBox || !bar.hasSize) return;
    final centers = List<Offset?>.generate(widget.destinations.length, (i) {
      final icon = _icons[i]?.findRenderObject();
      if (icon is! RenderBox || !icon.attached || !icon.hasSize) return null;
      return icon.localToGlobal(icon.size.center(Offset.zero), ancestor: bar);
    });
    if (!listEquals(centers, _centers)) setState(() => _centers = centers);
  }

  /// The pill resting on [index]'s icon, or null before it's measured.
  Rect? _restingOn(int index) {
    final center = index < _centers.length ? _centers[index] : null;
    return center == null ? null : Rect.fromCenter(center: center, width: _pillSize.width, height: _pillSize.height);
  }

  /// The pill at progress [t] of the move from [start] to [index].
  Rect? _pillRect(int index, Rect? start, double t) {
    final end = _restingOn(index);
    if (end == null || start == null || t >= 1) return end;
    final forward = end.center.dx >= start.center.dx;
    // The edge facing the move gets there quickly; the other one waits a
    // moment and catches up last, stretching the pill on the way.
    final lead = Curves.easeOutCubic.transform(t);
    final trail = const Interval(0.2, 1, curve: Curves.easeOutCubic).transform(t);
    final left = lerpDouble(start.left, end.left, forward ? trail : lead)!;
    final right = lerpDouble(start.right, end.right, forward ? lead : trail)!;
    final centerY = lerpDouble(start.center.dy, end.center.dy, lead)!;
    return _squashed(math.min(left, right), math.max(left, right), centerY);
  }

  /// A pill spanning [left]–[right], thinner the more it's stretched, like
  /// a drop pulled along.
  Rect _squashed(double left, double right, double centerY) {
    final stretch = ((right - left - _pillSize.width) / _pillSize.width).clamp(0.0, 1.0);
    final height = _pillSize.height * (1 - 0.18 * stretch);
    return Rect.fromLTRB(left, centerY - height / 2, right, centerY + height / 2);
  }

  /// The dragged pill: centred on [_pillX] and stretched back toward it
  /// from the finger by how far it trails.
  Rect _draggedRect() {
    final centerY = _centers.whereType<Offset>().first.dy;
    final lag = _fingerX - _pillX;
    final half = _pillSize.width / 2;
    final stretch = math.min(lag.abs() * 0.6, _pillSize.width * 0.8);
    final left = _pillX - half - (lag < 0 ? stretch : 0);
    final right = _pillX + half + (lag > 0 ? stretch : 0);
    return _squashed(left, right, centerY);
  }

  Rect? _currentRect() => _dragging ? _draggedRect() : _pillRect(widget.selectedIndex, _start, _controller.value);

  // ── Drag handling ──
  // A Listener (outside the gesture arena) so the drag also works after a
  // long hold, and taps on the destinations stay theirs: they cancel once
  // the finger moves past the touch slop, which is when dragging starts.

  bool get _canDrag => _centers.whereType<Offset>().length == widget.destinations.length;

  int _tabAt(double x) {
    var nearest = 0;
    for (var i = 1; i < _centers.length; i++) {
      if ((_centers[i]!.dx - x).abs() < (_centers[nearest]!.dx - x).abs()) nearest = i;
    }
    return nearest;
  }

  double _clampToTabs(double x) => x.clamp(_centers.first!.dx, _centers.last!.dx);

  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _downAt = event.localPosition;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || !_canDrag) return;
    if (!_dragging) {
      if ((event.localPosition.dx - _downAt!.dx).abs() <= kTouchSlop) return;
      _pillX = _currentRect()?.center.dx ?? _clampToTabs(event.localPosition.dx);
      _hovered = widget.selectedIndex;
      _dragging = true;
      _lastTick = Duration.zero;
      _dragTicker.start();
    }
    _fingerX = _clampToTabs(event.localPosition.dx);
    final hovered = _tabAt(_fingerX);
    if (hovered != _hovered) {
      _hovered = hovered;
      selectionHaptic();
    }
  }

  void _onPointerUp(PointerUpEvent event) => _endDrag(event.pointer, select: true);

  void _onPointerCancel(PointerCancelEvent event) => _endDrag(event.pointer, select: false);

  void _endDrag(int pointer, {required bool select}) {
    if (pointer != _pointer) return;
    _pointer = null;
    if (!_dragging) return;
    final released = _draggedRect();
    _dragging = false;
    _dragTicker.stop();
    final target = select ? _tabAt(_fingerX) : widget.selectedIndex;
    if (target != widget.selectedIndex) {
      // didUpdateWidget picks the move up from here.
      _releasedAt = released;
      widget.onDestinationSelected(target);
    } else {
      _start = released;
      _settle();
    }
  }

  void _followFinger(Duration elapsed) {
    // Eases toward the finger by elapsed time (the same at 60 or 120 Hz),
    // so the pill trails it and catches up when it stops. No trailing
    // when animations are reduced.
    final dt = (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    final follow = AppMotion.reduced(context) ? 1.0 : 1 - math.exp(-dt / 0.06);
    _pillX += (_fingerX - _pillX) * follow;
    if ((_fingerX - _pillX).abs() < 0.5) _pillX = _fingerX;
    _dragFrame.value++;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt (and re-measured) when the screen, insets or text size change.
    MediaQuery.sizeOf(context);
    MediaQuery.paddingOf(context);
    MediaQuery.textScalerOf(context);
    WidgetsBinding.instance.addPostFrameCallback(_measure);

    final barTheme = NavigationBarTheme.of(context);
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: barTheme.backgroundColor ?? colors.surfaceContainer)),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: LiquidNavigationBar.pillKey,
              painter: _PillPainter(
                repaint: Listenable.merge([_controller, _dragFrame]),
                rect: _currentRect,
                color: colors.primary,
                centers: _centers,
                selectedIndex: widget.selectedIndex,
              ),
            ),
          ),
        ),
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            selectedIndex: widget.selectedIndex,
            onDestinationSelected: widget.onDestinationSelected,
            destinations: [
              for (final (i, d) in widget.destinations.indexed)
                NavigationDestination(
                  icon: _IconProbe(slot: i, register: _register, unregister: _unregister, child: d.icon),
                  selectedIcon:
                      _IconProbe(slot: i, register: _register, unregister: _unregister, child: d.selectedIcon),
                  label: d.label,
                  // The label is always shown; a long-press tooltip would
                  // only cover the bar while dragging along it.
                  tooltip: '',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tells the bar which element shows a tab's icon, so it can measure it.
class _IconProbe extends StatefulWidget {
  const _IconProbe({required this.slot, required this.register, required this.unregister, required this.child});

  final int slot;
  final void Function(int slot, BuildContext icon) register;
  final void Function(int slot, BuildContext icon) unregister;
  final Widget child;

  @override
  State<_IconProbe> createState() => _IconProbeState();
}

class _IconProbeState extends State<_IconProbe> {
  @override
  void initState() {
    super.initState();
    widget.register(widget.slot, context);
  }

  @override
  void didUpdateWidget(_IconProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slot != widget.slot) {
      oldWidget.unregister(oldWidget.slot, context);
      widget.register(widget.slot, context);
    }
  }

  @override
  void dispose() {
    widget.unregister(widget.slot, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PillPainter extends CustomPainter {
  _PillPainter({
    required Listenable repaint,
    required this.rect,
    required this.color,
    required this.centers,
    required this.selectedIndex,
  }) : super(repaint: repaint);

  final Rect? Function() rect;
  final Color color;

  // Only compared in shouldRepaint: rect reads them.
  final List<Offset?> centers;
  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final pill = rect();
    if (pill == null) return;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.26), color.withValues(alpha: 0.14)],
      ).createShader(pill);
    canvas.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(pill.height / 2)), paint);
  }

  @override
  bool shouldRepaint(_PillPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selectedIndex != selectedIndex ||
      !identical(oldDelegate.centers, centers);
}

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

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
/// The pill is painted under a transparent NavigationBar, which keeps its
/// own layout, semantics and taps. The pill is placed on the icons' real
/// boxes, measured after layout, so it stays centred whatever the label
/// height, text scale or safe area.
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

class _LiquidNavigationBarState extends State<LiquidNavigationBar> with SingleTickerProviderStateMixin {
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

  @override
  void didUpdateWidget(LiquidNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex == widget.selectedIndex) return;
    // Leave from wherever the pill is now, even halfway through a move.
    _start = _pillRect(oldWidget.selectedIndex, _start, _controller.value);
    final duration = AppMotion.of(context, AppMotion.long);
    if (duration == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.duration = duration;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    // Thinner while stretched, like a drop pulled along.
    final stretch = ((right - left - end.width) / end.width).clamp(0.0, 1.0);
    final height = end.height * (1 - 0.18 * stretch);
    return Rect.fromLTRB(math.min(left, right), centerY - height / 2, math.max(left, right), centerY + height / 2);
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
                progress: _controller,
                rectAt: (t) => _pillRect(widget.selectedIndex, _start, t),
                color: colors.primary,
                centers: _centers,
                selectedIndex: widget.selectedIndex,
              ),
            ),
          ),
        ),
        NavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          selectedIndex: widget.selectedIndex,
          onDestinationSelected: widget.onDestinationSelected,
          destinations: [
            for (final (i, d) in widget.destinations.indexed)
              NavigationDestination(
                icon: _IconProbe(slot: i, register: _register, unregister: _unregister, child: d.icon),
                selectedIcon: _IconProbe(slot: i, register: _register, unregister: _unregister, child: d.selectedIcon),
                label: d.label,
              ),
          ],
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
    required this.progress,
    required this.rectAt,
    required this.color,
    required this.centers,
    required this.selectedIndex,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Rect? Function(double t) rectAt;
  final Color color;

  // Only compared in shouldRepaint: rectAt reads them.
  final List<Offset?> centers;
  final int selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = rectAt(progress.value);
    if (rect == null) return;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.26), color.withValues(alpha: 0.14)],
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)), paint);
  }

  @override
  bool shouldRepaint(_PillPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selectedIndex != selectedIndex ||
      !identical(oldDelegate.centers, centers) ||
      oldDelegate.progress != progress;
}

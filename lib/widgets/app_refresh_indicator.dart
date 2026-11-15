import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../utils/haptics.dart';

/// Pull-to-refresh with the app's own indicator: a spark that grows and
/// turns as the list is pulled, clicks when it has been pulled far enough,
/// and spins while [onRefresh] runs.
///
/// When a pull counts as a refresh is Flutter's own rule (see
/// [RefreshIndicator]); only what is shown differs. [edgeOffset] moves the
/// spark down, for a list that starts under a floating button or the status
/// bar.
class AppRefreshIndicator extends StatefulWidget {
  const AppRefreshIndicator({super.key, required this.onRefresh, required this.child, this.edgeOffset = 0});

  final RefreshCallback onRefresh;
  final Widget child;
  final double edgeOffset;

  @override
  State<AppRefreshIndicator> createState() => _AppRefreshIndicatorState();
}

class _AppRefreshIndicatorState extends State<AppRefreshIndicator> with TickerProviderStateMixin {
  // The share of the list's height a pull must cover: Flutter's own.
  static const _pullShare = 0.25;
  static const _size = 40.0;
  static const _restTop = 12.0;
  static const _travel = 24.0;

  /// How far out the spark is: 0 away, 1 fully there.
  late final AnimationController _shown = AnimationController(vsync: this, duration: AppMotion.medium);
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  RefreshIndicatorStatus? _status;
  // On Android the list does not move past its edge: the pull is added up.
  double _overscroll = 0;

  bool get _refreshing => _status == RefreshIndicatorStatus.snap || _status == RefreshIndicatorStatus.refresh;

  @override
  void dispose() {
    _shown.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _statusChanged(RefreshIndicatorStatus? status) {
    final wasRefreshing = _refreshing;
    _status = status;
    switch (status) {
      case RefreshIndicatorStatus.armed:
        selectionHaptic();
      case RefreshIndicatorStatus.snap || RefreshIndicatorStatus.refresh:
        if (wasRefreshing) return;
        _shown.animateTo(1, curve: AppMotion.standard);
        if (!AppMotion.reduced(context)) _spin.repeat();
      case RefreshIndicatorStatus.done || RefreshIndicatorStatus.canceled || null:
        _overscroll = 0;
        _shown.animateTo(0, curve: AppMotion.exit).whenCompleteOrCancel(() {
          if (mounted && !_refreshing) _spin.reset();
        });
      case RefreshIndicatorStatus.drag:
        break;
    }
  }

  /// Follows the finger: the spark is as far out as the list is pulled.
  bool _scrolled(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical || _refreshing) return false;
    final metrics = notification.metrics;
    if (notification is ScrollEndNotification) {
      _overscroll = 0;
      return false;
    }
    final double pull;
    if (metrics.pixels < metrics.minScrollExtent) {
      // iOS: the list itself is past its edge.
      pull = metrics.minScrollExtent - metrics.pixels;
    } else if (notification is OverscrollNotification && notification.overscroll < 0) {
      _overscroll -= notification.overscroll;
      pull = _overscroll;
    } else if (notification is ScrollUpdateNotification && _overscroll > 0) {
      // Pushed back up before letting go.
      _overscroll = math.max(0, _overscroll - (notification.scrollDelta ?? 0));
      pull = _overscroll;
    } else {
      return false;
    }
    if (_status == RefreshIndicatorStatus.drag || _status == RefreshIndicatorStatus.armed) {
      _shown.value = (pull / (metrics.viewportDimension * _pullShare)).clamp(0.0, 1.0);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _scrolled,
          child: RefreshIndicator.noSpinner(
            onRefresh: widget.onRefresh,
            onStatusChange: _statusChanged,
            child: widget.child,
          ),
        ),
        Positioned(
          top: widget.edgeOffset + _restTop,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge([_shown, _spin]),
              builder: (context, _) {
                final shown = _shown.value;
                if (shown == 0) return const SizedBox.shrink();
                // A pull turns it half way round; refreshing keeps it turning.
                final turns = shown * 0.5 + _spin.value;
                return Transform.translate(
                  offset: Offset(0, _travel * shown),
                  child: Center(
                    child: Opacity(
                      opacity: math.min(1, shown * 2),
                      child: Transform.scale(
                        scale: 0.5 + 0.5 * shown,
                        child: Container(
                          width: _size,
                          height: _size,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
                          ),
                          child: Center(
                            child: Transform.rotate(
                              angle: turns * 2 * math.pi,
                              child: SparkMark(size: _size * 0.5, color: cs.primary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// AniSpark's spark: a four-pointed star with pinched sides.
class SparkMark extends StatelessWidget {
  const SparkMark({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _SparkPainter(color));
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.color);

  final Color color;

  /// How far in the sides are pinched, as a share of the radius.
  static const _waist = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final w = r * _waist;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) => oldDelegate.color != color;
}

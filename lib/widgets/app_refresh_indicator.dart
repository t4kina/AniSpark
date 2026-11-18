import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../utils/haptics.dart';

/// Pull-to-refresh with the iPhone's own indicator: its spokes appear one
/// by one as the list is pulled, it clicks when it has been pulled far
/// enough, and it spins while [onRefresh] runs. No disc around it.
///
/// When a pull counts as a refresh is Flutter's own rule (see
/// [RefreshIndicator]); only what is shown differs. [edgeOffset] moves the
/// indicator down, for a list that starts under a floating button or the status
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
  static const _radius = 11.0;
  static const _restTop = 12.0;
  static const _travel = 24.0;

  /// How far out the indicator is: 0 away, 1 fully there.
  late final AnimationController _shown = AnimationController(vsync: this, duration: AppMotion.medium);
  RefreshIndicatorStatus? _status;
  // On Android the list does not move past its edge: the pull is added up.
  double _overscroll = 0;

  bool get _refreshing => _status == RefreshIndicatorStatus.snap || _status == RefreshIndicatorStatus.refresh;

  @override
  void dispose() {
    _shown.dispose();
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
        setState(() {});
      case RefreshIndicatorStatus.done || RefreshIndicatorStatus.canceled || null:
        _overscroll = 0;
        _shown.animateTo(0, curve: AppMotion.exit);
        setState(() {});
      case RefreshIndicatorStatus.drag:
        break;
    }
  }

  /// Follows the finger: the indicator is as far out as the list is pulled.
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
    final color = context.colors.textSecondary;
    final spinning = _refreshing && !AppMotion.reduced(context);
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
              animation: _shown,
              builder: (context, _) {
                final shown = _shown.value;
                if (shown == 0) return const SizedBox.shrink();
                return Transform.translate(
                  offset: Offset(0, _travel * shown),
                  child: Center(
                    child: Opacity(
                      opacity: math.min(1, shown * 2),
                      child: _refreshing
                          ? CupertinoActivityIndicator(radius: _radius, color: color, animating: spinning)
                          : CupertinoActivityIndicator.partiallyRevealed(
                              radius: _radius,
                              color: color,
                              progress: shown,
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

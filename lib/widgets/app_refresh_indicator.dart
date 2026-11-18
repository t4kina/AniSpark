import 'package:flutter/material.dart';

/// Pull-to-refresh as the app first had it: Flutter's own spinner, in the
/// accent colour, coming down from the top of the list.
///
/// Every list that can be pulled uses this, so the look lives in one place.
/// [edgeOffset] moves the spinner down, for a list that starts under a
/// floating button or the status bar.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({super.key, required this.onRefresh, required this.child, this.edgeOffset = 0});

  final RefreshCallback onRefresh;
  final Widget child;
  final double edgeOffset;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        edgeOffset: edgeOffset,
        color: Theme.of(context).colorScheme.primary,
        child: child,
      );
}

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';

/// Grows [child] into place with a small spring when it first appears, e.g.
/// the icon of the bottom-navigation tab that was just selected.
class PopIn extends StatefulWidget {
  const PopIn({super.key, required this.child, this.from = 0.8});

  final Widget child;

  /// The starting size.
  final double from;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.medium);
  late final Animation<double> _scale = Tween(begin: widget.from, end: 1.0)
      .chain(CurveTween(curve: Curves.easeOutBack))
      .animate(_controller);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale, child: widget.child);
}

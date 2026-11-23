import 'package:flutter/material.dart';

/// Tells [builder] whether the page it is on has finished sliding in.
///
/// A picture that flies to this page (see `RoundedHero`) needs somewhere to
/// land that holds still: a page that swapped its placeholder for its
/// content mid-flight would take the landing spot away. So such a page
/// keeps its placeholder until it has arrived.
///
/// A page that was never pushed (the first one) has arrived from the start,
/// and once arrived it stays so, also while it is being popped.
class ArrivalBuilder extends StatefulWidget {
  const ArrivalBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, bool arrived) builder;

  @override
  State<ArrivalBuilder> createState() => _ArrivalBuilderState();
}

class _ArrivalBuilderState extends State<ArrivalBuilder> {
  ModalRoute<Object?>? _route;
  Animation<double>? _entrance;
  bool _arrived = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrived) return;
    final route = ModalRoute.of(context);
    if (route == _route) return;
    _entrance?.removeStatusListener(_entranceChanged);
    _route = route;
    _entrance = route?.animation?..addStatusListener(_entranceChanged);
    _arrived = _hasArrived;
    // A page is built once out of sight, to measure where pictures flying
    // to it will land, and looks arrived meanwhile: ask again after it.
    if (route != null && route.offstage) WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _entrance?.removeStatusListener(_entranceChanged);
    super.dispose();
  }

  bool get _hasArrived {
    final route = _route;
    final entrance = _entrance;
    return route == null || entrance == null || (entrance.isCompleted && !route.offstage);
  }

  void _entranceChanged(AnimationStatus status) => _check();

  void _check() {
    if (!mounted || _arrived || !_hasArrived) return;
    _entrance?.removeStatusListener(_entranceChanged);
    setState(() => _arrived = true);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _arrived);
}

import 'package:flutter/widgets.dart';

/// Tells the tab screens when the user taps the tab that is already open,
/// so that tab can scroll back to the top.
class TabReselectNotifier extends ChangeNotifier {
  int? _tab;

  /// The tab tapped again most recently.
  int? get tab => _tab;

  /// Notifies listeners even when the same tab is tapped repeatedly.
  void reselect(int tab) {
    _tab = tab;
    notifyListeners();
  }
}

/// The app's bottom-navigation reselection events.
final tabReselectedNotifier = TabReselectNotifier();

/// Calls [onReselected] whenever [tab] is tapped again. Returns a function
/// that stops listening (call it from `dispose`).
VoidCallback scrollToTopOnReselect(
  TabReselectNotifier notifier, {
  required int tab,
  required VoidCallback onReselected,
}) {
  void listener() {
    if (notifier.tab == tab) onReselected();
  }

  notifier.addListener(listener);
  return () => notifier.removeListener(listener);
}

/// Scrolls [controller]'s scroll view back to the top, smoothly unless
/// [animate] is false (pass `!AppMotion.reduced(context)`); does nothing
/// when no scroll view uses it.
void scrollToTop(ScrollController controller, {bool animate = true}) {
  if (!controller.hasClients) return;
  if (!animate) {
    controller.jumpTo(0);
    return;
  }
  controller.animateTo(
    0,
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeOutCubic,
  );
}

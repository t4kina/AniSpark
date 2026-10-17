import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../utils/refresh_notifier.dart' show rateLimitActiveNotifier;
import '../utils/translations.dart' show tr;

/// While AniList rate-limits the app (it waits and retries), says so with
/// the app's usual floating snack bar, and removes it once the wait is
/// over. Wraps the navigator from `MaterialApp.builder`, which sits below
/// the app's ScaffoldMessenger.
class RateLimitNotice extends StatefulWidget {
  const RateLimitNotice({super.key, required this.child});

  final Widget child;

  @override
  State<RateLimitNotice> createState() => _RateLimitNoticeState();
}

class _RateLimitNoticeState extends State<RateLimitNotice> {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _notice;

  @override
  void initState() {
    super.initState();
    rateLimitActiveNotifier.addListener(_sync);
    // In case a wait had already started.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    rateLimitActiveNotifier.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (!rateLimitActiveNotifier.value) {
      _notice?.close();
      _notice = null;
      return;
    }
    if (_notice != null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final lang = context.read<SettingsProvider>().language;
    final notice = messenger.showSnackBar(SnackBar(
      content: Text(tr('rate_limit_banner', lang)),
      // Shown for as long as the wait lasts, then closed above.
      duration: const Duration(days: 1),
    ));
    _notice = notice;
    notice.closed.then((_) {
      if (identical(_notice, notice)) _notice = null;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

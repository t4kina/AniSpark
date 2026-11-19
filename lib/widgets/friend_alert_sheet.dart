import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/friend_alerts.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_text.dart';
import '../utils/haptics.dart';
import '../utils/translations.dart';
import 'app_sheet.dart';
import 'dev_badge.dart';
import 'sheet_list_surface.dart';
import 'social/social_widgets.dart' show openUserProfile;
import 'user_avatar.dart';

/// The bell of one friend: what to be told about them, each switched on or
/// off at once, and a way to stop altogether.
Future<void> showFriendAlertSheet(
  BuildContext context, {
  required int userId,
  required String name,
  String? avatarUrl,
}) =>
    showAppSheet<void>(
      context: context,
      builder: (_) => _FriendAlertSheet(userId: userId, name: name, avatarUrl: avatarUrl),
    );

/// Every friend whose bell is on, each opening their profile or turned off
/// with a cross.
Future<void> showFriendBellsSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      maxHeightFraction: 0.7,
      builder: (_) => const _FriendBellsSheet(),
    );

/// Asks for the right to notify the first time a bell is turned on, and
/// switches notifications on with it. False when it was refused.
Future<bool> _ensureNotifications(BuildContext context) async {
  final settings = context.read<SettingsProvider>();
  if (settings.pushNotifications) return true;
  final granted = await NotificationService().requestPermission();
  if (granted) await settings.setPushNotifications(true);
  return granted;
}

class _FriendAlertSheet extends StatelessWidget {
  const _FriendAlertSheet({required this.userId, required this.name, this.avatarUrl});

  final int userId;
  final String name;
  final String? avatarUrl;

  static const _kindKeys = {
    FriendAlertKind.progress: 'bell_progress',
    FriendAlertKind.status: 'bell_status',
    FriendAlertKind.text: 'bell_text',
  };

  Future<void> _toggle(BuildContext context, FriendAlertKind kind) async {
    final store = context.read<FriendAlertsStore>();
    final lang = context.read<SettingsProvider>().language;
    final messenger = ScaffoldMessenger.of(context);
    final current = store.watchOf(userId)?.kinds ?? const <FriendAlertKind>{};
    final next = current.contains(kind) ? ({...current}..remove(kind)) : {...current, kind};
    if (current.isEmpty && next.isNotEmpty && !await _ensureNotifications(context)) {
      messenger.showSnackBar(SnackBar(content: Text(tr('settings_enable_notifications', lang))));
      return;
    }
    selectionHaptic();
    await store.watch(userId: userId, name: name, avatarUrl: avatarUrl, kinds: next);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final watch = context.watch<FriendAlertsStore>().watchOf(userId);
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle(trf('bell_title', lang, {'name': name})),
            _Block(
              children: [
                for (final MapEntry(key: kind, value: key) in _kindKeys.entries)
                  ListTile(
                    key: ValueKey('bell-${kind.name}'),
                    tileColor: Colors.transparent,
                    shape: const RoundedRectangleBorder(),
                    title: Text(tr(key, lang), style: AppText.subhead.copyWith(fontWeight: FontWeight.w500)),
                    trailing: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: watch?.kinds.contains(kind) ?? false
                          ? Icon(Icons.check_rounded, key: const ValueKey('on'), color: cs.primary)
                          : const SizedBox(key: ValueKey('off'), width: 24),
                    ),
                    onTap: () => _toggle(context, kind),
                  ),
              ],
            ),
            if (watch != null) ...[
              const SizedBox(height: AppSpace.md),
              _Block(
                children: [
                  ListTile(
                    tileColor: Colors.transparent,
                    shape: const RoundedRectangleBorder(),
                    title: Text(tr('bell_off', lang), style: AppText.subhead.copyWith(color: context.colors.danger)),
                    onTap: () {
                      selectionHaptic();
                      context.read<FriendAlertsStore>().unwatch(userId);
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.md),
            Text(
              tr('bell_note', lang),
              style: AppText.caption.copyWith(color: context.colors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendBellsSheet extends StatelessWidget {
  const _FriendBellsSheet();

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final store = context.watch<FriendAlertsStore>();
    final watches = store.watches;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(tr('settings_friend_bells', lang)),
          if (watches.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.xl),
              child: Text(
                tr('settings_no_bells', lang),
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: context.colors.textSecondary),
              ),
            )
          else
            Flexible(
              child: SheetListSurface(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.lg),
                  children: [
                    for (final watch in watches)
                      ListTile(
                        key: ValueKey('bell-friend-${watch.userId}'),
                        leading: UserAvatar(url: watch.avatarUrl, size: 40),
                        title: BadgedName(watch.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        onTap: () {
                          Navigator.pop(context);
                          openUserProfile(context, {
                            'id': watch.userId,
                            'name': watch.name,
                            'avatar': {'large': watch.avatarUrl},
                          });
                        },
                        trailing: IconButton(
                          tooltip: tr('bell_off', lang),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => store.unwatch(watch.userId),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rows on one rounded block, split by hairlines.
class _Block extends StatelessWidget {
  const _Block({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.mdAll,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: AppSpace.lg),
              children[i],
            ],
          ],
        ),
      );
}

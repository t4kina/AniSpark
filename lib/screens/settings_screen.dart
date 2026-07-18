import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/settings_provider.dart' show SettingsProvider, accentColorOptions;
import '../services/auth_service.dart';
import '../utils/translations.dart';
import '../utils/refresh_notifier.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthService>();
    final lang = settings.language;
    final username = auth.user?['name'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('settings', lang),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── General ──
          _sectionHeader(tr('general', lang)),
          _tile(
            icon: Icons.language,
            label: tr('language', lang),
            trailing: Text(lang,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            onTap: () => _showPicker(
              context: context,
              title: tr('language', lang),
              options: const ['English', 'Spanish', 'Japanese', 'French', 'German', 'Portuguese', 'Italian', 'Korean'],
              current: lang,
              onSelected: (v) => context.read<SettingsProvider>().setLanguage(v),
            ),
          ),
          _tile(
            icon: Icons.palette_outlined,
            label: tr('appearance', lang),
            trailing: Text(settings.appearance,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            onTap: () => _showPicker(
              context: context,
              title: tr('appearance', lang),
              options: const ['Dark', 'Light'],
              current: settings.appearance,
              onSelected: (v) => context.read<SettingsProvider>().setAppearance(v),
            ),
          ),
          _tile(
            icon: Icons.color_lens_outlined,
            label: tr('accent_color', lang),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: settings.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(settings.accentColorName,
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
            onTap: () => _showAccentColorPicker(context, settings, lang),
          ),
          _tile(
            icon: Icons.title,
            label: tr('title_language', lang),
            trailing: Text(settings.titleLanguage,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            onTap: () => _showPicker(
              context: context,
              title: tr('title_language', lang),
              options: const ['English', 'Romaji', 'Native'],
              current: settings.titleLanguage,
              onSelected: (v) => context.read<SettingsProvider>().setTitleLanguage(v),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // ── Notifications ──
          _sectionHeader(tr('notifications', lang)),
          _switchTile(
            icon: Icons.notifications_outlined,
            label: tr('push_notifications', lang),
            value: settings.pushNotifications,
            onChanged: (v) async {
              final sp = context.read<SettingsProvider>();
              final messenger = ScaffoldMessenger.of(context);
              await sp.setPushNotifications(v);
              if (v) {
                final granted = await NotificationService().requestPermission();
                if (!granted && context.mounted) {
                  await sp.setPushNotifications(false);
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Enable notifications in System Settings'),
                  ));
                }
              } else {
                await NotificationService().cancelAll();
              }
            },
          ),
          _switchTile(
            icon: Icons.new_releases_outlined,
            label: tr('new_episode_alerts', lang),
            value: settings.newEpisodeAlerts,
            onChanged: (v) async {
              final sp = context.read<SettingsProvider>();
              final messenger = ScaffoldMessenger.of(context);
              await sp.setNewEpisodeAlerts(v);
              if (v) {
                final granted = await NotificationService().requestPermission();
                if (!granted && context.mounted) {
                  await sp.setNewEpisodeAlerts(false);
                  messenger.showSnackBar(const SnackBar(
                    content: Text('Enable notifications in System Settings'),
                  ));
                } else if (context.mounted) {
                  listRefreshNotifier.value++;
                }
              } else {
                await NotificationService().cancelAll();
              }
            },
          ),
          _switchTile(
            icon: Icons.group_outlined,
            label: tr('friend_activity_alerts', lang),
            value: settings.friendActivityAlerts,
            onChanged: (v) async {
              await context.read<SettingsProvider>().setFriendActivityAlerts(v);
            },
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // ── Data ──
          _sectionHeader(tr('data_storage', lang)),
          _tile(
            icon: Icons.cached,
            label: tr('clear_cache', lang),
            onTap: () => _clearImageCache(context, lang),
          ),
          _tile(
            icon: Icons.sync,
            label: tr('sync_anilist', lang),
            onTap: () => _syncWithAniList(context, auth, lang),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // ── Account ──
          _sectionHeader(tr('account', lang)),
          _tile(
            icon: Icons.open_in_new,
            label: tr('view_on_anilist', lang),
            onTap: () {
              if (username != null) {
                _openUrl('https://anilist.co/user/$username');
              }
            },
          ),
          _tile(
            icon: Icons.logout,
            label: tr('logout', lang),
            color: Colors.red,
            onTap: () => _confirmLogout(context, auth, lang),
          ),

          const SizedBox(height: 8),
          const Divider(height: 1),

          // ── About ──
          _sectionHeader(tr('about', lang)),
          _tile(
            icon: Icons.info_outline,
            label: tr('about_anispark', lang),
            onTap: () => _showAbout(context, lang),
          ),
          _tile(
            icon: Icons.description_outlined,
            label: tr('terms', lang),
            onTap: () => _openUrl('https://anilist.co/terms'),
          ),

          const SizedBox(height: 24),
          const Center(child: Text('AniSpark v1.0.0', style: TextStyle(color: Colors.grey, fontSize: 12))),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5)),
      );

  static Widget _switchTile({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      ListTile(
        leading: Icon(icon, color: Colors.grey, size: 22),
        title: Text(label, style: const TextStyle(fontSize: 14)),
        trailing: Builder(builder: (ctx) => Transform.scale(
          scale: 0.75,
          child: CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: Theme.of(ctx).colorScheme.primary,
          ),
        )),
        onTap: () => onChanged(!value),
      );

  static Widget _tile({
    required IconData icon,
    required String label,
    Color? color,
    Widget? trailing,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon, color: color ?? Colors.grey, size: 22),
        title: Text(label, style: TextStyle(color: color, fontSize: 14)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        onTap: onTap,
      );

  static void _showPicker({
    required BuildContext context,
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
              ),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: options.map((opt) => Builder(builder: (ctx) => ListTile(
                    leading: Icon(
                      current == opt ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: current == opt ? Theme.of(ctx).colorScheme.primary : Colors.grey,
                      size: 20,
                    ),
                    title: Text(opt,
                        style: TextStyle(
                            color: current == opt ? Theme.of(ctx).colorScheme.primary : null,
                            fontSize: 14)),
                    onTap: () {
                      onSelected(opt);
                      Navigator.pop(context);
                    },
                  ))).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showAccentColorPicker(
      BuildContext context, SettingsProvider settings, String lang) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2)),
              ),
              Text(tr('accent_color', lang),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: accentColorOptions.entries.map((e) {
                  final isSelected = settings.accentColorName == e.key;
                  return GestureDetector(
                    onTap: () {
                      context.read<SettingsProvider>().setAccentColor(e.key);
                      Navigator.pop(context);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: Colors.white, width: 3)
                                : null,
                            boxShadow: isSelected
                                ? [BoxShadow(color: e.value.withValues(alpha: 0.6), blurRadius: 8)]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 20)
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(e.key,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static void _showAbout(BuildContext context, String lang) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo.jpg', width: 40, height: 40),
            ),
            const SizedBox(width: 12),
            const Text('AniSpark', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Version 1.0.0', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            Text(tr('about_description', lang),
                style: const TextStyle(color: Colors.grey, height: 1.5, fontSize: 13)),
            const SizedBox(height: 12),
            Text(tr('made_with', lang), style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Builder(builder: (ctx) => Text(tr('close', lang), style: TextStyle(color: Theme.of(ctx).colorScheme.primary))),
          ),
        ],
      ),
    );
  }

  static Future<void> _clearImageCache(BuildContext context, String lang) async {
    await DefaultCacheManager().emptyCache();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image cache cleared'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  static Future<void> _syncWithAniList(
      BuildContext context, AuthService auth, String lang) async {
    if (!auth.isLoggedIn) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Syncing with AniList…'),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    await auth.fetchUser();
    profileRefreshNotifier.value++;
    listRefreshNotifier.value++;
    feedRefreshNotifier.value++;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Synced successfully'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  static void _confirmLogout(BuildContext context, AuthService auth, String lang) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('logout', lang)),
        content: Text(tr('logout_confirm', lang)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('cancel', lang))),
          TextButton(
            onPressed: () {
              auth.logout();
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text(tr('logout', lang), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

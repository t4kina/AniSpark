import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/external_url.dart';
import '../providers/settings_provider.dart' show SettingsProvider, accentColorOptions;
import '../services/auth_service.dart';
import '../utils/translations.dart';
import '../utils/refresh_notifier.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../services/notification_service.dart';

// The pickers below store these maps' keys and only show their labels.

/// Each language in its own name, so it can be found whatever is selected.
const _languageNames = {
  'English': 'English',
  'Spanish': 'Español',
  'Japanese': '日本語',
  'French': 'Français',
  'German': 'Deutsch',
  'Portuguese': 'Português',
  'Italian': 'Italiano',
  'Korean': '한국어',
};

const _appearanceKeys = {
  'Dark': 'settings_appearance_dark',
  'Light': 'settings_appearance_light',
  'System': 'settings_appearance_system',
};

const _titleLanguageKeys = {
  'English': 'settings_title_english',
  'Romaji': 'settings_title_romaji',
  'Native': 'settings_title_native',
};

const _accentColorKeys = {
  'Blue': 'settings_color_blue',
  'Purple': 'settings_color_purple',
  'Green': 'settings_color_green',
  'Pink': 'settings_color_pink',
  'Teal': 'settings_color_teal',
  'Orange': 'settings_color_orange',
};

/// The translated label of a stored [value], or [value] itself if unknown.
String _labelOf(Map<String, String> keys, String value, String lang) {
  final key = keys[value];
  return key == null ? value : tr(key, lang);
}

const _appVersion = '1.0.0';

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
            trailing: Text(_languageNames[lang] ?? lang,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            onTap: () => _showPicker(
              context: context,
              title: tr('language', lang),
              options: _languageNames.keys.toList(),
              labelOf: (v) => _languageNames[v] ?? v,
              current: lang,
              onSelected: (v) => context.read<SettingsProvider>().setLanguage(v),
            ),
          ),
          _tile(
            icon: Icons.palette_outlined,
            label: tr('appearance', lang),
            trailing: Text(_labelOf(_appearanceKeys, settings.appearance, lang),
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            onTap: () => _showPicker(
              context: context,
              title: tr('appearance', lang),
              options: _appearanceKeys.keys.toList(),
              labelOf: (v) => _labelOf(_appearanceKeys, v, lang),
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
                Text(_labelOf(_accentColorKeys, settings.accentColorName, lang),
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
            onTap: () => _showAccentColorPicker(context, settings, lang),
          ),
          _tile(
            icon: Icons.title,
            label: tr('title_language', lang),
            trailing: Text(_labelOf(_titleLanguageKeys, settings.titleLanguage, lang),
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            onTap: () => _showPicker(
              context: context,
              title: tr('title_language', lang),
              options: _titleLanguageKeys.keys.toList(),
              labelOf: (v) => _labelOf(_titleLanguageKeys, v, lang),
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
                  messenger.showSnackBar(SnackBar(
                    content: Text(tr('settings_enable_notifications', lang)),
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
                  messenger.showSnackBar(SnackBar(
                    content: Text(tr('settings_enable_notifications', lang)),
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
                _openUrl('https://anilist.co/user/${Uri.encodeComponent(username)}');
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
          const Center(child: Text('AniSpark v$_appVersion', style: TextStyle(color: Colors.grey, fontSize: 12))),
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
    required String Function(String option) labelOf,
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
                    title: Text(labelOf(opt),
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
                        Text(_labelOf(_accentColorKeys, e.key, lang),
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

  static Future<void> _openUrl(String url) => openExternalUrl(url);

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
            Text(trf('settings_version', lang, {'v': _appVersion}),
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
        SnackBar(
          content: Text(tr('settings_cache_cleared', lang)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static Future<void> _syncWithAniList(
      BuildContext context, AuthService auth, String lang) async {
    if (!auth.isLoggedIn) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(tr('settings_syncing', lang)),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );

    await auth.fetchUser();
    profileRefreshNotifier.value++;
    listRefreshNotifier.value++;
    feedRefreshNotifier.value++;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr('settings_synced', lang)),
        duration: const Duration(seconds: 2),
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

import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/external_url.dart';
import '../utils/haptics.dart';
import '../utils/performance_graphs.dart';
import '../widgets/dev_badge.dart';
import '../providers/settings_provider.dart' show SettingsProvider, accentColorOptions;
import '../services/auth_service.dart';
import '../utils/translations.dart';
import '../utils/refresh_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_text.dart';
import '../widgets/app_button.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_sheet.dart';
import '../widgets/motion/pressable.dart';
import '../widgets/option_sheet.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../services/notification_service.dart';
import 'search_screen.dart' show recentSearchesPrefsKey;

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

/// MainNavigation's tab order: Anime, Manga, Discover, Feed, Profile.
const _tabLabelKeys = {
  0: 'nav_anime',
  1: 'nav_manga',
  2: 'nav_discover',
  3: 'nav_feed',
  4: 'nav_profile',
};

/// The bottom bar's icons for [_tabLabelKeys].
const _tabIcons = {
  0: Icons.smart_display_outlined,
  1: Icons.collections_bookmark_outlined,
  2: Icons.travel_explore_outlined,
  3: Icons.article_outlined,
  4: Icons.person_outline_rounded,
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

/// The version line, which switches the frame timing graphs on or off
/// after [taps] taps in a row (see `performanceGraphsNotifier`): a tool to
/// find what stutters on a real phone, out of everyone's way.
class _VersionTapper extends StatefulWidget {
  const _VersionTapper({required this.child});

  final Widget child;

  static const taps = 7;

  /// Taps further apart than this start the count again.
  static const _window = Duration(seconds: 2);

  @override
  State<_VersionTapper> createState() => _VersionTapperState();
}

class _VersionTapperState extends State<_VersionTapper> {
  int _count = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void _tap() {
    final now = DateTime.now();
    _count = now.difference(_last) > _VersionTapper._window ? 1 : _count + 1;
    _last = now;
    if (_count < _VersionTapper.taps) return;
    _count = 0;
    performanceGraphsNotifier.value = !performanceGraphsNotifier.value;
    mediumHaptic();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: Padding(padding: const EdgeInsets.all(AppSpace.sm), child: widget.child),
      );
}

/// Shows the installed app's version (from the build, e.g. pubspec's 1.0.0).
class _AppVersion extends StatelessWidget {
  const _AppVersion({required this.builder});

  final Widget Function(String version) builder;

  static final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
        future: _info,
        builder: (_, snapshot) => builder(snapshot.data?.version ?? ''),
      );
}

/// The avatar, name and "Signed in as" caption shown atop the Account
/// section, so it's clear which AniList account is active.
class _SignedInAsRow extends StatelessWidget {
  const _SignedInAsRow({required this.auth, required this.lang});

  final AuthService auth;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final user = auth.user;
    final name = user?['name'] as String?;
    final avatar = user?['avatar'];
    final avatarUrl = avatar is Map ? avatar['large'] as String? : null;
    return Padding(
      padding: const EdgeInsets.all(_Group.inset),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            backgroundImage: avatarUrl == null ? null : CachedNetworkImageProvider(avatarUrl),
            child: avatarUrl == null ? const Icon(Icons.person, size: 20) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('signed_in_as', lang),
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                BadgedName(name ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How much disk the downloaded images take (flutter_cache_manager's
/// default cache), measured when shown and again after a clear. Nothing
/// on the web, where that cache isn't on a file system.
class _CacheSizeLabel extends StatefulWidget {
  const _CacheSizeLabel({required this.lang});

  final String lang;

  @override
  State<_CacheSizeLabel> createState() => _CacheSizeLabelState();
}

class _CacheSizeLabelState extends State<_CacheSizeLabel> {
  Future<int> _bytes = _measure();

  @override
  void initState() {
    super.initState();
    cacheSizeRefreshNotifier.addListener(_remeasure);
  }

  @override
  void dispose() {
    cacheSizeRefreshNotifier.removeListener(_remeasure);
    super.dispose();
  }

  void _remeasure() => setState(() => _bytes = _measure());

  static Future<int> _measure() async {
    if (kIsWeb) return 0;
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/${DefaultCacheManager.key}');
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length().catchError((_) => 0);
    }
    return total;
  }

  static String _format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
        future: _bytes,
        builder: (_, snapshot) {
          final bytes = snapshot.data;
          return Text(
            kIsWeb || bytes == null ? '' : trf('cache_size', widget.lang, {'size': _format(bytes)}),
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          );
        },
      );
}

/// A section's rows on one rounded block, inset from the screen's edges and
/// split by hairlines, as iOS groups its settings: short, quiet rows
/// instead of one full-width card each.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  /// The room inside the block at the left and right of its rows.
  static const inset = 14.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
      child: Material(
        color: cs.surface,
        borderRadius: AppRadius.mdAll,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: inset),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

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
        padding: const EdgeInsets.fromLTRB(0, AppSpace.sm, 0, AppSpace.sm),
        children: [
          // Who is signed in, on its own above the settings.
          if (username != null) _Group(children: [_SignedInAsRow(auth: auth, lang: lang)]),

          // ── General ──
          _sectionHeader(tr('general', lang)),
          _Group(children: [
            _tile(
              label: tr('language', lang),
              trailing: Text(_languageNames[lang] ?? lang,
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
              onTap: () => showOptionSheet<String>(
                context: context,
                title: tr('language', lang),
                options: _languageNames.keys.toList(),
                labelOf: (v) => _languageNames[v] ?? v,
                current: lang,
                onSelected: (v) => context.read<SettingsProvider>().setLanguage(v),
              ),
            ),
            _tile(
              label: tr('appearance', lang),
              trailing: Text(_labelOf(_appearanceKeys, settings.appearance, lang),
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
              onTap: () => showOptionSheet<String>(
                context: context,
                title: tr('appearance', lang),
                options: _appearanceKeys.keys.toList(),
                labelOf: (v) => _labelOf(_appearanceKeys, v, lang),
                current: settings.appearance,
                onSelected: (v) => context.read<SettingsProvider>().setAppearance(v),
              ),
            ),
            _tile(
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
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
                ],
              ),
              onTap: () => _showAccentColorPicker(context, settings, lang),
            ),
            _tile(
              label: tr('title_language', lang),
              trailing: Text(_labelOf(_titleLanguageKeys, settings.titleLanguage, lang),
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
              onTap: () => showOptionSheet<String>(
                context: context,
                title: tr('title_language', lang),
                options: _titleLanguageKeys.keys.toList(),
                labelOf: (v) => _labelOf(_titleLanguageKeys, v, lang),
                current: settings.titleLanguage,
                onSelected: (v) => context.read<SettingsProvider>().setTitleLanguage(v),
              ),
            ),
            _tile(
              label: tr('default_tab', lang),
              trailing: Text(tr(_tabLabelKeys[settings.defaultTab] ?? 'nav_anime', lang),
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
              onTap: () => showOptionSheet<int>(
                context: context,
                title: tr('default_tab', lang),
                options: _tabLabelKeys.keys.toList(),
                labelOf: (tab) => tr(_tabLabelKeys[tab]!, lang),
                iconOf: (tab) => _tabIcons[tab]!,
                current: settings.defaultTab,
                onSelected: (tab) => context.read<SettingsProvider>().setDefaultTab(tab),
              ),
            ),
            _switchTile(
              label: tr('haptic_feedback', lang),
              value: settings.hapticsEnabled,
              onChanged: (v) => context.read<SettingsProvider>().setHapticsEnabled(v),
            ),
          ]),

          // ── Notifications ──
          _sectionHeader(tr('notifications', lang)),
          _Group(children: [
            _switchTile(
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
          ]),

          // ── Data ──
          _sectionHeader(tr('data_storage', lang)),
          _Group(children: [
            _tile(
              label: tr('clear_cache', lang),
              trailing: _CacheSizeLabel(lang: lang),
              onTap: () => _clearImageCache(context, lang),
            ),
            _tile(
              label: tr('sync_anilist', lang),
              onTap: () => _syncWithAniList(context, auth, lang),
            ),
            _tile(
              label: tr('clear_recent_searches', lang),
              onTap: () => _clearRecentSearches(context, lang),
            ),
          ]),

          // ── Account ──
          _sectionHeader(tr('account', lang)),
          _Group(children: [
            _tile(
              label: tr('view_on_anilist', lang),
              onTap: () {
                if (username != null) {
                  _openUrl('https://anilist.co/user/${Uri.encodeComponent(username)}');
                }
              },
            ),
            _tile(
              label: tr('logout', lang),
              color: Colors.red,
              onTap: () => _confirmLogout(context, auth, lang),
            ),
          ]),

          // ── About ──
          _sectionHeader(tr('about', lang)),
          _Group(children: [
            _tile(
              label: tr('about_anispark', lang),
              onTap: () => _showAbout(context, lang),
            ),
            _tile(
              label: tr('terms', lang),
              onTap: () => _openUrl('https://anilist.co/terms'),
            ),
            _tile(
              label: tr('privacy', lang),
              onTap: () => _showPrivacy(context, lang),
            ),
            _tile(
              label: tr('send_feedback', lang),
              onTap: () => _openUrl('https://github.com/t4kina/AniSpark/issues/new'),
            ),
          ]),

          const SizedBox(height: 24),
          Center(
            child: _VersionTapper(
              child: _AppVersion(
                builder: (v) => Text('AniSpark v$v', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static Widget _sectionHeader(String title) => Padding(
        // Lined up with the text inside the groups below.
        padding: const EdgeInsets.fromLTRB(
          AppSpace.page + _Group.inset,
          AppSpace.xl,
          AppSpace.page + _Group.inset,
          AppSpace.sm,
        ),
        child: Builder(
          builder: (context) => Text(
            title.toUpperCase(),
            style: AppText.overline.copyWith(color: context.colors.textSecondary),
          ),
        ),
      );

  /// A setting switched on or off, by the switch or the whole row, with a
  /// selection tick.
  static Widget _switchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    void toggle(bool on) {
      onChanged(on);
      // After the change, so switching haptics on ticks and off doesn't.
      selectionHaptic();
    }

    return ListTile(
      tileColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: _Group.inset),
      title: Text(label, style: const TextStyle(fontSize: 15)),
      trailing: Builder(builder: (ctx) => Transform.scale(
        scale: 0.75,
        child: CupertinoSwitch(
          value: value,
          onChanged: toggle,
          activeTrackColor: Theme.of(ctx).colorScheme.primary,
        ),
      )),
      onTap: () => toggle(!value),
    );
  }

  /// A setting's row: its name, what it is set to (or a chevron) at the
  /// right. No icon: the names say enough, and a column of icons only
  /// crowds the page.
  static Widget _tile({
    required String label,
    Color? color,
    Widget? trailing,
    required VoidCallback onTap,
  }) =>
      ListTile(
        tileColor: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: _Group.inset),
        title: Text(label, style: TextStyle(color: color, fontSize: 15)),
        trailing: trailing ??
            Builder(
              builder: (context) => Icon(Icons.chevron_right, color: context.colors.textTertiary, size: 18),
            ),
        onTap: onTap,
      );

  static void _showAccentColorPicker(
      BuildContext context, SettingsProvider settings, String lang) {
    showAppSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetTitle(tr('accent_color', lang)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: accentColorOptions.entries.map((e) {
                  final isSelected = settings.accentColorName == e.key;
                  return Pressable(
                    onTap: () {
                      selectionHaptic();
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
    showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        leading: ClipRRect(
          borderRadius: AppRadius.smAll,
          child: Image.asset('assets/logo.jpg', width: 40, height: 40),
        ),
        title: 'AniSpark',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AppVersion(builder: (v) => Text(trf('settings_version', lang, {'v': v}))),
            const SizedBox(height: AppSpace.md),
            Text(tr('about_description', lang)),
            const SizedBox(height: AppSpace.md),
            Text(tr('made_with', lang), style: AppText.caption),
          ],
        ),
        actions: [_closeButton(dialogContext, lang)],
      ),
    );
  }

  static Widget _closeButton(BuildContext dialogContext, String lang) => AppButton(
        label: tr('close', lang),
        kind: AppButtonKind.tonal,
        expand: true,
        onPressed: () => Navigator.pop(dialogContext),
      );

  /// What AniSpark does with the user's data. It has no servers of its own,
  /// so this is its whole privacy policy; AniList's terms cover the account.
  static void _showPrivacy(BuildContext context, String lang) {
    showAppDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: tr('privacy', lang),
        content: Text(tr('privacy_summary', lang)),
        actions: [_closeButton(dialogContext, lang)],
      ),
    );
  }

  static Future<void> _clearImageCache(BuildContext context, String lang) async {
    await DefaultCacheManager().emptyCache();
    cacheSizeRefreshNotifier.value++;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('settings_cache_cleared', lang)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static Future<void> _clearRecentSearches(BuildContext context, String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(recentSearchesPrefsKey);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('recent_searches_cleared', lang)),
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

  static Future<void> _confirmLogout(BuildContext context, AuthService auth, String lang) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: tr('logout', lang),
      message: tr('logout_confirm', lang),
      confirmLabel: tr('logout', lang),
      cancelLabel: tr('cancel', lang),
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    // Back to the tabs first (closing Settings); AuthGate swaps them for the
    // login screen once the session has ended, whenever logout() reports it.
    Navigator.of(context).popUntil((route) => route.isFirst);
    auth.logout();
  }
}

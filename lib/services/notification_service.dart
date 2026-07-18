import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../providers/settings_provider.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'episode_alerts';
  static const _channelName = 'Episode Alerts';
  static const _channelDesc = 'Notifications when new anime episodes are available';

  static const _friendChannelId = 'friend_activity';
  static const _friendChannelName = 'Friend Activity';
  static const _friendChannelDesc = 'Notifications when friends are active on AniList';

  static const _friendNotifId = 99999;
  static const _prefLastActivityKey = 'last_seen_activity_at';

  Future<void> init() async {
    if (kIsWeb || _initialized) return;
    tz.initializeTimeZones();

    // Set timezone to device's local timezone (fixes UTC default)
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {
      // Fall back to UTC if timezone detection fails
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  /// Asks for permission only on first launch. Updates settings accordingly.
  Future<void> requestOnFirstLaunch(SettingsProvider settings) async {
    if (kIsWeb || !_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notification_asked') ?? false) return;
    await prefs.setBool('notification_asked', true);
    final granted = await requestPermission();
    await settings.setPushNotifications(granted);
    await settings.setNewEpisodeAlerts(granted);
  }

  /// Returns true if permission was granted (or already granted).
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  /// Schedule episode notifications for all CURRENT-status anime entries.
  Future<void> scheduleForAnimeList(
    Map<String, List<dynamic>> lists,
    SettingsProvider settings,
  ) async {
    if (!settings.pushNotifications || !settings.newEpisodeAlerts) return;
    if (!_initialized) return;
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) { return; }

    await _plugin.cancelAll();

    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final currentEntries = lists['CURRENT'] ?? [];

    for (final entry in currentEntries) {
      final media = entry['media'] as Map<String, dynamic>?;
      if (media == null) continue;

      final mediaId = media['id'] as int?;
      final nextAiring = media['nextAiringEpisode'] as Map<String, dynamic>?;
      if (mediaId == null || nextAiring == null) continue;

      final airingAt = (nextAiring['airingAt'] as num?)?.toInt();
      final episode = (nextAiring['episode'] as num?)?.toInt();
      if (airingAt == null || episode == null) continue;
      if (airingAt <= nowSeconds) continue;

      final title = (media['title']?['english'] ?? media['title']?['romaji'] ?? 'Unknown') as String;
      final coverUrl = media['coverImage']?['large'] as String?;
      final notifId = mediaId % 100000;
      final airingTime = tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, airingAt * 1000);
      final imagePath = coverUrl != null ? await _downloadImage(coverUrl) : null;

      try {
        await _plugin.zonedSchedule(
          notifId,
          'New Episode Airing',
          'Episode $episode of $title is now airing!',
          airingTime,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDesc,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
              styleInformation: imagePath != null
                  ? BigPictureStyleInformation(
                      FilePathAndroidBitmap(imagePath),
                      largeIcon: FilePathAndroidBitmap(imagePath),
                      contentTitle: 'New Episode Airing',
                      summaryText: 'Episode $episode of $title is now airing!',
                    )
                  : null,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
              attachments: imagePath != null
                  ? [DarwinNotificationAttachment(imagePath)]
                  : null,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        debugPrint('[Notifications] Failed to schedule for $title: $e');
      }
    }
  }

  /// Checks if there is new friend activity since the last time the feed was seen.
  /// If [settings.friendActivityAlerts] is enabled and new activity exists, fires a notification.
  /// Returns the number of new activities so the caller can update the last-seen timestamp.
  Future<void> checkFriendActivity(
    List<dynamic> activities,
    SettingsProvider settings,
  ) async {
    if (!settings.pushNotifications || !settings.friendActivityAlerts) return;
    if (!_initialized || kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) { return; }
    if (activities.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastSeenAt = prefs.getInt(_prefLastActivityKey) ?? 0;

    final newActivities = activities
        .where((a) => ((a['createdAt'] as int?) ?? 0) > lastSeenAt)
        .toList();

    if (newActivities.isEmpty) return;

    // Persist the most recent timestamp so we don't notify again for the same events
    final newestAt = newActivities
        .map((a) => (a['createdAt'] as int?) ?? 0)
        .reduce((a, b) => a > b ? a : b);
    await prefs.setInt(_prefLastActivityKey, newestAt);

    final count = newActivities.length;
    final body = count == 1
        ? _activitySummary(newActivities.first)
        : '$count friends were recently active';

    try {
      await _plugin.show(
        _friendNotifId,
        'Friend Activity',
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _friendChannelId,
            _friendChannelName,
            channelDescription: _friendChannelDesc,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[Notifications] Failed to show friend activity: $e');
    }
  }

  String _activitySummary(dynamic activity) {
    final user = activity['user'] as Map?;
    final name = user?['name'] as String? ?? 'A friend';
    final type = activity['type'] as String?;
    if (type == 'TEXT') return '$name posted a status update';
    final status = activity['status'] as String? ?? 'updated';
    final media = activity['media'] as Map<String, dynamic>?;
    final title = (media?['title']?['english'] ?? media?['title']?['romaji'] ?? 'something') as String;
    final progress = activity['progress'];
    if (progress != null) return '$name $status $progress of $title';
    return '$name $status $title';
  }

  Future<String?> _downloadImage(String url) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }

  Future<void> cancelForMedia(int mediaId) async {
    if (kIsWeb) return;
    await _plugin.cancel(mediaId % 100000);
  }
}

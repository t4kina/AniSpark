import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  Future<void> init() async {
    if (kIsWeb || _initialized) return;
    tz.initializeTimeZones();

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
    // iOS
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    // Android 13+
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }

    return true;
  }

  /// Schedule episode notifications for all CURRENT-status anime entries.
  /// Silently skips entries with no upcoming episode or if settings are off.
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
      if (airingAt <= nowSeconds) continue; // already aired

      final title = (media['title']?['english'] ?? media['title']?['romaji'] ?? 'Unknown') as String;
      final notifId = mediaId % 100000;

      try {
        await _plugin.zonedSchedule(
          notifId,
          '🎬 New Episode Available',
          'Episode $episode of $title is now airing!',
          tz.TZDateTime.fromMillisecondsSinceEpoch(tz.local, airingAt * 1000),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDesc,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
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

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }

  Future<void> cancelForMedia(int mediaId) async {
    if (kIsWeb) return;
    await _plugin.cancel(mediaId % 100000);
  }
}

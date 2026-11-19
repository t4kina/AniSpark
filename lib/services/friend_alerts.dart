import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'social_api.dart';

/// What a friend can be watched for, from their profile's bell.
enum FriendAlertKind {
  /// An episode watched or a chapter read.
  progress,

  /// A title started, finished, paused, dropped or planned.
  status,

  /// A status post.
  text,
}

/// What a fresh bell watches for until changed.
const defaultFriendAlertKinds = {FriendAlertKind.progress, FriendAlertKind.status};

/// The kind of alert an AniList activity is, or null for one no bell
/// watches (e.g. a message).
FriendAlertKind? friendAlertKindOf(Map<String, dynamic> activity) {
  final type = activity['type'];
  if (type == 'TEXT') return FriendAlertKind.text;
  if (type != 'ANIME_LIST' && type != 'MANGA_LIST') return null;
  // AniList fills progress ("5", "3 - 4") only for an episode or chapter.
  final progress = activity['progress'];
  final hasProgress = progress is num || (progress is String && progress.trim().isNotEmpty);
  return hasProgress ? FriendAlertKind.progress : FriendAlertKind.status;
}

/// A friend whose bell is on: who they are and what to tell about.
@immutable
class FriendWatch {
  const FriendWatch({
    required this.userId,
    required this.name,
    this.avatarUrl,
    required this.kinds,
    required this.since,
  });

  final int userId;
  final String name;
  final String? avatarUrl;
  final Set<FriendAlertKind> kinds;

  /// When the bell was turned on (Unix seconds): nothing older is told.
  final int since;

  FriendWatch copyWith({Set<FriendAlertKind>? kinds}) =>
      FriendWatch(userId: userId, name: name, avatarUrl: avatarUrl, kinds: kinds ?? this.kinds, since: since);

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'avatar': avatarUrl,
        'kinds': [for (final kind in kinds) kind.name],
        'since': since,
      };

  /// Null for anything that is not a watch as [toJson] writes it.
  static FriendWatch? fromJson(Object? json) {
    if (json is! Map) return null;
    final userId = json['userId'];
    final name = json['name'];
    final since = json['since'];
    final kinds = json['kinds'];
    if (userId is! int || name is! String || since is! int || kinds is! List) return null;
    final avatar = json['avatar'];
    return FriendWatch(
      userId: userId,
      name: name,
      avatarUrl: avatar is String ? avatar : null,
      kinds: {
        for (final kind in FriendAlertKind.values)
          if (kinds.contains(kind.name)) kind,
      },
      since: since,
    );
  }
}

/// The friends whose bell is on, kept on the device.
class FriendAlertsStore extends ChangeNotifier {
  FriendAlertsStore({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  static const prefsKey = 'friend_alerts';
  static const checkedAtKey = 'friend_alerts_checked_at';

  Map<int, FriendWatch> _watches = const {};

  /// Every watched friend, in the order their bells were turned on.
  List<FriendWatch> get watches => List.unmodifiable(_watches.values);

  FriendWatch? watchOf(int userId) => _watches[userId];

  /// Now, in Unix seconds.
  int get nowSeconds => _now().millisecondsSinceEpoch ~/ 1000;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      _watches = {
        for (final watch in list.map(FriendWatch.fromJson).whereType<FriendWatch>()) watch.userId: watch,
      };
      notifyListeners();
    } on FormatException catch (e) {
      debugPrint('[FriendAlerts] The saved bells could not be read: $e');
    }
  }

  /// Turns the bell of [userId] on (or changes what it watches); with no
  /// [kinds] left, off.
  Future<void> watch({
    required int userId,
    required String name,
    String? avatarUrl,
    required Set<FriendAlertKind> kinds,
  }) async {
    if (kinds.isEmpty) return unwatch(userId);
    final current = _watches[userId];
    final next = current?.copyWith(kinds: Set.unmodifiable(kinds)) ??
        FriendWatch(
          userId: userId,
          name: name,
          avatarUrl: avatarUrl,
          kinds: Set.unmodifiable(kinds),
          since: nowSeconds,
        );
    _watches = {..._watches, userId: next};
    notifyListeners();
    await _save();
  }

  Future<void> unwatch(int userId) async {
    if (!_watches.containsKey(userId)) return;
    _watches = {
      for (final entry in _watches.entries)
        if (entry.key != userId) entry.key: entry.value,
    };
    notifyListeners();
    await _save();
  }

  /// Forgets every bell, e.g. when the account logs out.
  Future<void> clear() async {
    _watches = const {};
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    await prefs.remove(checkedAtKey);
  }

  Future<int?> lastCheckedAt() async => (await SharedPreferences.getInstance()).getInt(checkedAtKey);

  Future<void> setLastCheckedAt(int seconds) async =>
      (await SharedPreferences.getInstance()).setInt(checkedAtKey, seconds);

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode([for (final watch in _watches.values) watch.toJson()]));
  }
}

/// Finds what the watched friends did since the last look.
class FriendAlertsChecker {
  FriendAlertsChecker({SocialApi? api}) : _api = api ?? SocialApi();

  final SocialApi _api;

  /// The activities worth an alert since the last check, oldest first, and
  /// remembers this check. Throws when AniList can not be asked; the next
  /// check then covers this one's time too.
  Future<List<Map<String, dynamic>>> newActivities(FriendAlertsStore store, {required String token}) async {
    final watches = {for (final watch in store.watches) watch.userId: watch};
    if (watches.isEmpty) return const [];
    final startedAt = store.nowSeconds;
    final checkedAt = await store.lastCheckedAt() ?? 0;
    int sinceFor(FriendWatch watch) => math.max(watch.since, checkedAt);
    final since = watches.values.map(sinceFor).reduce(math.min);

    final activities = await _api.fetchActivitiesOf(watches.keys.toList(), since: since, token: token);
    final fresh = <Map<String, dynamic>>[];
    for (final activity in activities) {
      final user = activity['user'];
      final watch = watches[user is Map ? user['id'] : null];
      final kind = friendAlertKindOf(activity);
      final createdAt = activity['createdAt'];
      if (watch == null || kind == null || createdAt is! int) continue;
      if (createdAt > sinceFor(watch) && watch.kinds.contains(kind)) fresh.add(activity);
    }
    fresh.sort((a, b) => (a['createdAt'] as int).compareTo(b['createdAt'] as int));
    await store.setLastCheckedAt(startedAt);
    return fresh;
  }
}

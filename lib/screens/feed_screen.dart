import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/social_api.dart';
import '../providers/settings_provider.dart';
import '../utils/activity_text.dart' show relativeTime;
import '../utils/refresh_notifier.dart';
import '../utils/translations.dart' show tr, trf;
import '../widgets/skeletons.dart';
import '../widgets/social/social_widgets.dart';
import 'activity_thread_screen.dart';
import 'notifications_screen.dart';

enum _FeedType { following, global, personal }

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with AutomaticKeepAliveClientMixin {
  final _social = SocialApi();
  List<Map<String, dynamic>> _activities = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _hasError = false;
  int _page = 1;
  int _unreadCount = 0;
  // Bumped on every reload so a slow response for a previous feed type or
  // session can't overwrite the current one.
  int _loadGeneration = 0;
  // Activities whose like toggle is still waiting for AniList.
  final Set<int> _pendingLikes = {};
  _FeedType _feedType = _FeedType.following;
  AuthService? _auth;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _auth = context.read<AuthService>()..addListener(_onAuthChanged);
      _load();
    });
    feedRefreshNotifier.addListener(_onFeedRefresh);
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuthChanged);
    feedRefreshNotifier.removeListener(_onFeedRefresh);
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (_loadingMore || !_hasMore) return false;
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 200) {
      _loadMore();
    }
    return false;
  }

  void _onAuthChanged() {
    final auth = _auth;
    if (auth == null || !mounted) return;
    if (auth.isLoggedIn && _activities.isEmpty) {
      _load();
    } else if (!auth.isLoggedIn) {
      _loadGeneration++;
      setState(() {
        _activities = [];
        _unreadCount = 0;
      });
    }
  }

  void _onFeedRefresh() => _load();

  Future<ActivityPage> _fetchPage(String token, AuthService auth, int page) =>
      _social.fetchFeed(
        token,
        isFollowing: _feedType == _FeedType.following,
        userId: _feedType == _FeedType.personal
            ? (auth.user?['id'] as int?)
            : null,
        page: page,
      );

  Future<void> _load() async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final token = auth.token;
    final generation = ++_loadGeneration;
    if (!auth.isLoggedIn || token == null) {
      setState(() { _loading = false; _hasError = false; });
      return;
    }
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasError = false;
      _page = 1;
    });
    unawaited(_loadUnreadCount());
    final feedType = _feedType;
    final settings = context.read<SettingsProvider>();
    final ActivityPage result;
    try {
      result = await _fetchPage(token, auth, 1);
    } on Exception catch (e) {
      debugPrint('[FeedScreen] Loading the feed failed: $e');
      if (mounted && generation == _loadGeneration) {
        setState(() { _loading = false; _hasError = true; });
      }
      return;
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _activities = result.activities;
      _hasMore = result.hasNextPage;
      _loading = false;
    });
    if (feedType != _FeedType.following) return;
    try {
      await NotificationService().checkFriendActivity(result.activities, settings);
    } on Exception catch (e) {
      debugPrint('[FeedScreen] Checking friend activity failed: $e');
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final auth = context.read<AuthService>();
    final token = auth.token;
    if (!auth.isLoggedIn || token == null) return;
    final generation = _loadGeneration;
    final nextPage = _page + 1;
    setState(() => _loadingMore = true);
    try {
      final result = await _fetchPage(token, auth, nextPage);
      if (!mounted || generation != _loadGeneration) return;
      // New posts shift AniList's pages, so a page can repeat activities.
      final seen = {for (final activity in _activities) activity['id']};
      setState(() {
        _activities = [
          ..._activities,
          ...result.activities.where((a) => !seen.contains(a['id'])),
        ];
        _hasMore = result.hasNextPage;
        _page = nextPage;
        _loadingMore = false;
      });
    } on Exception catch (e) {
      debugPrint('[FeedScreen] Loading feed page $nextPage failed: $e');
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _loadUnreadCount() async {
    final token = context.read<AuthService>().token;
    if (token == null) return;
    try {
      final count = await _social.fetchUnreadCount(token);
      if (mounted) setState(() => _unreadCount = count);
    } on Exception catch (e) {
      debugPrint('[FeedScreen] Loading the unread notification count failed: $e');
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    // The inbox marks everything read when it loads; confirm with AniList
    // rather than assuming it did.
    if (mounted) unawaited(_loadUnreadCount());
  }

  void _updateActivity(
    int id,
    Map<String, dynamic> Function(Map<String, dynamic> activity) update,
  ) {
    setState(() {
      _activities = [
        for (final activity in _activities)
          activity['id'] == id ? update(activity) : activity,
      ];
    });
  }

  Future<void> _toggleLike(Map<String, dynamic> activity) async {
    final id = activity['id'] as int?;
    final token = context.read<AuthService>().token;
    if (id == null || token == null || !_pendingLikes.add(id)) return;
    final lang = context.read<SettingsProvider>().language;
    final messenger = ScaffoldMessenger.of(context);
    final before = likeStateOf(activity);
    _updateActivity(id, withLikeToggled);
    final result =
        await _social.toggleLike(id, LikeTarget.activity, token: token);
    _pendingLikes.remove(id);
    if (!mounted) return;
    _updateActivity(id, (current) => withLikeState(current, result ?? before));
    if (result == null) {
      messenger.showSnackBar(SnackBar(content: Text(tr('save_failed', lang))));
    }
  }

  /// Keeps the card in sync with likes and replies made in its thread.
  void _onThreadChanged(Map<String, dynamic> updated) {
    final id = updated['id'] as int?;
    if (!mounted || id == null) return;
    _updateActivity(id, (current) => {
          ...current,
          'isLiked': updated['isLiked'] ?? current['isLiked'],
          'likeCount': updated['likeCount'] ?? current['likeCount'],
          'replyCount': updated['replyCount'] ?? current['replyCount'],
        });
  }

  void _openThread(Map<String, dynamic> activity) {
    final id = activity['id'] as int?;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivityThreadScreen(
          activityId: id,
          initialActivity: activity,
          onActivityChanged: _onThreadChanged,
        ),
      ),
    );
  }

  void _openComposer() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ComposeStatusSheet(onPost: _postStatus),
    );
  }

  /// Posts a status and puts it at the top of the feed. Returns whether
  /// AniList accepted it.
  Future<bool> _postStatus(String text) async {
    final token = context.read<AuthService>().token;
    if (token == null) return false;
    final activity = await _social.postStatus(text, token: token);
    if (activity == null) return false;
    if (mounted) {
      setState(() {
        _activities = [
          activity,
          ..._activities.where((a) => a['id'] != activity['id']),
        ];
        _hasError = false;
      });
    }
    return true;
  }

  String _feedLabel(String lang) {
    switch (_feedType) {
      case _FeedType.following:
        return tr('following_feed', lang);
      case _FeedType.global:
        return tr('global_feed', lang);
      case _FeedType.personal:
        return tr('your_feed', lang);
    }
  }

  void _showFeedPicker() {
    final lang = context.read<SettingsProvider>().language;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(tr('choose_feed', lang),
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ),
              _feedOption(tr('your_feed', lang), Icons.person, _FeedType.personal),
              _feedOption(tr('following_feed', lang), Icons.group, _FeedType.following),
              _feedOption(tr('global_feed', lang), Icons.public, _FeedType.global),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _feedOption(String label, IconData icon, _FeedType type) {
    final isSelected = _feedType == type;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey),
      title: Text(label,
          style: TextStyle(
              color: isSelected ? null : Colors.grey,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
      trailing: isSelected
          ? Builder(builder: (ctx) => Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary, size: 18))
          : null,
      onTap: () {
        Navigator.pop(context);
        if (_feedType != type) {
          setState(() => _feedType = type);
          _load();
        }
      },
    );
  }

  List<Widget> _appBarActions(String lang) => [
        IconButton(
          tooltip: tr('social_compose', lang),
          icon: const Icon(Icons.edit_outlined),
          onPressed: _openComposer,
        ),
        IconButton(
          tooltip: _unreadCount > 0
              ? trf('inbox_unread_tooltip', lang, {'n': _unreadCount})
              : tr('inbox_title', lang),
          icon: Badge.count(
            count: _unreadCount,
            isLabelVisible: _unreadCount > 0,
            child: const Icon(Icons.notifications_outlined),
          ),
          onPressed: _openNotifications,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.watch<AuthService>();
    final lang = context.watch<SettingsProvider>().language;

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('nav_feed', lang))),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.group_outlined, size: 52, color: Colors.grey),
              const SizedBox(height: 12),
              Text(tr('feed_connect_from_profile', lang),
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showFeedPicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _feedLabel(lang),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 20),
            ],
          ),
        ),
        actions: _appBarActions(lang),
      ),
      body: _loading
          ? const FeedSkeleton()
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(tr('feed_load_error', lang),
                          style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(tr('retry', lang)),
                      ),
                    ],
                  ),
                )
              : _activities.isEmpty
                  ? Center(
                      child: Text(tr('no_activity', lang),
                          style: const TextStyle(color: Colors.grey)))
                  : NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _activities.length + (_hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _activities.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final activity = _activities[i];
                            return _ActivityCard(
                              activity: activity,
                              lang: lang,
                              onToggleLike: () => _toggleLike(activity),
                              onOpenThread: () => _openThread(activity),
                            );
                          },
                        ),
                      ),
                    ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> activity;
  final String lang;
  final VoidCallback onToggleLike;
  final VoidCallback onOpenThread;

  // Long posts are cut in the feed; the thread shows them in full.
  static const _maxTextLines = 10;

  const _ActivityCard({
    required this.activity,
    required this.lang,
    required this.onToggleLike,
    required this.onOpenThread,
  });

  @override
  Widget build(BuildContext context) {
    final type = activity['type'] as String?;
    final user = asJsonMap(activity['user']);
    final username = user?['name'] as String? ?? tr('feed_unknown', lang);
    final createdAt = activity['createdAt'] as int? ?? 0;

    if (type == 'TEXT') {
      return _buildTextActivity(context, user, username, createdAt);
    }
    return _buildListActivity(context, user, username, createdAt);
  }

  BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      );

  /// Time on the left, replies and likes on the right.
  Widget _footer(int createdAt) => Row(children: [
        const Icon(Icons.access_time, size: 12, color: Colors.grey),
        const SizedBox(width: 3),
        Expanded(
          child: Text(relativeTime(createdAt, lang),
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ),
        ReplyCountButton(
          count: activity['replyCount'] as int? ?? 0,
          onPressed: onOpenThread,
        ),
        LikeButton(
          isLiked: activity['isLiked'] == true,
          count: activity['likeCount'] as int? ?? 0,
          onPressed: onToggleLike,
        ),
      ]);

  Widget _buildListActivity(BuildContext context, Map<String, dynamic>? user, String username, int createdAt) {
    final media = asJsonMap(activity['media']);
    final mediaId = media?['id'] as int?;
    final status = activity['status'] as String? ?? '';
    final progress = activity['progress'];
    final coverImage = asJsonMap(media?['coverImage'])?['large'] as String?;
    final titleMap = asJsonMap(media?['title']);
    final title = titleMap == null
        ? tr('feed_unknown', lang)
        : context.read<SettingsProvider>().resolveTitle(titleMap);
    final actionText = progress != null
        ? trf('feed_status_progress_of', lang,
            {'status': status, 'progress': progress})
        : status;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: _cardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(user: user),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => openUserProfile(context, user),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13),
                      children: [
                        TextSpan(
                            text: username,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary)),
                        TextSpan(
                            text: ' $actionText',
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                _footer(createdAt),
              ],
            ),
          ),
          if (coverImage != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: mediaId != null ? () => openMediaDetail(context, mediaId) : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: coverImage,
                  width: 45,
                  height: 64,
                  fit: BoxFit.cover,
                  memCacheWidth: 90,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextActivity(BuildContext context, Map<String, dynamic>? user, String username, int createdAt) {
    final text = activityPlainText(activity['text'] as String?, lang);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: _cardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(user: user),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => openUserProfile(context, user),
                  child: Text(username,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13)),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onOpenThread,
                  child: text.isEmpty
                      ? Text(tr('social_media_post', lang),
                          style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                              fontStyle: FontStyle.italic))
                      : Text(text,
                          maxLines: _maxTextLines,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                ),
                _footer(createdAt),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for writing and posting a status update.
class _ComposeStatusSheet extends StatefulWidget {
  const _ComposeStatusSheet({required this.onPost});

  /// Posts the text; resolves to whether it went through.
  final Future<bool> Function(String text) onPost;

  @override
  State<_ComposeStatusSheet> createState() => _ComposeStatusSheetState();
}

class _ComposeStatusSheetState extends State<_ComposeStatusSheet> {
  final _controller = TextEditingController();
  bool _posting = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() { _posting = true; _failed = false; });
    final posted = await widget.onPost(text);
    if (!mounted) return;
    if (posted) {
      Navigator.pop(context);
      return;
    }
    // Keep the sheet and the text so nothing written is lost.
    setState(() { _posting = false; _failed = true; });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(tr('social_compose_title', lang),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  IconButton(
                    tooltip: tr('close', lang),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_posting,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: tr('social_compose_hint', lang),
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_failed) ...[
                const SizedBox(height: 8),
                Text(tr('save_failed', lang),
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => FilledButton(
                    onPressed: _posting || value.text.trim().isEmpty ? null : _submit,
                    child: _posting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(tr('social_post', lang)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

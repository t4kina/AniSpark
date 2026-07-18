import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../providers/settings_provider.dart';
import '../utils/refresh_notifier.dart';
import 'detail_screen.dart';
import 'user_profile_screen.dart';

enum _FeedType { following, global, personal }

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with AutomaticKeepAliveClientMixin {
  final _service = AniListService();
  final _scrollController = ScrollController();
  List<dynamic> _activities = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _hasError = false;
  int _page = 1;
  _FeedType _feedType = _FeedType.following;
  late final AuthService _auth;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _auth = context.read<AuthService>();
      _auth.addListener(_onAuthChanged);
      _load();
    });
    feedRefreshNotifier.addListener(_onFeedRefresh);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _auth.removeListener(_onAuthChanged);
    feedRefreshNotifier.removeListener(_onFeedRefresh);
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _onAuthChanged() {
    if (_auth.isLoggedIn && _activities.isEmpty) {
      _load();
    } else if (!_auth.isLoggedIn) {
      setState(() => _activities = []);
    }
  }

  void _onFeedRefresh() => _load();

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      setState(() { _loading = false; _hasError = false; });
      return;
    }
    setState(() { _loading = true; _hasError = false; _page = 1; });
    try {
      final result = await _service.getActivityFeed(
        auth.token!,
        isFollowing: _feedType == _FeedType.following,
        userId: _feedType == _FeedType.personal
            ? (auth.user?['id'] as int?)
            : null,
        page: 1,
      );
      setState(() {
        _activities = result.activities;
        _hasMore = result.hasNextPage;
        _loading = false;
      });
      if (_feedType == _FeedType.following && mounted) {
        final settings = context.read<SettingsProvider>();
        await NotificationService().checkFriendActivity(result.activities, settings);
      }
    } catch (_) {
      setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final result = await _service.getActivityFeed(
        auth.token!,
        isFollowing: _feedType == _FeedType.following,
        userId: _feedType == _FeedType.personal
            ? (auth.user?['id'] as int?)
            : null,
        page: nextPage,
      );
      setState(() {
        _activities = [..._activities, ...result.activities];
        _hasMore = result.hasNextPage;
        _page = nextPage;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() => _loadingMore = false);
    }
  }

  String _timeAgo(int timestamp) {
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000));
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get _feedLabel {
    switch (_feedType) {
      case _FeedType.following:
        return 'Following Feed';
      case _FeedType.global:
        return 'Global Feed';
      case _FeedType.personal:
        return 'Your Feed';
    }
  }

  void _showFeedPicker() {
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Choose an activity feed:',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
              ),
              _feedOption('Your Feed', Icons.person, _FeedType.personal),
              _feedOption('Following Feed', Icons.group, _FeedType.following),
              _feedOption('Global Feed', Icons.public, _FeedType.global),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.watch<AuthService>();

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Feed')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.group_outlined, size: 52, color: Colors.grey),
              SizedBox(height: 12),
              Text('Connect your AniList from the Profile tab',
                  style: TextStyle(color: Colors.grey)),
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
                _feedLabel,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 20),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('No se pudo cargar el feed',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _activities.isEmpty
                  ? const Center(
                      child: Text('No activity yet',
                          style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _activities.length + (_hasMore ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i == _activities.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return _ActivityCard(
                            activity: _activities[i],
                            timeAgo: _timeAgo,
                          );
                        },
                      ),
                    ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final dynamic activity;
  final String Function(int) timeAgo;

  const _ActivityCard({required this.activity, required this.timeAgo});

  void _openUserProfile(BuildContext context, Map? user) {
    final id = user?['id'] as int?;
    final name = user?['name'] as String? ?? 'Unknown';
    final avatar = user?['avatar']?['large'] as String?;
    if (id == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: id, name: name, avatarUrl: avatar),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type = activity['type'] as String?;
    final user = activity['user'] as Map?;
    final avatar = user?['avatar']?['large'] as String?;
    final username = user?['name'] as String? ?? 'Unknown';
    final createdAt = activity['createdAt'] as int? ?? 0;

    if (type == 'TEXT') {
      return _buildTextActivity(context, user, avatar, username, createdAt);
    }
    return _buildListActivity(context, user, avatar, username, createdAt);
  }

  Widget _userAvatar(BuildContext context, Map? user, String? avatar) =>
      GestureDetector(
        onTap: () => _openUserProfile(context, user),
        child: CircleAvatar(
          radius: 18,
          backgroundImage:
              avatar != null ? CachedNetworkImageProvider(avatar) : null,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          child: avatar == null ? const Icon(Icons.person, size: 18) : null,
        ),
      );

  Widget _buildListActivity(BuildContext context, Map? user, String? avatar, String username, int createdAt) {
    final media = activity['media'] as Map<String, dynamic>?;
    final status = activity['status'] as String? ?? '';
    final progress = activity['progress'];
    final coverImage = media?['coverImage']?['large'] as String?;
    final title = (media?['title']?['english'] ??
        media?['title']?['romaji'] ??
        'Unknown') as String;
    final actionText = progress != null ? '$status $progress of' : status;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _userAvatar(context, user, avatar),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _openUserProfile(context, user),
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
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time, size: 12, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text(timeAgo(createdAt),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ],
            ),
          ),
          if (coverImage != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: media?['id'] != null && media?['type'] == 'ANIME'
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              DetailScreen(animeId: media!['id'] as int),
                        ),
                      )
                  : null,
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

  Widget _buildTextActivity(BuildContext context, Map? user, String? avatar, String username, int createdAt) {
    final text = activity['text'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _userAvatar(context, user, avatar),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _openUserProfile(context, user),
                  child: Text(username,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13)),
                ),
                const SizedBox(height: 4),
                Text(text,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.access_time, size: 12, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text(timeAgo(createdAt),
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

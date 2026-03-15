import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with AutomaticKeepAliveClientMixin {
  final _service = AniListService();
  List<dynamic> _activities = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      setState(() => _loading = false);
      return;
    }
    final activities = await _service.getActivityFeed(auth.token!);
    setState(() {
      _activities = activities;
      _loading = false;
    });
  }

  String _timeAgo(int timestamp) {
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000));
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.watch<AuthService>();

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Activity')),
        body: const Center(
          child: Text('Login to see your friends activity',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _activities.isEmpty
              ? const Center(
                  child: Text('No activity yet',
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _activities.length,
                    itemBuilder: (_, i) => _ActivityCard(
                      activity: _activities[i],
                      timeAgo: _timeAgo,
                    ),
                  ),
                ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final dynamic activity;
  final String Function(int) timeAgo;

  const _ActivityCard({required this.activity, required this.timeAgo});

  @override
  Widget build(BuildContext context) {
    final type = activity['type'] as String?;
    final user = activity['user'];
    final avatar = user?['avatar']?['large'] as String?;
    final username = user?['name'] as String? ?? 'Unknown';
    final createdAt = activity['createdAt'] as int? ?? 0;

    if (type == 'TEXT') {
      return _buildTextActivity(avatar, username, createdAt);
    }
    return _buildListActivity(avatar, username, createdAt);
  }

  Widget _buildListActivity(String? avatar, String username, int createdAt) {
    final media = activity['media'] as Map<String, dynamic>?;
    final status = activity['status'] as String? ?? '';
    final progress = activity['progress'];
    final coverImage = media?['coverImage']?['large'] as String?;
    final title = (media?['title']?['english'] ??
        media?['title']?['romaji'] ??
        'Unknown') as String;

    final actionText =
        progress != null ? '$status $progress of' : status;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: avatar != null
                ? CachedNetworkImageProvider(avatar)
                : null,
            backgroundColor: Colors.grey[800],
            child: avatar == null
                ? const Icon(Icons.person, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 13),
                    children: [
                      TextSpan(
                          text: username,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF02A9FF))),
                      TextSpan(
                          text: ' $actionText',
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (coverImage != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: CachedNetworkImage(
                          imageUrl: coverImage,
                          width: 35,
                          height: 50,
                          fit: BoxFit.cover,
                          memCacheWidth: 70,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(timeAgo(createdAt),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextActivity(String? avatar, String username, int createdAt) {
    final text = activity['text'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: avatar != null
                ? CachedNetworkImageProvider(avatar)
                : null,
            backgroundColor: Colors.grey[800],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(username,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF02A9FF),
                        fontSize: 13)),
                const SizedBox(height: 4),
                Text(text,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 4),
                Text(timeAgo(createdAt),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
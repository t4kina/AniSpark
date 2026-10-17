import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../services/social_api.dart';
import '../utils/activity_text.dart' show relativeTime;
import '../utils/translations.dart' show tr, trf;
import '../widgets/motion/fade_switcher.dart';
import '../widgets/motion/staggered_entrance.dart';
import '../widgets/people/paged_items.dart' show LoadMoreFooter;
import '../widgets/skeletons.dart';
import '../widgets/social/social_widgets.dart';
import 'activity_thread_screen.dart';

/// The viewer's AniList notifications, newest first. Opening it marks them
/// all read on AniList.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.api});

  final SocialApi? api;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // Pages made only of kinds the inbox skips are fetched through, up to
  // this many per load, so the list never ends up blank with more to come.
  static const _maxPagesPerLoad = 3;

  late final SocialApi _api = widget.api ?? SocialApi();
  List<InboxNotification> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _hasError = false;
  // The last page request failed: paging waits for a tap on the footer.
  bool _moreFailed = false;
  // The last pages fetched held nothing to show, so no scroll will follow:
  // paging waits for a tap on the footer.
  bool _moreStalled = false;
  // Bumped on every (re)load so a page requested before it can't be added
  // to the refreshed list.
  int _loadGeneration = 0;
  // Cached pages aren't paged further: the fresh first page replaces them.
  bool _isFresh = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<NotificationsPage> _fetchFrom(String token, int firstPage) async {
    var page = firstPage;
    while (true) {
      final result = await _api.fetchNotifications(token, page: page, resetCount: page == 1);
      final done = result.items.isNotEmpty || !result.hasNextPage || page - firstPage + 1 >= _maxPagesPerLoad;
      if (done) return result;
      page++;
    }
  }

  void _apply(NotificationsPage page, {required bool isFresh}) {
    _items = page.items;
    _hasMore = page.hasNextPage;
    _page = page.page;
    _isFresh = isFresh;
    _loading = false;
    _hasError = false;
    _loadingMore = false;
    _moreFailed = false;
    _moreStalled = page.items.isEmpty && page.hasNextPage;
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final token = auth.token;
    final userId = auth.user?['id'] as int?;
    final cache = context.read<ApiCache>();
    final messenger = ScaffoldMessenger.of(context);
    final lang = context.read<SettingsProvider>().language;
    if (token == null) {
      setState(() => _loading = false);
      return;
    }
    _loadGeneration++;
    setState(() {
      _hasError = false;
      _loadingMore = false;
      _moreFailed = false;
      _moreStalled = false;
      _loading = _items.isEmpty;
    });
    try {
      if (userId == null) {
        final page = await _fetchFrom(token, 1);
        if (mounted) setState(() => _apply(page, isFresh: true));
        return;
      }
      await cache.load<NotificationsPage>(
        key: ApiCache.userKey(userId, 'inbox'),
        force: force,
        fetch: () => _fetchFrom(token, 1),
        decode: NotificationsPage.fromJson,
        onData: (page, {required isFresh}) {
          if (mounted) setState(() => _apply(page, isFresh: isFresh));
        },
      );
    } on Exception catch (e) {
      debugPrint('[NotificationsScreen] Loading notifications failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
      if (_items.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(tr('load_error', lang))));
      }
    }
  }

  Future<void> _loadMore({bool retry = false}) async {
    final token = context.read<AuthService>().token;
    if (_loadingMore || !_hasMore || !_isFresh || token == null) return;
    if ((_moreFailed || _moreStalled) && !retry) return;
    final generation = _loadGeneration;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
      _moreStalled = false;
    });
    try {
      final result = await _fetchFrom(token, _page + 1);
      if (!mounted || generation != _loadGeneration) return;
      final seen = {for (final item in _items) item.id};
      final added = result.items.where((item) => !seen.contains(item.id)).toList();
      setState(() {
        _items = [..._items, ...added];
        _hasMore = result.hasNextPage;
        _page = result.page;
        _loadingMore = false;
        _moreStalled = added.isEmpty && result.hasNextPage;
      });
    } on Exception catch (e) {
      debugPrint('[NotificationsScreen] Loading notifications page ${_page + 1} failed: $e');
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loadingMore = false;
          _moreFailed = true;
        });
      }
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
      _loadMore();
    }
    return false;
  }

  Widget _footer(String lang) {
    if (_moreStalled) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton(
            key: const Key('load-more-button'),
            onPressed: () => _loadMore(retry: true),
            child: Text(tr('social_load_more', lang)),
          ),
        ),
      );
    }
    return LoadMoreFooter(
      key: _moreFailed ? const Key('load-more-retry') : null,
      hasMore: true,
      failed: _moreFailed,
      onRetry: () => _loadMore(retry: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final loggedIn = context.watch<AuthService>().isLoggedIn;
    return Scaffold(
      appBar: AppBar(title: Text(tr('inbox_title', lang))),
      body: FadeSwitcher(child: _body(lang, loggedIn)),
    );
  }

  /// Each state is keyed so switching between them cross-fades.
  Widget _body(String lang, bool loggedIn) {
    if (!loggedIn) {
      return _CenteredMessage(
        key: const ValueKey('inbox-logged-out'),
        icon: Icons.notifications_off_outlined,
        text: tr('feed_connect_from_profile', lang),
      );
    }
    if (_loading) return const FeedSkeleton(key: ValueKey('inbox-skeleton'), cards: 8);
    if (_items.isEmpty && _hasError) {
      return Center(
        key: const ValueKey('inbox-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(tr('load_error', lang), style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(tr('retry', lang)),
            ),
          ],
        ),
      );
    }
    // The first page cascades in once; refreshes and later pages don't.
    return EntranceGate(
      key: const ValueKey('inbox-list'),
      trigger: null,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: _items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 120),
                    _CenteredMessage(icon: Icons.notifications_none, text: tr('inbox_empty', lang)),
                    if (_hasMore) _footer(lang),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  // Dividers arrive with the tile above them.
                  separatorBuilder: (_, i) => StaggeredEntrance(
                    index: i,
                    child: const Divider(height: 1, indent: 68),
                  ),
                  itemBuilder: (_, i) {
                    if (i == _items.length) {
                      return _footer(lang);
                    }
                    return StaggeredEntrance(
                      index: i,
                      child: _NotificationTile(notification: _items[i], lang: lang),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.lang});

  final InboxNotification notification;
  final String lang;

  static final _placeholder = RegExp(r'\{(\w+)\}');

  (String key, Map<String, String> args) _sentence(BuildContext context) {
    final unknown = tr('feed_unknown', lang);
    final name = notification.user?['name'] as String? ?? unknown;
    final media = notification.media;
    final title = media == null ? unknown : context.read<SettingsProvider>().resolveTitle(asJsonMap(media['title']));
    return switch (notification.kind) {
      InboxKind.airing => ('inbox_airing', {'episode': '${notification.episode ?? '?'}', 'title': title}),
      InboxKind.following => ('inbox_following', {'name': name}),
      InboxKind.activityMessage => ('inbox_activity_message', {'name': name}),
      InboxKind.activityMention => ('inbox_activity_mention', {'name': name}),
      InboxKind.activityReply => ('inbox_activity_reply', {'name': name}),
      InboxKind.activityReplySubscribed => ('inbox_activity_reply_subscribed', {'name': name}),
      InboxKind.activityLike => ('inbox_activity_like', {'name': name}),
      InboxKind.activityReplyLike => ('inbox_activity_reply_like', {'name': name}),
      InboxKind.relatedMediaAddition => ('inbox_related_media', {'title': title}),
      InboxKind.mediaDataChange => ('inbox_media_data_change', {'title': title}),
      InboxKind.mediaMerge => (
          'inbox_media_merge',
          {
            'deleted': notification.deletedMediaTitles.isEmpty ? unknown : notification.deletedMediaTitles.join(', '),
            'title': title,
          },
        ),
      InboxKind.mediaDeletion => ('inbox_media_deletion', {'title': notification.deletedMediaTitle ?? unknown}),
    };
  }

  /// The translated sentence with the names and titles in bold.
  List<InlineSpan> _spans(String template, Map<String, String> args, TextStyle bold) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _placeholder.allMatches(template)) {
      if (match.start > last) spans.add(TextSpan(text: template.substring(last, match.start)));
      final value = args[match[1]];
      spans.add(TextSpan(text: value ?? match[0], style: value == null ? null : bold));
      last = match.end;
    }
    if (last < template.length) spans.add(TextSpan(text: template.substring(last)));
    return spans;
  }

  VoidCallback? _onTap(BuildContext context) {
    final kind = notification.kind;
    final mediaId = notification.mediaId;
    final activityId = notification.activityId;
    if (kind.isAboutMedia && mediaId != null) return () => openMediaDetail(context, mediaId);
    if (kind.isAboutActivity && activityId != null) {
      return () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ActivityThreadScreen(activityId: activityId)),
          );
    }
    if (kind == InboxKind.following) return () => openUserProfile(context, notification.user);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final (key, args) = _sentence(context);
    final reason = notification.reason;
    final bold = TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary);
    return InkWell(
      onTap: _onTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 44, child: Align(alignment: Alignment.topLeft, child: _leading(context))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: _spans(tr(key, lang), args, bold)),
                    style: const TextStyle(fontSize: 13),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 2),
                    Text(trf('inbox_reason', lang, {'reason': reason}),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 4),
                  Text(relativeTime(notification.createdAt, lang),
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leading(BuildContext context) {
    final kind = notification.kind;
    if (kind.isAboutActivity || kind == InboxKind.following) {
      return ProfileAvatar(user: notification.user, radius: 20);
    }
    final cover = asJsonMap(notification.media?['coverImage'])?['large'] as String?;
    final placeholder = Container(
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(kind == InboxKind.mediaDeletion ? Icons.delete_outline : Icons.movie_outlined,
          size: 20, color: Colors.grey),
    );
    if (cover == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: cover,
        width: 40,
        height: 56,
        fit: BoxFit.cover,
        memCacheWidth: 80,
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}

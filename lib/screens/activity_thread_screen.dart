import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/anilist_service.dart' show AniListRequestException;
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../services/social_api.dart';
import '../utils/activity_status.dart';
import '../utils/activity_text.dart';
import '../utils/translations.dart' show tr;
import '../widgets/people/paged_items.dart' show LoadMoreFooter;
import '../widgets/skeletons.dart';
import '../widgets/social/social_widgets.dart';

/// An activity with its replies and a field to reply.
class ActivityThreadScreen extends StatefulWidget {
  const ActivityThreadScreen({
    super.key,
    required this.activityId,
    this.initialActivity,
    this.onActivityChanged,
    this.api,
  });

  final int activityId;

  /// Shown while the thread loads, e.g. the feed's copy of the activity.
  final Map<String, dynamic>? initialActivity;

  /// Called with the activity after its likes or replies change here, so
  /// the screen that opened it can stay in sync.
  final ValueChanged<Map<String, dynamic>>? onActivityChanged;

  final SocialApi? api;

  @override
  State<ActivityThreadScreen> createState() => _ActivityThreadScreenState();
}

class _ActivityThreadScreenState extends State<ActivityThreadScreen> {
  late final SocialApi _api = widget.api ?? SocialApi();
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();
  Map<String, dynamic>? _activity;
  List<Map<String, dynamic>> _replies = const [];
  bool _loading = true;
  bool _hasError = false;
  bool _notFound = false;
  // Only fresh data is paged further or written back to the cache.
  bool _isFresh = false;
  bool _hasMore = false;
  bool _loadingMore = false;
  // The last replies page failed: paging waits for a tap on the footer.
  bool _moreFailed = false;
  // The viewer the thread was loaded for; only they may write it to the cache.
  int? _loadedViewerId;
  bool _sending = false;
  bool _likingActivity = false;
  final Set<int> _likingReplies = {};
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _activity = widget.initialActivity;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Where this viewer's copy of the thread is cached, or null when it must
  /// not be: a token without a known user id could be anyone, and the thread
  /// holds viewer-specific data (likes, private messages).
  String? _cacheKey() {
    final auth = context.read<AuthService>();
    final key = 'thread:${widget.activityId}';
    final viewerId = auth.user?['id'] as int?;
    if (viewerId != null) return ApiCache.userKey(viewerId, key);
    return auth.token == null ? 'anon:$key' : null;
  }

  /// Replies without duplicates, oldest first.
  static List<Map<String, dynamic>> _merged(Iterable<Map<String, dynamic>> replies) {
    final byId = {for (final reply in replies) reply['id'] as int: reply};
    return byId.values.toList()..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
  }

  void _applyThread(ActivityThread thread, {required bool isFresh}) {
    if (!mounted) return;
    setState(() {
      _activity = thread.activity;
      _replies = _merged(thread.replies);
      _hasMore = thread.hasNextPage;
      _page = thread.page;
      _isFresh = isFresh;
      _moreFailed = false;
      _loadingMore = false;
      _loading = false;
    });
    if (isFresh) widget.onActivityChanged?.call(thread.activity);
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final token = auth.token;
    final cache = context.read<ApiCache>();
    final key = _cacheKey();
    _loadedViewerId = auth.user?['id'] as int?;
    setState(() {
      _hasError = false;
      _loading = true;
    });
    try {
      if (key == null) {
        _applyThread(await _api.fetchThread(widget.activityId, token: token), isFresh: true);
        return;
      }
      await cache.load<ActivityThread>(
        key: key,
        force: force,
        fetch: () => _api.fetchThread(widget.activityId, token: token),
        decode: ActivityThread.fromJson,
        onData: (thread, {required isFresh}) => _applyThread(thread, isFresh: isFresh),
      );
    } on AniListRequestException catch (e) {
      debugPrint('[ActivityThreadScreen] Loading activity ${widget.activityId} failed: $e');
      if (e.statusCode == 404 && key != null) unawaited(cache.remove(key));
      _showLoadFailure(notFound: e.statusCode == 404);
    } on Exception catch (e) {
      debugPrint('[ActivityThreadScreen] Loading activity ${widget.activityId} failed: $e');
      _showLoadFailure(notFound: false);
    }
  }

  void _showLoadFailure({required bool notFound}) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _notFound = notFound;
      _hasError = !notFound;
      if (notFound) _activity = null;
    });
  }

  Future<void> _loadMore({bool retry = false}) async {
    if (_loadingMore || !_hasMore || !_isFresh || (_moreFailed && !retry)) return;
    final token = context.read<AuthService>().token;
    final nextPage = _page + 1;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final result = await _api.fetchReplies(widget.activityId, page: nextPage, token: token);
      if (!mounted) return;
      setState(() {
        _replies = _merged([..._replies, ...result.replies]);
        _hasMore = result.hasNextPage;
        _page = nextPage;
        _loadingMore = false;
      });
    } on Exception catch (e) {
      debugPrint('[ActivityThreadScreen] Loading replies page $nextPage failed: $e');
      if (mounted) {
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

  /// Saves what's on screen so reopening the thread shows it right away.
  /// Skipped once the session ended or changed hands since the thread loaded.
  void _persist() {
    final activity = _activity;
    if (!_isFresh || activity == null || !mounted) return;
    final auth = context.read<AuthService>();
    final viewerId = auth.user?['id'] as int?;
    if (!auth.isLoggedIn || viewerId == null || viewerId != _loadedViewerId) return;
    final thread = ActivityThread(activity: activity, replies: _replies, hasNextPage: _hasMore, page: _page);
    final key = ApiCache.userKey(viewerId, 'thread:${widget.activityId}');
    unawaited(context.read<ApiCache>().write(key, thread.toJson()));
  }

  void _showSaveFailed(ScaffoldMessengerState messenger, String lang) =>
      messenger.showSnackBar(SnackBar(content: Text(tr('save_failed', lang))));

  Future<void> _toggleActivityLike() async {
    final activity = _activity;
    final token = context.read<AuthService>().token;
    if (activity == null || token == null || _likingActivity) return;
    final messenger = ScaffoldMessenger.of(context);
    final lang = context.read<SettingsProvider>().language;
    final before = likeStateOf(activity);
    setState(() {
      _likingActivity = true;
      _activity = withLikeToggled(activity);
    });
    final result = await _api.toggleLike(widget.activityId, LikeTarget.activity, token: token);
    // State fields outlive the widget, so the opener is synced even if the
    // user already left this screen.
    final current = _activity;
    final updated = current == null ? null : withLikeState(current, result ?? before);
    if (result != null && updated != null) widget.onActivityChanged?.call(updated);
    if (!mounted) return;
    setState(() {
      _likingActivity = false;
      _activity = updated;
    });
    if (result == null) {
      _showSaveFailed(messenger, lang);
    } else {
      _persist();
    }
  }

  void _updateReply(int id, Map<String, dynamic> Function(Map<String, dynamic>) update) {
    setState(() {
      _replies = [for (final reply in _replies) reply['id'] == id ? update(reply) : reply];
    });
  }

  Future<void> _toggleReplyLike(Map<String, dynamic> reply) async {
    final id = reply['id'] as int;
    final token = context.read<AuthService>().token;
    if (token == null || !_likingReplies.add(id)) return;
    final messenger = ScaffoldMessenger.of(context);
    final lang = context.read<SettingsProvider>().language;
    final before = likeStateOf(reply);
    _updateReply(id, withLikeToggled);
    final result = await _api.toggleLike(id, LikeTarget.activityReply, token: token);
    _likingReplies.remove(id);
    if (!mounted) return;
    _updateReply(id, (current) => withLikeState(current, result ?? before));
    if (result == null) {
      _showSaveFailed(messenger, lang);
    } else {
      _persist();
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    final token = context.read<AuthService>().token;
    if (text.isEmpty || token == null || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    final lang = context.read<SettingsProvider>().language;
    setState(() => _sending = true);
    final reply = await _api.postReply(widget.activityId, text, token: token);
    if (!mounted) return;
    if (reply == null) {
      setState(() => _sending = false);
      _showSaveFailed(messenger, lang);
      return;
    }
    final activity = _activity;
    final updated = activity == null
        ? null
        : {...activity, 'replyCount': (activity['replyCount'] as int? ?? 0) + 1};
    setState(() {
      _sending = false;
      _replies = _merged([..._replies, reply]);
      _activity = updated;
    });
    _replyController.clear();
    if (updated != null) widget.onActivityChanged?.call(updated);
    _persist();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final loggedIn = context.watch<AuthService>().isLoggedIn;
    final activity = _activity;
    final isLocked = activity?['isLocked'] == true;
    return Scaffold(
      appBar: AppBar(title: Text(tr('social_thread_title', lang))),
      body: Column(
        children: [
          Expanded(child: _content(activity, lang)),
          if (activity != null && loggedIn)
            isLocked
                ? _LockedNotice(lang: lang)
                : _ReplyComposer(
                    controller: _replyController,
                    sending: _sending,
                    onSend: _sendReply,
                    lang: lang,
                  ),
        ],
      ),
    );
  }

  Widget _content(Map<String, dynamic>? activity, String lang) {
    if (_notFound) {
      return _CenteredMessage(icon: Icons.speaker_notes_off_outlined, text: tr('social_activity_not_found', lang));
    }
    if (activity == null) {
      if (_loading) return const FeedSkeleton(cards: 3);
      return _CenteredMessage(
        icon: Icons.wifi_off_rounded,
        text: tr('load_error', lang),
        onRetry: _load,
        retryLabel: tr('retry', lang),
      );
    }
    // Header, replies status row, the replies and a paging indicator.
    final itemCount = 2 + _replies.length + (_hasMore ? 1 : 0);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: itemCount,
          itemBuilder: (context, i) {
            if (i == 0) {
              return _ActivityHeader(
                activity: activity,
                lang: lang,
                onToggleLike: _toggleActivityLike,
              );
            }
            if (i == 1) return _repliesStatus(lang);
            final index = i - 2;
            if (index == _replies.length) {
              return LoadMoreFooter(
                key: _moreFailed ? const Key('load-more-retry') : null,
                hasMore: true,
                failed: _moreFailed,
                onRetry: () => _loadMore(retry: true),
              );
            }
            final reply = _replies[index];
            return _ReplyTile(
              reply: reply,
              lang: lang,
              onToggleLike: () => _toggleReplyLike(reply),
            );
          },
        ),
      ),
    );
  }

  Widget _repliesStatus(String lang) {
    final Widget? status;
    if (_hasError) {
      status = _InlineError(onRetry: _load, lang: lang);
    } else if (_loading && _replies.isEmpty) {
      status = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    } else if (_replies.isEmpty) {
      status = Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(tr('social_no_replies', lang), style: const TextStyle(color: Colors.grey))),
      );
    } else {
      status = null;
    }
    return Column(children: [const Divider(height: 24), ?status]);
  }
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({required this.activity, required this.lang, required this.onToggleLike});

  final Map<String, dynamic> activity;
  final String lang;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    final type = activity['type'] as String?;
    final isMessage = type == 'MESSAGE';
    final author = asJsonMap(isMessage ? activity['messenger'] : activity['user']);
    final recipient = isMessage ? asJsonMap(activity['recipient']) : null;
    final nameStyle = TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfileAvatar(user: author, radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _UserName(user: author, style: nameStyle, lang: lang),
                        if (recipient != null) ...[
                          const Icon(Icons.arrow_right, size: 20, color: Colors.grey),
                          _UserName(user: recipient, style: nameStyle, lang: lang),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(relativeTime(activity['createdAt'] as int? ?? 0, lang),
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (type == 'TEXT' || isMessage)
            _ActivityText(raw: (isMessage ? activity['message'] : activity['text']) as String?, lang: lang)
          else
            _ListActivityBody(activity: activity, lang: lang),
          const SizedBox(height: 4),
          Row(
            children: [
              LikeButton(
                isLiked: activity['isLiked'] == true,
                count: activity['likeCount'] as int? ?? 0,
                onPressed: onToggleLike,
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 4),
              Text('${activity['replyCount'] as int? ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserName extends StatelessWidget {
  const _UserName({required this.user, required this.style, required this.lang});

  final Map<String, dynamic>? user;
  final TextStyle style;
  final String lang;

  @override
  Widget build(BuildContext context) => TappableUserName(
        onTap: () => openUserProfile(context, user),
        child: Text(user?['name'] as String? ?? tr('feed_unknown', lang), style: style),
      );
}

/// Cleaned activity text, or a note when the post only had images/videos.
class _ActivityText extends StatelessWidget {
  const _ActivityText({required this.raw, required this.lang, this.style});

  final String? raw;
  final String lang;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = activityPlainText(raw, lang);
    if (text.isEmpty) {
      return Text(tr('social_media_post', lang),
          style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13));
    }
    return SelectableText(text, style: style ?? const TextStyle(fontSize: 14, height: 1.35));
  }
}

class _ListActivityBody extends StatelessWidget {
  const _ListActivityBody({required this.activity, required this.lang});

  final Map<String, dynamic> activity;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final media = asJsonMap(activity['media']);
    final mediaId = media?['id'] as int?;
    final cover = asJsonMap(media?['coverImage'])?['large'] as String?;
    final title = context.read<SettingsProvider>().resolveTitle(asJsonMap(media?['title']));
    final action = activityStatusText(activity['status'] as String?, activity['progress'], lang);
    return InkWell(
      onTap: mediaId == null ? null : () => openMediaDetail(context, mediaId),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          if (cover != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(imageUrl: cover, width: 60, height: 85, fit: BoxFit.cover, memCacheWidth: 120),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 4),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  const _ReplyTile({required this.reply, required this.lang, required this.onToggleLike});

  final Map<String, dynamic> reply;
  final String lang;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    final user = asJsonMap(reply['user']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(user: user, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _UserName(
                      user: user,
                      lang: lang,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    Text(relativeTime(reply['createdAt'] as int? ?? 0, lang),
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 2),
                _ActivityText(raw: reply['text'] as String?, lang: lang, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          LikeButton(
            isLiked: reply['isLiked'] == true,
            count: reply['likeCount'] as int? ?? 0,
            onPressed: onToggleLike,
          ),
        ],
      ),
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.lang,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final String lang;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !sending,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: tr('social_reply_hint', lang),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => IconButton(
                  tooltip: tr('social_send_reply', lang),
                  onPressed: sending || value.text.trim().isEmpty ? null : onSend,
                  icon: sending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedNotice extends StatelessWidget {
  const _LockedNotice({required this.lang});

  final String lang;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(tr('social_replies_locked', lang), style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
}

/// Full-screen message, with a retry button when [retryLabel] is given.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.text, this.onRetry, this.retryLabel});

  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  final String? retryLabel;

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
              if (retryLabel case final label?) ...[
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(label)),
              ],
            ],
          ),
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.onRetry, required this.lang});

  final VoidCallback onRetry;
  final String lang;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('load_error', lang), style: const TextStyle(color: Colors.grey))),
            TextButton(onPressed: onRetry, child: Text(tr('retry', lang))),
          ],
        ),
      );
}

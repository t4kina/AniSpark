import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../screens/user_profile_screen.dart';
import '../../services/api_cache.dart';
import '../../services/auth_service.dart';
import '../../services/media_extras_api.dart';
import '../../utils/score_utils.dart';
import '../../utils/translations.dart';
import 'section_title.dart';
import '../user_avatar.dart';

/// FOLLOWING on the media detail page: what the people the viewer follows
/// are doing with this media. Only for logged-in viewers; hidden while
/// loading and when none of them has it on their list.
class FollowingSection extends StatefulWidget {
  const FollowingSection({super.key, required this.mediaId, required this.isManga});

  final int mediaId;
  final bool isManga;

  @override
  State<FollowingSection> createState() => _FollowingSectionState();
}

class _FollowingSectionState extends State<FollowingSection> {
  static const _collapsedCount = 5;

  final _api = MediaExtrasApi();
  List<FollowingEntry> _entries = const [];
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FollowingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId) {
      _entries = const [];
      _expanded = false;
      _load();
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final token = auth.token;
    final viewerId = auth.user?['id'];
    if (token == null || viewerId is! int) return;
    final mediaId = widget.mediaId;
    try {
      // Account-specific and changes whenever a friend updates their list,
      // so the cached copy only bridges the wait for a fresh one.
      await context.read<ApiCache>().load<List<FollowingEntry>>(
        key: ApiCache.userKey(viewerId, 'following:$mediaId'),
        fetch: () => _api.getFollowing(mediaId, token: token),
        decode: (json) => FollowingEntry.listFromJson(json as List),
        onData: (entries, {required isFresh}) {
          if (mounted && mediaId == widget.mediaId) setState(() => _entries = entries);
        },
      );
    } on Exception catch (e) {
      debugPrint('[FollowingSection] Loading followed users of $mediaId failed: $e');
    }
  }

  void _openProfile(MiniUser user) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserProfileScreen(userId: user.id, name: user.name, avatarUrl: user.avatarUrl),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.select<AuthService, bool>((auth) => auth.isLoggedIn);
    final scoreFormat = context.select<AuthService, String?>((auth) => scoreFormatOf(auth.user));
    final lang = context.watch<SettingsProvider>().language;
    if (!isLoggedIn || _entries.isEmpty) return const SizedBox.shrink();
    final visible = _expanded ? _entries : _entries.take(_collapsedCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DetailSectionTitle(tr('following', lang).toUpperCase()),
        ),
        for (final entry in visible)
          _FollowingRow(
            entry: entry,
            isManga: widget.isManga,
            scoreFormat: scoreFormat,
            onTap: () => _openProfile(entry.user),
          ),
        if (_entries.length > _collapsedCount)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded
                    ? tr('detail_show_less', lang)
                    : trf('following_show_all', lang, {'n': _entries.length})),
              ),
            ),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1),
      ],
    );
  }
}

class _FollowingRow extends StatelessWidget {
  const _FollowingRow({
    required this.entry,
    required this.isManga,
    required this.scoreFormat,
    required this.onTap,
  });

  final FollowingEntry entry;
  final bool isManga;
  final String? scoreFormat;
  final VoidCallback onTap;

  /// "On episode 12" while it's in progress; nothing once completed or
  /// before starting.
  String? _progressLine(String lang) {
    final showsProgress = entry.progress > 0 && entry.status != 'COMPLETED' && entry.status != 'PLANNING';
    if (!showsProgress) return null;
    return trf(isManga ? 'following_on_chapter' : 'following_on_episode', lang, {'n': entry.progress});
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final progressLine = _progressLine(lang);
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              UserAvatar(url: entry.user.avatarUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(status: entry.status, isManga: isManga),
                      ],
                    ),
                    if (progressLine != null) ...[
                      const SizedBox(height: 2),
                      Text(progressLine, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
              if (entry.score > 0) ...[
                const SizedBox(width: 8),
                Icon(Icons.star_rounded, size: 16, color: Colors.amber, semanticLabel: tr('list_score', lang)),
                const SizedBox(width: 2),
                Text(
                  formatScore(entry.score, scoreFormat),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Coloured pill with a list status, worded for anime or manga.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.isManga});

  final String status;
  final bool isManga;

  // Darker than AniList's own shades (except CURRENT's blue) so the white
  // label stays readable.
  static const _colors = {
    'CURRENT': Color(0xFF3DB4F2),
    'COMPLETED': Color(0xFF388E3C),
    'PLANNING': Color(0xFFEF6C00),
    'PAUSED': Color(0xFFB28704),
    'DROPPED': Color(0xFFE53935),
    'REPEATING': Color(0xFF8E24AA),
  };

  String? get _labelKey => switch (status) {
        'CURRENT' => isManga ? 'reading' : 'watching',
        'COMPLETED' => 'completed',
        'PLANNING' => isManga ? 'plan_to_read' : 'plan_to_watch',
        'PAUSED' => 'on_hold',
        'DROPPED' => 'dropped',
        'REPEATING' => isManga ? 'rereading' : 'rewatching',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final key = _labelKey;
    final color = _colors[status];
    if (key == null || color == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(
        tr(key, lang),
        maxLines: 1,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

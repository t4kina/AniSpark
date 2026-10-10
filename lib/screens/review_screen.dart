import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/api_cache.dart';
import '../services/media_extras_api.dart';
import '../utils/review_text.dart';
import '../utils/translations.dart';
import '../widgets/detail/load_error_view.dart';
import '../widgets/detail/user_avatar.dart';
import '../widgets/skeletons.dart';

/// A full user review. [initial] (the summary from a list) lets the header
/// show straight away while the body loads.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.reviewId, this.initial});

  final int reviewId;
  final Review? initial;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _api = MediaExtrasApi();
  Review? _review;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Reviews are public and rarely edited, so a cached copy is shared
      // between accounts and kept for a few hours.
      await context.read<ApiCache>().load<Review>(
        key: 'review:${widget.reviewId}',
        maxAge: const Duration(hours: 6),
        fetch: () => _api.getReview(widget.reviewId),
        decode: (json) => Review.fromJson(json) ?? (throw const FormatException('Unreadable cached review')),
        onData: (review, {required isFresh}) {
          if (mounted) setState(() => _review = review);
        },
      );
    } on Exception catch (e) {
      debugPrint('[ReviewScreen] Loading review ${widget.reviewId} failed: $e');
      if (mounted && _review == null) setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: tr('tooltip_back', lang),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(tr('review_title', lang)),
      ),
      body: _failed && _review == null ? LoadErrorView(onRetry: _retry) : _content(lang),
    );
  }

  Widget _content(String lang) {
    final review = _review;
    final header = review ?? widget.initial;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (header != null) _ReviewHeader(review: header) else const _HeaderSkeleton(),
        if (header != null && header.summary.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            header.summary,
            style: TextStyle(fontSize: 16, height: 1.4, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        if (review == null)
          const _BodySkeleton()
        else ...[
          Text(
            cleanReviewText(review.body, spoilerPlaceholder: tr('review_spoiler', lang)),
            style: TextStyle(fontSize: 15, height: 1.55, color: cs.onSurface),
          ),
          if (review.ratingAmount > 0) ...[
            const SizedBox(height: 28),
            Text(
              trf('review_liked_by', lang, {'liked': review.rating, 'total': review.ratingAmount}),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ],
      ],
    );
  }
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = context.watch<SettingsProvider>().language;
    return Row(
      children: [
        UserAvatar(url: review.user.avatarUrl, size: 48, radius: 8),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            review.user.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        if (review.score > 0)
          Semantics(
            label: '${tr('list_score', lang)} ${review.score}/100',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
              child: Text(
                '${review.score}/100',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onPrimary),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) => const Skeleton(
        child: Row(
          children: [
            SkeletonBox(width: 48, height: 48, radius: 8),
            SizedBox(width: 12),
            SkeletonBox(width: 140, height: 16),
            Spacer(),
            SkeletonBox(width: 64, height: 26, radius: 12),
          ],
        ),
      );
}

class _BodySkeleton extends StatelessWidget {
  const _BodySkeleton();

  static const _lineCount = 12;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _lineCount; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                // Every fourth line is short, like the end of a paragraph.
                child: i % 4 == 3 ? const SkeletonBox(width: 180, height: 13) : const SkeletonBox(height: 13),
              ),
          ],
        ),
      );
}

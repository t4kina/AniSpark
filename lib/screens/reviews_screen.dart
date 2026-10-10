import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/media_extras_api.dart';
import '../utils/translations.dart';
import '../widgets/detail/load_error_view.dart';
import '../widgets/detail/review_card.dart';
import '../widgets/skeletons.dart';
import 'review_screen.dart';

/// Every review of a media, most liked first, loading more on scroll.
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key, required this.mediaId});

  final int mediaId;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  static const _pageSize = 20;
  // Space under each card for its floating shadow.
  static const _cardSpacing = 20.0;

  final _api = MediaExtrasApi();
  List<Review> _reviews = const [];
  int _nextPage = 1;
  bool _hasNextPage = true;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchNextPage());
  }

  /// Starts loading the next page unless one is loading or none is left.
  void _loadMore() {
    if (!mounted || _loading || !_hasNextPage) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    unawaited(_fetchNextPage());
  }

  Future<void> _fetchNextPage() async {
    final page = _nextPage;
    try {
      final result = await _api.getReviews(widget.mediaId, page: page, perPage: _pageSize);
      if (!mounted) return;
      final known = {for (final review in _reviews) review.id};
      setState(() {
        // Rankings can shift between pages; never show a review twice.
        _reviews = List.unmodifiable([
          ..._reviews,
          ...result.reviews.where((review) => !known.contains(review.id)),
        ]);
        _hasNextPage = result.hasNextPage && result.reviews.isNotEmpty;
        _nextPage = page + 1;
        _loading = false;
      });
    } on Exception catch (e) {
      debugPrint('[ReviewsScreen] Loading page $page of ${widget.mediaId} reviews failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _open(Review review) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewScreen(reviewId: review.id, initial: review)),
      );

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
        title: Text(tr('review_all_title', lang)),
      ),
      body: _body(lang),
    );
  }

  Widget _body(String lang) {
    if (_reviews.isEmpty) {
      if (_loading) return const _ReviewsSkeleton();
      if (_failed) return LoadErrorView(onRetry: _loadMore);
      return Center(child: Text(tr('nothing_here', lang), style: const TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _reviews.length + 1,
      itemBuilder: (context, i) {
        if (i == _reviews.length) return _footer(lang);
        final review = _reviews[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: _cardSpacing),
          child: ReviewCard(review: review, onTap: () => _open(review)),
        );
      },
    );
  }

  /// The end of the list: a retry button after a failure, otherwise a
  /// spinner that loads the next page as soon as it is built (scrolled near).
  Widget _footer(String lang) {
    if (_failed) {
      return Center(
        child: TextButton.icon(
          onPressed: _loadMore,
          icon: const Icon(Icons.refresh),
          label: Text(tr('retry', lang)),
        ),
      );
    }
    if (!_hasNextPage) return const SizedBox.shrink();
    if (!_loading) WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

class _ReviewsSkeleton extends StatelessWidget {
  const _ReviewsSkeleton();

  static const _cards = 5;

  @override
  Widget build(BuildContext context) => Skeleton(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          itemCount: _cards,
          itemBuilder: (_, _) => const Padding(
            padding: EdgeInsets.only(bottom: _ReviewsScreenState._cardSpacing),
            child: ReviewCardSkeleton(),
          ),
        ),
      );
}

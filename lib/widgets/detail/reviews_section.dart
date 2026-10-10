import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../screens/review_screen.dart';
import '../../screens/reviews_screen.dart';
import '../../services/api_cache.dart';
import '../../services/media_extras_api.dart';
import '../../utils/translations.dart';
import 'review_card.dart';
import 'section_title.dart';

/// REVIEWS on the media detail page: a row of the most liked reviews as
/// floating speech-bubble cards, with "View All" opening every review.
/// Hidden while loading and when the media has no reviews.
class ReviewsSection extends StatefulWidget {
  const ReviewsSection({super.key, required this.mediaId});

  final int mediaId;

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  // Cards leave part of the next one peeking in, without growing absurdly
  // wide on tablets.
  static const _cardWidthFactor = 0.86;
  static const _maxCardWidth = 420.0;
  static const _cardGap = 12.0;

  final _api = MediaExtrasApi();
  ReviewsPage _page = ReviewsPage.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReviewsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId) {
      _page = ReviewsPage.empty;
      _load();
    }
  }

  Future<void> _load() async {
    final mediaId = widget.mediaId;
    try {
      await context.read<ApiCache>().load<ReviewsPage>(
        key: 'reviews:$mediaId',
        maxAge: const Duration(hours: 6),
        fetch: () => _api.getReviews(mediaId),
        decode: (json) => ReviewsPage.fromJson(json as Map),
        onData: (page, {required isFresh}) {
          if (mounted && mediaId == widget.mediaId) setState(() => _page = page);
        },
      );
    } on Exception catch (e) {
      debugPrint('[ReviewsSection] Loading reviews of $mediaId failed: $e');
    }
  }

  void _openAll() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewsScreen(mediaId: widget.mediaId)),
      );

  void _open(Review review) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReviewScreen(reviewId: review.id, initial: review)),
      );

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final reviews = _page.reviews;
    if (reviews.isEmpty) return const SizedBox.shrink();
    final cardWidth = math.min(MediaQuery.sizeOf(context).width * _cardWidthFactor, _maxCardWidth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(child: DetailSectionTitle(tr('review_section_title', lang))),
              _ViewAllButton(label: tr('home_see_all', lang), onPressed: _openAll),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Room around the cards so their shadows aren't clipped.
          padding: const EdgeInsets.fromLTRB(16, 12, 16 - _cardGap, 26),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final review in reviews)
                Padding(
                  padding: const EdgeInsets.only(right: _cardGap),
                  child: ReviewCard(review: review, width: cardWidth, onTap: () => _open(review)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Small pill button; its touch target is padded to the 48px minimum.
class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: cs.surfaceContainerHighest,
        foregroundColor: cs.onSurface,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

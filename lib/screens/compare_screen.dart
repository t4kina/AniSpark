import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../utils/affinity.dart';
import '../utils/score_utils.dart';
import '../utils/translations.dart';
import '../widgets/motion/cover_hero.dart';
import '../widgets/motion/press_scale.dart';
import '../widgets/motion/rounded_hero.dart';
import '../widgets/motion/staggered_entrance.dart';
import '../widgets/profile/affinity_ring.dart';
import 'detail_screen.dart';

const _rowHeight = 76.0;
const _scoreWidth = 48.0;

/// The titles on both the viewer's and another user's list, with both
/// scores side by side, sortable by agreement or by title, under a summary
/// of the affinity.
class CompareScreen extends StatefulWidget {
  const CompareScreen({
    super.key,
    required this.affinity,
    required this.userName,
    required this.type,
  });

  final Affinity affinity;

  /// The other user.
  final String userName;

  /// `ANIME` or `MANGA`.
  final String type;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  CompareSort _sort = CompareSort.agreement;

  // Sorting resolves every title, so the order is kept until the sort or
  // the title language changes instead of being redone on each build.
  List<SharedTitle>? _sorted;
  (CompareSort, String)? _sortedFor;

  @override
  void didUpdateWidget(CompareScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.affinity, widget.affinity)) _sorted = null;
  }

  List<SharedTitle> _sortedTitles(SettingsProvider settings) {
    final sortedFor = (_sort, settings.titleLanguage);
    final cached = _sorted;
    if (cached != null && _sortedFor == sortedFor) return cached;
    final sorted = List<SharedTitle>.unmodifiable(
      sortShared(widget.affinity.shared, _sort, (title) => settings.resolveTitle(title.title)),
    );
    _sorted = sorted;
    _sortedFor = sortedFor;
    return sorted;
  }

  void _sortBy(CompareSort sort) {
    if (sort != _sort) setState(() => _sort = sort);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final scoreFormat = context.select<AuthService, String?>((auth) => scoreFormatOf(auth.user));
    final titles = _sortedTitles(settings);
    final mediaLabel = tr(widget.type == 'MANGA' ? 'nav_manga' : 'nav_anime', lang);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: tr('tooltip_back', lang),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              trf('affinity_compare_title', lang, {'name': widget.userName}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(mediaLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
      // The first rows cascade in once; re-sorting just reorders them.
      body: EntranceGate(
        trigger: null,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Summary(
                affinity: widget.affinity,
                userName: widget.userName,
                scoreFormat: scoreFormat,
              ),
            ),
            SliverToBoxAdapter(child: _SortBar(selected: _sort, onSelected: _sortBy)),
            SliverToBoxAdapter(child: _ColumnLabels(userName: widget.userName)),
            if (titles.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(tr('affinity_no_titles_in_common', lang), style: const TextStyle(color: Colors.grey)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 24),
                sliver: SliverFixedExtentList(
                  itemExtent: _rowHeight,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => StaggeredEntrance(
                      index: i,
                      child: _CompareRow(
                        title: titles[i],
                        userName: widget.userName,
                        scoreFormat: scoreFormat,
                        heroScope: 'compare-${widget.type}',
                      ),
                    ),
                    childCount: titles.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The affinity ring and verdict, then each user's mean score and the
/// titles only one of them has completed.
class _Summary extends StatelessWidget {
  const _Summary({required this.affinity, required this.userName, required this.scoreFormat});

  final Affinity affinity;
  final String userName;
  final String? scoreFormat;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final cs = Theme.of(context).colorScheme;
    final color = affinityTierColor(affinity.tier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outline),
        ),
        child: Column(
          children: [
            Row(
              children: [
                AffinityRing(percent: affinity.percent, color: color, size: 76),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        affinityHeadline(affinity, lang),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: affinity.percent == null ? null : color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        titlesInCommonText(affinity.shared.length, lang),
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      Text(
                        trf('affinity_scored_by_both', lang, {'n': affinity.scoredInCommon}),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outline),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _UserStats(
                      name: tr('affinity_you', lang),
                      mean: _formatMean(affinity.myMean, scoreFormat),
                      completedOnly: affinity.completedOnlyByMe,
                      completedOnlyLabel: tr('affinity_only_you_completed', lang),
                    ),
                  ),
                  VerticalDivider(width: 24, thickness: 1, color: cs.outline),
                  Expanded(
                    child: _UserStats(
                      name: userName,
                      mean: _formatMean(affinity.theirMean, scoreFormat),
                      completedOnly: affinity.completedOnlyByThem,
                      completedOnlyLabel: trf('affinity_only_they_completed', lang, {'name': userName}),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserStats extends StatelessWidget {
  const _UserStats({
    required this.name,
    required this.mean,
    required this.completedOnly,
    required this.completedOnlyLabel,
  });

  final String name;
  final String mean;
  final int completedOnly;
  final String completedOnlyLabel;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    const valueStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    const labelStyle = TextStyle(fontSize: 11, color: Colors.grey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
        const SizedBox(height: 8),
        Text(mean, style: valueStyle),
        Text(tr('affinity_mean_score', lang), style: labelStyle),
        const SizedBox(height: 8),
        Text('$completedOnly', style: valueStyle),
        Text(completedOnlyLabel, style: labelStyle),
      ],
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.selected, required this.onSelected});

  final CompareSort selected;
  final ValueChanged<CompareSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final options = [
      (CompareSort.agreement, 'compare-sort-agreement', tr('affinity_sort_agreement', lang)),
      (CompareSort.disagreement, 'compare-sort-disagreement', tr('affinity_sort_disagreement', lang)),
      (CompareSort.title, 'compare-sort-title', tr('search_sort_title', lang)),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          for (final (sort, key, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey(key),
                label: Text(label),
                selected: selected == sort,
                onSelected: (_) => onSelected(sort),
              ),
            ),
        ],
      ),
    );
  }
}

/// Whose score is in which column.
class _ColumnLabels extends StatelessWidget {
  const _ColumnLabels({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.3);
    Widget label(String text) => SizedBox(
          width: _scoreWidth,
          child: Text(text, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Row(
          children: [
            const Spacer(),
            label(tr('affinity_you', lang)),
            const SizedBox(width: 8),
            label(userName),
          ],
        ),
      ),
    );
  }
}

class _CompareRow extends StatefulWidget {
  const _CompareRow({
    required this.title,
    required this.userName,
    required this.scoreFormat,
    required this.heroScope,
  });

  final SharedTitle title;
  final String userName;
  final String? scoreFormat;

  /// Scope of the cover's hero tag, see `coverHeroTag`.
  final String heroScope;

  @override
  State<_CompareRow> createState() => _CompareRowState();
}

class _CompareRowState extends State<_CompareRow> {
  // The row's press dips its cover, like My List rows.
  final _pressed = ValueNotifier(false);

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  String? _score(double score) => score > 0 ? formatScore(score / 10, widget.scoreFormat) : null;

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final userName = widget.userName;
    final settings = context.watch<SettingsProvider>();
    final lang = settings.language;
    final cs = Theme.of(context).colorScheme;
    final name = settings.resolveTitle(title.title);
    final cover = title.coverUrl;
    final mine = _score(title.myScore);
    final theirs = _score(title.theirScore);
    final gap = title.gap;
    final tint = gap == null ? null : scoreGapColor(gap);
    final notScored = tr('list_not_scored', lang);
    final heroTag = coverHeroTag(widget.heroScope, title.mediaId);
    void open() => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailScreen(animeId: title.mediaId, heroTag: heroTag, initialCoverUrl: cover),
          ),
        );

    return Semantics(
      button: true,
      label: '$name. ${tr('affinity_you', lang)}: ${mine ?? notScored}. $userName: ${theirs ?? notScored}',
      excludeSemantics: true,
      onTap: open,
      child: InkWell(
        onTap: open,
        onHighlightChanged: (pressed) => _pressed.value = pressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              PressScale(
                pressed: _pressed,
                child: RoundedHero(
                  tag: heroTag,
                  borderRadius: BorderRadius.circular(6),
                  child: cover != null
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          width: 46,
                          height: 64,
                          fit: BoxFit.cover,
                          memCacheWidth: 92,
                          placeholder: (_, _) => Container(color: cs.surfaceContainerHighest),
                          errorWidget: (_, _, _) => Container(color: cs.surfaceContainerHighest),
                        )
                      : Container(width: 46, height: 64, color: cs.surfaceContainerHighest),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              _ScorePill(score: mine, tint: tint),
              const SizedBox(width: 8),
              _ScorePill(score: theirs, tint: tint),
            ],
          ),
        ),
      ),
    );
  }
}

/// A score, tinted by how far apart the two scores are.
class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score, required this.tint});

  final String? score;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = this.tint;
    return Container(
      width: _scoreWidth,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint == null ? cs.surfaceContainerHighest : tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        score ?? '–',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: score == null ? Colors.grey : null,
        ),
      ),
    );
  }
}

/// A mean score (0–100) in the viewer's score format, keeping one decimal
/// where the format would round it away.
String _formatMean(double? mean, String? format) {
  if (mean == null) return '–';
  return switch (format) {
    'POINT_100' => '${mean.round()}',
    'POINT_5' => '${(mean / 20).toStringAsFixed(1)}/5',
    _ => (mean / 10).toStringAsFixed(1),
  };
}

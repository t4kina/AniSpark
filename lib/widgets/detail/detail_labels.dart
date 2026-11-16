import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../screens/browse_screen.dart';
import '../../services/browse_api.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_layout.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_text.dart';
import '../../utils/translations.dart' show tr, trf;
import '../app_image.dart';
import '../genre_filter_sheet.dart' show genreLabel;
import '../motion/pressable.dart';

const _chipPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
const _chipGap = 6.0;

/// A media's genres, in the accent colour: each opens the grid of that
/// genre's anime or manga.
class GenreChips extends StatelessWidget {
  const GenreChips({super.key, required this.genres, required this.isManga});

  /// AniList genre names, as it sends them.
  final List<String> genres;
  final bool isManga;

  void _open(BuildContext context, String genre, String label) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BrowseScreen(
          title: label.toUpperCase(),
          query: BrowseQuery(
            id: 'genre-${isManga ? 'manga' : 'anime'}',
            type: isManga ? BrowseQuery.manga : BrowseQuery.anime,
            defaultSort: 'POPULARITY_DESC',
            genres: {genre},
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = context.watch<SettingsProvider>().language;
    return Wrap(
      spacing: _chipGap,
      runSpacing: _chipGap,
      children: [
        for (final genre in genres)
          Semantics(
            button: true,
            child: Pressable(
              onTap: () => _open(context, genre, genreLabel(genre, lang)),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.16),
                  borderRadius: AppRadius.pillAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      genreLabel(genre, lang),
                      style: AppText.caption.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 16, color: cs.primary.withValues(alpha: 0.8)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A media's tags with how much each weighs in it (AniList's rank, out of
/// 100). The ones that give the story away stay hidden behind a chip that
/// says how many there are; another chip shows the tags past the first few.
class TagChips extends StatefulWidget {
  const TagChips({super.key, required this.tags});

  /// The detail query's `tags { name rank isMediaSpoiler }`.
  final List<Map<String, dynamic>> tags;

  /// Tags shown before "show all".
  static const collapsedCount = 9;

  @override
  State<TagChips> createState() => _TagChipsState();
}

class _TagChipsState extends State<TagChips> {
  static const _spoilerColor = Colors.orange;

  bool _showAll = false;
  bool _showSpoilers = false;

  Widget _tag(Map<String, dynamic> tag) {
    final cs = Theme.of(context).colorScheme;
    final spoiler = tag['isMediaSpoiler'] == true;
    final rank = tag['rank'];
    return Container(
      padding: _chipPadding,
      decoration: BoxDecoration(
        color: spoiler ? _spoilerColor.withValues(alpha: 0.15) : cs.surfaceContainerHighest,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tag['name'] as String? ?? '', style: AppText.caption.copyWith(color: spoiler ? _spoilerColor : null)),
          if (rank is int) ...[
            const SizedBox(width: 6),
            Text(
              '$rank',
              style: AppText.micro.copyWith(
                color: context.colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// An outlined chip that does something to the list instead of being part
  /// of it.
  Widget _toggle(String label, VoidCallback onTap) => Semantics(
        button: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: _chipPadding,
            decoration: BoxDecoration(
              borderRadius: AppRadius.pillAll,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Text(label, style: AppText.caption.copyWith(color: context.colors.textSecondary)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final spoilers = widget.tags.where((tag) => tag['isMediaSpoiler'] == true).length;
    final visible = [
      for (final tag in widget.tags)
        if (_showSpoilers || tag['isMediaSpoiler'] != true) tag,
    ];
    final shown = _showAll ? visible : visible.take(TagChips.collapsedCount).toList();
    return AnimatedSize(
      duration: AppMotion.of(context, AppMotion.medium),
      curve: AppMotion.standard,
      alignment: AlignmentDirectional.topStart,
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: _chipGap,
          runSpacing: _chipGap,
          children: [
            for (final tag in shown) _tag(tag),
            if (spoilers > 0)
              _toggle(
                _showSpoilers
                    ? tr('detail_hide_spoiler_tags', lang)
                    : trf('detail_show_spoiler_tags', lang, {'n': spoilers}),
                () => setState(() => _showSpoilers = !_showSpoilers),
              ),
            if (visible.length > TagChips.collapsedCount)
              _toggle(
                _showAll ? tr('detail_show_less', lang) : trf('detail_show_all_tags', lang, {'n': visible.length}),
                () => setState(() => _showAll = !_showAll),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where a media can be watched or read, as cards in each service's own
/// colour, and under them its other links (official site, social) as chips
/// with a dot of theirs. Shows nothing without links.
class ExternalLinks extends StatelessWidget {
  const ExternalLinks({super.key, required this.links, required this.isManga, required this.onOpenUrl});

  /// The detail query's `externalLinks { url site color icon type language }`.
  final List<Map<String, dynamic>> links;
  final bool isManga;
  final void Function(String url) onOpenUrl;

  static const _streaming = 'STREAMING';

  /// AniList sends a link's colour as `#RRGGBB`; null when it sends none
  /// or something else.
  static Color? colorOf(Map<String, dynamic> link) {
    final raw = link['color'];
    if (raw is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw)) return null;
    return Color(0xFF000000 | int.parse(raw.substring(1), radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    bool usable(Map<String, dynamic> link) => (link['url'] as String? ?? '').isNotEmpty;
    final services = [
      for (final link in links)
        if (usable(link) && link['type'] == _streaming) link,
    ];
    final others = [
      for (final link in links)
        if (usable(link) && link['type'] != _streaming) link,
    ];
    if (services.isEmpty && others.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (services.isNotEmpty) ...[
          _heading(context, tr(isManga ? 'detail_where_to_read' : 'detail_where_to_watch', lang)),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              // Two to a row.
              final width = (constraints.maxWidth - AppSpace.sm) / 2;
              return Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final link in services) SizedBox(width: width, child: _ServiceCard(link: link, onOpenUrl: onOpenUrl)),
                ],
              );
            },
          ),
        ],
        if (services.isNotEmpty && others.isNotEmpty) const SizedBox(height: AppSpace.lg),
        if (others.isNotEmpty) ...[
          _heading(context, tr('detail_more_links', lang)),
          const SizedBox(height: 10),
          Wrap(
            spacing: _chipGap,
            runSpacing: _chipGap,
            children: [for (final link in others) _LinkChip(link: link, onOpenUrl: onOpenUrl)],
          ),
        ],
      ],
    );
  }

  Widget _heading(BuildContext context, String text) => Text(
        text.toUpperCase(),
        style: AppText.overline.copyWith(color: context.colors.textSecondary),
      );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.link, required this.onOpenUrl});

  final Map<String, dynamic> link;
  final void Function(String url) onOpenUrl;

  static const _logoSize = 28.0;
  static const _height = 52.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final site = link['site'] as String? ?? '';
    final icon = link['icon'] as String?;
    final language = link['language'] as String?;
    final color = ExternalLinks.colorOf(link) ?? cs.primary;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: () => onOpenUrl(link['url'] as String),
        child: Container(
          // One height for every card, with or without a language line.
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Color.alphaBlend(color.withValues(alpha: 0.14), cs.surfaceContainerHighest),
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              Container(
                width: _logoSize,
                height: _logoSize,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: color, borderRadius: AppRadius.smAll),
                // The service's own mark; its initial until it loads, or
                // when AniList has none.
                child: icon == null || icon.isEmpty
                    ? _initial(site)
                    : AppImage(url: icon, cacheWidth: 64, fill: false, placeholder: _initial(site)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      site,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.footnote.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (language != null && language.isNotEmpty)
                      Text(
                        language,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.micro.copyWith(color: context.colors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initial(String site) => Center(
        child: Text(
          site.isEmpty ? '' : site.characters.first.toUpperCase(),
          style: AppText.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      );
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.link, required this.onOpenUrl});

  final Map<String, dynamic> link;
  final void Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: () => onOpenUrl(link['url'] as String),
        child: Container(
          padding: _chipPadding,
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: AppRadius.pillAll),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ExternalLinks.colorOf(link) ?? context.colors.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(link['site'] as String? ?? '', style: AppText.caption.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

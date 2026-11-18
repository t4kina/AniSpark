import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../screens/detail_screen.dart';
import '../services/anilist_service.dart';
import '../services/api_cache.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_motion.dart';
import '../theme/app_text.dart';
import '../utils/haptics.dart';
import '../utils/translations.dart' show tr, trf;
import 'app_button.dart';
import 'app_image.dart';
import 'entry_editor/entry_draft.dart' show entryStatusKey;
import 'entry_editor/entry_editor_sheet.dart';
import 'skeletons.dart';

/// What the preview asks AniList for: what a list or a card may not have
/// (the synopsis, the genres) and whether it is in the viewer's list.
const _previewQuery = r'''
query ($id: Int) {
  Media(id: $id) {
    id
    type
    format
    episodes
    chapters
    averageScore
    seasonYear
    genres
    description(asHtml: false)
    mediaListEntry { id status progress }
  }
}''';

/// Opens a preview of [media] over the page: a card with its cover, what it
/// is and what it is about, and buttons to open it or to add or edit it in
/// the list. It is what holding an anime or a manga does everywhere.
///
/// [media] is an AniList `Media` map, as much of it as the caller has; the
/// rest is loaded. [context] is that of what was held: the card grows out of
/// it. [onEdit] replaces the default editor (which looks the media up) when
/// the caller already has the list entry.
Future<void> showMediaPreview(
  BuildContext context, {
  required Map<String, dynamic> media,
  bool? isManga,
  VoidCallback? onEdit,
  AniListService? service,
}) {
  final id = media['id'];
  if (id is! int) return Future.value();
  mediumHaptic();
  final box = context.findRenderObject();
  final screen = MediaQuery.sizeOf(context);
  final held = box is RenderBox && box.hasSize ? box.localToGlobal(box.size.center(Offset.zero)) : null;
  // Where on the screen it was held, as the point the card grows from.
  final origin = held == null
      ? Alignment.center
      : Alignment((held.dx / screen.width) * 2 - 1, (held.dy / screen.height) * 2 - 1);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: AppMotion.of(context, AppMotion.medium),
    pageBuilder: (_, _, _) => MediaPreview(
      media: media,
      isManga: isManga,
      onEdit: onEdit,
      service: service,
    ),
    transitionBuilder: (context, animation, _, child) {
      final shown = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.exit);
      return Stack(
        fit: StackFit.expand,
        children: [
          // The page behind goes out of focus as the card comes in.
          AnimatedBuilder(
            animation: shown,
            builder: (_, _) => BackdropFilter(
              filter: ImageFilter.blur(sigmaX: _backdropBlur * shown.value, sigmaY: _backdropBlur * shown.value),
              child: ColoredBox(color: Colors.black.withValues(alpha: _backdropDim * shown.value)),
            ),
          ),
          FadeTransition(
            opacity: shown,
            child: ScaleTransition(
              alignment: origin,
              scale: Tween(begin: _startScale, end: 1.0).animate(shown),
              child: child,
            ),
          ),
        ],
      );
    },
  );
}

const _backdropBlur = 14.0;
const _backdropDim = 0.45;
const _startScale = 0.86;

/// The card [showMediaPreview] opens. Its size never changes: what is still
/// loading has its room from the start.
class MediaPreview extends StatefulWidget {
  const MediaPreview({super.key, required this.media, this.isManga, this.onEdit, this.service});

  final Map<String, dynamic> media;
  final bool? isManga;
  final VoidCallback? onEdit;

  /// Talks to AniList; tests pass one with a mock client.
  final AniListService? service;

  static const coverSize = Size(100, 142);

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  static const _maxWidth = 340.0;
  static const _synopsisLines = 5;
  static const _genresShown = 3;

  late final AniListService _service = widget.service ?? AniListService();

  /// What AniList answered; null until then (and for good if it failed).
  Map<String, dynamic>? _loaded;
  bool _loading = true;

  int get _id => widget.media['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    final cache = context.read<ApiCache>();
    final token = auth.token;
    final userId = auth.user?['id'] as int?;
    // The answer says whether it is in the viewer's list: cached per account.
    final key = token == null ? 'anon:preview:$_id' : (userId == null ? null : ApiCache.userKey(userId, 'preview:$_id'));
    Future<Map<String, dynamic>> fetch() async {
      final data = await _service.request(_previewQuery, {'id': _id}, token: token);
      final media = data['Media'];
      if (media is Map<String, dynamic>) return media;
      throw const AniListRequestException('No media in the response', statusCode: 200);
    }

    void show(Map<String, dynamic> media) {
      if (mounted) setState(() => _loaded = media);
    }

    try {
      if (key == null) {
        show(await fetch());
      } else {
        await cache.load<Map<String, dynamic>>(
          key: key,
          fetch: fetch,
          decode: (json) => (json as Map).cast<String, dynamic>(),
          onData: (media, {required isFresh}) => show(media),
        );
      }
    } on Exception catch (e) {
      // The card still shows what the page already knew.
      debugPrint('[MediaPreview] Loading $_id failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// [key] from what was loaded, else from what the caller had.
  Object? _field(String key) => _loaded?[key] ?? widget.media[key];

  bool get _isManga =>
      widget.isManga ??
      switch (_field('type')) {
        'MANGA' => true,
        'ANIME' => false,
        _ => widget.media.containsKey('chapters') && !widget.media.containsKey('episodes'),
      };

  void _open() {
    final navigator = Navigator.of(context);
    final cover = (widget.media['coverImage'] as Map?)?['large'] as String?;
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => DetailScreen(animeId: _id, initialCoverUrl: cover)));
  }

  void _edit() {
    // The page under the preview hosts the editor; the preview is leaving.
    final navigator = Navigator.of(context);
    navigator.pop();
    final onEdit = widget.onEdit;
    if (onEdit != null) {
      onEdit();
      return;
    }
    final media = EditorMedia.fromMedia({...widget.media, ...?_loaded}, isManga: widget.isManga);
    if (media != null) showEntryEditor(navigator.context, media: media, entryKnown: false);
  }

  /// "★ 8.6 · TV · 26 eps · 1998", with whatever of it is known.
  String _facts(String lang) {
    final score = _field('averageScore');
    final format = _field('format');
    final episodes = _field('episodes');
    final chapters = _field('chapters');
    final year = _field('seasonYear');
    return [
      if (score is num) '★ ${(score / 10).toStringAsFixed(1)}',
      if (format is String) format.replaceAll('_', ' '),
      if (episodes is int)
        trf('search_eps', lang, {'n': episodes})
      else if (chapters is int)
        trf('search_ch', lang, {'n': chapters}),
      if (year is int) '$year',
    ].join(' · ');
  }

  /// "Watching · 3", when it is in the viewer's list.
  String? _listStatus(String lang) {
    final entry = _loaded?['mediaListEntry'];
    if (entry is! Map) return null;
    final status = entry['status'];
    if (status is! String) return null;
    final progress = entry['progress'];
    final label = tr(entryStatusKey(status, manga: _isManga), lang);
    return progress is int && progress > 0 ? '$label · $progress' : label;
  }

  Widget _header(BuildContext context, String lang) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final title = settings.resolveTitle(widget.media['title'] as Map<String, dynamic>?);
    final cover = (widget.media['coverImage'] as Map?)?['large'] as String?;
    final facts = _facts(lang);
    final listStatus = _listStatus(lang);
    final genres = [
      for (final genre in (_field('genres') as List? ?? const []).take(_genresShown))
        if (genre is String) genre,
    ];
    return SizedBox(
      height: MediaPreview.coverSize.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.fromSize(size: MediaPreview.coverSize, child: AppImage(url: cover, cacheWidth: 240)),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.headline),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    facts,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.footnote.copyWith(color: context.colors.textSecondary),
                  ),
                ],
                if (listStatus != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.16), borderRadius: AppRadius.pillAll),
                    child: Text(
                      listStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const Spacer(),
                if (genres.isNotEmpty)
                  Text(
                    genres.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(color: context.colors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What it is about, in a box as tall as [_synopsisLines] whether it is
  /// loading, there or missing, so the card never changes height.
  Widget _synopsis(BuildContext context) {
    final style = AppText.body.copyWith(color: context.colors.textSecondary, height: 1.4);
    final lineHeight = MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    final raw = _loaded?['description'] ?? widget.media['description'];
    final text = raw is String ? raw.replaceAll(RegExp(r'<[^>]{0,200}>'), '').trim() : '';
    final Widget content;
    if (text.isNotEmpty) {
      content = Text(text, maxLines: _synopsisLines, overflow: TextOverflow.ellipsis, style: style);
    } else if (_loading) {
      content = Skeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var line = 0; line < 3; line++)
              Padding(
                padding: EdgeInsets.only(top: lineHeight - 12),
                child: SkeletonBox(width: line == 2 ? 160 : null, height: 12),
              ),
          ],
        ),
      );
    } else {
      content = const SizedBox.shrink();
    }
    return SizedBox(
      height: lineHeight * _synopsisLines,
      width: double.infinity,
      child: Align(alignment: Alignment.topLeft, child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final loggedIn = context.select<AuthService, bool>((auth) => auth.isLoggedIn);
    final inList = widget.onEdit != null || _loaded?['mediaListEntry'] is Map;
    return GestureDetector(
      // A tap anywhere off the card closes it.
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: GestureDetector(
                // Taps on the card itself stay on it.
                onTap: () {},
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: AppRadius.lgAll,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(context, lang),
                        const SizedBox(height: AppSpace.md),
                        _synopsis(context),
                        const SizedBox(height: AppSpace.lg),
                        // Add or edit first, open at the right.
                        Row(
                          children: [
                            if (loggedIn) ...[
                              Expanded(
                                child: AppButton(
                                  key: const ValueKey('preview-edit'),
                                  label: tr(inList ? 'tooltip_edit_entry' : 'add_to_list', lang),
                                  expand: true,
                                  onPressed: _edit,
                                ),
                              ),
                              const SizedBox(width: AppSpace.md),
                            ],
                            Expanded(
                              child: AppButton(
                                key: const ValueKey('preview-open'),
                                label: tr('preview_open', lang),
                                kind: loggedIn ? AppButtonKind.tonal : AppButtonKind.primary,
                                expand: true,
                                onPressed: _open,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

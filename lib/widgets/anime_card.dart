import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../screens/detail_screen.dart';
import '../services/auth_service.dart';
import 'entry_editor/entry_editor_sheet.dart';

class AnimeCard extends StatelessWidget {
  final dynamic animeData; // from API
  final bool showScore;

  const AnimeCard({
    super.key,
    required this.animeData,
    this.showScore = true,
  });

  /// Long-press quick add: opens the entry editor, which looks the media up
  /// in the user's list (a new entry starts as Planning). Does nothing when
  /// logged out.
  void _quickAdd(BuildContext context) {
    final data = animeData;
    if (data is! Map<String, dynamic> || !context.read<AuthService>().isLoggedIn) return;
    final media = EditorMedia.fromMedia(data);
    if (media == null) return;
    HapticFeedback.mediumImpact();
    showEntryEditor(context, media: media, entryKnown: false);
  }

  @override
  Widget build(BuildContext context) {
    final id = animeData['id'] as int?;
    final title = context.select<SettingsProvider, String>(
      (s) => s.resolveTitle(animeData['title'] as Map<String, dynamic>?),
    );
    final image = animeData['coverImage']?['large'];
    final score = animeData['averageScore'];

    return GestureDetector(
      onTap: id == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetailScreen(animeId: id),
                ),
              ),
      onLongPress: id == null ? null : () => _quickAdd(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image != null
                      ? CachedNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.cover,
                          memCacheWidth: 240,
                          placeholder: (ctx, _) =>
                              Container(color: Theme.of(ctx).colorScheme.surfaceContainerHighest),
                          errorWidget: (ctx, _, _) =>
                              Container(color: Theme.of(ctx).colorScheme.surfaceContainerHighest),
                        )
                      : Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (showScore && score != null)
            Row(
              children: [
                const Icon(Icons.star, size: 12, color: Color(0xFFFFC107)),
                const SizedBox(width: 2),
                Text(
                  '${(score / 10).toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

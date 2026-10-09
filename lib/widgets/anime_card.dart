import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../screens/detail_screen.dart';

class AnimeCard extends StatelessWidget {
  final dynamic animeData; // from API
  final bool showScore;

  const AnimeCard({
    super.key,
    required this.animeData,
    this.showScore = true,
  });

  @override
  Widget build(BuildContext context) {
    final id = animeData['id'] as int?;
    final title = animeData['title']['english'] ??
        animeData['title']['romaji'] ??
        'Unknown';
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

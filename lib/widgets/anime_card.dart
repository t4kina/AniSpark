import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/anime.dart';
import '../screens/detail_screen.dart';

class AnimeCard extends StatelessWidget {
  final dynamic animeData; // from API
  final Anime? localAnime; // from local storage
  final bool showScore;

  const AnimeCard({
    super.key,
    this.animeData,
    this.localAnime,
    this.showScore = true,
  });

  @override
  Widget build(BuildContext context) {
    final id = animeData?['id'] ?? localAnime?.id;
    final title = animeData != null
        ? (animeData['title']['english'] ??
            animeData['title']['romaji'] ??
            'Unknown')
        : localAnime?.title ?? 'Unknown';
    final image = animeData?['coverImage']?['large'] ?? localAnime?.coverImage;
    final score = animeData?['averageScore'];
    final watched = localAnime?.episodesWatched ?? 0;
    final total = localAnime?.episodes;

    return GestureDetector(
      onTap: () => Navigator.push(
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
                  if (localAnime != null && watched > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '$watched${total != null ? "/$total" : ""}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ),
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

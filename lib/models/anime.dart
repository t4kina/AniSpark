import 'package:hive/hive.dart';

part 'anime.g.dart';

@HiveType(typeId: 0)
class Anime extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String? coverImage;

  @HiveField(3)
  final int? episodes;

  @HiveField(4)
  String status;

  @HiveField(5)
  int episodesWatched;

  @HiveField(6)
  int? userScore;

  @HiveField(7)
  final String? description;

  @HiveField(8)
  final double? averageScore;

  @HiveField(9)
  final List<String>? genres;

  Anime({
    required this.id,
    required this.title,
    this.coverImage,
    this.episodes,
    this.status = 'plan_to_watch',
    this.episodesWatched = 0,
    this.userScore,
    this.description,
    this.averageScore,
    this.genres,
  });

  factory Anime.fromApi(Map<String, dynamic> data) {
    final rawScore = data['averageScore'];
    final double? score =
        rawScore != null ? (rawScore as num).toDouble() : null;

    List<String>? genreList;
    if (data['genres'] != null) {
      genreList = List<String>.from(data['genres']);
    }

    return Anime(
      id: data['id'],
      title: data['title']['english'] ?? data['title']['romaji'] ?? data['title']['native'] ?? 'Unknown',
      coverImage: data['coverImage']?['large'] ?? data['coverImage']?['extraLarge'],
      episodes: data['episodes'],
      description: data['description'],
      averageScore: score,
      genres: genreList,
    );
  }
}
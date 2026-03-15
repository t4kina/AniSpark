import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/anime.dart';

class AnimeListProvider extends ChangeNotifier {
  late Box<Anime> _box;

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(AnimeAdapter());
    _box = await Hive.openBox<Anime>('myAnimeList');
  }

  List<Anime> get all => _box.values.toList();
  List<Anime> get watching =>
      _box.values.where((a) => a.status == 'watching').toList();
  List<Anime> get completed =>
      _box.values.where((a) => a.status == 'completed').toList();
  List<Anime> get planToWatch =>
      _box.values.where((a) => a.status == 'plan_to_watch').toList();
  List<Anime> get dropped =>
      _box.values.where((a) => a.status == 'dropped').toList();

  bool isInList(int id) => _box.containsKey(id);
  Anime? getAnime(int id) => _box.get(id);

  void addAnime(Anime anime) {
    _box.put(anime.id, anime);
    notifyListeners();
  }

  void removeAnime(int id) {
    _box.delete(id);
    notifyListeners();
  }

  void updateStatus(int id, String status) {
    final anime = _box.get(id);
    if (anime != null) {
      anime.status = status;
      anime.save();
      notifyListeners();
    }
  }

  void updateEpisodes(int id, int count) {
    final anime = _box.get(id);
    if (anime != null) {
      anime.episodesWatched = count;
      anime.save();
      notifyListeners();
    }
  }

  void updateScore(int id, int score) {
    final anime = _box.get(id);
    if (anime != null) {
      anime.userScore = score;
      anime.save();
      notifyListeners();
    }
  }
}
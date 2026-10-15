import 'package:anispark/utils/airing_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 16, 23, 30);

  Map<String, dynamic> schedule({int? duration}) => {
        'id': 9,
        'airingAt': start.millisecondsSinceEpoch ~/ 1000,
        'episode': 3,
        'media': {'id': 154587, 'duration': ?duration},
      };

  test('names the show and episode, from airing time to the episode\'s end', () {
    final event = airingEvent(schedule(duration: 25), title: 'Frieren', episodeLabel: 'Episode 3')!;

    expect(event.title, 'Frieren · Episode 3');
    expect(event.start, start);
    expect(event.end, start.add(const Duration(minutes: 25)));
  });

  test('links the show on AniList and alerts when it starts', () {
    final event = airingEvent(schedule(), title: 'Frieren')!;

    expect(event.notes, 'https://anilist.co/anime/154587');
    expect(event.url, 'https://anilist.co/anime/154587');
    expect(event.alertAtStart, isTrue);
  });

  test('lasts a usual episode when AniList has no duration', () {
    final event = airingEvent(schedule(), title: 'Frieren')!;

    expect(event.title, 'Frieren');
    expect(event.end.difference(event.start), defaultEpisodeLength);
  });

  test('is null without an airing time', () {
    final noTime = {
      'media': {'id': 1},
    };
    expect(airingEvent(noTime, title: 'Frieren'), isNull);
  });
}

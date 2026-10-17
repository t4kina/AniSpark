import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/mock_anilist.dart';

void main() {
  const token = 'test-token';
  late List<RecordedRequest> log;

  AniListService serviceReturning(Object body, {int status = 200}) =>
      AniListService(
        client: mockAniList(log, (_) => jsonResponse(body, status: status)),
      );

  AniListService offline() => AniListService(
        client: mockAniList(log, (_) => throw http.ClientException('offline')),
      );

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
  });

  group('toggleFollow', () {
    test('returns the new follow state', () async {
      final service = serviceReturning({
        'data': {
          'ToggleFollow': {'id': 3, 'isFollowing': false},
        },
      });

      expect(await service.toggleFollow(3, token), isFalse);
    });

    test('returns null on an HTTP error instead of looking like an unfollow', () async {
      final service = serviceReturning({'errors': []}, status: 500);

      expect(await service.toggleFollow(3, token), isNull);
    });

    test('returns null without network instead of throwing', () async {
      expect(await offline().toggleFollow(3, token), isNull);
    });
  });

  group('toggleCharacterFavourite', () {
    test('returns false without network instead of throwing', () async {
      expect(await offline().toggleCharacterFavourite(characterId: 1, token: token), isFalse);
    });

    test('returns false when AniList returns no data', () async {
      final service = serviceReturning({
        'data': {'ToggleFavourite': null},
      });

      expect(await service.toggleCharacterFavourite(characterId: 1, token: token), isFalse);
    });
  });

  group('responses with data: null', () {
    final noData = {
      'data': null,
      'errors': [
        {'message': 'Internal error'},
      ],
    };

    test('Discover queries return an empty list', () async {
      expect(await serviceReturning(noData).getTrending(), isEmpty);
    });

    test('getAnimeDetail returns null', () async {
      expect(await serviceReturning(noData).getAnimeDetail(1), isNull);
    });
  });
}

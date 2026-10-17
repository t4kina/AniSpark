import 'package:anispark/services/people_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _media(int id, {bool adult = false}) => {
      'id': id,
      'isAdult': adult,
      'title': {'romaji': 'Title $id'},
    };

Map<String, dynamic> _pageInfo(bool more) => {'hasNextPage': more};

void main() {
  group('an all-adult page that has more pages', () {
    test('StaffRolesPage keeps paging', () {
      final page = StaffRolesPage.fromJson({
        'pageInfo': _pageInfo(true),
        'edges': [
          {'staffRole': 'Director', 'node': _media(1, adult: true)},
          {'staffRole': 'Writer', 'node': _media(2, adult: true)},
        ],
      });
      expect(page.items, isEmpty);
      expect(page.hasNextPage, isTrue);
    });

    test('VoicedCharactersPage keeps paging', () {
      final page = VoicedCharactersPage.fromJson({
        'pageInfo': _pageInfo(true),
        'edges': [
          {
            'node': _media(1, adult: true),
            'characters': [
              {'id': 5, 'name': {'full': 'A'}},
            ],
          },
        ],
      });
      expect(page.items, isEmpty);
      expect(page.hasNextPage, isTrue);
    });

    test('MediaPage keeps paging', () {
      final page = MediaPage.fromJson({
        'pageInfo': _pageInfo(true),
        'nodes': [_media(1, adult: true), _media(2, adult: true)],
      });
      expect(page.media, isEmpty);
      expect(page.hasNextPage, isTrue);
    });

    test('survive a cache round trip', () {
      final staff = StaffRolesPage.fromJson({
        'pageInfo': _pageInfo(true),
        'edges': [
          {'staffRole': 'Director', 'node': _media(1, adult: true)},
        ],
      });
      final media = MediaPage.fromJson({
        'pageInfo': _pageInfo(true),
        'nodes': [_media(1, adult: true)],
      });
      final voiced = VoicedCharactersPage.fromJson({
        'pageInfo': _pageInfo(true),
        'edges': [
          {
            'node': _media(1, adult: true),
            'characters': [
              {'id': 5, 'name': {'full': 'A'}},
            ],
          },
        ],
      });

      expect(StaffRolesPage.fromJson(staff.toJson()).hasNextPage, isTrue);
      expect(MediaPage.fromJson(media.toJson()).hasNextPage, isTrue);
      expect(VoicedCharactersPage.fromJson(voiced.toJson()).hasNextPage, isTrue);
    });
  });

  group('an empty raw page ends paging even if AniList says there is more', () {
    test('StaffRolesPage', () {
      expect(StaffRolesPage.fromJson({'pageInfo': _pageInfo(true), 'edges': []}).hasNextPage, isFalse);
    });

    test('VoicedCharactersPage', () {
      expect(VoicedCharactersPage.fromJson({'pageInfo': _pageInfo(true), 'edges': []}).hasNextPage, isFalse);
    });

    test('MediaPage', () {
      expect(MediaPage.fromJson({'pageInfo': _pageInfo(true), 'nodes': []}).hasNextPage, isFalse);
    });
  });

  test('a page with visible items keeps AniList hasNextPage', () {
    final page = MediaPage.fromJson({
      'pageInfo': _pageInfo(true),
      'nodes': [_media(1), _media(2, adult: true)],
    });
    expect([for (final m in page.media) m.id], [1]);
    expect(page.hasNextPage, isTrue);
    expect(MediaPage.fromJson({'pageInfo': _pageInfo(false), 'nodes': [_media(1)]}).hasNextPage, isFalse);
  });
}

import 'anilist_service.dart';
import 'people_models.dart';

export 'people_models.dart';

/// AniList queries behind the staff, studio and character pages: people,
/// the characters they voiced, their credits and studios' productions.
///
/// Adult media are always left out. Everything here is public except a
/// character's `isFavourite`, which needs the viewer's token.
class PeopleApi {
  PeopleApi({AniListService? service}) : _service = service ?? AniListService();

  final AniListService _service;

  // AniList caps nested connections (characterMedia, Studio.media…) at 25
  // per page.

  /// Voiced characters and staff roles per page (fits 2, 3 and 4 columns).
  static const staffPageSize = 24;

  /// Productions per page of a studio.
  static const studioPageSize = 25;

  /// Appearances listed on a character page; its voice actors come from them.
  static const characterMediaCount = 10;

  static const _mediaFields = '''
    id type format isAdult averageScore
    title { romaji english native }
    coverImage { large }
    startDate { year }
  ''';

  static const _voicedCharactersFields = '''
    pageInfo { hasNextPage }
    edges {
      characterRole
      node { $_mediaFields }
      characters { id name { full } image { large } }
    }
  ''';

  static const _staffRolesFields = '''
    pageInfo { hasNextPage }
    edges { staffRole node { $_mediaFields } }
  ''';

  static const _studioMediaFields = '''
    pageInfo { hasNextPage }
    nodes { $_mediaFields }
  ''';

  // Ties are broken by id so consecutive pages never overlap.
  static const staffQuery = '''
    query (\$id: Int, \$perPage: Int) {
      Staff(id: \$id) {
        id
        name { full native }
        image { large }
        description(asHtml: false)
        primaryOccupations gender age yearsActive homeTown bloodType favourites
        dateOfBirth { year month day }
        dateOfDeath { year month day }
        characterMedia(page: 1, perPage: \$perPage, sort: [POPULARITY_DESC, ID]) {
          $_voicedCharactersFields
        }
        staffMedia(page: 1, perPage: \$perPage, sort: [POPULARITY_DESC, ID]) {
          $_staffRolesFields
        }
      }
    }
  ''';

  static const voicedCharactersQuery = '''
    query (\$id: Int, \$page: Int, \$perPage: Int) {
      Staff(id: \$id) {
        characterMedia(page: \$page, perPage: \$perPage, sort: [POPULARITY_DESC, ID]) {
          $_voicedCharactersFields
        }
      }
    }
  ''';

  static const staffRolesQuery = '''
    query (\$id: Int, \$page: Int, \$perPage: Int) {
      Staff(id: \$id) {
        staffMedia(page: \$page, perPage: \$perPage, sort: [POPULARITY_DESC, ID]) {
          $_staffRolesFields
        }
      }
    }
  ''';

  // `isMain: false` is the complement of `isMain: true`, so the two lists
  // never share a media.
  static const studioQuery = '''
    query (\$id: Int, \$perPage: Int) {
      Studio(id: \$id) {
        id name isAnimationStudio favourites
        main: media(isMain: true, page: 1, perPage: \$perPage, sort: [POPULARITY_DESC, ID]) {
          $_studioMediaFields
        }
        other: media(isMain: false, page: 1, perPage: \$perPage, sort: [POPULARITY_DESC, ID]) {
          $_studioMediaFields
        }
      }
    }
  ''';

  static const studioMediaQuery = '''
    query (\$id: Int, \$isMain: Boolean, \$page: Int, \$perPage: Int) {
      Studio(id: \$id) {
        media(isMain: \$isMain, page: \$page, perPage: \$perPage, sort: [POPULARITY_DESC, ID]) {
          $_studioMediaFields
        }
      }
    }
  ''';

  // Without a language, voiceActors lists every dub.
  static const characterQuery = '''
    query (\$id: Int, \$perPage: Int) {
      Character(id: \$id) {
        id isFavourite
        name { full native }
        image { large }
        description(asHtml: false)
        gender age bloodType
        dateOfBirth { year month day }
        media(perPage: \$perPage, sort: [POPULARITY_DESC]) {
          edges {
            node { $_mediaFields }
            voiceActors(sort: [RELEVANCE, ID]) { id name { full } image { large } languageV2 }
          }
        }
      }
    }
  ''';

  /// The staff member [staffId] with the first page of their voiced
  /// characters and staff roles.
  Future<StaffDetail> getStaff(int staffId) async {
    final data = await _service.request(staffQuery, {'id': staffId, 'perPage': staffPageSize});
    final staff = StaffDetail.fromJson(data['Staff']);
    if (staff == null) {
      throw const AniListRequestException('No staff in the response', statusCode: 200);
    }
    return staff;
  }

  /// Page [page] of the characters [staffId] voiced, most popular media first.
  Future<VoicedCharactersPage> getVoicedCharacters(int staffId, {required int page}) async {
    assert(page >= 1, 'AniList pages start at 1');
    final data = await _service.request(
      voicedCharactersQuery,
      {'id': staffId, 'page': page, 'perPage': staffPageSize},
    );
    final staff = data['Staff'];
    return VoicedCharactersPage.fromJson(staff is Map ? staff['characterMedia'] : null);
  }

  /// Page [page] of [staffId]'s staff credits, most popular media first.
  Future<StaffRolesPage> getStaffRoles(int staffId, {required int page}) async {
    assert(page >= 1, 'AniList pages start at 1');
    final data = await _service.request(
      staffRolesQuery,
      {'id': staffId, 'page': page, 'perPage': staffPageSize},
    );
    final staff = data['Staff'];
    return StaffRolesPage.fromJson(staff is Map ? staff['staffMedia'] : null);
  }

  /// The studio [studioId] with the first page of the media it was the main
  /// studio of and the first page of the rest.
  Future<StudioDetail> getStudio(int studioId) async {
    final data = await _service.request(studioQuery, {'id': studioId, 'perPage': studioPageSize});
    final studio = StudioDetail.fromJson(data['Studio']);
    if (studio == null) {
      throw const AniListRequestException('No studio in the response', statusCode: 200);
    }
    return studio;
  }

  /// Page [page] of [studioId]'s media, most popular first: those it was the
  /// main studio of when [isMain], otherwise the rest.
  Future<MediaPage> getStudioMedia(int studioId, {required bool isMain, required int page}) async {
    assert(page >= 1, 'AniList pages start at 1');
    final data = await _service.request(
      studioMediaQuery,
      {'id': studioId, 'isMain': isMain, 'page': page, 'perPage': studioPageSize},
    );
    final studio = data['Studio'];
    return MediaPage.fromJson(studio is Map ? studio['media'] : null);
  }

  /// The character [characterId] with its most popular appearances and
  /// everyone who voiced it in them. With a [token] `isFavourite` is the
  /// viewer's.
  Future<CharacterDetail> getCharacter(int characterId, {String? token}) async {
    final data = await _service.request(
      characterQuery,
      {'id': characterId, 'perPage': characterMediaCount},
      token: token,
    );
    final character = CharacterDetail.fromJson(data['Character']);
    if (character == null) {
      throw const AniListRequestException('No character in the response', statusCode: 200);
    }
    return character;
  }
}

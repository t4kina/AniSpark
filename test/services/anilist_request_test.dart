import 'package:anispark/services/anilist_service.dart';
import 'package:anispark/utils/refresh_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_anilist.dart';

void main() {
  late List<RecordedRequest> log;

  setUp(() {
    log = [];
    authExpiredNotifier.value = 0;
  });

  AniListService serviceReturning(Object body, {int status = 200}) => AniListService(
        client: mockAniList(log, (_) => jsonResponse(body, status: status)),
      );

  test('returns the data map and sends variables and the token', () async {
    final service = serviceReturning({
      'data': {'Media': {'id': 1}},
    });

    final data = await service.request('query(\$id: Int) { Media(id: \$id) { id } }', {'id': 1}, token: 't');

    expect(data, {'Media': {'id': 1}});
    expect(log.single.variables, {'id': 1});
    expect(log.single.authorization, 'Bearer t');
  });

  test('throws with the status code on HTTP errors and reports 401s', () async {
    final service = serviceReturning({'errors': []}, status: 401);

    await expectLater(
      service.request('query { Viewer { id } }', const {}, token: 't'),
      throwsA(isA<AniListRequestException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(authExpiredNotifier.value, 1);
  });

  test('throws when the response carries no data', () async {
    final service = serviceReturning({
      'data': null,
      'errors': [
        {'message': 'Not Found.'},
      ],
    });

    await expectLater(
      service.request('query { Media(id: 0) { id } }', const {}),
      throwsA(isA<AniListRequestException>().having((e) => e.message, 'message', 'Not Found.')),
    );
  });
}

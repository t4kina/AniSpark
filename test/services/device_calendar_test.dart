import 'package:anispark/services/device_calendar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final start = DateTime(2026, 10, 16, 23, 30);
  final event = CalendarEvent(
    title: 'Frieren · Episode 3',
    start: start,
    end: start.add(const Duration(minutes: 24)),
    notes: 'https://anilist.co/anime/154587',
    url: 'https://anilist.co/anime/154587',
    alertAtStart: true,
  );

  tearDown(() => messenger.setMockMethodCallHandler(calendarChannel, null));

  test('sends the event to the platform and passes its answer back', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(calendarChannel, (call) async {
      calls.add(call);
      return true;
    });

    expect(await openNewCalendarEvent(event), isTrue);

    expect(calls.single.method, 'addEvent');
    expect(calls.single.arguments, {
      'title': 'Frieren · Episode 3',
      'start': start.millisecondsSinceEpoch,
      'end': start.add(const Duration(minutes: 24)).millisecondsSinceEpoch,
      'notes': 'https://anilist.co/anime/154587',
      'url': 'https://anilist.co/anime/154587',
      'alertAtStart': true,
    });
  });

  test('reads no answer as not added', () async {
    messenger.setMockMethodCallHandler(calendarChannel, (_) async => null);

    expect(await openNewCalendarEvent(event), isFalse);
  });

  test('lets a platform failure through for the caller to report', () async {
    messenger.setMockMethodCallHandler(calendarChannel, (_) async => throw PlatformException(code: 'no_window'));

    expect(openNewCalendarEvent(event), throwsA(isA<PlatformException>()));
  });
}

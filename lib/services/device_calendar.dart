import 'package:flutter/services.dart';

/// An event to fill the device calendar's "new event" sheet with.
class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    this.notes,
    this.url,
    this.alertAtStart = false,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? notes;

  /// Shown as the event's link on iOS; Android has no such field.
  final String? url;

  /// An alert when it starts (iOS; Android keeps the calendar's own
  /// reminders).
  final bool alertAtStart;

  Map<String, Object?> toMap() => {
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'notes': notes,
        'url': url,
        'alertAtStart': alertAtStart,
      };
}

/// Opens the device calendar's "new event" sheet for an event. On iOS the
/// result says whether the event was saved; on Android, whether a calendar
/// app opened.
typedef AddCalendarEvent = Future<bool> Function(CalendarEvent event);

/// Answered by the app's own code in `AppDelegate.swift` and
/// `MainActivity.kt`.
const calendarChannel = MethodChannel('anispark/calendar');

/// The platform's [AddCalendarEvent]. Throws a [PlatformException] or
/// [MissingPluginException] when the platform can't open the sheet.
Future<bool> openNewCalendarEvent(CalendarEvent event) async =>
    await calendarChannel.invokeMethod<bool>('addEvent', event.toMap()) ?? false;

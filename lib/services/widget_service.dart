import 'package:flutter/services.dart';

class WidgetService {
  static const _channel = MethodChannel('com.example.anispark/widget');

  static Future<void> update({
    required int watchingCount,
    required int completedCount,
    String? airingToday,
  }) async {
    try {
      await _channel.invokeMethod('updateWidget', {
        'watching_count': watchingCount,
        'completed_count': completedCount,
        'airing_today': airingToday ?? '',
      });
    } catch (_) {
      // Widget not installed or platform not supported — silently ignore
    }
  }
}

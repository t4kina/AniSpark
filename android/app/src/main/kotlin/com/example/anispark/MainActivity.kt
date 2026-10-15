package com.example.anispark

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // lib/services/device_calendar.dart
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "anispark/calendar")
            .setMethodCallHandler { call, result ->
                if (call.method == "addEvent") {
                    result.success(openNewEvent(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()))
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Opens the calendar app's "new event" screen filled in with [event].
     * False when it can't: no calendar app, or no times to fill in.
     */
    private fun openNewEvent(event: Map<*, *>): Boolean {
        val start = (event["start"] as? Number)?.toLong() ?: return false
        val end = (event["end"] as? Number)?.toLong() ?: return false
        val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.Events.TITLE, event["title"] as? String)
            .putExtra(CalendarContract.Events.DESCRIPTION, event["notes"] as? String)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}

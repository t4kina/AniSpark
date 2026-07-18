package com.example.anispark

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "com.example.anispark/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                if (call.method == "updateWidget") {
                    val watching  = call.argument<Int>("watching_count") ?: 0
                    val completed = call.argument<Int>("completed_count") ?: 0
                    val airing    = call.argument<String>("airing_today") ?: ""

                    // Write to the prefs that the widget provider reads
                    val prefs = applicationContext.getSharedPreferences(
                        "HomeWidgetPlugin", Context.MODE_PRIVATE
                    )
                    prefs.edit()
                        .putInt("widget_watching_count", watching)
                        .putInt("widget_completed_count", completed)
                        .putString("widget_airing_today", airing.ifEmpty { null })
                        .apply()

                    // Notify all instances of the widget to refresh
                    val manager = AppWidgetManager.getInstance(applicationContext)
                    val ids = manager.getAppWidgetIds(
                        ComponentName(applicationContext, AniSparkWidgetProvider::class.java)
                    )
                    for (id in ids) {
                        AniSparkWidgetProvider.updateWidget(applicationContext, manager, id)
                    }

                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}

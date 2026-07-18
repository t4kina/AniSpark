package com.example.anispark

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class AniSparkWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            updateWidget(context, appWidgetManager, id)
        }
    }

    companion object {
        fun updateWidget(context: Context, appWidgetManager: AppWidgetManager, widgetId: Int) {
            val prefs = context.getSharedPreferences("HomeWidgetPlugin", Context.MODE_PRIVATE)
            val watching  = prefs.getInt("widget_watching_count", -1)
            val completed = prefs.getInt("widget_completed_count", -1)
            val airing    = prefs.getString("widget_airing_today", null)

            val views = RemoteViews(context.packageName, R.layout.anispark_widget)

            views.setTextViewText(
                R.id.widget_watching,
                if (watching >= 0) "Watching: $watching" else "Watching: —"
            )
            views.setTextViewText(
                R.id.widget_completed,
                if (completed >= 0) "$completed completed" else ""
            )
            views.setTextViewText(
                R.id.widget_airing,
                airing ?: ""
            )

            // Tap opens the app
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            val pendingIntent = PendingIntent.getActivity(
                context, 0, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_watching, pendingIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

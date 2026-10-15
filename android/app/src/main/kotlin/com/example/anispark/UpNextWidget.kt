package com.example.anispark

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.os.Bundle
import android.text.format.DateFormat
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.concurrent.thread
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * The "Up next" home-screen widget: the next episodes airing from the user's
 * AniList list (popular ones when logged out), in their accent colour. The
 * app says who's logged in and the accent (lib/services/home_widgets.dart);
 * the widget fetches the episodes itself every 30 minutes and keeps the last
 * answer, covers included, for when AniList can't be reached.
 */
class UpNextWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        thread {
            try {
                refresh(context)
                for (id in ids) render(context, manager, id)
            } finally {
                pending.finish()
            }
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        // Resized: as many rows as fit, from what's already saved.
        render(context, manager, id)
    }

    companion object {
        /** The app's default accent, until it says otherwise. */
        const val DEFAULT_ACCENT = 0xFF02A9FF.toInt()

        private const val TAG = "UpNextWidget"
        private const val PREFS = "up_next_widget"
        private const val KEY_USER = "user"
        private const val KEY_ACCENT = "accent"
        private const val KEY_UP_NEXT = "up_next"
        private const val KEY_FAILED = "failed"
        private const val COVER_DIR = "up_next_covers"
        private const val IMAGE_TIMEOUT_MS = 5_000

        // A row and the header, in dp, for how many rows fit.
        private const val ROW_HEIGHT_DP = 46
        private const val HEADER_HEIGHT_DP = 44

        private val ROWS = intArrayOf(R.id.widget_row_0, R.id.widget_row_1, R.id.widget_row_2)
        private val COVERS = intArrayOf(R.id.widget_cover_0, R.id.widget_cover_1, R.id.widget_cover_2)
        private val TITLES = intArrayOf(R.id.widget_title_0, R.id.widget_title_1, R.id.widget_title_2)
        private val TIMES = intArrayOf(R.id.widget_time_0, R.id.widget_time_1, R.id.widget_time_2)

        /** Called by the app with the logged-in user (null when logged out) and the accent. */
        fun configure(context: Context, user: String?, accent: Int) {
            val prefs = prefs(context)
            val editor = prefs.edit().putString(KEY_USER, user).putInt(KEY_ACCENT, accent)
            // Someone else's list isn't shown while the new one loads.
            if (prefs.getString(KEY_USER, null) != user) editor.remove(KEY_UP_NEXT).remove(KEY_FAILED)
            editor.apply()
            requestUpdate(context)
        }

        private fun requestUpdate(context: Context) {
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, UpNextWidget::class.java))
            if (ids.isEmpty()) return
            context.sendBroadcast(
                Intent(context, UpNextWidget::class.java)
                    .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
            )
        }

        private fun prefs(context: Context): SharedPreferences =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** Fetches and saves what to show; on failure the last answer stays. */
        private fun refresh(context: Context) {
            val prefs = prefs(context)
            try {
                val upNext = UpNextSource.fetch(prefs.getString(KEY_USER, null), System.currentTimeMillis() / 1000)
                saveCovers(context, upNext.episodes)
                prefs.edit().putString(KEY_UP_NEXT, encode(upNext)).putBoolean(KEY_FAILED, false).apply()
            } catch (e: IOException) {
                Log.w(TAG, "Fetching the airing episodes failed", e)
                prefs.edit().putBoolean(KEY_FAILED, true).apply()
            } catch (e: JSONException) {
                Log.w(TAG, "AniList's answer couldn't be read", e)
                prefs.edit().putBoolean(KEY_FAILED, true).apply()
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = prefs(context)
            val accent = prefs.getInt(KEY_ACCENT, DEFAULT_ACCENT)
            val upNext = prefs.getString(KEY_UP_NEXT, null)?.let(::decode)
            val now = System.currentTimeMillis() / 1000
            val episodes = upNext?.episodes.orEmpty().filter { it.airingAt > now }.take(rowsThatFit(manager, id))

            val views = RemoteViews(context.packageName, R.layout.widget_up_next)
            views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
            views.setInt(R.id.widget_dot, "setColorFilter", accent)
            views.setTextViewText(
                R.id.widget_header,
                context.getString(if (upNext?.fromList == false) R.string.widget_airing_soon else R.string.widget_up_next),
            )
            val message = when {
                episodes.isNotEmpty() -> null
                upNext != null -> R.string.widget_empty
                prefs.getBoolean(KEY_FAILED, false) -> R.string.widget_error
                else -> R.string.widget_loading
            }
            views.setViewVisibility(R.id.widget_message, if (message == null) View.GONE else View.VISIBLE)
            message?.let { views.setTextViewText(R.id.widget_message, context.getString(it)) }

            for (i in ROWS.indices) {
                val episode = episodes.getOrNull(i)
                views.setViewVisibility(ROWS[i], if (episode == null) View.GONE else View.VISIBLE)
                if (episode == null) continue
                views.setTextViewText(TITLES[i], episode.title)
                views.setTextViewText(
                    TIMES[i],
                    context.getString(R.string.widget_episode_at, episode.episode, whenLabel(context, episode.airingAt)),
                )
                views.setTextColor(TIMES[i], accent)
                val cover = BitmapFactory.decodeFile(coverFile(context, episode.mediaId).path)
                if (cover != null) {
                    views.setImageViewBitmap(COVERS[i], cover)
                } else {
                    views.setImageViewResource(COVERS[i], R.drawable.widget_cover_placeholder)
                }
            }
            manager.updateAppWidget(id, views)
        }

        private fun rowsThatFit(manager: AppWidgetManager, id: Int): Int {
            // Portrait height; 0 before the launcher has said.
            val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
            if (height <= 0) return UpNextSource.MAX_EPISODES
            return ((height - HEADER_HEIGHT_DP) / ROW_HEIGHT_DP).coerceIn(1, UpNextSource.MAX_EPISODES)
        }

        private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        /** "Today 18:30", "Tomorrow 01:00", "Fri 23:30", in the device's language and clock. */
        private fun whenLabel(context: Context, airingAt: Long): String {
            val time = Date(airingAt * 1000)
            val airs = Calendar.getInstance().apply { this.time = time }
            val today = Calendar.getInstance()
            val tomorrow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }
            val day = when {
                sameDay(today, airs) -> context.getString(R.string.widget_today)
                sameDay(tomorrow, airs) -> context.getString(R.string.widget_tomorrow)
                else -> SimpleDateFormat("EEE", Locale.getDefault()).format(time)
            }
            return "$day ${DateFormat.getTimeFormat(context).format(time)}"
        }

        private fun sameDay(a: Calendar, b: Calendar) =
            a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)

        // ── Saved answer ─────────────────────────────────────────────────

        private fun encode(upNext: UpNext): String {
            val episodes = JSONArray()
            for (episode in upNext.episodes) {
                episodes.put(
                    JSONObject()
                        .put("mediaId", episode.mediaId)
                        .put("title", episode.title)
                        .put("episode", episode.episode)
                        .put("airingAt", episode.airingAt),
                )
            }
            return JSONObject().put("fromList", upNext.fromList).put("episodes", episodes).toString()
        }

        private fun decode(saved: String): UpNext? = try {
            val json = JSONObject(saved)
            val episodes = json.getJSONArray("episodes")
            UpNext(
                fromList = json.getBoolean("fromList"),
                episodes = (0 until episodes.length()).map {
                    val episode = episodes.getJSONObject(it)
                    AiringEpisode(
                        mediaId = episode.getInt("mediaId"),
                        title = episode.getString("title"),
                        episode = episode.getInt("episode"),
                        airingAt = episode.getLong("airingAt"),
                        coverUrl = null,
                    )
                },
            )
        } catch (e: JSONException) {
            Log.w(TAG, "The saved episodes couldn't be read", e)
            null
        }

        // ── Covers ───────────────────────────────────────────────────────

        private fun coverFile(context: Context, mediaId: Int) = File(File(context.cacheDir, COVER_DIR), "$mediaId.png")

        /** Downloads the covers [episodes] need and deletes the others. */
        private fun saveCovers(context: Context, episodes: List<AiringEpisode>) {
            val dir = File(context.cacheDir, COVER_DIR).apply { mkdirs() }
            for (episode in episodes) {
                val file = coverFile(context, episode.mediaId)
                val url = episode.coverUrl ?: continue
                if (file.exists()) continue
                val cover = downloadImage(url) ?: continue
                FileOutputStream(file).use { rounded(cover).compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
            val keep = episodes.map { "${it.mediaId}.png" }.toSet()
            dir.listFiles()?.filter { it.name !in keep }?.forEach { it.delete() }
        }

        private fun downloadImage(url: String): Bitmap? {
            val connection = URL(url).openConnection() as HttpURLConnection
            return try {
                connection.connectTimeout = IMAGE_TIMEOUT_MS
                connection.readTimeout = IMAGE_TIMEOUT_MS
                connection.inputStream.use { BitmapFactory.decodeStream(it) }
            } catch (e: IOException) {
                Log.w(TAG, "Downloading a cover failed", e)
                null
            } finally {
                connection.disconnect()
            }
        }

        /** [source] with rounded corners, as RemoteViews can't clip an image. */
        private fun rounded(source: Bitmap): Bitmap {
            val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            }
            val radius = source.width * 0.12f
            Canvas(output).drawRoundRect(
                RectF(0f, 0f, source.width.toFloat(), source.height.toFloat()),
                radius,
                radius,
                paint,
            )
            return output
        }
    }
}

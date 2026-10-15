package com.example.anispark

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONArray
import org.json.JSONObject

/** An episode the widget shows. [airingAt] is in epoch seconds. */
data class AiringEpisode(
    val mediaId: Int,
    val title: String,
    val episode: Int,
    val airingAt: Long,
    val coverUrl: String?,
)

/** What the widget shows: the next episodes from the user's list, or popular ones. */
data class UpNext(val fromList: Boolean, val episodes: List<AiringEpisode>)

/** Asks AniList what the "Up next" widget shows; public data, so no token. */
object UpNextSource {
    const val MAX_EPISODES = 3

    private const val ENDPOINT = "https://graphql.anilist.co"
    private const val TIMEOUT_MS = 5_000
    private const val DAY_SECONDS = 86_400L

    // The calendar's "My list": what the user watches or plans to.
    private val listQuery = """
        query(${'$'}name: String) {
          MediaListCollection(userName: ${'$'}name, type: ANIME, status_in: [CURRENT, PLANNING]) {
            lists { entries { media {
              id title { userPreferred } coverImage { medium }
              nextAiringEpisode { episode airingAt }
            } } }
          }
        }
    """.trimIndent()

    private val popularQuery = """
        query(${'$'}from: Int, ${'$'}to: Int) {
          Page(perPage: 50) {
            airingSchedules(airingAt_greater: ${'$'}from, airingAt_lesser: ${'$'}to, sort: TIME) {
              episode airingAt
              media { id isAdult popularity title { userPreferred } coverImage { medium } }
            }
          }
        }
    """.trimIndent()

    /**
     * The next episodes from [user]'s list, else (logged out, a private list
     * or nothing on it airing) the most popular ones airing in the next day.
     * Throws [IOException] when AniList can't be reached.
     */
    fun fetch(user: String?, nowSeconds: Long): UpNext {
        if (user != null) {
            val mine = try {
                fromList(user, nowSeconds)
            } catch (e: IOException) {
                emptyList()
            }
            if (mine.isNotEmpty()) return UpNext(fromList = true, episodes = mine)
        }
        return UpNext(fromList = false, episodes = popular(nowSeconds))
    }

    private fun fromList(user: String, now: Long): List<AiringEpisode> {
        val data = post(listQuery, JSONObject().put("name", user))
        val lists = data.optJSONObject("MediaListCollection")?.optJSONArray("lists") ?: return emptyList()
        // A show can be on more than one (custom) list.
        val byMedia = HashMap<Int, AiringEpisode>()
        for (entries in lists.objects().mapNotNull { it.optJSONArray("entries") }) {
            for (media in entries.objects().mapNotNull { it.optJSONObject("media") }) {
                val next = media.optJSONObject("nextAiringEpisode") ?: continue
                val episode = episodeOf(media, next) ?: continue
                if (episode.airingAt > now) byMedia[episode.mediaId] = episode
            }
        }
        return byMedia.values.sortedBy { it.airingAt }.take(MAX_EPISODES)
    }

    private fun popular(now: Long): List<AiringEpisode> {
        val variables = JSONObject().put("from", now).put("to", now + DAY_SECONDS)
        val schedules = post(popularQuery, variables).optJSONObject("Page")?.optJSONArray("airingSchedules")
            ?: return emptyList()
        val found = ArrayList<Pair<Int, AiringEpisode>>()
        for (schedule in schedules.objects()) {
            val media = schedule.optJSONObject("media") ?: continue
            if (media.optBoolean("isAdult")) continue
            val episode = episodeOf(media, schedule) ?: continue
            found += media.optInt("popularity") to episode
        }
        return found.sortedByDescending { it.first }.take(MAX_EPISODES).map { it.second }.sortedBy { it.airingAt }
    }

    /** [airing] holds `episode` and `airingAt`: a schedule or a nextAiringEpisode. */
    private fun episodeOf(media: JSONObject, airing: JSONObject): AiringEpisode? {
        val id = media.optInt("id", -1)
        val title = media.optJSONObject("title")?.stringOrNull("userPreferred")
        val episode = airing.optInt("episode", -1)
        val airingAt = airing.optLong("airingAt", -1)
        if (id < 0 || title.isNullOrBlank() || episode < 0 || airingAt < 0) return null
        val cover = media.optJSONObject("coverImage")?.stringOrNull("medium")?.takeIf { it.startsWith("https://") }
        return AiringEpisode(id, title, episode, airingAt, cover)
    }

    private fun post(query: String, variables: JSONObject): JSONObject {
        val connection = URL(ENDPOINT).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            val body = JSONObject().put("query", query).put("variables", variables).toString()
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            if (status != HttpURLConnection.HTTP_OK) throw IOException("AniList answered $status")
            val text = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            return JSONObject(text).optJSONObject("data") ?: throw IOException("AniList sent no data")
        } finally {
            connection.disconnect()
        }
    }
}

private fun JSONArray.objects(): List<JSONObject> = (0 until length()).mapNotNull { optJSONObject(it) }

/** The string at [key], or null when it's missing or JSON null (optString gives "null"). */
private fun JSONObject.stringOrNull(key: String): String? = if (isNull(key)) null else optString(key)

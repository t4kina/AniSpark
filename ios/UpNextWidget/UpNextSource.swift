import Foundation
import UIKit

/// An episode the widget shows.
struct AiringEpisode: Identifiable {
  let id: Int
  let title: String
  let episode: Int
  let airingAt: Date
  let coverURL: URL?
  var cover: UIImage?
}

/// Asks AniList what the "Up next" widget shows; public data, so no token.
/// The Android widget does the same in UpNextSource.kt.
enum UpNextSource {
  static let maxEpisodes = 3

  private static let endpoint = URL(string: "https://graphql.anilist.co")!
  private static let day = 86_400
  private static let coverSize = CGSize(width: 120, height: 170)

  // The calendar's "My list": what the user watches or plans to.
  private static let listQuery = """
    query($name: String) {
      MediaListCollection(userName: $name, type: ANIME, status_in: [CURRENT, PLANNING]) {
        lists { entries { media {
          id title { userPreferred } coverImage { medium }
          nextAiringEpisode { episode airingAt }
        } } }
      }
    }
    """

  private static let popularQuery = """
    query($from: Int, $to: Int) {
      Page(perPage: 50) {
        airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: TIME) {
          episode airingAt
          media { id isAdult popularity title { userPreferred } coverImage { medium } }
        }
      }
    }
    """

  /// The next episodes from [username]'s list, else (no username, a private
  /// list or nothing on it airing) the most popular ones airing in the next
  /// day. Throws when AniList can't be reached.
  static func fetch(username: String?) async throws -> (fromList: Bool, episodes: [AiringEpisode]) {
    let name = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !name.isEmpty, let mine = try? await fromList(name), !mine.isEmpty {
      return (true, await withCovers(mine))
    }
    let mostPopular = try await popular()
    return (false, await withCovers(mostPopular))
  }

  private static func fromList(_ name: String) async throws -> [AiringEpisode] {
    let data: ListData = try await post(listQuery, ["name": name])
    let now = Date()
    // A show can be on more than one (custom) list.
    var byMedia: [Int: AiringEpisode] = [:]
    for list in data.collection?.lists ?? [] {
      for entry in list.entries ?? [] {
        guard let media = entry.media, let next = media.nextAiringEpisode,
              let airing = makeEpisode(media, next.episode, next.airingAt), airing.airingAt > now else { continue }
        byMedia[airing.id] = airing
      }
    }
    return Array(byMedia.values.sorted { $0.airingAt < $1.airingAt }.prefix(maxEpisodes))
  }

  private static func popular() async throws -> [AiringEpisode] {
    let now = Int(Date().timeIntervalSince1970)
    let data: ScheduleData = try await post(popularQuery, ["from": now, "to": now + day])
    let found = (data.page?.airingSchedules ?? []).compactMap { schedule -> (Int, AiringEpisode)? in
      guard let media = schedule.media, media.isAdult != true,
            let airing = makeEpisode(media, schedule.episode, schedule.airingAt) else { return nil }
      return (media.popularity ?? 0, airing)
    }
    let mostPopular = found.sorted { $0.0 > $1.0 }.prefix(maxEpisodes).map { $0.1 }
    return mostPopular.sorted { $0.airingAt < $1.airingAt }
  }

  private static func makeEpisode(_ media: Media, _ number: Int, _ airingAt: Int) -> AiringEpisode? {
    guard let title = media.title?.userPreferred, !title.isEmpty else { return nil }
    var cover: URL?
    if let link = media.coverImage?.medium, let url = URL(string: link), url.scheme == "https" {
      cover = url
    }
    return AiringEpisode(
      id: media.id,
      title: title,
      episode: number,
      airingAt: Date(timeIntervalSince1970: TimeInterval(airingAt)),
      coverURL: cover
    )
  }

  /// [episodes] with their covers, as small as the widget shows them (a
  /// widget has little memory). A cover that fails to load is left out.
  private static func withCovers(_ episodes: [AiringEpisode]) async -> [AiringEpisode] {
    var loaded: [AiringEpisode] = []
    for var airing in episodes {
      if let url = airing.coverURL,
         let download = try? await URLSession.shared.data(from: url),
         let image = UIImage(data: download.0) {
        airing.cover = image.preparingThumbnail(of: coverSize) ?? image
      }
      loaded.append(airing)
    }
    return loaded
  }

  private static func post<T: Decodable>(_ query: String, _ variables: [String: Any]) async throws -> T {
    var request = URLRequest(url: endpoint, timeoutInterval: 10)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let body: [String: Any] = ["query": query, "variables": variables]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (answer, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    guard let data = try JSONDecoder().decode(GraphQLResponse<T>.self, from: answer).data else {
      throw URLError(.cannotParseResponse)
    }
    return data
  }
}

// MARK: - AniList's answers

private struct GraphQLResponse<T: Decodable>: Decodable {
  let data: T?
}

private struct ListData: Decodable {
  let collection: MediaLists?

  enum CodingKeys: String, CodingKey {
    case collection = "MediaListCollection"
  }

  struct MediaLists: Decodable {
    let lists: [MediaList]?
  }

  struct MediaList: Decodable {
    let entries: [Entry]?
  }

  struct Entry: Decodable {
    let media: Media?
  }
}

private struct ScheduleData: Decodable {
  let page: Page?

  enum CodingKeys: String, CodingKey {
    case page = "Page"
  }

  struct Page: Decodable {
    let airingSchedules: [Schedule]?
  }

  struct Schedule: Decodable {
    let episode: Int
    let airingAt: Int
    let media: Media?
  }
}

private struct Media: Decodable {
  let id: Int
  let isAdult: Bool?
  let popularity: Int?
  let title: Title?
  let coverImage: Cover?
  let nextAiringEpisode: NextEpisode?

  struct Title: Decodable {
    let userPreferred: String?
  }

  struct Cover: Decodable {
    let medium: String?
  }

  struct NextEpisode: Decodable {
    let episode: Int
    let airingAt: Int
  }
}

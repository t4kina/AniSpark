import SwiftUI
import WidgetKit

struct UpNextView: View {
  @Environment(\.widgetFamily) private var family
  let entry: UpNextEntry

  var body: some View {
    switch family {
    case .systemSmall:
      SmallUpNext(entry: entry)
    case .accessoryRectangular:
      LockScreenUpNext(entry: entry)
    default:
      MediumUpNext(entry: entry)
    }
  }
}

private let widgetBackground = Color(rgb: 0x141218)

/// The next episode, over its blurred cover.
private struct SmallUpNext: View {
  let entry: UpNextEntry

  var body: some View {
    let next = entry.episodes.first
    VStack(alignment: .leading, spacing: 3) {
      Header(entry: entry, showsBrand: false)
      Spacer(minLength: 0)
      if let next {
        Text(next.title)
          .font(.system(size: 15, weight: .bold))
          .lineLimit(2)
        Text(L10n.episode(next.episode))
          .font(.system(size: 12))
          .foregroundStyle(.white.opacity(0.75))
        Countdown.text(next.airingAt)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(entry.accent)
          .lineLimit(1)
      } else {
        Message(entry: entry)
      }
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .containerBackground(for: .widget) {
      ZStack {
        widgetBackground
        if let cover = next?.cover {
          Image(uiImage: cover)
            .resizable()
            .scaledToFill()
            .blur(radius: 3)
          LinearGradient(
            colors: [.black.opacity(0.25), .black.opacity(0.85)],
            startPoint: .top,
            endPoint: .bottom
          )
        }
      }
    }
  }
}

/// Up to three episodes, soonest first.
private struct MediumUpNext: View {
  let entry: UpNextEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Header(entry: entry, showsBrand: true)
      if entry.episodes.isEmpty {
        Spacer(minLength: 0)
        Message(entry: entry)
          .frame(maxWidth: .infinity)
        Spacer(minLength: 0)
      } else {
        ForEach(Array(entry.episodes.prefix(UpNextSource.maxEpisodes))) { airing in
          EpisodeRow(airing: airing, accent: entry.accent)
        }
        Spacer(minLength: 0)
      }
    }
    .foregroundStyle(.white)
    .containerBackground(for: .widget) {
      widgetBackground
    }
  }
}

/// The next episode on the lock screen.
private struct LockScreenUpNext: View {
  let entry: UpNextEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let next = entry.episodes.first {
        Text(next.title)
          .font(.headline)
          .lineLimit(1)
        Text(L10n.episode(next.episode))
          .lineLimit(1)
        Countdown.text(next.airingAt)
          .lineLimit(1)
      } else {
        Text(entry.failed ? L10n.failed : L10n.nothing)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .containerBackground(for: .widget) {
      Color.clear
    }
  }
}

private struct Header: View {
  let entry: UpNextEntry
  let showsBrand: Bool

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(entry.accent)
        .frame(width: 7, height: 7)
      Text(entry.fromList || entry.failed ? L10n.upNext : L10n.airingSoon)
        .font(.system(size: 13, weight: .bold))
        .lineLimit(1)
      Spacer(minLength: 0)
      if showsBrand {
        Text("AniSpark")
          .font(.system(size: 10))
          .foregroundStyle(.white.opacity(0.5))
      }
    }
  }
}

private struct EpisodeRow: View {
  let airing: AiringEpisode
  let accent: Color

  var body: some View {
    HStack(spacing: 10) {
      Cover(image: airing.cover, accent: accent)
      VStack(alignment: .leading, spacing: 1) {
        Text(airing.title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        (Text(L10n.episode(airing.episode) + " · ") + Countdown.text(airing.airingAt))
          .font(.system(size: 12))
          .foregroundStyle(accent)
          .lineLimit(1)
      }
    }
  }
}

private struct Cover: View {
  let image: UIImage?
  let accent: Color

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        accent.opacity(0.25)
      }
    }
    .frame(width: 25, height: 35)
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
  }
}

private struct Message: View {
  let entry: UpNextEntry

  var body: some View {
    Text(entry.failed ? L10n.failed : L10n.nothing)
      .font(.system(size: 12))
      .foregroundStyle(.white.opacity(0.7))
  }
}

private enum Countdown {
  /// Within a day, a countdown that ticks by itself ("2 hr, 10 min");
  /// further off, the day and time.
  static func text(_ date: Date) -> Text {
    if date.timeIntervalSinceNow < 86_400 {
      return Text(date, style: .relative)
    }
    return Text(date, format: .dateTime.weekday(.abbreviated).hour().minute())
  }
}

/// The widget's few texts in the app's 8 languages, picked from the
/// device's preferred language (the Android widget's are in res/values-*).
enum L10n {
  private static let language = String((Locale.preferredLanguages.first ?? "en").prefix(2))

  private static let texts: [String: [String: String]] = [
    "upNext": [
      "en": "Up next", "es": "A continuación", "ja": "次のエピソード", "fr": "À suivre",
      "de": "Als Nächstes", "pt": "A seguir", "it": "Prossimi", "ko": "다음 에피소드",
    ],
    "airingSoon": [
      "en": "Airing soon", "es": "En emisión pronto", "ja": "まもなく放送", "fr": "Bientôt diffusé",
      "de": "Läuft bald", "pt": "Em breve", "it": "In onda a breve", "ko": "곧 방영",
    ],
    "description": [
      "en": "The next episodes airing from your list",
      "es": "Los próximos episodios de tu lista",
      "ja": "リストから次に放送されるエピソード",
      "fr": "Les prochains épisodes de votre liste",
      "de": "Die nächsten Folgen aus deiner Liste",
      "pt": "Os próximos episódios da sua lista",
      "it": "I prossimi episodi della tua lista",
      "ko": "내 목록에서 곧 방영될 에피소드",
    ],
    "nothing": [
      "en": "Nothing airing soon", "es": "Nada en emisión pronto", "ja": "まもなく放送の作品はありません",
      "fr": "Rien de diffusé prochainement", "de": "Demnächst läuft nichts", "pt": "Nada em exibição em breve",
      "it": "Niente in onda a breve", "ko": "곧 방영될 작품이 없어요",
    ],
    "failed": [
      "en": "Couldn't load", "es": "No se pudo cargar", "ja": "読み込めませんでした", "fr": "Chargement impossible",
      "de": "Laden fehlgeschlagen", "pt": "Não foi possível carregar", "it": "Impossibile caricare",
      "ko": "불러오지 못했어요",
    ],
    "episode": [
      "en": "Ep {n}", "es": "Ep {n}", "ja": "第{n}話", "fr": "Ép. {n}",
      "de": "Folge {n}", "pt": "Ep. {n}", "it": "Ep. {n}", "ko": "{n}화",
    ],
  ]

  private static func text(_ key: String) -> String {
    texts[key]?[language] ?? texts[key]?["en"] ?? key
  }

  static var upNext: String { text("upNext") }
  static var airingSoon: String { text("airingSoon") }
  static var description: String { text("description") }
  static var nothing: String { text("nothing") }
  static var failed: String { text("failed") }

  static func episode(_ number: Int) -> String {
    text("episode").replacingOccurrences(of: "{n}", with: String(number))
  }
}

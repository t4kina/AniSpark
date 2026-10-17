import AppIntents
import SwiftUI
import WidgetKit

@main
struct AniSparkWidgets: WidgetBundle {
  var body: some Widget {
    UpNextWidget()
  }
}

/// The next episodes airing from an AniList list, with a live countdown.
/// A free Apple ID can't share data between the app and a widget, so the
/// widget asks for the username and accent in its own settings (touch and
/// hold it, then Edit Widget).
struct UpNextWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: "UpNextWidget", intent: UpNextConfiguration.self, provider: UpNextProvider()) { entry in
      UpNextView(entry: entry)
    }
    .configurationDisplayName(L10n.upNext)
    .description(L10n.description)
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

struct UpNextConfiguration: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "Up next"
  static var description = IntentDescription("The next episodes airing from your AniList list.")

  @Parameter(title: "AniList username")
  var username: String?

  @Parameter(title: "Accent colour", default: .blue)
  var accent: AccentOption
}

/// The accent colours of the app's Settings (accentColorOptions in
/// settings_provider.dart), so the widget can match the app.
enum AccentOption: String, AppEnum {
  case blue, purple, green, pink, teal, orange

  static var typeDisplayRepresentation: TypeDisplayRepresentation = "Accent colour"
  static var caseDisplayRepresentations: [AccentOption: DisplayRepresentation] = [
    .blue: "Blue",
    .purple: "Purple",
    .green: "Green",
    .pink: "Pink",
    .teal: "Teal",
    .orange: "Orange",
  ]

  var color: Color {
    switch self {
    case .blue: return Color(rgb: 0x02A9FF)
    case .purple: return Color(rgb: 0x9C27B0)
    case .green: return Color(rgb: 0x4CAF50)
    case .pink: return Color(rgb: 0xE91E63)
    case .teal: return Color(rgb: 0x009688)
    case .orange: return Color(rgb: 0xFF6B35)
    }
  }
}

struct UpNextEntry: TimelineEntry {
  let date: Date
  let fromList: Bool
  let episodes: [AiringEpisode]
  let failed: Bool
  let accent: Color

  /// Shown in the widget gallery and while the first answer loads.
  static func sample(accent: Color) -> UpNextEntry {
    let now = Date()
    let titles = ["Frieren", "Dandadan", "The Apothecary Diaries"]
    let episodes = titles.enumerated().map { (index, title) in
      AiringEpisode(
        id: index,
        title: title,
        episode: 5 + index,
        airingAt: now.addingTimeInterval(TimeInterval(3_600 * (2 + 5 * index))),
        coverURL: nil
      )
    }
    return UpNextEntry(date: now, fromList: true, episodes: episodes, failed: false, accent: accent)
  }
}

struct UpNextProvider: AppIntentTimelineProvider {
  private static let maxWait: TimeInterval = 3_600

  func placeholder(in context: Context) -> UpNextEntry {
    .sample(accent: AccentOption.blue.color)
  }

  func snapshot(for configuration: UpNextConfiguration, in context: Context) async -> UpNextEntry {
    if context.isPreview { return .sample(accent: configuration.accent.color) }
    return await load(configuration)
  }

  func timeline(for configuration: UpNextConfiguration, in context: Context) async -> Timeline<UpNextEntry> {
    let entry = await load(configuration)
    // Again just after the first episode airs, and at least hourly.
    let hourLater = Date().addingTimeInterval(Self.maxWait)
    let afterFirst = entry.episodes.first?.airingAt.addingTimeInterval(60) ?? hourLater
    return Timeline(entries: [entry], policy: .after(min(afterFirst, hourLater)))
  }

  private func load(_ configuration: UpNextConfiguration) async -> UpNextEntry {
    let accent = configuration.accent.color
    do {
      let result = try await UpNextSource.fetch(username: configuration.username)
      return UpNextEntry(date: Date(), fromList: result.fromList, episodes: result.episodes, failed: false, accent: accent)
    } catch {
      return UpNextEntry(date: Date(), fromList: false, episodes: [], failed: true, accent: accent)
    }
  }
}

extension Color {
  init(rgb: UInt32) {
    self.init(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255
    )
  }
}

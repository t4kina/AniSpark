import WidgetKit
import SwiftUI

// MARK: - Data

struct WidgetData {
    var watchingCount: Int
    var completedCount: Int
    var airingToday: String?

    static let placeholder = WidgetData(watchingCount: 12, completedCount: 84, airingToday: "Demon Slayer - Ep 5")
    static let empty       = WidgetData(watchingCount: 0,  completedCount: 0,  airingToday: nil)

    static func fromDefaults() -> WidgetData {
        let defaults = UserDefaults(suiteName: "group.com.example.anispark")
        let watching  = defaults?.integer(forKey: "widget_watching_count")  ?? 0
        let completed = defaults?.integer(forKey: "widget_completed_count") ?? 0
        let airing    = defaults?.string(forKey:  "widget_airing_today")
        return WidgetData(watchingCount: watching, completedCount: completed, airingToday: airing)
    }
}

// MARK: - Timeline

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date(), data: context.isPreview ? .placeholder : .fromDefaults()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date(), data: .fromDefaults())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - View

struct AniSparkWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.10, blue: 0.18)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 5) {
                    Image("AppIcon")
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("AniSpark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.67, green: 0.67, blue: 0.8))
                }

                Divider()
                    .background(Color(red: 0.16, green: 0.16, blue: 0.29))
                    .padding(.vertical, 7)

                // Watching
                Text("Watching: \(entry.data.watchingCount)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                // Completed
                Text("\(entry.data.completedCount) completed")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.6))
                    .padding(.top, 2)

                // Airing today
                if let airing = entry.data.airingToday, !airing.isEmpty {
                    Text(airing)
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.008, green: 0.663, blue: 1.0))
                        .lineLimit(2)
                        .padding(.top, 7)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
    }
}

// MARK: - Widget

@main
struct AniSparkWidget: Widget {
    let kind: String = "AniSparkWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AniSparkWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AniSpark")
        .description("Your watching stats at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

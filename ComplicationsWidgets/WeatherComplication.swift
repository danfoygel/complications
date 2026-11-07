import SwiftUI
import WidgetKit

/// Current temperature and the next high or low.
struct WeatherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.weather.widgetKind, provider: WeatherProvider()) { entry in
            WeatherComplicationView(entry: entry)
                .environment(\.complicationAccent, AccentColor.current.color)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.weather.url)
        }
        .configurationDisplayName("Temperature")
        .description("Current temperature and the next high or low.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct WeatherTimelineEntry: TimelineEntry {
    var date: Date
    /// `nil` when there is no location or forecast to show.
    var weather: WeatherEntry?
    /// Whether a location was found, so an empty entry can say which of the two is missing.
    var hasLocation = true
}

/// Reloads every hour (the system may stretch that) and fills the gap with the hourly forecast. The forecast is the
/// one `WeatherSnapshot` shares with Up Next, so a reload often fetches nothing. When a fetch fails, the last good
/// one is shown instead, while it's under `WeatherForecast.horizon` old and from about the same place; the timeline
/// ends with the no-data icon at that age.
struct WeatherProvider: TimelineProvider {
    func placeholder(in _: Context) -> WeatherTimelineEntry {
        WeatherTimelineEntry(date: .now, weather: WeatherEntry.samples[0])
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WeatherTimelineEntry) -> Void) {
        let cached = WeatherSnapshot.fallback(for: .saved(), maxAge: WeatherForecast.horizon)
            .flatMap { WeatherForecast.entries(from: $0).first }
        completion(
            cached.map { WeatherTimelineEntry(date: .now, weather: $0) }
                ?? (context.isPreview ? placeholder(in: context) : WeatherTimelineEntry(date: .now, weather: nil))
        )
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<WeatherTimelineEntry>) -> Void) {
        Task {
            let now = Date.now
            let location = PhoneLocation.saved()
            var snapshot: WeatherSnapshot?
            if let location {
                snapshot = await (try? WeatherSnapshot.latest(for: location, now: now))
                    ?? WeatherSnapshot.fallback(for: location, maxAge: WeatherForecast.horizon, now: now)
            }
            let forecast = snapshot.map { WeatherForecast.entries(from: $0, now: now) } ?? []
            guard let snapshot, !forecast.isEmpty else {
                completion(Timeline(
                    entries: [WeatherTimelineEntry(date: now, weather: nil, hasLocation: location != nil)],
                    policy: .after(now.addingTimeInterval(15 * 60))
                ))
                return
            }
            // `horizon` after the fetch the no-data icon takes over, in case the system puts off the next reload that
            // long: past its last entry the face would keep showing that hour's temperature.
            let expiry = snapshot.date.addingTimeInterval(WeatherForecast.horizon)
            let entries = forecast.filter { $0.date < expiry }.map {
                WeatherTimelineEntry(date: max($0.date, now), weather: $0)
            } + [WeatherTimelineEntry(date: expiry, weather: nil)]
            completion(Timeline(entries: entries, policy: .after(min(now.addingTimeInterval(60 * 60), expiry))))
        }
    }
}

struct WeatherComplicationView: View {
    let entry: WeatherTimelineEntry

    var body: some View {
        if let weather = entry.weather {
            TemperatureView(weather: weather)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.hasLocation ? "icloud.slash" : "location.slash")
                    .font(.system(size: 19, weight: .semibold))
            }
        }
    }
}

#Preview(as: .accessoryCircular) {
    WeatherComplication()
} timeline: {
    WeatherTimelineEntry(date: .now, weather: WeatherEntry.samples[0])
    WeatherTimelineEntry(date: .now, weather: WeatherEntry.samples[1])
    WeatherTimelineEntry(date: .now, weather: WeatherEntry.samples[2])
    WeatherTimelineEntry(date: .now, weather: WeatherEntry.samples[3])
    WeatherTimelineEntry(date: .now, weather: nil)
    WeatherTimelineEntry(date: .now, weather: nil, hasLocation: false)
}

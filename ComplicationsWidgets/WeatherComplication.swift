import SwiftUI
import WidgetKit

/// Current temperature and the next high or low.
struct WeatherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.weather.widgetKind, provider: WeatherProvider()) { entry in
            WeatherComplicationView(entry: entry)
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
/// one is shown instead, while it's under `WeatherForecast.horizon` old and from about the same place.
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
            var forecast: [WeatherEntry] = []
            let location = PhoneLocation.saved()
            if let location,
               let snapshot = await (try? WeatherSnapshot.latest(for: location, now: now))
               ?? WeatherSnapshot.fallback(for: location, maxAge: WeatherForecast.horizon, now: now) {
                forecast = WeatherForecast.entries(from: snapshot, now: now)
            }
            let entries = forecast.isEmpty
                ? [WeatherTimelineEntry(date: now, weather: nil, hasLocation: location != nil)]
                : forecast.map { WeatherTimelineEntry(date: max($0.date, now), weather: $0) }
            let retry: TimeInterval = forecast.isEmpty ? 15 * 60 : 60 * 60
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(retry))))
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

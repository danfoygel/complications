import SwiftUI
import WidgetKit

/// Current temperature on a ring that runs from the day's low to its high, with the condition symbol below.
struct WeatherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.weather.widgetKind, provider: WeatherProvider()) { entry in
            WeatherComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.weather.url)
        }
        .configurationDisplayName("Temperature")
        .description("Current temperature within today's low and high.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct WeatherTimelineEntry: TimelineEntry {
    var date: Date
    /// `nil` when there is no location or forecast to show.
    var weather: WeatherEntry?
}

/// Fetches every 30 minutes (the system may stretch that) and fills the gap with the hourly forecast.
/// When a fetch fails, the forecast from the last good one is shown instead.
struct WeatherProvider: TimelineProvider {
    func placeholder(in _: Context) -> WeatherTimelineEntry {
        WeatherTimelineEntry(date: .now, weather: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (WeatherTimelineEntry) -> Void) {
        let cached = WeatherForecast.cached(after: .now).first
        completion(
            cached.map { WeatherTimelineEntry(date: .now, weather: $0) }
                ?? (context.isPreview ? placeholder(in: context) : WeatherTimelineEntry(date: .now, weather: nil))
        )
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<WeatherTimelineEntry>) -> Void) {
        Task {
            let now = Date.now
            var forecast: [WeatherEntry] = []
            if let location = await Location.current() {
                do {
                    forecast = try await WeatherForecast.entries(for: location, now: now)
                    WeatherForecast.save(forecast)
                } catch {
                    forecast = WeatherForecast.cached(after: now)
                }
            }
            let entries = forecast.isEmpty
                ? [WeatherTimelineEntry(date: now, weather: nil)]
                : forecast.map { WeatherTimelineEntry(date: max($0.date, now), weather: $0) }
            let retry: TimeInterval = forecast.isEmpty ? 15 * 60 : 30 * 60
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(retry))))
        }
    }
}

struct WeatherComplicationView: View {
    let entry: WeatherTimelineEntry

    var body: some View {
        if let weather = entry.weather {
            Gauge(value: weather.temperature, in: weather.low ... max(weather.high, weather.low + 1)) {
                Image(systemName: weather.symbolName)
            } currentValueLabel: {
                Text(Temperature.text(weather.temperature))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "location.slash")
                    .font(.title3)
            }
        }
    }
}

extension WeatherEntry {
    static let sample = WeatherEntry(
        date: .now,
        temperature: 18,
        low: 11,
        high: 22,
        symbolName: "cloud.sun",
        condition: "Partly Cloudy"
    )
}

#Preview(as: .accessoryCircular) {
    WeatherComplication()
} timeline: {
    WeatherTimelineEntry(date: .now, weather: .sample)
    WeatherTimelineEntry(date: .now, weather: nil)
}

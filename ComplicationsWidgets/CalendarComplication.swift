import SwiftUI
import WidgetKit

/// The next two events, one per line, over a weather line: with rain or snow ahead, the 24-hour total and when it
/// starts or stops; otherwise the next sunrise or sunset and the air quality.
/// One that's on now or starts within the hour leads, large and in its calendar's color. With no forecast, a third
/// event takes the weather line's place. Text sizes are fixed points for the 41mm watch rather than text styles, so
/// they don't follow the watch's Text Size setting.
struct CalendarComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.calendar.widgetKind, provider: CalendarProvider()) { entry in
            CalendarComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.calendar.url)
        }
        .configurationDisplayName("Up Next")
        .description("Your next calendar events, then rain or snow, or sunrise or sunset and air quality.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct CalendarEntry: TimelineEntry {
    var date: Date
    var upNext: CalendarEvents.UpNext
    var isAuthorized: Bool
    var weather: WeatherLine?

    init(date: Date, events: [CalendarEvent], isAuthorized: Bool, forecast: PrecipitationForecast? = nil) {
        self.date = date
        self.isAuthorized = isAuthorized
        weather = forecast.flatMap { WeatherLine(at: date, forecast: $0) }
        upNext = CalendarEvents.upNext(at: date, in: events, lines: weather == nil ? 3 : 2)
    }
}

/// An entry at every start and end in the next week, an hour before each start, and at each midnight, so the
/// complication moves on as events come within the lead window, begin, and finish, and as days change. For the
/// weather line, also one at each sunrise and sunset, each hour of air quality, and wherever the rain or snow reads
/// differently in the next 12 hours (`WeatherLine.changes`).
struct CalendarProvider: TimelineProvider {
    /// How far ahead the timeline goes. A reload normally comes every 30 minutes, but the system rations them and can
    /// go a day or more without one; past its last entry the complication would stay on that entry, showing events
    /// that have ended. A week of entries keeps it right until the next reload comes.
    static let horizon: TimeInterval = 7 * 24 * 60 * 60

    func placeholder(in _: Context) -> CalendarEntry {
        CalendarEntry(date: .now, events: CalendarEvent.samples, isAuthorized: true, forecast: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (CalendarEntry) -> Void) {
        let now = Date.now
        let events = CalendarEvents.events(from: now, to: now.addingTimeInterval(24 * 60 * 60))
        completion(
            context.isPreview && events.isEmpty
                ? placeholder(in: context)
                : CalendarEntry(
                    date: now, events: events, isAuthorized: CalendarEvents.isAuthorized,
                    forecast: WeatherSnapshot.cached().map {
                        var forecast = PrecipitationForecast($0)
                        forecast.airQuality = AirQuality.cached()
                        return forecast
                    }
                )
        )
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<CalendarEntry>) -> Void) {
        Task {
            let now = Date.now
            let horizon = now.addingTimeInterval(Self.horizon)
            let forecast = await Self.forecast()
            // Look past the horizon so an entry near its end can still find the event after.
            let events = CalendarEvents.events(from: now, to: horizon.addingTimeInterval(24 * 60 * 60))
            // A later day's events show their weekday, so each midnight changes what's shown.
            let today = Calendar.current.startOfDay(for: now)
            let midnights = (1 ... 8).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
            let eventChanges = events.flatMap {
                [$0.start.addingTimeInterval(-CalendarEvents.leadWindow), $0.start, $0.end]
            }
            let weatherChanges = forecast.map { WeatherLine.changes(after: now, forecast: $0) } ?? []
            let changes = Set(eventChanges + midnights + weatherChanges)
                .filter { $0 > now && $0 <= horizon }
            let entries = ([now] + changes.sorted()).map {
                CalendarEntry(date: $0, events: events, isAuthorized: CalendarEvents.isAuthorized, forecast: forecast)
            }
            // Reload now and then to pick up events added or changed since, and a fresh forecast.
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }

    /// The forecast `WeatherSnapshot` shares with the weather complication (fetched only when it's old), else the
    /// last one saved, with the air quality (also fetched only when it's old).
    private static func forecast() async -> PrecipitationForecast? {
        var snapshot: WeatherSnapshot?
        var airQuality = AirQuality.cached()
        if let location = PhoneLocation.saved() {
            async let latestAirQuality = AirQuality.latest(for: location)
            snapshot = try? await WeatherSnapshot.latest(for: location)
            airQuality = await latestAirQuality
        }
        return (snapshot ?? WeatherSnapshot.cached()).map {
            var forecast = PrecipitationForecast($0)
            forecast.airQuality = airQuality
            return forecast
        }
    }
}

struct CalendarComplicationView: View {
    let entry: CalendarEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            events
            if let weather = entry.weather {
                // At the bottom of the slot, so any spare height falls between the events and the weather.
                Spacer(minLength: 0)
                WeatherLineView(line: weather)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var events: some View {
        let upNext = entry.upNext
        if upNext.lead != nil || !upNext.rest.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                if let lead = upNext.lead {
                    leadRow(lead)
                }
                // Each title starts right after its own label rather than in a column, so it gets all the width
                // that row's label leaves.
                ForEach(upNext.rest) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(label(event))
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        FittedText(event.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(upNext.lead == nil ? .primary : .secondary)
                    }
                }
            }
            .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Calendar", systemImage: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                Text(entry.isAuthorized ? "No more events" : "Open to allow access")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(entry.weather == nil ? 2 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func leadRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(Color(event.color))
                .frame(width: 4, height: 18)
                .widgetAccentable()
            FittedText(event.title)
                .font(.system(size: 16, weight: .semibold))
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(event.start <= entry.date ? "until \(clock(event.end))" : clock(event.start))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
    }

    /// "Now", or when it starts.
    private func label(_ event: CalendarEvent) -> String {
        event.start <= entry.date ? "Now" : clock(event.start)
    }

    /// "11:30" today, with the weekday later this week ("Sa 1pm", "Sa 1:30pm", "Sa 13:30"), or just the date a week
    /// or more away ("Nov 6"), where a weekday would read as this one.
    private func clock(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: entry.date), to: calendar.startOfDay(for: date)
        ).day ?? 0
        if days == 0 {
            return ClockTime.string(date)
        }
        if days >= 7 {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        let formatter = DateFormatter()
        if ClockTime.format.contains("h") {
            // Without the space before AM/PM, and without ":00", to fit beside the title.
            let onTheHour = calendar.component(.minute, from: date) == 0
            // The two-letter weekday ("EEEEEE") for the same reason.
            formatter.dateFormat = onTheHour ? "EEEEEE ha" : "EEEEEE h:mma"
            formatter.amSymbol = "am"
            formatter.pmSymbol = "pm"
        } else {
            formatter.dateFormat = "EEEEEE " + ClockTime.format
        }
        return formatter.string(from: date)
    }
}

/// One line of text cut off at the last whole character that fits, with no "…": on a complication that space is better
/// spent on another character or two.
struct FittedText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // ViewThatFits shows the first that fits the width, so the longest prefix; the last, an empty one, always does.
        ViewThatFits(in: .horizontal) {
            ForEach(Self.prefixes(of: text), id: \.self) { prefix in
                Text(prefix).lineLimit(1)
            }
        }
    }

    /// Every prefix, longest first, without trailing spaces and so without repeats.
    static func prefixes(of text: String) -> [String] {
        var prefixes: [String] = []
        for length in stride(from: text.count, through: 0, by: -1) {
            let prefix = String(text.prefix(length).trimmingCharacters(in: .whitespaces))
            if prefix != prefixes.last {
                prefixes.append(prefix)
            }
        }
        return prefixes
    }
}

extension CalendarEvent {
    static let samples = [
        sample(id: "standup", "Standup", minutes: -5, length: 15, color: RGB(red: 0.04, green: 0.52, blue: 1)),
        sample(
            id: "review", "Design review with platform team", minutes: 85, length: 30,
            color: RGB(red: 0.75, green: 0.35, blue: 0.95)
        ),
        sample(id: "lunch", "Lunch with Sam", minutes: 145, length: 60, color: RGB(red: 0.19, green: 0.82, blue: 0.35)),
        sample(id: "priya", "1:1 with Priya", minutes: 235, length: 30, color: RGB(red: 0.75, green: 0.35, blue: 0.95)),
    ]

    /// The samples two days later, so they show their weekday.
    static let laterSamples = samples.map {
        var event = $0
        event.start.addTimeInterval(2 * 24 * 60 * 60)
        event.end.addTimeInterval(2 * 24 * 60 * 60)
        return event
    }

    private static func sample(id: String, _ title: String, minutes: Double, length: Double, color: RGB) -> Self {
        CalendarEvent(
            id: id,
            title: title,
            start: .now.addingTimeInterval(minutes * 60),
            end: .now.addingTimeInterval((minutes + length) * 60),
            isAllDay: false,
            location: nil,
            color: color
        )
    }
}

#Preview(as: .accessoryRectangular) {
    CalendarComplication()
} timeline: {
    // Standup on now, over the weather line.
    CalendarEntry(date: .now, events: CalendarEvent.samples, isAuthorized: true, forecast: .sample)
    CalendarEntry(date: .now, events: CalendarEvent.samples, isAuthorized: true)
    // Standup over and the review over an hour away: no lead.
    CalendarEntry(date: .now.addingTimeInterval(20 * 60), events: CalendarEvent.samples, isAuthorized: true)
    // Review starts within the hour.
    CalendarEntry(date: .now.addingTimeInterval(40 * 60), events: CalendarEvent.samples, isAuthorized: true)
    // Later this week: each title right after its weekday, cut off without "…".
    CalendarEntry(date: .now, events: CalendarEvent.laterSamples, isAuthorized: true, forecast: .sample)
    CalendarEntry(date: .now, events: [], isAuthorized: true)
    CalendarEntry(date: .now, events: [], isAuthorized: false)
}

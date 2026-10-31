import SwiftUI
import WidgetKit

/// The next two events, one per line, over a weather line: the next sunrise or sunset and the nearest rain or snow.
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
        .description("Your next calendar events, sunrise or sunset, and rain or snow.")
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
/// weather line, also one every 5 minutes for 12 hours and one at each sunrise and sunset.
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
                    forecast: PrecipitationForecast.cached()
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
            let changes = Set(eventChanges + midnights + Self.weatherChanges(after: now, forecast: forecast))
                .filter { $0 > now && $0 <= horizon }
            let entries = ([now] + changes.sorted()).map {
                CalendarEntry(date: $0, events: events, isAuthorized: CalendarEvents.isAuthorized, forecast: forecast)
            }
            // Reload now and then to pick up events added or changed since, and a fresh forecast.
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }

    /// A fresh forecast, saved for next time, else the last one saved.
    private static func forecast() async -> PrecipitationForecast? {
        if let location = await Location.current(),
           let forecast = try? await PrecipitationForecast.fetch(for: location) {
            forecast.save()
            return forecast
        }
        return PrecipitationForecast.cached()
    }

    /// Every 5-minute mark for 12 hours, so "in 30m" counts down, and each sunrise and sunset.
    private static func weatherChanges(after now: Date, forecast: PrecipitationForecast?) -> [Date] {
        guard let forecast else { return [] }
        let step: TimeInterval = 5 * 60
        let firstMark = (now.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        let marks = (0 ..< Int(WeatherForecast.precipitationWindow / step)).map {
            Date(timeIntervalSinceReferenceDate: firstMark + Double($0) * step)
        }
        return marks + forecast.days.flatMap { [$0.sunrise, $0.sunset].compactMap(\.self) }
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
                Grid(alignment: .leading, horizontalSpacing: 5, verticalSpacing: 1) {
                    ForEach(upNext.rest) { event in
                        GridRow {
                            Text(label(event))
                                .font(.system(size: 13, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(event.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(upNext.lead == nil ? .primary : .secondary)
                        }
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
            Text(event.title)
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

    /// "11:30" today, with the weekday later this week ("Sat 1pm", "Sat 1:30pm", "Sat 13:30"), or just the date a week
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
            formatter.dateFormat = onTheHour ? "EEE ha" : "EEE h:mma"
            formatter.amSymbol = "am"
            formatter.pmSymbol = "pm"
        } else {
            formatter.dateFormat = "EEE " + ClockTime.format
        }
        return formatter.string(from: date)
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
    CalendarEntry(date: .now, events: [], isAuthorized: true)
    CalendarEntry(date: .now, events: [], isAuthorized: false)
}

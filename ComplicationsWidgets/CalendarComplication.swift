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
/// weather line, also wherever it reads differently: at a sunrise or sunset, an hour of air quality, or a change in
/// the rain or snow in the next 24 hours (`WeatherLine.changes`).
struct CalendarProvider: TimelineProvider {
    /// How far ahead the timeline goes. A reload normally comes every 30 minutes, but the system rations them and can
    /// go a day or more without one; past its last entry the complication would stay on that entry, showing events
    /// that have ended. A week of entries keeps it right until the next reload comes.
    static let horizon: TimeInterval = 7 * 24 * 60 * 60

    /// How old a saved forecast can be and still stand in when a fetch fails. Past a day, its rain no longer covers
    /// the line's 24 hours, and a third event is more use than sunrise times from an old forecast.
    static let fallbackAge: TimeInterval = 24 * 60 * 60

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
                    forecast: WeatherSnapshot.fallback(for: .saved(), maxAge: Self.fallbackAge).map {
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
            // Only events the complication can show; an all-day one's start and end would be entries that look just
            // like the one before.
            let eventChanges = events.filter(\.isShown).flatMap {
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
    /// last one saved for about the same place within `fallbackAge`, with the air quality (also fetched only when
    /// it's old). Both fetches have time limits, so the events aren't held up for long by a poor connection.
    private static func forecast() async -> PrecipitationForecast? {
        guard let location = PhoneLocation.saved(),
              let snapshot = await (try? WeatherSnapshot.latest(for: location))
              ?? WeatherSnapshot.fallback(for: location, maxAge: fallbackAge) else { return nil }
        var forecast = PrecipitationForecast(snapshot)
        // After the weather rather than alongside it, so there's no fetch for air quality the line won't show: none
        // without a forecast, and none when rain or snow is on every hour of the next day.
        if needsAirQuality(forecast) {
            forecast.airQuality = await AirQuality.latest(for: location)
        }
        return forecast
    }

    /// Whether the line shows the air quality at some hour of the next day (it does when there's no rain or snow to
    /// tell of).
    private static func needsAirQuality(_ forecast: PrecipitationForecast, now: Date = .now) -> Bool {
        (0 ..< 24).contains { hour in
            WeatherLine(at: now.addingTimeInterval(Double(hour) * 60 * 60), forecast: forecast)?.outlook == nil
        }
    }
}

struct CalendarComplicationView: View {
    let entry: CalendarEntry

    var body: some View {
        // The width to fit titles to; see FittedText.
        GeometryReader { geometry in
            content(width: geometry.size.width)
        }
    }

    private func content(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            events(width: width)
            if let weather = entry.weather {
                // At the bottom of the slot, so any spare height falls between the events and the weather.
                Spacer(minLength: 0)
                WeatherLineView(line: weather)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func events(width: CGFloat) -> some View {
        let upNext = entry.upNext
        if upNext.lead != nil || !upNext.rest.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                if let lead = upNext.lead {
                    leadRow(lead, width: width)
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
                        FittedText(
                            event.title, size: 16, weight: .medium,
                            width: width - labelWidth(label(event)) - 5
                        )
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

    private func leadRow(_ event: CalendarEvent, width: CGFloat) -> some View {
        let time = event.start <= entry.date ? "until \(clock(event.end))" : clock(event.start)
        return HStack(spacing: 5) {
            Capsule()
                .fill(Color(event.color))
                .frame(width: 4, height: 18)
                .widgetAccentable()
            FittedText(
                event.title, size: 16, weight: .semibold,
                width: width - 4 - 5 - 5 - labelWidth(time)
            )
            .widgetAccentable()
            Spacer(minLength: 0)
            Text(time)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
    }

    /// The width of a time label, in its 13-point semibold with monospaced digits. Taken at Core Text's full measure:
    /// `FittedText.drawnScale` was measured on the titles, and the label, which never shrinks, taking more room than
    /// estimated would leave the title too little and get it cut off with "…". Too much costs a character at most.
    private func labelWidth(_ text: String) -> CGFloat {
        FittedText.width(of: text, size: 13, weight: .semibold, monospacedDigits: true, drawnScale: 1)
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
        let format = ClockTime.format
        if format.contains("h") {
            // Without the space before AM/PM, and without ":00", to fit beside the title.
            let onTheHour = calendar.component(.minute, from: date) == 0
            // The two-letter weekday ("EEEEEE") for the same reason.
            return ClockTime.string(
                date, format: onTheHour ? "EEEEEE ha" : "EEEEEE h:mma", amSymbol: "am", pmSymbol: "pm"
            )
        }
        return ClockTime.string(date, format: "EEEEEE " + format)
    }
}

/// One line of text cut off at the last whole character that fits, with no "…": on a complication that space is better
/// spent on another character or two.
///
/// The fit is measured here with Core Text rather than left to SwiftUI layout. The watch face draws a complication's
/// text itself, and with `ViewThatFits` choosing among the prefixes it still drew titles too long for their row and
/// cut them off with "…".
struct FittedText: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let width: CGFloat

    init(_ text: String, size: CGFloat, weight: Font.Weight, width: CGFloat) {
        self.text = text
        self.size = size
        self.weight = weight
        self.width = width
    }

    var body: some View {
        Text(Self.longestPrefix(of: text, size: size, weight: weight, fitting: width))
            .font(.system(size: size, weight: weight))
            .lineLimit(1)
    }

    /// How wide the face draws text compared with Core Text's measure of the same font: measured on the Series 8 as
    /// 0.94–0.946 for the titles, which matches SF Compact Display against SF Compact Text on the Mac.
    static let drawnScale: CGFloat = 0.94

    /// A little room to spare, for the spread in `drawnScale`.
    private static let slack: CGFloat = 1

    /// The longest prefix, without trailing spaces, that fits the width.
    static func longestPrefix(of text: String, size: CGFloat, weight: Font.Weight, fitting width: CGFloat) -> String {
        let prefixes = prefixes(of: text)
        // Prefixes only get narrower, and the last, an empty one, always fits.
        var low = 0
        var high = prefixes.count - 1
        while low < high {
            let middle = (low + high) / 2
            if Self.width(of: prefixes[middle], size: size, weight: weight) <= width - slack {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return prefixes[low]
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

    /// The width the face draws one line of text at in the system font, optionally with monospaced digits as the labels
    /// use.
    static func width(
        of text: String, size: CGFloat, weight: Font.Weight, monospacedDigits: Bool = false,
        drawnScale: CGFloat = drawnScale
    ) -> CGFloat {
        let font = monospacedDigits
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: uiWeight(weight))
            : UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return CTLineGetTypographicBounds(line, nil, nil, nil) * drawnScale
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .semibold: .semibold
        case .medium: .medium
        case .bold: .bold
        default: .regular
        }
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

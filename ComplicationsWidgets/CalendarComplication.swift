import SwiftUI
import WidgetKit

/// The next three events, one per line. One that's on now or starts within the hour leads, large and in its
/// calendar's color.
struct CalendarComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.calendar.widgetKind, provider: CalendarProvider()) { entry in
            CalendarComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.calendar.url)
        }
        .configurationDisplayName("Up Next")
        .description("Your next three calendar events.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct CalendarEntry: TimelineEntry {
    var date: Date
    var upNext: CalendarEvents.UpNext
    var isAuthorized: Bool

    init(date: Date, events: [CalendarEvent], isAuthorized: Bool) {
        self.date = date
        self.isAuthorized = isAuthorized
        upNext = CalendarEvents.upNext(at: date, in: events)
    }
}

/// An entry at every start and end in the next day, and an hour before each start, so the complication moves on as
/// events come within the lead window, begin, and finish.
struct CalendarProvider: TimelineProvider {
    func placeholder(in _: Context) -> CalendarEntry {
        CalendarEntry(date: .now, events: CalendarEvent.samples, isAuthorized: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (CalendarEntry) -> Void) {
        let now = Date.now
        let events = CalendarEvents.events(from: now, to: now.addingTimeInterval(24 * 60 * 60))
        completion(
            context.isPreview && events.isEmpty
                ? placeholder(in: context)
                : CalendarEntry(date: now, events: events, isAuthorized: CalendarEvents.isAuthorized)
        )
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<CalendarEntry>) -> Void) {
        let now = Date.now
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        // Look past the horizon so an entry near its end can still find the event after.
        let events = CalendarEvents.events(from: now, to: horizon.addingTimeInterval(24 * 60 * 60))
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
        let changes = Set(events.flatMap { [$0.start.addingTimeInterval(-CalendarEvents.leadWindow), $0.start, $0.end] }
            + [midnight]).filter { $0 > now && $0 <= horizon }
        let entries = ([now] + changes.sorted()).map {
            CalendarEntry(date: $0, events: events, isAuthorized: CalendarEvents.isAuthorized)
        }
        // Reload now and then to pick up events added or changed since.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct CalendarComplicationView: View {
    let entry: CalendarEntry

    var body: some View {
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
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(event.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(upNext.lead == nil ? .primary : .secondary)
                        }
                    }
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("Calendar", systemImage: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .widgetAccentable()
                Text(entry.isAuthorized ? "No more events" : "Open to allow access")
                    .font(.headline)
                    .lineLimit(2)
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
                .font(.headline)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(event.start <= entry.date ? "until \(time(event.end))" : time(event.start))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
    }

    /// "11:30", "Now", or the weekday for a later day.
    private func label(_ event: CalendarEvent) -> String {
        if event.start <= entry.date {
            return "Now"
        }
        if Calendar.current.isDate(event.start, inSameDayAs: entry.date) {
            return time(event.start)
        }
        return event.start.formatted(.dateTime.weekday())
    }

    /// The locale's time format without AM/PM, which takes too much width: "9:05", or "09:05" in 24-hour locales.
    /// (`.hour(.defaultDigits(amPM: .omitted))` gives "09:05" in en_US.)
    private static let timeFormat =
        (DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "j:mm")
            .replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces)

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Self.timeFormat
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
    // Standup on now.
    CalendarEntry(date: .now, events: CalendarEvent.samples, isAuthorized: true)
    // Standup over and the review over an hour away: no lead.
    CalendarEntry(date: .now.addingTimeInterval(20 * 60), events: CalendarEvent.samples, isAuthorized: true)
    // Review starts within the hour.
    CalendarEntry(date: .now.addingTimeInterval(40 * 60), events: CalendarEvent.samples, isAuthorized: true)
    CalendarEntry(date: .now, events: [], isAuthorized: true)
    CalendarEntry(date: .now, events: [], isAuthorized: false)
}

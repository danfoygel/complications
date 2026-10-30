import SwiftUI
import WidgetKit

/// The next event: its time, title, and location, with the calendar's color down the side.
struct CalendarComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.calendar.widgetKind, provider: CalendarProvider()) { entry in
            CalendarComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.calendar.url)
        }
        .configurationDisplayName("Up Next")
        .description("Your next calendar event.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct CalendarEntry: TimelineEntry {
    var date: Date
    var event: CalendarEvent?
    /// Timed events after `event` on the same day.
    var moreToday: Int
    var isAuthorized: Bool

    init(date: Date, events: [CalendarEvent], isAuthorized: Bool) {
        self.date = date
        self.isAuthorized = isAuthorized
        event = CalendarEvents.upNext(at: date, in: events)
        moreToday = event.map { shown in
            events.filter {
                !$0.isAllDay && $0.start > shown.start && Calendar.current.isDate($0.start, inSameDayAs: date)
            }.count
        } ?? 0
    }
}

/// An entry at every start and end in the next day, so the complication moves on as events begin and finish.
struct CalendarProvider: TimelineProvider {
    func placeholder(in _: Context) -> CalendarEntry {
        CalendarEntry(date: .now, events: [.sample], isAuthorized: true)
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
        let changes = Set(events.flatMap { [$0.start, $0.end] } + [midnight]).filter { $0 > now && $0 <= horizon }
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
        if let event = entry.event {
            HStack(spacing: 6) {
                Capsule()
                    .fill(Color(event.color))
                    .frame(width: 4)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text(when(event))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.headline)
                        .widgetAccentable()
                    if let detail = detail(event) {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
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

    private func when(_ event: CalendarEvent) -> String {
        if event.isAllDay {
            return "All day"
        }
        if event.start <= entry.date {
            return "Now · until \(event.end.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDate(event.start, inSameDayAs: entry.date) {
            return event.timeRange
        }
        return "Tomorrow · \(event.start.formatted(date: .omitted, time: .shortened))"
    }

    private func detail(_ event: CalendarEvent) -> String? {
        let more = entry.moreToday > 0 ? "+\(entry.moreToday) more" : nil
        return [event.location, more].compactMap(\.self).joined(separator: " · ").nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension CalendarEvent {
    static let sample = CalendarEvent(
        id: "sample",
        title: "Design review",
        start: .now.addingTimeInterval(20 * 60),
        end: .now.addingTimeInterval(50 * 60),
        isAllDay: false,
        location: "Room 4",
        color: RGB(red: 0.2, green: 0.5, blue: 1)
    )
}

#Preview(as: .accessoryRectangular) {
    CalendarComplication()
} timeline: {
    CalendarEntry(date: .now, events: [.sample], isAuthorized: true)
    CalendarEntry(date: .now.addingTimeInterval(30 * 60), events: [.sample], isAuthorized: true)
    CalendarEntry(date: .now, events: [], isAuthorized: true)
    CalendarEntry(date: .now, events: [], isAuthorized: false)
}

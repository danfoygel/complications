import CoreGraphics
import EventKit
import Foundation
import SwiftUI

/// A calendar event copied out of EventKit, so it can cross actors and live in timeline entries.
struct CalendarEvent: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    /// The calendar's color as sRGB components.
    var color: RGB

    struct RGB: Hashable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }
}

enum CalendarEvents {
    static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Asks for access the first time; afterwards returns the existing answer without prompting.
    static func requestAccess() async -> Bool {
        if isAuthorized {
            return true
        }
        return await (try? EKEventStore().requestFullAccessToEvents()) ?? false
    }

    /// Events overlapping `start..<end`, earliest first; empty without calendar access.
    static func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard isAuthorized else { return [] }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .map(CalendarEvent.init)
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// What the complication lists at a moment: one line per event.
    struct UpNext: Equatable, Sendable {
        /// The next timed event, when it's on now or starts within `leadWindow`; shown large on the first line.
        var lead: CalendarEvent?
        /// The timed events after it that haven't ended.
        var rest: [CalendarEvent]
    }

    /// How soon an event has to start to become the lead.
    static let leadWindow: TimeInterval = 60 * 60

    /// Events longer than this are effectively all-day ones (a trip, a conference), so they're left out too.
    static let longestShown: TimeInterval = 12 * 60 * 60

    /// Up to `lines` timed events to show at `date`, from `events` sorted by start. All-day events and ones longer
    /// than `longestShown` are never shown.
    static func upNext(at date: Date, in events: [CalendarEvent], lines: Int = 3) -> UpNext {
        let candidates = events.filter {
            !$0.isAllDay && $0.end.timeIntervalSince($0.start) <= longestShown && $0.end > date
        }
        // An event that overlaps a shorter one steps aside for it: a long block (a meeting-heavy day's "Dan CR")
        // would otherwise crowd out the short meetings that actually happen inside it.
        let timed = candidates.filter { event in
            !candidates.contains {
                $0.id != event.id && $0.start < event.end && event.start < $0.end && $0.duration < event.duration
            }
        }
        let lead = timed.first.flatMap { $0.start <= date.addingTimeInterval(leadWindow) ? $0 : nil }
        let rest = timed.dropFirst(lead == nil ? 0 : 1)
        return UpNext(lead: lead, rest: Array(rest.prefix(lead == nil ? lines : lines - 1)))
    }
}

extension CalendarEvent {
    init(_ event: EKEvent) {
        let srgb = event.calendar.cgColor.flatMap {
            $0.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        }
        let components = srgb?.components.flatMap { $0.count >= 3 ? $0.map(Double.init) : nil } ?? [0.5, 0.5, 0.5]
        self.init(
            id: event.calendarItemIdentifier + "@\(event.startDate.timeIntervalSinceReferenceDate)",
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location.flatMap { $0.isEmpty ? nil : $0 },
            color: RGB(red: components[0], green: components[1], blue: components[2])
        )
    }

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    /// "10:00 – 10:30 AM", or "All day".
    var timeRange: String {
        isAllDay ? "All day" : (start ..< end).formatted(.interval.hour().minute())
    }
}

extension Color {
    init(_ rgb: CalendarEvent.RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

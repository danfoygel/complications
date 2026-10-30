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

    /// The event to show at `date`: the earliest timed event that hasn't ended, else an all-day event on that day.
    static func upNext(at date: Date, in events: [CalendarEvent]) -> CalendarEvent? {
        let calendar = Calendar.current
        return events.first { !$0.isAllDay && $0.end > date }
            ?? events.first { $0.isAllDay && calendar.isDate($0.start, inSameDayAs: date) }
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

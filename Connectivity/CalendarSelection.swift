import EventKit
import Foundation

/// The calendars Up Next and the Calendar screen leave out, picked in the iPhone app. Travels alongside
/// `PhoneBatteryReading` in the same messages, under its own key; the phone keeps its pick in its own defaults and the
/// watch the latest it received in the app group. It lists the hidden calendars rather than the shown ones, so a
/// calendar added later shows until it's turned off.
struct CalendarSelection: Codable, Equatable, Sendable {
    /// When it was picked, so an older pick arriving late doesn't replace a newer one.
    var date: Date
    var hidden: [Key]

    /// A calendar as both devices can recognize it. The watch keeps its own copy of the phone's calendars, whose
    /// identifiers may not match the phone's, so the title and account are kept too.
    struct Key: Codable, Hashable, Sendable {
        var identifier: String
        var title: String
        /// The account's name ("iCloud", an email address).
        var source: String
    }

    /// Until one is picked: every calendar.
    static let all = CalendarSelection(date: .distantPast, hidden: [])

    /// Whether `calendar`, one of `calendars` on this device, is left out: it has a hidden calendar's identifier, or
    /// its title in the same account, or only its title when this device has no account of that name.
    func hides(_ calendar: Key, among calendars: [Key]) -> Bool {
        let sources = Set(calendars.map(\.source))
        return hidden.contains { key in
            key.identifier == calendar.identifier
                || key.title == calendar.title && (key.source == calendar.source || !sources.contains(key.source))
        }
    }

    var message: [String: Any] {
        (try? JSONEncoder().encode(self)).map { [Self.key: $0] } ?? [:]
    }

    init(date: Date, hidden: [Key]) {
        self.date = date
        self.hidden = hidden
    }

    init?(message: [String: Any]) {
        guard let data = message[Self.key] as? Data,
              let selection = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = selection
    }

    private static let key = "calendarSelection"

    static func saved(in defaults: UserDefaults) -> CalendarSelection? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    /// Saves this selection unless a newer pick is already saved; returns whether it did.
    @discardableResult func save(in defaults: UserDefaults) -> Bool {
        if let saved = Self.saved(in: defaults), saved.date >= date {
            return false
        }
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
        return true
    }
}

extension CalendarSelection.Key {
    init(_ calendar: EKCalendar) {
        self.init(identifier: calendar.calendarIdentifier, title: calendar.title, source: calendar.source?.title ?? "")
    }
}

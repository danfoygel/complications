import Foundation

/// The iPhone's Clock alarms that are turned on, as a Shortcuts automation last read them: iOS gives apps no way to
/// read them, but Shortcuts' Find Alarms can, and hands each to the iPhone app's Prepare Alarm for Watch and then Send
/// Alarms to Watch. Travels alongside `PhoneBatteryReading` in the same messages, under its own key; the phone keeps
/// the latest in its own defaults and the watch the latest it received in the app group.
struct PhoneAlarms: Codable, Equatable, Sendable {
    /// When they were read. A one-time alarm rings at its next time after this, and then turns itself off.
    var date: Date
    var alarms: [Alarm]

    struct Alarm: Codable, Hashable, Sendable {
        /// 0–23, on the phone's wall clock.
        var hour: Int
        var minute: Int
        /// The `Calendar` weekdays it repeats on, 1 (Sunday) to 7; empty for a one-time alarm.
        var weekdays: [Int]
        /// `nil` when it has none (the Clock app shows "Alarm").
        var label: String?

        var isRepeating: Bool {
            !weekdays.isEmpty
        }
    }

    /// When each alarm rings in `start..<end`, earliest first. A one-time alarm rings once, at its first time after
    /// `date`; a repeating one on each of its weekdays.
    func rings(from start: Date, to end: Date, calendar: Calendar = .current) -> [(alarm: Alarm, date: Date)] {
        let window = start ..< end
        return alarms.flatMap { alarm in
            ringDates(of: alarm, from: start, to: end, calendar: calendar)
                .filter(window.contains)
                .map { (alarm: alarm, date: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    /// A one-time alarm's next time after `date`; a repeating one's times on its weekdays, from the start of `start`'s
    /// day until `end`.
    private func ringDates(of alarm: Alarm, from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        guard alarm.isRepeating else {
            let time = DateComponents(hour: alarm.hour, minute: alarm.minute)
            return calendar.nextDate(after: date, matching: time, matchingPolicy: .nextTime).map { [$0] } ?? []
        }
        var dates: [Date] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            let ring = calendar.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: day)
            if let ring, alarm.weekdays.contains(calendar.component(.weekday, from: day)) {
                dates.append(ring)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }

    /// The weekdays in Shortcuts' Repeat Days, however they come through as text: one day per string or several in
    /// one, by full or short name in English or the phone's language, or as "Weekdays", "Weekends" or "Every Day".
    static func weekdays(from text: [String], calendar: Calendar = .current) -> [Int] {
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US_POSIX")
        let symbolLists = [
            english.weekdaySymbols, english.shortWeekdaySymbols, calendar.weekdaySymbols, calendar.shortWeekdaySymbols,
        ]
        var names: [String: Int] = [:]
        for symbols in symbolLists {
            for (index, name) in symbols.enumerated() {
                names[name.lowercased().trimmingCharacters(in: .punctuationCharacters)] = index + 1
            }
        }
        var weekdays = Set<Int>()
        for string in text {
            let words = string.lowercased().split { !$0.isLetter }.map(String.init)
            for (index, word) in words.enumerated() {
                switch word {
                case "weekdays", "weekday": weekdays.formUnion(2 ... 6)
                case "weekends", "weekend": weekdays.formUnion([1, 7])
                case "daily", "everyday": weekdays.formUnion(1 ... 7)
                case "day" where index > 0 && words[index - 1] == "every": weekdays.formUnion(1 ... 7)
                default:
                    if let weekday = names[word] {
                        weekdays.insert(weekday)
                    }
                }
            }
        }
        return weekdays.sorted()
    }

    var message: [String: Any] {
        (try? JSONEncoder().encode(self)).map { [Self.key: $0] } ?? [:]
    }

    init(date: Date, alarms: [Alarm]) {
        self.date = date
        self.alarms = alarms
    }

    init?(message: [String: Any]) {
        guard let data = message[Self.key] as? Data,
              let alarms = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = alarms
    }

    private static let key = "phoneAlarms"

    static func saved(in defaults: UserDefaults) -> PhoneAlarms? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    /// Saves these alarms unless ones read later are already saved; returns whether it did.
    @discardableResult func save(in defaults: UserDefaults) -> Bool {
        if let saved = Self.saved(in: defaults), saved.date >= date {
            return false
        }
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
        return true
    }
}

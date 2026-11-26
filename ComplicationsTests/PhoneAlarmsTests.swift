import Foundation
import Testing

struct PhoneAlarmsTests {
    private let calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    /// Monday, November 23, 2026, 10:05 AM.
    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 10, minute: 5))!
    }

    private func at(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private typealias Alarm = PhoneAlarms.Alarm

    private func alarm(_ hour: Int, _ minute: Int = 0, on weekdays: [Int] = [], _ label: String? = nil) -> Alarm {
        Alarm(hour: hour, minute: minute, weekdays: weekdays, label: label)
    }

    @Test func travelsInAMessage() throws {
        let alarms = PhoneAlarms(date: monday, alarms: [alarm(7, 30, on: [2, 3, 4, 5, 6], "Up")])
        #expect(try #require(PhoneAlarms(message: alarms.message)) == alarms)
        #expect(PhoneAlarms(message: PhoneBatteryReading(date: .now, level: 0.5, isPluggedIn: false).message) == nil)
    }

    @Test func keepsTheLatestRead() throws {
        let defaults = try #require(UserDefaults(suiteName: "PhoneAlarmsTests"))
        defaults.removePersistentDomain(forName: "PhoneAlarmsTests")
        let alarms = PhoneAlarms(date: monday, alarms: [alarm(7)])
        #expect(alarms.save(in: defaults))
        #expect(!PhoneAlarms(date: monday.addingTimeInterval(-60), alarms: []).save(in: defaults))
        #expect(PhoneAlarms.saved(in: defaults) == alarms)
        // Reading that none are on replaces them.
        #expect(PhoneAlarms(date: monday.addingTimeInterval(60), alarms: []).save(in: defaults))
        #expect(PhoneAlarms.saved(in: defaults)?.alarms.isEmpty == true)
    }

    @Test func oneTimeAlarmRingsOnceAtItsNextTimeAfterTheRead() {
        let alarms = PhoneAlarms(date: monday, alarms: [alarm(7), alarm(11, 30)])
        let rings = alarms.rings(from: monday, to: monday.addingTimeInterval(3 * 24 * 60 * 60), calendar: calendar)
        // 7:00 has passed today, so it rings tomorrow; 11:30 is still to come today.
        #expect(rings.map(\.date) == [at(day: 23, 11, 30), at(day: 24, 7)])
    }

    @Test func oneTimeAlarmIsOffOnceItHasRung() {
        let alarms = PhoneAlarms(date: monday, alarms: [alarm(11, 30)])
        let later = at(day: 23, 12)
        #expect(alarms.rings(from: later, to: later.addingTimeInterval(7 * 24 * 60 * 60), calendar: calendar).isEmpty)
    }

    @Test func repeatingAlarmRingsOnEachOfItsWeekdays() {
        // Weekdays at 6:45, read on a Monday after that time, from Tuesday to the next Tuesday.
        let alarms = PhoneAlarms(date: monday, alarms: [alarm(6, 45, on: [2, 3, 4, 5, 6])])
        let rings = alarms.rings(from: at(day: 24, 0), to: at(day: 31, 0), calendar: calendar)
        #expect(rings.map(\.date) == [24, 25, 26, 27, 30].map { at(day: $0, 6, 45) })
    }

    @Test func repeatingAlarmRingsLaterTodayButNotEarlier() {
        let alarms = PhoneAlarms(date: monday, alarms: [alarm(7, on: [2]), alarm(18, on: [2])])
        let rings = alarms.rings(from: monday, to: at(day: 24, 0), calendar: calendar)
        #expect(rings.map(\.date) == [at(day: 23, 18)])
    }

    @Test func readsRepeatDaysHoweverShortcutsWritesThem() {
        #expect(calendar.component(.weekday, from: monday) == 2)
        #expect(PhoneAlarms.weekdays(from: [], calendar: calendar).isEmpty)
        #expect(PhoneAlarms.weekdays(from: ["Monday", "Wednesday"], calendar: calendar) == [2, 4])
        #expect(PhoneAlarms.weekdays(from: ["Monday\nFriday"], calendar: calendar) == [2, 6])
        #expect(PhoneAlarms.weekdays(from: ["Sat, Sun"], calendar: calendar) == [1, 7])
        #expect(PhoneAlarms.weekdays(from: ["Weekdays"], calendar: calendar) == [2, 3, 4, 5, 6])
        #expect(PhoneAlarms.weekdays(from: ["Weekends"], calendar: calendar) == [1, 7])
        #expect(PhoneAlarms.weekdays(from: ["Every Day"], calendar: calendar) == Array(1 ... 7))
        #expect(PhoneAlarms.weekdays(from: ["Never"], calendar: calendar).isEmpty)
    }

    @Test func alarmsBecomeEventsOnce() {
        let alarms = PhoneAlarms(date: monday, alarms: [alarm(11, 30, "Call"), alarm(11, 30, "Call"), alarm(12)])
        let events = CalendarEvents.alarms(from: monday, to: at(day: 24, 0), in: alarms)
        #expect(events.map(\.title) == ["Call", "Alarm"])
        #expect(events.allSatisfy { $0.isAlarm && $0.start == $0.end && $0.isShown })
        #expect(events.first?.timeRange == CalendarEvent(alarm: alarm(11, 30), at: at(day: 23, 11, 30)).timeRange)
    }

    @Test func alarmShowsInUpNextUntilItRings() {
        let ring = CalendarEvent(alarm: alarm(11), at: monday.addingTimeInterval(30 * 60))
        #expect(CalendarEvents.upNext(at: monday, in: [ring]).lead == ring)
        #expect(CalendarEvents.upNext(at: ring.start, in: [ring]) == CalendarEvents.UpNext(lead: nil, rest: []))
    }

    @Test func blockDoesNotStepAsideForAnAlarm() {
        let block = CalendarEvent(
            id: "block", title: "block", start: monday.addingTimeInterval(-5 * 60),
            end: monday.addingTimeInterval(3 * 60 * 60), isAllDay: false, location: nil,
            color: CalendarEvent.RGB(red: 0, green: 0, blue: 0)
        )
        let ring = CalendarEvent(alarm: alarm(11), at: monday.addingTimeInterval(30 * 60))
        let upNext = CalendarEvents.upNext(at: monday, in: [block, ring])
        #expect(upNext.lead == block)
        #expect(upNext.rest == [ring])
    }
}

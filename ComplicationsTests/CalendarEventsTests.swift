import Foundation
import Testing

struct CalendarEventsTests {
    /// 10:05 AM today.
    private let now = Calendar.current.date(bySettingHour: 10, minute: 5, second: 0, of: .now)!

    private func event(_ id: String, minutes: Double, length: Double = 30) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: id,
            start: now.addingTimeInterval(minutes * 60),
            end: now.addingTimeInterval((minutes + length) * 60),
            isAllDay: false,
            location: nil,
            color: CalendarEvent.RGB(red: 0, green: 0, blue: 0)
        )
    }

    private func allDay(_ id: String) -> CalendarEvent {
        let start = Calendar.current.startOfDay(for: now)
        return CalendarEvent(
            id: id,
            title: id,
            start: start,
            end: start.addingTimeInterval(24 * 60 * 60),
            isAllDay: true,
            location: nil,
            color: CalendarEvent.RGB(red: 0, green: 0, blue: 0)
        )
    }

    @Test func eventOnNowLeads() {
        let upNext = CalendarEvents.upNext(at: now, in: [event("a", minutes: -5), event("b", minutes: 90)])
        #expect(upNext.lead?.id == "a")
        #expect(upNext.rest.map(\.id) == ["b"])
    }

    @Test func eventWithinTheHourLeads() {
        #expect(CalendarEvents.upNext(at: now, in: [event("a", minutes: 60)]).lead?.id == "a")
    }

    @Test func noLeadWhenNextEventIsOverAnHourAway() {
        let events = [event("a", minutes: 61), event("b", minutes: 90), event("c", minutes: 120)]
        let upNext = CalendarEvents.upNext(at: now, in: events)
        #expect(upNext.lead == nil)
        #expect(upNext.rest.map(\.id) == ["a", "b", "c"])
    }

    @Test func threeLinesInAll() {
        let events = (0 ..< 5).map { event("\($0)", minutes: Double($0) * 30) }
        let upNext = CalendarEvents.upNext(at: now, in: events)
        #expect(upNext.lead?.id == "0")
        #expect(upNext.rest.map(\.id) == ["1", "2"])
    }

    @Test func endedEventsAreSkipped() {
        let upNext = CalendarEvents.upNext(at: now, in: [event("a", minutes: -40), event("b", minutes: 10)])
        #expect(upNext.lead?.id == "b")
        #expect(upNext.rest.isEmpty)
    }

    @Test func allDayEventsAreNeverShown() {
        let upNext = CalendarEvents.upNext(at: now, in: [allDay("day"), event("a", minutes: 90)])
        #expect(upNext.lead == nil)
        #expect(upNext.rest.map(\.id) == ["a"])
        #expect(CalendarEvents.upNext(at: now, in: [allDay("day")]) == CalendarEvents.UpNext(lead: nil, rest: []))
    }

    @Test func eventsOverTwelveHoursAreNeverShown() {
        // A week-long trip that's on now, and one exactly 12 hours long, which still counts.
        let trip = event("trip", minutes: -60, length: 7 * 24 * 60)
        let shift = event("shift", minutes: 30, length: 12 * 60)
        let upNext = CalendarEvents.upNext(at: now, in: [trip, shift, event("a", minutes: 800)])
        #expect(upNext.lead?.id == "shift")
        #expect(upNext.rest.map(\.id) == ["a"])
    }

    @Test func longEventStepsAsideForShorterOverlappingOnes() {
        // A 3-hour block starting first, with three 30-minute meetings inside it.
        let events = [
            event("block", minutes: -5, length: 180),
            event("a", minutes: 10),
            event("b", minutes: 50),
            event("c", minutes: 90),
        ]
        let upNext = CalendarEvents.upNext(at: now, in: events)
        #expect(upNext.lead?.id == "a")
        #expect(upNext.rest.map(\.id) == ["b", "c"])
    }

    @Test func blockShowsUntilTheMeetingInsideItComesUp() {
        // A 3-hour block on now, with its only meeting two hours away.
        let events = [event("block", minutes: -5, length: 180), event("a", minutes: 120)]
        let upNext = CalendarEvents.upNext(at: now, in: events)
        #expect(upNext.lead?.id == "block")
        #expect(upNext.rest.map(\.id) == ["a"])
        let later = CalendarEvents.upNext(at: now.addingTimeInterval(61 * 60), in: events)
        #expect(later.lead?.id == "a")
        #expect(later.rest.isEmpty)
    }

    @Test func blockShowsBesideAMeetingItOnlyOverlaps() {
        // The meeting starts inside the block but runs past its end.
        let events = [event("block", minutes: -5, length: 180), event("a", minutes: 160, length: 60)]
        let upNext = CalendarEvents.upNext(at: now.addingTimeInterval(120 * 60), in: events)
        #expect(upNext.lead?.id == "block")
        #expect(upNext.rest.map(\.id) == ["a"])
    }

    @Test func doubleBookedMeetingsBothShow() {
        // An hour-long meeting with a 15-minute one inside it; neither is a block.
        let events = [event("hour", minutes: -5, length: 60), event("quick", minutes: 40, length: 15)]
        let upNext = CalendarEvents.upNext(at: now, in: events)
        #expect(upNext.lead?.id == "hour")
        #expect(upNext.rest.map(\.id) == ["quick"])
    }

    @Test func longEventShowsWhenNothingShorterOverlaps() {
        let events = [event("block", minutes: 10, length: 180), event("a", minutes: 200)]
        let upNext = CalendarEvents.upNext(at: now, in: events)
        #expect(upNext.lead?.id == "block")
        #expect(upNext.rest.map(\.id) == ["a"])
    }
}

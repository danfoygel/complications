import Foundation
import Testing

struct WeatherLineTests {
    /// Friday, October 30, 2026, 11 a.m.
    private let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 11))!

    private func time(_ hours: Double) -> Date {
        start.addingTimeInterval(hours * 3600)
    }

    /// Days from today with sunrise at 7:20 and sunset at 17:40, offsets in hours from `start`.
    private func days(_ count: Int = 3) -> [ForecastDay] {
        (0 ..< count).map { offset in
            ForecastDay(
                date: time(Double(offset * 24) - 11), low: 5, high: 15,
                sunrise: time(Double(offset * 24) - 11 + 7.33), sunset: time(Double(offset * 24) - 11 + 17.67)
            )
        }
    }

    private func forecast(hours count: Int, rainFrom first: Int? = nil) -> PrecipitationForecast {
        PrecipitationForecast(
            minutes: [],
            hours: (0 ..< count).map { hour in
                ForecastHour(date: time(Double(hour)), temperature: 10, precipitation: hour == first ? .rain : nil)
            },
            days: days()
        )
    }

    @Test func daytimeGivesTonightsSunset() {
        let sun = SunEvent.next(after: start, in: days())
        #expect(sun == SunEvent(isSunrise: false, date: time(6.67)))
    }

    @Test func afterSunsetGivesTomorrowsSunrise() {
        let sun = SunEvent.next(after: time(7), in: days())
        #expect(sun == SunEvent(isSunrise: true, date: time(13 + 7.33)))
    }

    @Test func noSunTimesGiveNoSunEvent() {
        let polar = [ForecastDay(date: start, low: -20, high: -15)]
        #expect(SunEvent.next(after: start, in: polar) == nil)
    }

    @Test func lineHasSunAndRain() {
        let line = WeatherLine(at: start, forecast: forecast(hours: 24, rainFrom: 3))
        #expect(line?.sun?.isSunrise == false)
        #expect(line?.outlook?.text == "in 3h")
    }

    @Test func rainIsLeftOutPastTheHourlyForecast() {
        // Hours run out 6 hours from now, short of the 12-hour window: no claim about rain, but still the sunset.
        let line = WeatherLine(at: start, forecast: forecast(hours: 6))
        #expect(line?.outlook == nil)
        #expect(line?.sun != nil)
    }

    @Test func nothingToShowIsNil() {
        let empty = PrecipitationForecast(minutes: [], hours: [], days: [])
        #expect(WeatherLine(at: start, forecast: empty) == nil)
    }
}

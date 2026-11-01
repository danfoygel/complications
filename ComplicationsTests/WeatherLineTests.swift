import Foundation
import Testing

struct WeatherLineTests {
    /// Friday, October 30, 2026, 11 a.m.
    private let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 11))!

    private func time(_ hours: Double) -> Date {
        start.addingTimeInterval(hours * 3600)
    }

    /// Days from today with sunrise at 7:20 and sunset at 17:40, offsets in hours from `start`.
    private func days(_ count: Int = 5) -> [ForecastDay] {
        (0 ..< count).map { offset in
            ForecastDay(
                date: time(Double(offset * 24) - 11), low: 5, high: 15,
                sunrise: time(Double(offset * 24) - 11 + 7.33), sunset: time(Double(offset * 24) - 11 + 17.67)
            )
        }
    }

    private func forecast(
        hours count: Int, rainFrom first: Int? = nil, rainOnDay rainDay: Int? = nil, aqi: Int? = nil
    ) -> PrecipitationForecast {
        PrecipitationForecast(
            minutes: [],
            hours: (0 ..< count).map { hour in
                ForecastHour(
                    date: time(Double(hour)), temperature: 10, precipitation: hour == first ? .rain : nil,
                    precipitationAmount: hour == first ? 4 : 0
                )
            },
            days: days().enumerated().map { offset, day in
                var day = day
                if offset == rainDay {
                    // By the calendar: 24-hour steps cross the end of daylight saving time.
                    day.date = Calendar.current.date(byAdding: .day, value: offset, to: start)!
                    day.precipitation = .rain
                }
                return day
            },
            airQuality: aqi.map { aqi in (0 ..< count).map { AirQualityReading(date: time(Double($0)), aqi: aqi) } }
                ?? []
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

    @Test func rainAheadGivesTheTotalAndWhenItStarts() {
        let line = WeatherLine(at: start, forecast: forecast(hours: 25, rainFrom: 3, aqi: 40))
        #expect(line?.total == PrecipitationTotal(kind: .rain, amount: 4))
        #expect(line?.outlook?.text == "in 3h")
        #expect(line?.sun == nil)
        #expect(line?.airQuality == nil)
    }

    @Test func rainLaterInTheDayCountsAsAhead() {
        let line = WeatherLine(at: start, forecast: forecast(hours: 25, rainFrom: 18, aqi: 40))
        #expect(line?.total == PrecipitationTotal(kind: .rain, amount: 4))
        #expect(line?.outlook?.text == "in 18h")
    }

    @Test func rainLaterInTheWeekGivesTheSunAndTheDay() {
        // Friday the 30th: rain on Tuesday, none in the next 24 hours.
        let line = WeatherLine(at: start, forecast: forecast(hours: 25, rainOnDay: 4, aqi: 40))
        #expect(line?.sun?.isSunrise == false)
        #expect(line?.outlook?.text == "on Tu")
        #expect(line?.total == nil)
        #expect(line?.airQuality == nil)
    }

    @Test func dryGivesTheSunAndAirQuality() {
        let line = WeatherLine(at: start, forecast: forecast(hours: 25, aqi: 40))
        #expect(line?.sun?.isSunrise == false)
        #expect(line?.airQuality == 40)
        #expect(line?.total == nil)
        #expect(line?.outlook == nil)
    }

    @Test func rainIsLeftOutPastTheHourlyForecast() {
        // Hours run out 13 hours from now, short of the 24-hour window: no claim about rain, but still the sunset.
        let line = WeatherLine(at: start, forecast: forecast(hours: 13, rainFrom: 3))
        #expect(line?.outlook == nil)
        #expect(line?.sun != nil)
    }

    @Test func dryDaysChangeOnlyAtSunriseAndSunset() {
        let changes = WeatherLine.changes(after: start, forecast: forecast(hours: 30))
        #expect(changes.count == 10)
    }

    @Test func rainAheadChangesOnlyWhenItsWordingDoes() {
        let rainy = forecast(hours: 30, rainFrom: 3)
        let marks = WeatherLine.changes(after: start, forecast: rainy).dropLast(10)
        // "in 3h" until it rounds to "in 2h", "in 1h", then 5-minute steps under the hour, then "for 1h" as the total
        // falls, and dry: far fewer than the 288 five-minute marks in 24 hours, and each reads differently from the
        // one before.
        #expect(marks.count > 5 && marks.count < 40)
        func reading(at date: Date) -> String {
            let line = WeatherLine(at: date, forecast: rainy)
            return "\(line?.total?.text ?? "") \(line?.outlook?.text ?? "")"
        }
        var previous = reading(at: start)
        for mark in marks {
            let text = reading(at: mark)
            #expect(text != previous)
            previous = text
        }
    }

    @Test func nothingToShowIsNil() {
        let empty = PrecipitationForecast(minutes: [], hours: [], days: [])
        #expect(WeatherLine(at: start, forecast: empty) == nil)
    }
}

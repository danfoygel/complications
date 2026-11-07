import Foundation
import Testing

struct WeatherOutlookTests {
    /// 11 AM local time, so whole days line up with the calendar.
    private let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 11))!

    private func time(_ hours: Double) -> Date {
        start.addingTimeInterval(hours * 60 * 60)
    }

    /// One hour per temperature, starting at `start`.
    private func hours(_ temperatures: [Double]) -> [ForecastHour] {
        temperatures.enumerated().map { ForecastHour(date: time(Double($0.offset)), temperature: $0.element) }
    }

    private func hours(_ precipitation: [PrecipitationSpan.Kind?], from first: Double = 0) -> [ForecastHour] {
        precipitation.enumerated().map {
            ForecastHour(date: time(first + Double($0.offset)), temperature: 10, precipitation: $0.element)
        }
    }

    // MARK: Next high or low

    @Test func risingTemperatureGivesTheHighAtThePeak() throws {
        let next = try #require(WeatherForecast.nextExtreme(
            after: start, temperature: 15, hours: hours([15, 17, 19, 21, 20, 16, 12]), days: []
        ))
        #expect(next.isHigh)
        #expect(next.temperature == 21)
    }

    @Test func fallingTemperatureGivesTheLowAtTheTrough() throws {
        let next = try #require(WeatherForecast.nextExtreme(
            after: start, temperature: 12, hours: hours([12, 10, 7, 5, 6, 9]), days: []
        ))
        #expect(!next.isHigh)
        #expect(next.temperature == 5)
    }

    @Test func smallWobblesDontEndTheRise() throws {
        // The dip from 18 to 17.8 is within the tolerance, so the peak is the 22 after it.
        let next = try #require(WeatherForecast.nextExtreme(
            after: start, temperature: 15, hours: hours([15, 18, 17.8, 22, 19]), days: []
        ))
        #expect(next.temperature == 22)
    }

    @Test func steadyTemperatureHasNoNextExtreme() {
        #expect(WeatherForecast.nextExtreme(
            after: start, temperature: 15, hours: hours([15, 15.2, 14.8, 15.3]), days: []
        ) == nil)
    }

    @Test func justPastThePeakTheLowIsNext() throws {
        let next = try #require(WeatherForecast.nextExtreme(
            after: start, temperature: 21, hours: hours([21, 20, 17, 14, 15]), days: []
        ))
        #expect(!next.isHigh)
        #expect(next.temperature == 14)
    }

    @Test func dayForecastStandsInForANearbyPeak() throws {
        let next = try #require(WeatherForecast.nextExtreme(
            after: start, temperature: 15, hours: hours([15, 18, 21, 20]),
            days: [ForecastDay(date: start, low: 9, high: 22)]
        ))
        #expect(next.temperature == 22)
    }

    @Test func overnightLowUsesTomorrowsForecast() throws {
        // From 11 AM falling for 19 hours to 10.5 at 6 AM tomorrow, then rising.
        let falling: [Double] = (0 ... 19).map { 20 - Double($0) / 2 }
        let temperatures = falling + [11.5, 12.5, 13.5]
        let next = try #require(WeatherForecast.nextExtreme(
            after: start, temperature: 20, hours: hours(temperatures),
            days: [ForecastDay(date: start, low: 3, high: 21), ForecastDay(date: time(24), low: 9.5, high: 18)]
        ))
        #expect(!next.isHigh)
        #expect(next.temperature == 9.5)
    }

    @Test func farOffDayForecastIsIgnored() throws {
        // Today's low (3) was this morning; the trough this afternoon is 12.
        let next = try #require(WeatherForecast.nextExtreme(
            after: start, temperature: 16, hours: hours([16, 14, 12, 15, 18]),
            days: [ForecastDay(date: start, low: 3, high: 21)]
        ))
        #expect(next.temperature == 12)
    }

    @Test func onlyLooksAheadOneDay() {
        let temperatures = [15] + Array(repeating: 15, count: 24) + [25]
        #expect(WeatherForecast.nextExtreme(
            after: start, temperature: 15, hours: hours(temperatures.map(Double.init)), days: []
        ) == nil)
    }

    // MARK: Rain and snow

    @Test func consecutiveHoursMergeIntoOneSpan() {
        let spans = WeatherForecast.precipitation(after: start, hours: hours([nil, nil, .rain, .rain, .rain, nil]))
        #expect(spans.count == 1)
        #expect(spans.first?.kind == .rain)
        #expect(spans.first?.start == time(2))
        #expect(spans.first?.end == time(5))
    }

    @Test func kindChangeStartsANewSpan() {
        let spans = WeatherForecast.precipitation(after: start, hours: hours([.rain, .rain, .snow, nil, .snow]))
        #expect(spans.map(\.kind) == [.rain, .snow, .snow])
        #expect(spans.map(\.start) == [time(0), time(2), time(4)])
    }

    @Test func currentHourCountsFromNow() {
        // Raining in the hour that started at 10:00; it's now 10:30.
        let now = time(-0.5)
        let spans = WeatherForecast.precipitation(after: now, hours: hours([.rain, .rain, nil], from: -1))
        #expect(spans.first?.start == now)
        #expect(spans.first?.end == time(1))
    }

    @Test func spansAreClippedToTwelveHours() {
        let spans = WeatherForecast.precipitation(after: start, hours: hours(Array(repeating: .snow, count: 20)))
        #expect(spans.count == 1)
        #expect(spans.first?.end == time(12))
    }

    @Test func dryForecastHasNoSpans() {
        #expect(WeatherForecast.precipitation(after: start, hours: hours([nil, nil, nil])).isEmpty)
    }

    @Test func minuteForecastTakesOverForTheHourItCovers() {
        // The hourly forecast says rain all hour; the minute forecast says it holds off until 11:25.
        let minutes = (0 ..< 60).map {
            ForecastMinute(date: time(Double($0) / 60), precipitation: $0 >= 25 ? .rain : nil)
        }
        let spans = WeatherForecast.precipitation(after: start, minutes: minutes, hours: hours([.rain, .rain, nil]))
        #expect(spans.count == 1)
        #expect(spans.first?.start == time(25.0 / 60))
        #expect(spans.first?.end == time(2))
    }

    // MARK: Wording

    @Test func dryNowGivesTimeUntilItStarts() {
        let spans = WeatherForecast.precipitation(after: start, hours: hours([nil, nil, .rain, .rain]))
        let outlook = WeatherForecast.outlook(at: start, spans: spans)
        #expect(outlook?.kind == .rain)
        #expect(outlook?.text == "in 2h")
    }

    @Test func fallingNowGivesTimeUntilItStops() {
        let spans = WeatherForecast.precipitation(after: start, hours: hours([.snow, .snow, .snow, .snow, nil]))
        #expect(WeatherForecast.outlook(at: start, spans: spans)?.text == "for 4h")
    }

    @Test func fallingAllWindowIsOpenEnded() {
        let spans = WeatherForecast.precipitation(after: start, hours: hours(Array(repeating: .rain, count: 20)))
        #expect(WeatherForecast.outlook(at: start, spans: spans)?.text == "for 12h+")
    }

    @Test func dryWindowHasNoOutlook() {
        #expect(WeatherForecast.outlook(at: start, spans: []) == nil)
    }

    private func day(_ offset: Int, _ precipitation: PrecipitationSpan.Kind?) -> ForecastDay {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: start))!
        return ForecastDay(date: date, low: 5, high: 15, precipitation: precipitation)
    }

    @Test func dryWindowNamesTheNextDayWithRainOrSnow() {
        // Friday the 30th: today's own rain (past the window) is skipped; Tuesday has snow.
        let days = [day(0, .rain), day(1, nil), day(2, nil), day(3, nil), day(4, .snow), day(5, .rain)]
        let outlook = WeatherForecast.outlook(at: start, spans: [], days: days)
        #expect(outlook?.kind == .snow)
        #expect(outlook?.text == "on Tu")
    }

    @Test func rainInTheWindowBeatsALaterDay() {
        let spans = WeatherForecast.precipitation(after: start, hours: hours([nil, .rain]))
        #expect(WeatherForecast.outlook(at: start, spans: spans, days: [day(1, .snow)])?.text == "in 1h")
    }

    @Test func dayAWeekOutIsTooFarToName() {
        #expect(WeatherForecast.outlook(at: start, spans: [], days: [day(7, .rain)]) == nil)
    }

    // MARK: 24-hour total

    @Test func totalCountsWhatsLeftOfTheCurrentHour() throws {
        // 2 mm an hour for a day from `start`, asked half an hour in: half of the first hour and of the hour after
        // the last full one, which isn't there, so the forecast must run an hour longer.
        let hours = (0 ..< 25).map {
            ForecastHour(date: time(Double($0)), temperature: 10, precipitationAmount: 2, snowfallAmount: 20)
        }
        let rain = try #require(WeatherForecast.total(of: .rain, after: time(0.5), hours: hours))
        #expect(abs(rain.amount - 48) < 0.001)
        let snow = try #require(WeatherForecast.total(of: .snow, after: time(0.5), hours: hours))
        #expect(abs(snow.amount - 480) < 0.001)
    }

    @Test func sleetWithNoSnowfallTotalsItsWater() throws {
        let hours = (0 ..< 25).map { ForecastHour(date: time(Double($0)), temperature: 0, precipitationAmount: 1) }
        let total = try #require(WeatherForecast.total(of: .snow, after: time(0), hours: hours))
        #expect(total.kind == .rain)
        #expect(abs(total.amount - 24) < 0.001)
    }

    @Test func totalNeedsTheWholeDay() {
        let hours = (0 ..< 24).map { ForecastHour(date: time(Double($0)), temperature: 10, precipitationAmount: 2) }
        #expect(WeatherForecast.total(of: .rain, after: time(0.5), hours: hours) == nil)
    }

    @Test func totalsInMillimetresAndInches() {
        let metric = Locale(identifier: "en_GB")
        let american = Locale(identifier: "en_US")
        #expect(PrecipitationTotal(kind: .rain, amount: 12.3).text(locale: metric) == "12mm")
        #expect(PrecipitationTotal(kind: .rain, amount: 10).text(locale: american) == "0.4″")
        #expect(PrecipitationTotal(kind: .rain, amount: 0.5).text(locale: american) == "<0.1″")
        #expect(PrecipitationTotal(kind: .rain, amount: 0).text(locale: american) == "0.0″")
        #expect(PrecipitationTotal(kind: .snow, amount: 76).text(locale: american) == "3.0″")
        #expect(PrecipitationTotal(kind: .snow, amount: 300).text(locale: american) == "12″")
    }

    @Test func durationsRoundToFiveMinutesThenHours() {
        #expect(PrecipitationOutlook.duration(60) == "5m")
        #expect(PrecipitationOutlook.duration(28 * 60) == "30m")
        #expect(PrecipitationOutlook.duration(58 * 60) == "1h")
        #expect(PrecipitationOutlook.duration(130 * 60) == "2h")
        #expect(PrecipitationOutlook.duration(150 * 60) == "3h")
    }
}

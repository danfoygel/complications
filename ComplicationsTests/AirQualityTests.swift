import Foundation
import Testing

struct AirQualityTests {
    @Test func readsOpenMeteoHourlyValuesSkippingGaps() throws {
        let json = #"{"hourly":{"time":[1793404800,1793408400,1793412000],"us_aqi":[13,null,41]}}"#
        let readings = try AirQuality.readings(from: Data(json.utf8))
        #expect(readings.map(\.aqi) == [13, 41])
        #expect(readings.first?.date == Date(timeIntervalSince1970: 1_793_404_800))
    }

    @Test func readingIsTheHourTheDateFallsIn() {
        let hour = Date(timeIntervalSince1970: 1_793_404_800)
        let readings = [AirQualityReading(date: hour, aqi: 13), AirQualityReading(date: hour + 3600, aqi: 20)]
        #expect(AirQuality.reading(at: hour + 1800, in: readings)?.aqi == 13)
        #expect(AirQuality.reading(at: hour + 3600, in: readings)?.aqi == 20)
        #expect(AirQuality.reading(at: hour + 7200, in: readings) == nil)
    }

    @Test func categoriesFollowTheEPABands() {
        #expect(AirQuality.Category(50) == .good)
        #expect(AirQuality.Category(51) == .moderate)
        #expect(AirQuality.Category(150) == .sensitive)
        #expect(AirQuality.Category(201) == .veryUnhealthy)
        #expect(AirQuality.Category(301) == .hazardous)
    }
}

import CoreLocation
import Foundation

/// The US Air Quality Index for one hour.
struct AirQualityReading: Codable, Sendable {
    /// The start of the hour.
    var date: Date
    var aqi: Int
}

/// Hourly US AQI from Open-Meteo's air-quality API (WeatherKit has none). It's free and needs no key; the location
/// sent is rounded to about 1 km.
enum AirQuality {
    /// The EPA's bands, which set the gauge's color.
    enum Category: Sendable {
        case good, moderate, sensitive, unhealthy, veryUnhealthy, hazardous

        init(_ aqi: Int) {
            self = switch aqi {
            case ...50: .good
            case ...100: .moderate
            case ...150: .sensitive
            case ...200: .unhealthy
            case ...300: .veryUnhealthy
            default: .hazardous
            }
        }
    }

    /// The gauge is full at this value ("very unhealthy" and worse).
    static let gaugeMax = 300.0

    /// The hour that `date` falls in, if `readings` has it. Readings must be in order.
    static func reading(at date: Date, in readings: [AirQualityReading]) -> AirQualityReading? {
        readings.last { $0.date <= date && date < $0.date.addingTimeInterval(60 * 60) }
    }

    /// Today and tomorrow, by the hour (UTC days, so the next hours are always there).
    static func fetch(for location: CLLocation) async throws -> [AirQualityReading] {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", location.coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "us_aqi"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try readings(from: data)
    }

    /// The readings in an Open-Meteo response; hours with no value are left out.
    static func readings(from data: Data) throws -> [AirQualityReading] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let hourly = try decoder.decode(OpenMeteoResponse.self, from: data).hourly
        return zip(hourly.time, hourly.usAqi).compactMap { time, aqi in
            aqi.map { AirQualityReading(date: Date(timeIntervalSince1970: time), aqi: $0) }
        }
    }

    static func cached(in defaults: UserDefaults = AppGroup.defaults) -> [AirQualityReading] {
        defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode([AirQualityReading].self, from: $0) } ?? []
    }

    static func save(_ readings: [AirQualityReading], in defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(try? JSONEncoder().encode(readings), forKey: cacheKey)
    }

    private static let cacheKey = "airQuality"
}

private struct OpenMeteoResponse: Decodable {
    struct Hourly: Decodable {
        var time: [TimeInterval]
        var usAqi: [Int?]
    }

    var hourly: Hourly
}

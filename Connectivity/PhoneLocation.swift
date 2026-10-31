import CoreLocation
import Foundation

/// Where the phone last was, as the iPhone app read it. The watch never takes a location fix of its own: it uses
/// this for the weather. Travels alongside `PhoneBatteryReading` in the same messages, under its own key.
struct PhoneLocation: Codable, Equatable, Sendable {
    /// When the fix was taken, not when it was sent.
    var date: Date
    var latitude: Double
    var longitude: Double

    /// A move this far is worth waking the watch for and reloading its weather.
    static let significantDistance: CLLocationDistance = 3000

    var location: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0, horizontalAccuracy: 0, verticalAccuracy: -1, timestamp: date
        )
    }

    /// Whether this is a significant move from `other`, or there's nothing to compare with.
    func isFar(from other: PhoneLocation?) -> Bool {
        guard let other else { return true }
        return location.distance(from: other.location) >= Self.significantDistance
    }

    var message: [String: Any] {
        (try? JSONEncoder().encode(self)).map { ["phoneLocation": $0] } ?? [:]
    }

    init(date: Date, latitude: Double, longitude: Double) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ location: CLLocation) {
        self.init(
            date: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    init?(message: [String: Any]) {
        guard let data = message["phoneLocation"] as? Data,
              let location = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = location
    }
}

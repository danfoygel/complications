import Foundation
import SwiftUI

/// The complications' accent color, picked in the iPhone app. In full color everything the face would tint is drawn in
/// it (the battery outline aside, which shows its level instead). Travels alongside `PhoneBatteryReading` in the same
/// messages, under its own key; the phone keeps its pick in its own defaults and the watch the latest it received in
/// the app group.
struct AccentColor: Codable, Equatable, Sendable {
    /// When it was picked, so an older pick arriving late doesn't replace a newer one.
    var date: Date
    /// Extended sRGB components, so a Display P3 pick keeps its color.
    var red: Double
    var green: Double
    var blue: Double

    /// Until one is picked: the system orange.
    static let standard = AccentColor(date: .distantPast, red: 1, green: 0.624, blue: 0.039)

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }

    var message: [String: Any] {
        (try? JSONEncoder().encode(self)).map { [Self.key: $0] } ?? [:]
    }

    init(date: Date, red: Double, green: Double, blue: Double) {
        self.date = date
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(message: [String: Any]) {
        guard let data = message[Self.key] as? Data,
              let accent = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = accent
    }

    private static let key = "accentColor"

    static func saved(in defaults: UserDefaults) -> AccentColor? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    /// Saves this color unless a newer pick is already saved; returns whether it did.
    @discardableResult func save(in defaults: UserDefaults) -> Bool {
        if let saved = Self.saved(in: defaults), saved.date >= date {
            return false
        }
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
        return true
    }
}

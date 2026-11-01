import CoreLocation

/// Shows the When In Use prompt if the user hasn't answered it yet, and waits for the answer. The watch's weather
/// uses the location the phone sends with each battery reading, so the phone is the only one that asks.
@MainActor
final class LocationPermission: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var answered: CheckedContinuation<Void, Never>?

    func request() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            answered = continuation
            manager.delegate = self
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Also called as soon as the delegate is set, while the status is still undetermined.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        answered?.resume()
        answered = nil
    }
}

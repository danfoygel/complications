import CoreLocation

/// Shows the When In Use prompt if the user hasn't answered it yet, and waits for the answer. Only the app can
/// prompt; the weather widget uses whatever was granted here.
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

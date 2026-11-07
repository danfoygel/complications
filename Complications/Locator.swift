import CoreLocation

/// The phone app's location access: shows the When In Use prompt if the user hasn't answered it yet, and takes a fresh
/// fix while the app is open. The watch's weather uses the location the phone sends with each battery reading; in the
/// background that's only the system's last fix, which can be hours old, so one taken whenever the app is in front
/// keeps it closer to current.
@MainActor
final class Locator: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var answered: CheckedContinuation<Void, Never>?
    private var located: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        // The weather needs no better, and a coarse fix comes sooner and costs less.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    /// Returns once the user has answered the prompt, or after `limit` if they leave it up.
    func requestAccess(limit: Duration = .seconds(60)) async {
        guard manager.authorizationStatus == .notDetermined, answered == nil else { return }
        await withCheckedContinuation { continuation in
            answered = continuation
            manager.requestWhenInUseAuthorization()
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                self.finish(&self.answered)
            }
        }
    }

    /// Takes a fix, which `PhoneLocation.current()` then reads. Returns once there is one, it fails, or `limit`
    /// passes; does nothing without location access.
    func refresh(limit: Duration = .seconds(10)) async {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: break
        default: return
        }
        guard located == nil else { return }
        await withCheckedContinuation { continuation in
            located = continuation
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                self.finish(&self.located)
            }
        }
    }

    private func finish(_ waiter: inout CheckedContinuation<Void, Never>?) {
        waiter?.resume()
        waiter = nil
    }

    // MARK: CLLocationManagerDelegate

    /// Also called as soon as the delegate is set, while the status may still be undetermined.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        finish(&answered)
    }

    func locationManager(_: CLLocationManager, didUpdateLocations _: [CLLocation]) {
        finish(&located)
    }

    func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        finish(&located)
    }
}

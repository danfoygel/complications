import SwiftUI
import WidgetKit

@main
struct ComplicationsWatchApp: App {
    init() {
        // Early, so a reading that woke the app in the background is delivered.
        PhoneLink.shared.start()
        Self.reloadComplicationsIfNewBuild()
    }

    /// After an install, the face keeps showing what the old build drew until each complication's next scheduled
    /// reload, up to 30 minutes later. Reloading them all once, on the first launch of a new build, shows the new
    /// look right away.
    private static func reloadComplicationsIfNewBuild() {
        let build = buildIdentity()
        let key = "lastLaunchedBuild"
        guard AppGroup.defaults.string(forKey: key) != build else { return }
        AppGroup.defaults.set(build, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Changes with each install: the bundle moves to a new container, and the widget extension's files are new.
    /// The build number alone doesn't, since it only changes on release.
    private static func buildIdentity() -> String {
        let extensionURL = Bundle.main.builtInPlugInsURL?.appendingPathComponent("ComplicationsWidgets.appex")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: extensionURL ?? Bundle.main.bundleURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        let newest = files
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
        return "\(Bundle.main.bundlePath) \(newest?.timeIntervalSince1970 ?? 0)"
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if CommandLine.arguments.contains("-complicationGallery") {
                    ComplicationGallery()
                } else {
                    RootView()
                }
            #else
                RootView()
            #endif
        }
        .backgroundTask(.watchConnectivity) {
            await PhoneLink.shared.waitForPendingContent()
        }
    }
}

/// A list of the four screens. A complication's URL replaces the navigation path with that complication's screen.
/// Opening the app also asks the phone for its battery, which updates the battery complication.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            List(Route.allCases, id: \.self) { route in
                NavigationLink(value: route) {
                    Label(route.title, systemImage: route.symbol)
                }
            }
            .navigationTitle("Complications")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .calendar: CalendarScreen()
                case .battery: BatteryScreen()
                case .weather: WeatherScreen()
                case .activity: ActivityScreen()
                }
            }
        }
        .onOpenURL { url in
            if let route = Route(url: url) {
                path = [route]
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { _ = await PhoneLink.shared.refresh() }
            }
        }
    }
}

extension Route {
    var title: String {
        switch self {
        case .calendar: "Calendar"
        case .battery: "Battery"
        case .weather: "Weather"
        case .activity: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .battery: "battery.75percent"
        case .weather: "cloud.sun"
        case .activity: "figure.run"
        }
    }
}

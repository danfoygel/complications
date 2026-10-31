import SwiftUI

@main
struct ComplicationsWatchApp: App {
    init() {
        // Early, so a reading that woke the app in the background is delivered.
        PhoneLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .backgroundTask(.watchConnectivity) {
            await PhoneLink.shared.waitForPendingContent()
        }
    }
}

/// A list of the three screens. A complication's URL replaces the navigation path with that complication's screen.
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
        }
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .battery: "battery.75percent"
        case .weather: "cloud.sun"
        }
    }
}

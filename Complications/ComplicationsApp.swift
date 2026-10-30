import SwiftUI

@main
struct ComplicationsApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// A list of the three screens. A complication's URL replaces the navigation path with that complication's screen.
struct RootView: View {
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

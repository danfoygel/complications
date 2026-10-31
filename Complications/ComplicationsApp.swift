import BackgroundTasks
import SwiftUI

@main
struct ComplicationsApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Early, so a watch request that launched the app in the background finds an active session.
        WatchLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            PhoneView()
        }
        // Not from init: submitting before SwiftUI has registered the `.backgroundTask` handler below is an
        // assertion failure that kills the app at launch.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()
            await WatchLink.shared.send()
        }
    }
}

/// Asks iOS to run the app every 15 minutes or so to send the battery. iOS decides when, and for an app that's
/// rarely opened that can be hours apart; the Shortcuts automations are what keep the watch current.
enum BackgroundRefresh {
    static let identifier = "com.danfoygel.complications.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

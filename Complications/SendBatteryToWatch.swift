import AppIntents

/// The action Shortcuts automations run on battery-level and charger triggers. Runs in the background.
struct SendBatteryToWatch: AppIntent {
    static var title: LocalizedStringResource {
        "Send Battery to Watch"
    }

    static var description: IntentDescription {
        IntentDescription("Sends this iPhone's battery level to the battery complication on your Apple Watch.")
    }

    func perform() async throws -> some IntentResult {
        await WatchLink.shared.send()
        return .result()
    }
}

struct ComplicationsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendBatteryToWatch(),
            phrases: ["Send battery to watch with \(.applicationName)"],
            shortTitle: "Send Battery to Watch",
            systemImageName: "applewatch"
        )
    }
}

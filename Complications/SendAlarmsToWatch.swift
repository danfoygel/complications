import AppIntents
import Foundation

/// Turns one of the Clock app's alarms, from Shortcuts' Find Alarms, into text for Send Alarms to Watch. An app can't
/// take another app's alarms as they are, so the shortcut passes their fields in one alarm at a time.
struct PrepareAlarmForWatch: AppIntent {
    static var title: LocalizedStringResource {
        "Prepare Alarm for Watch"
    }

    static var description: IntentDescription {
        IntentDescription("""
        Turns a Clock alarm's hours, minutes, repeat days and label into text for Send Alarms to Watch. Use it inside \
        a Repeat with Each over Find Alarms.
        """)
    }

    @Parameter(title: "Hours")
    var hours: Int

    @Parameter(title: "Minutes")
    var minutes: Int

    @Parameter(title: "Repeat Days")
    var repeatDays: [String]?

    @Parameter(title: "Label")
    var label: String?

    /// For a shortcut that gets every alarm rather than finding only the ones that are on.
    @Parameter(title: "Is Enabled", default: true)
    var isEnabled: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Prepare alarm at \(\.$hours):\(\.$minutes) for watch") {
            \.$repeatDays
            \.$label
            \.$isEnabled
        }
    }

    /// Empty for an alarm that's off or has no real time, which Send Alarms to Watch skips.
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard isEnabled, (0 ..< 24).contains(hours), (0 ..< 60).contains(minutes) else { return .result(value: "") }
        let label = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alarm = PhoneAlarms.Alarm(
            hour: hours,
            minute: minutes,
            weekdays: PhoneAlarms.weekdays(from: repeatDays ?? []),
            label: label?.isEmpty == false ? label : nil
        )
        let text = (try? JSONEncoder().encode(alarm)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return .result(value: text)
    }
}

/// Saves the alarms Prepare Alarm for Watch made, replacing the ones before, and sends them to the watch with the
/// battery. Runs in the background.
struct SendAlarmsToWatch: AppIntent {
    static var title: LocalizedStringResource {
        "Send Alarms to Watch"
    }

    static var description: IntentDescription {
        IntentDescription("""
        Sends the alarms that are on to your Apple Watch, for its calendar. Pass it the Repeat Results of Prepare \
        Alarm for Watch; with none, the watch shows no alarms.
        """)
    }

    @Parameter(title: "Alarms")
    var alarms: [String]?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$alarms) to watch")
    }

    func perform() async throws -> some IntentResult {
        // One alarm per line too, in case Shortcuts joins the list into one text.
        let alarms = (alarms ?? []).flatMap { $0.split(whereSeparator: \.isNewline) }.compactMap { line in
            try? JSONDecoder().decode(PhoneAlarms.Alarm.self, from: Data(line.utf8))
        }
        PhoneAlarms(date: .now, alarms: alarms).save(in: .standard)
        await WatchLink.shared.send()
        return .result()
    }
}

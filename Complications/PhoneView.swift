import SwiftUI

/// The phone's battery, what the watch has been sent, and how to set up the automations that keep it current.
struct PhoneView: View {
    @State private var reading: PhoneBatteryReading?
    @State private var lastSent: PhoneBatteryReading?
    @State private var status: WatchLink.Status?
    @State private var outcome: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("iPhone battery", value: reading.map(describe) ?? "Unavailable")
                    LabeledContent("Last sent to watch") {
                        if let lastSent {
                            Text(lastSent.date, format: .relative(presentation: .named))
                        } else {
                            Text("Never")
                        }
                    }
                    Button("Send to Watch Now") {
                        Task { await send() }
                    }
                    if let outcome {
                        Text(outcome).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let status {
                    Section("Watch") {
                        LabeledContent("Paired", value: status.isPaired ? "Yes" : "No")
                        LabeledContent("Watch app installed", value: status.isWatchAppInstalled ? "Yes" : "No")
                        LabeledContent("Complication on face", value: status.isComplicationEnabled ? "Yes" : "No")
                        LabeledContent("Updates left today", value: "\(status.transfersLeft)")
                    }
                }
                Section {
                    AutomationSetup()
                } header: {
                    Text("Keep the watch current")
                } footer: {
                    Text("""
                    The watch also asks the phone directly whenever its app is opened, and iOS runs this app \
                    in the background now and then to send an update.
                    """)
                }
            }
            .navigationTitle("Complications")
            .refreshable { await refresh() }
        }
        .task { await send() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            Task { await send() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            Task { await send() }
        }
    }

    private func send() async {
        outcome = switch await WatchLink.shared.send() {
        case .noBattery: "No battery to read here."
        case .noWatch: "No Apple Watch is paired."
        case .noWatchApp: "Install Complications on the watch first."
        case .sent(woke: true): "Sent; the complication updates now."
        case .sent(woke: false): "Sent; the watch picks it up the next time its app runs."
        }
        await refresh()
    }

    private func refresh() async {
        reading = PhoneBatteryReading.current()
        lastSent = Sent.last
        status = await WatchLink.shared.status()
    }

    private func describe(_ reading: PhoneBatteryReading) -> String {
        "\(reading.percent)%" + (reading.isPluggedIn ? " · Charging" : "")
    }
}

private struct AutomationSetup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("""
            In Shortcuts › Automation, add a personal automation for each trigger below. For each, choose \
            the **Send Battery to Watch** action, set it to **Run Immediately**, and turn off **Notify When Run**.
            """)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "• Battery Level falls below 90%, 80%, 70%, 60%, 50%, 40%, 30%, 20%, 10%")
                Text(verbatim: "• Battery Level rises above 20%, 40%, 60%, 80%, 95%")
                Text(verbatim: "• Charger is connected")
                Text(verbatim: "• Charger is disconnected")
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PhoneView()
}

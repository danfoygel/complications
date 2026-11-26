import EventKit
import SwiftUI

/// The phone's calendars, by account, each with a switch for whether the watch shows its events.
struct CalendarPicker: View {
    @Binding var selection: CalendarSelection
    @State private var isAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @State private var accounts: [(title: String, calendars: [Item])] = []
    /// Kept for as long as the screen is open: EventKit only reports changes to a store that's still around.
    @State private var store = EKEventStore()

    struct Item: Identifiable {
        var key: CalendarSelection.Key
        var color: Color
        var id: String {
            key.identifier
        }
    }

    var body: some View {
        List {
            if !isAuthorized {
                Text("Allow calendar access in Settings › Apps › Complications › Calendars to pick them here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(accounts, id: \.title) { account in
                Section(account.title) {
                    ForEach(account.calendars) { item in
                        Toggle(isOn: shown(item)) {
                            Label {
                                Text(item.key.title)
                            } icon: {
                                Circle().fill(item.color).frame(width: 12, height: 12)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Calendars")
        .task {
            if !isAuthorized {
                isAuthorized = await (try? store.requestFullAccessToEvents()) ?? false
            }
            load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)) { _ in
            load()
        }
    }

    private var items: [Item] {
        accounts.flatMap(\.calendars)
    }

    private func shown(_ item: Item) -> Binding<Bool> {
        Binding {
            !selection.hides(item.key, among: items.map(\.key))
        } set: { isShown in
            let keys = items.map(\.key)
            // From the calendars there are now, so one that's gone drops out and a renamed one goes by its new title.
            let hidden = keys.filter { key in
                key == item.key ? !isShown : selection.hides(key, among: keys)
            }
            selection = CalendarSelection(date: .now, hidden: hidden)
        }
    }

    private func load() {
        guard isAuthorized else { return }
        let calendars = store.calendars(for: .event).map { calendar in
            Item(key: CalendarSelection.Key(calendar), color: Color(cgColor: calendar.cgColor))
        }
        let grouped: [String: [Item]] = Dictionary(grouping: calendars) { $0.key.source }
        accounts = grouped.keys.sorted().map { source in
            let sorted = grouped[source, default: []].sorted { $0.key.title < $1.key.title }
            return (title: source, calendars: sorted)
        }
    }
}

#Preview {
    NavigationStack { CalendarPicker(selection: .constant(.all)) }
}

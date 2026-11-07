import EventKit
import SwiftUI
import WidgetKit

/// The rest of today's events and all of tomorrow's, kept current while it's open.
struct CalendarScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var days: [(day: Date, events: [CalendarEvent])] = []
    @State private var isAuthorized = CalendarEvents.isAuthorized
    /// Kept for as long as the screen is open: EventKit only reports changes to a store that's still around.
    @State private var store = EKEventStore()

    var body: some View {
        List {
            if !isAuthorized {
                Text("Allow calendar access in Settings › Privacy & Security › Calendars.")
                    .foregroundStyle(.secondary)
            }
            ForEach(days, id: \.day) { day in
                Section(day.day.formatted(.dateTime.weekday(.wide).month().day())) {
                    if day.events.isEmpty {
                        Text("No events").foregroundStyle(.secondary)
                    }
                    ForEach(day.events) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
        .navigationTitle("Calendar")
        // Again each time the app comes back, so events that ended while it was away drop off.
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            let wasAuthorized = isAuthorized
            isAuthorized = await CalendarEvents.requestAccess()
            if isAuthorized != wasAuthorized {
                WidgetCenter.shared.reloadTimelines(ofKind: Route.calendar.widgetKind)
            }
            load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)) { _ in
            load()
        }
    }

    private func load() {
        guard isAuthorized else { return }
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let after = calendar.date(byAdding: .day, value: 1, to: tomorrow)!
        let events = CalendarEvents.events(from: now, to: after, in: store)
        days = [today, tomorrow].map { day in
            (day, events.filter { calendar.isDate(max($0.start, now), inSameDayAs: day) })
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color(event.color))
                .frame(width: 4)
            VStack(alignment: .leading) {
                Text(event.title).font(.headline)
                Text(event.timeRange).font(.caption).foregroundStyle(.secondary)
                if let location = event.location {
                    Text(location).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { CalendarScreen() }
}

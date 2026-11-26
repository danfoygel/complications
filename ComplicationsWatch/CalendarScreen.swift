import EventKit
import SwiftUI
import WidgetKit

/// The rest of today's events and all of tomorrow's, with the phone's alarms, kept current while it's open.
struct CalendarScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var days: [(day: Date, events: [CalendarEvent])] = []
    @State private var isAuthorized = CalendarEvents.isAuthorized
    /// The calendars the phone's pick leaves out, named at the bottom so a calendar that went missing can be found.
    @State private var hidden: [String] = []
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
                        Text("No events or alarms").foregroundStyle(.secondary)
                    }
                    ForEach(day.events) { event in
                        EventRow(event: event)
                    }
                }
            }
            if !hidden.isEmpty {
                Text("Hidden on iPhone: \(hidden.formatted(.list(type: .and)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            // The extension isn't told of changes; a reload while the app is in front doesn't count against its
            // budget, so the face catches up now rather than at the next scheduled one.
            if scenePhase == .active {
                WidgetCenter.shared.reloadTimelines(ofKind: Route.calendar.widgetKind)
            }
        }
        // Posted on the session's queue.
        .onReceive(NotificationCenter.default.publisher(for: PhoneAlarms.didChange).receive(on: RunLoop.main)) { _ in
            load()
        }
    }

    /// Alarms too without calendar access.
    private func load() {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let after = calendar.date(byAdding: .day, value: 1, to: tomorrow)!
        let events = CalendarEvents.eventsAndAlarms(from: now, to: after, in: store)
        hidden = CalendarEvents.hiddenCalendars(in: store).map(\.title).sorted()
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
                if event.isAlarm {
                    Text("\(Image(systemName: "alarm.fill")) \(event.title)").font(.headline)
                } else {
                    Text(event.title).font(.headline)
                }
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

import SwiftUI
import WidgetKit

/// The rest of today's events and all of tomorrow's.
struct CalendarScreen: View {
    @State private var days: [(day: Date, events: [CalendarEvent])] = []
    @State private var isAuthorized = CalendarEvents.isAuthorized

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
        .task {
            let wasAuthorized = isAuthorized
            isAuthorized = await CalendarEvents.requestAccess()
            if isAuthorized != wasAuthorized {
                WidgetCenter.shared.reloadTimelines(ofKind: Route.calendar.widgetKind)
            }
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
        let events = CalendarEvents.events(from: now, to: after)
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

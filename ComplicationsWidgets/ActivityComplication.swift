import SwiftUI
import WidgetKit

/// Today's Move, Exercise and Stand rings, all in the accent color.
struct ActivityComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Route.activity.widgetKind, provider: ActivityProvider()) { entry in
            ActivityRingsView(rings: entry.rings)
                .environment(\.complicationAccent, AccentColor.current.color)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(Route.activity.url)
        }
        .configurationDisplayName("Activity Rings")
        .description("Your Move, Exercise and Stand rings in your accent color.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Re-reads today's summary every 15 minutes (the system may stretch that), with the rings emptied at midnight in case
/// the next reload is late. Rings can't be forecast, so the face lags behind the Activity app's by up to a reload; the
/// Activity screen reloads this while it's open. When HealthKit can't be read, the last summary read stands in.
struct ActivityProvider: TimelineProvider {
    func placeholder(in _: Context) -> ActivityEntry {
        ActivityEntry(date: .now, rings: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ActivityEntry) -> Void) {
        let isPreview = context.isPreview
        Task {
            let rings = await ActivitySummaries.latest()
            completion(ActivityEntry(date: .now, rings: rings ?? (isPreview ? .sample : nil)))
        }
    }

    func getTimeline(in _: Context, completion: @escaping @Sendable (Timeline<ActivityEntry>) -> Void) {
        Task {
            let now = Date.now
            let rings = await ActivitySummaries.latest(now: now)
            completion(Timeline(
                entries: ActivitySummaries.entries(for: rings, now: now),
                policy: .after(now.addingTimeInterval(15 * 60))
            ))
        }
    }
}

#Preview(as: .accessoryCircular) {
    ActivityComplication()
} timeline: {
    ActivityEntry(date: .now, rings: .sample)
    ActivityEntry(date: .now, rings: ActivityRings(
        day: .now,
        move: .init(value: 1450, goal: 500),
        exercise: .init(value: 29, goal: 30),
        stand: .init(value: 12, goal: 12)
    ))
    ActivityEntry(date: .now, rings: ActivityRings.sample.reset(to: .now))
    ActivityEntry(date: .now, rings: nil)
}

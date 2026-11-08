import SwiftUI
import WidgetKit

/// Move, Exercise and Stand as three concentric rings, outermost first, each filling clockwise from the top over a
/// faded track, like the system's Activity complication, but all three in the accent color (on a tinted face, the
/// tint). A ring past its goal laps itself, its head casting a shadow on the lap underneath so the overlap shows.
/// Without rings to show, just the tracks.
/// In `Shared/` so the app's debug gallery and the Activity screen can show it too.
struct ActivityRingsView: View {
    let rings: ActivityRings?
    @Environment(\.complicationAccent) private var accent
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                ring(rings?.move.progress ?? 0, index: 0, side: side)
                ring(rings?.exercise.progress ?? 0, index: 1, side: side)
                ring(rings?.stand.progress ?? 0, index: 2, side: side)
            }
            .widgetAccentable()
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ring(_ progress: Double, index: Int, side: Double) -> some View {
        let width = side * Layout.thickness
        // Of the ring's centerline, which the stroke straddles.
        let diameter = side - width - 2 * Double(index) * (Layout.thickness + Layout.gap) * side
        let lap = progress >= 1 ? progress.truncatingRemainder(dividingBy: 1) : progress
        let angle = 2 * Double.pi * lap
        // Once the head's round cap reaches the start's, the head needs its shadow to stand out.
        let overlaps = progress > 1 - width / (.pi * diameter)
        let style = StrokeStyle(lineWidth: width, lineCap: .round)
        return ZStack {
            Circle().stroke(accent.opacity(Layout.trackOpacity), lineWidth: width)
            if progress >= 1 {
                Circle().stroke(accent, lineWidth: width)
            }
            Circle()
                .trim(from: 0, to: lap)
                .stroke(accent, style: style)
                .rotationEffect(.degrees(-90))
            if overlaps, renderingMode == .fullColor {
                // A copy of the head's cap, its shadow cast forward along the ring; the mask keeps it on the ring.
                Circle()
                    .fill(accent)
                    .frame(width: width, height: width)
                    .shadow(
                        color: .black.opacity(Layout.shadowOpacity),
                        radius: width * Layout.shadowRadius,
                        x: cos(angle) * width * Layout.shadowOffset,
                        y: sin(angle) * width * Layout.shadowOffset
                    )
                    .position(x: diameter / 2 * (1 + sin(angle)), y: diameter / 2 * (1 - cos(angle)))
            }
        }
        .frame(width: diameter, height: diameter)
        .mask(Circle().stroke(lineWidth: width).frame(width: diameter, height: diameter))
    }
}

/// Fractions of the complication's side: three rings filling it, about 5.2 pt thick with 0.9 pt between them on a
/// 41mm watch.
private enum Layout {
    static let thickness = 0.115
    static let gap = 0.02
    /// Matches the track of the system's circular gauges on a tinted face, as the battery outline's does.
    static let trackOpacity = 0.35
    static let shadowOpacity = 0.7
    /// Of the ring's thickness. Offset forward by more than it's blurred, so none falls behind the head.
    static let shadowRadius = 0.18
    static let shadowOffset = 0.3
}

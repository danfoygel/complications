import SwiftUI
import WidgetKit

/// The watch's percent over the phone's, inside a ring split in two: the top half is the watch's battery, the bottom
/// half the phone's. Both halves fill from 9 o'clock, the watch's clockwise over the top and the phone's
/// counter-clockwise under the bottom, so each drains back toward 9 o'clock. A stale phone reading is dimmed rather
/// than hidden; with no reading yet its half is empty.
/// In `Shared/` so the app's debug gallery can show it too.
struct BatteryComplicationView: View {
    let entry: BatteryEntry

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                halfRing(entry.level, tint: .green, isTop: true, side: side)
                halfRing(entry.phone?.level, tint: .blue, isTop: false, side: side)
                    .opacity(isPhoneStale ? 0.4 : 1)
                percent(entry.percent, color: .white, centerY: Layout.watchNumberY, side: side)
                percent(entry.phone?.percent, color: .cyan, centerY: Layout.phoneNumberY, side: side)
                    .opacity(isPhoneStale ? 0.4 : 1)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var isPhoneStale: Bool {
        entry.phone?.isStale(at: entry.date) ?? false
    }

    /// A circle's path starts at 3 o'clock and runs clockwise, so the bottom half is its first half as drawn, and
    /// turning it 180° puts that half on top.
    private func halfRing(_ level: Double?, tint: Color, isTop: Bool, side: Double) -> some View {
        let lineWidth = side * Layout.thickness
        let diameter = side * (1 - Layout.thickness)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        // Each end stops short of 3 and 9 o'clock by half the gap plus its rounded cap, as a share of the
        // circumference.
        let inset = (Layout.gap + Layout.thickness) / 2 / (.pi * (1 - Layout.thickness))
        let start = inset
        let end = 0.5 - inset
        let filled = (end - start) * min(max(level ?? 0, 0), 1)
        return ZStack {
            // A dim shade of the half's color, which tinted faces draw as a dim shade of their tint.
            Circle().trim(from: start, to: end).stroke(tint.opacity(0.3), style: style)
                .widgetAccentable()
            Circle()
                // On top the fill runs on from 9 o'clock; on the bottom it runs back to it.
                .trim(from: isTop ? start : end - filled, to: isTop ? start + filled : end)
                .stroke((level ?? 0) <= 0.1 ? .red : tint, style: style)
                .widgetAccentable()
        }
        .rotationEffect(.degrees(isTop ? 180 : 0))
        .frame(width: diameter, height: diameter)
    }

    private func percent(_ value: Int?, color: Color, centerY: Double, side: Double) -> some View {
        Text(value.map(String.init) ?? "--")
            .font(.system(size: Layout.fontSize, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: side * Layout.textWidth)
            .position(x: side / 2, y: side * centerY)
    }
}

/// Fractions of the complication's side, laid out in the dual battery designer on the 41mm canvas.
private enum Layout {
    /// The ring's outer edge is the complication's edge. 4.5 pt on a 41mm watch, as thick as the system's ring
    /// complications.
    static let thickness = 0.10
    /// Space between the two halves at 3 and 9 o'clock, about 1.3 pt on a 41mm watch.
    static let gap = 0.03
    /// In points, not a fraction: the complication's text is sized for the 41mm watch, where it is 44.5 pt across.
    static let fontSize: CGFloat = 16
    static let watchNumberY = 0.326
    static let phoneNumberY = 0.669
    /// Room for a percent before it shrinks; "100" needs less than full size.
    static let textWidth = 0.62
}

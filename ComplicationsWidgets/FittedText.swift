import SwiftUI
import UIKit

/// One line of text cut off at the last whole character that fits, with no "…": on a complication that space is better
/// spent on another character or two.
///
/// The fit is measured here with Core Text rather than left to SwiftUI layout. The watch face draws a complication's
/// text itself, and with `ViewThatFits` choosing among the prefixes it still drew titles too long for their row and
/// cut them off with "…".
struct FittedText: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let width: CGFloat

    init(_ text: String, size: CGFloat, weight: Font.Weight, width: CGFloat) {
        self.text = text
        self.size = size
        self.weight = weight
        self.width = width
    }

    var body: some View {
        Text(Self.longestPrefix(of: text, size: size, weight: weight, fitting: width))
            .font(.system(size: size, weight: weight))
            .lineLimit(1)
    }

    /// How wide the face draws text compared with Core Text's measure of the same font: measured on the Series 8 as
    /// 0.94–0.946 for the titles, which matches SF Compact Display against SF Compact Text on the Mac.
    static let drawnScale: CGFloat = 0.94

    /// A little room to spare, for the spread in `drawnScale`.
    private static let slack: CGFloat = 1

    /// The longest prefix, without trailing spaces, that fits the width.
    static func longestPrefix(of text: String, size: CGFloat, weight: Font.Weight, fitting width: CGFloat) -> String {
        let prefixes = prefixes(of: text)
        // Prefixes only get narrower, and the last, an empty one, always fits.
        var low = 0
        var high = prefixes.count - 1
        while low < high {
            let middle = (low + high) / 2
            if Self.width(of: prefixes[middle], size: size, weight: weight) <= width - slack {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return prefixes[low]
    }

    /// Every prefix, longest first, without trailing spaces and so without repeats.
    static func prefixes(of text: String) -> [String] {
        var prefixes: [String] = []
        for length in stride(from: text.count, through: 0, by: -1) {
            let prefix = String(text.prefix(length).trimmingCharacters(in: .whitespaces))
            if prefix != prefixes.last {
                prefixes.append(prefix)
            }
        }
        return prefixes
    }

    /// The width the face draws one line of text at in the system font, optionally with monospaced digits as the labels
    /// use.
    static func width(
        of text: String, size: CGFloat, weight: Font.Weight, monospacedDigits: Bool = false,
        drawnScale: CGFloat = drawnScale
    ) -> CGFloat {
        let font = monospacedDigits
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: uiWeight(weight))
            : UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        return CTLineGetTypographicBounds(line, nil, nil, nil) * drawnScale
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .semibold: .semibold
        case .medium: .medium
        case .bold: .bold
        default: .regular
        }
    }
}

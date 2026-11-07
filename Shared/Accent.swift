import SwiftUI

extension AccentColor {
    /// The latest pick the phone sent, or the standard orange.
    static var current: AccentColor {
        saved(in: AppGroup.defaults) ?? .standard
    }
}

extension EnvironmentValues {
    /// What the complications draw their accented parts in on a full-color face. On a tinted face those parts take
    /// the face's tint anyway. Each widget sets it from `AccentColor.current`; previews and the gallery get the
    /// standard orange.
    @Entry var complicationAccent = AccentColor.standard.color
}

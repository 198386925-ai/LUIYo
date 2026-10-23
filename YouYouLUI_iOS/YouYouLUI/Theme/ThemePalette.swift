import UIKit

/// Resolves stored preferences into the dynamic colours the native shells paint.
enum ThemePalette {
    /// Light factory background: the flat colour #EFEFF3 (Build 24 —
    /// it replaced the earlier wallpaper-image default; the bundled
    /// `DefaultWallpaper` asset remains in the catalog, unused).
    /// Surfaces that can only take a solid colour use the same hex.
    static let lightBackground = "#EFEFF3"
    static let darkBackground = "#121214"
    static let lightCard = "#FFFFFF"
    static let darkCard = "#1C1C1E"

    /// Background used by every page before any custom colour is applied.
    /// Light = #EFEFF3, dark keeps its own #121214.
    static let adaptiveBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 20.0 / 255.0, alpha: 1)
            : UIColor(red: 239.0 / 255.0, green: 239.0 / 255.0, blue: 243.0 / 255.0, alpha: 1)
    }

    /// Fill applied to card materials when the platform paints the surface itself.
    static let cardTint = UIColor { $0.userInterfaceStyle == .dark ? UIColor(nativeHex: darkCard) : .white }

    /// Per-appearance stored hex, or nil when the user never customised it.
    static func storedCardHex(isDark: Bool) -> String {
        ThemePreferences.shared.colorHex(.heroCardColor, appearance: isDark ? "dark" : "light")
            ?? (isDark ? darkCard : lightCard)
    }
}

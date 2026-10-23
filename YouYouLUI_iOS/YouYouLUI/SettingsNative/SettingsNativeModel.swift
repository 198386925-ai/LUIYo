import Combine
import UIKit

/// Observable state for the native Settings page.
/// Wraps ThemePreferences (UserDefaults-backed) so the UI stays in sync.
final class SettingsNativeModel: ObservableObject {
    private let prefs = ThemePreferences.shared
    /// Font controller for custom font import. Set by the hosting shell.
    var fontController: ThemeFontController?

    /// Bumped when the native hero card should re-render (theme changes).
    @Published var heroRefreshToken: Int = 0
    /// Set by hero buttons: which fold to scroll to after expanding.
    @Published var pendingScroll: String?
    var onAppearanceChanged: ((String) -> Void)?
    var onCardMaterialChanged: ((String) -> Void)?
    var onColorsChanged: (() -> Void)?
    var onMinimizeChanged: ((Bool) -> Void)?
    var onBottomSearchLayoutChanged: ((String) -> Void)?
    var onFontChanged: (() -> Void)?

    // MARK: - Appearance
    @Published var appearanceMode: String {
        didSet { prefs.appearanceMode = appearanceMode; onAppearanceChanged?(appearanceMode) }
    }

    // MARK: - Card material
    /// "liquid" or "blur"
    @Published var cardMaterial: String {
        didSet { prefs.cardMaterialMode = cardMaterial; onCardMaterialChanged?(cardMaterial) }
    }

    // MARK: - Colors (hex strings)
    // Build 41 removed the 背景颜色 setting and that stays removed:
    // the page background is pinned to the factory flat colour and
    // has no model state. (Build 41 also removed 卡片材质； Build 42
    // restored it above at the user's request.)
    @Published var cardColorHex: String = "#FFFFFF"
    @Published var buttonColorHex: String = "#FFFFFF"

    // MARK: - Bottom search
    @Published var bottomSearchLayout: String {
        didSet { prefs.bottomSearchLayout = bottomSearchLayout; onBottomSearchLayoutChanged?(bottomSearchLayout) }
    }

    // MARK: - Minimize bottom bar (TRUE NATIVE Toggle)
    @Published var minimizeBottomBar: Bool {
        didSet { prefs.minimizeBottomBar = minimizeBottomBar; onMinimizeChanged?(minimizeBottomBar) }
    }

    // MARK: - Custom font
    @Published var customFontName: String = "使用默认字体"
    @Published var hasCustomFont: Bool = false

    // MARK: - Section expansion
    @Published var themeExpanded: Bool = false
    @Published var guideExpanded: Bool = false
    @Published var changelogExpanded: Bool = false

    init() {
        self.appearanceMode = prefs.appearanceMode
        self.cardMaterial = prefs.cardMaterialMode
        self.bottomSearchLayout = prefs.bottomSearchLayout
        self.minimizeBottomBar = prefs.minimizeBottomBar
        // Load saved colors for current appearance
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        if let hex = prefs.colorHex(.heroCardColor, appearance: appearance) {
            self.cardColorHex = hex
        }
        if let hex = prefs.colorHex(.buttonColor, appearance: appearance) {
            self.buttonColorHex = hex
        }
    }

    func resetCardColor() {
        let def = "#FFFFFF"
        cardColorHex = def
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        prefs.setColorHex(def, kind: .heroCardColor, appearance: appearance)
        onColorsChanged?()
    }

    func resetButtonColor() {
        let def = "#FFFFFF"
        buttonColorHex = def
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        prefs.setColorHex(def, kind: .buttonColor, appearance: appearance)
    }

    func updateCardColor(_ hex: String) {
        cardColorHex = hex
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        prefs.setColorHex(hex, kind: .heroCardColor, appearance: appearance)
        onColorsChanged?()
    }
}

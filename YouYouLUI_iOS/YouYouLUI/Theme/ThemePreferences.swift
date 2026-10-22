import Foundation

/// Colour slot persisted per appearance. The raw strings are part of the
/// contract: the bundled HTML and the ObjC hero cell read them directly.
enum ThemeColorKind: String {
    case background
    case buttonColor
    case heroCardColor
}

/// Every `UserDefaults` key the app owns. Never inline a literal elsewhere.
enum PreferenceKey {
    static let appearanceMode = "youyou.appearanceMode"
    static let bottomSearchEnabled = "youyou.bottomSearchEnabled"
    static let bottomSearchLayout = "youyou.bottomSearchLayout"
    static let minimizeBottomBar = "youyou.minimizeBottomBar"
    static let cardMaterialMode = "youyou.cardMaterialMode"
    static let accountSVIP = "youyou.account.svip"
    static let accountSVIPExpiresAt = "youyou.account.svipExpiresAt"
    static let accountEmail = "youyou.account.email"
    static let accountDisplayName = "youyou.account.displayName"
    static let accountLocalDisplayNames = "youyou.account.localDisplayNames"
    static let nativeIconColors = "luiyo.nativeIconColors"

    static func color(_ kind: ThemeColorKind, appearance: String) -> String {
        "youyou." + kind.rawValue + "." + appearance
    }

    /// Keys the CI layout report samples verbatim. Kept separate from the
    /// write keys on purpose — they are diagnostics only.
    static func diagnosticsColor(_ slot: String, appearance: String) -> String {
        "youyou." + slot + "." + appearance
    }
}

extension Notification.Name {
    static let luiyoAccountAuthUpdated = Notification.Name("LUIYoAccountAuthUpdated")
}

/// Typed access to persisted preferences. Also broadcasts account
/// authorization changes so the settings hero card can refresh.
final class ThemePreferences {
    static let shared = ThemePreferences()

    private let defaults = UserDefaults.standard

    func registerDefaults() {
        defaults.register(defaults: [
            PreferenceKey.bottomSearchEnabled: true,
            PreferenceKey.bottomSearchLayout: "separate"
        ])
    }

    var appearanceMode: String {
        get { defaults.string(forKey: PreferenceKey.appearanceMode) ?? "system" }
        set { defaults.set(newValue, forKey: PreferenceKey.appearanceMode) }
    }

    var bottomSearchEnabled: Bool {
        get { defaults.bool(forKey: PreferenceKey.bottomSearchEnabled) }
        set { defaults.set(newValue, forKey: PreferenceKey.bottomSearchEnabled) }
    }

    var bottomSearchLayout: String {
        get { defaults.string(forKey: PreferenceKey.bottomSearchLayout) ?? "separate" }
        set { defaults.set(newValue, forKey: PreferenceKey.bottomSearchLayout) }
    }

    var isSeparateSearch: Bool {
        get { bottomSearchLayout == "separate" }
        set { bottomSearchLayout = newValue ? "separate" : "merged" }
    }

    var minimizeBottomBar: Bool {
        get { defaults.bool(forKey: PreferenceKey.minimizeBottomBar) }
        set { defaults.set(newValue, forKey: PreferenceKey.minimizeBottomBar) }
    }

    /// Card material mode: "liquid" (iOS 26+ liquid glass) or "blur" (native frosted).
    var cardMaterialMode: String {
        get { defaults.string(forKey: PreferenceKey.cardMaterialMode) ?? "liquid" }
        set { defaults.set(newValue, forKey: PreferenceKey.cardMaterialMode) }
    }

    /// Whether the account backend's latest `status` verdict says the
    /// logged-in account holds SVIP (a card is bound). One of the three
    /// mirrors the ObjC hero cell reads; kept in sync by
    /// `AccountAuthorization`, cleared on account logout.
    var accountSVIP: Bool {
        get { defaults.bool(forKey: PreferenceKey.accountSVIP) }
        set {
            guard newValue != accountSVIP else { return }
            defaults.set(newValue, forKey: PreferenceKey.accountSVIP)
            NotificationCenter.default.post(name: .luiyoAccountAuthUpdated, object: nil)
        }
    }

    /// Unix seconds at which the account's SVIP expires (0 = none).
    var accountSVIPExpiresAt: Int {
        get { defaults.integer(forKey: PreferenceKey.accountSVIPExpiresAt) }
        set {
            guard newValue != accountSVIPExpiresAt else { return }
            defaults.set(newValue, forKey: PreferenceKey.accountSVIPExpiresAt)
            NotificationCenter.default.post(name: .luiyoAccountAuthUpdated, object: nil)
        }
    }

    /// The logged-in account's email, mirrored for the hero cell.
    var accountEmail: String? {
        get { defaults.string(forKey: PreferenceKey.accountEmail) }
        set {
            guard newValue != accountEmail else { return }
            if let value = newValue {
                defaults.set(value, forKey: PreferenceKey.accountEmail)
            } else {
                defaults.removeObject(forKey: PreferenceKey.accountEmail)
            }
            NotificationCenter.default.post(name: .luiyoAccountAuthUpdated, object: nil)
        }
    }

    /// The EFFECTIVE display name shown on the hero card, mirrored
    /// for the ObjC hero cell like `accountEmail`. Written only by
    /// `AccountAuthorization`: the server's `display_name` when the
    /// backend has issued one, otherwise the per-account local
    /// fallback (see `localDisplayName(for:)`), so the hero always
    /// has one stable name to show. Cleared on account logout.
    var accountDisplayName: String? {
        get { defaults.string(forKey: PreferenceKey.accountDisplayName) }
        set {
            guard newValue != accountDisplayName else { return }
            if let value = newValue {
                defaults.set(value, forKey: PreferenceKey.accountDisplayName)
            } else {
                defaults.removeObject(forKey: PreferenceKey.accountDisplayName)
            }
            NotificationCenter.default.post(name: .luiyoAccountAuthUpdated, object: nil)
        }
    }

    /// Per-account locally generated fallback display names
    /// (email → `LUI用户XXXX`), in the same format as the server's.
    /// Minted once per account and kept, so until the server's own
    /// name arrives the same account always shows the same name on
    /// this device. The map deliberately survives logout: it is
    /// keyed by account, and a different account gets its own entry.
    func localDisplayName(for email: String) -> String {
        var map = defaults.dictionary(forKey: PreferenceKey.accountLocalDisplayNames) as? [String: String] ?? [:]
        if let existing = map[email], !existing.isEmpty { return existing }
        let name = "LUI用户" + String(format: "%04d", Int.random(in: 0...9999))
        map[email] = name
        defaults.set(map, forKey: PreferenceKey.accountLocalDisplayNames)
        return name
    }

    var nativeIconColors: [String: Any] {
        get { defaults.dictionary(forKey: PreferenceKey.nativeIconColors) ?? [:] }
        set { defaults.set(newValue, forKey: PreferenceKey.nativeIconColors) }
    }

    func colorHex(_ kind: ThemeColorKind, appearance: String) -> String? {
        defaults.string(forKey: PreferenceKey.color(kind, appearance: appearance))
    }

    func setColorHex(_ hex: String, kind: ThemeColorKind, appearance: String) {
        defaults.set(hex, forKey: PreferenceKey.color(kind, appearance: appearance))
    }
}

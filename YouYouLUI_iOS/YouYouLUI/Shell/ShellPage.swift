import Foundation

/// The four content pages, all native and seated in their own tabs.
/// Bubble sits right of home; inserting it renumbers rules/settings —
/// every tab lookup flows from allCases order / rawValue, so no other
/// page's code changes.
enum ShellPage: Int, CaseIterable {
    case home = 0
    case bubble = 1
    case rules = 2
    case settings = 3

    /// Page identifier used by the shell and the search overlay.
    var name: String {
        switch self {
        case .home: return "home"
        case .bubble: return "bubble"
        case .rules: return "rules"
        case .settings: return "settings"
        }
    }

    var title: String {
        switch self {
        case .home: return "首页"
        case .bubble: return "气泡包"
        case .rules: return "规则"
        case .settings: return "我的"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "house"
        case .bubble: return "bubble.left.and.bubble.right"
        case .rules: return "list.bullet.rectangle"
        case .settings: return "person.crop.circle"
        }
    }

    var selectedIconName: String {
        switch self {
        case .home: return "house.fill"
        case .bubble: return "bubble.left.and.bubble.right.fill"
        case .rules: return "list.bullet.rectangle.fill"
        case .settings: return "person.crop.circle.fill"
        }
    }

    /// Stable identifier of the UIKit `UITab` that hosts this page.
    var tabIdentifier: String { "page." + String(rawValue) }

    init?(name: String) {
        guard let page = ShellPage.allCases.first(where: { $0.name == name }) else { return nil }
        self = page
    }

    init(clamping tag: Int) {
        self = ShellPage(rawValue: min(max(tag, 0), 3)) ?? .home
    }
}

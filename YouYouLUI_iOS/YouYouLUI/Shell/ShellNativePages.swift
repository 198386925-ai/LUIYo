import UIKit
import ObjectiveC

/// Native page models + hosts for the UIKit Settings and Rules pages.
/// Hosts are seated per-tab by ShellWebPlacement.keepContentBelowNativeBar().
extension MainShellViewController {
    /// The shared Settings model, created once and wired to the shell.
    var settingsModel: SettingsNativeModel {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.settingsModel) as? SettingsNativeModel {
            return existing
        }
        let model = SettingsNativeModel()
        model.fontController = self.fontController
        model.hasCustomFont = self.fontController.library.hasAnyCustomSelection
        model.customFontName = self.fontController.library.summary()
        model.onAppearanceChanged = { [weak self] mode in self?.applyAppearance(mode) }
        model.onCardMaterialChanged = { [weak self] mode in self?.setCardMaterialMode(mode) }
        model.onColorsChanged = { [weak self] in self?.applyStoredPalette() }
        model.onMinimizeChanged = { [weak self] enabled in self?.setScrollMinimize(enabled) }
        model.onBottomSearchLayoutChanged = { [weak self] layout in
            guard let self else { return }
            let enabled = layout != "off"
            let separate = layout == "separate"
            if enabled != self.bottomSearchEnabled || separate != self.separateSearch {
                self.bottomSearchEnabled = enabled
                self.separateSearch = separate
                self.preferences.bottomSearchEnabled = enabled
                self.preferences.isSeparateSearch = separate
                UIView.performWithoutAnimation { self.refreshTabItems() }
                // The home page shows its own search box only while the
                // bottom search is off; refresh its theme right away or the
                // switch only takes effect after a relaunch.
                self.refreshHomeTheme()
            }
        }
        model.onFontChanged = { [weak self] in
            guard let self else { return }
            self.distributeFonts()
            model.customFontName = self.fontController.library.summary()
            model.hasCustomFont = self.fontController.library.hasAnyCustomSelection
        }
        objc_setAssociatedObject(self, &AssociatedKeys.settingsModel, model, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return model
    }

    /// The shared Rules model (the shell's bottom search writes its query).
    var rulesModel: RulesNativeModel {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.rulesModel) as? RulesNativeModel {
            return existing
        }
        let model = RulesNativeModel()
        objc_setAssociatedObject(self, &AssociatedKeys.rulesModel, model, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return model
    }

    /// Returns the Settings page controller, creating it once.
    var settingsHost: SettingsViewController {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.settingsHost) as? SettingsViewController {
            return existing
        }
        let controller = SettingsViewController(model: settingsModel, homeModel: homeModel)
        controller.view.backgroundColor = .clear
        controller.applyPageFont(self.fontController.font(for: .settings))
        objc_setAssociatedObject(self, &AssociatedKeys.settingsHost, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }

    /// Returns the Rules page controller, creating it once.
    var rulesHost: RulesViewController {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.rulesHost) as? RulesViewController {
            return existing
        }
        let controller = RulesViewController(model: rulesModel, homeModel: homeModel)
        controller.view.backgroundColor = .clear
        controller.applyPageFont(self.fontController.font(for: .rules))
        objc_setAssociatedObject(self, &AssociatedKeys.rulesHost, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }

    /// The Settings host if it has been created already (never creates it).
    var existingSettingsHost: SettingsViewController? {
        objc_getAssociatedObject(self, &AssociatedKeys.settingsHost) as? SettingsViewController
    }

    /// The Rules host if it has been created already (never creates it).
    var existingRulesHost: RulesViewController? {
        objc_getAssociatedObject(self, &AssociatedKeys.rulesHost) as? RulesViewController
    }

    /// Re-renders the native hero card after name/avatar changes.
    func notifyHeroNeedsRefresh() {
        guard let model = objc_getAssociatedObject(self, &AssociatedKeys.settingsModel) as? SettingsNativeModel else { return }
        model.heroRefreshToken += 1
    }
}

/// Associated object keys for the native page hosts and models.
private enum AssociatedKeys {
    static var settingsHost = "settingsHost"
    static var rulesHost = "rulesHost"
    static var settingsModel = "settingsModel"
    static var rulesModel = "rulesModel"
}

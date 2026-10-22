import UIKit

extension MainShellViewController {
    /// Applies light / dark / system and persists the choice.
    func applyAppearance(_ rawMode: String) {
        let mode = ["light", "dark"].contains(rawMode) ? rawMode : "system"
        preferences.appearanceMode = mode
        let style = Self.savedAppearanceStyle
        overrideUserInterfaceStyle = style
        view.window?.overrideUserInterfaceStyle = style
        applyStoredPalette()
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Recomputes the homepage theme from the natively stored palette: page
    /// background, card colour, dark flag and the bottom-search visibility.
    func refreshHomeTheme() {
        let dark = traitCollection.userInterfaceStyle == .dark
        let appearance = dark ? "dark" : "light"
        var theme = NativeHomeTheme()
        theme.background = preferences.colorHex(.background, appearance: appearance)
            ?? (dark ? ThemePalette.darkBackground : ThemePalette.lightBackground)
        theme.card = ThemePalette.storedCardHex(isDark: dark)
        theme.dark = dark
        theme.bottomSearchEnabled = preferences.bottomSearchEnabled
        if homeModel.theme != theme { homeModel.theme = theme }
    }

    static var savedAppearanceStyle: UIUserInterfaceStyle {
        switch ThemePreferences.shared.appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }

    /// The factory default background is now a flat colour
    /// (#EFEFF3 light / #121214 dark — see ThemePalette); there is
    /// no default wallpaper image anymore. This pass only guarantees
    /// the seat stays empty: any image a previous build placed here
    /// (or mirrored into `homeModel.backgroundImage` for Home / the
    /// rules page / the search overlay) is cleared, so every page
    /// paints the solid palette colour. A stored custom colour
    /// always wins via `applyStoredPalette()`. (The bundled
    /// `DefaultWallpaper` asset stays in the catalog, unused.)
    func refreshDefaultWallpaper() {
        if backgroundImageView.image != nil {
            backgroundImageView.image = nil
        }
        if homeModel.backgroundImage != nil {
            homeModel.backgroundImage = nil
        }
    }

    /// Re-resolves every stored colour after an appearance change.
    func applyStoredPalette() {
        refreshDefaultWallpaper()
        view.backgroundColor = ThemePalette.stored(.background,
                                                  lightDefault: ThemePalette.lightBackground,
                                                  darkDefault: ThemePalette.darkBackground)
        nativeHomeHost?.view.backgroundColor = view.backgroundColor
        refreshHero()
        refreshHomeTheme()
    }

    // MARK: - Update progress pill

    /// Builds the floating download-progress pill and subscribes it
    /// to the shared update checker. This is the implementation of
    /// the 检查更新 page's "show update progress" switch: while a
    /// download runs, the pill floats above the tab bar in the
    /// shell, so progress stays visible after the user leaves the
    /// page. (The project ships no Live Activity extension — the
    /// pill is an in-app presentation, not a fake Live Activity.)
    func installUpdateProgressPill() {
        let pill = UIView()
        pill.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        pill.layer.cornerRadius = 17
        pill.isUserInteractionEnabled = false
        pill.alpha = 0
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        let bar = UIProgressView(progressViewStyle: .default)
        bar.tintColor = .white
        bar.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        let stack = UIStackView(arrangedSubviews: [label, bar])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        pill.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -7),
            bar.widthAnchor.constraint(equalToConstant: 130),
        ])
        view.addSubview(pill)
        pill.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -76),
        ])
        updateProgressPill = pill
        updateProgressLabel = label
        updateProgressBar = bar
        updateProgressCancellable = AppUpdateChecker.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshUpdateProgressPill() }
            }
        refreshUpdateProgressPill()
    }

    func refreshUpdateProgressPill() {
        guard let pill = updateProgressPill else { return }
        let updater = AppUpdateChecker.shared
        let visible = UpdateSettings.showProgress && updater.phase == .downloading
        if visible {
            updateProgressLabel?.text = "正在下载更新 \(Int(updater.downloadProgress * 100))%"
            updateProgressBar?.progress = Float(updater.downloadProgress)
        }
        let shown = pill.alpha > 0
        guard shown != visible else { return }
        UIView.animate(withDuration: 0.25) { pill.alpha = visible ? 1 : 0 }
    }

    /// Re-renders the settings hero card (name, version, tier, avatar, colours, font).
    func refreshHero() {
        notifyHeroNeedsRefresh()
        guard let hero = settingsHero else { return }
        LUIYoRefreshSettingsHero(hero)
        LUIYoSetSettingsHeroFont(hero, fontController.font)
    }

    func setCardMaterialMode(_ rawMode: String) {
        homeModel.useBlur = rawMode == "blur"
    }

    /// Applies the theme font to the tab bar, the search overlay, the hero card
    /// and every native control the material layer draws.
    func applyFont(_ font: UIFont?) {
        // Change title fonts only; retain all UIKit Liquid Glass/background settings.
        if let base = defaultTabAppearance?.copy() as? UITabBarAppearance {
            Self.applyFont(font, to: base)
            tabBar.standardAppearance = base
            if let edge = defaultScrollEdgeAppearance?.copy() as? UITabBarAppearance {
                Self.applyFont(font, to: edge)
                tabBar.scrollEdgeAppearance = edge
            }
        }
        for item in tabBar.items ?? [] {
            let attributes: [NSAttributedString.Key: Any]? = font.map { [.font: $0] }
            item.setTitleTextAttributes(attributes, for: .normal)
            item.setTitleTextAttributes(attributes, for: .selected)
        }
        updateTabLabelFonts(in: tabBar)
        activeSearchController?.themeFont = font
        // Apply theme font to the settings hero card (native view).
        if let hero = settingsHero { LUIYoSetSettingsHeroFont(hero, font) }
        tabBar.setNeedsLayout()
    }


    /// Pushes each area's chosen font to its page: tab bar, hero and the
    /// settings page use the settings font; home and the search overlay use
    /// the home font; the rules page uses the rules font.
    func distributeFonts() {
        let settingsFont = fontController.font(for: .settings)
        applyFont(settingsFont)
        let homeFont = fontController.font(for: .home)
        homeModel.importedFont = homeFont
        homeModel.fontName = homeFont?.fontName
        activeSearchController?.themeFont = homeFont
        existingSettingsHost?.applyPageFont(settingsFont)
        existingRulesHost?.applyPageFont(fontController.font(for: .rules))
    }

    private static func applyFont(_ font: UIFont?, to appearance: UITabBarAppearance) {
        guard let font else { return }
        for layout in [appearance.stackedLayoutAppearance,
                       appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            var normal = layout.normal.titleTextAttributes
            var selected = layout.selected.titleTextAttributes
            normal[.font] = font
            selected[.font] = font
            layout.normal.titleTextAttributes = normal
            layout.selected.titleTextAttributes = selected
        }
    }

    /// Keeps tab titles at their original size when a decorative font is imported.
    func updateTabLabelFonts(in view: UIView) {
        if let label = view as? UILabel, let text = label.text,
           ["首页", "规则", "设置", "搜索", "Search"].contains(text) {
            if originalTabLabelFonts.object(forKey: label) == nil {
                let original = fontController.font == nil ? label.font! : UIFont.systemFont(ofSize: label.font.pointSize)
                originalTabLabelFonts.setObject(original, forKey: label)
            }
            if let original = originalTabLabelFonts.object(forKey: label) {
                let desired = fontController.font?.withSize(original.pointSize) ?? original
                if label.font != desired { label.font = desired }
            }
        }
        for child in view.subviews { updateTabLabelFonts(in: child) }
    }
}

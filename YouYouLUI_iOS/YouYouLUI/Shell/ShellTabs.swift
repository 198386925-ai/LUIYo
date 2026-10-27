import UIKit

extension MainShellViewController {
    /// Persists and applies the bottom-search entry visibility.
    func setBottomSearchEnabled(_ enabled: Bool) {
        preferences.bottomSearchEnabled = enabled
        bottomSearchEnabled = enabled
        refreshTabItems()
    }

    /// Rebuilds the tab bar. Called whenever search visibility or layout changes.
    func refreshTabItems() {
        if #available(iOS 18.0, *) {
            // UIKit owns the complete bar geometry, including the detached
            // search surface. Never shrink the bar or position a glass button
            // using separate width, height or safe-area offsets.
            // A UITab owns its provider's UIViewController. The old implementation
            // returned the SAME pageControllers every time tabs were rebuilt.
            // UIKit asserts inside -[UITab viewController] when an already-owned
            // controller is handed to a newly created UITab (see device .ips).
            // Give each newly-created tab its own, never-before-owned controller.
            var nativeTabs = pageTabs.enumerated().map { index, item -> UITab in
                let identifier = "page.\(index)"
                if let existing = retainedTabs[identifier] as? UITab { return existing }
                let controller = UIViewController()
                controller.view.backgroundColor = .clear
                let tab = UITab(title: item.title ?? "", image: item.image, identifier: identifier) { _ in controller }
                retainedTabs[identifier] = tab
                return tab
            }
            if bottomSearchEnabled {
                let controller = UIViewController()
                controller.view.backgroundColor = .clear
                if separateSearch {
                    let search = UISearchTab { _ in controller }
                    if #available(iOS 26.0, *) { search.automaticallyActivatesSearch = false }
                    nativeTabs.append(search)
                } else {
                    nativeTabs.append(UITab(title: "搜索", image: UIImage(systemName: "magnifyingglass"),
                                            identifier: "action.search") { _ in controller })
                }
            }
            setTabs(nativeTabs, animated: false)
        } else {
            setViewControllers(pageControllers + (bottomSearchEnabled ? [searchTabController] : []), animated: false)
        }
        // Keep the shared WebKit document alive while native tabs change.
        selectPage(activePage)
        for (index, item) in (tabBar.items ?? []).enumerated() { item.tag = index }
        distributeFonts()
        keepContentBelowNativeBar()
        view.setNeedsLayout()
        updateLayoutMetrics(force: true)
    }

    /// Selects a page without triggering navigation (used while rebuilding tabs).
    func selectPage(_ page: ShellPage) {
        activePage = page
        if #available(iOS 18.0, *) {
            selectedTab = tabs.first { $0.identifier == page.tabIdentifier }
        } else if pageControllers.indices.contains(page.rawValue) {
            selectedViewController = pageControllers[page.rawValue]
        }
        keepContentBelowNativeBar()
    }

    /// User tapped a content tab. Returns false when the shell handles the switch itself.
    func preparePageSelection(_ tag: Int) -> Bool {
        let page = ShellPage(clamping: tag)
        guard nativeHomeReady, page != activePage else { return true }
        pageSwitchGeneration += 1
        switchingPage = true
        UIView.performWithoutAnimation {
            self.selectPage(page)
            self.updatePageScroll(page)
        }
        keepContentBelowNativeBar()
        switchingPage = false
        return false
    }

    /// Navigates after a tab change driven by UIKit.
    func navigateFromNativeTab(_ tag: Int) {
        let page = ShellPage(clamping: tag)
        activePage = page
        updatePageScroll(page)
        keepContentBelowNativeBar()
    }

    func setScrollMinimize(_ enabled: Bool) {
        scrollMinimizeEnabled = enabled
        preferences.minimizeBottomBar = enabled
        if #available(iOS 26.0, *) { tabBarMinimizeBehavior = enabled ? .onScrollDown : .never }
    }

    /// Build 12: show or hide the four page tab titles. Off = icons only;
    /// the search button is a separate control and is untouched.
    /// Build 13: the bar actually shows UITabs cached in retainedTabs
    /// (titles copied from pageTabs at creation), so sync them too —
    /// changing pageTabs alone only took effect after relaunch.
    func setTabTitlesVisible(_ visible: Bool) {
        for (page, item) in zip(ShellPage.allCases, pageTabs) {
            item.title = visible ? page.title : nil
        }
        if #available(iOS 18.0, *) {
            for (index, page) in ShellPage.allCases.enumerated() {
                (retainedTabs["page.\(index)"] as? UITab)?.title = visible ? page.title : ""
            }
        }
    }
}

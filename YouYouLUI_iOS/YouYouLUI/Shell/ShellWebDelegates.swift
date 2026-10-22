import UIKit

// MARK: - Tab bar delegate

extension MainShellViewController: UITabBarControllerDelegate {
    // Build 21: tap feedback lives ONLY in the shouldSelect
    // callbacks — UIKit calls those exclusively for genuine user
    // taps. The didSelect callbacks also fire for PROGRAMMATIC
    // selection (the shell selecting the initial/restored tab
    // while it is being built at launch), and tapping there played
    // a click as the user merely entered the app. When
    // `preparePageSelection` returns false the shell performed the
    // switch itself inside shouldSelect, so the feedback for that
    // tap is played here; when it returns true there was no switch
    // to feed back (already on the page).
    func tabBarController(_ tabBarController: UITabBarController,
                          shouldSelect viewController: UIViewController) -> Bool {
        AppFeedback.arm()
        if viewController === searchTabController {
            // Action-only item: keep the currently selected page.
            AppFeedback.tap()
            presentBottomSearch()
            return false
        }
        guard let tag = pageControllers.firstIndex(of: viewController) else { return true }
        let handled = preparePageSelection(tag)
        if !handled { AppFeedback.tap() }
        return handled
    }

    func tabBarController(_ tabBarController: UITabBarController,
                          didSelect viewController: UIViewController) {
        if #available(iOS 18.0, *) { return }
        if viewController === searchTabController {
            selectPage(activePage)
            presentBottomSearch()
            return
        }
        guard let tag = pageControllers.firstIndex(of: viewController) else { return }
        navigateFromNativeTab(tag)
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        AppFeedback.arm()
        if tab is UISearchTab || tab.identifier == "action.search" {
            // Both native entries open the same full-screen search page.
            // Keep the content tab selected so closing search restores it.
            AppFeedback.tap()
            presentBottomSearch()
            return false
        }
        guard let tag = Int(tab.identifier.replacingOccurrences(of: "page.", with: "")) else { return true }
        let handled = preparePageSelection(tag)
        if !handled { AppFeedback.tap() }
        return handled
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController,
                          didSelectTab selectedTab: UITab,
                          previousTab: UITab?) {
        // No feedback here: this callback also fires when the
        // shell selects a tab programmatically (launch restore,
        // rebuilds). The genuine-tap click is played in
        // shouldSelectTab above.
        guard let tag = Int(selectedTab.identifier.replacingOccurrences(of: "page.", with: "")) else { return }
        navigateFromNativeTab(tag)
    }
}

import UIKit

// MARK: - Tab bar delegate

extension MainShellViewController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController,
                          shouldSelect viewController: UIViewController) -> Bool {
        if viewController === searchTabController {
            // Action-only item: keep the currently selected page.
            presentBottomSearch()
            return false
        }
        guard let tag = pageControllers.firstIndex(of: viewController) else { return true }
        return preparePageSelection(tag)
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
        if tab is UISearchTab || tab.identifier == "action.search" {
            // Both native entries open the same full-screen search page.
            // Keep the content tab selected so closing search restores it.
            presentBottomSearch()
            return false
        }
        guard let tag = Int(tab.identifier.replacingOccurrences(of: "page.", with: "")) else { return true }
        return preparePageSelection(tag)
    }

    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController,
                          didSelectTab selectedTab: UITab,
                          previousTab: UITab?) {
        guard let tag = Int(selectedTab.identifier.replacingOccurrences(of: "page.", with: "")) else { return }
        navigateFromNativeTab(tag)
    }
}

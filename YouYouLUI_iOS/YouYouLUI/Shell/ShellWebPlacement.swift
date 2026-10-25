import UIKit

/// Tracks whether home has been shown (skip animation on first launch)
private var hasShownHomeOnce = false

extension MainShellViewController {
    /// Seats the active native page inside the selected tab. All three pages
    /// are native; nothing else shares their space.
    func keepContentBelowNativeBar() {
        guard isViewLoaded, let parent = selectedViewController, let host = parent.view else { return }
        switch activePage {
        case .bubble:
            attachNativePage(bubbleHost, to: parent, host: host)
            // 气泡包页不绑滚动缩小：它的底栏必须固定在底部、永远可见，
            // 不随内容滚动消失（其它页仍按“滚动时缩小底栏”开关正常绑定）。
        case .rules:
            attachNativePage(rulesHost, to: parent, host: host)
            bindNativeContentScroll(rulesHost.view, parent: parent)
        case .settings:
            attachNativePage(settingsHost, to: parent, host: host)
            bindNativeContentScroll(settingsHost.view, parent: parent)
        case .home:
            attachNativeHome(to: parent, host: host)
            if let scroll = nativeHomeScrollView,
               boundScrollViews[ObjectIdentifier(parent)] !== scroll {
                if #available(iOS 18.0, *) { parent.setContentScrollView(scroll, for: .bottom) }
                boundScrollViews[ObjectIdentifier(parent)] = scroll
            }
        }
    }

    /// Kept for the existing call sites; the floating bar no longer needs to
    /// publish its position anywhere.
    func updateLayoutMetrics(force: Bool = false) {}

    func updatePageScroll(_ page: ShellPage) {
        activePage = page
        keepContentBelowNativeBar()
    }

    /// The homepage host, seated in its own tab like the other native pages.
    private func attachNativeHome(to parent: UIViewController, host: UIView) {
        let visible = activePage == .home && (activeSearchController == nil || activeSearchPage == "home")
        guard visible else {
            nativeHomeHost?.view.isHidden = true
            nativeHomeHost?.view.accessibilityElementsHidden = true
            return
        }
        if nativeHomeHost == nil {
            let controller = HomeViewController()
            controller.model = homeModel
            controller.view.backgroundColor = backgroundImageView.image == nil ? view.backgroundColor : .clear
            nativeHomeHost = controller
        }
        guard let controller = nativeHomeHost else { return }
        if controller.parent == nil {
            parent.addChild(controller)
            host.addSubview(controller.view)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            nativeHomeConstraints = [
                controller.view.topAnchor.constraint(equalTo: host.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                controller.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: host.trailingAnchor)
            ]
            NSLayoutConstraint.activate(nativeHomeConstraints)
            controller.didMove(toParent: parent)
        }
        controller.view.isHidden = !visible
        controller.view.accessibilityElementsHidden = !visible
        if visible {
            if !hasShownHomeOnce {
                hasShownHomeOnce = true
            } else {
                homeModel.homeAppearCount += 1
            }
        }
    }
}

// MARK: - Native page seating (route A)

extension MainShellViewController {
    /// Seats a native page host inside its tab, mirroring attachNativeHome.
    func attachNativePage(_ controller: UIViewController, to parent: UIViewController, host: UIView) {
        if controller.parent == nil {
            parent.addChild(controller)
            host.addSubview(controller.view)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: host.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                controller.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: host.trailingAnchor)
            ])
            controller.didMove(toParent: parent)
        }
        controller.view.isHidden = false
        controller.view.alpha = 1
    }

    /// Binds the native page's scroll view for the bottom-bar behaviours.
    func bindNativeContentScroll(_ contentView: UIView, parent: UIViewController) {
        guard let scroll = Self.findScrollView(in: contentView) else { return }
        if boundScrollViews[ObjectIdentifier(parent)] !== scroll {
            if #available(iOS 18.0, *) { parent.setContentScrollView(scroll, for: .bottom) }
            boundScrollViews[ObjectIdentifier(parent)] = scroll
        }
    }

    private static func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }
}

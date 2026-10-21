import UIKit

/// The app's entry door (Build 14): chooses and hosts the launch
/// experience in the MAIN window, routes by the persisted ACCOUNT
/// state, and only installs the real app (`AppRoot`) once the account
/// gate has been passed.
///
/// - No account token → splash 03 （粒子聚合）, a hard gate: it never
///   dismisses itself; its 立即注册 button presents the register/login
///   page modally, and closing that page without a successful
///   register/login returns here. There is no other way in.
/// - Token present → splash 04 （玻璃呼吸）: a `status` heartbeat runs
///   behind the design timeline; the splash plays once (~3.6 s incl.
///   stageOut) and dissolves into the home shell. A banned verdict
///   swaps in the blocking ban page instead; an invalid/kicked token
///   is cleared and the flow falls back to the 03 gate; a network
///   failure fails open into home (the shell keeps its own state).
///
/// The OLD device-code activation system is untouched by this build:
/// it lives inside `AppRoot`'s controller exactly as before, and the
/// account gate is purely the door in front of it.
final class EntryGateViewController: UIViewController {
    private var contentViewController: UIViewController?
    private var splash03: Splash03ViewController?
    private var splash04: Splash04ViewController?
    private var bannedController: BannedViewController?
    private var began = false
    private var statusVerdict: AccountStatus?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = splashHex("#6a54c8")
        NotificationCenter.default.addObserver(
            self, selector: #selector(startIfNeeded),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startIfNeeded()
    }

    override var childForStatusBarStyle: UIViewController? { contentViewController }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    @objc private func startIfNeeded() {
        guard !began, isViewLoaded, view.window != nil,
              UIApplication.shared.applicationState == .active else { return }
        began = true
        if AccountSession.isLoggedIn {
            showSplash04()
        } else {
            showSplash03()
        }
    }

    // MARK: Splash 03 gate

    private func showSplash03() {
        let splash = Splash03ViewController()
        splash.onRegisterTap = { [weak self] in self?.presentAccount() }
        embed(splash)
        splash03 = splash
        splash.begin()
    }

    private func presentAccount() {
        let account = AccountViewController()
        account.onClose = { [weak self] in
            self?.dismiss(animated: true)
        }
        account.onAuthenticated = { [weak self] in
            self?.accountAuthenticated()
        }
        account.modalPresentationStyle = .overFullScreen
        account.modalTransitionStyle = .crossDissolve
        present(account, animated: true)
    }

    private func accountAuthenticated() {
        dismiss(animated: true) { [weak self] in
            self?.installContent()
        }
    }

    // MARK: Splash 04 + status verdict

    private func showSplash04() {
        let splash = Splash04ViewController()
        embed(splash)
        splash04 = splash
        splash.begin()
        AccountAPI.fetchStatus { [weak self] status in
            self?.statusVerdict = status
            self?.applyVerdict()
        }
    }

    private func applyVerdict() {
        guard let splash = splash04, let verdict = statusVerdict else { return }
        switch verdict {
        case .ok, .unreachable:
            // The splash's own finish() keeps stageOut on the design
            // timeline (never before 10t); content installs as the
            // stage dissolves.
            splash.finish { [weak self] in
                self?.installContent()
            }
        case .banned(let title, let subtitle, let reason):
            splash.fadeOutQuickly { [weak self] in
                guard let self else { return }
                remove(self.splash04)
                self.splash04 = nil
                showBanned(title: title, subtitle: subtitle, reason: reason)
            }
        case .invalid:
            AccountSession.clear()
            splash.fadeOutQuickly { [weak self] in
                guard let self else { return }
                remove(self.splash04)
                self.splash04 = nil
                showSplash03()
            }
        }
    }

    private func showBanned(title: String, subtitle: String, reason: String) {
        let banned = BannedViewController(
            banTitle: title, banSubtitle: subtitle, banReason: reason,
            buttonTitle: "退出账号")
        banned.onButton = { [weak self] in
            guard let self else { return }
            AccountSession.clear()
            remove(bannedController)
            bannedController = nil
            showSplash03()
        }
        embed(banned)
        bannedController = banned
    }

    // MARK: Content install

    /// Installs the real app over/under the splash and removes the
    /// splash. With a splash up we crossfade: content slides under
    /// the splash, the splash fades, then leaves the hierarchy.
    private func installContent() {
        guard contentViewController == nil else { return }
        let content = AppRoot.makeRootViewController()
        contentViewController = content
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let splash = splash03 {
            view.insertSubview(content.view, belowSubview: splash.view)
        } else if let splash = splash04 {
            view.insertSubview(content.view, belowSubview: splash.view)
        } else {
            view.addSubview(content.view)
        }
        content.didMove(toParent: self)
        setNeedsStatusBarAppearanceUpdate()
        splash03?.shutdown()
        let splash = splash03 ?? splash04
        splash03 = nil
        splash04 = nil
        guard let splash else { return }
        UIView.animate(withDuration: 0.45, animations: {
            splash.view.alpha = 0
        }, completion: { _ in
            self.remove(splash)
        })
    }

    // MARK: Child plumbing

    private func embed(_ controller: UIViewController) {
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    private func remove(_ controller: UIViewController?) {
        guard let controller else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }
}

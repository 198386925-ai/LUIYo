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
/// - Token present → splash 04 （玻璃呼吸）: a `status` check runs
///   behind the design timeline; the splash plays once (~3.6 s incl.
///   stageOut) and dissolves into the home shell. The wait for the
///   verdict is capped at 1.5 s (Build 40): past that, the shell
///   installs with the cached account state and the verdict, when
///   it lands, is applied exactly like a heartbeat verdict. A 7 s
///   backstop abandons a still-pending launch request and forces
///   one fresh check with a 5 s timeout. A banned verdict
///   swaps in the blocking red ban popup instead (Build 20: the
///   same fig2 popup as the version ban — the plain ban page is
///   gone); an invalid/kicked token is cleared and the flow falls
///   back to the 03 gate; a network failure fails open into home
///   (the shell keeps its own state). Once home is installed, a
///   mid-session heartbeat re-checks `status` every 30 s (and on
///   every return to the foreground), so an account banned
///   mid-session gets the same red popup without waiting for the
///   next launch — and a kicked token drops back to the 03 gate.
///
/// The account system is the app's only authorization system: every
/// `status` verdict also feeds `AccountAuthorization` (SVIP state
/// from the same payload), which the gate pushes into the installed
/// shell — the launch check, the post-login refresh and the 30 s
/// heartbeat all keep the home status row, the hero chip and the
/// export-ZIP gate in sync.
final class EntryGateViewController: UIViewController {
    private var contentViewController: UIViewController?
    private var splash03: Splash03ViewController?
    private var splash04: Splash04ViewController?
    private var accountBanController: VersionPopupViewController?
    private var heartbeatTimer: Timer?
    private var began = false
    private var statusVerdict: AccountStatus?
    private var launchWaitCap: DispatchWorkItem?
    private var enteredPendingVerdict = false
    private var launchBackstop: DispatchWorkItem?
    private var launchVerdictResolved = false
    private var launchFetchGeneration = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        // The gate's own background is only visible in the frames
        // before the splash child embeds (the splash is embedded
        // from viewDidAppear), so it wears the incoming splash's
        // own base colour — Splash04 paints #7698db behind its
        // gradient, Splash03 paints #768bbf (Build 44: both bases
        // lightened with the splash gradients, 34% toward white).
        // Build 42: this used to be a solid #6a54c8 (the purple end
        // stop of both splash gradients), which flashed as a
        // full-screen purple moment at every launch before the
        // splash composed.
        view.backgroundColor = splashHex(AccountSession.isLoggedIn ? "#7698db" : "#768bbf")
        NotificationCenter.default.addObserver(
            self, selector: #selector(startIfNeeded),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(foregroundHeartbeat),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(accountLoggedOut),
            name: .accountSessionDidLogout, object: nil)
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
        view.backgroundColor = splashHex("#768bbf")
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

    // MARK: Account logout (from the settings 我的 page)

    /// The account session was cleared in settings: tear everything
    /// down — presented pages, the installed app, any splash — and
    /// put the 03 register gate back up. The next launch lands here
    /// too (no token). The session clear has already reset the
    /// authorization mirrors (see `AccountSession.clear()`).
    @objc private func accountLoggedOut() {
        tearDownToGate()
    }

    /// Tears everything down — presented pages, the installed app,
    /// any splash, the ban popup, the heartbeat — and puts the 03
    /// register gate back up. Shared by the settings logout, the
    /// ban popup's 退出 and a mid-session kicked verdict. (Callers
    /// clear the account session first, which also resets
    /// `AccountAuthorization` — see `AccountSession.clear()`.)
    private func tearDownToGate() {
        stopHeartbeat()
        launchWaitCap?.cancel()
        launchWaitCap = nil
        launchBackstop?.cancel()
        launchBackstop = nil
        launchVerdictResolved = true
        launchFetchGeneration += 1
        enteredPendingVerdict = false
        if presentedViewController != nil {
            dismiss(animated: false)
        }
        splash03?.shutdown()
        remove(splash03)
        splash03 = nil
        remove(splash04)
        splash04 = nil
        remove(accountBanController)
        accountBanController = nil
        remove(contentViewController)
        contentViewController = nil
        statusVerdict = nil
        showSplash03()
    }

    // MARK: Splash 04 + status verdict

    private func showSplash04() {
        view.backgroundColor = splashHex("#7698db")
        let splash = Splash04ViewController()
        embed(splash)
        splash04 = splash
        splash.begin()
        enteredPendingVerdict = false
        launchVerdictResolved = false
        launchFetchGeneration += 1
        let generation = launchFetchGeneration
        AccountAPI.fetchStatus { [weak self] status in
            guard let self, self.launchFetchGeneration == generation,
                  !self.launchVerdictResolved else { return }
            self.launchVerdictResolved = true
            self.launchBackstop?.cancel()
            self.launchBackstop = nil
            if self.enteredPendingVerdict {
                self.enteredPendingVerdict = false
                self.applyLateLaunchVerdict(status)
            } else {
                self.statusVerdict = status
                self.applyVerdict()
            }
        }
        // Build 40 （方案二）: cap the launch wait at 1.5 s. If the
        // verdict has not landed by then, enter with the cached
        // account state and let the verdict land in the background.
        // The splash's own 10t minimum keeps the total entry time
        // at the animation's length either way.
        let cap = DispatchWorkItem { [weak self] in self?.enterWithCachedState() }
        launchWaitCap = cap
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: cap)
        // Build 40 backstop: at 7 s after launch, a still-pending
        // launch request is abandoned and one fresh check with a
        // short timeout is forced (see resolveLaunchWindow).
        let backstop = DispatchWorkItem { [weak self] in self?.resolveLaunchWindow() }
        launchBackstop = backstop
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: backstop)
    }

    /// The 7 s launch-window backstop: abandon the pending launch
    /// request (the generation bump makes its completion a no-op
    /// whenever it eventually returns) and issue one fresh status
    /// check with a 5 s timeout. Its verdict is applied the moment
    /// it lands, through the same paths as the original request.
    /// If the forced check also fails, the cached state stands and
    /// the steady 30 s heartbeat owns the verdict from here — the
    /// launch window is over either way.
    private func resolveLaunchWindow() {
        guard !launchVerdictResolved else { return }
        launchFetchGeneration += 1
        let generation = launchFetchGeneration
        AccountAPI.fetchStatus(timeout: 5) { [weak self] status in
            guard let self, self.launchFetchGeneration == generation,
                  !self.launchVerdictResolved else { return }
            self.launchVerdictResolved = true
            if self.enteredPendingVerdict {
                self.enteredPendingVerdict = false
                self.applyLateLaunchVerdict(status)
            } else {
                self.statusVerdict = status
                self.applyVerdict()
            }
        }
    }

    private func applyVerdict() {
        guard let splash = splash04, let verdict = statusVerdict else { return }
        launchWaitCap?.cancel()
        launchWaitCap = nil
        launchBackstop?.cancel()
        launchBackstop = nil
        switch verdict {
        case .ok(let email, let svip, let svipExpiresAt, let displayName):
            AccountAuthorization.update(email: email, svip: svip, svipExpiresAt: svipExpiresAt, displayName: displayName)
            fallthrough
        case .unreachable:
            // Build 21: the home shell is installed UNDER the
            // splash first, fully rendered, and finish() then
            // dissolves the splash into it in one monotonic fade;
            // the completion only removes the emptied splash.
            // (Before, content installed after stageOut and the
            // gate faded the splash a second time — the visible
            // icon flash at the end of the splash.)
            addContentView()
            splash.finish { [weak self] in
                guard let self, let splash = self.splash04 else { return }
                self.splash04 = nil
                self.remove(splash)
                VersionPopup.noteSplashFinished()
            }
        case .banned(let title, let subtitle, let reason):
            splash.fadeOutQuickly { [weak self] in
                guard let self else { return }
                remove(self.splash04)
                self.splash04 = nil
                showAccountBanned(title: title, subtitle: subtitle, reason: reason)
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

    /// The 1.5 s cap fired before the launch verdict: install the
    /// shell under the splash with the cached account state (the
    /// shell seeds itself from the `AccountAuthorization` mirror)
    /// and let the splash finish on its own timeline.
    private func enterWithCachedState() {
        guard let splash = splash04, statusVerdict == nil,
              contentViewController == nil else { return }
        enteredPendingVerdict = true
        addContentView()
        splash.finish { [weak self] in
            guard let self, let splash = self.splash04 else { return }
            self.splash04 = nil
            self.remove(splash)
            VersionPopup.noteSplashFinished()
        }
    }

    /// The launch verdict arriving after the capped entry: applied
    /// exactly like a heartbeat verdict — the red ban popup over
    /// the shell, a kick back to the 03 gate, or an authorization
    /// refresh. A network failure keeps failing open.
    private func applyLateLaunchVerdict(_ status: AccountStatus) {
        guard contentViewController != nil, accountBanController == nil else { return }
        switch status {
        case .banned(let title, let subtitle, let reason):
            showAccountBanned(title: title, subtitle: subtitle, reason: reason)
        case .invalid:
            AccountSession.clear()
            tearDownToGate()
        case .ok(let email, let svip, let svipExpiresAt, let displayName):
            applyAccountAuthorization(email: email, svip: svip, svipExpiresAt: svipExpiresAt, displayName: displayName)
        case .unreachable:
            break
        }
    }

    /// Build 20: an account ban shows the red banned popup — the
    /// EXACT VersionPopup banned rendering (same artwork, entrance
    /// and layout), hosted as a child covering the gate just like
    /// the version popup is hosted in the main window. Texts come
    /// from the status payload's ban fields. 退出 clears the
    /// account session and returns to the 03 gate (it does NOT
    /// terminate the app); 联系客服 opens the shared support
    /// link, same as the version popup.
    private func showAccountBanned(title: String, subtitle: String, reason: String) {
        guard accountBanController == nil else { return }
        if presentedViewController != nil {
            dismiss(animated: false)
        }
        let popup = VersionPopupViewController(
            payload: VersionPopup.accountBanPayload(
                title: title, subtitle: subtitle, reason: reason))
        popup.onBannedExit = { [weak self] in
            guard let self else { return }
            AccountSession.clear()
            tearDownToGate()
        }
        accountBanController = popup
        addChild(popup)
        popup.view.frame = view.bounds
        popup.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(popup.view)
        popup.didMove(toParent: self)
        popup.view.layoutIfNeeded()
        popup.beginEntrance()
    }

    // MARK: Mid-session heartbeat (Build 20)

    /// While home is installed, re-check `status` every 30 s so a
    /// mid-session ban (or kick) lands without waiting for the next
    /// launch: banned → the red ban popup over the shell; invalid →
    /// the session is cleared and the gate falls back to 03. A
    /// network failure fails open, exactly like the launch check.
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.heartbeatTick()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    @objc private func foregroundHeartbeat() {
        heartbeatTick()
    }

    private func heartbeatTick() {
        guard AccountSession.isLoggedIn,
              contentViewController != nil,
              accountBanController == nil else { return }
        AccountAPI.fetchStatus { [weak self] status in
            guard let self,
                  self.contentViewController != nil,
                  self.accountBanController == nil else { return }
            switch status {
            case .banned(let title, let subtitle, let reason):
                showAccountBanned(title: title, subtitle: subtitle, reason: reason)
            case .invalid:
                AccountSession.clear()
                tearDownToGate()
            case .ok(let email, let svip, let svipExpiresAt, let displayName):
                // SVIP grants / expiries land here within ~30 s,
                // same cadence as bans and kicks.
                applyAccountAuthorization(email: email, svip: svip, svipExpiresAt: svipExpiresAt, displayName: displayName)
            case .unreachable:
                break
            }
        }
    }

    // MARK: Content install

    /// Installs the real app over/under the splash and removes the
    /// splash. With a splash up we crossfade: content slides under
    /// the splash, the splash fades, then leaves the hierarchy.
    /// (The splash-04 verdict path no longer comes through here —
    /// it installs the shell via `addContentView()` first and lets
    /// the splash's own finish() own the single exit fade.)
    private func installContent() {
        guard addContentView() else { return }
        // Fresh login/register: the shell was seeded from the cached
        // verdict, so pull a live one — a card bound during register
        // grants SVIP the moment the home screen appears.
        refreshAccountAuthorization()
        splash03?.shutdown()
        let splash = splash03 ?? splash04
        splash03 = nil
        splash04 = nil
        guard let splash else { return }
        UIView.animate(withDuration: 0.45, animations: {
            splash.view.alpha = 0
        }, completion: { _ in
            self.remove(splash)
            VersionPopup.noteSplashFinished()
        })
    }

    // MARK: Account authorization

    /// Records a `status` verdict in `AccountAuthorization` and
    /// pushes the computed state into the installed shell. Called by
    /// the launch verdict, the post-login refresh and every
    /// heartbeat tick that hears back from the server.
    private func applyAccountAuthorization(email: String, svip: Bool, svipExpiresAt: Int, displayName: String) {
        AccountAuthorization.update(email: email, svip: svip, svipExpiresAt: svipExpiresAt, displayName: displayName)
        pushAuthorizationToShell()
    }

    private func pushAuthorizationToShell() {
        guard let shell = contentViewController as? MainShellViewController else { return }
        shell.setAuthorization(AccountAuthorization.isAuthorized)
    }

    /// One-shot `status` fetch whose only job is the authorization
    /// verdict (used right after a fresh login/register; the launch
    /// path and the heartbeat have their own flows). Banned/invalid
    /// verdicts are left for the heartbeat to surface.
    private func refreshAccountAuthorization() {
        AccountAPI.fetchStatus { [weak self] status in
            guard let self else { return }
            if case .ok(let email, let svip, let svipExpiresAt, let displayName) = status {
                applyAccountAuthorization(email: email, svip: svip, svipExpiresAt: svipExpiresAt, displayName: displayName)
            }
        }
    }

    /// Adds `AppRoot` under any splash currently up and starts the
    /// account heartbeat. Split out of `installContent` (Build 21)
    /// so the splash-04 exit can put the live shell beneath the
    /// splash BEFORE the splash fades into it. False when content
    /// was already installed.
    @discardableResult
    private func addContentView() -> Bool {
        guard contentViewController == nil else { return false }
        let content = AppRoot.makeRootViewController()
        contentViewController = content
        startHeartbeat()
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
        return true
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

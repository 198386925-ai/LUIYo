import AVFoundation
import Combine
import UIKit

/// Global tap feedback (haptics + click sound), each with a four-step level
/// （关闭 / 弱 / 中 / 强） chosen in the settings page behind the settings
/// list's 设置 entry. Feedback is installed once by swapping
/// `UIControl.sendAction`, so every control activated by a real touch across
/// the app ticks — no per-screen wiring. Programmatic actions (nil event)
/// stay silent.
enum AppFeedback {
    private static let hapticsLevelKey = "feedback.hapticsLevel"
    private static let soundLevelKey = "feedback.soundLevel"

    /// 0 = off, 1 = lightest … 3 = strongest. Defaults to 1.
    static var hapticsLevel: Int {
        get { UserDefaults.standard.object(forKey: hapticsLevelKey) as? Int ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: hapticsLevelKey) }
    }

    static var soundLevel: Int {
        get { UserDefaults.standard.object(forKey: soundLevelKey) as? Int ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: soundLevelKey) }
    }

    private static let generators: [UIImpactFeedbackGenerator] = [
        UIImpactFeedbackGenerator(style: .light),
        UIImpactFeedbackGenerator(style: .medium),
        UIImpactFeedbackGenerator(style: .heavy),
    ]

    static func install() {
        // Ambient category: the click mixes with other apps' audio instead
        // of interrupting it, and it respects the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        _ = UIControl.feedbackSwizzleOnce
        generators.forEach { $0.prepare() }
        // One-time migration from the old on/off switches (Builds 4–5).
        let defaults = UserDefaults.standard
        if defaults.object(forKey: hapticsLevelKey) == nil,
           let old = defaults.object(forKey: "feedback.hapticsEnabled") as? Bool {
            hapticsLevel = old ? 1 : 0
        }
        if defaults.object(forKey: soundLevelKey) == nil,
           let old = defaults.object(forKey: "feedback.soundsEnabled") as? Bool {
            soundLevel = old ? 1 : 0
        }
    }

    /// Build 21: feedback stays DISARMED from process launch until
    /// the first genuine user interaction arms it (a touch-driven
    /// control action in the swizzle below, or a tab-bar
    /// `shouldSelect`, which UIKit only calls for real taps).
    /// Launch-time state restoration — the shell building its tab
    /// bar and programmatically selecting the initial tab, which
    /// UIKit reports through the same delegate callbacks as a user
    /// tap — used to play a click the moment the user entered the
    /// app, with no touch at all. While disarmed, `tap()` is a
    /// no-op, so no restore path can sound off before the user has
    /// touched anything; once armed it stays armed.
    private static var armed = false

    static func arm() { armed = true }

    static func tap() {
        guard armed else { return }
        let haptics = hapticsLevel
        if (1...3).contains(haptics) { generators[haptics - 1].impactOccurred() }
        let sound = soundLevel
        if (1...3).contains(sound) { ClickSound.play(level: sound) }
    }
}

/// A short synthesized click played through AVAudioPlayer so its loudness
/// can follow the user's sound level (system sound IDs have a fixed volume).
private enum ClickSound {
    private static var player: AVAudioPlayer?

    static func play(level: Int) {
        if player == nil {
            player = try? AVAudioPlayer(data: clickData(), fileTypeHint: AVFileType.wav.rawValue)
        }
        guard let player else { return }
        player.volume = [0.15, 0.4, 0.7][level - 1]
        player.currentTime = 0
        player.play()
    }

    private static func clickData() -> Data {
        let sampleRate = 44100
        let frames = 1323 // 30 ms
        var pcm = Data()
        pcm.reserveCapacity(frames * 2)
        for index in 0..<frames {
            let t = Double(index) / Double(sampleRate)
            let envelope = exp(-t * 220)
            let value = Int16(5000 * envelope * sin(2 * Double.pi * 1500 * t))
            var little = value.littleEndian
            pcm.append(Data(bytes: &little, count: 2))
        }
        var data = Data()
        func appendString(_ string: String) { data.append(string.data(using: .ascii)!) }
        func appendUInt32(_ value: UInt32) { var v = value.littleEndian; data.append(Data(bytes: &v, count: 4)) }
        func appendUInt16(_ value: UInt16) { var v = value.littleEndian; data.append(Data(bytes: &v, count: 2)) }
        appendString("RIFF"); appendUInt32(UInt32(36 + pcm.count)); appendString("WAVE")
        appendString("fmt "); appendUInt32(16); appendUInt16(1); appendUInt16(1)
        appendUInt32(UInt32(sampleRate)); appendUInt32(UInt32(sampleRate * 2)); appendUInt16(2); appendUInt16(16)
        appendString("data"); appendUInt32(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}

private extension UIControl {
    static let feedbackSwizzleOnce: Void = {
        guard let original = class_getInstanceMethod(UIControl.self, #selector(UIControl.sendAction(_:to:for:))),
              let swizzled = class_getInstanceMethod(UIControl.self, #selector(UIControl.luiyo_feedbackSendAction(_:to:for:)))
        else { return }
        method_exchangeImplementations(original, swizzled)
    }()

    @objc func luiyo_feedbackSendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        luiyo_feedbackSendAction(action, to: target, for: event)
        if event != nil, isEnabled {
            // A real touch on a control: arm the launch-phase gate
            // first, so this very tap still ticks.
            AppFeedback.arm()
            AppFeedback.tap()
        }
    }
}

extension UIViewController {
    /// Left-edge swipe back for the full-screen sub-pages (they are presented
    /// modally, so there is no navigation swipe-back without this).
    func installEdgeSwipeBack() {
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(luiyo_handleEdgeSwipe(_:)))
        edge.edges = .left
        view.addGestureRecognizer(edge)
    }

    @objc func luiyo_handleEdgeSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        if gesture.state == .ended, gesture.translation(in: view).x > 70 {
            dismiss(animated: true)
        }
    }
}

/// The 设置 page behind the settings list's 设置 entry: the two feedback
/// level pickers （触控反馈 / 声音）, each a four-step segmented control,
/// the 检查更新 entry card (moved here from the 我的 page in Build 35,
/// red dot and all — it opens the same update page), and the account
/// 退出登录 card.
final class AppSettingsViewController: UIViewController {
    private let homeModel: NativeHomeModel
    private let updater = AppUpdateChecker.shared
    private let updateCard = UIView()
    private var updateBadge: UIView?
    private let logoutCard = UIView()
    private var cancellables = Set<AnyCancellable>()

    init(homeModel: NativeHomeModel) {
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Page font

    private var pageFont: UIFont?

    /// The 设置页 area's chosen font, handed over by the presenting
    /// settings page — same mechanism as the settings page itself.
    func applyPageFont(_ font: UIFont?) {
        pageFont = font
        if isViewLoaded { PageFontApplier.apply(font, to: view) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(nativeHex: homeModel.theme.background)
        installEdgeSwipeBack()

        let header = luiyoPageHeader(title: "设置", backAction: #selector(backTapped), target: self)
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),
        ])

        let card = UIView()
        card.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        card.layer.cornerRadius = 26
        card.clipsToBounds = true
        view.addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            card.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
        ])

        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 0
        card.addSubview(rows)
        rows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            rows.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            rows.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
        ])

        let hapticsSeg = PillSegmentedControl()
        hapticsSeg.options = [("0", "关闭"), ("1", "轻微"), ("2", "中度"), ("3", "高度")]
        hapticsSeg.setSelectedValue(String(AppFeedback.hapticsLevel))
        hapticsSeg.onChange = { value in AppFeedback.hapticsLevel = Int(value) ?? 1 }
        rows.addArrangedSubview(levelRow(title: "触控反馈", subtitle: "点按时的振动强度", control: hapticsSeg))

        let line = UIView()
        line.backgroundColor = UIAppColors.divider
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        rows.addArrangedSubview(line)

        let soundSeg = PillSegmentedControl()
        soundSeg.options = [("0", "关闭"), ("1", "柔和"), ("2", "适中"), ("3", "响亮")]
        soundSeg.setSelectedValue(String(AppFeedback.soundLevel))
        soundSeg.onChange = { value in AppFeedback.soundLevel = Int(value) ?? 1 }
        rows.addArrangedSubview(levelRow(title: "声音", subtitle: "点按时的提示音量", control: soundSeg))

        // Build 35: the 检查更新 entry lives here now, as its own
        // card directly under the feedback card — same entry as the
        // old 我的-page row (bundled icon, chevron, and the red dot
        // the shared checker raises when background discovery finds
        // a newer build), opening the same 检查更新 page.
        buildUpdateCard(below: card)

        // Build 17: the account 退出登录 lives HERE, as a card in
        // this page's own card style (moved off the 我的 page at the
        // user's request). Visible only while an account session
        // exists; the behavior is unchanged — confirmation, clear
        // the account session, and the entry gate hears the
        // notification and swaps the app back to splash 03 at once.
        // Build 41: the solid card surface is back (Build 40's
        // transparency was a misread instruction, reverted); the
        // height and radius keep the 我的-row metrics (48 pt / 24).
        logoutCard.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        logoutCard.layer.cornerRadius = 24
        logoutCard.clipsToBounds = true
        view.addSubview(logoutCard)
        logoutCard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logoutCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            logoutCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            logoutCard.topAnchor.constraint(equalTo: updateCard.bottomAnchor, constant: 12),
            logoutCard.heightAnchor.constraint(equalToConstant: 48),
        ])
        let logoutTap = UIControl()
        logoutTap.addTarget(self, action: #selector(accountLogoutTapped), for: .touchUpInside)
        logoutCard.addSubview(logoutTap)
        logoutTap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logoutTap.leadingAnchor.constraint(equalTo: logoutCard.leadingAnchor),
            logoutTap.trailingAnchor.constraint(equalTo: logoutCard.trailingAnchor),
            logoutTap.topAnchor.constraint(equalTo: logoutCard.topAnchor),
            logoutTap.bottomAnchor.constraint(equalTo: logoutCard.bottomAnchor),
        ])
        let logoutTitle = UILabel()
        logoutTitle.text = "退出登录"
        logoutTitle.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        logoutTitle.textColor = .systemRed
        logoutTitle.textAlignment = .center
        logoutTap.addSubview(logoutTitle)
        logoutTitle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logoutTitle.centerXAnchor.constraint(equalTo: logoutTap.centerXAnchor),
            logoutTitle.centerYAnchor.constraint(equalTo: logoutTap.centerYAnchor),
        ])
        refreshLogoutVisibility()
        PageFontApplier.apply(pageFont, to: view)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshLogoutVisibility()
        PageFontApplier.apply(pageFont, to: view)
    }

    private func refreshLogoutVisibility() {
        logoutCard.isHidden = !AccountSession.isLoggedIn
    }

    @objc private func accountLogoutTapped() {
        let alert = UIAlertController(
            title: "退出登录",
            message: "退出后需要重新登录才能进入。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出登录", style: .destructive) { [weak self] _ in
            AccountSession.clear()
            self?.refreshLogoutVisibility()
            // The entry gate hears this and immediately swaps the
            // app back to the splash-03 register gate.
            NotificationCenter.default.post(name: .accountSessionDidLogout, object: nil)
        })
        present(alert, animated: true)
    }

    // MARK: - 检查更新 card (Build 35: moved from the 我的 page)

    private func buildUpdateCard(below card: UIView) {
        // Build 41: the solid card surface is back (Build 40's
        // transparency was a misread instruction, reverted); the
        // height and radius keep the 我的-row metrics (48 pt / 24).
        updateCard.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        updateCard.layer.cornerRadius = 24
        updateCard.clipsToBounds = true
        view.addSubview(updateCard)
        updateCard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            updateCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            updateCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            updateCard.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
            updateCard.heightAnchor.constraint(equalToConstant: 48),
        ])
        let tap = UIControl()
        tap.addTarget(self, action: #selector(updateTapped), for: .touchUpInside)
        updateCard.addSubview(tap)
        tap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tap.leadingAnchor.constraint(equalTo: updateCard.leadingAnchor),
            tap.trailingAnchor.constraint(equalTo: updateCard.trailingAnchor),
            tap.topAnchor.constraint(equalTo: updateCard.topAnchor),
            tap.bottomAnchor.constraint(equalTo: updateCard.bottomAnchor),
        ])
        let icon = UIImageView(image: luiyoBundledIcon("update"))
        icon.tintColor = UIAppColors.inkDynamic
        icon.contentMode = .scaleAspectFit
        let title = UILabel()
        title.text = "检查更新"
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = UIAppColors.inkDynamic
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = UIAppColors.inkDynamic
        chevron.contentMode = .scaleAspectFit
        // Red dot shown while the shared update checker knows a
        // newer build exists (launch auto-check / manual check) —
        // the same badge the 我的-page row carried before the move.
        let badge = UIView()
        badge.backgroundColor = .systemRed
        badge.layer.cornerRadius = 5
        badge.isHidden = !updater.updateFound
        updateBadge = badge
        tap.addSubview(icon)
        tap.addSubview(title)
        tap.addSubview(chevron)
        tap.addSubview(badge)
        icon.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: tap.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 21),
            icon.heightAnchor.constraint(equalToConstant: 21),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: tap.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 10),
            badge.heightAnchor.constraint(equalToConstant: 10),
        ])
        updater.$updateFound
            .receive(on: DispatchQueue.main)
            .sink { [weak self] found in self?.updateBadge?.isHidden = !found }
            .store(in: &cancellables)
    }

    @objc private func updateTapped() {
        let page = UpdateCheckViewController(updater: updater, homeModel: homeModel)
        page.applyPageFont(pageFont)
        present(page, animated: true)
    }

    private func levelRow(title: String, subtitle: String, control: UIView) -> UIView {
        let row = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 13)
        titleLabel.textColor = UIAppColors.inkDynamic
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 10)
        subtitleLabel.textColor = UIAppColors.secondary
        let texts = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        texts.axis = .vertical
        texts.spacing = 2
        row.addSubview(texts)
        row.addSubview(control)
        texts.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            texts.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            texts.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: 212),
            row.heightAnchor.constraint(equalToConstant: 48),
        ])
        return row
    }

    @objc private func backTapped() { dismiss(animated: true) }
}

extension AppSettingsViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: false)
    }
}

import AudioToolbox
import UIKit

/// Global tap feedback (haptics + click sound) with its two switches living
/// in the settings page reached from the settings list's 设置 entry.
/// Feedback is installed once by swapping `UIControl.sendAction`, so every
/// control activated by a real touch across the app ticks — no per-screen
/// wiring. Programmatic actions (nil event) stay silent.
enum AppFeedback {
    private static let hapticsKey = "feedback.hapticsEnabled"
    private static let soundsKey = "feedback.soundsEnabled"

    static var hapticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
    }

    static var soundsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundsKey) }
    }

    private static let impact = UIImpactFeedbackGenerator(style: .light)

    static func install() {
        _ = UIControl.feedbackSwizzleOnce
        impact.prepare()
    }

    static func tap() {
        if hapticsEnabled { impact.impactOccurred() }
        if soundsEnabled { AudioServicesPlaySystemSound(1104) }
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

/// The 设置 page behind the settings list's 设置 entry: currently the two
/// feedback switches （触控反馈 / 声音）.
final class AppSettingsViewController: UIViewController {
    private let homeModel: NativeHomeModel

    init(homeModel: NativeHomeModel) {
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
            rows.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
        ])

        let haptics = UISwitch()
        haptics.isOn = AppFeedback.hapticsEnabled
        haptics.addTarget(self, action: #selector(hapticsChanged(_:)), for: .valueChanged)
        rows.addArrangedSubview(switchRow(title: "触控反馈", subtitle: "点按按钮和开关时轻微振动", control: haptics))

        let line = UIView()
        line.backgroundColor = UIAppColors.divider
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        rows.addArrangedSubview(line)

        let sounds = UISwitch()
        sounds.isOn = AppFeedback.soundsEnabled
        sounds.addTarget(self, action: #selector(soundsChanged(_:)), for: .valueChanged)
        rows.addArrangedSubview(switchRow(title: "声音", subtitle: "点按时播放轻响", control: sounds))
    }

    private func switchRow(title: String, subtitle: String, control: UIView) -> UIView {
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
            row.heightAnchor.constraint(equalToConstant: 56),
        ])
        return row
    }

    @objc private func hapticsChanged(_ sender: UISwitch) { AppFeedback.hapticsEnabled = sender.isOn }
    @objc private func soundsChanged(_ sender: UISwitch) { AppFeedback.soundsEnabled = sender.isOn }
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

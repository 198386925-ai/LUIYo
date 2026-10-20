import Combine
import UIKit

/// The 检查更新 page: current version, live check status, the new version's
/// notes when one is available, and the download action — all in one place
/// instead of crammed into the settings row. Opened from the settings
/// 检查更新 entry; entering the page checks once automatically.
final class UpdateCheckViewController: UIViewController {
    private let updater: AppUpdateChecker
    private let homeModel: NativeHomeModel
    private var cancellables: Set<AnyCancellable> = []
    private var didAutoCheck = false

    private var statusLabel: UILabel!
    private var newVersionBlock: UIStackView!
    private var newVersionTitle: UILabel!
    private var newVersionNotes: UILabel!
    private var actionButton: UIButton!

    init(updater: AppUpdateChecker, homeModel: NativeHomeModel) {
        self.updater = updater
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(nativeHex: homeModel.theme.background)

        let header = luiyoPageHeader(title: "检查更新", backAction: #selector(backTapped), target: self)
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
        ])
        stack.addArrangedSubview(infoCard())

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIAppColors.accentPurple
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return attributes
        }
        actionButton = UIButton(configuration: config)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        stack.addArrangedSubview(actionButton)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.heightAnchor.constraint(equalToConstant: 46).isActive = true

        updater.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        updater.$showUpdateAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self, show else { return }
                // The page itself shows the new version; no alert needed.
                self.updater.showUpdateAlert = false
                self.refresh()
            }
            .store(in: &cancellables)
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didAutoCheck {
            didAutoCheck = true
            if case .idle = updater.state { updater.checkForUpdate() }
        }
    }

    @objc private func backTapped() { dismiss(animated: true) }

    private func infoCard() -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        card.layer.cornerRadius = 26
        card.clipsToBounds = true
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 8
        card.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        let name = UILabel()
        name.text = "LUIYo"
        name.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        name.textColor = UIAppColors.inkDynamic
        inner.addArrangedSubview(name)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let current = UILabel()
        current.text = "当前版本 \(version)（Build \(AppConfiguration.buildNumber)）"
        current.font = UIFont.systemFont(ofSize: 12)
        current.textColor = UIAppColors.secondary
        inner.addArrangedSubview(current)
        statusLabel = UILabel()
        statusLabel.font = UIFont.systemFont(ofSize: 13)
        statusLabel.textColor = UIAppColors.inkDynamic
        statusLabel.numberOfLines = 0
        inner.addArrangedSubview(statusLabel)

        newVersionBlock = UIStackView()
        newVersionBlock.axis = .vertical
        newVersionBlock.spacing = 6
        let line = UIView()
        line.backgroundColor = UIAppColors.divider
        newVersionBlock.addArrangedSubview(line)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        newVersionTitle = UILabel()
        newVersionTitle.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        newVersionTitle.textColor = UIAppColors.inkDynamic
        newVersionBlock.addArrangedSubview(newVersionTitle)
        newVersionNotes = UILabel()
        newVersionNotes.font = UIFont.systemFont(ofSize: 12)
        newVersionNotes.textColor = UIAppColors.secondary
        newVersionNotes.numberOfLines = 0
        newVersionBlock.addArrangedSubview(newVersionNotes)
        inner.addArrangedSubview(newVersionBlock)
        return card
    }

    private var updateAvailable: Bool {
        let current = Int(AppConfiguration.buildNumber) ?? 0
        return updater.latestBuild > current && !updater.latestVersion.isEmpty
    }

    private func refresh() {
        guard isViewLoaded, statusLabel != nil else { return }
        var actionTitle = "检查更新"
        var actionEnabled = true
        switch updater.state {
        case .idle:
            statusLabel.text = updateAvailable ? "发现新版本，可以下载更新。" : "点按下方按钮检查新版本。"
            actionTitle = updateAvailable ? "下载 IPA" : "检查更新"
        case .checking:
            statusLabel.text = "检查中…"
            actionTitle = "检查中…"
            actionEnabled = false
        case .downloading(let progress):
            statusLabel.text = "下载中 \(Int(progress * 100))%"
            actionTitle = "取消下载"
        case .readyToShare:
            statusLabel.text = "已下载完成，请通过弹出的分享菜单保存到「文件」，再用安装工具安装。"
            actionTitle = "重新检查"
        case .error(let message):
            statusLabel.text = message
            actionTitle = "重新检查"
        }
        actionButton.configuration?.title = actionTitle
        actionButton.isEnabled = actionEnabled
        newVersionBlock.isHidden = !updateAvailable
        if updateAvailable {
            newVersionTitle.text = "新版本 \(updater.latestVersion)（Build \(updater.latestBuild)）"
            newVersionNotes.text = updater.changelog
            newVersionNotes.isHidden = updater.changelog.isEmpty
        }
    }

    @objc private func actionTapped() {
        switch updater.state {
        case .downloading:
            updater.cancelDownload()
        case .idle:
            if updateAvailable { updater.downloadIPA() } else { updater.checkForUpdate() }
        case .checking:
            break
        case .readyToShare, .error:
            updater.checkForUpdate()
        }
    }
}

extension UpdateCheckViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: false)
    }
}

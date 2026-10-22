import Combine
import UIKit
import UniformTypeIdentifiers

/// The 检查更新 page, rebuilt after the reference update page: the
/// current version and a manual check with its status line share
/// one card — and, once a check finds one, the update offer (notes
/// + in-app download with progress) folds into that same card —
/// then the install-method row heading the behaviour switches
/// card, and the certificate card (UDID entry, 导入证书， and the
/// install-node row as its last row). The feed is the luioe
/// `updates/latest.json` and nothing else — no external release
/// pages are linked.
final class UpdateCheckViewController: UIViewController {
    private let updater: AppUpdateChecker
    private let homeModel: NativeHomeModel
    private var cancellables: Set<AnyCancellable> = []

    // Offer section (inside the version-check card)
    private var offerSection: UIView!
    private var offerDivider: UIView!
    private var offerNotesLabel: UILabel!
    private var offerChevron: UIImageView!
    /// 更新内容 starts collapsed; the header row toggles it. A
    /// newly discovered build resets it to collapsed.
    private var notesExpanded = false
    private var lastOfferBuild = 0
    private var progressView: UIProgressView!
    private var progressBytesLabel: UILabel!
    private var downloadButton: UIButton!
    private var lcSignButton: UIButton!
    private var signButton: UIButton!
    private var signingInProgress = false
    private var installButton: UIButton!
    /// The signed IPA from the last successful in-app signing of
    /// the CURRENT download, and the bookkeeping that keeps the
    /// post-sign card state (and the auto-sign chain) honest when
    /// the download changes underneath it.
    private var signedIPAURL: URL?
    private var signedForDownloadURL: URL?
    private var lastSeenDownloadURL: URL?
    private var autoSignAttemptedFor: URL?
    private var autoSignFailureText: String?
    /// The on-device install server while an install hand-off
    /// is in flight (nil otherwise). Retained here so it keeps
    /// serving until it reports itself stopped.
    private var installServer: LocalInstallServer?

    // LCSign detection (internal only — it decides the offer
    // card's primary action; it is never displayed on the page)
    private var lcSignDetected = false

    // Status line
    private var statusLabel: UILabel!
    private var checkRow: UIControl!

    // Certificate section
    private var certUDIDRow: UIControl!
    private var certUDIDValueLabel: UILabel!
    private var certUDIDCopyButton: UIButton!
    /// The UDID the cert-card entry row currently shows (nil
    /// while the row reads 请导入证书 / 未包含 — no copy button
    /// is shown in those states).
    private var certUDIDCopyText: String?
    private var certUDIDCopyFeedbackToken = 0

    init(updater: AppUpdateChecker, homeModel: NativeHomeModel) {
        self.updater = updater
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Page font

    private var pageFont: UIFont?

    /// The 设置页 area's chosen font, handed over by the presenting
    /// settings page (nil = system font). Applied through the same
    /// PageFontApplier the settings page itself uses: faces swap,
    /// each element's own point size stays.
    func applyPageFont(_ font: UIFont?) {
        pageFont = font
        if isViewLoaded { PageFontApplier.apply(font, to: view) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PageFontApplier.apply(pageFont, to: view)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installEdgeSwipeBack()
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

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -28),
        ])

        stack.addArrangedSubview(versionCheckCard())
        stack.addArrangedSubview(togglesCard())
        let togglesNote = footnoteLabel("打开 LUIYo 时检查更新服务，每六小时最多一次。开启自动下载后，发现新版会在后台下载，准备完成后再次确认安装。")
        stack.addArrangedSubview(togglesNote)
        stack.addArrangedSubview(certificateCard())
        let certNote = footnoteLabel("选择证书 zip 压缩包，或同时选择一份 P12 证书和描述文件，再输入密码，验证成功后保存。证书、密码与文件仅保存在本机钥匙串，不会上传。")
        stack.addArrangedSubview(certNote)

        updater.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // @Published fires before the value lands; hop one
                // tick so refresh() reads the settled state.
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &cancellables)
        refresh()
        refreshCertificate()
        refreshLCSignDetection()
        PageFontApplier.apply(pageFont, to: view)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // LCSign may have been installed or removed since the page
        // was last shown — re-probe on every appearance.
        refreshLCSignDetection()
        // Opening this page never starts a check on its own: the
        // status line simply shows the updater's last known state
        // (the background auto-check keeps that state fresh, and
        // the 检查更新 row is the manual trigger).
    }

    @objc private func backTapped() { dismiss(animated: true) }

    // MARK: - Card scaffolding

    private func makeCard() -> (card: UIView, inner: UIStackView) {
        let card = UIView()
        card.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        card.layer.cornerRadius = 18
        card.clipsToBounds = true
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 0
        card.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        return (card, inner)
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = UIAppColors.divider
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        let wrapper = UIView()
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            line.topAnchor.constraint(equalTo: wrapper.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    private func rowLabel(_ text: String, size: CGFloat = 13, weight: UIFont.Weight = .regular, color: UIColor = UIAppColors.inkDynamic) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    /// Label-left / value-right info row, 44pt.
    private func infoRow(title: String, value: String, valueColor: UIColor = UIAppColors.secondary) -> UIView {
        let row = UIView()
        let titleLabel = rowLabel(title)
        let valueLabel = rowLabel(value, color: valueColor)
        valueLabel.textAlignment = .right
        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        // Minimum 44 tall; the row GROWS when a wider custom font
        // wraps text onto another line instead of clipping it.
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            valueLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            valueLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
        ])
        return row
    }

    /// A tappable text row (the row is the button).
    private func actionRow(title: String, color: UIColor, action: Selector) -> UIControl {
        let control = UIControl()
        control.addTarget(self, action: action, for: .touchUpInside)
        let label = rowLabel(title, color: color)
        control.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            label.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: control.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -12),
        ])
        return control
    }

    private func toggleRow(title: String, isOn: Bool, action: Selector) -> UIView {
        let row = UIView()
        let titleLabel = rowLabel(title)
        let toggle = UISwitch.luiyoSmall()
        toggle.isOn = isOn
        toggle.addTarget(self, action: action, for: .valueChanged)
        row.addSubview(titleLabel)
        row.addSubview(toggle)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        toggle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            toggle.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
        ])
        return row
    }

    private func footnoteLabel(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = UIAppColors.secondary
        label.numberOfLines = 0
        let wrapper = UIView()
        wrapper.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: -4),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    // MARK: - Sections

    /// Current version, the manual check and its status line in
    /// one card: version row — divider — check action — divider —
    /// status line.
    private func versionCheckCard() -> UIView {
        let (card, inner) = makeCard()
        let value = "\(AppConfiguration.marketingVersion) (Build \(AppConfiguration.buildNumber))"
        inner.addArrangedSubview(infoRow(title: "当前版本", value: value))
        inner.addArrangedSubview(divider())
        checkRow = actionRow(title: "检查更新", color: UIAppColors.accentPurple, action: #selector(checkTapped))
        inner.addArrangedSubview(checkRow)
        inner.addArrangedSubview(divider())
        let statusRow = UIView()
        statusLabel = rowLabel("", size: 12.5, color: UIAppColors.secondary)
        statusRow.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: statusRow.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: statusRow.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: statusRow.topAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: statusRow.bottomAnchor, constant: -10),
        ])
        inner.addArrangedSubview(statusRow)
        // The update offer folds into this same card, below the
        // status line, whenever a check has found a newer build.
        offerDivider = divider()
        inner.addArrangedSubview(offerDivider)
        inner.addArrangedSubview(buildOfferSection())
        return card
    }

    /// The offer UI as a section of the version-check card (it was
    /// a standalone card before): 更新内容 header + notes, the
    /// download progress, then the phase buttons. The header row
    /// folds the notes — collapsed by default, tap to expand.
    private func buildOfferSection() -> UIView {
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 8
        content.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        content.isLayoutMarginsRelativeArrangement = true

        let headerRow = UIControl()
        headerRow.addTarget(self, action: #selector(offerHeaderTapped), for: .touchUpInside)
        let headerTitle = rowLabel("更新内容", size: 13, weight: .semibold)
        headerTitle.isUserInteractionEnabled = false
        headerRow.addSubview(headerTitle)
        offerChevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
        offerChevron.tintColor = UIAppColors.secondary
        offerChevron.contentMode = .scaleAspectFit
        offerChevron.isUserInteractionEnabled = false
        headerRow.addSubview(offerChevron)
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        offerChevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
            headerTitle.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            headerTitle.topAnchor.constraint(equalTo: headerRow.topAnchor, constant: 2),
            headerTitle.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: -2),
            offerChevron.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor),
            offerChevron.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
            headerTitle.trailingAnchor.constraint(lessThanOrEqualTo: offerChevron.leadingAnchor, constant: -12),
        ])
        content.addArrangedSubview(headerRow)
        offerNotesLabel = rowLabel("", size: 12.5, color: UIAppColors.secondary)
        offerNotesLabel.isHidden = true
        content.addArrangedSubview(offerNotesLabel)

        progressView = UIProgressView(progressViewStyle: .default)
        progressView.tintColor = UIAppColors.accentPurple
        progressView.trackTintColor = UIAppColors.dividerStrong
        content.addArrangedSubview(progressView)
        progressBytesLabel = rowLabel("", size: 12, color: UIAppColors.secondary)
        content.addArrangedSubview(progressBytesLabel)

        lcSignButton = UIButton(configuration: filledButtonConfiguration())
        lcSignButton.configuration?.title = "用 LCSign 签装"
        lcSignButton.addTarget(self, action: #selector(lcSignTapped), for: .touchUpInside)
        content.addArrangedSubview(lcSignButton)
        lcSignButton.translatesAutoresizingMaskIntoConstraints = false
        lcSignButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true

        installButton = UIButton(configuration: filledButtonConfiguration())
        installButton.configuration?.title = "安装"
        installButton.addTarget(self, action: #selector(installTapped), for: .touchUpInside)
        content.addArrangedSubview(installButton)
        installButton.translatesAutoresizingMaskIntoConstraints = false
        installButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true

        downloadButton = UIButton(configuration: filledButtonConfiguration())
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        content.addArrangedSubview(downloadButton)
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true

        signButton = UIButton(configuration: secondaryButtonConfiguration())
        signButton.configuration?.title = "签名此更新"
        signButton.addTarget(self, action: #selector(signTapped), for: .touchUpInside)
        content.addArrangedSubview(signButton)
        signButton.translatesAutoresizingMaskIntoConstraints = false
        signButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true

        offerSection = content
        return content
    }

    @objc private func offerHeaderTapped() {
        notesExpanded.toggle()
        offerNotesLabel.isHidden = !notesExpanded
        offerChevron.image = UIImage(systemName: notesExpanded ? "chevron.down" : "chevron.right",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
    }

    /// Configuration buttons render their title from the
    /// configuration's own attributes (PageFontApplier's titleLabel
    /// write does not reach them), so the transformer reads the
    /// page font lazily — every refresh() rebuild picks up the
    /// current face at the design size.
    private var buttonTitleTransformer: UIConfigurationTextAttributesTransformer {
        UIConfigurationTextAttributesTransformer { [weak self] attributes in
            var attributes = attributes
            attributes.font = self?.pageFont?.withSize(15) ?? UIFont.systemFont(ofSize: 15, weight: .semibold)
            return attributes
        }
    }

    private func filledButtonConfiguration() -> UIButton.Configuration {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIAppColors.accentPurple
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.titleTextAttributesTransformer = buttonTitleTransformer
        return config
    }

    /// The in-app download stays available as the secondary action
    /// whenever the LCSign hand-off is the card's primary action.
    private func secondaryButtonConfiguration() -> UIButton.Configuration {
        var config = UIButton.Configuration.tinted()
        config.baseBackgroundColor = UIAppColors.accentPurple
        config.baseForegroundColor = UIAppColors.accentPurple
        config.cornerStyle = .capsule
        config.titleTextAttributesTransformer = buttonTitleTransformer
        return config
    }

    /// Probes the LCSign URL scheme (declared in
    /// LSApplicationQueriesSchemes). The result stays internal:
    /// it decides whether the offer card's primary action is the
    /// LCSign hand-off or the in-app download.
    private func refreshLCSignDetection() {
        if let probe = URL(string: "loadcontroller://") {
            lcSignDetected = UIApplication.shared.canOpenURL(probe)
        } else {
            lcSignDetected = false
        }
        refresh()
    }

    private func togglesCard() -> UIView {
        let (card, inner) = makeCard()
        // The install-method row heads this card: single line,
        // like every other row — title + value, display-only (the
        // method is fixed; there is nothing to select). Whether
        // LCSign is installed is probed internally (it picks the
        // offer card's primary action) and deliberately not shown
        // here.
        inner.addArrangedSubview(infoRow(title: "安装方式", value: "证书签名 (LCSign)"))
        inner.addArrangedSubview(divider())
        inner.addArrangedSubview(toggleRow(title: "在灵动岛与锁屏显示更新进度", isOn: UpdateSettings.showProgress, action: #selector(showProgressChanged(_:))))
        inner.addArrangedSubview(divider())
        inner.addArrangedSubview(toggleRow(title: "自动检查更新", isOn: UpdateSettings.autoCheck, action: #selector(autoCheckChanged(_:))))
        inner.addArrangedSubview(divider())
        inner.addArrangedSubview(toggleRow(title: "自动下载并签名", isOn: UpdateSettings.autoDownload, action: #selector(autoDownloadChanged(_:))))
        inner.addArrangedSubview(divider())
        inner.addArrangedSubview(toggleRow(title: "安装时自动退出 LUIYo", isOn: UpdateSettings.autoExitAfterInstall, action: #selector(autoExitChanged(_:))))
        return card
    }

    private func certificateCard() -> UIView {
        let (card, inner) = makeCard()
        // Every row in this card uses the page's shared row
        // metrics — min-height 44 with 12pt vertical padding.
        // The UDID entry is always visible and reads as one line:
        // 「当前设备UDID：<udid>」 once a certificate is imported,
        // 「当前设备UDID：请导入证书」 while the store is empty.
        // Tapping it opens the cert-material detail page.
        certUDIDRow = UIControl()
        certUDIDRow.addTarget(self, action: #selector(udidEntryTapped), for: .touchUpInside)
        certUDIDValueLabel = rowLabel("")
        certUDIDValueLabel.isUserInteractionEnabled = false
        certUDIDRow.addSubview(certUDIDValueLabel)
        let udidChevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        udidChevron.tintColor = UIAppColors.secondary
        udidChevron.contentMode = .scaleAspectFit
        udidChevron.isUserInteractionEnabled = false
        certUDIDRow.addSubview(udidChevron)
        // Copy button for the shown UDID, sitting ahead of the
        // chevron. As its own control it takes its taps itself —
        // the row's navigation target never sees them. Hidden
        // until a real UDID is on the row (refreshCertificate).
        certUDIDCopyButton = UIButton(type: .system)
        certUDIDCopyButton.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)), for: .normal)
        certUDIDCopyButton.tintColor = UIAppColors.secondary
        certUDIDCopyButton.addTarget(self, action: #selector(copyUDIDTapped), for: .touchUpInside)
        certUDIDCopyButton.isHidden = true
        certUDIDRow.addSubview(certUDIDCopyButton)
        certUDIDValueLabel.translatesAutoresizingMaskIntoConstraints = false
        udidChevron.translatesAutoresizingMaskIntoConstraints = false
        certUDIDCopyButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            certUDIDRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            certUDIDValueLabel.leadingAnchor.constraint(equalTo: certUDIDRow.leadingAnchor, constant: 16),
            certUDIDValueLabel.topAnchor.constraint(equalTo: certUDIDRow.topAnchor, constant: 12),
            certUDIDValueLabel.bottomAnchor.constraint(equalTo: certUDIDRow.bottomAnchor, constant: -12),
            udidChevron.trailingAnchor.constraint(equalTo: certUDIDRow.trailingAnchor, constant: -16),
            udidChevron.centerYAnchor.constraint(equalTo: certUDIDRow.centerYAnchor),
            certUDIDCopyButton.widthAnchor.constraint(equalToConstant: 30),
            certUDIDCopyButton.heightAnchor.constraint(equalToConstant: 30),
            certUDIDCopyButton.trailingAnchor.constraint(equalTo: udidChevron.leadingAnchor, constant: -8),
            certUDIDCopyButton.centerYAnchor.constraint(equalTo: certUDIDRow.centerYAnchor),
            certUDIDValueLabel.trailingAnchor.constraint(lessThanOrEqualTo: certUDIDCopyButton.leadingAnchor, constant: -8),
        ])
        inner.addArrangedSubview(certUDIDRow)
        inner.addArrangedSubview(divider())
        inner.addArrangedSubview(actionRow(title: "导入证书", color: .systemBlue, action: #selector(importCertTapped)))
        inner.addArrangedSubview(divider())
        // The install node lives in this card as its last row:
        // installation is served by the app's own on-device
        // install server, so the row is display-only.
        inner.addArrangedSubview(infoRow(title: "安装节点", value: "LUIYo 本地内置"))
        return card
    }

    // MARK: - Refresh

    private func refresh() {
        guard isViewLoaded, statusLabel != nil else { return }
        statusLabel.text = updater.statusText
        statusLabel.isHidden = updater.statusText.isEmpty
        checkRow.isEnabled = updater.phase != .checking && updater.phase != .downloading

        offerSection.isHidden = !updater.updateFound
        offerDivider.isHidden = !updater.updateFound
        // A newly discovered build starts with its notes folded.
        if updater.latestBuild != lastOfferBuild {
            lastOfferBuild = updater.latestBuild
            notesExpanded = false
        }
        offerNotesLabel.isHidden = !notesExpanded
        offerChevron.image = UIImage(systemName: notesExpanded ? "chevron.down" : "chevron.right",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        lcSignButton.isHidden = true
        // A signed result belongs to one specific download; when
        // the downloaded file changes, the signed state (and the
        // auto-sign attempt marker) starts over.
        if updater.downloadedFileURL != lastSeenDownloadURL {
            lastSeenDownloadURL = updater.downloadedFileURL
            autoSignAttemptedFor = nil
            autoSignFailureText = nil
        }
        if updater.downloadedFileURL != signedForDownloadURL { signedIPAURL = nil }
        // In-app signing is offered only for a finished download
        // with complete certificate material stored.
        signButton.isHidden = !(updater.phase == .downloaded && UpdateSigner.canSign) || signingInProgress || signedIPAURL != nil
        // Direct install is offered only once the current download
        // has actually been signed in-app AND the on-device
        // install certificate ships in the bundle; without the
        // cert file the action does not exist at all.
        installButton.isHidden = !(updater.phase == .downloaded && signedIPAURL != nil && LocalInstallServer.isAvailable)
        guard updater.updateFound else { return }
        offerNotesLabel.text = updater.releaseNotes.isEmpty ? "本次更新：优化体验，修复已知问题。" : updater.releaseNotes
        switch updater.phase {
        case .downloading:
            progressView.isHidden = false
            progressView.progress = Float(updater.downloadProgress)
            progressBytesLabel.isHidden = false
            let percent = Int(updater.downloadProgress * 100)
            progressBytesLabel.text = updater.totalBytes > 0
                ? "\(AppUpdateChecker.formatBytes(updater.downloadedBytes)) / \(AppUpdateChecker.formatBytes(updater.totalBytes)) · \(percent)%"
                : "已下载 \(AppUpdateChecker.formatBytes(updater.downloadedBytes)) · \(percent)%"
            downloadButton.configuration = filledButtonConfiguration()
            downloadButton.configuration?.title = "取消下载"
            downloadButton.isEnabled = true
        case .downloaded:
            progressView.isHidden = false
            progressBytesLabel.isHidden = false
            downloadButton.isEnabled = true
            if signingInProgress {
                progressView.progress = 1
                progressBytesLabel.text = "正在签名…"
            } else if signedIPAURL != nil {
                // Signed in-app: 安装 is the card's primary action
                // (installButton, above the download button);
                // sharing the signed IPA stays as the secondary.
                progressView.progress = 1
                progressBytesLabel.text = "签名完成 · 已通过签名校验"
                downloadButton.configuration = secondaryButtonConfiguration()
                downloadButton.configuration?.title = "分享"
            } else if let autoSignFailureText {
                progressView.progress = 1
                progressBytesLabel.text = autoSignFailureText
                downloadButton.configuration = filledButtonConfiguration()
                downloadButton.configuration?.title = "分享 / 安装 IPA"
            } else {
                progressView.progress = 1
                progressBytesLabel.text = "下载完成 · \(AppUpdateChecker.formatBytes(updater.totalBytes > 0 ? updater.totalBytes : updater.downloadedBytes))"
                downloadButton.configuration = filledButtonConfiguration()
                downloadButton.configuration?.title = "分享 / 安装 IPA"
            }
        default:
            progressView.isHidden = true
            progressBytesLabel.isHidden = true
            if lcSignDetected {
                // The hand-off is the primary action; the in-app
                // download stays as the secondary one.
                lcSignButton.isHidden = false
                downloadButton.configuration = secondaryButtonConfiguration()
            } else {
                downloadButton.configuration = filledButtonConfiguration()
            }
            downloadButton.configuration?.title = "下载更新"
            downloadButton.isEnabled = true
        }

        // 自动下载并签名 chaining: the toggle (named for both
        // halves) also carries a finished download straight into
        // in-app signing when certificate material is stored.
        // Signing only — starting the on-device install server
        // and opening the system install prompt always stay
        // deliberate taps.
        if updater.phase == .downloaded, UpdateSettings.autoDownload, UpdateSigner.canSign,
           !signingInProgress, signedIPAURL == nil,
           let downloaded = updater.downloadedFileURL, autoSignAttemptedFor != downloaded {
            autoSignAttemptedFor = downloaded
            startSigning(auto: true)
        }
    }

    private func refreshCertificate() {
        guard isViewLoaded, certUDIDValueLabel != nil else { return }
        let material = UpdateCertificateStore.load()
        // The UDID entry always shows exactly one line: with a
        // certificate imported, the header profile's first
        // provisioned device (未包含 when the profile carries no
        // device list); with an empty store, the import prompt.
        if material.isEmpty {
            certUDIDValueLabel.text = "当前设备UDID：请导入证书"
            certUDIDCopyText = nil
        } else {
            let udids = material.profiles.last.map { UpdateCertificateStore.provisionedDevices(in: $0.data) } ?? []
            certUDIDValueLabel.text = "当前设备UDID：\(udids.first ?? "未包含")"
            certUDIDCopyText = udids.first
        }
        certUDIDCopyButton.isHidden = certUDIDCopyText == nil
        // Freshly imported material may unlock the 签名此更新 action.
        refresh()
    }

    // MARK: - Actions

    @objc private func checkTapped() {
        updater.checkForUpdate()
    }

    @objc private func downloadTapped() {
        switch updater.phase {
        case .downloading:
            updater.cancelDownload()
        case .downloaded:
            // Once the download has been signed in-app, the
            // button shares the SIGNED file; before that it keeps
            // sharing the plain downloaded IPA.
            if let signedIPAURL {
                presentShareSheet(fileURL: signedIPAURL)
            } else {
                updater.shareDownloaded()
            }
        default:
            updater.startDownload()
        }
    }

    /// Hands the offered IPA to LCSign through its import scheme:
    /// LCSign downloads the file itself and imports it as a project,
    /// ready to sign and install with the user's own certificate
    /// (managed inside LCSign). If the open fails, the in-app
    /// download takes over, exactly like the plain download action.
    @objc private func lcSignTapped() {
        let rawURL = updater.latestDownloadURLString
        // Every parameter value is percent-encoded on its own
        // (RFC 3986 unreserved set) before joining: the download
        // URL, the feed's SHA-256 (so LCSign can verify what it
        // downloads; omitted when the feed has no digest), and
        // the same file name the in-app download uses (so the
        // imported project in LCSign is named properly).
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard !rawURL.isEmpty,
              let encodedURL = rawURL.addingPercentEncoding(withAllowedCharacters: allowed) else {
            updater.startDownload()
            return
        }
        var handoff = "loadcontroller://import?url=\(encodedURL)"
        let sha256 = updater.latestSHA256
        if !sha256.isEmpty, let encodedSHA = sha256.addingPercentEncoding(withAllowedCharacters: allowed) {
            handoff += "&sha256=\(encodedSHA)"
        }
        let fileName = "LUIYo-\(updater.latestVersion)-Build(\(updater.latestBuild)).ipa"
        if let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: allowed) {
            handoff += "&filename=\(encodedName)"
        }
        guard let handoffURL = URL(string: handoff) else {
            updater.startDownload()
            return
        }
        UIApplication.shared.open(handoffURL, options: [:]) { [weak self] success in
            guard let self else { return }
            if success {
                self.updater.markLCSignHandoffCompleted()
            } else {
                self.updater.startDownload()
            }
        }
    }

    /// Signs the downloaded update in-app with the stored P12 +
    /// profile (vendored zsign engine) and verifies the result.
    /// On success the signed file stays on the offer card: 安装
    /// (served by the on-device install server) becomes the
    /// primary action when the install certificate is bundled,
    /// and 分享 stays as the secondary action either way — no
    /// sheet is thrown up automatically. `auto` marks the
    /// 自动下载并签名 chain: it never raises an alert and never
    /// presents anything; its outcome lands on the card's status
    /// line.
    @objc private func signTapped() { startSigning(auto: false) }

    private func startSigning(auto: Bool) {
        guard let downloaded = updater.downloadedFileURL, !signingInProgress else { return }
        signingInProgress = true
        signButton.isHidden = true
        progressBytesLabel.isHidden = false
        progressBytesLabel.text = "正在签名…"
        UpdateSigner.signDownloadedUpdate(
            ipa: downloaded, version: updater.latestVersion, build: updater.latestBuild
        ) { [weak self] result in
            guard let self else { return }
            self.signingInProgress = false
            switch result {
            case .success(let signedURL):
                self.signedIPAURL = signedURL
                self.signedForDownloadURL = downloaded
                self.autoSignFailureText = nil
                self.refresh()
            case .failure(let failure):
                if auto {
                    self.autoSignFailureText = "自动签名失败：\(failure.message)"
                    self.refresh()
                } else {
                    self.refresh()
                    self.showMessage(title: "签名失败", message: failure.message)
                }
            }
        }
    }

    /// Starts the on-device install server with the signed IPA
    /// and, once it is listening, hands the system's itms-services
    /// installer a manifest URL whose host resolves (via its DNS
    /// A record) to this very phone — the whole hand-off stays
    /// on-device, no server of ours involved. Entirely
    /// tap-driven: nothing here ever runs from the
    /// auto-download/auto-sign chain. Any failure keeps the
    /// share path available.
    @objc private func installTapped() {
        guard let signedIPAURL else { return }
        // One install server at a time: a re-tap replaces the
        // previous server (which then stops quietly, and its
        // onStopped is ignored by the identity check below).
        installServer?.stop()
        let metadata = LocalInstallServer.metadata(
            forIPA: signedIPAURL, fallbackVersion: updater.latestVersion)
        let server = LocalInstallServer()
        installServer = server
        server.onReady = { [weak self] port in
            guard let self else { return }
            let manifestURL = "https://\(LocalInstallServer.host):\(port)/manifest.plist"
            self.progressBytesLabel.isHidden = false
            self.progressBytesLabel.text = "安装已发起，请按系统提示完成。"
            self.openInstallManifest(manifestURL)
        }
        server.onStopped = { [weak self, weak server] reason in
            guard let self, let server, self.installServer === server else { return }
            self.installServer = nil
            if case .failed(let failure) = reason {
                self.showMessage(title: "安装失败", message: failure.message)
            }
        }
        server.start(ipaURL: signedIPAURL, metadata: metadata)
    }

    private func openInstallManifest(_ manifestURLString: String) {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = manifestURLString.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else {
            showMessage(title: "安装失败", message: "安装链接无效。")
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            if !success {
                self?.showMessage(title: "安装失败", message: "无法打开系统安装入口，请改用分享安装。")
            }
        }
    }

    private func presentShareSheet(fileURL: URL) {
        let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
        }
        present(activity, animated: true)
    }

    @objc private func showProgressChanged(_ sender: UISwitch) { UpdateSettings.showProgress = sender.isOn }
    @objc private func autoCheckChanged(_ sender: UISwitch) { UpdateSettings.autoCheck = sender.isOn }
    @objc private func autoDownloadChanged(_ sender: UISwitch) { UpdateSettings.autoDownload = sender.isOn }
    @objc private func autoExitChanged(_ sender: UISwitch) { UpdateSettings.autoExitAfterInstall = sender.isOn }

    // MARK: - Certificate import

    private static var provisionType: UTType {
        UTType(filenameExtension: "mobileprovision") ?? .data
    }

    /// One import entry for every shape of certificate material:
    /// a single `.zip` (the format the UDID page exports — P12 +
    /// profile(s) inside, one folder level is fine) or the loose
    /// P12 + 描述文件 pair picked together (either file alone
    /// also works). Everything funnels into the same validated
    /// finishImport below.
    @objc private func importCertTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pkcs12, Self.provisionType, UTType.zip], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    /// Opens the 设备 UDID detail page: the header profile's
    /// UDIDs plus the imported certificate as one bundle item
    /// (tap for 证书详情， swipe for zip export / bundle delete).
    /// Deletions in there call back so this card re-reads the
    /// store on return.
    @objc private func udidEntryTapped() {
        let detail = CertMaterialViewController(homeModel: homeModel)
        detail.applyPageFont(pageFont)
        detail.onMaterialChanged = { [weak self] in self?.refreshCertificate() }
        present(detail, animated: true)
    }

    /// Copies the UDID shown on the cert-card entry row. The
    /// glyph flips to a checkmark for ~1.2s as the confirmation
    /// (the tap itself already ticks via the global AppFeedback
    /// swizzle); a token keeps a quick second tap from being
    /// reverted by the first tap's timer.
    @objc private func copyUDIDTapped() {
        guard let udid = certUDIDCopyText else { return }
        UIPasteboard.general.string = udid
        certUDIDCopyFeedbackToken += 1
        let token = certUDIDCopyFeedbackToken
        certUDIDCopyButton.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        certUDIDCopyButton.tintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.certUDIDCopyFeedbackToken == token else { return }
            self.certUDIDCopyButton.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)), for: .normal)
            self.certUDIDCopyButton.tintColor = UIAppColors.secondary
        }
    }

    /// Validates everything first, then saves in one write: a parse
    /// or password failure leaves the stored material untouched.
    private func finishImport(p12Data: Data?, profile: (info: (name: String, teamId: String, expiration: Date?), data: Data)?) {
        guard let p12Data else {
            saveImport(p12: nil, profile: profile)
            return
        }
        let alert = UIAlertController(title: "输入 P12 密码", message: "导入证书需要先验证密码。", preferredStyle: .alert)
        alert.addTextField { field in
            field.isSecureTextEntry = true
            field.placeholder = "P12 密码"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "导入", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let password = alert?.textFields?.first?.text ?? ""
            guard let label = UpdateCertificateStore.p12IdentityLabel(data: p12Data, password: password) else {
                self.showMessage(title: "导入失败", message: "P12 密码错误或文件已损坏，未保存任何内容。")
                return
            }
            self.saveImport(p12: (data: p12Data, password: password, label: label), profile: profile)
        })
        present(alert, animated: true)
    }

    private func saveImport(p12: (data: Data, password: String, label: String)?,
                            profile: (info: (name: String, teamId: String, expiration: Date?), data: Data)?) {
        var material = UpdateCertificateStore.load()
        if let p12 {
            material.p12Data = p12.data
            material.p12Password = p12.password
            material.p12Label = p12.label
        }
        if let profile {
            let stored = StoredProvisionProfile(
                id: UUID().uuidString,
                name: profile.info.name,
                teamId: profile.info.teamId,
                expiration: profile.info.expiration,
                data: profile.data)
            material.profiles.removeAll { $0.name == stored.name && $0.teamId == stored.teamId }
            material.profiles.append(stored)
        }
        UpdateCertificateStore.save(material)
        refreshCertificate()
        showMessage(title: "导入完成", message: "证书已保存到本机钥匙串。")
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Certificate material detail

/// The 设备 UDID detail page behind the certificate card's UDID
/// entry. Hand-built with the same card scaffolding as the
/// 检查更新 page — 12pt cards and real labels for EVERY text,
/// section headers included, so the page font reaches all of it
/// (the previous UITableView version drew its own section
/// headers outside the font walk, which is why text in here did
/// not follow the chosen font). Top section: the header
/// profile's device UDIDs — or the import prompt while the store
/// is empty. Below: the imported certificate as ONE item (the
/// P12 and its profiles are a single bundle): tap it for the
/// 证书详情 page; swipe it to 导出 the whole bundle as one zip,
/// or 删除 the whole bundle. Presented as a full-screen modal
/// with the shared page header, like the other subpages reached
/// from the 我的 tab (no nav stack).
final class CertMaterialViewController: UIViewController {
    private let homeModel: NativeHomeModel

    /// Called after the bundle is deleted so the presenting
    /// update page can re-read the store for its cert card.
    var onMaterialChanged: (() -> Void)?

    private var stack: UIStackView!
    private var material = UpdateCertMaterial()
    private var udids: [String] = []
    /// Pending glyph reverts for the UDID rows' copy buttons,
    /// keyed by button so a re-tap restarts that button's timer.
    private var udidCopyReverts: [ObjectIdentifier: DispatchWorkItem] = [:]

    init(homeModel: NativeHomeModel) {
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Page font

    private var pageFont: UIFont?

    /// The 检查更新 page's font, handed over by the presenting
    /// page — routed through the same PageFontApplier, so this
    /// page follows the 设置 area font like its parent. No rows
    /// are exempt here.
    func applyPageFont(_ font: UIFont?) {
        pageFont = font
        if isViewLoaded { PageFontApplier.apply(font, to: view) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PageFontApplier.apply(pageFont, to: view)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installEdgeSwipeBack()
        view.backgroundColor = UIColor(nativeHex: homeModel.theme.background)

        let header = luiyoPageHeader(title: "设备 UDID", backAction: #selector(backTapped), target: self)
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),
        ])

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -28),
        ])
        reloadMaterial()
        PageFontApplier.apply(pageFont, to: view)
    }

    @objc private func backTapped() { dismiss(animated: true) }

    // MARK: - Scaffolding (same shapes as the 检查更新 page)

    private func makeCard() -> (card: UIView, inner: UIStackView) {
        let card = UIView()
        card.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        card.layer.cornerRadius = 18
        card.clipsToBounds = true
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 0
        card.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        return (card, inner)
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = UIAppColors.divider
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        let wrapper = UIView()
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            line.topAnchor.constraint(equalTo: wrapper.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    private func rowLabel(_ text: String, size: CGFloat = 13, weight: UIFont.Weight = .regular, color: UIColor = UIAppColors.inkDynamic) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func sectionLabel(_ text: String) -> UIView {
        let label = rowLabel(text, size: 13, weight: .semibold, color: UIAppColors.secondary)
        let wrapper = UIView()
        wrapper.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    /// A plain text row at the shared 44pt metrics.
    private func plainRow(_ text: String, color: UIColor = UIAppColors.inkDynamic) -> UIView {
        let row = UIView()
        let label = rowLabel(text, color: color)
        row.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
        ])
        return row
    }

    /// A UDID row with a trailing copy button, at the shared
    /// 44pt metrics. The button is tagged with the row's index
    /// into `udids` (rows are rebuilt on every reload, so the
    /// tag always matches the current list).
    private func udidRow(_ udid: String, index: Int) -> UIView {
        let row = UIView()
        let label = rowLabel(udid)
        let copyButton = UIButton(type: .system)
        copyButton.tag = index
        copyButton.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)), for: .normal)
        copyButton.tintColor = UIAppColors.secondary
        copyButton.addTarget(self, action: #selector(copyUDIDTapped(_:)), for: .touchUpInside)
        row.addSubview(label)
        row.addSubview(copyButton)
        label.translatesAutoresizingMaskIntoConstraints = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -8),
            copyButton.widthAnchor.constraint(equalToConstant: 30),
            copyButton.heightAnchor.constraint(equalToConstant: 30),
            copyButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            copyButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    /// Copies the tapped row's UDID; the button's glyph flips
    /// to a checkmark for ~1.2s as the confirmation (the tap
    /// itself already ticks via the global AppFeedback swizzle).
    @objc private func copyUDIDTapped(_ sender: UIButton) {
        guard udids.indices.contains(sender.tag) else { return }
        UIPasteboard.general.string = udids[sender.tag]
        sender.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        sender.tintColor = .systemGreen
        let key = ObjectIdentifier(sender)
        udidCopyReverts[key]?.cancel()
        let revert = DispatchWorkItem { [weak self, weak sender] in
            guard let sender else { return }
            sender.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)), for: .normal)
            sender.tintColor = UIAppColors.secondary
            self?.udidCopyReverts[key] = nil
        }
        udidCopyReverts[key] = revert
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: revert)
    }

    // MARK: - Data

    private func reloadMaterial() {
        material = UpdateCertificateStore.load()
        udids = material.profiles.last.map { UpdateCertificateStore.provisionedDevices(in: $0.data) } ?? []
        rebuildContent()
        // Rows are (re)built by the reload; re-run the font
        // applier so fresh labels pick up the page font as well.
        if isViewLoaded { PageFontApplier.apply(pageFont, to: view) }
    }

    private func rebuildContent() {
        guard stack != nil else { return }
        for arranged in stack.arrangedSubviews {
            stack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        stack.addArrangedSubview(sectionLabel("设备 UDID"))
        let (udidCard, udidInner) = makeCard()
        if material.isEmpty {
            udidInner.addArrangedSubview(plainRow("当前设备UDID：请导入证书", color: UIAppColors.secondary))
        } else if udids.isEmpty {
            udidInner.addArrangedSubview(plainRow("未包含", color: UIAppColors.secondary))
        } else {
            for (index, udid) in udids.enumerated() {
                if index > 0 { udidInner.addArrangedSubview(divider()) }
                udidInner.addArrangedSubview(udidRow(udid, index: index))
            }
        }
        stack.addArrangedSubview(udidCard)

        stack.addArrangedSubview(sectionLabel("证书与描述文件"))
        let (certCard, certInner) = makeCard()
        if material.isEmpty {
            certInner.addArrangedSubview(plainRow("未导入任何证书", color: UIAppColors.secondary))
        } else {
            let row = SwipeRevealRow(
                title: Self.bundleTitle(material),
                subtitle: Self.bundleSubtitle(material),
                backgroundColor: UIColor(nativeHex: homeModel.theme.card))
            row.onTap = { [weak self] in self?.openCertDetail() }
            row.onExport = { [weak self, weak row] in
                guard let self, let row else { return }
                self.exportBundle(from: row)
            }
            row.onDelete = { [weak self] in self?.deleteBundle() }
            certInner.addArrangedSubview(row)
        }
        stack.addArrangedSubview(certCard)
    }

    /// The bundle's display name: the P12's identity label, then
    /// the header profile's name, then a generic fallback.
    private static func bundleTitle(_ material: UpdateCertMaterial) -> String {
        material.p12Label ?? material.profiles.last?.name ?? "已导入证书"
    }

    private static func bundleSubtitle(_ material: UpdateCertMaterial) -> String {
        switch (material.p12Data != nil, !material.profiles.isEmpty) {
        case (true, true): return "证书 · 含描述文件"
        case (true, false): return "证书文件（.p12）"
        case (false, true): return "描述文件（.mobileprovision）"
        case (false, false): return ""
        }
    }

    // MARK: - Actions

    private func openCertDetail() {
        let detail = CertDetailViewController(homeModel: homeModel)
        detail.applyPageFont(pageFont)
        present(detail, animated: true)
    }

    private static func sanitizedFileName(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.controlCharacters)
        let cleaned = raw.components(separatedBy: bad).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "LUIYo" : cleaned
    }

    /// Exports the WHOLE bundle as one zip — the stored P12 and
    /// every profile under their proper file names — through the
    /// share sheet. The same zip re-imports via 导入证书.
    private func exportBundle(from anchor: UIView) {
        var entries: [ZipWriter.Entry] = []
        var usedNames: Set<String> = []
        func uniqueName(_ base: String) -> String {
            var name = base
            var counter = 2
            while usedNames.contains(name) {
                let dot = base.range(of: ".", options: .backwards)
                if let dot {
                    name = String(base[..<dot.lowerBound]) + "-\(counter)" + String(base[dot.lowerBound...])
                } else {
                    name = base + "-\(counter)"
                }
                counter += 1
            }
            usedNames.insert(name)
            return name
        }
        if let p12Data = material.p12Data {
            let name = uniqueName(Self.sanitizedFileName(material.p12Label ?? "LUIYo 证书") + ".p12")
            entries.append(ZipWriter.Entry(name: name, data: p12Data))
        }
        for profile in material.profiles {
            let name = uniqueName(Self.sanitizedFileName(profile.name) + ".mobileprovision")
            entries.append(ZipWriter.Entry(name: name, data: profile.data))
        }
        guard !entries.isEmpty else { return }
        let zipData = ZipWriter.archive(entries: entries)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.sanitizedFileName(Self.bundleTitle(material)) + ".zip")
        do {
            try zipData.write(to: url, options: .atomic)
        } catch {
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
        }
        present(activity, animated: true)
    }

    /// Deletes the whole stored bundle (P12 + password + every
    /// profile) in one store clear.
    private func deleteBundle() {
        UpdateCertificateStore.clear()
        reloadMaterial()
        onMaterialChanged?()
    }
}

/// One row whose content slides left to reveal two trailing
/// action buttons — 导出 (blue) and 删除 (red). A drag that runs
/// past the revealed buttons fires the first action (export —
/// the harmless one), mirroring a table row's full swipe. A tap
/// fires `onTap` while closed, and just closes the row while
/// open. Built by hand (not a table row) so the surrounding
/// card's 12pt radius and the page-font walk apply unchanged.
private final class SwipeRevealRow: UIView {
    var onTap: (() -> Void)?
    var onExport: (() -> Void)?
    var onDelete: (() -> Void)?

    private let contentView = UIView()
    private var contentLeading: NSLayoutConstraint!
    private var offset: CGFloat = 0
    private var panStartOffset: CGFloat = 0
    private let actionsWidth: CGFloat = 152

    init(title: String, subtitle: String, backgroundColor: UIColor) {
        super.init(frame: .zero)
        clipsToBounds = true

        let exportButton = UIButton(type: .system)
        exportButton.setTitle("导出", for: .normal)
        exportButton.setTitleColor(.white, for: .normal)
        exportButton.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        exportButton.backgroundColor = .systemBlue
        exportButton.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
        let deleteButton = UIButton(type: .system)
        deleteButton.setTitle("删除", for: .normal)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        deleteButton.backgroundColor = .systemRed
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [exportButton, deleteButton])
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        addSubview(actions)
        actions.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            actions.trailingAnchor.constraint(equalTo: trailingAnchor),
            actions.topAnchor.constraint(equalTo: topAnchor),
            actions.bottomAnchor.constraint(equalTo: bottomAnchor),
            actions.widthAnchor.constraint(equalToConstant: actionsWidth),
        ])

        contentView.backgroundColor = backgroundColor
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentLeading = contentView.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            contentLeading,
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: widthAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 15)
        titleLabel.textColor = UIAppColors.inkDynamic
        titleLabel.numberOfLines = 0
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = UIAppColors.secondary
        subtitleLabel.numberOfLines = 0
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.isUserInteractionEnabled = false
        contentView.addSubview(textStack)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        contentView.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.require(toFail: pan)
        contentView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyOffset(animated: Bool) {
        contentLeading.constant = offset
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                self.layoutIfNeeded()
            }
        } else {
            layoutIfNeeded()
        }
    }

    private func setOpen(_ open: Bool, animated: Bool = true) {
        offset = open ? -actionsWidth : 0
        applyOffset(animated: animated)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            panStartOffset = offset
        case .changed:
            let translation = recognizer.translation(in: self).x
            offset = min(0, max(-actionsWidth - 48, panStartOffset + translation))
            applyOffset(animated: false)
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: self).x
            if offset < -(actionsWidth + 30) || (offset < -40 && velocity < -600) {
                // Full swipe: fire the first (harmless) action.
                setOpen(false)
                onExport?()
            } else if offset < -actionsWidth / 2 {
                setOpen(true)
            } else {
                setOpen(false)
            }
        default:
            break
        }
    }

    @objc private func handleTap() {
        if offset != 0 {
            setOpen(false)
        } else {
            onTap?()
        }
    }

    @objc private func exportTapped() {
        setOpen(false)
        onExport?()
    }

    @objc private func deleteTapped() {
        setOpen(false)
        onDelete?()
    }
}

// MARK: - Certificate detail

/// The 证书详情 page, opened by tapping the certificate row on
/// the 设备 UDID page: the bundle's parsed identity — 证书名称，
/// 团队 ID, 描述文件名称， 到期时间， 包含设备数 — over the full
/// provisioned-device list. Same scaffolding (12pt cards) and
/// page-font routing as its presenter; unknown fields read —.
final class CertDetailViewController: UIViewController {
    private let homeModel: NativeHomeModel

    init(homeModel: NativeHomeModel) {
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Page font

    private var pageFont: UIFont?

    func applyPageFont(_ font: UIFont?) {
        pageFont = font
        if isViewLoaded { PageFontApplier.apply(font, to: view) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PageFontApplier.apply(pageFont, to: view)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installEdgeSwipeBack()
        view.backgroundColor = UIColor(nativeHex: homeModel.theme.background)

        let header = luiyoPageHeader(title: "证书详情", backAction: #selector(backTapped), target: self)
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),
        ])

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -28),
        ])

        let material = UpdateCertificateStore.load()
        let profile = material.profiles.last
        let udids = profile.map { UpdateCertificateStore.provisionedDevices(in: $0.data) } ?? []

        let (card, inner) = makeCard()
        let expirationText: String
        if let expiration = profile?.expiration {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "yyyy年M月d日"
            expirationText = formatter.string(from: expiration)
        } else {
            expirationText = "—"
        }
        let rows: [(String, String)] = [
            ("证书名称", material.p12Label ?? profile?.name ?? "已导入证书"),
            ("团队 ID", profile.map { $0.teamId.isEmpty ? "—" : $0.teamId } ?? "—"),
            ("描述文件名称", profile?.name ?? "—"),
            ("到期时间", expirationText),
            ("包含设备数", profile == nil ? "—" : "\(udids.count)"),
        ]
        for (index, row) in rows.enumerated() {
            if index > 0 { inner.addArrangedSubview(divider()) }
            inner.addArrangedSubview(infoRow(title: row.0, value: row.1))
        }
        stack.addArrangedSubview(card)

        stack.addArrangedSubview(sectionLabel("设备 UDID"))
        let (udidCard, udidInner) = makeCard()
        if udids.isEmpty {
            udidInner.addArrangedSubview(plainRow("未包含", color: UIAppColors.secondary))
        } else {
            for (index, udid) in udids.enumerated() {
                if index > 0 { udidInner.addArrangedSubview(divider()) }
                udidInner.addArrangedSubview(plainRow(udid))
            }
        }
        stack.addArrangedSubview(udidCard)
        PageFontApplier.apply(pageFont, to: view)
    }

    @objc private func backTapped() { dismiss(animated: true) }

    // MARK: - Scaffolding (same shapes as the 检查更新 page)

    private func makeCard() -> (card: UIView, inner: UIStackView) {
        let card = UIView()
        card.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        card.layer.cornerRadius = 18
        card.clipsToBounds = true
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 0
        card.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        return (card, inner)
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = UIAppColors.divider
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        let wrapper = UIView()
        wrapper.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            line.topAnchor.constraint(equalTo: wrapper.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    private func rowLabel(_ text: String, size: CGFloat = 13, weight: UIFont.Weight = .regular, color: UIColor = UIAppColors.inkDynamic) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func sectionLabel(_ text: String) -> UIView {
        let label = rowLabel(text, size: 13, weight: .semibold, color: UIAppColors.secondary)
        let wrapper = UIView()
        wrapper.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    /// Label-left / value-right info row, min-height 44, growing
    /// when a long value wraps.
    private func infoRow(title: String, value: String) -> UIView {
        let row = UIView()
        let titleLabel = rowLabel(title)
        let valueLabel = rowLabel(value, color: UIAppColors.secondary)
        valueLabel.textAlignment = .right
        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            valueLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            valueLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
        ])
        return row
    }

    private func plainRow(_ text: String, color: UIColor = UIAppColors.inkDynamic) -> UIView {
        let row = UIView()
        let label = rowLabel(text, color: color)
        row.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
        ])
        return row
    }
}

extension CertDetailViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: false)
    }
}

extension CertMaterialViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: false)
    }
}

// MARK: - UIDocumentPickerDelegate

extension UpdateCheckViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var p12Data: Data?
        var profile: (info: (name: String, teamId: String, expiration: Date?), data: Data)?
        // A picked profile (loose or from a zip) goes through the
        // same parse validation; a parse failure aborts the whole
        // import with nothing saved.
        func acceptProfile(_ data: Data) -> Bool {
            guard let info = UpdateCertificateStore.parseProvision(data: data) else { return false }
            profile = (info, data)
            return true
        }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if scoped { url.stopAccessingSecurityScopedResource() }
            guard let data else {
                showMessage(title: "导入失败", message: "读取文件失败，未保存任何内容。")
                return
            }
            switch url.pathExtension.lowercased() {
            case "p12", "pfx":
                p12Data = data
            case "mobileprovision":
                guard acceptProfile(data) else {
                    showMessage(title: "导入失败", message: "描述文件解析失败，未保存任何内容。")
                    return
                }
            case "zip":
                guard let extracted = UpdateCertificateStore.certFiles(fromZipData: data) else {
                    showMessage(title: "导入失败", message: "压缩包里没有找到 P12 证书或描述文件，未保存任何内容。")
                    return
                }
                if let zipP12 = extracted.p12 { p12Data = zipP12 }
                if let zipProfile = extracted.profile {
                    guard acceptProfile(zipProfile) else {
                        showMessage(title: "导入失败", message: "压缩包里的描述文件解析失败，未保存任何内容。")
                        return
                    }
                }
            default:
                showMessage(title: "导入失败", message: "不支持的文件类型，未保存任何内容。")
                return
            }
        }
        guard p12Data != nil || profile != nil else {
            showMessage(title: "导入失败", message: "没有选到可导入的文件。")
            return
        }
        finishImport(p12Data: p12Data, profile: profile)
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

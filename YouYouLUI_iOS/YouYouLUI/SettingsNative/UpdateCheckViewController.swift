import Combine
import UIKit
import UniformTypeIdentifiers

/// The 检查更新 page, rebuilt after the reference update page: the
/// current version and a manual check with its status line share
/// one card, then the update offer (notes + in-app download with
/// progress), then the install-method row heading the behaviour
/// switches card, the LCSign certificate section and the
/// install-node row. The feed is the luioe `updates/latest.json`
/// and nothing else — no external release pages are linked.
final class UpdateCheckViewController: UIViewController {
    private let updater: AppUpdateChecker
    private let homeModel: NativeHomeModel
    private var cancellables: Set<AnyCancellable> = []
    private var didAutoCheck = false

    // Offer card
    private var offerCard: UIView!
    private var offerNotesLabel: UILabel!
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
    private var certIdentityLabel: UILabel!
    private var certSavedLabel: UILabel!
    private var certUDIDRow: UIView!
    private var certUDIDDivider: UIView!
    private var certUDIDValueLabel: UILabel!

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
        stack.addArrangedSubview(buildOfferCard())
        stack.addArrangedSubview(togglesCard())
        let togglesNote = footnoteLabel("打开 LUIYo 时检查更新服务，每六小时最多一次。开启自动下载后，发现新版会在后台下载，准备完成后再次确认安装。")
        stack.addArrangedSubview(togglesNote)
        stack.addArrangedSubview(certificateCard())
        let certNote = footnoteLabel("同时选择一份 P12 证书和描述文件，再输入密码，验证成功后保存。证书、密码与文件仅保存在本机钥匙串，不会上传。")
        stack.addArrangedSubview(certNote)
        stack.addArrangedSubview(lcSignNodeCard())
        let nodeNote = footnoteLabel("安装节点由 LCSign 提供，在 LCSign 中选择；节点不可用时自动切换。")
        stack.addArrangedSubview(nodeNote)

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
        if !didAutoCheck {
            didAutoCheck = true
            if case .idle = updater.phase { updater.checkForUpdate() }
        }
    }

    @objc private func backTapped() { dismiss(animated: true) }

    // MARK: - Card scaffolding

    private func makeCard() -> (card: UIView, inner: UIStackView) {
        let card = UIView()
        card.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        card.layer.cornerRadius = 26
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

    private func selectorGlyph() -> UIImageView {
        let glyph = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))
        glyph.tintColor = UIAppColors.secondary
        glyph.contentMode = .scaleAspectFit
        return glyph
    }

    /// Label-left / value + selector-glyph row (single current value).
    private func selectorRow(title: String, value: String) -> UIView {
        let row = UIView()
        let titleLabel = rowLabel(title)
        let valueLabel = rowLabel(value, color: UIAppColors.secondary)
        let glyph = selectorGlyph()
        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        row.addSubview(glyph)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            glyph.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            glyph.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: glyph.leadingAnchor, constant: -6),
            valueLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            valueLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
        ])
        return row
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
        return card
    }

    private func buildOfferCard() -> UIView {
        let (card, inner) = makeCard()
        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 8
        content.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        content.isLayoutMarginsRelativeArrangement = true
        inner.addArrangedSubview(content)

        let title = rowLabel("更新内容", size: 13, weight: .semibold)
        content.addArrangedSubview(title)
        offerNotesLabel = rowLabel("", size: 12.5, color: UIAppColors.secondary)
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

        offerCard = card
        return card
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
        // like every other row — title + value + chevron. Whether
        // LCSign is installed is probed internally (it picks the
        // offer card's primary action) and deliberately not shown
        // here.
        inner.addArrangedSubview(selectorRow(title: "安装方式", value: "证书签名 (LCSign)"))
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
        // metrics — min-height 44 with 12pt vertical padding for
        // content rows, and the status-line metrics (no min-height,
        // 10pt padding) for the saved-count line, exactly like the
        // check card's status row. (This card previously hand-rolled
        // a 46pt header and a 38pt / 9pt saved row, which put its
        // text rhythm off the rest of the page.)
        let headerRow = UIView()
        certIdentityLabel = rowLabel("", size: 13.5, weight: .semibold)
        headerRow.addSubview(certIdentityLabel)
        certIdentityLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            certIdentityLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 16),
            certIdentityLabel.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor, constant: -16),
            certIdentityLabel.topAnchor.constraint(equalTo: headerRow.topAnchor, constant: 12),
            certIdentityLabel.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: -12),
        ])
        inner.addArrangedSubview(headerRow)
        inner.addArrangedSubview(divider())
        // The header profile's device UDID(s), above the saved
        // count. UDIDs are long, so the value gets its own
        // full-width line(s) under the title instead of squeezing
        // into the value column of an info row.
        certUDIDRow = UIView()
        let udidTitleLabel = rowLabel("设备 UDID")
        certUDIDValueLabel = rowLabel("", size: 12.5, color: UIAppColors.secondary)
        let udidStack = UIStackView(arrangedSubviews: [udidTitleLabel, certUDIDValueLabel])
        udidStack.axis = .vertical
        udidStack.spacing = 2
        certUDIDRow.addSubview(udidStack)
        udidStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            certUDIDRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            udidStack.leadingAnchor.constraint(equalTo: certUDIDRow.leadingAnchor, constant: 16),
            udidStack.trailingAnchor.constraint(equalTo: certUDIDRow.trailingAnchor, constant: -16),
            udidStack.topAnchor.constraint(equalTo: certUDIDRow.topAnchor, constant: 12),
            udidStack.bottomAnchor.constraint(equalTo: certUDIDRow.bottomAnchor, constant: -12),
        ])
        inner.addArrangedSubview(certUDIDRow)
        certUDIDDivider = divider()
        inner.addArrangedSubview(certUDIDDivider)
        let savedRow = UIView()
        certSavedLabel = rowLabel("", size: 12.5, color: UIAppColors.secondary)
        savedRow.addSubview(certSavedLabel)
        certSavedLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            certSavedLabel.leadingAnchor.constraint(equalTo: savedRow.leadingAnchor, constant: 16),
            certSavedLabel.trailingAnchor.constraint(equalTo: savedRow.trailingAnchor, constant: -16),
            certSavedLabel.topAnchor.constraint(equalTo: savedRow.topAnchor, constant: 10),
            certSavedLabel.bottomAnchor.constraint(equalTo: savedRow.bottomAnchor, constant: -10),
        ])
        inner.addArrangedSubview(savedRow)
        inner.addArrangedSubview(divider())
        inner.addArrangedSubview(actionRow(title: "导入 P12 与描述文件", color: UIAppColors.inkDynamic, action: #selector(importP12Tapped)))
        inner.addArrangedSubview(divider())
        inner.addArrangedSubview(actionRow(title: "导入描述文件", color: UIAppColors.inkDynamic, action: #selector(importProfileTapped)))
        inner.addArrangedSubview(divider())
        inner.addArrangedSubview(actionRow(title: "移除证书", color: .systemRed, action: #selector(removeCertTapped)))
        return card
    }

    private func lcSignNodeCard() -> UIView {
        let (card, inner) = makeCard()
        // Display only: install nodes live inside LCSign (the
        // hand-off URL carries no node choice), so this row is a
        // plain info row — no chevron, no tap behaviour.
        inner.addArrangedSubview(infoRow(title: "LCSign 安装节点", value: "LCSign 内置"))
        return card
    }

    // MARK: - Refresh

    private func refresh() {
        guard isViewLoaded, statusLabel != nil else { return }
        statusLabel.text = updater.statusText
        statusLabel.isHidden = updater.statusText.isEmpty
        checkRow.isEnabled = updater.phase != .checking && updater.phase != .downloading

        offerCard.isHidden = !updater.updateFound
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
        guard isViewLoaded, certIdentityLabel != nil else { return }
        let material = UpdateCertificateStore.load()
        certIdentityLabel.text = UpdateCertificateStore.identityLine ?? "未导入证书"
        certSavedLabel.text = "已保存 \(material.profiles.count) 份描述文件"
        // UDID row: read from the header profile (the one the
        // identity line comes from). A distribution profile has
        // no device list, so the row reads 未包含； with nothing
        // stored at all the row (and its divider) stays hidden.
        let udids = material.profiles.last.map { UpdateCertificateStore.provisionedDevices(in: $0.data) } ?? []
        let showUDIDRow = !material.isEmpty
        certUDIDRow.isHidden = !showUDIDRow
        certUDIDDivider.isHidden = !showUDIDRow
        if showUDIDRow {
            certUDIDValueLabel.text = udids.isEmpty ? "未包含" : udids.joined(separator: "\n")
        }
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

    private enum ImportKind { case p12AndProfile, profileOnly }
    private var pendingImportKind: ImportKind = .profileOnly

    private static var provisionType: UTType {
        UTType(filenameExtension: "mobileprovision") ?? .data
    }

    @objc private func importP12Tapped() {
        pendingImportKind = .p12AndProfile
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pkcs12, Self.provisionType], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    @objc private func importProfileTapped() {
        pendingImportKind = .profileOnly
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [Self.provisionType], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func removeCertTapped() {
        let material = UpdateCertificateStore.load()
        guard !material.isEmpty else {
            showMessage(title: "移除证书", message: "尚未导入任何证书。")
            return
        }
        let alert = UIAlertController(title: "移除证书", message: "将删除本机保存的证书、密码与描述文件。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "移除", style: .destructive) { [weak self] _ in
            UpdateCertificateStore.clear()
            self?.refreshCertificate()
        })
        present(alert, animated: true)
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

// MARK: - UIDocumentPickerDelegate

extension UpdateCheckViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var p12Data: Data?
        var profile: (info: (name: String, teamId: String, expiration: Date?), data: Data)?
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
                if pendingImportKind == .p12AndProfile { p12Data = data }
            case "mobileprovision":
                guard let info = UpdateCertificateStore.parseProvision(data: data) else {
                    showMessage(title: "导入失败", message: "描述文件解析失败，未保存任何内容。")
                    return
                }
                profile = (info, data)
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

import Combine
import UIKit
import UniformTypeIdentifiers

/// The 检查更新 page, rebuilt after the reference update page: the
/// current version, a manual check with a status line, the update
/// offer (notes + in-app download with progress), the install-method
/// row, the behaviour switches, the LCSign certificate section and
/// the install-node row. The feed is the luioe `updates/latest.json`
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

    // Status line
    private var statusLabel: UILabel!
    private var checkRow: UIControl!

    // Certificate section
    private var certIdentityLabel: UILabel!
    private var certSavedLabel: UILabel!

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

        stack.addArrangedSubview(currentVersionCard())
        stack.addArrangedSubview(checkCard())
        stack.addArrangedSubview(buildOfferCard())
        stack.addArrangedSubview(installMethodCard())
        stack.addArrangedSubview(togglesCard())
        let togglesNote = footnoteLabel("打开 LUIYo 时检查更新服务，每六小时最多一次。开启自动下载后，发现新版会在后台下载，准备完成后再次确认安装。")
        stack.addArrangedSubview(togglesNote)
        stack.addArrangedSubview(certificateCard())
        let certNote = footnoteLabel("同时选择一份 P12 证书和描述文件，再输入密码，验证成功后保存。证书、密码与文件仅保存在本机钥匙串，不会上传。")
        stack.addArrangedSubview(certNote)
        stack.addArrangedSubview(installNodeCard())
        let nodeNote = footnoteLabel("使用 LCSign 的 HTTPS 安装清单服务，签好的 IPA 通过本机连接交给 iOS。节点不可用时自动切换。")
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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
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
            control.heightAnchor.constraint(equalToConstant: 44),
            label.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
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
            row.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            glyph.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            glyph.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: glyph.leadingAnchor, constant: -6),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
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
            row.heightAnchor.constraint(equalToConstant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
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

    private func currentVersionCard() -> UIView {
        let (card, inner) = makeCard()
        let value = "\(AppConfiguration.marketingVersion) (Build \(AppConfiguration.buildNumber))"
        inner.addArrangedSubview(infoRow(title: "当前版本", value: value))
        return card
    }

    private func checkCard() -> UIView {
        let (card, inner) = makeCard()
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

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIAppColors.accentPurple
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return attributes
        }
        downloadButton = UIButton(configuration: config)
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)
        content.addArrangedSubview(downloadButton)
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.heightAnchor.constraint(equalToConstant: 46).isActive = true

        offerCard = card
        return card
    }

    private func installMethodCard() -> UIView {
        let (card, inner) = makeCard()
        inner.addArrangedSubview(selectorRow(title: "安装方式", value: "证书签名 (LCSign)"))
        return card
    }

    private func togglesCard() -> UIView {
        let (card, inner) = makeCard()
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
        let headerRow = UIView()
        certIdentityLabel = rowLabel("", size: 13.5, weight: .semibold)
        headerRow.addSubview(certIdentityLabel)
        certIdentityLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerRow.heightAnchor.constraint(equalToConstant: 46),
            certIdentityLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 16),
            certIdentityLabel.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor, constant: -16),
            certIdentityLabel.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
        ])
        inner.addArrangedSubview(headerRow)
        inner.addArrangedSubview(divider())
        let savedRow = UIView()
        certSavedLabel = rowLabel("", size: 12.5, color: UIAppColors.secondary)
        savedRow.addSubview(certSavedLabel)
        certSavedLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            savedRow.heightAnchor.constraint(equalToConstant: 38),
            certSavedLabel.leadingAnchor.constraint(equalTo: savedRow.leadingAnchor, constant: 16),
            certSavedLabel.trailingAnchor.constraint(equalTo: savedRow.trailingAnchor, constant: -16),
            certSavedLabel.centerYAnchor.constraint(equalTo: savedRow.centerYAnchor),
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

    private func installNodeCard() -> UIView {
        let (card, inner) = makeCard()
        inner.addArrangedSubview(selectorRow(title: "LCSign 安装节点", value: UpdateSettings.installNode))
        return card
    }

    // MARK: - Refresh

    private func refresh() {
        guard isViewLoaded, statusLabel != nil else { return }
        statusLabel.text = updater.statusText
        statusLabel.isHidden = updater.statusText.isEmpty
        checkRow.isEnabled = updater.phase != .checking && updater.phase != .downloading

        offerCard.isHidden = !updater.updateFound
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
            downloadButton.configuration?.title = "取消下载"
            downloadButton.isEnabled = true
        case .downloaded:
            progressView.isHidden = false
            progressView.progress = 1
            progressBytesLabel.isHidden = false
            progressBytesLabel.text = "下载完成 · \(AppUpdateChecker.formatBytes(updater.totalBytes > 0 ? updater.totalBytes : updater.downloadedBytes))"
            downloadButton.configuration?.title = "分享 / 安装 IPA"
            downloadButton.isEnabled = true
        default:
            progressView.isHidden = true
            progressBytesLabel.isHidden = true
            downloadButton.configuration?.title = "下载更新"
            downloadButton.isEnabled = true
        }
    }

    private func refreshCertificate() {
        guard isViewLoaded, certIdentityLabel != nil else { return }
        let material = UpdateCertificateStore.load()
        certIdentityLabel.text = UpdateCertificateStore.identityLine ?? "未导入证书"
        certSavedLabel.text = "已保存 \(material.profiles.count) 份描述文件"
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
            updater.shareDownloaded()
        default:
            updater.startDownload()
        }
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

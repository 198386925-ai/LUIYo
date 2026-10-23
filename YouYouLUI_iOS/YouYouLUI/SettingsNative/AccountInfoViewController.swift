import UIKit

/// Per-account, on-device profile overrides — a self-chosen nickname
/// and avatar, edited only from the account page. Both maps are
/// keyed by the account email, so accounts never see each other's
/// values and the data survives logout (a returning account finds
/// its own again). The ObjC hero cell reads the SAME UserDefaults
/// dictionaries and the SAME avatar directory — the key strings and
/// the `AccountAvatars` folder name must not drift between the two.
enum AccountProfileStore {
    private static let nicknamesKey = "youyou.profile.nicknames"
    private static let avatarFilesKey = "youyou.profile.avatarFiles"
    private static let avatarDirectoryName = "AccountAvatars"

    static var currentEmail: String { ThemePreferences.shared.accountEmail ?? "" }

    static func nickname(for email: String) -> String? {
        guard !email.isEmpty else { return nil }
        let map = UserDefaults.standard.dictionary(forKey: nicknamesKey) as? [String: String]
        let value = map?[email]
        return (value?.isEmpty == false) ? value : nil
    }

    static func setNickname(_ nickname: String, for email: String) {
        guard !email.isEmpty else { return }
        var map = UserDefaults.standard.dictionary(forKey: nicknamesKey) as? [String: String] ?? [:]
        map[email] = nickname
        UserDefaults.standard.set(map, forKey: nicknamesKey)
        NotificationCenter.default.post(name: .luiyoAccountAuthUpdated, object: nil)
    }

    static func avatarImage(for email: String) -> UIImage? {
        guard !email.isEmpty,
              let map = UserDefaults.standard.dictionary(forKey: avatarFilesKey) as? [String: String],
              let fileName = map[email],
              let url = avatarDirectory()?.appendingPathComponent(fileName)
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Stores an already square-cropped image as the account's
    /// avatar (JPEG in Application Support/AccountAvatars, replacing
    /// the previous file).
    static func setAvatarImage(_ image: UIImage, for email: String) {
        guard !email.isEmpty,
              let directory = avatarDirectory(),
              let data = image.jpegData(compressionQuality: 0.9)
        else { return }
        let fileName = UUID().uuidString + ".jpg"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        } catch { return }
        let defaults = UserDefaults.standard
        var map = defaults.dictionary(forKey: avatarFilesKey) as? [String: String] ?? [:]
        if let old = map[email], old != fileName {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old))
        }
        map[email] = fileName
        defaults.set(map, forKey: avatarFilesKey)
        NotificationCenter.default.post(name: .luiyoAccountAuthUpdated, object: nil)
    }

    /// Display priority: the on-device nickname wins, then the
    /// server-assigned display name, then the brand placeholder.
    static func effectiveDisplayName() -> String {
        if let local = nickname(for: currentEmail) { return local }
        let server = ThemePreferences.shared.accountDisplayName
        return (server?.isEmpty == false) ? (server ?? "LUIYo") : "LUIYo"
    }

    private static func avatarDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(avatarDirectoryName, isDirectory: true)
    }
}

/// The account page behind the hero card's top-right entry (the
/// chevron where the theme switch used to live), titled
/// 「我的账号资料」. It shows the account block — display name,
/// login email, authorization state — and is the ONE place where
/// the nickname and avatar can be changed (both stored on-device,
/// per account; the hero card itself only ever displays them).
/// Build 35 adds a 修改密码 row under 账号授权 (opens
/// `ChangePasswordViewController`) and a standalone 退出登录 card
/// at the bottom, mirroring the 设置 page's logout card. Build 39
/// adds an 输入卡密授权 row under 修改密码 (opens
/// `BindCardViewController`).
///
/// State is read from the same account mirrors the hero card reads
/// (`ThemePreferences` + `AccountAuthorization` + the profile
/// overrides above) and refreshes live on
/// `.luiyoAccountAuthUpdated`, so a tier grant or expiry landing via
/// the 30 s heartbeat updates this page too.
final class AccountInfoViewController: UIViewController {
    private let homeModel: NativeHomeModel
    private let avatarImageView = UIImageView()
    private let nameValueLabel = UILabel()
    private let emailValueLabel = UILabel()
    private let authValueLabel = UILabel()

    /// The hero auth chip's gold (sand gold), light/dark variants —
    /// the same two values `LUISettingsHeroCell` uses for 已授权.
    private static let authorizedGold = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.85, green: 0.75, blue: 0.56, alpha: 1)
            : UIColor(red: 0.49, green: 0.38, blue: 0.20, alpha: 1)
    }

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

        let header = luiyoPageHeader(title: "我的账号资料", backAction: #selector(backTapped), target: self)
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),
        ])

        // 修改头像 card: current avatar + the edit entry. Tapping the
        // card opens the photo picker (square crop built in).
        let avatarCard = UIView()
        avatarCard.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        avatarCard.layer.cornerRadius = 26
        avatarCard.clipsToBounds = true
        avatarCard.luiyoApplyGlassCardSurface(radius: 26, useBlur: homeModel.useBlur, tint: UIColor(nativeHex: homeModel.theme.card))
        view.addSubview(avatarCard)
        avatarCard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            avatarCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            avatarCard.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            avatarCard.heightAnchor.constraint(equalToConstant: 76),
        ])
        let avatarTap = UIControl()
        avatarTap.addTarget(self, action: #selector(avatarCardTapped), for: .touchUpInside)
        avatarCard.addSubview(avatarTap)
        avatarTap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarTap.leadingAnchor.constraint(equalTo: avatarCard.leadingAnchor),
            avatarTap.trailingAnchor.constraint(equalTo: avatarCard.trailingAnchor),
            avatarTap.topAnchor.constraint(equalTo: avatarCard.topAnchor),
            avatarTap.bottomAnchor.constraint(equalTo: avatarCard.bottomAnchor),
        ])
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 24
        avatarTap.addSubview(avatarImageView)
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: avatarTap.leadingAnchor, constant: 16),
            avatarImageView.centerYAnchor.constraint(equalTo: avatarTap.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 48),
            avatarImageView.heightAnchor.constraint(equalToConstant: 48),
        ])
        let avatarTitle = UILabel()
        avatarTitle.text = "修改头像"
        avatarTitle.font = UIFont.systemFont(ofSize: 13)
        avatarTitle.textColor = UIAppColors.inkDynamic
        avatarTap.addSubview(avatarTitle)
        avatarTitle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarTitle.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
            avatarTitle.centerYAnchor.constraint(equalTo: avatarTap.centerYAnchor),
        ])
        let avatarChevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        avatarChevron.tintColor = UIAppColors.inkDynamic
        avatarChevron.contentMode = .scaleAspectFit
        avatarTap.addSubview(avatarChevron)
        avatarChevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarChevron.trailingAnchor.constraint(equalTo: avatarTap.trailingAnchor, constant: -16),
            avatarChevron.centerYAnchor.constraint(equalTo: avatarTap.centerYAnchor),
        ])

        // Account block card: nickname (editable) / email / auth.
        let card = UIView()
        card.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        card.layer.cornerRadius = 26
        card.clipsToBounds = true
        card.luiyoApplyGlassCardSurface(radius: 26, useBlur: homeModel.useBlur, tint: UIColor(nativeHex: homeModel.theme.card))
        view.addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            card.topAnchor.constraint(equalTo: avatarCard.bottomAnchor, constant: 12),
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

        rows.addArrangedSubview(nicknameRow())
        rows.addArrangedSubview(divider())
        rows.addArrangedSubview(infoRow(title: "邮箱", valueLabel: emailValueLabel))
        rows.addArrangedSubview(divider())
        rows.addArrangedSubview(infoRow(title: "账号授权", valueLabel: authValueLabel))
        rows.addArrangedSubview(divider())
        rows.addArrangedSubview(actionRow(title: "修改密码", action: #selector(changePasswordTapped)))
        rows.addArrangedSubview(divider())
        rows.addArrangedSubview(actionRow(title: "输入卡密授权", action: #selector(bindCardTapped)))

        // Build 35: standalone 退出登录 card at the page bottom —
        // same card shape and behaviour as the 设置 page's logout
        // card (confirmation, clear the session, the entry gate
        // hears the notification and swaps back to splash 03).
        let logoutCard = UIView()
        logoutCard.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        logoutCard.layer.cornerRadius = 26
        logoutCard.clipsToBounds = true
        logoutCard.luiyoApplyGlassCardSurface(radius: 26, useBlur: homeModel.useBlur, tint: UIColor(nativeHex: homeModel.theme.card))
        view.addSubview(logoutCard)
        logoutCard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logoutCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            logoutCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            logoutCard.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
            logoutCard.heightAnchor.constraint(equalToConstant: 52),
        ])
        let logoutTap = UIControl()
        logoutTap.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
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

        NotificationCenter.default.addObserver(
            self, selector: #selector(accountAuthUpdated),
            name: .luiyoAccountAuthUpdated, object: nil)
        refreshAccount()
        PageFontApplier.apply(pageFont, to: view)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAccount()
        PageFontApplier.apply(pageFont, to: view)
    }

    @objc private func accountAuthUpdated() {
        DispatchQueue.main.async { [weak self] in self?.refreshAccount() }
    }

    private func refreshAccount() {
        let email = AccountProfileStore.currentEmail
        nameValueLabel.text = AccountProfileStore.effectiveDisplayName()
        emailValueLabel.text = email
        avatarImageView.image = AccountProfileStore.avatarImage(for: email) ?? UIImage(named: "DefaultAvatar")
        let authorized = AccountAuthorization.isAuthorized
        authValueLabel.text = authorized ? "已授权" : "未授权"
        authValueLabel.textColor = authorized ? Self.authorizedGold : UIAppColors.secondary
    }

    // MARK: - Editing

    @objc private func changePasswordTapped() {
        let page = ChangePasswordViewController(homeModel: homeModel)
        page.applyPageFont(pageFont)
        present(page, animated: true)
    }

    @objc private func bindCardTapped() {
        let page = BindCardViewController(homeModel: homeModel)
        page.applyPageFont(pageFont)
        present(page, animated: true)
    }

    /// Same logout as the 设置 page's card: confirm, clear the
    /// account session, and let the entry gate hear the
    /// notification and swap the app back to the splash-03 gate.
    @objc private func logoutTapped() {
        let alert = UIAlertController(
            title: "退出登录",
            message: "退出后需要重新登录才能进入。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出登录", style: .destructive) { _ in
            AccountSession.clear()
            NotificationCenter.default.post(name: .accountSessionDidLogout, object: nil)
        })
        present(alert, animated: true)
    }

    @objc private func avatarCardTapped() {
        guard !AccountProfileStore.currentEmail.isEmpty else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func nicknameRowTapped() {
        let email = AccountProfileStore.currentEmail
        guard !email.isEmpty else { return }
        let alert = UIAlertController(title: "修改昵称", message: "昵称只保存在这台设备上，最多 20 个字。", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = AccountProfileStore.effectiveDisplayName()
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 20 else {
                let error = UIAlertController(
                    title: name.isEmpty ? "昵称不能为空" : "昵称不能超过 20 个字",
                    message: nil, preferredStyle: .alert)
                error.addAction(UIAlertAction(title: "好", style: .default))
                self.present(error, animated: true)
                return
            }
            AccountProfileStore.setNickname(name, for: email)
            self.refreshAccount()
        })
        present(alert, animated: true)
    }

    /// Centre square crop + downscale to 512, so whatever the picker
    /// hands back is stored as one fixed-size square avatar.
    private func squaredAvatar(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let flat = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let cg = flat.cgImage else { return flat }
        let side = min(cg.width, cg.height)
        let crop = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)
        guard let cropped = cg.cropping(to: crop) else { return flat }
        let square = UIImage(cgImage: cropped)
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { _ in
            square.draw(in: CGRect(x: 0, y: 0, width: 512, height: 512))
        }
    }

    // MARK: - Rows

    private func nicknameRow() -> UIView {
        let row = UIControl()
        row.addTarget(self, action: #selector(nicknameRowTapped), for: .touchUpInside)
        let titleLabel = UILabel()
        titleLabel.text = "昵称"
        titleLabel.font = UIFont.systemFont(ofSize: 13)
        titleLabel.textColor = UIAppColors.inkDynamic
        nameValueLabel.font = UIFont.systemFont(ofSize: 13)
        nameValueLabel.textColor = UIAppColors.secondary
        nameValueLabel.textAlignment = .right
        nameValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = UIAppColors.inkDynamic
        chevron.contentMode = .scaleAspectFit
        row.addSubview(titleLabel)
        row.addSubview(nameValueLabel)
        row.addSubview(chevron)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        nameValueLabel.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            nameValueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            nameValueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -6),
            nameValueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 48),
        ])
        return row
    }

    /// A tappable title + chevron row (the 修改密码 entry), shaped
    /// like the nickname row but without a value.
    private func actionRow(title: String, action: Selector) -> UIView {
        let row = UIControl()
        row.addTarget(self, action: action, for: .touchUpInside)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 13)
        titleLabel.textColor = UIAppColors.inkDynamic
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = UIAppColors.inkDynamic
        chevron.contentMode = .scaleAspectFit
        row.addSubview(titleLabel)
        row.addSubview(chevron)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            row.heightAnchor.constraint(equalToConstant: 48),
        ])
        return row
    }

    private func infoRow(title: String, valueLabel: UILabel) -> UIView {
        let row = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 13)
        titleLabel.textColor = UIAppColors.inkDynamic
        valueLabel.font = UIFont.systemFont(ofSize: 13)
        valueLabel.textColor = UIAppColors.secondary
        valueLabel.textAlignment = .right
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addSubview(titleLabel)
        row.addSubview(valueLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 48),
        ])
        return row
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = UIAppColors.divider
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return line
    }

    @objc private func backTapped() { dismiss(animated: true) }
}

extension AccountInfoViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        let picked = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        guard let picked else { return }
        AccountProfileStore.setAvatarImage(squaredAvatar(picked), for: AccountProfileStore.currentEmail)
        refreshAccount()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension AccountInfoViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: false)
    }
}

/// The 修改密码 page behind the account page's 修改密码 row
/// (Build 35), in the settings sub-page idiom (shared header, card,
/// edge-swipe back). Three secure fields — 原密码 / 新密码 /
/// 确认新密码 — validated on the client with the register page's
/// own rule (≥ 8 characters, at least one uppercase and one
/// lowercase, via `AccountViewController.passwordIssue`), then
/// sent to the backend's `change_password` action with the session
/// token. The token IS the device id and the backend leaves
/// `current_device_id` untouched, so this device stays signed in
/// after a successful change. Until the updated backend is live
/// the action answers 「未知 action」, which simply lands in the
/// error line like any other server error — no crash path.
final class ChangePasswordViewController: UIViewController {
    private let homeModel: NativeHomeModel
    private var pageFont: UIFont?

    private let oldField = UITextField()
    private let newField = UITextField()
    private let confirmField = UITextField()
    private let errorLabel = UILabel()
    private let submitTap = UIControl()
    private let submitTitle = UILabel()

    init(homeModel: NativeHomeModel) {
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The 设置页 area's chosen font, handed over by the presenting
    /// account page — same mechanism as the other sub-pages.
    func applyPageFont(_ font: UIFont?) {
        pageFont = font
        if isViewLoaded { PageFontApplier.apply(font, to: view) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(nativeHex: homeModel.theme.background)
        installEdgeSwipeBack()

        let header = luiyoPageHeader(title: "修改密码", backAction: #selector(backTapped), target: self)
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
        card.luiyoApplyGlassCardSurface(radius: 26, useBlur: homeModel.useBlur, tint: UIColor(nativeHex: homeModel.theme.card))
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
        configure(oldField, placeholder: "请输入原密码", returnKey: .next)
        configure(newField, placeholder: "请输入新密码", returnKey: .next)
        configure(confirmField, placeholder: "再次输入新密码", returnKey: .done)
        rows.addArrangedSubview(fieldRow(title: "原密码", field: oldField))
        rows.addArrangedSubview(divider())
        rows.addArrangedSubview(fieldRow(title: "新密码", field: newField))
        rows.addArrangedSubview(divider())
        rows.addArrangedSubview(fieldRow(title: "确认新密码", field: confirmField))

        let hint = UILabel()
        hint.text = "新密码至少 8 个字符，需含大写和小写字母各 1 个。"
        hint.font = UIFont.systemFont(ofSize: 12)
        hint.textColor = UIAppColors.secondary
        view.addSubview(hint)
        hint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            hint.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 10),
        ])

        errorLabel.font = UIFont.systemFont(ofSize: 12.5)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        view.addSubview(errorLabel)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            errorLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 6),
        ])

        // Submit: a standalone card like the logout cards, with a
        // dark title instead of red.
        let submitCard = UIView()
        submitCard.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        submitCard.layer.cornerRadius = 26
        submitCard.clipsToBounds = true
        submitCard.luiyoApplyGlassCardSurface(radius: 26, useBlur: homeModel.useBlur, tint: UIColor(nativeHex: homeModel.theme.card))
        view.addSubview(submitCard)
        submitCard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            submitCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            submitCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            submitCard.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            submitCard.heightAnchor.constraint(equalToConstant: 52),
        ])
        submitTap.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submitCard.addSubview(submitTap)
        submitTap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            submitTap.leadingAnchor.constraint(equalTo: submitCard.leadingAnchor),
            submitTap.trailingAnchor.constraint(equalTo: submitCard.trailingAnchor),
            submitTap.topAnchor.constraint(equalTo: submitCard.topAnchor),
            submitTap.bottomAnchor.constraint(equalTo: submitCard.bottomAnchor),
        ])
        submitTitle.text = "确认修改"
        submitTitle.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        submitTitle.textColor = UIAppColors.inkDynamic
        submitTitle.textAlignment = .center
        submitTap.addSubview(submitTitle)
        submitTitle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            submitTitle.centerXAnchor.constraint(equalTo: submitTap.centerXAnchor),
            submitTitle.centerYAnchor.constraint(equalTo: submitTap.centerYAnchor),
        ])

        PageFontApplier.apply(pageFont, to: view)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PageFontApplier.apply(pageFont, to: view)
    }

    private func configure(_ field: UITextField, placeholder: String, returnKey: UIReturnKeyType) {
        field.isSecureTextEntry = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.textContentType = .password
        field.font = UIFont.systemFont(ofSize: 13)
        field.textColor = UIAppColors.inkDynamic
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIAppColors.secondary])
        field.returnKeyType = returnKey
        field.delegate = self
    }

    private func fieldRow(title: String, field: UITextField) -> UIView {
        let row = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 13)
        titleLabel.textColor = UIAppColors.inkDynamic
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        row.addSubview(titleLabel)
        row.addSubview(field)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 76),
            field.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            field.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 52),
        ])
        return row
    }

    private func divider() -> UIView {
        let line = UIView()
        line.backgroundColor = UIAppColors.divider
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        return line
    }

    // MARK: - Submit

    private func showError(_ message: String, field: UITextField?) {
        errorLabel.text = message
        errorLabel.isHidden = false
        if let field { field.becomeFirstResponder() }
    }

    private func setBusy(_ busy: Bool) {
        submitTap.isEnabled = !busy
        submitTitle.text = busy ? "正在提交…" : "确认修改"
    }

    @objc private func submitTapped() {
        let old = oldField.text ?? ""
        let new = newField.text ?? ""
        let confirm = confirmField.text ?? ""
        if old.isEmpty { showError("请输入原密码。", field: oldField); return }
        if new.isEmpty { showError("请输入新密码。", field: newField); return }
        if let issue = AccountViewController.passwordIssue(new) {
            showError(issue, field: newField); return
        }
        if new == old { showError("新密码不能与原密码相同。", field: newField); return }
        if confirm != new { showError("两次输入的新密码不一致。", field: confirmField); return }
        guard let token = AccountSession.token else {
            showError("登录已过期，请重新登录。", field: nil); return
        }
        errorLabel.isHidden = true
        view.endEditing(true)
        setBusy(true)
        AccountAPI.post("change_password", [
            "token": token, "old_password": old, "new_password": new,
        ]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let failure):
                self.setBusy(false)
                if case .error(let message) = AccountAPI.outcome(.failure(failure)) {
                    self.showError(message, field: nil)
                }
            case .success(let json):
                if (json["ok"] as? Bool) == true {
                    self.submitTap.isEnabled = false
                    self.submitTitle.text = "修改成功"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        self.dismiss(animated: true)
                    }
                } else {
                    self.setBusy(false)
                    let message = json["error"] as? String ?? "修改失败，请稍后再试。"
                    if (json["code"] as? String) == "wrong_password" {
                        self.showError(message, field: self.oldField)
                    } else {
                        self.showError(message, field: nil)
                    }
                }
            }
        }
    }

    @objc private func backTapped() { dismiss(animated: true) }
}

extension ChangePasswordViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ field: UITextField) -> Bool {
        if field === oldField { newField.becomeFirstResponder() }
        else if field === newField { confirmField.becomeFirstResponder() }
        else { field.resignFirstResponder() }
        return true
    }
}

extension ChangePasswordViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: false)
    }
}

/// The 输入卡密授权 page behind the account page's 输入卡密授权
/// row (Build 39), in the same settings sub-page idiom as
/// `ChangePasswordViewController` (shared header, card, edge-swipe
/// back). One field for the card key — keyed in with the register
/// form's own convention (all-caps keyboard, whitespace trimmed) —
/// and a 绑定授权 submit. The call is the backend's existing
/// `bind_card` action with the session token; the server's answer
/// decides everything (invalid / already-used keys surface their
/// server message verbatim, and an already-authorized account may
/// still submit — no client-side renewal rules). On success the
/// account status is re-fetched through the same `fetchStatus`
/// flow the entry gate uses and applied via
/// `AccountAuthorization.update`, so this page's 账号授权 row and
/// the 我的 hero reflect the new state the moment the user pops
/// back; the 30 s heartbeat remains the backstop.
final class BindCardViewController: UIViewController {
    private let homeModel: NativeHomeModel
    private var pageFont: UIFont?

    private let cardField = UITextField()
    private let errorLabel = UILabel()
    private let submitTap = UIControl()
    private let submitTitle = UILabel()

    init(homeModel: NativeHomeModel) {
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The 设置页 area's chosen font, handed over by the presenting
    /// account page — same mechanism as the other sub-pages.
    func applyPageFont(_ font: UIFont?) {
        pageFont = font
        if isViewLoaded { PageFontApplier.apply(font, to: view) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(nativeHex: homeModel.theme.background)
        installEdgeSwipeBack()

        let header = luiyoPageHeader(title: "输入卡密授权", backAction: #selector(backTapped), target: self)
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
        card.luiyoApplyGlassCardSurface(radius: 26, useBlur: homeModel.useBlur, tint: UIColor(nativeHex: homeModel.theme.card))
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
        configure(cardField)
        rows.addArrangedSubview(fieldRow(title: "卡密", field: cardField))

        let hint = UILabel()
        hint.text = "卡密格式为 LUI-备注-随机码，绑定成功后授权状态立即刷新。"
        hint.font = UIFont.systemFont(ofSize: 12)
        hint.textColor = UIAppColors.secondary
        hint.numberOfLines = 0
        view.addSubview(hint)
        hint.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            hint.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 10),
        ])

        errorLabel.font = UIFont.systemFont(ofSize: 12.5)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        view.addSubview(errorLabel)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            errorLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 6),
        ])

        // Submit: a standalone card like the logout cards, with a
        // dark title instead of red.
        let submitCard = UIView()
        submitCard.backgroundColor = UIColor(nativeHex: homeModel.theme.card)
        submitCard.layer.cornerRadius = 26
        submitCard.clipsToBounds = true
        submitCard.luiyoApplyGlassCardSurface(radius: 26, useBlur: homeModel.useBlur, tint: UIColor(nativeHex: homeModel.theme.card))
        view.addSubview(submitCard)
        submitCard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            submitCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            submitCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            submitCard.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            submitCard.heightAnchor.constraint(equalToConstant: 52),
        ])
        submitTap.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submitCard.addSubview(submitTap)
        submitTap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            submitTap.leadingAnchor.constraint(equalTo: submitCard.leadingAnchor),
            submitTap.trailingAnchor.constraint(equalTo: submitCard.trailingAnchor),
            submitTap.topAnchor.constraint(equalTo: submitCard.topAnchor),
            submitTap.bottomAnchor.constraint(equalTo: submitCard.bottomAnchor),
        ])
        submitTitle.text = "绑定授权"
        submitTitle.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        submitTitle.textColor = UIAppColors.inkDynamic
        submitTitle.textAlignment = .center
        submitTap.addSubview(submitTitle)
        submitTitle.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            submitTitle.centerXAnchor.constraint(equalTo: submitTap.centerXAnchor),
            submitTitle.centerYAnchor.constraint(equalTo: submitTap.centerYAnchor),
        ])

        PageFontApplier.apply(pageFont, to: view)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PageFontApplier.apply(pageFont, to: view)
    }

    private func configure(_ field: UITextField) {
        // Same convention as the register form's card field: an
        // all-caps keyboard (card keys are `LUI-<备注>-<random>`),
        // no autocorrection, and the value is trimmed on submit.
        field.autocapitalizationType = .allCharacters
        field.autocorrectionType = .no
        field.font = UIFont.systemFont(ofSize: 13)
        field.textColor = UIAppColors.inkDynamic
        field.attributedPlaceholder = NSAttributedString(
            string: "请输入卡密",
            attributes: [.foregroundColor: UIAppColors.secondary])
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        field.delegate = self
    }

    private func fieldRow(title: String, field: UITextField) -> UIView {
        let row = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 13)
        titleLabel.textColor = UIAppColors.inkDynamic
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        row.addSubview(titleLabel)
        row.addSubview(field)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 76),
            field.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            field.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 52),
        ])
        return row
    }

    // MARK: - Submit

    private func showError(_ message: String, refocus: Bool) {
        errorLabel.text = message
        errorLabel.isHidden = false
        if refocus { cardField.becomeFirstResponder() }
    }

    private func setBusy(_ busy: Bool) {
        submitTap.isEnabled = !busy
        submitTitle.text = busy ? "正在绑定…" : "绑定授权"
    }

    @objc private func submitTapped() {
        let card = (cardField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if card.isEmpty { showError("请输入卡密。", refocus: true); return }
        guard let token = AccountSession.token else {
            showError("登录已过期，请重新登录。", refocus: false); return
        }
        errorLabel.isHidden = true
        view.endEditing(true)
        setBusy(true)
        AccountAPI.post("bind_card", ["token": token, "card": card]) { [weak self] result in
            guard let self else { return }
            switch AccountAPI.outcome(result) {
            case .error(let message):
                self.setBusy(false)
                self.showError(message, refocus: false)
            case .ok:
                // Refresh through the gate's own status flow so the
                // mirrors (and with them the account page + hero)
                // carry the server's verdict, never a local guess.
                AccountAPI.fetchStatus { [weak self] status in
                    guard let self else { return }
                    if case .ok(let email, let svip, let svipExpiresAt, let displayName) = status {
                        AccountAuthorization.update(
                            email: email, svip: svip,
                            svipExpiresAt: svipExpiresAt, displayName: displayName)
                    }
                    self.submitTap.isEnabled = false
                    self.submitTitle.text = "绑定成功"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        self.dismiss(animated: true)
                    }
                }
            }
        }
    }

    @objc private func backTapped() { dismiss(animated: true) }
}

extension BindCardViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ field: UITextField) -> Bool {
        submitTapped()
        return true
    }
}

extension BindCardViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        SlideFadeTransitionAnimator(presenting: false)
    }
}

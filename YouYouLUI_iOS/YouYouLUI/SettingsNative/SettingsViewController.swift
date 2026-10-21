import Combine
import UIKit
import UniformTypeIdentifiers

/// A settings fold: glass card with a tappable header (icon in a circle,
/// title, subtitle, chevron) and a collapsible content area. Collapsed it is
/// capsule-shaped like the reference design; expanded it opens to radius 22.
final class FoldView: UIView {
    let card = GlassCardView(radius: 24)
    let contentView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView()
    private(set) var expanded = false
    var onToggle: (() -> Void)?
    private var lastUseBlur = false
    private var lastTint: UIColor = .white

    init(icon: String, iconImage: UIImage? = nil, title: String, subtitle: String) {
        super.init(frame: .zero)
        addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let header = UIControl()
        header.addTarget(self, action: #selector(headerTapped), for: .touchUpInside)
        if let iconImage {
            iconView.image = iconImage
        } else {
            iconView.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium))
        }
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIAppColors.ink
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.text = subtitle
        subtitleLabel.font = UIFont.systemFont(ofSize: 8)
        subtitleLabel.textColor = UIAppColors.secondary
        subtitleLabel.isHidden = true
        chevron.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        chevron.tintColor = UIAppColors.ink
        chevron.contentMode = .scaleAspectFit

        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 0
        card.content.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.content.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.content.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.content.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.content.bottomAnchor),
        ])
        inner.addArrangedSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        header.heightAnchor.constraint(equalToConstant: 42).isActive = true
        header.addSubview(iconView)
        header.addSubview(titleLabel)
        header.addSubview(subtitleLabel)
        header.addSubview(chevron)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 21),
            iconView.heightAnchor.constraint(equalToConstant: 21),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            subtitleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        contentView.isHidden = true
        contentView.clipsToBounds = true
        card.content.clipsToBounds = true
        card.content.layer.cornerRadius = 24
        inner.addArrangedSubview(contentView)
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func headerTapped() { onToggle?() }

    func setSubtitle(_ text: String) { subtitleLabel.text = text }

    func setExpanded(_ value: Bool, animated: Bool) {
        expanded = value
        // No height animation: stretching a glass surface frame-by-frame
        // makes its backdrop sampling lag, so neighbouring folds' text
        // shows through the card mid-animation (the overlap/ghosting seen
        // on device). The layout switches instantly instead; only the
        // chevron turns and the content fades in, which stays clean.
        contentView.isHidden = !value
        subtitleLabel.isHidden = !value
        card.surface.glassRadius = value ? 26 : 24
        card.content.layer.cornerRadius = value ? 26 : 24
        card.configure(useBlur: lastUseBlur, tint: lastTint)
        superview?.layoutIfNeeded()
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                self.chevron.transform = value ? CGAffineTransform(rotationAngle: .pi) : .identity
            }
            if value {
                contentView.alpha = 0
                UIView.animate(withDuration: 0.18) { self.contentView.alpha = 1 }
            }
        } else {
            chevron.transform = value ? CGAffineTransform(rotationAngle: .pi) : .identity
        }
    }

    func configureGlass(useBlur: Bool, tint: UIColor) {
        lastUseBlur = useBlur
        lastTint = tint
        card.configure(useBlur: useBlur, tint: tint)
    }

    func refreshAppearance() {
        iconView.tintColor = UIAppColors.inkDynamic
        titleLabel.textColor = UIAppColors.inkDynamic
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshAppearance()
    }
}

/// Settings page (UIKit): identity hero, activation card, theme / guide /
/// changelog folds and the update check row — same content and behaviour as
/// the previous settings page, rendered with UIKit and the UIKit material.
final class SettingsViewController: UIViewController {
    let model: SettingsNativeModel
    let homeModel: NativeHomeModel
    private let updater = AppUpdateChecker()

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let heroContainer = UIView()
    private var heroView: UIView?
    private let activationCard = GlassCardView(radius: 26)
    private let authStatus = UILabel()
    private let codeField = UITextField()
    private let activateButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var themeFold: FoldView!
    private var guideFold: FoldView!
    private var changelogFold: FoldView!
    private let updateCard = GlassCardView(radius: 26)
    private let appSettingsCard = GlassCardView(radius: 26)
    private let accountLogoutCard = GlassCardView(radius: 26)
    private var changelogCards: [GlassCardView] = []
    private var backgroundWell: UIColorWell!
    private var minimizeSwitch: UISwitch!
    private var appearanceSeg: PillSegmentedControl!
    private var materialSeg: PillSegmentedControl!
    private var bottomSearchSeg: PillSegmentedControl!
    private var fontSubtitleLabel: UILabel?
    private var authIconView: UIImageView?
    private var cancellables = Set<AnyCancellable>()


    init(model: SettingsNativeModel, homeModel: NativeHomeModel) {
        self.model = model
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        stack.axis = .vertical
        stack.spacing = 8
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -28),
        ])

        let title = UILabel()
        title.text = "我的"
        title.font = UIFont.systemFont(ofSize: 25, weight: .bold)
        title.textColor = UIAppColors.inkDynamic
        stack.addArrangedSubview(title)
        let subtitle = UILabel()
        subtitle.text = "外观、使用说明与更新日志"
        subtitle.font = UIFont.systemFont(ofSize: 12)
        subtitle.textColor = UIAppColors.secondary
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(10, after: subtitle)

        heroContainer.translatesAutoresizingMaskIntoConstraints = false
        heroContainer.heightAnchor.constraint(equalToConstant: 116).isActive = true
        stack.addArrangedSubview(heroContainer)
        rebuildHero()

        buildActivationCard()
        stack.addArrangedSubview(activationCard)

        themeFold = FoldView(icon: "circle.lefthalf.filled", iconImage: luiyoBundledIcon("theme"), title: "外观", subtitle: "卡片材质、背景、按钮与字体")
        themeFold.onToggle = { [weak self] in
            guard let self else { return }
            self.model.themeExpanded.toggle()
        }
        let themeContent = buildThemeContent()
        themeFold.contentView.addSubview(themeContent)
        themeContent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            themeContent.leadingAnchor.constraint(equalTo: themeFold.contentView.leadingAnchor),
            themeContent.trailingAnchor.constraint(equalTo: themeFold.contentView.trailingAnchor),
            themeContent.topAnchor.constraint(equalTo: themeFold.contentView.topAnchor),
            themeContent.bottomAnchor.constraint(equalTo: themeFold.contentView.bottomAnchor),
        ])
        stack.addArrangedSubview(themeFold)

        guideFold = FoldView(icon: "questionmark", iconImage: luiyoBundledIcon("guide"), title: "使用说明", subtitle: "查看功能说明与操作方法")
        guideFold.onToggle = { [weak self] in self?.model.guideExpanded.toggle() }
        let guideContent = buildGuideContent()
        guideFold.contentView.addSubview(guideContent)
        guideContent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            guideContent.leadingAnchor.constraint(equalTo: guideFold.contentView.leadingAnchor),
            guideContent.trailingAnchor.constraint(equalTo: guideFold.contentView.trailingAnchor),
            guideContent.topAnchor.constraint(equalTo: guideFold.contentView.topAnchor),
            guideContent.bottomAnchor.constraint(equalTo: guideFold.contentView.bottomAnchor),
        ])
        stack.addArrangedSubview(guideFold)

        changelogFold = FoldView(icon: "clock.arrow.circlepath", iconImage: luiyoBundledIcon("changelog"), title: "更新日志", subtitle: "Version 1.0.8 · 当前版本")
        changelogFold.onToggle = { [weak self] in self?.model.changelogExpanded.toggle() }
        let changelogContent = buildChangelogContent()
        changelogFold.contentView.addSubview(changelogContent)
        changelogContent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            changelogContent.leadingAnchor.constraint(equalTo: changelogFold.contentView.leadingAnchor),
            changelogContent.trailingAnchor.constraint(equalTo: changelogFold.contentView.trailingAnchor),
            changelogContent.topAnchor.constraint(equalTo: changelogFold.contentView.topAnchor),
            changelogContent.bottomAnchor.constraint(equalTo: changelogFold.contentView.bottomAnchor),
        ])
        stack.addArrangedSubview(changelogFold)

        buildUpdateCard()
        stack.addArrangedSubview(updateCard)

        buildAppSettingsCard()
        stack.addArrangedSubview(appSettingsCard)

        buildAccountLogoutCard()
        stack.addArrangedSubview(accountLogoutCard)

        let footer = UILabel()
        footer.text = "特别鸣谢 Mk · 作者：优优\n仅供学习交流"
        footer.numberOfLines = 2
        footer.textAlignment = .center
        footer.font = UIFont.systemFont(ofSize: 12)
        footer.textColor = UIAppColors.secondary
        stack.addArrangedSubview(footer)
        stack.setCustomSpacing(8, after: updateCard)
        stack.setCustomSpacing(8, after: appSettingsCard)
        stack.setCustomSpacing(12, after: accountLogoutCard)

        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshFromModel() }
            .store(in: &cancellables)
        model.$heroRefreshToken
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshHero() }
            .store(in: &cancellables)
        model.$themeExpanded.sink { [weak self] value in self?.themeFold?.setExpanded(value, animated: true) }.store(in: &cancellables)
        model.$guideExpanded.sink { [weak self] value in self?.guideFold?.setExpanded(value, animated: true) }.store(in: &cancellables)
        model.$changelogExpanded.sink { [weak self] value in self?.changelogFold?.setExpanded(value, animated: true) }.store(in: &cancellables)
        model.$pendingScroll
            .receive(on: DispatchQueue.main)
            .sink { [weak self] target in
                guard let self, let target else { return }
                self.model.pendingScroll = nil
                let fold = target == "guide" ? self.guideFold : self.changelogFold
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let rect = fold!.convert(fold!.bounds, to: self.scrollView)
                    self.scrollView.scrollRectToVisible(rect.insetBy(dx: 0, dy: -8), animated: true)
                }
            }
            .store(in: &cancellables)
        homeModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTheme() }
            .store(in: &cancellables)
        refreshTheme()
        refreshFromModel()
        themeFold.setExpanded(model.themeExpanded, animated: false)
        guideFold.setExpanded(model.guideExpanded, animated: false)
        changelogFold.setExpanded(model.changelogExpanded, animated: false)
    }

    // MARK: - Hero

    private func rebuildHero() {
        heroView?.removeFromSuperview()
        let hero = LUIYoCreateSettingsHero(
            { [weak self] in
                guard let self else { return }
                self.model.guideExpanded.toggle()
                if self.model.guideExpanded { self.model.pendingScroll = "guide" }
            },
            { [weak self] in
                guard let self else { return }
                self.model.changelogExpanded.toggle()
                if self.model.changelogExpanded { self.model.pendingScroll = "changelog" }
            },
            { [weak self] in self?.model.onEditAvatar?() },
            { [weak self] in self?.model.onEditName?() }
        )
        heroView = hero
        heroContainer.addSubview(hero)
        hero.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hero.leadingAnchor.constraint(equalTo: heroContainer.leadingAnchor),
            hero.trailingAnchor.constraint(equalTo: heroContainer.trailingAnchor),
            hero.topAnchor.constraint(equalTo: heroContainer.topAnchor),
            hero.bottomAnchor.constraint(equalTo: heroContainer.bottomAnchor),
        ])
        refreshHero()
    }

    private func refreshHero() {
        guard let hero = heroView else { return }
        LUIYoRefreshSettingsHero(hero)
        LUIYoSetSettingsHeroFont(hero, model.fontController?.font)
    }

    // MARK: - Activation

    private func buildActivationCard() {
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 10
        activationCard.content.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: activationCard.content.leadingAnchor, constant: 15),
            inner.trailingAnchor.constraint(equalTo: activationCard.content.trailingAnchor, constant: -15),
            inner.topAnchor.constraint(equalTo: activationCard.content.topAnchor, constant: 14),
            inner.bottomAnchor.constraint(equalTo: activationCard.content.bottomAnchor, constant: -14),
        ])
        let titleRow = UIStackView()
        titleRow.axis = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .center
        let shield = UIImageView(image: luiyoBundledIcon(model.isAuthorized ? "auth-yes" : "auth-no"))
        authIconView = shield
        shield.tintColor = UIAppColors.inkDynamic
        shield.contentMode = .scaleAspectFit
        shield.translatesAutoresizingMaskIntoConstraints = false
        shield.widthAnchor.constraint(equalToConstant: 19).isActive = true
        shield.heightAnchor.constraint(equalToConstant: 19).isActive = true
        let title = UILabel()
        title.text = "激活授权"
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = UIAppColors.inkDynamic
        titleRow.addArrangedSubview(shield)
        titleRow.addArrangedSubview(title)
        inner.addArrangedSubview(titleRow)

        authStatus.font = UIFont.systemFont(ofSize: 10)
        authStatus.numberOfLines = 0
        inner.addArrangedSubview(authStatus)

        let fieldRow = UIStackView()
        fieldRow.axis = .horizontal
        fieldRow.spacing = 10
        fieldRow.alignment = .center
        codeField.placeholder = "输入卡密"
        codeField.font = UIFont.systemFont(ofSize: 10)
        codeField.autocapitalizationType = .allCharacters
        codeField.autocorrectionType = .no
        codeField.returnKeyType = .go
        codeField.backgroundColor = UIColor(red: 120 / 255, green: 120 / 255, blue: 128 / 255, alpha: 0.08)
        codeField.layer.cornerRadius = 22
        codeField.layer.borderWidth = 1 / UIScreen.main.scale
        codeField.layer.borderColor = UIAppColors.dividerStrong.cgColor
        codeField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        codeField.leftViewMode = .always
        codeField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        codeField.rightViewMode = .always
        codeField.delegate = self
        codeField.translatesAutoresizingMaskIntoConstraints = false
        codeField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        fieldRow.addArrangedSubview(codeField)

        activateButton.setTitle("激活", for: .normal)
        activateButton.setTitleColor(.white, for: .normal)
        activateButton.titleLabel?.font = UIFont.systemFont(ofSize: 10)
        activateButton.backgroundColor = UIAppColors.accentPurple
        activateButton.layer.cornerRadius = 24
        activateButton.addTarget(self, action: #selector(submitLicense), for: .touchUpInside)
        activateButton.translatesAutoresizingMaskIntoConstraints = false
        activateButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        activateButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        fieldRow.addArrangedSubview(activateButton)
        inner.addArrangedSubview(fieldRow)

        spinner.hidesWhenStopped = true
        activateButton.addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: activateButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: activateButton.centerYAnchor),
        ])
    }

    @objc private func submitLicense() {
        let code = (codeField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        codeField.resignFirstResponder()
        model.onSubmitLicense?(code)
    }

    // MARK: - Theme content

    private func smallButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(UIAppColors.inkDynamic, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12.5)
        button.backgroundColor = UIColor(red: 120 / 255, green: 120 / 255, blue: 128 / 255, alpha: 0.10)
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func themeRow(title: String, subtitle: String?, control: UIView, divider: Bool) -> UIView {
        let row = UIView()
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 12)
        titleLabel.textColor = UIAppColors.inkDynamic
        row.addSubview(titleLabel)
        row.addSubview(control)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        if let subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = UIFont.systemFont(ofSize: 10)
            subtitleLabel.textColor = UIAppColors.secondary
            subtitleLabel.tag = 77
            row.addSubview(subtitleLabel)
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 15),
                titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
                subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
                subtitleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
                control.leadingAnchor.constraint(greaterThanOrEqualTo: subtitleLabel.trailingAnchor, constant: 10),
            ])
        } else {
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 15),
                titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 15),
                titleLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -15),
                control.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
            ])
        }
        NSLayoutConstraint.activate([
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -15),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        if divider {
            let line = UIView()
            line.backgroundColor = UIAppColors.divider
            row.addSubview(line)
            line.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 15),
                line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                line.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            ])
        }
        return row
    }

    /// The official system colour well: iOS draws it (colour disc with the
    /// spectrum ring) and presents the official colour picker on tap;
    /// changes arrive as `.valueChanged`.
    private func colorWell(title: String) -> UIColorWell {
        let well = UIColorWell()
        well.title = title
        well.supportsAlpha = false
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 30).isActive = true
        well.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return well
    }

    private func buildThemeContent() -> UIView {
        let container = UIView()
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 0
        container.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inner.topAnchor.constraint(equalTo: container.topAnchor),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        let topLine = UIView()
        topLine.backgroundColor = UIAppColors.divider
        topLine.translatesAutoresizingMaskIntoConstraints = false
        topLine.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        inner.addArrangedSubview(topLine)

        appearanceSeg = PillSegmentedControl()
        appearanceSeg.options = [("system", "系统"), ("light", "浅色"), ("dark", "深色")]
        appearanceSeg.setSelectedValue(model.appearanceMode)
        appearanceSeg.onChange = { [weak self] value in self?.model.appearanceMode = value }
        appearanceSeg.translatesAutoresizingMaskIntoConstraints = false
        appearanceSeg.widthAnchor.constraint(equalToConstant: 140).isActive = true
        inner.addArrangedSubview(themeRow(title: "外观模式", subtitle: "跟随系统或固定浅色 / 深色", control: appearanceSeg, divider: true))

        materialSeg = PillSegmentedControl()
        materialSeg.options = [("liquid", "液态玻璃"), ("blur", "原生磨砂")]
        materialSeg.setSelectedValue(model.cardMaterial)
        materialSeg.onChange = { [weak self] value in self?.model.cardMaterial = value }
        materialSeg.translatesAutoresizingMaskIntoConstraints = false
        materialSeg.widthAnchor.constraint(equalToConstant: 132).isActive = true
        inner.addArrangedSubview(themeRow(title: "卡片材质", subtitle: "iOS 26+ 原生液态玻璃 / UIKit 原生磨砂", control: materialSeg, divider: true))

        backgroundWell = colorWell(title: "背景颜色")
        backgroundWell.addTarget(self, action: #selector(backgroundWellChanged), for: .valueChanged)
        let bgControl = UIStackView(arrangedSubviews: [backgroundWell, smallButton("恢复", action: #selector(resetBackground))])
        bgControl.axis = .horizontal
        bgControl.spacing = 8
        bgControl.alignment = .center
        inner.addArrangedSubview(themeRow(title: "背景颜色", subtitle: "浅色背景", control: bgControl, divider: true))

        bottomSearchSeg = PillSegmentedControl()
        bottomSearchSeg.options = [("off", "关闭"), ("merged", "合并"), ("separate", "分开")]
        bottomSearchSeg.setSelectedValue(model.bottomSearchLayout)
        bottomSearchSeg.onChange = { [weak self] value in self?.model.bottomSearchLayout = value }
        bottomSearchSeg.translatesAutoresizingMaskIntoConstraints = false
        bottomSearchSeg.widthAnchor.constraint(equalToConstant: 150).isActive = true
        inner.addArrangedSubview(themeRow(title: "底栏搜索按钮", subtitle: "关闭后使用顶部搜索框", control: bottomSearchSeg, divider: true))

        minimizeSwitch = UISwitch.luiyoSmall()
        minimizeSwitch.isOn = model.minimizeBottomBar
        minimizeSwitch.addTarget(self, action: #selector(minimizeChanged(_:)), for: .valueChanged)
        inner.addArrangedSubview(themeRow(title: "滚动时缩小底栏", subtitle: "向下滚动缩小，向上滚动恢复", control: minimizeSwitch, divider: true))

        // Custom font is an entry row now: one tap opens the choices
        // (import / restore) instead of crowding the row with buttons.
        let fontChevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        fontChevron.tintColor = UIAppColors.inkDynamic
        fontChevron.contentMode = .scaleAspectFit
        fontChevron.translatesAutoresizingMaskIntoConstraints = false
        fontChevron.widthAnchor.constraint(equalToConstant: 16).isActive = true
        fontChevron.heightAnchor.constraint(equalToConstant: 16).isActive = true
        let fontRow = themeRow(title: "自定义字体", subtitle: nil, control: fontChevron, divider: false)
        fontSubtitleLabel = fontRow.viewWithTag(77) as? UILabel
        fontRow.isUserInteractionEnabled = true
        fontRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fontEntryTapped)))
        inner.addArrangedSubview(fontRow)
        let fontSpacer = UIView()
        fontSpacer.translatesAutoresizingMaskIntoConstraints = false
        fontSpacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        inner.addArrangedSubview(fontSpacer)
        return container
    }

    @objc private func minimizeChanged(_ sender: UISwitch) { model.minimizeBottomBar = sender.isOn }
    @objc private func resetBackground() { model.resetBackgroundColor() }
    @objc private func resetCard() { model.resetCardColor() }
    @objc private func backgroundWellChanged() {
        if let color = backgroundWell.selectedColor { model.updateBackgroundColor(color.nativeHex) }
    }
    @objc private func fontEntryTapped() {
        guard let controller = model.fontController else { return }
        let page = FontSettingsViewController(fontController: controller, homeModel: homeModel)
        page.modalPresentationStyle = .fullScreen
        page.onChanged = { [weak self] in
            guard let self else { return }
            self.model.customFontName = controller.library.summary()
            self.model.hasCustomFont = controller.library.hasAnyCustomSelection
            self.fontSubtitleLabel?.text = self.model.customFontName
        }
        present(page, animated: true)
    }

    // MARK: - Guide / changelog content

    private func paddedContent(_ inner: UIStackView) -> UIView {
        let container = UIView()
        container.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 15),
            inner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -15),
            inner.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
        ])
        let topLine = UIView()
        topLine.backgroundColor = UIAppColors.divider
        topLine.translatesAutoresizingMaskIntoConstraints = false
        topLine.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        container.addSubview(topLine)
        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        return container
    }

    private func buildGuideContent() -> UIView {
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 10
        for section in SettingsContent.guide {
            let label = UILabel()
            label.numberOfLines = 0
                let text = NSMutableAttributedString()
                let para = NSMutableParagraphStyle()
                para.lineSpacing = 3
                text.append(NSAttributedString(string: "•  ", attributes: [
                    .font: UIFont.systemFont(ofSize: 13.5),
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: para,
                ]))
                text.append(NSAttributedString(string: section.title, attributes: [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .semibold),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: para,
                ]))
                text.append(NSAttributedString(string: section.body, attributes: [
                    .font: UIFont.systemFont(ofSize: 13.5),
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: para,
                ]))
                label.attributedText = text
                inner.addArrangedSubview(label)
        }
        return paddedContent(inner)
    }

    private func tagColor(_ tag: String) -> UIColor {
        switch tag {
        case "新增": return UIColor(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255, alpha: 1)
        case "优化": return UIColor(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255, alpha: 1)
        case "修复": return UIColor(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255, alpha: 1)
        default: return UIAppColors.secondary
        }
    }

    private func buildChangelogContent() -> UIView {
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 12
        for version in SettingsContent.changelog {
            let cardView = GlassCardView(radius: 26)
            cardView.configure(useBlur: homeModel.useBlur, tint: UIColor(nativeHex: homeModel.theme.card))
            changelogCards.append(cardView)
            let block = UIStackView()
            block.axis = .vertical
            block.spacing = 10
            cardView.content.addSubview(block)
            block.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                block.leadingAnchor.constraint(equalTo: cardView.content.leadingAnchor, constant: 14),
                block.trailingAnchor.constraint(equalTo: cardView.content.trailingAnchor, constant: -14),
                block.topAnchor.constraint(equalTo: cardView.content.topAnchor, constant: 13),
                block.bottomAnchor.constraint(equalTo: cardView.content.bottomAnchor, constant: -13),
            ])
            let head = UIStackView()
            head.axis = .horizontal
            head.spacing = 8
            head.alignment = .center
            let title = UILabel()
            title.text = version.title
            title.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
            title.textColor = .label
            head.addArrangedSubview(title)
            if version.isCurrent {
                let current = UILabel()
                current.text = "当前版本"
                current.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
                current.textColor = .systemBlue
                head.addArrangedSubview(current)
            }
            head.addArrangedSubview(UIView())
            block.addArrangedSubview(head)
            for entry in version.entries {
                let label = UILabel()
                label.numberOfLines = 0
                let text = NSMutableAttributedString()
                let para = NSMutableParagraphStyle()
                para.lineSpacing = 3
                if let tag = entry.tag, !tag.isEmpty {
                    text.append(NSAttributedString(string: tag + "  ", attributes: [
                        .font: UIFont.systemFont(ofSize: 13),
                        .foregroundColor: tagColor(tag),
                        .paragraphStyle: para,
                    ]))
                }
                text.append(NSAttributedString(string: entry.text, attributes: [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: para,
                ]))
                label.attributedText = text
                block.addArrangedSubview(label)
            }
            inner.addArrangedSubview(cardView)
        }
        return paddedContent(inner)
    }

    // MARK: - Update row

    private func buildUpdateCard() {
        let tap = UIControl()
        tap.addTarget(self, action: #selector(updateTapped), for: .touchUpInside)
        updateCard.content.addSubview(tap)
        tap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tap.leadingAnchor.constraint(equalTo: updateCard.content.leadingAnchor),
            tap.trailingAnchor.constraint(equalTo: updateCard.content.trailingAnchor),
            tap.topAnchor.constraint(equalTo: updateCard.content.topAnchor),
            tap.bottomAnchor.constraint(equalTo: updateCard.content.bottomAnchor),
            tap.heightAnchor.constraint(equalToConstant: 42),
        ])
        let icon = UIImageView(image: luiyoBundledIcon("update"))
        icon.tintColor = UIAppColors.inkDynamic
        icon.contentMode = .scaleAspectFit
        let title = UILabel()
        title.text = "检查更新"
        title.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = UIAppColors.inkDynamic
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = UIAppColors.inkDynamic
        tap.addSubview(icon)
        tap.addSubview(title)
        tap.addSubview(chevron)
        icon.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: tap.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 21),
            icon.heightAnchor.constraint(equalToConstant: 21),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: tap.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
        ])
    }

    @objc private func updateTapped() {
        let page = UpdateCheckViewController(updater: updater, homeModel: homeModel)
        present(page, animated: true)
    }

    private func buildAppSettingsCard() {
        let tap = UIControl()
        tap.addTarget(self, action: #selector(appSettingsTapped), for: .touchUpInside)
        appSettingsCard.content.addSubview(tap)
        tap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tap.leadingAnchor.constraint(equalTo: appSettingsCard.content.leadingAnchor),
            tap.trailingAnchor.constraint(equalTo: appSettingsCard.content.trailingAnchor),
            tap.topAnchor.constraint(equalTo: appSettingsCard.content.topAnchor),
            tap.bottomAnchor.constraint(equalTo: appSettingsCard.content.bottomAnchor),
            tap.heightAnchor.constraint(equalToConstant: 42),
        ])
        let icon = UIImageView(image: UIImage(named: "tab-settings")?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = UIAppColors.inkDynamic
        icon.contentMode = .scaleAspectFit
        let title = UILabel()
        title.text = "设置"
        title.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = UIAppColors.inkDynamic
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = UIAppColors.inkDynamic
        tap.addSubview(icon)
        tap.addSubview(title)
        tap.addSubview(chevron)
        icon.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: tap.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 21),
            icon.heightAnchor.constraint(equalToConstant: 21),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: tap.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
        ])
    }

    @objc private func appSettingsTapped() {
        let page = AppSettingsViewController(homeModel: homeModel)
        present(page, animated: true)
    }

    // MARK: - Account logout

    /// The account （邮箱） logout row: same single-row glass card as
    /// 检查更新 / 设置 above it, with a centered red title. Visible
    /// only while an account session exists. This logs out the
    /// ACCOUNT only — the old device-code activation state inside
    /// the app is a separate system and is not touched.
    private func buildAccountLogoutCard() {
        let tap = UIControl()
        tap.addTarget(self, action: #selector(accountLogoutTapped), for: .touchUpInside)
        accountLogoutCard.content.addSubview(tap)
        tap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tap.leadingAnchor.constraint(equalTo: accountLogoutCard.content.leadingAnchor),
            tap.trailingAnchor.constraint(equalTo: accountLogoutCard.content.trailingAnchor),
            tap.topAnchor.constraint(equalTo: accountLogoutCard.content.topAnchor),
            tap.bottomAnchor.constraint(equalTo: accountLogoutCard.content.bottomAnchor),
            tap.heightAnchor.constraint(equalToConstant: 42),
        ])
        let title = UILabel()
        title.text = "退出登录"
        title.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .systemRed
        title.textAlignment = .center
        tap.addSubview(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: tap.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
        ])
        refreshAccountLogoutVisibility()
    }

    private func refreshAccountLogoutVisibility() {
        accountLogoutCard.isHidden = !AccountSession.isLoggedIn
    }

    @objc private func accountLogoutTapped() {
        let alert = UIAlertController(
            title: "退出登录",
            message: "退出后需要重新登录才能进入。",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出登录", style: .destructive) { [weak self] _ in
            AccountSession.clear()
            self?.refreshAccountLogoutVisibility()
            // The entry gate hears this and immediately swaps the
            // app back to the splash-03 register gate.
            NotificationCenter.default.post(name: .accountSessionDidLogout, object: nil)
        })
        present(alert, animated: true)
    }



    // MARK: - Page font

    private var pageFont: UIFont?
    private var pageFontSet = false

    /// Applies this page area's chosen font (nil = system font).
    func applyPageFont(_ font: UIFont?) {
        pageFont = font
        pageFontSet = true
        if isViewLoaded { PageFontApplier.apply(font, to: view) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAccountLogoutVisibility()
        if pageFontSet { PageFontApplier.apply(pageFont, to: view) }
    }

    // MARK: - Refresh

    private func refreshFromModel() {
        authStatus.text = model.authMessage
        authIconView?.image = luiyoBundledIcon(model.isAuthorized ? "auth-yes" : "auth-no")
        authStatus.textColor = model.isAuthorized
            ? UIColor(red: 0x24 / 255, green: 0x8A / 255, blue: 0x3D / 255, alpha: 1)
            : UIAppColors.secondary
        if model.authBusy {
            spinner.startAnimating()
            activateButton.setTitle("", for: .normal)
        } else {
            spinner.stopAnimating()
            activateButton.setTitle("激活", for: .normal)
        }
        backgroundWell?.selectedColor = UIColor(nativeHex: model.backgroundColorHex)
        minimizeSwitch?.setOn(model.minimizeBottomBar, animated: false)
        appearanceSeg?.setSelectedValue(model.appearanceMode)
        materialSeg?.setSelectedValue(model.cardMaterial)
        bottomSearchSeg?.setSelectedValue(model.bottomSearchLayout)
        fontSubtitleLabel?.text = model.customFontName
        refreshHero()
    }

    private func refreshTheme() {
        view.backgroundColor = UIColor(nativeHex: homeModel.theme.background)
        let tint = UIColor(nativeHex: homeModel.theme.card)
        activationCard.configure(useBlur: homeModel.useBlur, tint: tint)
        updateCard.configure(useBlur: homeModel.useBlur, tint: tint)
        appSettingsCard.configure(useBlur: homeModel.useBlur, tint: tint)
        accountLogoutCard.configure(useBlur: homeModel.useBlur, tint: tint)
        themeFold?.configureGlass(useBlur: homeModel.useBlur, tint: tint)
        guideFold?.configureGlass(useBlur: homeModel.useBlur, tint: tint)
        changelogFold?.configureGlass(useBlur: homeModel.useBlur, tint: tint)
        for card in changelogCards { card.configure(useBlur: homeModel.useBlur, tint: tint) }
    }
}

extension SettingsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitLicense()
        return true
    }
}


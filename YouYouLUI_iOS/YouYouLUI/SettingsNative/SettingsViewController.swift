import Combine
import UIKit
import UniformTypeIdentifiers

/// A plain solid-colour card for the 我的 page (Build 38: this page
/// dropped liquid glass). Same shape contract as GlassCardView — a
/// content container pinned to the card's edges over a flat fill — but
/// the fill is the theme card colour, fully opaque, following the same
/// precedent as the 更改字体 page's solid cards.
final class SolidCardView: UIView {
    let content = UIView()
    private(set) var radius: CGFloat

    init(radius: CGFloat = 22) {
        self.radius = radius
        super.init(frame: .zero)
        backgroundColor = .white
        layer.cornerRadius = radius
        clipsToBounds = true
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setRadius(_ value: CGFloat) {
        radius = value
        layer.cornerRadius = value
    }

    func configure(tint: UIColor) { backgroundColor = tint }
}

/// A settings fold: solid card with a tappable header (icon in a
/// circle, title, subtitle, chevron) and a collapsible content area.
/// The row matches the 设置 page's card metrics — a 48 pt header
/// height and a fixed 24 pt corner radius, collapsed or expanded
/// (the same values as the 设置 page's 检查更新 card; the page
/// stack's 14 pt side insets match too). Build 41: the solid card
/// surface is restored — Build 40's transparency came from a
/// misread instruction and is reverted.
final class FoldView: UIView {
    let card = SolidCardView(radius: 24)
    let contentView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevron = UIImageView()
    private(set) var expanded = false
    var onToggle: (() -> Void)?
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
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
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
        header.heightAnchor.constraint(equalToConstant: 48).isActive = true
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
        // No height animation: the layout switches instantly instead;
        // only the chevron turns and the content fades in, which stays
        // clean. (Kept from the glass era, where stretching the surface
        // frame-by-frame ghosted neighbouring folds' text through it.)
        contentView.isHidden = !value
        subtitleLabel.isHidden = !value
        card.setRadius(24)
        card.content.layer.cornerRadius = 24
        card.configure(tint: lastTint)
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

    /// The 我的 page's cards are solid (Build 38): only the theme
    /// card colour applies here, painted fully opaque.
    func configureGlass(useBlur: Bool, tint: UIColor) {
        lastTint = tint
        card.configure(tint: tint)
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

/// Settings page (UIKit): identity hero, theme / guide folds and
/// the changelog viewer entry — same content and behaviour as the
/// page, rendered with UIKit and the UIKit material. (Authorization
/// lives in the account system now; the hero card shows its state —
/// there is no activation form here. The 检查更新 entry moved to
/// the 设置 page in Build 35; the background auto-check itself is
/// unchanged.)
final class SettingsViewController: UIViewController {
    let model: SettingsNativeModel
    let homeModel: NativeHomeModel

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let heroContainer = UIView()
    private var heroView: UIView?
    private var themeFold: FoldView!
    private var guideFold: FoldView!
    private var changelogRowCard: SolidCardView!
    private let appSettingsCard = SolidCardView(radius: 24)
    private var minimizeSwitch: UISwitch!
    private var appearanceSeg: PillSegmentedControl!
    private var materialSeg: PillSegmentedControl!
    private var bottomSearchSeg: PillSegmentedControl!
    private var fontSubtitleLabel: UILabel?
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

        themeFold = FoldView(icon: "circle.lefthalf.filled", iconImage: luiyoBundledIcon("theme"), title: "外观", subtitle: "卡片材质、按钮与字体")
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

        // 更新日志 is a plain push row since Build 46: tapping it
        // presents the changelog viewer sheet; the log no longer
        // expands inline on this page.
        changelogRowCard = SolidCardView(radius: 24)
        buildChangelogRow()
        stack.addArrangedSubview(changelogRowCard)

        buildAppSettingsCard()
        stack.addArrangedSubview(appSettingsCard)

        let footer = UILabel()
        footer.text = "特别鸣谢 Mk · 作者：优优\n仅供学习交流"
        footer.numberOfLines = 2
        footer.textAlignment = .center
        footer.font = UIFont.systemFont(ofSize: 12)
        footer.textColor = UIAppColors.secondary
        stack.addArrangedSubview(footer)
        stack.setCustomSpacing(8, after: appSettingsCard)

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
        model.$pendingScroll
            .receive(on: DispatchQueue.main)
            .sink { [weak self] target in
                guard let self, let target else { return }
                self.model.pendingScroll = nil
                let fold = self.guideFold
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
            { [weak self] in self?.openChangelogViewer() },
            { [weak self] in self?.openAccountInfo() }
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

    // MARK: - Theme content

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
    @objc private func resetCard() { model.resetCardColor() }
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

    /// The 更新日志 row: a 48 pt solid card in the same shape as
    /// the 设置 entry below it — bundled icon, 13 pt semibold
    /// title, push chevron. Tapping it (like the hero's 更新日志
    /// pill) presents the changelog viewer sheet.
    private func buildChangelogRow() {
        let tap = UIControl()
        tap.addTarget(self, action: #selector(changelogRowTapped), for: .touchUpInside)
        changelogRowCard.content.addSubview(tap)
        tap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tap.leadingAnchor.constraint(equalTo: changelogRowCard.content.leadingAnchor),
            tap.trailingAnchor.constraint(equalTo: changelogRowCard.content.trailingAnchor),
            tap.topAnchor.constraint(equalTo: changelogRowCard.content.topAnchor),
            tap.bottomAnchor.constraint(equalTo: changelogRowCard.content.bottomAnchor),
            tap.heightAnchor.constraint(equalToConstant: 48),
        ])
        let icon = UIImageView(image: luiyoBundledIcon("changelog"))
        icon.tintColor = UIAppColors.inkDynamic
        icon.contentMode = .scaleAspectFit
        let title = UILabel()
        title.text = "更新日志"
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = UIAppColors.inkDynamic
        let subtitle = UILabel()
        subtitle.text = "Version 1.0.8 · 当前版本"
        subtitle.font = UIFont.systemFont(ofSize: 8)
        subtitle.textColor = UIAppColors.secondary
        subtitle.isHidden = true
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = UIAppColors.inkDynamic
        chevron.contentMode = .scaleAspectFit
        tap.addSubview(icon)
        tap.addSubview(title)
        tap.addSubview(subtitle)
        tap.addSubview(chevron)
        icon.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: tap.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 21),
            icon.heightAnchor.constraint(equalToConstant: 21),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            subtitle.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 6),
            subtitle.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: tap.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: tap.centerYAnchor),
        ])
    }

    @objc private func changelogRowTapped() { openChangelogViewer() }

    private func openChangelogViewer() {
        let viewer = ChangelogViewController(backgroundColor: UIColor(nativeHex: homeModel.theme.background))
        viewer.applyPageFont(pageFont)
        // Shell child overlay, not a modal (Build 51): the modal
        // version's top read as opaque page colour on device.
        viewer.show(from: self)
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
            tap.heightAnchor.constraint(equalToConstant: 48),
        ])
        let icon = UIImageView(image: UIImage(named: "tab-settings")?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = UIAppColors.inkDynamic
        icon.contentMode = .scaleAspectFit
        let title = UILabel()
        title.text = "设置"
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
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
        page.applyPageFont(pageFont)
        present(page, animated: true)
    }

    /// The hero card's top-right entry (the chevron where the theme
    /// switch used to live) opens the account page, presented like
    /// the other sub-pages from here （设置 / 检查更新）.
    private func openAccountInfo() {
        let page = AccountInfoViewController(homeModel: homeModel)
        page.applyPageFont(pageFont)
        present(page, animated: true)
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
        if pageFontSet { PageFontApplier.apply(pageFont, to: view) }
    }

    // MARK: - Refresh

    private func refreshFromModel() {
        minimizeSwitch?.setOn(model.minimizeBottomBar, animated: false)
        appearanceSeg?.setSelectedValue(model.appearanceMode)
        materialSeg?.setSelectedValue(model.cardMaterial)
        bottomSearchSeg?.setSelectedValue(model.bottomSearchLayout)
        fontSubtitleLabel?.text = model.customFontName
        refreshHero()
    }

    private func refreshTheme() {
        // Same rule as Home: over a background image (the default
        // wallpaper) the page stays clear; over a colour it paints it.
        view.backgroundColor = homeModel.backgroundImage == nil
            ? UIColor(nativeHex: homeModel.theme.background)
            : .clear
        let tint = UIColor(nativeHex: homeModel.theme.card)
        appSettingsCard.configure(tint: tint)
        themeFold?.configureGlass(useBlur: homeModel.useBlur, tint: tint)
        guideFold?.configureGlass(useBlur: homeModel.useBlur, tint: tint)
        changelogRowCard?.configure(tint: tint)
    }
}


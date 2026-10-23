import UIKit

/// 更新日志 viewer (Build 46): a sheet that slides up over the
/// presenting page and comes to rest ≈54 pt below the top of the
/// screen with its top corners rounded ≈34 pt (Build 49, matched
/// to the reference). The root view is fully transparent — only
/// the sheet region carries the page background, so the live page
/// underneath shows through above the sheet and in the corner
/// notches. Inside: a fixed header (centered title, frosted-glass
/// close button) over a scrolling stack of per-version cards.
/// The cards are true frosted glass （毛玻璃）: a light system
/// blur pushed milky-white with a white overlay and a bright rim
/// (Build 47 recipe, overlay lightened to 0.38 in Build 48),
/// pinned on purpose: they do NOT follow the 卡片材质 (liquid /
/// blur) setting. Content is `SettingsContent.changelog`, newest
/// first, rendered in the same type sizes the old inline fold
/// used.
final class ChangelogViewController: UIViewController {
    private let backgroundColor: UIColor
    private var pageFont: UIFont?

    init(backgroundColor: UIColor) {
        self.backgroundColor = backgroundColor
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Page font

    /// The 设置页 area's chosen font, handed over by the presenter
    /// (nil = system font), applied the same way the other settings
    /// sub-pages apply it.
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
        // Fully transparent root: nothing outside the sheet is
        // painted or dimmed, so the presenting page stays live and
        // visible above the sheet and in its rounded corner
        // notches (Build 49).
        view.backgroundColor = .clear
        view.isOpaque = false

        let sheet = UIView()
        sheet.backgroundColor = backgroundColor
        sheet.layer.cornerRadius = 34
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.clipsToBounds = true
        view.addSubview(sheet)
        sheet.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.topAnchor.constraint(equalTo: view.topAnchor, constant: 54),
            sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let header = UIView()
        sheet.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            header.topAnchor.constraint(equalTo: sheet.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 74),
        ])
        let title = UILabel()
        title.text = "更新日志"
        title.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        title.textColor = UIAppColors.inkDynamic
        header.addSubview(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        let closeButton = ChangelogCloseButton()
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        header.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 33),
            closeButton.heightAnchor.constraint(equalToConstant: 33),
            title.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -12),
        ])

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        sheet.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sheet.bottomAnchor),
        ])
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 0),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36),
        ])
        for version in SettingsContent.changelog {
            stack.addArrangedSubview(makeCard(version))
        }
    }

    @objc private func closeTapped() { dismiss(animated: true) }

    // MARK: - Cards

    private func makeCard(_ version: ChangelogVersion) -> UIView {
        let card = ChangelogGlassCardView()
        let block = UIStackView()
        block.axis = .vertical
        block.spacing = 10
        card.content.addSubview(block)
        block.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            block.leadingAnchor.constraint(equalTo: card.content.leadingAnchor, constant: 15),
            block.trailingAnchor.constraint(equalTo: card.content.trailingAnchor, constant: -15),
            block.topAnchor.constraint(equalTo: card.content.topAnchor, constant: 15),
            block.bottomAnchor.constraint(equalTo: card.content.bottomAnchor, constant: -15),
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
            block.addArrangedSubview(entryLabel(entry))
        }
        return card
    }

    private func entryLabel(_ entry: ChangelogEntry) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: para,
        ]
        // The stored text often repeats its own kind word ("新增 …",
        // "修复 …"); the coloured prefix already says it, so one
        // leading kind word comes off the body.
        var body = entry.text
        for word in ["新增", "优化", "修复"] where body.hasPrefix(word) {
            body = String(body.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        let text = NSMutableAttributedString()
        if let tag = entry.tag, !tag.isEmpty {
            text.append(NSAttributedString(string: tag, attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: prefixColor(tag),
                .paragraphStyle: para,
            ]))
            text.append(NSAttributedString(string: " " + body, attributes: bodyAttributes))
        } else {
            text.append(NSAttributedString(string: body, attributes: bodyAttributes))
        }
        label.attributedText = text
        return label
    }

    /// Kind-word colours sampled from the approved reference.
    private func prefixColor(_ tag: String) -> UIColor {
        switch tag {
        case "新增": return UIColor(red: 40 / 255, green: 200 / 255, blue: 90 / 255, alpha: 1)
        case "优化": return UIColor(red: 10 / 255, green: 122 / 255, blue: 229 / 255, alpha: 1)
        case "修复": return UIColor(red: 240 / 255, green: 118 / 255, blue: 40 / 255, alpha: 1)
        default: return UIAppColors.secondary
        }
    }
}

/// One changelog card: a true frosted-glass （毛玻璃） surface
/// under a content container — a light system blur pushed
/// milky-white by a white overlay (0.38 since Build 48), finished with a bright
/// 1 pt rim, so the card reads almost white against the sheet
/// while keeping a hint of translucency (Build 47; the Build 46
/// iOS 26 liquid-glass surface read as a gray-lavender wash over
/// the sheet and was rejected). Only a whisper of shadow beneath
/// (the user asked for the shadow kept very light). The recipe
/// is pinned and never follows the 卡片材质 setting. Structure:
/// this wrapper owns the shadow, border and radius; the effect
/// view pinned inside clips itself to the same radius.
private final class ChangelogGlassCardView: UIView {
    let content = UIView()
    private let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
    private let whitewash = UIView()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        layer.cornerRadius = 26
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)
        surface.isUserInteractionEnabled = false
        surface.clipsToBounds = true
        whitewash.backgroundColor = UIColor.white.withAlphaComponent(0.38)
        whitewash.isUserInteractionEnabled = false
        surface.contentView.addSubview(whitewash)
        addSubview(surface)
        addSubview(content)
        surface.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        whitewash.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            whitewash.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor),
            whitewash.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor),
            whitewash.topAnchor.constraint(equalTo: surface.contentView.topAnchor),
            whitewash.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 26).cgPath
        surface.layer.cornerRadius = 26
    }
}

/// The header's circular close button (≈33 pt), in the same
/// frosted-glass （毛玻璃） recipe as the cards (Build 47): light
/// system blur + milky-white overlay + bright rim.
private final class ChangelogCloseButton: UIControl {
    private let surface = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
    private let whitewash = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        surface.isUserInteractionEnabled = false
        surface.clipsToBounds = true
        whitewash.backgroundColor = UIColor.white.withAlphaComponent(0.38)
        whitewash.isUserInteractionEnabled = false
        surface.contentView.addSubview(whitewash)
        addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        whitewash.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            whitewash.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor),
            whitewash.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor),
            whitewash.topAnchor.constraint(equalTo: surface.contentView.topAnchor),
            whitewash.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor),
        ])
        let icon = UIImageView(image: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)))
        icon.tintColor = UIAppColors.inkDynamic
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        addSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.topAnchor.constraint(equalTo: topAnchor),
            icon.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let radius = bounds.height / 2
        layer.cornerRadius = radius
        surface.layer.cornerRadius = radius
    }
}

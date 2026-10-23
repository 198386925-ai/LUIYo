import UIKit

/// 更新日志 viewer (Build 46): a sheet that slides up over the
/// presenting page and comes to rest ≈54 pt below the top of the
/// screen with its top corners rounded ≈30 pt, so a strip of the
/// page underneath stays visible. Inside: a fixed header (centered
/// title, glass close button) over a scrolling stack of per-version
/// cards. The cards are frosted GLASS — iOS 26 `UIGlassEffect` in
/// its regular, non-interactive form, pinned on purpose: they do
/// NOT follow the 卡片材质 (liquid / blur) setting. Content is
/// `SettingsContent.changelog`, newest first, rendered in the same
/// type sizes the old inline fold used.
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
        view.backgroundColor = .clear

        let sheet = UIView()
        sheet.backgroundColor = backgroundColor
        sheet.layer.cornerRadius = 30
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
            header.heightAnchor.constraint(equalToConstant: 64),
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
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),
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
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
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

/// One changelog card: a frosted-glass surface under a content
/// container, with only a whisper of shadow beneath (the user
/// asked for the shadow kept very light). The glass is pinned —
/// iOS 26 native glass on current systems, the system material
/// blur only where glass does not exist — and never follows the
/// 卡片材质 setting.
private final class ChangelogGlassCardView: UIView {
    let content = UIView()
    private let surface = UIVisualEffectView()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)
        if #available(iOS 26.0, *) {
            surface.effect = UIGlassEffect(style: .regular)
        } else {
            surface.effect = UIBlurEffect(style: .systemMaterial)
        }
        surface.isUserInteractionEnabled = false
        addSubview(surface)
        addSubview(content)
        surface.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        if #available(iOS 26.0, *), surface.effect is UIGlassEffect {
            surface.cornerConfiguration = .uniformCorners(radius: .fixed(26))
            surface.clipsToBounds = false
        } else {
            surface.clipsToBounds = true
        }
        removeExtraLayerShadows(surface.layer)
    }
}

/// The header's circular glass close button (≈34 pt).
private final class ChangelogCloseButton: UIControl {
    private let surface = UIVisualEffectView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOS 26.0, *) {
            surface.effect = UIGlassEffect(style: .regular)
        } else {
            surface.effect = UIBlurEffect(style: .systemMaterial)
        }
        surface.isUserInteractionEnabled = false
        addSubview(surface)
        surface.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
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
        surface.layer.cornerRadius = radius
        if #available(iOS 26.0, *), surface.effect is UIGlassEffect {
            surface.cornerConfiguration = .uniformCorners(radius: .fixed(Double(radius)))
            surface.clipsToBounds = false
        } else {
            surface.clipsToBounds = true
        }
        removeExtraLayerShadows(surface.layer)
    }
}

import UIKit

/// 更新日志 viewer (Build 46): a sheet that slides up over the
/// current page and comes to rest ≈84 pt below the top of the
/// screen (54 pt originally, lowered 10 pt in Build 52 and
/// another 20 pt in Build 53) with its top
/// corners rounded ≈34 pt (Build 49, matched
/// to the reference). The root view is fully transparent — the
/// live page underneath shows through above the sheet and in the
/// corner notches. The sheet's own background is TWO layers
/// (Build 51, the reference's construction): an opaque fill in
/// the page background colour — the live page does not ghost
/// through the sheet's body at all — plus a frosted-glass film
/// over it, so the sheet reads soft while transparency exists
/// only above it. Build 55: the light-mode background layer is
/// a FLAT warm beige #F0EEE8 (the reference app's paper colour,
/// the user's pick over Build 54's #BAD0EB-family gradient)
/// and the film stays a colour-neutral frost (light blur +
/// plain white sheen 0.15) over it; dark mode keeps its flat
/// #121214 background and film.
/// Presentation is a CHILD OVERLAY of the app shell (Build 51,
/// see `show(from:)`): Builds 49–50 presented this modally
/// (.overFullScreen) from the embedded settings child and on
/// device the modal's top read as flat opaque page colour —
/// what sits behind a modal here is the window/shell painted
/// with the background colour, not the live page render, so a
/// translucent wash of that colour over a blur of itself is
/// indistinguishable from a solid fill. As a shell child the
/// viewer sits directly on top of the attached live page,
/// the way the bottom-search overlay does.
/// Inside: a fixed header (centered title, native-glass
/// close button since Build 52) over a scrolling stack of
/// per-version cards. Build 55: the scroll view spans the
/// full sheet, so scrolled cards travel up through the header
/// zone and clip at the sheet's top edge; the title and close
/// button keep their exact positions and appearance from
/// Builds 46–54. Builds 55–58 put a strip in the header zone
/// (frosted, solid, frosted again, tint raised) — every
/// version was rejected. Build 59 (the user's final word:
/// 不要顶栏颜色，改透明，更新日志往上显示): the strip is
/// GONE entirely — no colour, no layer at all in the header
/// zone; the zone is transparent, showing the sheet's own
/// body and, while scrolling, the content itself, which
/// travels up through the zone fully visible, passing under
/// the floating title and close button, until the sheet's
/// own clip cuts it at the sheet's top edge. It is the
/// sheet's clip — not any layer's opacity — that keeps text
/// out of the transparent zone above the sheet.
/// The cards wear the frosted-glass （毛玻璃） LOOK — a milky,
/// almost-white surface with a bright rim (the Build 47 recipe,
/// overlay lightened to 0.38 in Build 48) — pinned on purpose:
/// they do NOT follow the 卡片材质 (liquid / blur) setting.
/// Build 56 (the user: 毛玻璃可以不用透明的效果吗): the card
/// surface is a SOLID fill baked to the exact colour the live
/// blur + white overlay produced over the flat sheet, and the
/// header strip was likewise solid. Build 57 (the user's
/// clarification — sliding up, he wants to SEE it, but the
/// text must never reach the transparent zone): the CARDS
/// stay solid; the STRIP returns to live frost, and the
/// sheet's own clipsToBounds is the hard clip that keeps
/// every scrolled pixel inside the sheet. Content is
/// `SettingsContent.changelog`, newest first, rendered in the
/// same type sizes the old inline fold used.
final class ChangelogViewController: UIViewController {
    private let backgroundColor: UIColor
    private var pageFont: UIFont?
    private weak var sheetView: UIView?
    private var presentedAsOverlay = false
    private var isDismissing = false

    init(backgroundColor: UIColor) {
        self.backgroundColor = backgroundColor
        super.init(nibName: nil, bundle: nil)
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
        sheet.layer.cornerRadius = 34
        sheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheet.clipsToBounds = true
        sheetView = sheet
        view.addSubview(sheet)
        sheet.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheet.topAnchor.constraint(equalTo: view.topAnchor, constant: 84),
            sheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Sheet background (Build 51 — the reference's TWO-layer
        // construction, per the user's correction): layer 1 is an
        // OPAQUE background — the live page does NOT ghost through
        // the sheet's body at all; layer 2, on top of it, is a
        // frosted-glass film. Build 55 (the user's colour call):
        // the colour belongs to the BACKGROUND layer only —
        // light mode is a FLAT warm beige #F0EEE8 (the reference
        // app's paper colour, sampled from its sheet; he picked
        // it over Build 54's #BAD0EB-family gradient; dark mode
        // keeps the flat #121214) — and the film is
        // colour-NEUTRAL: one light system blur plus a plain
        // white sheen at 0.15 (dark: the #121214 tint at 0.5 as
        // before), so the beige shows through the frost undyed.
        // Transparency exists ONLY above the sheet (the clear
        // root). The sheet's clipsToBounds keeps both layers
        // inside the rounded-top shape; the scroll view and
        // the header are added after, so they sit on top.
        let sheetBackground = ChangelogSheetBackgroundView()
        sheetBackground.isUserInteractionEnabled = false
        sheet.addSubview(sheetBackground)
        sheetBackground.translatesAutoresizingMaskIntoConstraints = false
        let frost = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialLight))
        frost.isUserInteractionEnabled = false
        let frostTint = UIView()
        frostTint.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 20.0 / 255.0, alpha: 0.5)
                : UIColor.white.withAlphaComponent(0.15)
        }
        frostTint.isUserInteractionEnabled = false
        frost.contentView.addSubview(frostTint)
        frostTint.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(frost)
        frost.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sheetBackground.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            sheetBackground.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            sheetBackground.topAnchor.constraint(equalTo: sheet.topAnchor),
            sheetBackground.bottomAnchor.constraint(equalTo: sheet.bottomAnchor),
            frost.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            frost.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            frost.topAnchor.constraint(equalTo: sheet.topAnchor),
            frost.bottomAnchor.constraint(equalTo: sheet.bottomAnchor),
            frostTint.leadingAnchor.constraint(equalTo: frost.contentView.leadingAnchor),
            frostTint.trailingAnchor.constraint(equalTo: frost.contentView.trailingAnchor),
            frostTint.topAnchor.constraint(equalTo: frost.contentView.topAnchor),
            frostTint.bottomAnchor.constraint(equalTo: frost.contentView.bottomAnchor),
        ])

        // Scroll view (Build 55): spans the FULL sheet — its top
        // is the sheet's top edge — so scrolled cards travel up
        // through the header zone and clip at the sheet's top
        // edge (the user's red line) instead of being cut off at
        // the header's bottom edge. A 74 pt top content inset
        // keeps the resting layout pixel-identical to Builds
        // 46–54: the first card still begins at sheet top + 74.
        // The header is added after the scroll view so the
        // title and close button render above the content;
        // they keep their original constraints.
        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset.top = 74
        scrollView.verticalScrollIndicatorInsets.top = 74
        sheet.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: sheet.topAnchor),
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

        // Header zone (Build 59 — the user's final word:
        // 不要顶栏颜色，改透明，更新日志往上显示): there is NO
        // strip here any more. Builds 55–58 tried a frosted
        // strip, a solid strip, frost again, and a heavier
        // tint over the frost — every one rejected. The
        // header zone carries NO colour and NO layer at all:
        // it is transparent, so what shows in it is the
        // sheet's own body (background + film, laid down
        // above) and, while scrolling, the content itself —
        // cards and text travel up through the zone fully
        // visible, passing underneath the floating title and
        // close button (the header added next renders above
        // the scroll view), all the way to the sheet's top
        // edge.
        // The hard guarantee against escape is unchanged and
        // relies on no layer's opacity: the scroll view is a
        // subview of the sheet, pinned edge to edge to it, and
        // the sheet's clipsToBounds — with the 34 pt radius
        // masked to the top corners — clips ALL descendants at
        // the sheet's bounds; UIScrollView also clips its
        // content to its own frame, which is exactly the
        // sheet's bounds, so no card pixel can ever render
        // above the sheet's top edge or outside its rounded
        // corners, into the transparent zone where the live
        // page shows through. The header view itself has no
        // background colour — its only subviews are the title
        // label and the close button.
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
    }

    @objc private func closeTapped() { dismissViewer() }

    // MARK: - Presentation (Build 51: shell child overlay, not a modal)

    /// Shows the viewer as a child overlay of the app shell — the
    /// construction the bottom-search overlay uses
    /// (`showSearchOverlay`) — so the live page and tab bar stay
    /// attached directly underneath: the clear root shows the
    /// raw page above the sheet, and the cards rest on the
    /// sheet's own layered surface. Falls back to an
    /// over-current-context
    /// modal (presenter stays in the hierarchy) only if no shell
    /// is reachable from the presenter.
    func show(from presenter: UIViewController) {
        guard let shell = Self.findShell(from: presenter) else {
            modalPresentationStyle = .overCurrentContext
            modalTransitionStyle = .coverVertical
            presenter.present(self, animated: true)
            return
        }
        presentedAsOverlay = true
        shell.addChild(self)
        view.frame = shell.view.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shell.view.addSubview(view)
        view.layer.zPosition = 3
        didMove(toParent: shell)
        view.layoutIfNeeded()
        // Slide the sheet up from below the screen to its rest
        // position (top at 84 pt), keeping the cover-vertical feel
        // the modal version had.
        guard let sheet = sheetView else { return }
        let travel = view.bounds.height + 60
        sheet.transform = CGAffineTransform(translationX: 0, y: travel)
        UIView.animate(withDuration: 0.42, delay: 0, options: [.curveEaseOut], animations: {
            sheet.transform = .identity
        })
    }

    private func dismissViewer() {
        guard presentedAsOverlay else {
            dismiss(animated: true)
            return
        }
        guard !isDismissing else { return }
        isDismissing = true
        let travel = view.bounds.height + 60
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn], animations: {
            self.sheetView?.transform = CGAffineTransform(translationX: 0, y: travel)
        }, completion: { _ in
            self.willMove(toParent: nil)
            self.view.removeFromSuperview()
            self.removeFromParent()
        })
    }

    /// Finds the app shell above a presenter: walks each
    /// presenter's parent chain, stepping through the
    /// presenting chain for presenters that are themselves
    /// presented (the 检查更新 path sits two page sheets deep).
    private static func findShell(from viewController: UIViewController) -> MainShellViewController? {
        var link: UIViewController? = viewController
        while let current = link {
            var node: UIViewController? = current
            while let candidate = node {
                if let shell = candidate as? MainShellViewController { return shell }
                node = candidate.parent
            }
            link = current.presentingViewController
        }
        return nil
    }

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

/// One changelog card: the frosted-glass （毛玻璃） look under
/// a content container — a milky, almost-white surface finished
/// with a bright 1 pt rim, so the card reads almost white
/// against the sheet (Builds 47–55: a light system blur pushed
/// milky-white by a white overlay, 0.38 since Build 48; the
/// Build 46 iOS 26 liquid-glass surface read as a gray-lavender
/// wash over the sheet and was rejected). Build 56 (the user:
/// 毛玻璃可以不用透明的效果吗): the surface is a SOLID fill —
/// NO live blur, nothing shows through. Its colour is the old
/// recipe baked flat over the sheet's baked surface (the flat
/// background under the sheet's white-0.15 film, then the
/// white 0.38 wash over that): light (247, 246, 244), dark
/// (108, 108, 112). Over the flat sheet the bake is exact —
/// the resting card looks the same as Build 55. Only a whisper
/// of shadow beneath (the user asked for the shadow kept very
/// light). The recipe is pinned and never follows the 卡片材质
/// setting. Structure: this wrapper owns the shadow, border
/// and radius; the solid fill pinned inside clips itself to
/// the same radius.
private final class ChangelogGlassCardView: UIView {
    let content = UIView()
    private let surface = UIView()

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
        surface.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 108.0 / 255.0, green: 108.0 / 255.0, blue: 112.0 / 255.0, alpha: 1)
                : UIColor(red: 247.0 / 255.0, green: 246.0 / 255.0, blue: 244.0 / 255.0, alpha: 1)
        }
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
    }
}

/// The header's circular close button (≈33 pt). Build 52: on
/// iOS 26 the surface is TRUE NATIVE GLASS — a `UIGlassEffect`
/// effect view, interactive, clear/untinted (the same plain
/// `UIGlassEffect()` the search overlay's input surface uses),
/// shaped by `cornerConfiguration`; the × glyph is a plain
/// content view on top of the effect view. Before iOS 26 the
/// button falls back to the cards' frosted-glass （毛玻璃）
/// recipe (Build 47): light system blur + milky-white overlay
/// + bright rim. The CARDS stay frosted on every system — only
/// this button is native glass, per the user's word.
private final class ChangelogCloseButton: UIControl {
    private let surface = UIVisualEffectView()
    private let whitewash = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.isUserInteractionEnabled = false
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = true
            surface.effect = glass
            whitewash.isHidden = true
        } else {
            layer.borderWidth = 1
            layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
            surface.effect = UIBlurEffect(style: .systemMaterialLight)
            surface.clipsToBounds = true
            whitewash.backgroundColor = UIColor.white.withAlphaComponent(0.38)
        }
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
        if #available(iOS 26.0, *), surface.effect is UIGlassEffect {
            surface.cornerConfiguration = .uniformCorners(radius: .fixed(Double(radius)))
        } else {
            surface.layer.cornerRadius = radius
        }
    }
}

/// The sheet's background layer (layer 1 of the two-layer
/// construction). Light mode (Build 55, the user's colour
/// call): a FLAT warm beige #F0EEE8 — the reference app's
/// paper colour, sampled from its sheet (RGB 240, 238, 232) —
/// which he picked over Build 54's #BAD0EB-family gradient;
/// opaque, so the live page never ghosts through the sheet's
/// body. Dark mode keeps the flat #121214 of Builds 51–54.
/// The colour lives ONLY in this layer; the frost film laid
/// over it is colour-neutral. A dynamic colour provider
/// keeps the fill correct across appearance changes.
private final class ChangelogSheetBackgroundView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 20.0 / 255.0, alpha: 1) // #121214
                : UIColor(red: 240.0 / 255.0, green: 238.0 / 255.0, blue: 232.0 / 255.0, alpha: 1) // #F0EEE8
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

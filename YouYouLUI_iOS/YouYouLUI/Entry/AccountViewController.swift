import UIKit
import CoreText

/// The register/login gate pages, restored 1:1 from the user's design
/// file `account-design/register-login.html` ("注册或登录 — LOSEVA.PRO").
/// The design is a responsive page; on a phone its ≤520px media query
/// is the operative spec, so the CSS px values below are used as
/// points verbatim (body padding 28/14, card radius 36, panel inset
/// 20, tabs 54, form padding 22/16, …). The page is light-only in the
/// design, so these controllers pin `.light`.
///
/// One rendering note: the design's `.hint` uses `var(--muted-2)`,
/// which the file never defines — per CSS rules the declaration is
/// invalid and the hint inherits the body ink color (#17171a). It is
/// rendered that way here, exactly as the file computes.

/// Build 20: the register/login card assembly shrunk a touch
/// (~8–10% footprint). Side margins widened (14 → 28); every
/// internal vertical spacing/padding is the design value × 0.92
/// and the title/tab/field block heights are × 0.95. All account
/// pages share these constants (the register/login page, the
/// reset page and the captcha sheet all sit on the same base
/// card), so the whole family shrinks consistently. Horizontal
/// paddings inside the form (16) and all texts are unchanged.
enum AccountMetrics {
    static let cardSideMargin: CGFloat = 28   // was 14
    static let cardTopPad: CGFloat = 39       // 42 × 0.92
    static let titleHeight: CGFloat = 27      // 28 × 0.95
    static let titleGap: CGFloat = 29         // 32 × 0.92
    static let cardBottomPad: CGFloat = 18    // 20 × 0.92
    static let pagePad: CGFloat = 26          // 28 × 0.92 (overflow layout)
    static let panelInset: CGFloat = 18       // 20 × 0.92
    static let tabHeight: CGFloat = 51        // 54 × 0.95
    static let formPadTop: CGFloat = 20       // 22 × 0.92
    static let formPadBottom: CGFloat = 20    // 22 × 0.92
    static let fieldHeight: CGFloat = 38      // 40 × 0.95
    static let fieldGap: CGFloat = 18         // field marginBottom 20 × 0.92
    static let hintGap: CGFloat = 6           // 7 × 0.92
    static let buttonHeight: CGFloat = 46     // 48 × 0.95
    static let accessoryHeight: CGFloat = 29  // 30 × 0.95 (code button / suffix chip)
    static let eyeSize: CGFloat = 36          // 38 × 0.95
    static let agreeGap: CGFloat = 15         // 16 × 0.92
    static let agreeRowHeight: CGFloat = 20   // 21 × 0.95
    static let forgotGap: CGFloat = 18        // 20 × 0.92
    static let shortFieldGap: CGFloat = 6     // 7 × 0.92 (password field margin)
    static let brandGap: CGFloat = 26         // 28 × 0.92 (card → brand line)
}

enum AccountPalette {
    static let ink = splashHex("#17171a")
    static let inkSoft = splashHex("#3d3d44")
    static let muted = splashHex("#9c9ca4")
    static let line = splashHex("#e9e9ed")
    static let fieldBg = splashHex("#fbfbfb")
    static let dark = splashHex("#3f3f47")
    static let darkPressed = splashHex("#2f2f37")
    static let danger = splashHex("#d94a45")
    static let errorBorder = splashHex("#d06b65")
    static let errorBorderFocus = splashHex("#c93a35")
    static let errorBg = splashHex("#fffafa")
    static let focusBorder = splashHex("#cfcfd8")
    static let tabIdle = splashHex("#5c5c66")
    static let tabActive = splashHex("#141418")
    static let pageBg = splashHex("#f8f9fa")
    static let success = splashHex("#1d7a4b")
}

/// The design's text input: 40 tall, radius 14, 1px border, 16px side
/// padding (right padding grows when an accessory rides inside).
final class AccountTextField: UITextField {
    var rightInset: CGFloat = 16
    private(set) var hasError = false
    var hasFocus = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 14)
        textColor = splashHex("#15151a")
        tintColor = AccountPalette.dark
        layer.borderWidth = 1
        layer.cornerRadius = 14
        autocorrectionType = .no
        applyStyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setError(_ on: Bool) {
        hasError = on
        applyStyle()
    }

    func applyStyle() {
        if hasError {
            backgroundColor = AccountPalette.errorBg
            layer.borderColor = (hasFocus
                ? AccountPalette.errorBorderFocus : AccountPalette.errorBorder).cgColor
        } else if hasFocus {
            backgroundColor = .white
            layer.borderColor = AccountPalette.focusBorder.cgColor
        } else {
            backgroundColor = AccountPalette.fieldBg
            layer.borderColor = AccountPalette.line.cgColor
        }
        if let placeholderText = placeholder {
            attributedPlaceholder = NSAttributedString(
                string: placeholderText,
                attributes: [.foregroundColor: hasFocus
                    ? splashHex("#b6b6be") : AccountPalette.muted,
                             .font: font as Any])
        }
    }

    private func insetRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + 16, y: rect.minY,
               width: rect.width - 16 - rightInset, height: rect.height)
    }
    override func textRect(forBounds bounds: CGRect) -> CGRect { insetRect(bounds) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { insetRect(bounds) }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect { insetRect(bounds) }
}

/// One design `.field`: the input, an optional hint line under it and
/// an error line (both measured; the block's height is dynamic, like
/// the web form's).
final class FormField: NSObject {
    let view = UIView()
    let input = AccountTextField()
    let errLabel = UILabel()
    private(set) var hintLabel: UILabel?
    /// Bottom gap after this block (design `.field { margin-bottom }`).
    var marginBottom: CGFloat = AccountMetrics.fieldGap
    /// Called whenever the block's height may have changed.
    var onHeightChanged: (() -> Void)?

    init(placeholder: String, hint: String? = nil) {
        input.placeholder = placeholder
        input.applyStyle()
        view.addSubview(input)
        errLabel.font = .systemFont(ofSize: 12)
        errLabel.textColor = AccountPalette.danger
        errLabel.numberOfLines = 0
        errLabel.isHidden = true
        view.addSubview(errLabel)
        if let hint {
            let label = UILabel()
            label.text = hint
            label.font = .systemFont(ofSize: 11, weight: .light)
            // var(--muted-2) is undefined in the design → inherits ink.
            label.textColor = AccountPalette.ink
            label.numberOfLines = 0
            view.addSubview(label)
            hintLabel = label
        }
        super.init()
        input.addTarget(self, action: #selector(editingBegan), for: .editingDidBegin)
        input.addTarget(self, action: #selector(editingEnded), for: .editingDidEnd)
        input.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
    }

    var text: String { input.text ?? "" }

    func setError(_ message: String?) {
        errLabel.text = message
        errLabel.isHidden = message == nil
        input.setError(message != nil)
        onHeightChanged?()
    }

    var hasError: Bool { !errLabel.isHidden }

    @objc private func editingBegan() {
        input.hasFocus = true
        input.applyStyle()
    }
    @objc private func editingEnded() {
        input.hasFocus = false
        input.applyStyle()
    }
    @objc private func editingChanged() {
        if hasError { setError(nil) }
    }

    private func measure(_ label: UILabel, width: CGFloat) -> CGFloat {
        guard let text = label.text, !text.isEmpty else { return 0 }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: label.font as Any], context: nil)
        return ceil(rect.height)
    }

    /// Lays the block out at the given width; returns its height
    /// (excluding marginBottom).
    @discardableResult
    func layout(width: CGFloat) -> CGFloat {
        input.frame = CGRect(x: 0, y: 0, width: width, height: AccountMetrics.fieldHeight)
        var y: CGFloat = AccountMetrics.fieldHeight
        if let hintLabel {
            y += AccountMetrics.hintGap
            let h = measure(hintLabel, width: width - 18)
            hintLabel.frame = CGRect(x: 18, y: y, width: width - 18, height: h)
            y += h
        }
        if !errLabel.isHidden {
            y += 6
            let h = measure(errLabel, width: width - 18)
            errLabel.frame = CGRect(x: 18, y: y, width: width - 18, height: h)
            y += h
        }
        view.frame = CGRect(x: view.frame.minX, y: view.frame.minY, width: width, height: y)
        return y
    }
}

/// The white region behind the tabs + form: PRE-RENDERED BITMAPS
/// of the folder outline — one image per (tab, width, height,
/// interface style), drawn once from the exact CGPaths below and
/// shown in UIImageViews. No CAShapeLayer anywhere.
///
/// Build 19 FORENSICS (the warp that survived Builds 16/17/18):
/// the bitmap pipeline was faithfully reproducing a BROKEN PATH.
/// In formsPath's login branch the bottom-left corner arc was
/// ordered for the signup walk, so addArc auto-drew diagonal
/// chords (documented UIKit behaviour when the current point is
/// not the arc's start), the bottom edge ran diagonally from
/// (0, H-r) to (W-r, H), and close() ran the right edge
/// diagonally from (W-r, H) back to (W, T). Replicating the exact
/// path math offline reproduces the device shape to the pixel:
/// bottom slope +0.0764 (theory r/(W-r) = +0.0776, device
/// +0.077), right-edge slope -0.1009 (theory -r/(H-T) = -0.1036,
/// device -0.104), triangular spikes at both bottom corners.
/// Signup's branch was always correct, which is why only the
/// login state ever warped — and why three rounds of "stop the
/// live layers from deforming" changed nothing. The path is
/// fixed in formsPath below.
///
/// Switch rendering (Build 19): both tabs' bitmaps live in the
/// panel at NATURAL size, top-anchored, and the panel clips. A
/// switch crossfades the two images while the controller animates
/// the layout (card/panel heights) — a growing panel uncovers the
/// taller image, a shrinking panel clips it; the images themselves
/// are never scaled, so no frame of the switch can shear or squash
/// anything either.
final class WhitePanelView: UIView {
    /// 0 = signup (bump left), 1 = login (bump right).
    private(set) var tabIndex = 0
    /// One image view per tab; each shows its tab's bitmap at its
    /// OWN natural size, top-anchored. The panel clips to its
    /// bounds, so while the controller animates the panel height,
    /// the taller bitmap is uncovered/clipped — never stretched.
    private let imageViews = [UIImageView(), UIImageView()]
    /// Each tab's own panel height.
    private var heights: [CGFloat] = [0, 0]
    /// Rendered images per interface style: [style][tab].
    private var cache: [UIUserInterfaceStyle: [UIImage?]] = [:]
    /// (width, signupHeight, loginHeight) in half-points; a change
    /// invalidates the cache.
    private var cacheKey: (Int, Int, Int)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        // Build 43: the panel's own clip must carry the shape's
        // bottom radius (formsPath's r = 26). Until now the panel
        // clipped as a plain rectangle and the bitmaps supplied
        // the roundness — but the switch animates the panel height
        // for 0.55 s, and mid-switch the panel's bottom edge slices
        // straight across the white bitmaps, so the visible white
        // bottom read as two SQUARE corners against the gray card
        // until the height settled and the bitmaps' own arcs
        // reached the panel's bottom again (the user's recording
        // shows exactly that slab mid-shrink). With the layer's
        // bottom corners masked at the same 26 pt, every
        // intermediate clip boundary is the design's arc. The top
        // stays unmasked: the bump shapes live there and are never
        // touched by the clip. At rest the panel height equals the
        // bitmap height, so the mask coincides with the bitmap's
        // own arcs and the settled look is unchanged.
        layer.cornerRadius = 26
        layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        for (i, iv) in imageViews.enumerated() {
            // The frame is always set to the bitmap's own size, so
            // this content mode never actually scales anything.
            iv.contentMode = .scaleToFill
            iv.alpha = i == tabIndex ? 1 : 0
            addSubview(iv)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setHeights(signup: CGFloat, login: CGFloat) {
        if [signup, login] != heights {
            heights = [signup, login]
            cache.removeAll()
            cacheKey = nil
        }
        refreshImages()
    }

    /// Instant tab switch: snap the two bitmaps' alphas.
    func select(_ index: Int) {
        tabIndex = index
        refreshImages()
        for (i, iv) in imageViews.enumerated() {
            iv.alpha = i == index ? 1 : 0
        }
    }

    /// Animated tab switch: crossfade the two bitmaps inside the
    /// caller's animator (which also animates the sheet layout).
    /// Both bitmaps stay at natural size for the whole switch.
    func crossfade(to index: Int, in animator: UIViewPropertyAnimator) {
        let outgoing = imageViews[tabIndex]
        let incoming = imageViews[index]
        tabIndex = index
        refreshImages()
        incoming.alpha = 0
        outgoing.alpha = 1
        animator.addAnimations {
            incoming.alpha = 1
            outgoing.alpha = 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshImages()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            refreshImages()
        }
    }

    /// Ensures both tabs' bitmaps exist for the current style and
    /// pins each image view to its bitmap's natural frame. Never
    /// touches alpha — a crossfade may be in flight while the
    /// animated layout keeps calling this.
    private func refreshImages() {
        let W = bounds.width
        guard W > 0 else { return }
        let key = (Int((W * 2).rounded()), Int((heights[0] * 2).rounded()),
                   Int((heights[1] * 2).rounded()))
        if cacheKey.map({ $0 != key }) ?? true {
            cache.removeAll()
            cacheKey = key
        }
        let style = traitCollection.userInterfaceStyle
        var pair = cache[style] ?? [nil, nil]
        for tab in 0...1 {
            let H = heights[tab]
            let iv = imageViews[tab]
            guard H > 54 else { iv.image = nil; continue }
            if pair[tab] == nil {
                pair[tab] = renderImage(tab: tab, width: W, height: H, style: style)
            }
            iv.image = pair[tab]
            iv.frame = CGRect(x: 0, y: 0, width: W, height: H)
        }
        cache[style] = pair
    }

    /// Draws the tab's folder outline (forms body + tab bump, the
    /// exact paths the shape version used) into a bitmap ONCE.
    private func renderImage(tab: Int, width W: CGFloat, height H: CGFloat,
                             style: UIUserInterfaceStyle) -> UIImage {
        let signup = tab == 0
        let B = W / 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = traitCollection.displayScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: format)
        let trait = UITraitCollection(userInterfaceStyle: style)
        return renderer.image { _ in
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.addPath(formsPath(signup: signup, width: W, tabs: AccountMetrics.tabHeight, height: H))
            // The bump path is in bump-local coordinates; a path is
            // converted to device space when it is ADDED, so
            // translating the CTM first lands it at its panel offset
            // (the old bump layer's frame origin).
            context.saveGState()
            context.translateBy(x: signup ? 0 : B - 18, y: 0)
            context.addPath(bumpPath(signup: signup, half: B, tabs: AccountMetrics.tabHeight))
            context.restoreGState()
            context.setFillColor(UIColor.white.resolvedColor(with: trait).cgColor)
            context.fillPath()
        }
    }

    /// The bump in bump-local coordinates: local width is B + 18
    /// (B = half the panel). Signup: body at 0…B, foot (with the
    /// concave fillet) extending right to B + 18. Login is the exact
    /// mirror: foot at 0…18, body at 18…B + 18.
    private func bumpPath(signup: Bool, half B: CGFloat, tabs T: CGFloat) -> CGPath {
        let path = UIBezierPath()
        if signup {
            path.move(to: CGPoint(x: 0, y: T))
            path.addLine(to: CGPoint(x: 0, y: 26))
            path.addArc(withCenter: CGPoint(x: 26, y: 26), radius: 26,
                        startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
            path.addLine(to: CGPoint(x: B - 22, y: 0))
            path.addArc(withCenter: CGPoint(x: B - 22, y: 22), radius: 22,
                        startAngle: -.pi / 2, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: B, y: T - 18))
            path.addArc(withCenter: CGPoint(x: B + 18, y: T - 18), radius: 18,
                        startAngle: .pi, endAngle: .pi / 2, clockwise: false)
            path.addLine(to: CGPoint(x: 0, y: T))
        } else {
            path.move(to: CGPoint(x: 0, y: T))
            path.addArc(withCenter: CGPoint(x: 0, y: T - 18), radius: 18,
                        startAngle: .pi / 2, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: 18, y: 22))
            path.addArc(withCenter: CGPoint(x: 40, y: 22), radius: 22,
                        startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
            path.addLine(to: CGPoint(x: B - 8, y: 0))
            path.addArc(withCenter: CGPoint(x: B - 8, y: 26), radius: 26,
                        startAngle: -.pi / 2, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: B + 18, y: T))
            path.addLine(to: CGPoint(x: 0, y: T))
        }
        path.close()
        return path.cgPath
    }

    private func formsPath(signup: Bool, width W: CGFloat, tabs T: CGFloat, height H: CGFloat) -> CGPath {
        let path = UIBezierPath()
        let r: CGFloat = 26
        if signup {
            path.move(to: CGPoint(x: 0, y: T))
            path.addLine(to: CGPoint(x: W - r, y: T))
            path.addArc(withCenter: CGPoint(x: W - r, y: T + r), radius: r,
                        startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        } else {
            path.move(to: CGPoint(x: W, y: T))
            path.addLine(to: CGPoint(x: r, y: T))
            path.addArc(withCenter: CGPoint(x: r, y: T + r), radius: r,
                        startAngle: -.pi / 2, endAngle: .pi, clockwise: false)
        }
        path.addLine(to: CGPoint(x: signup ? W : 0, y: H - r))
        if signup {
            path.addArc(withCenter: CGPoint(x: W - r, y: H - r), radius: r,
                        startAngle: 0, endAngle: .pi / 2, clockwise: true)
            path.addLine(to: CGPoint(x: r, y: H))
            path.addArc(withCenter: CGPoint(x: r, y: H - r), radius: r,
                        startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        } else {
            // Build 19: the login branch's point ORDER was wrong —
            // it is the root cause of the warped panel in Builds
            // 16-18 (see the WhitePanelView note). Travelling down
            // the left edge, the path must FIRST take the bottom-left
            // corner arc from (0, H-r) to (r, H) — the old code
            // reused the signup arc (pi/2 -> pi), whose start point
            // is (r, H), so addArc auto-drew a diagonal chord to it
            // and back (the bottom-left "curl"); the following line
            // to (W-r, H) then ran diagonally from (0, H-r) (bottom
            // slope r/(W-r) = 0.078, device-measured 0.077), and
            // close() connected (W-r, H) diagonally back up to the
            // subpath start (W, T) (right-edge slope -r/(H-T) =
            // -0.104, device-measured -0.104). Every arc below now
            // starts EXACTLY at the current point.
            path.addArc(withCenter: CGPoint(x: r, y: H - r), radius: r,
                        startAngle: .pi, endAngle: .pi / 2, clockwise: false)
            path.addLine(to: CGPoint(x: W - r, y: H))
            path.addArc(withCenter: CGPoint(x: W - r, y: H - r), radius: r,
                        startAngle: .pi / 2, endAngle: 0, clockwise: false)
        }
        path.close()
        return path.cgPath
    }

}

// MARK: - Shared controls

/// The design's `.btn`: 48 tall (44 in modals), radius = height/2,
/// dark #3f3f47, pressed #2f2f37, disabled at 0.72 opacity, success
/// state #1d7a4b with the design's 成功 ✓ label swap.
final class DarkButton: UIButton {
    var isSuccessState = false {
        didSet { refresh() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        setTitleColor(.white, for: .normal)
        layer.cornerRadius = AccountMetrics.buttonHeight / 2
        clipsToBounds = true
        refresh()
        addTarget(self, action: #selector(pressDown), for: .touchDown)
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isEnabled: Bool {
        didSet { refresh() }
    }

    private func refresh() {
        backgroundColor = isSuccessState ? AccountPalette.success : AccountPalette.dark
        alpha = isEnabled ? 1 : 0.72
    }

    func setBusy(_ title: String) {
        isEnabled = false
        setTitle(title, for: .normal)
    }

    func setSuccess() {
        isSuccessState = true
        isEnabled = false
        setTitle("成功 ✓", for: .normal)
    }

    func restore(title: String) {
        isSuccessState = false
        isEnabled = true
        setTitle(title, for: .normal)
    }

    @objc private func pressDown() {
        guard isEnabled, !isSuccessState else { return }
        backgroundColor = AccountPalette.darkPressed
        UIView.animate(withDuration: 0.18) {
            self.transform = CGAffineTransform(scaleX: 0.988, y: 0.988)
        }
    }

    @objc private func pressUp() {
        backgroundColor = isSuccessState ? AccountPalette.success : AccountPalette.dark
        UIView.animate(withDuration: 0.18) { self.transform = .identity }
    }
}

/// The password eye toggle (the design's own two SVGs, shipped as
/// template assets): closed-eye while the password is hidden,
/// open-eye while shown.
final class EyeButton: UIButton {
    private weak var field: UITextField?

    init(field: UITextField) {
        self.field = field
        super.init(frame: .zero)
        setImage(UIImage(named: "AccountEyeClosed")?.withRenderingMode(.alwaysTemplate),
                 for: .normal)
        tintColor = splashHex("#8d8d96")
        addTarget(self, action: #selector(toggle), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func toggle() {
        guard let field else { return }
        let show = field.isSecureTextEntry
        let font = field.font
        field.isSecureTextEntry = !show
        field.font = font  // toggling secure entry can reset the font
        setImage(UIImage(named: show ? "AccountEyeOpen" : "AccountEyeClosed")?
            .withRenderingMode(.alwaysTemplate), for: .normal)
        tintColor = show ? splashHex("#4a4a53") : splashHex("#8d8d96")
    }
}

/// The in-field email suffix picker: a chip showing the current
/// suffix with the design's double chevron; tapping opens a menu of
/// the design's suffix list. The address is COMPOSED — the box holds
/// the local part, the chip holds the suffix, and validation/submit
/// always evaluate local-part + selected suffix as one address (see
/// `resolvedEmail`). Selecting a suffix is enough on its own: the
/// suffix is never typed into the box. Typing a known suffix into
/// the box syncs the chip instead.
final class SuffixChip: UIButton {
    static let suffixes = ["@qq.com", "@163.com", "@gmail.com", "@126.com",
                           "@outlook.com", "@hotmail.com", "@sina.com",
                           "@foxmail.com", "@139.com", "@icloud.com"]
    private(set) var current = "@qq.com"
    /// Fired when the chip's width changes (a different suffix was
    /// picked), so the owner can re-layout the field's accessories.
    var onLayoutNeeded: (() -> Void)?
    private weak var field: UITextField?

    init(field: UITextField) {
        self.field = field
        super.init(frame: .zero)
        titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        setTitleColor(AccountPalette.inkSoft, for: .normal)
        setImage(UIImage(named: "AccountChevron")?.withRenderingMode(.alwaysTemplate),
                 for: .normal)
        tintColor = AccountPalette.inkSoft
        semanticContentAttribute = .forceRightToLeft
        imageEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 0)
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 4)
        showsMenuAsPrimaryAction = true
        setTitle(current, for: .normal)
        rebuildMenu()
        field.addTarget(self, action: #selector(fieldChanged), for: .editingChanged)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var chipWidth: CGFloat {
        let text = (current as NSString).size(
            withAttributes: [.font: titleLabel?.font as Any]).width
        return ceil(text) + 27
    }

    private func rebuildMenu() {
        menu = UIMenu(children: Self.suffixes.map { suffix in
            UIAction(title: suffix, state: suffix == current ? .on : .off) { [weak self] _ in
                self?.select(suffix)
            }
        })
    }

    private func select(_ suffix: String) {
        current = suffix
        setTitle(suffix, for: .normal)
        rebuildMenu()
        // The box keeps holding just the local part — the suffix
        // lives here on the chip. Nudge the field's change handlers
        // so a stale email error re-evaluates against the new pair.
        field?.sendActions(for: .editingChanged)
        onLayoutNeeded?()
    }

    /// The address this field means: local part (whatever precedes
    /// any "@" in the box) + the chip's selected suffix. A fully
    /// typed address whose suffix is NOT one of the chip's is taken
    /// as typed. This composed value — never the raw box text — is
    /// what validation and every account call use, so a complete
    /// valid pair can never sit in the red error state.
    func resolvedEmail() -> String {
        let raw = (field?.text ?? "").trimmingCharacters(in: .whitespaces)
        guard let at = raw.firstIndex(of: "@") else { return raw + current }
        let typedSuffix = String(raw[at...])
        if Self.suffixes.contains(typedSuffix) {
            return String(raw[..<at]) + current
        }
        return raw
    }

    /// Re-reads the suffix from the box (used after the box text is
    /// set programmatically, e.g. returning from the reset page).
    func syncFromField() {
        guard let value = field?.text,
              let at = value.firstIndex(of: "@") else { return }
        let suffix = String(value[at...])
        if Self.suffixes.contains(suffix), suffix != current {
            current = suffix
            setTitle(suffix, for: .normal)
            rebuildMenu()
            onLayoutNeeded?()
        }
    }

    @objc private func fieldChanged() {
        syncFromField()
    }
}

/// Owns a 获取验证码 button's 60 s countdown (the design disables the
/// button and counts "Ns 后重发").
final class CodeCountdown {
    private weak var button: UIButton?
    private var timer: Timer?
    private var left = 0

    init(button: UIButton) { self.button = button }

    var isCounting: Bool { left > 0 }

    func start() {
        left = 60
        button?.isEnabled = false
        button?.alpha = 0.45
        button?.setTitle("60s 后重发", for: .normal)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            left -= 1
            if left <= 0 {
                reset()
            } else {
                button?.setTitle("\(left)s 后重发", for: .normal)
            }
        }
    }

    func reset() {
        timer?.invalidate()
        timer = nil
        left = 0
        button?.isEnabled = true
        button?.alpha = 1
        button?.setTitle("获取验证码", for: .normal)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// Builds a design `.code-btn`: dark pill riding inside the code
/// field's right edge.
func makeCodeButton(in field: FormField, target: Any, action: Selector) -> UIButton {
    let button = UIButton(type: .custom)
    button.setTitle("获取验证码", for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .medium)
    button.backgroundColor = AccountPalette.dark
    button.layer.cornerRadius = AccountMetrics.accessoryHeight / 2
    button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    button.addTarget(target, action: action, for: .touchUpInside)
    field.view.addSubview(button)
    field.input.rightInset = 104
    return button
}

/// Positions a code button inside its field (right 5, vertically
/// centered on the input, h = accessoryHeight).
func layoutCodeButton(_ button: UIButton, in field: FormField, fieldWidth: CGFloat) {
    let size = button.intrinsicContentSize
    button.frame = CGRect(x: fieldWidth - 5 - size.width,
                          y: (AccountMetrics.fieldHeight - AccountMetrics.accessoryHeight) / 2,
                          width: size.width, height: AccountMetrics.accessoryHeight)
}

/// Positions an eye button inside its field (right 5, eyeSize ×
/// eyeSize, vertically centered on the input).
func layoutEyeButton(_ button: UIButton, fieldWidth: CGFloat) {
    button.frame = CGRect(x: fieldWidth - 5 - AccountMetrics.eyeSize,
                          y: (AccountMetrics.fieldHeight - AccountMetrics.eyeSize) / 2,
                          width: AccountMetrics.eyeSize, height: AccountMetrics.eyeSize)
}

/// Positions a suffix chip inside its field (right 5, vertically
/// centered on the input, h = accessoryHeight).
func layoutSuffixChip(_ chip: SuffixChip, fieldWidth: CGFloat) {
    chip.frame = CGRect(x: fieldWidth - 5 - chip.chipWidth,
                        y: (AccountMetrics.fieldHeight - AccountMetrics.accessoryHeight) / 2,
                        width: chip.chipWidth, height: AccountMetrics.accessoryHeight)
}

// MARK: - Page scaffolding

/// Shared scaffolding for the account pages: the page background, the
/// centered gradient card with its title, keyboard-aware scrolling,
/// the cardIn entrance and the design's legal-text modal.
class AccountFormBaseViewController: UIViewController {
    var pageTitle = ""
    /// When set, a close (✕) button rides at the page's top right;
    /// tapping it invokes this instead of entering the app.
    var onClose: (() -> Void)?

    let scrollView = UIScrollView()
    let contentView = UIView()
    let cardView = CSSGradientView(angle: 168, stops: [
        (splashHex("#e3e4e8"), 0), (splashHex("#dedfe3"), 0.45), (splashHex("#d9dade"), 1)
    ])
    let titleLabel = UILabel()
    private let closeButton = UIButton(type: .custom)
    private var entranceDone = false
    private var legalOverlay: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = AccountPalette.pageBg
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        cardView.layer.cornerRadius = 36
        cardView.layer.masksToBounds = true
        contentView.addSubview(cardView)
        titleLabel.text = pageTitle
        titleLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        titleLabel.textColor = splashHex("#111116")
        titleLabel.textAlignment = .center
        cardView.addSubview(titleLabel)
        closeButton.setImage(UIImage(named: "AccountCloseX")?
            .withRenderingMode(.alwaysTemplate), for: .normal)
        closeButton.tintColor = splashHex("#8d8d96")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.isHidden = onClose == nil
        view.addSubview(closeButton)
        // cardIn .75s cubic-bezier(.2,.8,.25,1): from opacity 0,
        // translateY 16, scale .985.
        cardView.alpha = 0
        cardView.transform = CGAffineTransform(translationX: 0, y: 16)
            .scaledBy(x: 0.985, y: 0.985)
        observeKeyboard()
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tap.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !entranceDone {
            entranceDone = true
            let animator = UIViewPropertyAnimator(
                duration: 0.75,
                timingParameters: UICubicTimingParameters(
                    controlPoint1: CGPoint(x: 0.2, y: 0.8),
                    controlPoint2: CGPoint(x: 0.25, y: 1)))
            animator.addAnimations {
                self.cardView.alpha = 1
                self.cardView.transform = .identity
            }
            animator.startAnimation()
        }
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func backgroundTapped() { view.endEditing(true) }

    // MARK: Layout hooks (subclasses)

    /// Height of the card's content region (between the title block
    /// and the card's bottom padding) at the given card width.
    func contentHeight(forWidth width: CGFloat) -> CGFloat { 0 }
    /// Lays content out inside the card; `originY` is the content
    /// region's top within the card.
    func layoutContent(originY: CGFloat, width: CGFloat) {}
    /// Extra height below the card (the brand line on the main page).
    var belowCardHeight: CGFloat { 0 }
    func layoutBelowCard(top: CGFloat, width: CGFloat) {}

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let W = view.bounds.width, H = view.bounds.height
        guard W > 0, H > 0 else { return }
        scrollView.frame = view.bounds
        let cardW = W - 2 * AccountMetrics.cardSideMargin
        let contentH = contentHeight(forWidth: cardW)
        let contentTop = AccountMetrics.cardTopPad + AccountMetrics.titleHeight
            + AccountMetrics.titleGap
        let cardH = contentTop + contentH + AccountMetrics.cardBottomPad
        let totalH = cardH + belowCardHeight
        let scrollContentH = max(H, AccountMetrics.pagePad + totalH + AccountMetrics.pagePad)
        contentView.frame = CGRect(x: 0, y: 0, width: W, height: scrollContentH)
        scrollView.contentSize = contentView.frame.size
        let cardY = totalH < H ? (H - totalH) / 2 : AccountMetrics.pagePad
        cardView.frame = CGRect(x: AccountMetrics.cardSideMargin, y: cardY,
                                width: cardW, height: cardH)
        titleLabel.frame = CGRect(x: 24, y: AccountMetrics.cardTopPad,
                                  width: cardW - 48, height: AccountMetrics.titleHeight)
        layoutContent(originY: contentTop, width: cardW)
        if belowCardHeight > 0 {
            layoutBelowCard(top: cardY + cardH, width: W)
        }
        closeButton.frame = CGRect(x: W - AccountMetrics.cardSideMargin - 38,
                                   y: view.safeAreaInsets.top + 2,
                                   width: 38, height: 38)
        closeButton.isHidden = onClose == nil
    }

    func relayout(animated: Bool) {
        // Build 20: the view MUST be marked dirty first — an
        // animator that only calls layoutIfNeeded() performs no
        // layout pass at all when nothing is marked, so the height
        // change silently never happened (this is also why the
        // register/login tab switch left the card at the old
        // height: setTab now marks the view dirty the same way).
        view.setNeedsLayout()
        if animated {
            // The design's panel height transition: .2s
            // cubic-bezier(.4,.05,.2,1). The layout itself carries
            // the height change (the card and panel resize through
            // layoutIfNeeded inside the animation), so every shape
            // follows its real geometry frame by frame.
            let animator = UIViewPropertyAnimator(
                duration: 0.2,
                timingParameters: UICubicTimingParameters(
                    controlPoint1: CGPoint(x: 0.4, y: 0.05),
                    controlPoint2: CGPoint(x: 0.2, y: 1)))
            animator.addAnimations { self.view.layoutIfNeeded() }
            animator.startAnimation()
        }
    }

    // MARK: Keyboard

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        let overlap = note.name == UIResponder.keyboardWillHideNotification
            ? 0 : max(0, view.bounds.height - view.convert(frame, from: nil).minY)
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        if overlap > 0 { scrollFirstResponderIntoView() }
    }

    private func scrollFirstResponderIntoView() {
        guard let responder = view.firstResponderField else { return }
        let rect = responder.convert(responder.bounds, to: scrollView)
            .insetBy(dx: 0, dy: -12)
        scrollView.scrollRectToVisible(rect, animated: true)
    }

    // MARK: Field factories

    func makeEmailField() -> (FormField, SuffixChip) {
        let field = FormField(placeholder: "请输入邮箱地址")
        field.input.keyboardType = .emailAddress
        field.input.autocapitalizationType = .none
        field.input.textContentType = .emailAddress
        field.input.rightInset = 108
        let chip = SuffixChip(field: field.input)
        field.view.addSubview(chip)
        return (field, chip)
    }

    func makeCodeField(target: Any, action: Selector) -> (FormField, UIButton) {
        let field = FormField(placeholder: "请输入验证码")
        field.input.keyboardType = .numberPad
        field.input.textContentType = .oneTimeCode
        let button = makeCodeButton(in: field, target: target, action: action)
        return (field, button)
    }

    func makePasswordField(placeholder: String, hint: String? = nil) -> (FormField, EyeButton) {
        let field = FormField(placeholder: placeholder, hint: hint)
        field.input.isSecureTextEntry = true
        field.input.textContentType = .password
        field.input.rightInset = 50
        let eye = EyeButton(field: field.input)
        field.view.addSubview(eye)
        return (field, eye)
    }

    // MARK: Legal modal (the design's 服务条款 / 隐私政策 popups)

    func presentLegal(terms: Bool) {
        dismissLegal()
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = UIColor(red: 18 / 255, green: 18 / 255,
                                          blue: 26 / 255, alpha: 0.52)
        overlay.alpha = 0
        let card = UIView()
        card.backgroundColor = .white
        card.layer.cornerRadius = 26
        card.clipsToBounds = true
        overlay.addSubview(card)
        let head = UILabel()
        head.text = terms ? "服务条款" : "隐私政策"
        head.font = .systemFont(ofSize: 17, weight: .semibold)
        head.textColor = AccountPalette.ink
        card.addSubview(head)
        let xButton = UIButton(type: .custom)
        xButton.setImage(UIImage(named: "AccountCloseX")?
            .withRenderingMode(.alwaysTemplate), for: .normal)
        xButton.tintColor = splashHex("#8d8d96")
        xButton.addTarget(self, action: #selector(dismissLegal), for: .touchUpInside)
        card.addSubview(xButton)
        let body = UITextView()
        body.isEditable = false
        body.isSelectable = false
        body.attributedText = legalAttributedText(terms ? LegalTexts.terms : LegalTexts.privacy)
        body.textContainerInset = UIEdgeInsets(top: 16, left: 20, bottom: 8, right: 20)
        body.showsVerticalScrollIndicator = true
        card.addSubview(body)
        let ok = DarkButton()
        ok.setTitle("我已阅读", for: .normal)
        ok.layer.cornerRadius = 22
        ok.addTarget(self, action: #selector(dismissLegal), for: .touchUpInside)
        card.addSubview(ok)
        let cardW = min(560, view.bounds.width - 40)
        let cardH = min(view.bounds.height * 0.82, 760)
        card.frame = CGRect(x: (view.bounds.width - cardW) / 2,
                            y: (view.bounds.height - cardH) / 2,
                            width: cardW, height: cardH)
        head.frame = CGRect(x: 20, y: 18, width: cardW - 76, height: 24)
        xButton.frame = CGRect(x: cardW - 20 - 30, y: 15, width: 30, height: 30)
        let footH: CGFloat = 14 + 44 + 18
        body.frame = CGRect(x: 0, y: 54, width: cardW, height: cardH - 54 - footH)
        ok.frame = CGRect(x: 20, y: cardH - 18 - 44, width: cardW - 40, height: 44)
        card.transform = CGAffineTransform(translationX: 0, y: 14)
            .scaledBy(x: 0.985, y: 0.985)
        card.alpha = 0
        view.addSubview(overlay)
        legalOverlay = overlay
        UIView.animate(withDuration: 0.22) { overlay.alpha = 1 }
        UIView.animate(withDuration: 0.28, delay: 0,
                       options: [.curveEaseOut]) {
            card.alpha = 1
            card.transform = .identity
        }
    }

    @objc func dismissLegal() {
        guard let overlay = legalOverlay else { return }
        legalOverlay = nil
        UIView.animate(withDuration: 0.18, animations: { overlay.alpha = 0 }) { _ in
            overlay.removeFromSuperview()
        }
    }

    private func legalAttributedText(_ blocks: [LegalTexts.Block]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            let paragraph = NSMutableParagraphStyle()
            var font: UIFont
            var color: UIColor
            switch block {
            case .meta(let text):
                font = .systemFont(ofSize: 12)
                color = AccountPalette.muted
                paragraph.lineSpacing = 12 * 0.7
                paragraph.paragraphSpacing = 14
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: color, .paragraphStyle: paragraph]))
            case .heading(let text):
                font = .systemFont(ofSize: 14, weight: .semibold)
                color = AccountPalette.ink
                paragraph.paragraphSpacingBefore = 20
                paragraph.paragraphSpacing = 8
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: color, .paragraphStyle: paragraph]))
            case .body(let text):
                font = .systemFont(ofSize: 13.5)
                color = splashHex("#4a4a53")
                paragraph.lineSpacing = 13.5 * 0.8
                paragraph.paragraphSpacing = 10
                result.append(NSAttributedString(string: text, attributes: [
                    .font: font, .foregroundColor: color, .paragraphStyle: paragraph]))
            }
        }
        return result
    }
}

private extension UIView {
    var firstResponderField: UIView? {
        if isFirstResponder { return self }
        for sub in subviews {
            if let found = sub.firstResponderField { return found }
        }
        return nil
    }
}

// MARK: - Register / login page

final class AccountViewController: AccountFormBaseViewController {
    /// Fired once a register/login fully succeeds (token persisted).
    var onAuthenticated: (() -> Void)?

    private let panelView = UIView()
    private let whitePanel = WhitePanelView()
    private let signupTabButton = UIButton(type: .custom)
    private let loginTabButton = UIButton(type: .custom)
    private let signupForm = UIView()
    private let loginForm = UIView()
    private var activeTab = 0
    /// The tab switch's two animators (panel crossfade + height;
    /// the two forms' cross-fade). A new tap first snaps any
    /// in-flight switch to its end state, so the choreography can
    /// never stack or be left half-applied.
    private var switchAnimator: UIViewPropertyAnimator?
    private var formInAnimator: UIViewPropertyAnimator?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Returning to this page (e.g. from the reset page): top
        // the spare challenge up if it went stale meanwhile.
        CaptchaPrefetch.warm()
    }

    private var suEmail: FormField!
    private var suChip: SuffixChip!
    private var suCode: FormField!
    private var suCodeButton: UIButton!
    private var suCountdown: CodeCountdown!
    private var suPass: FormField!
    private var suPassEye: EyeButton!
    private var suConfirm: FormField!
    private var suConfirmEye: EyeButton!
    private var suKey: FormField!
    private let suButton = DarkButton()
    private let agreeView = UIView()
    private let agreeBox = UIButton(type: .custom)
    private let agreeCheck = UIImageView(image: UIImage(named: "AccountCheck"))
    private let agreeLabel = UILabel()
    private let agreeTermsButton = UIButton(type: .custom)
    private let agreeAndLabel = UILabel()
    private let agreePrivacyButton = UIButton(type: .custom)
    private var agreeChecked = false
    private var agreeWarned = false

    private var liEmail: FormField!
    private var liChip: SuffixChip!
    private var liPass: FormField!
    private var liPassEye: EyeButton!
    private let liButton = DarkButton()
    private let forgotButton = UIButton(type: .custom)

    private let brandView = UIView()
    private var brandLayers: [CATextLayer] = []
    private var brandAnimated = false
    /// The account-ban popup (Build 20: the red fig2 popup, hosted
    /// as a child covering this page while a ban is being shown).
    private var banPopupController: VersionPopupViewController?

    override func viewDidLoad() {
        pageTitle = "注册或登录账户"
        super.viewDidLoad()
        // Build 21: warm a slider-captcha challenge the moment the
        // account page opens, so if verification is needed the
        // sheet comes up with its notch already rendered.
        CaptchaPrefetch.warm()
        cardView.addSubview(panelView)
        panelView.addSubview(whitePanel)
        // Tabs
        for (button, title, tag) in [(signupTabButton, "注册", 0), (loginTabButton, "登录", 1)] {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14.5)
            button.tag = tag
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            panelView.addSubview(button)
        }
        panelView.addSubview(signupForm)
        panelView.addSubview(loginForm)
        loginForm.isHidden = true
        // Build 44: clip each form to its own bounds. During a tab
        // switch the layout prices BOTH forms at the incoming tab's
        // panel height while the outgoing form's children keep their
        // natural offsets, so unclipped, the outgoing form's lower
        // rows would spill past the panel's bottom edge while it
        // cross-fades out (part of the old ghosting). At rest each
        // form's height is priced to its own content, so the clip
        // is a no-op when settled.
        signupForm.clipsToBounds = true
        loginForm.clipsToBounds = true
        // Signup form
        let (emailF, emailChip) = makeEmailField()
        suEmail = emailF; suChip = emailChip
        suChip.onLayoutNeeded = { [weak self] in self?.relayout(animated: false) }
        let (codeF, codeBtn) = makeCodeField(target: self, action: #selector(getCodeTapped))
        suCode = codeF; suCodeButton = codeBtn
        suCountdown = CodeCountdown(button: codeBtn)
        let (passF, passEye) = makePasswordField(
            placeholder: "设置密码", hint: "至少 8 个字符，需含大写和小写字母各 1 个。")
        suPass = passF; suPassEye = passEye
        suPass.input.textContentType = .newPassword
        suPass.marginBottom = AccountMetrics.shortFieldGap
        let (confirmF, confirmEye) = makePasswordField(placeholder: "请再次输入密码")
        suConfirm = confirmF; suConfirmEye = confirmEye
        suConfirm.input.textContentType = .newPassword
        suKey = FormField(placeholder: "填写授权卡密（可不填）")
        suKey.input.autocapitalizationType = .allCharacters
        for field in [suEmail, suCode, suPass, suConfirm, suKey] {
            signupForm.addSubview(field!.view)
            field!.onHeightChanged = { [weak self] in self?.relayout(animated: true) }
        }
        suButton.setTitle("创建账户", for: .normal)
        suButton.addTarget(self, action: #selector(signupTapped), for: .touchUpInside)
        signupForm.addSubview(suButton)
        buildAgreeRow()
        signupForm.addSubview(agreeView)
        // Login form
        let (liEmailF, liEmailChip) = makeEmailField()
        liEmail = liEmailF; liChip = liEmailChip
        liChip.onLayoutNeeded = { [weak self] in self?.relayout(animated: false) }
        let (liPassF, liPassEyeBtn) = makePasswordField(placeholder: "请输入密码")
        liPass = liPassF; liPassEye = liPassEyeBtn
        liPass.input.textContentType = .password
        for field in [liEmail, liPass] {
            loginForm.addSubview(field!.view)
            field!.onHeightChanged = { [weak self] in self?.relayout(animated: true) }
        }
        liButton.setTitle("登录", for: .normal)
        liButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        loginForm.addSubview(liButton)
        forgotButton.setTitle("忘记密码？", for: .normal)
        forgotButton.titleLabel?.font = .systemFont(ofSize: 12.5)
        forgotButton.setTitleColor(splashHex("#aaacb6"), for: .normal)
        forgotButton.addTarget(self, action: #selector(forgotTapped), for: .touchUpInside)
        loginForm.addSubview(forgotButton)
        updateTabStyles()
        buildBrand()
        contentView.addSubview(brandView)
    }

    private func buildAgreeRow() {
        agreeBox.layer.cornerRadius = 7.5
        agreeBox.layer.borderWidth = 1.5
        agreeBox.layer.borderColor = splashHex("#d5d5de").cgColor
        agreeBox.backgroundColor = .white
        agreeBox.addTarget(self, action: #selector(agreeTapped), for: .touchUpInside)
        agreeCheck.isHidden = true
        agreeBox.addSubview(agreeCheck)
        agreeView.addSubview(agreeBox)
        agreeLabel.text = "我已阅读并同意"
        agreeTermsButton.setTitle("《服务条款》", for: .normal)
        agreeTermsButton.addTarget(self, action: #selector(termsTapped), for: .touchUpInside)
        agreeAndLabel.text = "和"
        agreePrivacyButton.setTitle("《隐私政策》", for: .normal)
        agreePrivacyButton.addTarget(self, action: #selector(privacyTapped), for: .touchUpInside)
        for label in [agreeLabel, agreeAndLabel] {
            label.font = .systemFont(ofSize: 12.5, weight: .light)
            label.textColor = AccountPalette.muted
            agreeView.addSubview(label)
        }
        for button in [agreeTermsButton, agreePrivacyButton] {
            button.titleLabel?.font = .systemFont(ofSize: 12.5, weight: .light)
            button.setTitleColor(.black, for: .normal)
            agreeView.addSubview(button)
        }
    }

    private func buildBrand() {
        let font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        let ctFont = CTFontCreateWithName(font.fontName as CFString, 19, nil)
        for char in "LUIYou-PRO" {
            let layer = CATextLayer()
            layer.string = String(char)
            layer.font = ctFont
            layer.fontSize = 19
            layer.foregroundColor = splashHex("#7d7d88").cgColor
            layer.alignmentMode = .center
            layer.contentsScale = UIScreen.main.scale
            brandView.layer.addSublayer(layer)
            brandLayers.append(layer)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !brandAnimated {
            brandAnimated = true
            let base = splashHex("#7d7d88").cgColor
            let dark = splashHex("#33333b").cgColor
            for (i, layer) in brandLayers.enumerated() {
                let wave = CAKeyframeAnimation(keyPath: "foregroundColor")
                wave.values = [base, dark, base, base]
                wave.keyTimes = [0, 0.28, 0.62, 1]
                wave.timingFunctions = [SplashTiming.cssEaseInOut,
                                        SplashTiming.cssEaseInOut,
                                        SplashTiming.cssEaseInOut]
                wave.duration = 3.2
                wave.beginTime = CACurrentMediaTime() + Double(i) * 0.09
                wave.repeatCount = .infinity
                layer.add(wave, forKey: "brandWave")
            }
        }
    }

    // MARK: Layout

    override var belowCardHeight: CGFloat { AccountMetrics.brandGap + 26 }

    override func layoutBelowCard(top: CGFloat, width: CGFloat) {
        brandView.frame = CGRect(x: 0, y: top + AccountMetrics.brandGap, width: width, height: 26)
        let font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        let spacing: CGFloat = 19 * 0.08
        var widths: [CGFloat] = []
        var total: CGFloat = 0
        for layer in brandLayers {
            let w = ((layer.string as? String) ?? "")
                .size(withAttributes: [.font: font]).width
            widths.append(w)
            total += w + spacing
        }
        total -= spacing
        var x = (width - total) / 2
        for (i, layer) in brandLayers.enumerated() {
            layer.frame = CGRect(x: x, y: 3, width: widths[i] + spacing, height: 22)
            x += widths[i] + spacing
        }
    }

    private func formContentHeight(_ form: UIView, fields: [FormField],
                                   width: CGFloat) -> CGFloat {
        var y: CGFloat = AccountMetrics.formPadTop
        for field in fields {
            y += field.layout(width: width) + field.marginBottom
        }
        if form === signupForm {
            y += AccountMetrics.buttonHeight + AccountMetrics.agreeGap
                + AccountMetrics.agreeRowHeight
        } else {
            y += AccountMetrics.buttonHeight + AccountMetrics.forgotGap
                + AccountMetrics.agreeRowHeight
        }
        return y + AccountMetrics.formPadBottom
    }

    private func panelHeight(forTab tab: Int, formW: CGFloat) -> CGFloat {
        if tab == 0 {
            let fields = [suEmail, suCode, suPass, suConfirm, suKey].compactMap { $0 }
            return AccountMetrics.tabHeight + formContentHeight(signupForm, fields: fields, width: formW)
        }
        let fields = [liEmail, liPass].compactMap { $0 }
        return AccountMetrics.tabHeight + formContentHeight(loginForm, fields: fields, width: formW)
    }

    override func contentHeight(forWidth width: CGFloat) -> CGFloat {
        let panelW = width - 2 * AccountMetrics.panelInset
        return panelHeight(forTab: activeTab, formW: panelW - 32)
    }

    override func layoutContent(originY: CGFloat, width: CGFloat) {
        let panelW = width - 2 * AccountMetrics.panelInset
        let formW = panelW - 32
        let panelH = contentHeight(forWidth: width)
        panelView.frame = CGRect(x: AccountMetrics.panelInset, y: originY, width: panelW, height: panelH)
        whitePanel.frame = panelView.bounds
        whitePanel.setHeights(signup: panelHeight(forTab: 0, formW: formW),
                              login: panelHeight(forTab: 1, formW: formW))
        signupTabButton.frame = CGRect(x: 0, y: 0, width: panelW / 2, height: AccountMetrics.tabHeight)
        loginTabButton.frame = CGRect(x: panelW / 2, y: 0, width: panelW / 2, height: AccountMetrics.tabHeight)
        for form in [signupForm, loginForm] {
            form.frame = CGRect(x: 0, y: AccountMetrics.tabHeight,
                                width: panelW, height: panelH - AccountMetrics.tabHeight)
        }
        layoutSignup(formW: formW)
        layoutLogin(formW: formW)
    }

    private func layoutSignup(formW: CGFloat) {
        var y: CGFloat = AccountMetrics.formPadTop
        for field in [suEmail, suCode, suPass, suConfirm, suKey] {
            guard let field else { continue }
            field.view.frame = CGRect(x: 16, y: y, width: formW, height: 0)
            y += field.layout(width: formW) + field.marginBottom
        }
        layoutSuffixChip(suChip, fieldWidth: formW)
        layoutCodeButton(suCodeButton, in: suCode, fieldWidth: formW)
        layoutEyeButton(suPassEye, fieldWidth: formW)
        layoutEyeButton(suConfirmEye, fieldWidth: formW)
        suButton.frame = CGRect(x: 16, y: y, width: formW, height: AccountMetrics.buttonHeight)
        y += AccountMetrics.buttonHeight + AccountMetrics.agreeGap
        layoutAgreeRow(y: y, formW: formW)
    }

    private func layoutAgreeRow(y: CGFloat, formW: CGFloat) {
        agreeView.frame = CGRect(x: 16, y: y, width: formW, height: AccountMetrics.agreeRowHeight)
        let boxSize: CGFloat = 15
        let labelW = (agreeLabel.text! as NSString)
            .size(withAttributes: [.font: agreeLabel.font as Any]).width
        let termsW = ("《服务条款》" as NSString)
            .size(withAttributes: [.font: agreeTermsButton.titleLabel!.font as Any]).width
        let andW = ("和" as NSString)
            .size(withAttributes: [.font: agreeAndLabel.font as Any]).width
        let privacyW = ("《隐私政策》" as NSString)
            .size(withAttributes: [.font: agreePrivacyButton.titleLabel!.font as Any]).width
        let total = boxSize + 6 + labelW + 2 + termsW + 2 + andW + 2 + privacyW
        var x = (formW - total) / 2
        agreeBox.frame = CGRect(x: x, y: (AccountMetrics.agreeRowHeight - boxSize) / 2,
                                width: boxSize, height: boxSize)
        agreeCheck.frame = CGRect(x: 2, y: 2, width: 11, height: 11)
        x += boxSize + 6
        agreeLabel.frame = CGRect(x: x, y: 0, width: labelW, height: AccountMetrics.agreeRowHeight)
        x += labelW + 2
        agreeTermsButton.frame = CGRect(x: x, y: 0, width: termsW, height: AccountMetrics.agreeRowHeight)
        x += termsW + 2
        agreeAndLabel.frame = CGRect(x: x, y: 0, width: andW, height: AccountMetrics.agreeRowHeight)
        x += andW + 2
        agreePrivacyButton.frame = CGRect(x: x, y: 0, width: privacyW, height: AccountMetrics.agreeRowHeight)
    }

    private func layoutLogin(formW: CGFloat) {
        var y: CGFloat = AccountMetrics.formPadTop
        for field in [liEmail, liPass] {
            guard let field else { continue }
            field.view.frame = CGRect(x: 16, y: y, width: formW, height: 0)
            y += field.layout(width: formW) + field.marginBottom
        }
        layoutSuffixChip(liChip, fieldWidth: formW)
        layoutEyeButton(liPassEye, fieldWidth: formW)
        liButton.frame = CGRect(x: 16, y: y, width: formW, height: AccountMetrics.buttonHeight)
        y += AccountMetrics.buttonHeight + AccountMetrics.forgotGap
        forgotButton.frame = CGRect(x: 16, y: y, width: formW, height: AccountMetrics.agreeRowHeight)
    }

    // MARK: Tabs

    @objc private func tabTapped(_ sender: UIButton) {
        setTab(sender.tag)
    }

    /// Snaps any in-flight tab switch to its end state (final
    /// alphas, final layout, outgoing form hidden) so a new switch
    /// always starts from a coherent state.
    private func finishSwitchAnimations() {
        for animator in [switchAnimator, formInAnimator] {
            if let animator, animator.isRunning {
                animator.stopAnimation(false)
                animator.finishAnimation(at: .end)
            }
        }
        switchAnimator = nil
        formInAnimator = nil
    }

    func setTab(_ index: Int) {
        guard index != activeTab else { return }
        finishSwitchAnimations()
        activeTab = index
        // Build 20: mark the view dirty BEFORE the switch animator
        // runs layoutIfNeeded(). Without this the animator's layout
        // call was a no-op (nothing was marked), so the card kept
        // the OUTGOING form's height forever — switching to login
        // left the short form floating at the top of a register-tall
        // card with a large empty gray area below it. With the view
        // marked, the layout pass runs with the NEW activeTab:
        // contentHeight() prices the incoming form, the card + panel
        // resize on the same panel curve in BOTH directions, and
        // because the layout centers the card for whatever height
        // it currently has (both resting centers are the screen
        // center), the assembly stays centered throughout the
        // contraction/expansion.
        view.setNeedsLayout()
        updateTabStyles()
        let incoming = index == 0 ? signupForm : loginForm
        let outgoing = index == 0 ? loginForm : signupForm
        clearErrors(of: outgoing)
        // Build 19 switch choreography (the Build 18 instant snap
        // read as fake/abrupt on device): the panel bitmaps
        // CROSSFADE while the sheet layout (panel + card heights,
        // so the sheet below contracts/expands with the form)
        // animates on the design's panel curve
        // cubic-bezier(.4,.05,.2,1); the two forms cross-fade
        // across the same interval (Build 44, below). The panel
        // bitmaps are pinned at natural size inside the clipping
        // panel for the whole switch — only frames, clip and
        // opacity ever move, so no frame of the switch can shear or
        // squash (and with the formsPath point order fixed, the
        // bitmaps themselves are exact).
        // Build 21: the whole switch slowed down — on device the
        // Build 19/20 timings still read fast and snappy, so the
        // panel runs 0.55s and the switch settles with it.
        // Build 44: the FORM swap is now a true cross-fade over the
        // panel's full 0.55s. Builds 19–43 ran it SEQUENTIALLY: the
        // outgoing form faded out over 0.22s and hid, and the
        // incoming form's formIn only STARTED at 0.25s (its alpha
        // pinned at 0 until then) — between ≈0.22s and the new
        // form's fade-in getting going, NEITHER form was visible
        // and the white panel sat completely blank mid-switch (the
        // user's Build 43 recording, worst in the login→signup
        // direction where the panel is also growing). Now one
        // animator drives outgoing alpha 1→0, incoming alpha 0→1
        // and the incoming form's design 7px rise on the design's
        // formIn curve, all from t=0: both alphas ride the same
        // fraction and sum to ~1 at every frame, so the panel is
        // never empty, and the overlap never exceeds a clean
        // cross-fade.
        outgoing.isHidden = false
        outgoing.alpha = 1
        incoming.isHidden = false
        incoming.alpha = 0
        incoming.transform = CGAffineTransform(translationX: 0, y: 7)

        let panelAnim = UIViewPropertyAnimator(
            duration: 0.55,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.4, y: 0.05),
                controlPoint2: CGPoint(x: 0.2, y: 1)))
        whitePanel.crossfade(to: index, in: panelAnim)
        panelAnim.addAnimations { self.view.layoutIfNeeded() }
        panelAnim.startAnimation()
        switchAnimator = panelAnim

        let formsAnim = UIViewPropertyAnimator(
            duration: 0.55,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.25, y: 0.8),
                controlPoint2: CGPoint(x: 0.3, y: 1)))
        formsAnim.addAnimations {
            outgoing.alpha = 0
            incoming.alpha = 1
            incoming.transform = .identity
        }
        formsAnim.addCompletion { position in
            if position == .end {
                outgoing.isHidden = true
            }
        }
        formsAnim.startAnimation()
        formInAnimator = formsAnim
    }

    private func clearErrors(of form: UIView) {
        let fields = form === signupForm
            ? [suEmail, suCode, suPass, suConfirm, suKey]
            : [liEmail, liPass]
        for field in fields { field?.setError(nil) }
    }

    private func updateTabStyles() {
        for (button, index) in [(signupTabButton, 0), (loginTabButton, 1)] {
            let active = index == activeTab
            button.setTitleColor(active ? AccountPalette.tabActive : AccountPalette.tabIdle,
                                 for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14.5,
                                                  weight: active ? .medium : .regular)
        }
    }

    // MARK: Agree

    @objc private func agreeTapped() {
        agreeChecked.toggle()
        applyAgreeStyle()
        if agreeChecked { setAgreeWarn(false) }
    }

    private func applyAgreeStyle() {
        agreeBox.backgroundColor = agreeChecked ? AccountPalette.dark : .white
        agreeBox.layer.borderColor = (agreeChecked
            ? AccountPalette.dark : splashHex("#d5d5de")).cgColor
        agreeCheck.isHidden = !agreeChecked
    }

    private func setAgreeWarn(_ on: Bool) {
        agreeWarned = on
        let color = on ? AccountPalette.errorBorderFocus : nil
        agreeLabel.textColor = color ?? AccountPalette.muted
        agreeAndLabel.textColor = color ?? AccountPalette.muted
        agreeTermsButton.setTitleColor(color ?? .black, for: .normal)
        agreePrivacyButton.setTitleColor(color ?? .black, for: .normal)
    }

    @objc private func termsTapped() { presentLegal(terms: true) }
    @objc private func privacyTapped() { presentLegal(terms: false) }
}

// MARK: - Account flows

extension AccountViewController {
    static let emailRegex = try! NSRegularExpression(
        pattern: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#)

    static func emailValid(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return emailRegex.firstMatch(in: value, range: range) != nil
    }

    /// The design's passwordIssue(): exact design messages.
    static func passwordIssue(_ value: String) -> String? {
        if value.isEmpty { return "请设置密码。" }
        if value.count < 8 { return "密码至少需要 8 个字符。" }
        if !value.contains(where: { $0.isUppercase }) { return "请至少添加 1 个大写字母。" }
        if !value.contains(where: { $0.isLowercase }) { return "请至少添加 1 个小写字母。" }
        return nil
    }

    // MARK: Signup — get code

    @objc func getCodeTapped() {
        if suCountdown.isCounting { return }
        if !agreeChecked {
            setAgreeWarn(true)
            return
        }
        // The composed address: box local part + the chip's suffix.
        let email = suChip.resolvedEmail()
        if suEmail.text.trimmingCharacters(in: .whitespaces).isEmpty {
            suEmail.setError("请输入邮箱地址。"); return
        }
        if !Self.emailValid(email) { suEmail.setError("邮箱格式不完整，请检查。"); return }
        suEmail.setError(nil)
        performProtected("send_code", ["email": email, "purpose": "register"],
                         onStart: { [weak self] in self?.suCodeButton.isEnabled = false }
        ) { [weak self] result in
            guard let self, let result else { return }
            switch AccountAPI.outcome(result) {
            case .ok:
                suCountdown.start()
            case .error(let message):
                suCodeButton.isEnabled = true
                suCode.setError(message)
            }
        }
    }

    // MARK: Signup — submit

    @objc func signupTapped() {
        let email = suChip.resolvedEmail()
        var firstBad: UITextField?
        if suEmail.text.trimmingCharacters(in: .whitespaces).isEmpty {
            suEmail.setError("请输入邮箱地址。"); firstBad = firstBad ?? suEmail.input
        } else if !Self.emailValid(email) {
            suEmail.setError("邮箱格式不完整，请检查。"); firstBad = firstBad ?? suEmail.input
        } else { suEmail.setError(nil) }

        let code = suCode.text.trimmingCharacters(in: .whitespaces)
        if code.isEmpty {
            suCode.setError("请输入验证码。"); firstBad = firstBad ?? suCode.input
        } else if !(code.count == 6 && code.allSatisfy({ $0.isNumber })) {
            suCode.setError("验证码为 6 位数字。"); firstBad = firstBad ?? suCode.input
        } else { suCode.setError(nil) }

        if let issue = Self.passwordIssue(suPass.text) {
            suPass.setError(issue); firstBad = firstBad ?? suPass.input
        } else { suPass.setError(nil) }

        if suConfirm.text.isEmpty {
            suConfirm.setError("请再次输入密码。"); firstBad = firstBad ?? suConfirm.input
        } else if suConfirm.text != suPass.text {
            suConfirm.setError("两次输入的密码不一致。"); firstBad = firstBad ?? suConfirm.input
        } else { suConfirm.setError(nil) }

        if !agreeChecked {
            setAgreeWarn(true)
            firstBad = firstBad ?? suEmail.input
        }
        if firstBad != nil {
            firstBad?.becomeFirstResponder()
            return
        }
        performDirect("register", [
            "email": email, "password": suPass.text, "code": code
        ], onStart: { [weak self] in self?.suButton.setBusy("正在创建账户…") }
        ) { [weak self] result in
            guard let self, let result else { return }
            switch AccountAPI.outcome(result) {
            case .ok:
                login(email: email, password: suPass.text,
                      button: suButton, restoreTitle: "创建账户", busyTitle: "正在创建账户…",
                      card: suKey.text.trimmingCharacters(in: .whitespaces),
                      passwordField: suPass, emailField: suEmail)
            case .error(let message):
                suButton.restore(title: "创建账户")
                if message.contains("验证码") { suCode.setError(message) }
                else if message.contains("密码") { suPass.setError(message) }
                else { suEmail.setError(message) }
            }
        }
    }

    // MARK: Login — submit

    @objc func loginTapped() {
        let email = liChip.resolvedEmail()
        var firstBad: UITextField?
        if liEmail.text.trimmingCharacters(in: .whitespaces).isEmpty {
            liEmail.setError("请输入邮箱地址。"); firstBad = liEmail.input
        } else if !Self.emailValid(email) {
            liEmail.setError("邮箱格式不完整，请检查。"); firstBad = firstBad ?? liEmail.input
        } else { liEmail.setError(nil) }
        if liPass.text.isEmpty {
            liPass.setError("请输入密码。"); firstBad = firstBad ?? liPass.input
        } else { liPass.setError(nil) }
        if let firstBad {
            firstBad.becomeFirstResponder()
            return
        }
        login(email: email, password: liPass.text,
              button: liButton, restoreTitle: "登录", busyTitle: "正在登录…",
              card: "", passwordField: liPass, emailField: liEmail)
    }

    /// The shared login call (captcha-protected): success persists
    /// the token — a new device now logs in directly once the slider
    /// proof is attached (the backend switches the device and kicks
    /// the old one; there is no email-confirmation detour anymore);
    /// a ban opens the blocking red ban popup; errors land on the
    /// relevant field.
    func login(email: String, password: String, button: DarkButton,
               restoreTitle: String, busyTitle: String, card: String,
               passwordField: FormField, emailField: FormField) {
        performDirect("login", [
            "email": email, "password": password,
            "device_id": AccountSession.deviceID
        ], onStart: { button.setBusy(busyTitle) }
        ) { [weak self] result in
            guard let self, let result else { return }
            switch result {
            case .failure:
                button.restore(title: restoreTitle)
                emailField.setError("网络异常，请稍后再试")
            case .success(let json):
                if (json["ok"] as? Bool) == true, let token = json["token"] as? String {
                    completeAuth(token: token, email: email, card: card, button: button)
                } else if json["banned"] as? Bool == true {
                    button.restore(title: restoreTitle)
                    presentBanned(title: json["ban_title"] as? String ?? "",
                                  subtitle: json["ban_subtitle"] as? String ?? "",
                                  reason: json["ban_reason"] as? String ?? "")
                } else {
                    button.restore(title: restoreTitle)
                    let message = json["error"] as? String ?? "登录失败"
                    if message.contains("密码") || message.contains("锁定") {
                        passwordField.setError(message)
                    } else {
                        emailField.setError(message)
                    }
                }
            }
        }
    }

    /// Persists the session, binds the optional card (a bind failure
    /// is shown on the card field but never undoes the login), plays
    /// the design's success state, then hands over to the gate.
    func completeAuth(token: String, email: String, card: String, button: DarkButton) {
        AccountSession.save(token: token, email: email)
        let enter = { [weak self] in
            button.setSuccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self?.onAuthenticated?()
            }
        }
        if card.isEmpty {
            enter()
            return
        }
        AccountAPI.post("bind_card", ["token": token, "card": card]) { [weak self] result in
            guard let self else { return }
            if case .error(let message) = AccountAPI.outcome(result) {
                suKey.setError(message)
            }
            enter()
        }
    }

    // MARK: Aux pages

    private func presentAux(_ controller: UIViewController) {
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        present(controller, animated: true)
    }

    /// Build 20: a banned login answer shows the SAME red banned
    /// popup as the version ban (fig2 design, reused wholesale via
    /// VersionPopupViewController) instead of the old plain ban
    /// page. It is hosted as a child covering this page — the same
    /// in-window hosting the version popup uses. 退出 clears the
    /// account session and dismisses the whole account page, back
    /// to the gate's 03 splash; 联系客服 opens the shared support
    /// link (AppConfiguration.supportURL).
    func presentBanned(title: String, subtitle: String, reason: String) {
        guard banPopupController == nil else { return }
        let popup = VersionPopupViewController(
            payload: VersionPopup.accountBanPayload(
                title: title, subtitle: subtitle, reason: reason))
        popup.onBannedExit = { [weak self] in
            guard let self else { return }
            AccountSession.clear()
            removeBanPopup()
            onClose?()
        }
        banPopupController = popup
        addChild(popup)
        popup.view.frame = view.bounds
        popup.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(popup.view)
        popup.didMove(toParent: self)
        popup.view.layoutIfNeeded()
        popup.beginEntrance()
    }

    private func removeBanPopup() {
        guard let popup = banPopupController else { return }
        banPopupController = nil
        popup.willMove(toParent: nil)
        popup.view.removeFromSuperview()
        popup.removeFromParent()
    }

    @objc func forgotTapped() {
        let reset = ResetPasswordViewController()
        reset.onClose = { [weak self] in self?.dismiss(animated: true) }
        reset.onResetSuccess = { [weak self] email in
            guard let self else { return }
            dismiss(animated: true) {
                self.setTab(1)
                self.liEmail.input.text = email
                self.liChip.syncFromField()
                self.liEmail.setError(nil)
                self.liPass.input.becomeFirstResponder()
            }
        }
        presentAux(reset)
    }
}

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
    var marginBottom: CGFloat = 20
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
        input.frame = CGRect(x: 0, y: 0, width: width, height: 40)
        var y: CGFloat = 40
        if let hintLabel {
            y += 7
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

/// The white region behind the tabs + form: a folder-tab shape drawn
/// as two shape layers — the sliding tab bump (with its concave 18px
/// fillet where it meets the form) and the form body (top corner
/// rounded on the inactive side only). Mirrors the design's
/// `.tab-ind` + `.forms` border-radius choreography.
final class WhitePanelView: UIView {
    /// 0 = signup (bump left), 1 = login (bump right).
    private(set) var tabIndex = 0
    private let formsView = ShapeView()
    private let bumpView = ShapeView()
    private var panelHeight: CGFloat = 0
    private var sliding = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        formsView.shape.fillColor = UIColor.white.cgColor
        bumpView.shape.fillColor = UIColor.white.cgColor
        addSubview(formsView)
        addSubview(bumpView)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setHeight(_ height: CGFloat) {
        let changed = abs(height - panelHeight) > 0.5
        panelHeight = height
        rebuildPaths(animatePath: changed)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        formsView.frame = bounds
        rebuildPaths(animatePath: false)
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
            path.addArc(withCenter: CGPoint(x: r, y: H - r), radius: r,
                        startAngle: .pi / 2, endAngle: .pi, clockwise: true)
            path.addLine(to: CGPoint(x: W - r, y: H))
            path.addArc(withCenter: CGPoint(x: W - r, y: H - r), radius: r,
                        startAngle: 0, endAngle: .pi / 2, clockwise: true)
        }
        path.close()
        return path.cgPath
    }

    private func rebuildPaths(animatePath: Bool) {
        let W = bounds.width
        guard W > 0, panelHeight > 54 else { return }
        let signup = tabIndex == 0
        let B = W / 2
        let newFormsPath = formsPath(signup: signup, width: W, tabs: 54, height: panelHeight)
        if animatePath, let oldPath = formsView.shape.path {
            let anim = CABasicAnimation(keyPath: "path")
            anim.fromValue = oldPath
            anim.toValue = newFormsPath
            anim.duration = 0.25
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            formsView.shape.add(anim, forKey: "heightMorph")
        }
        formsView.shape.path = newFormsPath
        bumpView.shape.path = bumpPath(signup: signup, half: B, tabs: 54)
        if !sliding {
            bumpView.frame = CGRect(x: signup ? 0 : B - 18, y: 0,
                                    width: B + 18, height: 54)
        }
    }

    /// Slides the bump across with the design's .52s tab curve,
    /// swapping its mirrored path and the form body's corner at the
    /// midpoint (the design crossfades its notches the same way).
    func slide(to index: Int) {
        guard index != tabIndex else { return }
        tabIndex = index
        let W = bounds.width
        let B = W / 2
        sliding = true
        let animator = UIViewPropertyAnimator(
            duration: 0.52,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.62, y: 0.04),
                controlPoint2: CGPoint(x: 0.33, y: 1)))
        animator.addAnimations {
            self.bumpView.frame = CGRect(x: index == 0 ? 0 : B - 18, y: 0,
                                         width: B + 18, height: 54)
        }
        animator.addAnimations({ [weak self] in
            guard let self else { return }
            self.bumpView.shape.path = self.bumpPath(signup: index == 0, half: B, tabs: 54)
            self.formsView.shape.path = self.formsPath(
                signup: index == 0, width: W, tabs: 54, height: self.panelHeight)
        }, delayFactor: 0.5)
        animator.addCompletion { [weak self] _ in
            self?.sliding = false
            self?.rebuildPaths(animatePath: false)
        }
        animator.startAnimation()
    }
}

/// A view backed by a CAShapeLayer (for the white panel pieces).
final class ShapeView: UIView {
    override class var layerClass: AnyClass { CAShapeLayer.self }
    var shape: CAShapeLayer { layer as! CAShapeLayer }
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
        layer.cornerRadius = 24
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
/// the design's suffix list and rewrites the field as
/// `userPart + suffix`. Typing a known suffix syncs the chip.
final class SuffixChip: UIButton {
    static let suffixes = ["@qq.com", "@163.com", "@gmail.com", "@126.com",
                           "@outlook.com", "@hotmail.com", "@sina.com",
                           "@foxmail.com", "@139.com", "@icloud.com"]
    private(set) var current = "@qq.com"
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
        if let field {
            let value = field.text ?? ""
            let userPart = value.split(separator: "@", maxSplits: 1).first.map(String.init) ?? value
            field.text = userPart + suffix
            field.sendActions(for: .editingChanged)
        }
    }

    @objc private func fieldChanged() {
        guard let value = field?.text,
              let at = value.firstIndex(of: "@") else { return }
        let suffix = String(value[at...])
        if Self.suffixes.contains(suffix), suffix != current {
            current = suffix
            setTitle(suffix, for: .normal)
            rebuildMenu()
        }
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
    button.layer.cornerRadius = 15
    button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    button.addTarget(target, action: action, for: .touchUpInside)
    field.view.addSubview(button)
    field.input.rightInset = 104
    return button
}

/// Positions a code button inside its field (right 5, top 5, h 30).
func layoutCodeButton(_ button: UIButton, in field: FormField, fieldWidth: CGFloat) {
    let size = button.intrinsicContentSize
    button.frame = CGRect(x: fieldWidth - 5 - size.width, y: 5,
                          width: size.width, height: 30)
}

/// Positions an eye button inside its field (right 5, 38 × 38,
/// vertically centered on the 40-tall input).
func layoutEyeButton(_ button: UIButton, fieldWidth: CGFloat) {
    button.frame = CGRect(x: fieldWidth - 5 - 38, y: 1, width: 38, height: 38)
}

/// Positions a suffix chip inside its field (right 5, top 5, h 30).
func layoutSuffixChip(_ chip: SuffixChip, fieldWidth: CGFloat) {
    chip.frame = CGRect(x: fieldWidth - 5 - chip.chipWidth, y: 5,
                        width: chip.chipWidth, height: 30)
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
        let cardW = W - 28
        let contentH = contentHeight(forWidth: cardW)
        let cardH = 42 + 28 + 32 + contentH + 20
        let totalH = cardH + belowCardHeight
        let scrollContentH = max(H, 28 + totalH + 28)
        contentView.frame = CGRect(x: 0, y: 0, width: W, height: scrollContentH)
        scrollView.contentSize = contentView.frame.size
        let cardY = totalH < H ? (H - totalH) / 2 : 28
        cardView.frame = CGRect(x: 14, y: cardY, width: cardW, height: cardH)
        titleLabel.frame = CGRect(x: 24, y: 42, width: cardW - 48, height: 28)
        layoutContent(originY: 42 + 28 + 32, width: cardW)
        if belowCardHeight > 0 {
            layoutBelowCard(top: cardY + cardH, width: W)
        }
        closeButton.frame = CGRect(x: W - 14 - 38, y: view.safeAreaInsets.top + 2,
                                   width: 38, height: 38)
        closeButton.isHidden = onClose == nil
    }

    func relayout(animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState]) {
                self.view.layoutIfNeeded()
            }
        } else {
            view.setNeedsLayout()
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

    override func viewDidLoad() {
        pageTitle = "注册或登录账户"
        super.viewDidLoad()
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
        // Signup form
        let (emailF, emailChip) = makeEmailField()
        suEmail = emailF; suChip = emailChip
        let (codeF, codeBtn) = makeCodeField(target: self, action: #selector(getCodeTapped))
        suCode = codeF; suCodeButton = codeBtn
        suCountdown = CodeCountdown(button: codeBtn)
        let (passF, passEye) = makePasswordField(
            placeholder: "设置密码", hint: "至少 8 个字符，需含大写和小写字母各 1 个。")
        suPass = passF; suPassEye = passEye
        suPass.input.textContentType = .newPassword
        suPass.marginBottom = 7
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

    override var belowCardHeight: CGFloat { 28 + 26 }

    override func layoutBelowCard(top: CGFloat, width: CGFloat) {
        brandView.frame = CGRect(x: 0, y: top + 28, width: width, height: 26)
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
        var y: CGFloat = 22
        for field in fields {
            y += field.layout(width: width) + field.marginBottom
        }
        if form === signupForm {
            y += 48 + 16 + 21
        } else {
            y += 48 + 20 + 21
        }
        return y + 22
    }

    override func contentHeight(forWidth width: CGFloat) -> CGFloat {
        let panelW = width - 40
        let formW = panelW - 32
        if activeTab == 0 {
            let fields = [suEmail, suCode, suPass, suConfirm, suKey].compactMap { $0 }
            return 54 + formContentHeight(signupForm, fields: fields, width: formW)
        }
        let fields = [liEmail, liPass].compactMap { $0 }
        return 54 + formContentHeight(loginForm, fields: fields, width: formW)
    }

    override func layoutContent(originY: CGFloat, width: CGFloat) {
        let panelW = width - 40
        let formW = panelW - 32
        let panelH = contentHeight(forWidth: width)
        panelView.frame = CGRect(x: 20, y: originY, width: panelW, height: panelH)
        whitePanel.frame = panelView.bounds
        whitePanel.setHeight(panelH)
        signupTabButton.frame = CGRect(x: 0, y: 0, width: panelW / 2, height: 54)
        loginTabButton.frame = CGRect(x: panelW / 2, y: 0, width: panelW / 2, height: 54)
        for form in [signupForm, loginForm] {
            form.frame = CGRect(x: 0, y: 54, width: panelW, height: panelH - 54)
        }
        layoutSignup(formW: formW)
        layoutLogin(formW: formW)
    }

    private func layoutSignup(formW: CGFloat) {
        var y: CGFloat = 22
        for field in [suEmail, suCode, suPass, suConfirm, suKey] {
            guard let field else { continue }
            field.view.frame = CGRect(x: 16, y: y, width: formW, height: 0)
            y += field.layout(width: formW) + field.marginBottom
        }
        layoutSuffixChip(suChip, fieldWidth: formW)
        layoutCodeButton(suCodeButton, in: suCode, fieldWidth: formW)
        layoutEyeButton(suPassEye, fieldWidth: formW)
        layoutEyeButton(suConfirmEye, fieldWidth: formW)
        suButton.frame = CGRect(x: 16, y: y, width: formW, height: 48)
        y += 48 + 16
        layoutAgreeRow(y: y, formW: formW)
    }

    private func layoutAgreeRow(y: CGFloat, formW: CGFloat) {
        agreeView.frame = CGRect(x: 16, y: y, width: formW, height: 21)
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
        agreeBox.frame = CGRect(x: x, y: 3, width: boxSize, height: boxSize)
        agreeCheck.frame = CGRect(x: 2, y: 2, width: 11, height: 11)
        x += boxSize + 6
        agreeLabel.frame = CGRect(x: x, y: 0, width: labelW, height: 21)
        x += labelW + 2
        agreeTermsButton.frame = CGRect(x: x, y: 0, width: termsW, height: 21)
        x += termsW + 2
        agreeAndLabel.frame = CGRect(x: x, y: 0, width: andW, height: 21)
        x += andW + 2
        agreePrivacyButton.frame = CGRect(x: x, y: 0, width: privacyW, height: 21)
    }

    private func layoutLogin(formW: CGFloat) {
        var y: CGFloat = 22
        for field in [liEmail, liPass] {
            guard let field else { continue }
            field.view.frame = CGRect(x: 16, y: y, width: formW, height: 0)
            y += field.layout(width: formW) + field.marginBottom
        }
        layoutSuffixChip(liChip, fieldWidth: formW)
        layoutEyeButton(liPassEye, fieldWidth: formW)
        liButton.frame = CGRect(x: 16, y: y, width: formW, height: 48)
        y += 48 + 20
        forgotButton.frame = CGRect(x: 16, y: y, width: formW, height: 21)
    }

    // MARK: Tabs

    @objc private func tabTapped(_ sender: UIButton) {
        setTab(sender.tag)
    }

    func setTab(_ index: Int) {
        guard index != activeTab else { return }
        activeTab = index
        whitePanel.slide(to: index)
        updateTabStyles()
        let incoming = index == 0 ? signupForm : loginForm
        let outgoing = index == 0 ? loginForm : signupForm
        clearErrors(of: outgoing)
        outgoing.isHidden = true
        incoming.isHidden = false
        incoming.alpha = 0
        incoming.transform = CGAffineTransform(translationX: 0, y: 7)
        UIView.animate(withDuration: 0.32, delay: 0.24,
                       options: [.curveEaseOut]) {
            incoming.alpha = 1
            incoming.transform = .identity
        }
        relayout(animated: true)
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
        let email = suEmail.text.trimmingCharacters(in: .whitespaces)
        if email.isEmpty { suEmail.setError("请输入邮箱地址。"); return }
        if !Self.emailValid(email) { suEmail.setError("邮箱格式不完整，请检查。"); return }
        suEmail.setError(nil)
        suCodeButton.isEnabled = false
        AccountAPI.post("send_code", ["email": email, "purpose": "register"]) { [weak self] result in
            guard let self else { return }
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
        let email = suEmail.text.trimmingCharacters(in: .whitespaces)
        var firstBad: UITextField?
        if email.isEmpty {
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
        suButton.setBusy("正在创建账户…")
        AccountAPI.post("register", [
            "email": email, "password": suPass.text, "code": code
        ]) { [weak self] result in
            guard let self else { return }
            switch AccountAPI.outcome(result) {
            case .ok:
                login(email: email, password: suPass.text,
                      button: suButton, restoreTitle: "创建账户",
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
        let email = liEmail.text.trimmingCharacters(in: .whitespaces)
        var firstBad: UITextField?
        if email.isEmpty {
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
        liButton.setBusy("正在登录…")
        login(email: email, password: liPass.text,
              button: liButton, restoreTitle: "登录",
              card: "", passwordField: liPass, emailField: liEmail)
    }

    /// The shared login call: success persists the token; a new device
    /// detours through the email-confirmation wait page; a ban opens
    /// the blocking ban page; errors land on the relevant field.
    func login(email: String, password: String, button: DarkButton,
               restoreTitle: String, card: String,
               passwordField: FormField, emailField: FormField) {
        AccountAPI.post("login", [
            "email": email, "password": password,
            "device_id": AccountSession.deviceID
        ]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                button.restore(title: restoreTitle)
                emailField.setError("网络异常，请稍后再试")
            case .success(let json):
                if (json["ok"] as? Bool) == true, let token = json["token"] as? String {
                    completeAuth(token: token, email: email, card: card, button: button)
                } else if (json["ok"] as? Bool) == true, json["need_confirm"] as? Bool == true {
                    button.restore(title: restoreTitle)
                    presentConfirmWait(email: email, card: card, button: button)
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

    func presentConfirmWait(email: String, card: String, button: DarkButton) {
        let wait = ConfirmWaitViewController(email: email)
        wait.onClose = { [weak self, weak wait] in
            self?.dismiss(animated: true)
            _ = wait
        }
        wait.onConfirmed = { [weak self, weak wait] token in
            guard let self else { return }
            wait?.dismiss(animated: true) {
                self.completeAuth(token: token, email: email, card: card, button: button)
            }
        }
        presentAux(wait)
    }

    func presentBanned(title: String, subtitle: String, reason: String) {
        let banned = BannedViewController(
            banTitle: title, banSubtitle: subtitle, banReason: reason,
            buttonTitle: "返回")
        banned.onButton = { [weak self] in self?.dismiss(animated: true) }
        presentAux(banned)
    }

    @objc func forgotTapped() {
        let reset = ResetPasswordViewController()
        reset.onClose = { [weak self] in self?.dismiss(animated: true) }
        reset.onResetSuccess = { [weak self] email in
            guard let self else { return }
            dismiss(animated: true) {
                self.setTab(1)
                self.liEmail.input.text = email
                self.liEmail.setError(nil)
                self.liPass.input.becomeFirstResponder()
            }
        }
        presentAux(reset)
    }
}

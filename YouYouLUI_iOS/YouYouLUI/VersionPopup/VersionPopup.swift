import UIKit
import CoreImage

// MARK: - Feed check

/// Native 1:1 restoration of the user's two version popups (HTML designs in
/// luiyoaccount/popup-design: fig1 = blue-purple 弹更新 / soft, fig2 =
/// red-orange 禁用 / banned).
///
/// Every visual value — geometry, gradient stops and angles, colors (light
/// and dark), type sizes/weights, shadows, the glyph artwork itself (the
/// designs' SVGs, pre-rendered offline into PNG assets at their fully
/// drawn resting state), and the entrance choreography (jellyIn /
/// riseIn / fadeUp keyframes, with the designs' own delays, durations
/// and timing functions; Build 15 compresses all entrance times
/// x 0.7 — see beginEntrance) — is taken from the two HTML files and
/// scaled by s = min(screenW / 1080, screenH / 1918), exactly like the
/// designs' own fit() function.
///
/// Once per launch this reads the static feed `updates/latest.json` and
/// looks up `version_states["<own build>"]`:
///   - soft   → the blue-purple popup （取消 dismisses, 更新 opens the
///              latest IPA's download URL in Safari)
///   - banned → the red-orange popup, not dismissible （退出 exits the app,
///              联系客服 is wired but has no destination yet — no-op)
/// The fetch starts immediately at launch, but presentation is gated:
/// the popup is presented only once the app is `.active` AND the home
/// shell has completed its first appearance. If the answer arrives
/// before the gate opens, the payload is held and presented the moment
/// both conditions hold (re-checked on `didBecomeActive` and on the
/// shell's first `viewDidAppear`). Fail-open: any network/parse
/// failure = no popup.
///
/// Build 13 architecture (the Builds 11/12 mechanisms each failed on
/// device, so the architecture changed instead of the parameters):
/// 1. The popup is presented INSIDE the app's main window — a child
///    view controller of the window's root controller, its view
///    covering the shell — never in a separate overlay UIWindow.
/// 2. All artwork is pre-rendered offline from the designs at
///    design-space @3x and shipped as PNG assets (card background,
///    icon-card glass, primary-button gradient). Nothing is baked at
///    runtime except the gradient title (dynamic server text; that
///    bake demonstrably draws — it was visible even in the ghost
///    renders).
enum VersionPopup {
    private static let feedURL = URL(string: "https://luioe.bbroot.com/updates/latest.json")!
    private static var didCheck = false
    private static var popupController: VersionPopupViewController?
    private static var pendingPayload: Payload?
    private static var hostWindowRef: UIWindow?
    private static var homeAppeared = false
    private static var activeObserver: NSObjectProtocol?

    struct Payload {
        let banned: Bool
        let title: String
        let l2: String
        let l3: String
        let downloadURL: URL?
    }

    static func checkIfNeeded(hostWindow: UIWindow) {
        guard !didCheck else { return }
        didCheck = true
        hostWindowRef = hostWindow
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main) { _ in
                tryPresent()
            }
        }
        fetch { payload in
            guard let payload else { return }
            pendingPayload = payload
            tryPresent()
        }
    }

    /// Called by the main shell on every `viewDidAppear`; only the
    /// first appearance matters (the gate opens once per launch, and
    /// any held payload is presented then if the app is active).
    static func noteHomeShellDidAppear() {
        homeAppeared = true
        tryPresent()
    }

    private static func tryPresent() {
        guard popupController == nil,
              let payload = pendingPayload,
              homeAppeared,
              UIApplication.shared.applicationState == .active,
              let hostWindow = hostWindowRef else { return }
        pendingPayload = nil
        present(payload, hostWindow: hostWindow)
    }

    private static func fetch(completion: @escaping (Payload?) -> Void) {
        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, _, _ in
            var payload: Payload?
            if let data,
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                payload = parse(json)
            }
            DispatchQueue.main.async { completion(payload) }
        }.resume()
    }

    private static func parse(_ json: [String: Any]) -> Payload? {
        let ownBuild = AppConfiguration.buildNumber
        guard !ownBuild.isEmpty,
              let states = json["version_states"] as? [String: Any],
              let entry = states[ownBuild] as? [String: Any],
              let state = entry["state"] as? String,
              state == "soft" || state == "banned" else { return nil }
        var downloadURL: URL?
        if let assets = json["assets"] as? [[String: Any]],
           let raw = assets.first?["browser_download_url"] as? String {
            downloadURL = URL(string: raw)
        }
        return Payload(
            banned: state == "banned",
            title: entry["title"] as? String ?? "",
            l2: entry["l2"] as? String ?? "",
            l3: entry["l3"] as? String ?? "",
            downloadURL: downloadURL
        )
    }

    /// Build 13: the popup is hosted in the app's MAIN window — the
    /// popup controller becomes a child of the window's root view
    /// controller and its view covers the whole window, above the
    /// shell. No separate overlay window (Builds 8–12 presented in a
    /// dedicated UIWindow; on device that window's contents were the
    /// first-appearance ghosts). Appearance traits (interface style
    /// included) inherit from the host window through the root
    /// controller, as they did via the old window copy.
    private static func present(_ payload: Payload, hostWindow: UIWindow) {
        guard let root = hostWindow.rootViewController else { return }
        let controller = VersionPopupViewController(payload: payload)
        controller.onDismiss = { dismiss() }
        popupController = controller
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        controller.view.layoutIfNeeded()
        controller.beginEntrance()
    }

    private static func dismiss() {
        guard let controller = popupController else { return }
        popupController = nil
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
    }
}

// MARK: - Palette (all values from the designs' CSS, incl. dark variants)

private func vpHex(_ string: String, _ alpha: CGFloat = 1) -> UIColor {
    (ColorHex.parse(string) ?? .white).withAlphaComponent(alpha)
}

private func vpRGBA(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> UIColor {
    UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

private struct PopupPalette {
    /// Runtime colors only: the card background, icon-card glass and
    /// primary-button gradient are pre-rendered assets since Build 13;
    /// what remains is text/button chrome colors and layer shadows.
    let brandShadow: UIColor
    /// (color, location) stops of line 1's 90deg text gradient.
    let titleStops: [(UIColor, CGFloat)]
    /// Dark mode: the svg drop-shadow color.
    let glyphShadow: UIColor
    let subText: UIColor
    let cancelBackground: UIColor
    let cancelBorder: UIColor
    let cancelText: UIColor
    /// Modal box-shadows: 0 30px 66px and 0 10px 22px.
    let outerShadow: UIColor
    let innerShadow: UIColor
    let iconCardShadow: UIColor

    static func make(banned: Bool, dark: Bool) -> PopupPalette {
        let brand: [UIColor] = banned
            ? [vpHex("#ff8a3d"), vpHex("#ff5b5b"), vpHex("#ff3d3d")]
            : [vpHex("#8a7bff"), vpHex("#3d8bff"), vpHex("#49c6fd")]
        if dark {
            return PopupPalette(
                brandShadow: banned ? vpRGBA(230, 90, 90, 0.32) : vpRGBA(80, 120, 230, 0.32),
                titleStops: banned
                    ? [(vpHex("#ffd7c2"), 0), (vpHex("#ffaf9f"), 0.52), (vpHex("#ff9a97"), 1)]
                    : [(vpHex("#ded7ff"), 0), (vpHex("#9fcaff"), 0.52), (vpHex("#97e2ff"), 1)],
                glyphShadow: banned ? vpRGBA(255, 150, 110, 0.38) : vpRGBA(130, 160, 255, 0.38),
                subText: vpHex("#9d9da3"),
                cancelBackground: vpHex("#3a3a40"),
                cancelBorder: vpHex("#4a4a52"),
                cancelText: vpHex("#f2f2f4"),
                outerShadow: vpRGBA(0, 0, 0, 0.55),
                innerShadow: vpRGBA(0, 0, 0, 0.40),
                iconCardShadow: vpRGBA(0, 0, 0, 0.34)
            )
        }
        return PopupPalette(
            brandShadow: banned ? vpRGBA(230, 90, 90, 0.32) : vpRGBA(80, 120, 230, 0.32),
            titleStops: [(brand[0], 0), (brand[1], 0.52), (brand[2], 1)],
            glyphShadow: vpRGBA(130, 160, 255, 0),
            subText: vpHex("#afb1b2"),
            cancelBackground: vpHex("#ffffff"),
            cancelBorder: vpHex("#dedede"),
            cancelText: vpHex("#111111"),
            outerShadow: vpRGBA(120, 130, 150, 0.20),
            innerShadow: vpRGBA(120, 130, 150, 0.12),
            iconCardShadow: vpRGBA(110, 145, 190, 0.14)
        )
    }
}

// MARK: - Gradient title (line 1): text baked into an image with the
// design's 90deg gradient. Two passes, both inside UIGraphicsImageRenderer
// (top-left origin by construction):
//   1. the text drawn solid via NSString — the mask;
//   2. the gradient painted by a CAGradientLayer, then cut to the glyphs
//      by drawing the mask back with .destinationIn.
// UIImage compositing can never mirror the text — the Build 9 approach
// (CGContext clip-to-mask in a raw bitmap context) flipped it on device.
// No CGBitmapContext, no CTLine, no transform flips anywhere in this file's
// title path.

private enum TitleRenderer {
    static func image(text: String, font: UIFont,
                      stops: [(UIColor, CGFloat)],
                      trait: UITraitCollection) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let canvas = CGSize(width: ceil(textSize.width), height: ceil(font.lineHeight))
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = trait.displayScale
        format.opaque = false
        let rect = CGRect(origin: .zero, size: canvas)
        // Pass 1 — the mask: the string drawn solid white.
        let mask = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            (text as NSString).draw(in: rect, withAttributes: [
                .font: font,
                .foregroundColor: UIColor.white
            ])
        }
        // Pass 2 — gradient fill, cut to the mask via destination-in.
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = rect
        gradientLayer.colors = stops.map { $0.0.resolvedColor(with: trait).cgColor }
        gradientLayer.locations = stops.map { NSNumber(value: Double($0.1)) }
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            gradientLayer.render(in: context.cgContext)
            mask.draw(in: rect, blendMode: .destinationIn, alpha: 1)
        }
    }
}

// MARK: - Popup view controller
// Geometry (design px, relative to the 835 × 728 modal):
//   hero band height 335 · icon cards 145 × 145 at (295, 84) and (416, 84),
//   radius 44, tilted -8° / +6° · glyph svg box = 47% of the card
//   texts at left 56, line boxes (27 tall, line-height 1) at tops
//   406 / 467 / 516 · buttons top 589, height 90, radius 45:
//   left at 48 w 355, right at 430 w 378 · modal radius 88.

private final class IconCard {
    let wrap = UIView()       // riseIn target (opacity / translateY / blur)
    let card = UIView()       // resting tilt + design box-shadow
    let clip = UIView()       // rounded glass clipping
    /// Pre-rendered frosted-glass background (a shipped PNG asset):
    /// the artwork under the card, blurred + tinted + highlighted
    /// offline with the design's composite formula — never a live
    /// effect view (its material tint stacking made the cards milky
    /// in Build 10, and a live effect view's backdrop failed to
    /// appear in Build 11's ghost render) and never a runtime bake
    /// (Build 12's runtime-baked images ghosted exactly the same way).
    let glass = UIImageView()
    let glyph = UIImageView()
    /// Live draw-on mask over the glyph image (the designs' .drw strokes).
    let glyphMask = CALayer()
    var strokeLayers: [CAShapeLayer] = []
    var strokeSpecs: [GlyphStroke] = []
}

final class VersionPopupViewController: UIViewController {
    var onDismiss: (() -> Void)?

    private let payload: VersionPopup.Payload
    private var palette: PopupPalette
    private var dark = false
    /// Design px → points, as in the designs' fit(): min(vw/1080, vh/1918).
    private var s: CGFloat = 0.36

    private let scrimView = UIView()
    private let shadowOuter = UIView()
    private let shadowInner = UIView()
    private let cardView = UIView()
    private let bgImageView = UIImageView()
    private let cardL = IconCard()
    private let cardR = IconCard()
    private let titleView = UIImageView()
    private let line2 = UILabel()
    private let line3 = UILabel()
    private let leftButton = UIButton(type: .custom)
    private let rightButton = UIButton(type: .custom)

    private var scaledConstraints: [(NSLayoutConstraint, CGFloat)] = []
    private var titleTop: NSLayoutConstraint!
    private var titleWidth: NSLayoutConstraint!
    private var titleHeight: NSLayoutConstraint!
    private var line2Top: NSLayoutConstraint!
    private var line3Top: NSLayoutConstraint!
    private var line2Height: NSLayoutConstraint!
    private var line3Height: NSLayoutConstraint!

    private var entranceBegan = false
    private var entranceStart: CFTimeInterval = 0

    init(payload: VersionPopup.Payload) {
        self.payload = payload
        self.palette = PopupPalette.make(banned: payload.banned, dark: false)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Build

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dark = traitCollection.userInterfaceStyle == .dark

        shadowInner.addSubview(cardView)
        shadowOuter.addSubview(shadowInner)
        // Backdrop: a plain black scrim at alpha 0.15 (measured against
        // the user's design videos — the feed behind stays light, mildly
        // dimmed). No blur, no white layer anywhere behind the card.
        scrimView.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        view.addSubview(scrimView)
        view.addSubview(shadowOuter)
        cardView.clipsToBounds = true
        cardView.addSubview(bgImageView)

        for icon in [cardL, cardR] {
            icon.clip.addSubview(icon.glass)
            icon.clip.clipsToBounds = true
            icon.card.addSubview(icon.clip)
            icon.card.addSubview(icon.glyph)
            icon.wrap.addSubview(icon.card)
            cardView.addSubview(icon.wrap)
            pinEdges(icon.glass, to: icon.clip)
            pinEdges(icon.clip, to: icon.card)
            pinEdges(icon.card, to: icon.wrap)
            icon.glyph.translatesAutoresizingMaskIntoConstraints = false
            activate(icon.glyph.centerXAnchor.constraint(equalTo: icon.card.centerXAnchor))
            activate(icon.glyph.centerYAnchor.constraint(equalTo: icon.card.centerYAnchor))
            pin(icon.glyph.widthAnchor.constraint(equalToConstant: 0), px: 68.15)
            pin(icon.glyph.heightAnchor.constraint(equalToConstant: 0), px: 68.15)
            icon.glyph.layer.shadowOffset = .zero
            if let filter = makeRiseBlurFilter() {
                icon.wrap.layer.filters = [filter]
            }
        }
        // Design stacking: the left card (z-index 4) sits OVER the
        // right (z-index 3) in their 24px overlap strip. The loop
        // above added left first (right on top) — restore the
        // design's order. (Build 18; the left glass is also baked
        // refracting the right card beneath it, as the browser's
        // backdrop-filter does.)
        cardView.bringSubviewToFront(cardL.wrap)
        cardL.card.transform = CGAffineTransform(rotationAngle: -8 * .pi / 180)
        cardR.card.transform = CGAffineTransform(rotationAngle: 6 * .pi / 180)
        setupDrawMask(for: cardL, specs: GlyphDraw.left)
        setupDrawMask(for: cardR, specs: GlyphDraw.right)

        line2.text = payload.l2
        line3.text = payload.l3
        for label in [line2, line3] {
            label.numberOfLines = 1
            label.lineBreakMode = .byClipping
            cardView.addSubview(label)
        }
        cardView.addSubview(titleView)

        leftButton.setTitle(payload.banned ? "退出" : "取消", for: .normal)
        rightButton.setTitle(payload.banned ? "联系客服" : "更新", for: .normal)
        rightButton.setTitleColor(.white, for: .normal)
        // The primary button's 135deg brand gradient is a pre-rendered
        // pill-shaped PNG asset (Build 13) — no CAGradientLayer, whose
        // contents were among the first-appearance ghosts.
        rightButton.setBackgroundImage(
            UIImage(named: payload.banned ? "PopupButtonBanned" : "PopupButtonSoft"),
            for: .normal)
        for button in [leftButton, rightButton] {
            button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(buttonTouchUp(_:)),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
            cardView.addSubview(button)
        }
        leftButton.addTarget(self, action: #selector(leftTapped), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(rightTapped), for: .touchUpInside)

        buildConstraints()
        applyPalette()
    }

    private func activate(_ constraint: NSLayoutConstraint) {
        constraint.isActive = true
    }

    /// A constraint whose constant is a design-px value (scaled by s).
    private func pin(_ constraint: NSLayoutConstraint, px: CGFloat) {
        constraint.constant = px * s
        scaledConstraints.append((constraint, px))
        constraint.isActive = true
    }

    private func pinEdges(_ sub: UIView, to parent: UIView) {
        sub.translatesAutoresizingMaskIntoConstraints = false
        activate(sub.leftAnchor.constraint(equalTo: parent.leftAnchor))
        activate(sub.rightAnchor.constraint(equalTo: parent.rightAnchor))
        activate(sub.topAnchor.constraint(equalTo: parent.topAnchor))
        activate(sub.bottomAnchor.constraint(equalTo: parent.bottomAnchor))
    }

    private func buildConstraints() {
        for v in [scrimView, shadowOuter, shadowInner, cardView, bgImageView,
                  titleView, line2, line3, leftButton, rightButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        pinEdges(scrimView, to: view)
        activate(shadowOuter.centerXAnchor.constraint(equalTo: view.centerXAnchor))
        activate(shadowOuter.centerYAnchor.constraint(equalTo: view.centerYAnchor))
        pin(shadowOuter.widthAnchor.constraint(equalToConstant: 0), px: 835)
        pin(shadowOuter.heightAnchor.constraint(equalToConstant: 0), px: 728)
        pinEdges(shadowInner, to: shadowOuter)
        pinEdges(cardView, to: shadowInner)
        pinEdges(bgImageView, to: cardView)

        for (icon, left) in [(cardL, 295.0), (cardR, 416.0)] {
            icon.wrap.translatesAutoresizingMaskIntoConstraints = false
            pin(icon.wrap.leftAnchor.constraint(equalTo: cardView.leftAnchor), px: CGFloat(left))
            pin(icon.wrap.topAnchor.constraint(equalTo: cardView.topAnchor), px: 84)
            pin(icon.wrap.widthAnchor.constraint(equalToConstant: 0), px: 145)
            pin(icon.wrap.heightAnchor.constraint(equalToConstant: 0), px: 145)
        }

        pin(titleView.leftAnchor.constraint(equalTo: cardView.leftAnchor), px: 56)
        titleTop = titleView.topAnchor.constraint(equalTo: cardView.topAnchor)
        titleWidth = titleView.widthAnchor.constraint(equalToConstant: 0)
        titleHeight = titleView.heightAnchor.constraint(equalToConstant: 0)
        activate(titleTop)
        activate(titleWidth)
        activate(titleHeight)

        pin(line2.leftAnchor.constraint(equalTo: cardView.leftAnchor), px: 56)
        pin(line2.widthAnchor.constraint(equalToConstant: 0), px: 779)
        line2Top = line2.topAnchor.constraint(equalTo: cardView.topAnchor)
        line2Height = line2.heightAnchor.constraint(equalToConstant: 0)
        activate(line2Top)
        activate(line2Height)
        pin(line3.leftAnchor.constraint(equalTo: cardView.leftAnchor), px: 56)
        pin(line3.widthAnchor.constraint(equalToConstant: 0), px: 779)
        line3Top = line3.topAnchor.constraint(equalTo: cardView.topAnchor)
        line3Height = line3.heightAnchor.constraint(equalToConstant: 0)
        activate(line3Top)
        activate(line3Height)

        pin(leftButton.leftAnchor.constraint(equalTo: cardView.leftAnchor), px: 48)
        pin(leftButton.topAnchor.constraint(equalTo: cardView.topAnchor), px: 589)
        pin(leftButton.widthAnchor.constraint(equalToConstant: 0), px: 355)
        pin(leftButton.heightAnchor.constraint(equalToConstant: 0), px: 90)
        pin(rightButton.leftAnchor.constraint(equalTo: cardView.leftAnchor), px: 430)
        pin(rightButton.topAnchor.constraint(equalTo: cardView.topAnchor), px: 589)
        pin(rightButton.widthAnchor.constraint(equalToConstant: 0), px: 378)
        pin(rightButton.heightAnchor.constraint(equalToConstant: 0), px: 90)
    }

    private func makeRiseBlurFilter() -> CIFilter? {
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.name = "gaussianBlur"
        filter.setValue(0, forKey: kCIInputRadiusKey)
        return filter
    }

    /// Builds the glyph's draw-on mask: one CAShapeLayer per .drw stroke
    /// from the designs' SVGs — the mask centerlines for the filled parts,
    /// the elements' own geometry for the stroked circles — each with the
    /// design's stroke width, butt caps and miter joins (the SVG
    /// defaults), in 200-unit space. updateLayout scales the layers onto
    /// the laid-out glyph; beginEntrance sweeps strokeEnd per stroke.
    /// The artwork itself stays the shipped PNG — the mask is a live
    /// layer, nothing is baked or composed at runtime.
    private func setupDrawMask(for icon: IconCard, specs: [GlyphStroke]) {
        icon.strokeSpecs = specs
        for spec in specs {
            let shape = CAShapeLayer()
            shape.path = drawPath(spec)
            shape.fillColor = nil
            shape.strokeColor = UIColor.white.cgColor
            shape.lineWidth = spec.width
            shape.lineCap = .butt
            shape.lineJoin = .miter
            shape.miterLimit = 4
            shape.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
            shape.anchorPoint = .zero
            shape.position = .zero
            icon.glyphMask.addSublayer(shape)
            icon.strokeLayers.append(shape)
        }
        icon.glyph.layer.mask = icon.glyphMask
    }

    private func drawPath(_ spec: GlyphStroke) -> CGPath {
        let path = CGMutablePath()
        if let circle = spec.circle {
            // SVG circle strokes start at 3 o'clock and sweep clockwise
            // (y-down); a UIKit arc from angle 0, clockwise, is the same.
            path.addArc(center: CGPoint(x: circle.cx, y: circle.cy),
                        radius: circle.r, startAngle: 0,
                        endAngle: .pi * 2, clockwise: true)
        } else {
            let points = spec.points
            guard points.count >= 4 else { return path }
            path.move(to: CGPoint(x: points[0], y: points[1]))
            var i = 2
            while i + 1 < points.count {
                path.addLine(to: CGPoint(x: points[i], y: points[i + 1]))
                i += 2
            }
        }
        return path
    }

    // MARK: Palette application

    private func applyPalette() {
        palette = PopupPalette.make(banned: payload.banned, dark: dark)
        let trait = traitCollection
        shadowOuter.layer.shadowColor = palette.outerShadow.resolvedColor(with: trait).cgColor
        shadowOuter.layer.shadowOpacity = 1
        shadowInner.layer.shadowColor = palette.innerShadow.resolvedColor(with: trait).cgColor
        shadowInner.layer.shadowOpacity = 1
        line2.textColor = palette.subText
        line3.textColor = palette.subText
        leftButton.backgroundColor = palette.cancelBackground
        leftButton.layer.borderColor = palette.cancelBorder.resolvedColor(with: trait).cgColor
        leftButton.setTitleColor(palette.cancelText, for: .normal)
        rightButton.layer.shadowColor = palette.brandShadow.resolvedColor(with: trait).cgColor
        rightButton.layer.shadowOpacity = 1
        // All artwork is pre-rendered offline and shipped as assets;
        // the catalog resolves each image's light/dark appearance
        // variant automatically, so these assignments depend only on
        // the variant (soft/banned), never on the trait.
        bgImageView.image = UIImage(named: payload.banned ? "PopupCardBanned" : "PopupCardSoft")
        let glassFamily = payload.banned ? "PopupGlassBanned" : "PopupGlassSoft"
        cardL.glass.image = UIImage(named: glassFamily + "Left")
        cardR.glass.image = UIImage(named: glassFamily + "Right")
        updateGlyphImages()
        for icon in [cardL, cardR] {
            icon.card.layer.shadowColor = palette.iconCardShadow.resolvedColor(with: trait).cgColor
            icon.card.layer.shadowOpacity = 1
            icon.glyph.layer.shadowColor = palette.glyphShadow.resolvedColor(with: trait).cgColor
            icon.glyph.layer.shadowOpacity = dark ? 1 : 0
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let nowDark = traitCollection.userInterfaceStyle == .dark
        if nowDark != dark {
            dark = nowDark
            applyPalette()
            updateLayout()
        }
    }

    // MARK: Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout()
    }

    private func updateLayout() {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        s = min(bounds.width / 1080, bounds.height / 1918)
        for (constraint, px) in scaledConstraints {
            constraint.constant = px * s
        }
        cardView.layer.cornerRadius = 88 * s
        shadowOuter.layer.shadowOffset = CGSize(width: 0, height: 30 * s)
        shadowOuter.layer.shadowRadius = 33 * s
        shadowOuter.layer.shadowPath = UIBezierPath(
            roundedRect: shadowOuter.bounds, cornerRadius: 88 * s).cgPath
        shadowInner.layer.shadowOffset = CGSize(width: 0, height: 10 * s)
        shadowInner.layer.shadowRadius = 11 * s
        shadowInner.layer.shadowPath = UIBezierPath(
            roundedRect: shadowInner.bounds, cornerRadius: 88 * s).cgPath
        for icon in [cardL, cardR] {
            icon.card.layer.shadowOffset = CGSize(width: 0, height: 15 * s)
            icon.card.layer.shadowRadius = 15 * s
            icon.card.layer.shadowPath = UIBezierPath(
                roundedRect: icon.card.bounds, cornerRadius: 44 * s).cgPath
            icon.clip.layer.cornerRadius = 44 * s
            icon.glyph.layer.shadowRadius = 2.5 * s
            // The draw-on mask tracks the glyph's laid-out size.
            let glyphBounds = icon.glyph.bounds
            if glyphBounds.width > 0 {
                icon.glyphMask.frame = glyphBounds
                let k = glyphBounds.width / 200
                for shape in icon.strokeLayers {
                    shape.transform = CATransform3DMakeScale(k, k, 1)
                }
            }
        }
        // Design type: texts 27px (line 1 semibold, lines 2-3 regular),
        // buttons 30px (cancel medium, primary semibold).
        let textFont = UIFont.systemFont(ofSize: 27 * s)
        line2.font = textFont
        line3.font = textFont
        leftButton.titleLabel?.font = .systemFont(ofSize: 30 * s, weight: .medium)
        rightButton.titleLabel?.font = .systemFont(ofSize: 30 * s, weight: .semibold)
        // Each text line box is 27 design px tall (line-height: 1); center
        // the font's own line box on the design line box.
        setConstant(line2Top, (467 + 13.5) * s - textFont.lineHeight / 2)
        setConstant(line3Top, (516 + 13.5) * s - textFont.lineHeight / 2)
        setConstant(line2Height, textFont.lineHeight)
        setConstant(line3Height, textFont.lineHeight)
        // Buttons.
        leftButton.layer.cornerRadius = 45 * s
        leftButton.layer.borderWidth = 2 * s
        rightButton.layer.cornerRadius = 45 * s
        rightButton.layer.shadowOffset = CGSize(width: 0, height: 12 * s)
        rightButton.layer.shadowRadius = 13 * s
        rightButton.layer.shadowPath = UIBezierPath(
            roundedRect: rightButton.bounds, cornerRadius: 45 * s).cgPath
        renderTitle()
    }

    private func setConstant(_ constraint: NSLayoutConstraint, _ value: CGFloat) {
        if constraint.constant != value { constraint.constant = value }
    }

    private func renderTitle() {
        let font = UIFont.systemFont(ofSize: 27 * s, weight: .semibold)
        titleView.image = TitleRenderer.image(
            text: payload.title, font: font, stops: palette.titleStops, trait: traitCollection)
        if let image = titleView.image {
            titleView.isHidden = false
            setConstant(titleTop, (406 + 13.5) * s - image.size.height / 2)
            setConstant(titleWidth, image.size.width)
            setConstant(titleHeight, image.size.height)
        } else {
            titleView.isHidden = true
        }
    }

    /// The glyphs are pre-rendered PNG assets (the designs' SVGs at their
    /// fully drawn resting state; light/dark variants ship in the catalog
    /// and resolve automatically). The draw-on reveal is a live layer
    /// mask over the image — the artwork is never baked at runtime.
    private func updateGlyphImages() {
        let family = payload.banned ? "PopupGlyphBanned" : "PopupGlyphSoft"
        cardL.glyph.image = UIImage(named: family + "Left")
        cardR.glyph.image = UIImage(named: family + "Right")
    }

    // MARK: Entrance — the designs' choreography, time-compressed:
    // Build 15 (user: the verbatim timing felt slow; frame measurement
    // of the design video confirmed the implementation matched the
    // design, so every delay/duration below is the design value x 0.7,
    // ratios and timing functions unchanged; full settle 2.2s -> 1.54s):
    // jellyIn .665s cubic-bezier(.2,.9,.25,1.12) on the modal;
    // riseIn .665s cubic-bezier(.22,.85,.3,1), delays .098s / .189s, on
    // the icon cards (opacity 0→1, translateY 34px→0, blur 10px→0);
    // fadeUp .42s cubic-bezier(.22,.85,.3,1), delays .91s / 1.015s /
    // 1.12s, on the text lines (opacity 0→1, translateY 14px→0);
    // the glyphs draw on stroke by stroke over their PNGs (the designs'
    // .drw dashoffset sweep) via a live CAShapeLayer mask.

    func beginEntrance() {
        guard !entranceBegan else { return }
        entranceBegan = true
        entranceStart = CACurrentMediaTime()
        if UIAccessibility.isReduceMotionEnabled {
            // The designs' prefers-reduced-motion block: everything rests
            // (scrim at full alpha, glyph masks fully revealed).
            return
        }
        scrimView.alpha = 0
        UIView.animate(withDuration: 0.42, delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            self.scrimView.alpha = 1
        }
        let jellyTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.12)
        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = [0.9, 1.028, 0.992, 1.01, 1.0]
        scaleAnim.keyTimes = [0, 0.55, 0.72, 0.86, 1]
        scaleAnim.timingFunctions = [jellyTiming, jellyTiming, jellyTiming, jellyTiming]
        scaleAnim.duration = 0.665
        let fadeAnim = CAKeyframeAnimation(keyPath: "opacity")
        fadeAnim.values = [0, 1, 1]
        fadeAnim.keyTimes = [0, 0.55, 1]
        fadeAnim.timingFunctions = [jellyTiming, jellyTiming]
        fadeAnim.duration = 0.665
        shadowOuter.layer.add(scaleAnim, forKey: "jellyInScale")
        shadowOuter.layer.add(fadeAnim, forKey: "jellyInOpacity")

        let riseTiming = CAMediaTimingFunction(controlPoints: 0.22, 0.85, 0.3, 1)
        for (icon, delay) in [(cardL, 0.098), (cardR, 0.189)] {
            let group = CAAnimationGroup()
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0
            opacity.toValue = 1
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = 34 * s
            move.toValue = 0
            group.animations = [opacity, move]
            group.duration = 0.665
            group.beginTime = entranceStart + delay
            group.timingFunction = riseTiming
            group.fillMode = .backwards
            icon.wrap.layer.add(group, forKey: "riseIn")
            if let filters = icon.wrap.layer.filters, !filters.isEmpty {
                let blur = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
                blur.fromValue = 10 * s
                blur.toValue = 0
                blur.duration = 0.665
                blur.beginTime = entranceStart + delay
                blur.timingFunction = riseTiming
                blur.fillMode = .backwards
                icon.wrap.layer.add(blur, forKey: "riseInBlur")
            }
        }
        for (target, delay) in [(titleView as UIView, 0.91),
                                (line2 as UIView, 1.015),
                                (line3 as UIView, 1.12)] {
            let group = CAAnimationGroup()
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0
            opacity.toValue = 1
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = 14 * s
            move.toValue = 0
            group.animations = [opacity, move]
            group.duration = 0.42
            group.beginTime = entranceStart + delay
            group.timingFunction = riseTiming
            group.fillMode = .backwards
            target.layer.add(group, forKey: "fadeUp")
        }
        // Glyphs draw on stroke by stroke: each mask stroke sweeps
        // strokeEnd 0→1 with the design's own delay / duration / easing,
        // revealing the PNG along its centerline in the design's order.
        // (fillMode .backwards keeps each stroke hidden until its delay;
        // the model strokeEnd stays 1, so the resting art is exact.)
        let drawTiming = CAMediaTimingFunction(controlPoints: 0.35, 0.55, 0.35, 1)
        for icon in [cardL, cardR] {
            for (shape, spec) in zip(icon.strokeLayers, icon.strokeSpecs) {
                let draw = CABasicAnimation(keyPath: "strokeEnd")
                draw.fromValue = 0
                draw.toValue = 1
                draw.duration = spec.duration
                draw.beginTime = entranceStart + spec.delay
                draw.timingFunction = drawTiming
                draw.fillMode = .backwards
                shape.add(draw, forKey: "drawOn")
            }
        }
    }

    // MARK: Actions

    @objc private func buttonTouchDown(_ button: UIButton) {
        // .btn:active { transform: scale(.975) } with a .15s transition.
        UIView.animate(withDuration: 0.15) {
            button.transform = CGAffineTransform(scaleX: 0.975, y: 0.975)
        }
    }

    @objc private func buttonTouchUp(_ button: UIButton) {
        UIView.animate(withDuration: 0.15) { button.transform = .identity }
    }

    @objc private func leftTapped() {
        if payload.banned {
            // 退出：fade out, then terminate.
            UIView.animate(withDuration: 0.25, animations: { self.view.alpha = 0 }) { _ in
                exit(0)
            }
        } else {
            dismissPopup()
        }
    }

    @objc private func rightTapped() {
        if payload.banned {
            // 联系客服：no destination exists yet — intentionally a no-op
            // (button press feedback only). Wire a URL here once the user
            // provides one.
            return
        }
        if let url = payload.downloadURL {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        dismissPopup()
    }

    private func dismissPopup() {
        UIView.animate(withDuration: 0.25, animations: {
            self.scrimView.alpha = 0
            self.shadowOuter.alpha = 0
            self.shadowOuter.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }, completion: { _ in
            self.onDismiss?()
        })
    }
}

// MARK: - Glyph draw-on data (extracted verbatim from the designs' SVGs)
//
// Every visible glyph element in the two HTML designs is either a .drw
// element itself (the two gradient-stroked circles) or a filled path
// revealed by exactly one .drw mask path — there are no plain
// always-visible parts, so the union of these strokes, swept in the
// designs' order, reproduces the draw-on exactly and rests on the full
// artwork. Geometry and timing are byte-identical in fig1 and fig2
// (only the gradient palettes differ), so one table serves both
// variants. data-d / data-t are the designs' delay / duration, in
// seconds, compressed x 0.7 in Build 15 with the rest of the entrance
// (see beginEntrance); points are the mask centerlines in the SVGs'
// 200×200 space.

private struct GlyphStroke {
    /// Flattened [x, y, x, y, …] centerline; empty for a circle stroke.
    let points: [CGFloat]
    let circle: (cx: CGFloat, cy: CGFloat, r: CGFloat)?
    let width: CGFloat
    let delay: CFTimeInterval
    let duration: CFTimeInterval
}

private enum GlyphDraw {
    static let left: [GlyphStroke] = [
        .init(points: [], circle: (99.5, 45.34, 28.8), width: 11.93, delay: 0.175, duration: 0.266),
        .init(points: [94.5, 93.9, 85.8, 98.9, 84.8, 99.4, 83.6, 100.1, 82.3, 101, 80.7, 102, 79.4, 103, 78, 104, 76.6, 105, 75.3, 106, 73.6, 107, 71.2, 108, 68.5, 109, 65.6, 110, 62.6, 111, 59.5, 112, 56.4, 113, 53.4, 114, 51.1, 115, 49.2, 116, 47.4, 117, 45.8, 118, 44.2, 119, 42.8, 120, 41.4, 121, 40.1, 122, 38.9, 123, 37.8, 124, 36.6, 125, 35.6, 126, 34.5, 127, 33.5, 128, 32.6, 129, 31.7, 130, 30.9, 131, 30, 132, 29.2, 133, 28.4, 134, 27.8, 135, 27.1, 136, 26.3, 137, 25.6, 138, 25, 139, 24.4, 140, 23.9, 141, 23.3, 142, 22.8, 143, 22.4, 144, 21.9, 145, 21.4, 146, 20.9, 147, 20.6, 148, 20.1, 149, 19.7, 150, 19.4, 151, 19.1, 152, 18.7, 153, 18.4, 154, 18.1, 155, 17.9, 156, 17.7, 157, 17.5, 158, 17.2, 159, 17.1, 160, 16.9, 161, 16.8, 162, 16.6, 163, 16.6, 164, 16.4, 165, 16.4, 166, 16.4, 167, 16.4, 168, 16.3, 169, 16.3, 170, 16.3, 171, 16.4, 172, 16.4, 173, 16.3, 173.9, 16.2, 174.6, 16.2, 175.1, 16.2, 185.1], circle: nil, width: 28.8, delay: 0.364, duration: 0.336),
        .init(points: [152.1, 101.7, 153.7, 111.6, 153.8, 112.2, 153.9, 113, 154, 114, 154, 115, 154, 116, 154, 117, 154, 118, 154, 119, 154, 120, 154, 121, 154, 122, 154, 123, 154, 124, 154, 125, 154, 126, 154, 127, 154, 128, 153.9, 129, 153.8, 130, 153.6, 131, 153.3, 132, 152.8, 133, 152.2, 134, 151.4, 135, 150.5, 136, 149.5, 137, 148.5, 138, 147.5, 139, 146.5, 140, 145.5, 141, 144.5, 142, 143.5, 143, 142.5, 144, 141.5, 145, 140.5, 146, 139.5, 147, 138.5, 148, 137.5, 149, 136.5, 150, 135.5, 151, 134.5, 152, 133.5, 153, 132.5, 154, 131.6, 155, 130.7, 156, 129.9, 157, 129.2, 158, 128.6, 159, 128, 160, 127.5, 161, 127, 162, 126.5, 163, 126, 164, 125.5, 165, 125, 166, 124.5, 167, 124, 168, 123.5, 169, 123, 170, 122.5, 171, 122, 172, 121.6, 173, 121.2, 174, 120.8, 175, 120.5, 176, 120.3, 177, 120.2, 178, 120.2, 178.8, 120.3, 179.4, 121.9, 189.3], circle: nil, width: 49.1, delay: 0.616, duration: 0.28),
    ]
    static let right: [GlyphStroke] = [
        .init(points: [], circle: (99.5, 99.5, 82.99), width: 12.05, delay: 0.266, duration: 0.266),
        .init(points: [55, 93.1, 59.4, 86.4, 59.8, 85.8, 60.2, 85, 60.8, 84, 61.2, 83, 61.8, 82, 62.2, 81, 62.8, 80, 63.4, 79, 64, 78, 64.6, 77, 65.4, 76, 66.2, 75, 66.8, 74, 67.6, 73, 68.4, 72, 69.2, 71, 70, 70, 71, 69.2, 72, 68.4, 73, 67.6, 74, 66.8, 75, 66.2, 76, 65.4, 77, 64.6, 78, 64, 79, 63.4, 80, 62.8, 81, 62.2, 82, 61.8, 83, 61.4, 84, 61, 85, 60.6, 86, 60.4, 87, 60, 88, 59.6, 89, 59.4, 90, 59.2, 91, 59, 92, 59, 93, 59, 94, 58.8, 95, 58.6, 96, 58.4, 97, 58.2, 98, 58, 99, 58, 100, 58, 101, 58, 102, 58.2, 103, 58.4, 104, 58.6, 105, 58.8, 106, 59, 107, 59, 108, 59, 109, 59.2, 110, 59.4, 111, 59.6, 112, 60, 113, 60.4, 114, 60.6, 115, 61, 116, 61.4, 117, 61.8, 118, 62.2, 119, 62.8, 120, 63.2, 121, 63.8, 122, 64.4, 123, 65, 124, 65.6, 125, 66.2, 126, 66.6, 127, 66.8, 128, 67.2, 129, 67.4, 130, 67.6, 131, 68, 132, 68.4, 133, 68.8, 134, 69.2, 135, 69.8, 135.8, 70.4, 136.6, 71.2, 137.2, 72, 137.6, 73, 137.8, 74, 138, 75, 138.2, 76, 138.4, 77, 138.6, 78, 138.8, 79, 139, 80, 139, 81, 139, 81.8, 139, 82.4, 139, 90.4], circle: nil, width: 26, delay: 0.49, duration: 0.336),
        .init(points: [135.1, 75.7, 137, 70, 140, 61, 141.9, 55.3], circle: nil, width: 13.5, delay: 0.945, duration: 0.14),
        .init(points: [144, 104.9, 139.6, 111.6, 139.2, 112.2, 138.8, 113, 138.4, 114, 138, 115, 137.6, 116, 137.2, 117, 136.6, 118, 136, 119, 135.6, 120, 135, 121, 134.4, 122, 134, 123, 133.4, 124, 132.6, 125, 131.8, 126, 131, 127, 130, 128, 129, 129, 128, 130, 127, 131, 126, 131.8, 125, 132.6, 124, 133.4, 123, 134, 122, 134.4, 121, 135, 120, 135.6, 119, 136, 118, 136.6, 117, 137.2, 116, 137.6, 115, 138, 114, 138.4, 113, 138.6, 112, 138.8, 111, 139, 110, 139.2, 109, 139.4, 108, 139.6, 107, 139.8, 106, 140, 105, 140, 104, 140, 103, 140, 102, 140, 101, 140, 100, 140, 99, 140, 98, 140, 97, 140, 96, 140, 95, 140, 94, 140, 93, 140, 92, 139.8, 91, 139.6, 90, 139.4, 89, 139.2, 88, 139, 87, 138.8, 86, 138.6, 85, 138.4, 84, 138, 83, 137.6, 82, 137.2, 81, 136.6, 80, 136, 79, 135.4, 78, 134.8, 77, 134.2, 76, 133.6, 75, 133, 74, 132.6, 73, 132, 72, 131.6, 71, 131.4, 70, 131.2, 69, 130.8, 68, 130.6, 67, 130.2, 66, 129.8, 65, 129.4, 64, 129, 63, 128.4, 62.2, 127.8, 61.6, 127, 61, 126, 60.6, 125, 60.4, 124, 60.2, 123, 60, 122, 60, 121, 59.8, 120, 59.6, 119, 59.6, 118, 59.6, 117, 59.6, 116, 59.8, 115, 59.8, 114, 59.6, 113, 59.4, 112.2, 59.2, 111.6, 56.7, 104], circle: nil, width: 25.9, delay: 0.735, duration: 0.336),
        .init(points: [62.3, 122.1, 61, 128, 59, 137, 57.7, 142.9], circle: nil, width: 13.3, delay: 1.092, duration: 0.14),
    ]}

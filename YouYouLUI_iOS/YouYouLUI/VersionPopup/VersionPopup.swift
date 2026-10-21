import UIKit

// MARK: - Feed check

/// Native restoration of the user's two version popups (HTML designs in
/// luiyoaccount/popup-design: fig1 = blue-purple 弹更新 / soft, fig2 =
/// red-orange 禁用 / banned).
///
/// Once per launch, after the home UI is up, this reads the static feed
/// `updates/latest.json` and looks up `version_states["<own build>"]`:
///   - soft   → the blue-purple popup （取消 dismisses, 更新 opens the
///              latest IPA's download URL in Safari)
///   - banned → the red-orange popup, not dismissible （退出 exits the app,
///              联系客服 is wired but has no destination yet — no-op)
/// Fail-open by design: any network/parse failure means no popup.
enum VersionPopup {
    private static let feedURL = URL(string: "https://luioe.bbroot.com/updates/latest.json")!
    private static var didCheck = false
    private static var popupWindow: UIWindow?

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
        // Let the home UI settle before the popup can appear.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            fetch { payload in
                guard let payload else { return }
                present(payload, hostWindow: hostWindow)
            }
        }
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

    private static func present(_ payload: Payload, hostWindow: UIWindow) {
        guard let scene = hostWindow.windowScene else { return }
        let controller = VersionPopupViewController(payload: payload)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 10
        window.overrideUserInterfaceStyle = hostWindow.overrideUserInterfaceStyle
        window.backgroundColor = .clear
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        controller.onDismiss = { dismiss() }
        popupWindow = window
        window.layoutIfNeeded()
        controller.prepareEntrance()
        window.isHidden = false
        controller.playEntrance()
    }

    private static func dismiss() {
        popupWindow?.isHidden = true
        popupWindow = nil
    }
}

// MARK: - Gradient text (design line 1 renders its text in a 90° gradient)

final class GradientTextLabel: UIView {
    var text: String = "" { didSet { invalidateIntrinsicContentSize(); render() } }
    var font: UIFont = .systemFont(ofSize: 12) { didSet { invalidateIntrinsicContentSize(); render() } }
    var gradientColors: [UIColor] = [] { didSet { render() } }

    private let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        render()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        render()
    }

    private func render() {
        let size = bounds.size
        guard size.width > 1, size.height > 1, !text.isEmpty, gradientColors.count > 1 else {
            imageView.image = nil
            return
        }
        let colors = gradientColors.map { $0.resolvedColor(with: traitCollection) }
        let font = self.font
        let text = self.text
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map { $0.cgColor } as CFArray,
                locations: [0, 0.52, 1]
            )!
            cg.drawLinearGradient(gradient, start: CGPoint.zero,
                                  end: CGPoint(x: size.width, y: 0), options: [])
            cg.setBlendMode(.destinationIn)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let rect = CGRect(x: 0, y: (size.height - font.lineHeight) / 2,
                              width: size.width, height: font.lineHeight)
            (text as NSString).draw(in: rect, withAttributes: attributes)
        }
        imageView.image = image
    }
}

// MARK: - Popup view controller (design canvas 1080 × 1918, modal 835 × 728)

final class VersionPopupViewController: UIViewController {
    var onDismiss: (() -> Void)?

    private let payload: VersionPopup.Payload
    private var dark = false
    private var scale: CGFloat = 0.36

    // Card chrome
    private let shadowHost = UIView()
    private let cardView = UIView()
    private let baseGradient = CAGradientLayer()
    private let sheenLayer = CAGradientLayer()
    private let glowLayer = CAGradientLayer()
    // Hero band
    private let heroView = UIView()
    private let heroGradient = CAGradientLayer()
    private let heroGlow = CAGradientLayer()
    private let streakView = UIView()
    private let streakGradient = CAGradientLayer()
    // Icon cards
    private let iconCardL = UIView()
    private let iconCardR = UIView()
    private let glyphL = UIImageView()
    private let glyphRBox = UIView()
    private let ringGradient = CAGradientLayer()
    private let glyphR = UIImageView()
    // Texts + buttons
    private let line1 = GradientTextLabel()
    private let line2 = UILabel()
    private let line3 = UILabel()
    private let leftButton = UIButton(type: .custom)
    private let rightButton = UIButton(type: .custom)
    private let rightGradient = CAGradientLayer()

    init(payload: VersionPopup.Payload) {
        self.payload = payload
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Build

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dark = traitCollection.userInterfaceStyle == .dark

        shadowHost.addSubview(cardView)
        view.addSubview(shadowHost)
        cardView.clipsToBounds = true

        cardView.layer.addSublayer(baseGradient)
        cardView.layer.addSublayer(glowLayer)
        cardView.layer.addSublayer(sheenLayer)
        glowLayer.type = .radial
        sheenLayer.type = .radial

        heroView.clipsToBounds = true
        heroGradient.startPoint = CGPoint(x: 0.5, y: 0)
        heroGradient.endPoint = CGPoint(x: 0.5, y: 1)
        heroView.layer.addSublayer(heroGradient)
        heroGlow.type = .radial
        heroView.layer.addSublayer(heroGlow)
        streakGradient.colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(0.55).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        streakGradient.startPoint = CGPoint(x: 0, y: 0)
        streakGradient.endPoint = CGPoint(x: 1, y: 1)
        streakView.layer.addSublayer(streakGradient)
        heroView.addSubview(streakView)
        cardView.addSubview(heroView)

        configureIconCard(iconCardL)
        configureIconCard(iconCardR)
        glyphL.contentMode = .scaleAspectFit
        iconCardL.addSubview(glyphL)
        ringGradient.startPoint = CGPoint(x: 0.08, y: 0)
        ringGradient.endPoint = CGPoint(x: 0.92, y: 1)
        glyphRBox.layer.addSublayer(ringGradient)
        glyphR.contentMode = .scaleAspectFit
        glyphRBox.addSubview(glyphR)
        iconCardR.addSubview(glyphRBox)
        cardView.addSubview(iconCardL)
        cardView.addSubview(iconCardR)

        line2.numberOfLines = 1
        line3.numberOfLines = 2
        cardView.addSubview(line1)
        cardView.addSubview(line2)
        cardView.addSubview(line3)
        line1.text = payload.title
        line2.text = payload.l2
        line3.text = payload.l3

        leftButton.setTitle(payload.banned ? "退出" : "取消", for: .normal)
        rightButton.setTitle(payload.banned ? "联系客服" : "更新", for: .normal)
        for button in [leftButton, rightButton] {
            button.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(buttonTouchUp(_:)),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])
            cardView.addSubview(button)
        }
        leftButton.addTarget(self, action: #selector(leftTapped), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(rightTapped), for: .touchUpInside)
        rightButton.layer.insertSublayer(rightGradient, at: 0)
        rightButton.setTitleColor(.white, for: .normal)

        applyPalette()
    }

    private func configureIconCard(_ card: UIView) {
        let clip = UIView()
        clip.clipsToBounds = true
        clip.tag = 101
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.tag = 102
        let tint = UIView()
        tint.tag = 103
        clip.addSubview(blur)
        clip.addSubview(tint)
        card.addSubview(clip)
    }

    // MARK: Palette (from the designs' CSS, incl. dark-mode variants)

    private func hex(_ string: String, _ alpha: CGFloat = 1) -> UIColor {
        (ColorHex.parse(string) ?? .white).withAlphaComponent(alpha)
    }

    private struct Palette {
        let hero: [UIColor]
        let brand: [UIColor]
        let titleGradient: [UIColor]
        let icons: [UIColor]
        let glow: [UIColor]
        let base: [UIColor]
        let sheen: [UIColor]
        let subText: UIColor
        let cancelBackground: UIColor
        let cancelBorder: UIColor
        let cancelText: UIColor
        let primaryShadow: UIColor
        let cardShadow: UIColor
        let iconCardTint: UIColor
        let iconCardShadow: UIColor
    }

    private func palette(dark: Bool) -> Palette {
        if payload.banned {
            return Palette(
                hero: [hex("#ffb07a"), hex("#ff8a5b"), hex("#ff5b5b"),
                       hex("#ff5b5b", 0.45), hex("#ff5b5b", 0)],
                brand: [hex("#ff8a3d"), hex("#ff5b5b"), hex("#ff3d3d")],
                titleGradient: dark ? [hex("#ffd7c2"), hex("#ffaf9f"), hex("#ff9a97")]
                                    : [hex("#ff8a3d"), hex("#ff5b5b"), hex("#ff3d3d")],
                icons: dark ? [hex("#ff9d5c"), hex("#ff7d63"), hex("#ff5252")]
                            : [hex("#ff8a3d"), hex("#ff6a5b"), hex("#ff3d3d")],
                glow: [hex("#f07070", 0.34), hex("#f27e70", 0.19),
                       hex("#fa9454", 0.05), hex("#fdad49", 0)],
                base: dark ? [hex("#2b2b30"), hex("#222226")] : [hex("#ffffff"), hex("#ffffff")],
                sheen: dark ? [hex("#ffffff", 0.05), hex("#ffffff", 0)]
                            : [hex("#ffffff", 0.96), hex("#ffffff", 0)],
                subText: dark ? hex("#9d9da3") : hex("#afb1b2"),
                cancelBackground: dark ? hex("#3a3a40") : hex("#ffffff"),
                cancelBorder: dark ? hex("#4a4a52") : hex("#dedede"),
                cancelText: dark ? hex("#f2f2f4") : hex("#111111"),
                primaryShadow: hex("#e65a5a", 0.32),
                cardShadow: dark ? hex("#000000", 0.55) : hex("#788296", 0.20),
                iconCardTint: hex("#ffffff", dark ? 0.16 : 0.44),
                iconCardShadow: dark ? hex("#000000", 0.34) : hex("#6e91be", 0.14)
            )
        }
        return Palette(
            hero: [hex("#f9c0fc"), hex("#c9bdfa"), hex("#8fb4fb"),
                   hex("#8fb4fb", 0.45), hex("#8fb4fb", 0)],
            brand: [hex("#8a7bff"), hex("#3d8bff"), hex("#49c6fd")],
            titleGradient: dark ? [hex("#ded7ff"), hex("#9fcaff"), hex("#97e2ff")]
                                : [hex("#8a7bff"), hex("#3d8bff"), hex("#49c6fd")],
            icons: dark ? [hex("#bb86ff"), hex("#849dff"), hex("#4fb5ff")]
                        : [hex("#b07bf2"), hex("#6f8bf6"), hex("#49aefd")],
            glow: [hex("#8270f0", 0.34), hex("#707ef2", 0.19),
                   hex("#5494fa", 0.05), hex("#49aeFD", 0)],
            base: dark ? [hex("#2b2b30"), hex("#222226")] : [hex("#ffffff"), hex("#ffffff")],
            sheen: dark ? [hex("#ffffff", 0.05), hex("#ffffff", 0)]
                        : [hex("#ffffff", 0.96), hex("#ffffff", 0)],
            subText: dark ? hex("#9d9da3") : hex("#afb1b2"),
            cancelBackground: dark ? hex("#3a3a40") : hex("#ffffff"),
            cancelBorder: dark ? hex("#4a4a52") : hex("#dedede"),
            cancelText: dark ? hex("#f2f2f4") : hex("#111111"),
            primaryShadow: hex("#5078e6", 0.32),
            cardShadow: dark ? hex("#000000", 0.55) : hex("#788296", 0.20),
            iconCardTint: hex("#ffffff", dark ? 0.16 : 0.44),
            iconCardShadow: dark ? hex("#000000", 0.34) : hex("#6e91be", 0.14)
        )
    }

    private func applyPalette() {
        let p = palette(dark: dark)
        let trait = traitCollection
        func resolved(_ colors: [UIColor]) -> [CGColor] {
            colors.map { $0.resolvedColor(with: trait).cgColor }
        }
        baseGradient.colors = resolved(p.base)
        sheenLayer.colors = resolved(p.sheen)
        glowLayer.colors = resolved(p.glow)
        glowLayer.isHidden = !dark
        heroView.isHidden = dark
        heroGradient.colors = resolved(p.hero)
        heroGradient.locations = [0, 0.26, 0.48, 0.78, 0.98]
        heroGlow.colors = [
            UIColor.white.withAlphaComponent(0.88).cgColor,
            UIColor.white.withAlphaComponent(0.22).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        rightGradient.colors = resolved(p.brand)
        rightGradient.startPoint = CGPoint(x: 0, y: 0)
        rightGradient.endPoint = CGPoint(x: 1, y: 1)
        rightButton.layer.shadowColor = p.primaryShadow.resolvedColor(with: trait).cgColor
        shadowHost.layer.shadowColor = p.cardShadow.resolvedColor(with: trait).cgColor
        line1.gradientColors = p.titleGradient
        line2.textColor = p.subText
        line3.textColor = p.subText
        leftButton.backgroundColor = p.cancelBackground
        leftButton.layer.borderColor = p.cancelBorder.resolvedColor(with: trait).cgColor
        leftButton.setTitleColor(p.cancelText, for: .normal)
        for card in [iconCardL, iconCardR] {
            card.layer.shadowColor = p.iconCardShadow.resolvedColor(with: trait).cgColor
            card.viewWithTag(103)?.backgroundColor = p.iconCardTint
        }
        ringGradient.colors = resolved(p.icons)
        refreshGlyphs()
    }

    // MARK: Glyphs (the designs' hand-drawn SVGs: a person, and a bell in a ring)

    private func refreshGlyphs() {
        let p = palette(dark: dark)
        let colors = p.icons.map { $0.resolvedColor(with: traitCollection) }
        let box = glyphBoxSize
        guard box > 1 else { return }
        if let person = symbolImage(named: "person.fill", pointSize: box * 0.82) {
            glyphL.image = gradientImage(person, colors: colors, size: CGSize(width: box, height: box))
        }
        if let bell = symbolImage(named: "bell.fill", pointSize: box * 0.52) {
            let bellSize = CGSize(width: box * 0.62, height: box * 0.62)
            glyphR.image = gradientImage(bell, colors: colors, size: bellSize)
        }
        // Ring around the bell: stroke = 12.05 / 200 of the glyph box.
        let inset = box * 17.01 / 200
        let ringRect = CGRect(x: inset, y: inset,
                              width: box - inset * 2, height: box - inset * 2)
        let mask = CAShapeLayer()
        mask.path = UIBezierPath(ovalIn: ringRect).cgPath
        mask.fillColor = nil
        mask.strokeColor = UIColor.black.cgColor
        mask.lineWidth = box * 12.05 / 200
        ringGradient.frame = glyphRBox.bounds
        ringGradient.mask = mask
    }

    private var glyphBoxSize: CGFloat = 0

    private func symbolImage(named name: String, pointSize: CGFloat) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return UIImage(systemName: name, withConfiguration: config)
    }

    /// Fills a symbol's alpha with a diagonal gradient (the SVG icons' look).
    private func gradientImage(_ symbol: UIImage, colors: [UIColor], size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            // Aspect-fit the symbol inside the target box.
            let symbolSize = symbol.size
            let fit = min(size.width / symbolSize.width, size.height / symbolSize.height)
            let drawSize = CGSize(width: symbolSize.width * fit, height: symbolSize.height * fit)
            let drawRect = CGRect(x: (size.width - drawSize.width) / 2,
                                  y: (size.height - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height)
            let mask = UIGraphicsImageRenderer(size: size).image { _ in
                symbol.draw(in: drawRect)
            }
            let cg = context.cgContext
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map { $0.cgColor } as CFArray,
                locations: [0, 0.5, 1]
            )!
            cg.drawLinearGradient(gradient,
                                  start: CGPoint(x: size.width * 0.08, y: 0),
                                  end: CGPoint(x: size.width * 0.92, y: size.height),
                                  options: [])
            cg.setBlendMode(.destinationIn)
            mask.draw(in: rect)
        }
    }

    // MARK: Layout (all numbers are design px on the 1080-wide canvas)

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutDesign()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let nowDark = traitCollection.userInterfaceStyle == .dark
        if nowDark != dark {
            dark = nowDark
            applyPalette()
            layoutDesign()
        }
    }

    private func layoutDesign() {
        let bounds = view.bounds
        guard bounds.width > 0 else { return }
        let s = bounds.width / 1080
        scale = s
        let modalW = 835 * s
        let modalH = 728 * s
        let radius = 88 * s
        shadowHost.frame = CGRect(x: (bounds.width - modalW) / 2,
                                  y: (bounds.height - modalH) / 2,
                                  width: modalW, height: modalH)
        shadowHost.layer.shadowOffset = CGSize(width: 0, height: 30 * s)
        shadowHost.layer.shadowRadius = 40 * s
        shadowHost.layer.shadowOpacity = 1
        shadowHost.layer.shadowPath = UIBezierPath(
            roundedRect: shadowHost.bounds, cornerRadius: radius).cgPath
        cardView.frame = shadowHost.bounds
        cardView.layer.cornerRadius = radius
        baseGradient.frame = cardView.bounds
        baseGradient.startPoint = CGPoint(x: 0.5, y: 0)
        baseGradient.endPoint = CGPoint(x: 0.5, y: 1)
        sheenLayer.frame = cardView.bounds
        sheenLayer.startPoint = CGPoint(x: 0.5, y: 0)
        sheenLayer.endPoint = CGPoint(x: 1.2, y: 0)
        glowLayer.frame = CGRect(x: -modalW * 0.09, y: -modalH * 0.30,
                                 width: modalW * 1.18, height: modalH * 0.72)
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1.0, y: 0.5)

        let heroH = 335 * s
        heroView.frame = CGRect(x: 0, y: 0, width: modalW, height: heroH)
        heroGradient.frame = heroView.bounds
        heroGlow.frame = heroView.bounds
        heroGlow.startPoint = CGPoint(x: 0.52, y: 0.22)
        heroGlow.endPoint = CGPoint(x: 1.12, y: 0.22)
        streakView.frame = CGRect(x: modalW * 0.52, y: -heroH * 0.55,
                                  width: modalW * 0.42, height: heroH * 2.2)
        streakView.transform = CGAffineTransform(rotationAngle: 24 * .pi / 180)
        streakGradient.frame = streakView.bounds

        let cardSize = 145 * s
        let cardRadius = 44 * s
        if !entranceInFlight {
            layoutIconCard(iconCardL, x: 295 * s, y: 84 * s, size: cardSize, radius: cardRadius)
            layoutIconCard(iconCardR, x: 416 * s, y: 84 * s, size: cardSize, radius: cardRadius)
        }
        glyphBoxSize = cardSize * 0.47
        glyphL.frame = CGRect(x: (cardSize - glyphBoxSize) / 2,
                              y: (cardSize - glyphBoxSize) / 2,
                              width: glyphBoxSize, height: glyphBoxSize)
        glyphRBox.frame = glyphL.frame
        glyphR.frame = glyphRBox.bounds
        ringGradient.frame = glyphRBox.bounds

        let textSize = max(27 * s, 12)
        let textX = 56 * s
        let textW = modalW - textX - 40 * s
        line1.font = .systemFont(ofSize: textSize, weight: .semibold)
        line1.frame = CGRect(x: textX, y: 406 * s, width: textW,
                             height: line1.font.lineHeight + 6 * s)
        line2.font = .systemFont(ofSize: textSize)
        line2.frame = CGRect(x: textX, y: 467 * s, width: textW,
                             height: line2.font.lineHeight + 6 * s)
        line3.font = .systemFont(ofSize: textSize)
        line3.frame = CGRect(x: textX, y: 516 * s, width: textW,
                             height: line3.font.lineHeight * 2 + 6 * s)

        let buttonFont = UIFont.systemFont(ofSize: max(30 * s, 13), weight: .semibold)
        let buttonY = 589 * s
        let buttonH = 90 * s
        let buttonRadius = 45 * s
        leftButton.frame = CGRect(x: 48 * s, y: buttonY, width: 355 * s, height: buttonH)
        leftButton.layer.cornerRadius = buttonRadius
        leftButton.layer.borderWidth = max(2 * s, 0.7)
        leftButton.titleLabel?.font = .systemFont(ofSize: max(30 * s, 13), weight: .medium)
        rightButton.frame = CGRect(x: 430 * s, y: buttonY, width: 378 * s, height: buttonH)
        rightButton.layer.cornerRadius = buttonRadius
        rightButton.layer.shadowOffset = CGSize(width: 0, height: 12 * s)
        rightButton.layer.shadowRadius = 16 * s
        rightButton.layer.shadowOpacity = 1
        rightButton.layer.shadowPath = UIBezierPath(
            roundedRect: rightButton.bounds, cornerRadius: buttonRadius).cgPath
        rightButton.titleLabel?.font = buttonFont
        rightGradient.frame = rightButton.bounds
        rightGradient.cornerRadius = buttonRadius

        refreshGlyphs()
    }

    private func layoutIconCard(_ card: UIView, x: CGFloat, y: CGFloat,
                                size: CGFloat, radius: CGFloat) {
        card.frame = CGRect(x: x, y: y, width: size, height: size)
        card.layer.shadowOffset = CGSize(width: 0, height: 15 * scale)
        card.layer.shadowRadius = 18 * scale
        card.layer.shadowOpacity = 1
        if let clip = card.viewWithTag(101) {
            clip.frame = card.bounds
            clip.layer.cornerRadius = radius
            clip.viewWithTag(102)?.frame = clip.bounds
            clip.viewWithTag(103)?.frame = clip.bounds
        }
    }

    // MARK: Entrance (jellyIn .95s + riseIn icon cards + fadeUp texts)

    private var iconCardCenters: [CGPoint] = []
    private var entrancePrepared = false
    private var entranceInFlight = false

    func prepareEntrance() {
        guard !entrancePrepared else { return }
        entrancePrepared = true
        entranceInFlight = true
        layoutDesign()
        if UIAccessibility.isReduceMotionEnabled { return }
        shadowHost.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        shadowHost.alpha = 0
        iconCardCenters = [iconCardL.center, iconCardR.center]
        for (index, card) in [iconCardL, iconCardR].enumerated() {
            card.alpha = 0
            card.center = CGPoint(x: iconCardCenters[index].x,
                                  y: iconCardCenters[index].y + 34 * scale)
            card.transform = CGAffineTransform(rotationAngle: index == 0 ? -8 * .pi / 180
                                                                      : 6 * .pi / 180)
        }
        for label in [line1, line2, line3] {
            label.alpha = 0
            label.transform = CGAffineTransform(translationX: 0, y: 14 * scale)
        }
    }

    func playEntrance() {
        // Icon-card resting tilt (also the non-animated resting state).
        iconCardL.transform = CGAffineTransform(rotationAngle: -8 * .pi / 180)
        iconCardR.transform = CGAffineTransform(rotationAngle: 6 * .pi / 180)
        if UIAccessibility.isReduceMotionEnabled {
            shadowHost.transform = .identity
            shadowHost.alpha = 1
            iconCardL.alpha = 1
            iconCardR.alpha = 1
            for label in [line1, line2, line3] {
                label.alpha = 1
                label.transform = .identity
            }
            return
        }
        UIView.animateKeyframes(withDuration: 0.95, delay: 0,
                                options: [.calculationModeCubic]) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.55) {
                self.shadowHost.transform = CGAffineTransform(scaleX: 1.028, y: 1.028)
                self.shadowHost.alpha = 1
            }
            UIView.addKeyframe(withRelativeStartTime: 0.55, relativeDuration: 0.17) {
                self.shadowHost.transform = CGAffineTransform(scaleX: 0.992, y: 0.992)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.72, relativeDuration: 0.14) {
                self.shadowHost.transform = CGAffineTransform(scaleX: 1.01, y: 1.01)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.86, relativeDuration: 0.14) {
                self.shadowHost.transform = .identity
            }
        }
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.22, y: 0.85),
                                             controlPoint2: CGPoint(x: 0.3, y: 1))
        for (index, card) in [iconCardL, iconCardR].enumerated() {
            let animator = UIViewPropertyAnimator(duration: 0.95, timingParameters: timing)
            animator.addAnimations {
                card.alpha = 1
                card.center = self.iconCardCenters[index]
            }
            animator.startAnimation(afterDelay: index == 0 ? 0.14 : 0.27)
        }
        for (index, label) in [line1, line2, line3].enumerated() {
            let animator = UIViewPropertyAnimator(duration: 0.6, timingParameters: timing)
            animator.addAnimations {
                label.alpha = 1
                label.transform = .identity
            }
            animator.startAnimation(afterDelay: 1.3 + 0.15 * Double(index))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.entranceInFlight = false
            self?.layoutDesign()
        }
    }

    // MARK: Actions

    @objc private func buttonTouchDown(_ button: UIButton) {
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
            self.shadowHost.alpha = 0
            self.shadowHost.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }, completion: { _ in
            self.onDismiss?()
        })
    }
}

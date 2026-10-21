import UIKit

/// Splash 03 （粒子聚合） — the not-logged-in HARD GATE.
///
/// Faithful port of the user's `splash-03-particles-register-login.html`:
/// a full-screen canvas whose particles start on a ring around the
/// center and assemble, with the design's own easing, into the "LUiYo"
/// wordmark sampled from an offscreen text render — over the design's
/// 160° gradient with two drifting radial blobs, the loading dots and
/// the ASSEMBLE · FLOW tag.
///
/// Gate behaviour (user-specified): unlike the looping demo there is
/// NO stageOut and NO particle dispersal — after assembly the wordmark
/// holds (with the design's wobble + twinkle continuing) and the
/// ambient blob drift / dot jumps run forever. An 立即注册 glass button
/// fades in once the wordmark has assembled (fadeUp at 11t, the tag's
/// own timing) and stays. The splash never dismisses itself; only a
/// successful register/login (via the button) leaves this screen.
final class Splash03ViewController: UIViewController {
    var onRegisterTap: (() -> Void)?

    /// Design px → points.
    private var s: CGFloat = 0.5
    private var started = false
    private var startTime: CFTimeInterval = 0

    private let backgroundView = CSSGradientView(angle: 160, stops: [
        (splashHex("#2f4f9e"), 0), (splashHex("#3d6fd0"), 0.4), (splashHex("#6a54c8"), 1)
    ])
    private let blob1 = RadialGlowView(stops: [
        (splashHex("#c9aaf7"), 0), (splashHex("#c9aaf7", 0), 0.65)
    ])
    private let blob2 = RadialGlowView(stops: [
        (splashHex("#8ab6f5"), 0), (splashHex("#8ab6f5", 0), 0.65)
    ])
    private let canvas = ParticleCanvasView()
    private let dotsView: SplashDotsView
    private let tagLabel = UILabel()
    private let registerWrap = UIView()
    private let registerButton = UIButton(type: .custom)

    init() {
        dotsView = SplashDotsView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = splashHex("#2f4f9e")
        blob1.layer.opacity = 0.6
        blob2.layer.opacity = 0.6
        view.addSubview(backgroundView)
        view.addSubview(blob1)
        view.addSubview(blob2)
        view.addSubview(canvas)
        view.addSubview(dotsView)
        tagLabel.text = "ASSEMBLE · FLOW"
        tagLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        tagLabel.textAlignment = .center
        view.addSubview(tagLabel)

        // 立即注册 — a glass pill in the splash's own language: a light
        // material blur, a white wash, a hairline white border.
        let effect = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        effect.isUserInteractionEnabled = false
        registerButton.addSubview(effect)
        let wash = UIView()
        wash.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        wash.isUserInteractionEnabled = false
        registerButton.addSubview(wash)
        registerButton.setTitle("立即注册", for: .normal)
        registerButton.setTitleColor(.white, for: .normal)
        registerButton.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        registerButton.clipsToBounds = true
        registerButton.addTarget(self, action: #selector(registerTapped), for: .touchUpInside)
        registerWrap.addSubview(registerButton)
        registerWrap.alpha = 0
        view.addSubview(registerWrap)
        effect.translatesAutoresizingMaskIntoConstraints = false
        wash.translatesAutoresizingMaskIntoConstraints = false
        for inner in [effect, wash] {
            NSLayoutConstraint.activate([
                inner.leadingAnchor.constraint(equalTo: registerButton.leadingAnchor),
                inner.trailingAnchor.constraint(equalTo: registerButton.trailingAnchor),
                inner.topAnchor.constraint(equalTo: registerButton.topAnchor),
                inner.bottomAnchor.constraint(equalTo: registerButton.bottomAnchor)
            ])
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        s = bounds.width / 750
        backgroundView.frame = bounds
        canvas.frame = bounds
        // Blobs (design px, from the CSS: sizes and offsets verbatim).
        blob1.frame = CGRect(x: -100 * s, y: -60 * s, width: 320 * s, height: 320 * s)
        blob2.frame = CGRect(x: bounds.width - (300 - 90) * s, y: bounds.height - (300 - 70) * s,
                             width: 300 * s, height: 300 * s)
        // Center column: spacer 220 / dots / tag, gap 26, centered —
        // the same flex column as the design's .center overlay.
        dotsView.scale = s
        let tagHeight = 14.4 * s
        let columnHeight = (220 + 26 + 7 + 26) * s + tagHeight
        let columnTop = (bounds.height - columnHeight) / 2
        let dotsY = columnTop + (220 + 26) * s
        dotsView.frame = CGRect(x: (bounds.width - dotsView.intrinsicContentSize.width) / 2,
                                y: dotsY, width: dotsView.intrinsicContentSize.width, height: 7 * s)
        let tagY = dotsY + 7 * s + 26 * s
        tagLabel.frame = CGRect(x: 0, y: tagY, width: bounds.width, height: tagHeight)
        tagLabel.font = .systemFont(ofSize: 12 * s, weight: .bold)
        tagLabel.addTracking(5 * s)
        // The register button hangs below the tag, in the same column.
        let buttonSize = CGSize(width: 320 * s, height: 96 * s)
        registerWrap.frame = CGRect(x: (bounds.width - buttonSize.width) / 2,
                                    y: tagY + tagHeight + 44 * s,
                                    width: buttonSize.width, height: buttonSize.height)
        registerButton.frame = registerWrap.bounds
        registerButton.layer.cornerRadius = buttonSize.height / 2
        registerButton.layer.borderWidth = max(1, 1 * s)
        registerButton.titleLabel?.font = .systemFont(ofSize: 30 * s, weight: .semibold)
    }

    /// Starts the choreography (called once, when the splash is on
    /// screen and the app is active).
    func begin() {
        guard !started else { return }
        started = true
        startTime = CACurrentMediaTime()
        view.layoutIfNeeded()
        drift(blob1, to: CGPoint(x: 70, y: 50), scaleTo: 1.15, duration: 18)
        drift(blob2, to: CGPoint(x: -80, y: 40), scaleTo: 0.9, duration: 22)
        canvas.start()
        dotsView.start(at: startTime)
        if UIAccessibility.isReduceMotionEnabled {
            registerWrap.alpha = 1
            return
        }
        addFadeUp(to: tagLabel.layer, beginTime: startTime + 11 * 0.24,
                  duration: 5 * 0.24, distance: 12 * s)
        // The button fades in with the tag's own fadeUp timing (11t,
        // once the wordmark has assembled at 0.78 of the cycle ≈ 10.9t)
        // and then stays — model alpha 1, animation fills backwards.
        addFadeUp(to: registerWrap.layer, beginTime: startTime + 11 * 0.24,
                  duration: 5 * 0.24, distance: 12 * s)
        registerWrap.alpha = 1
    }

    private func drift(_ blob: UIView, to offset: CGPoint, scaleTo: CGFloat, duration: CFTimeInterval) {
        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = CATransform3DIdentity
        var target = CATransform3DMakeTranslation(offset.x * s, offset.y * s, 0)
        target = CATransform3DScale(target, scaleTo, scaleTo, 1)
        anim.toValue = target
        anim.duration = duration
        anim.timingFunction = SplashTiming.cssEaseInOut
        anim.autoreverses = true
        anim.repeatCount = .infinity
        blob.layer.add(anim, forKey: "drift")
    }

    @objc private func registerTapped() {
        onRegisterTap?()
    }

    /// Stops the particle display link before the splash is removed
    /// for good (the link retains the canvas; this breaks the cycle).
    func shutdown() {
        canvas.stop()
    }
}

/// The particle canvas. The JS system, ported line for line:
/// targets are sampled from "LUiYo" drawn offscreen at 800 weight /
/// 130px in a 640 × 220 box, step 4, alpha > 128, capped at 1400;
/// colors run across the wordmark through the design's 5-stop palette;
/// each particle starts on a ring of radius max(W,H) × 0.62, eases to
/// its target with easeOutCubic over progress 0 → 0.78 of the 3360 ms
/// cycle (per-particle delay up to 0.16), with the design's sinusoidal
/// wobble and twinkle. Where the demo then disperses the particles and
/// loops, the gate HOLDS the assembled wordmark (wobble + twinkle
/// continue) — the splash is a door, not a loop.
final class ParticleCanvasView: UIView {
    private struct Particle {
        var sx: CGFloat, sy: CGFloat
        var tx: CGFloat, ty: CGFloat
        var color: UIColor
        var delay: CGFloat
        var size: CGFloat
        var seed: CGFloat
    }

    private var particles: [Particle] = []
    private var displayLink: CADisplayLink?
    private var startStamp: CFTimeInterval = 0
    /// Design-space size (750 wide, aspect follows the real bounds).
    private var designSize = CGSize(width: 750, height: 1334)
    private var pointScale: CGFloat = 0.5

    func start() {
        guard displayLink == nil else { return }
        buildParticles()
        if UIAccessibility.isReduceMotionEnabled {
            setNeedsDisplay()
            return
        }
        startStamp = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func buildParticles() {
        let bounds = self.bounds
        guard bounds.width > 0 else { return }
        pointScale = bounds.width / 750
        designSize = CGSize(width: 750, height: 750 * bounds.height / bounds.width)
        let targets = sampleTargets()
        let W = designSize.width, H = designSize.height
        let radius = max(W, H) * 0.62
        particles = targets.map { target in
            let angle = CGFloat.random(in: 0 ..< (.pi * 2))
            let sx = W / 2 + cos(angle) * radius
            let sy = H / 2 + sin(angle) * radius
            return Particle(
                sx: sx, sy: sy, tx: target.x, ty: target.y,
                color: target.color,
                delay: CGFloat.random(in: 0 ..< 0.16),
                size: 1.4 + CGFloat.random(in: 0 ..< 1.5),
                seed: CGFloat.random(in: 0 ..< 6.28))
        }
    }

    /// Renders the wordmark offscreen and samples its pixels, exactly
    /// as the design's buildTargets() does.
    private func sampleTargets() -> [(x: CGFloat, y: CGFloat, color: UIColor)] {
        let boxW: CGFloat = 640, boxH: CGFloat = 220
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: boxW, height: boxH), format: format)
            .image { _ in
                let font = roundedHeavyFont(size: 130)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: UIColor.white
                ]
                let text = "LUiYo" as NSString
                let textWidth = text.size(withAttributes: attrs).width
                let rect = CGRect(x: (boxW - textWidth) / 2,
                                  y: 112 - font.lineHeight / 2,
                                  width: textWidth, height: font.lineHeight)
                text.draw(in: rect, withAttributes: attrs)
            }
        guard let cg = image.cgImage,
              let provider = cg.dataProvider,
              let data = provider.data else { return [] }
        let bytes = CFDataGetBytePtr(data)!
        let bytesPerRow = cg.bytesPerRow
        let colors = ["#ffffff", "#eaf6ff", "#a9d4f5", "#8ab6f5", "#c9aaf7"]
            .map { splashHex($0) }
        var points: [(x: CGFloat, y: CGFloat, color: UIColor)] = []
        var y: CGFloat = 0
        while y < boxH {
            var x: CGFloat = 0
            while x < boxW {
                let alpha = bytes[Int(y) * bytesPerRow + Int(x) * 4 + 3]
                if alpha > 128 {
                    let idx = min(colors.count - 1, Int(x / boxW * CGFloat(colors.count - 1)))
                    points.append((x, y, colors[idx]))
                }
                x += 4
            }
            y += 4
        }
        if points.count > 1400 {
            let stride = Int(ceil(Double(points.count) / 1400))
            points = points.enumerated().filter { $0.offset % stride == 0 }.map { $0.element }
        }
        let W = designSize.width, H = designSize.height
        let k = min(W * 0.8 / boxW, 1)
        let ox = (W - boxW * k) / 2
        let oy = (H - boxH * k) / 2 - 30
        return points.map { (ox + $0.x * k, oy + $0.y * k, $0.color) }
    }

    private func roundedHeavyFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .black)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    @objc private func tick() {
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !particles.isEmpty else { return }
        let total: CFTimeInterval = 14000 * 0.24 / 1000  // cycleMs = --t × 14000 (3.36 s)
        let staticMode = displayLink == nil
        let elapsed = staticMode ? total : CACurrentMediaTime() - startStamp
        let p = min(elapsed / total, 1)
        let nowMs = elapsed * 1000
        for particle in particles {
            let local: CGFloat
            if p < 0.78 {
                local = min(1, max(0, (CGFloat(p) - particle.delay) / (0.78 - particle.delay)))
            } else {
                local = 1
            }
            let e = 1 - pow(1 - local, 3)
            var x = particle.sx + (particle.tx - particle.sx) * e
            var y = particle.sy + (particle.ty - particle.sy) * e
            let wobbleAmp: CGFloat = p > 0.3 ? 1 : 0.2
            y += sin(CGFloat(nowMs) / 380 + particle.seed) * 1.2 * wobbleAmp
            x *= pointScale
            y *= pointScale
            let twinkle: CGFloat = staticMode
                ? 1
                : 0.78 + 0.22 * sin(CGFloat(nowMs) / 240 + particle.seed)
            context.setFillColor(particle.color.withAlphaComponent(twinkle).cgColor)
            let r = particle.size * pointScale
            context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }
}

extension UILabel {
    /// CSS letter-spacing (tracking) via the attributed string.
    func addTracking(_ value: CGFloat) {
        guard let text else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        attributedText = NSAttributedString(
            string: text, attributes: [.kern: value, .font: font as Any,
                                       .foregroundColor: textColor as Any,
                                       .paragraphStyle: paragraph])
    }
}

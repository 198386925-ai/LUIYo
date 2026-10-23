import UIKit
import CoreText

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
/// fades in once the wordmark has assembled and stays. The splash
/// never dismisses itself; only a
/// successful register/login (via the button) leaves this screen.

/// Splash 03 pacing (Build 19). The design's own JS assembles the
/// wordmark over progress 0 → 0.78 of a --t × 14000 = 3.36 s cycle
/// (fully assembled at 2.62 s), and the app originally matched it
/// exactly — verified against the design file's constants and its
/// rendered frames. The user reads that flight as too fast, so the
/// assembly phase (only the flight — delays included) is stretched
/// ×1.45 to ≈3.80 s. The tag and the register button still appear
/// the moment assembly completes; the hold (wobble + twinkle) is
/// unchanged.
enum Splash03Pacing {
    static let cycleSeconds: CFTimeInterval = 14000 * 0.24 / 1000  // 3.36
    static let slowdown: CFTimeInterval = 1.45
    static var assemblySeconds: CFTimeInterval {
        cycleSeconds * 0.78 * slowdown  // ≈ 3.80
    }
}

final class Splash03ViewController: UIViewController {
    var onRegisterTap: (() -> Void)?

    /// Design px → points.
    private var s: CGFloat = 0.5
    private var started = false
    private var startTime: CFTimeInterval = 0

    private let backgroundView = CSSGradientView(angle: 160, stops: [
        (splashHex("#768bbf"), 0), (splashHex("#7fa0e0"), 0.4), (splashHex("#9d8edb"), 1)
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
        view.backgroundColor = splashHex("#768bbf")
        blob1.layer.opacity = 0.6
        blob2.layer.opacity = 0.6
        view.addSubview(backgroundView)
        view.addSubview(blob1)
        view.addSubview(blob2)
        view.addSubview(canvas)
        dotsView.sizeBoost = 1.4  // Build 18: dots x1.4 (see layout)
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
        // Build 18: the whole central cluster (this column AND the
        // particle wordmark, whose sampler applies the same shift)
        // sits 4% of the screen height lower than the design's exact
        // centre — the device read as too high. The dots and the tag
        // are scaled x1.4 (they read too small); the wordmark and the
        // gaps keep the design's sizes.
        dotsView.scale = s
        let dotsHeight = dotsView.intrinsicContentSize.height
        let tagHeight = 14.4 * 1.4 * s
        let columnHeight = (220 + 26) * s + dotsHeight + 26 * s + tagHeight
        let columnTop = (bounds.height - columnHeight) / 2 + bounds.height * 0.04
        let dotsY = columnTop + (220 + 26) * s
        dotsView.frame = CGRect(x: (bounds.width - dotsView.intrinsicContentSize.width) / 2,
                                y: dotsY, width: dotsView.intrinsicContentSize.width, height: dotsHeight)
        let tagY = dotsY + dotsHeight + 26 * s
        tagLabel.frame = CGRect(x: 0, y: tagY, width: bounds.width, height: tagHeight)
        tagLabel.font = .systemFont(ofSize: 12 * 1.4 * s, weight: .bold)
        tagLabel.addTracking(5 * 1.4 * s)
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
        addFadeUp(to: tagLabel.layer,
                  beginTime: startTime + Splash03Pacing.assemblySeconds + 0.02,
                  duration: 5 * 0.24, distance: 12 * s)
        // The button fades in with the tag's own fadeUp timing, the
        // moment the wordmark has assembled (Build 19: assembly is
        // ≈3.80 s after the ×1.45 stretch, see Splash03Pacing) and
        // then stays — model alpha 1, animation fills backwards.
        addFadeUp(to: registerWrap.layer,
                  beginTime: startTime + Splash03Pacing.assemblySeconds + 0.02,
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
/// 130px in a 640 × 220 box, step 3, alpha > 128, capped at 1900;
/// colors run across the wordmark through the design's 5-stop palette;
/// each particle starts on a ring of radius max(W,H) × 0.62, eases to
/// its target with easeOutCubic over progress 0 → 0.78 of the 3360 ms
/// cycle (per-particle delay up to 0.16) — played on a ×1.45-stretched
/// virtual clock since Build 19 (see Splash03Pacing), with the design's sinusoidal
/// wobble and twinkle. Where the demo then disperses the particles and
/// loops, the gate HOLDS the assembled wordmark (wobble + twinkle
/// continue) — the splash is a door, not a loop.
final class ParticleCanvasView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        // The gradient and blobs live UNDER this canvas in the splash;
        // the canvas itself must stay transparent — an opaque backing
        // here was half of Build 14's black splash.
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
    /// as the design's buildTargets() does — but into a bitmap context
    /// this code OWNS, with a guaranteed pixel layout.
    ///
    /// Build 14 read the bytes behind a `UIGraphicsImageRenderer`
    /// image's data provider assuming 4 bytes/pixel RGBA. On device
    /// that image's storage is a wider pixel format, so the alpha
    /// probe landed on garbage bytes and the "targets" were noise
    /// scattered over the whole box — the black-static splash. Here
    /// the buffer is created with DeviceRGB / 8-bit /
    /// premultipliedLast / bytesPerRow = width × 4 by construction,
    /// so the alpha byte is always exactly where the sampler looks.
    private func sampleTargets() -> [(x: CGFloat, y: CGFloat, color: UIColor)] {
        let boxW = 640, boxH = 220
        let bytesPerRow = boxW * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * boxH)
        let font = Self.wordmarkFont(size: 130)
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                    data: base, width: boxW, height: boxH,
                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            // CoreText draws in the context's native y-up space.
            // The design centres the wordmark at (320, 112) in
            // y-down canvas space, i.e. (320, 220 − 112) y-up; centre
            // the line's optical bounds on that point.
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: "LUiYo",
                attributes: [.font: font, .foregroundColor: UIColor.white]))
            let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            context.textPosition = CGPoint(
                x: 320 - (bounds.minX + bounds.width / 2),
                y: (220 - 112) - (bounds.minY + bounds.height / 2))
            CTLineDraw(line, context)
        }
        let colors = ["#ffffff", "#eaf6ff", "#a9d4f5", "#8ab6f5", "#c9aaf7"]
            .map { splashHex($0) }
        var points: [(x: CGFloat, y: CGFloat, color: UIColor)] = []
        var row = 0
        while row < boxH {
            var x = 0
            while x < boxW {
                if buffer[row * bytesPerRow + x * 4 + 3] > 128 {
                    let idx = min(colors.count - 1,
                                  Int(CGFloat(x) / CGFloat(boxW) * CGFloat(colors.count - 1)))
                    // The bitmap's memory rows run in the SAME
                    // order as the design's top-down canvas rows
                    // (row 0 = the top of the drawn wordmark) — the
                    // target y is the row itself. Build 16 flipped it
                    // (boxH − row) on the assumption the buffer was
                    // bottom-up; on device the assembled wordmark
                    // came out upside down.
                    points.append((CGFloat(x), CGFloat(row), colors[idx]))
                }
                x += 3
            }
            row += 3
        }
        if points.count > 1900 {
            let stride = Int(ceil(Double(points.count) / 1900.0))
            points = points.enumerated().filter { $0.offset % stride == 0 }.map { $0.element }
        }
        let W = designSize.width, H = designSize.height
        let boxWf = CGFloat(boxW), boxHf = CGFloat(boxH)
        let k = min(W * 0.8 / boxWf, 1) * 1.35  // Build 17: wordmark ×1.35 (≈60% of screen width)
        let ox = (W - boxWf * k) / 2
        // Build 18: +4% of the screen height — the whole central
        // cluster (wordmark + dots + tag + button) shifts down
        // together; the view controller's column applies the same
        // 4% shift in points.
        let oy = (H - boxHf * k) / 2 - 30 + H * 0.04
        return points.map { (ox + $0.x * k, oy + $0.y * k, $0.color) }
    }

    private static var fontRegistered = false

    /// The design's wordmark font: Quicksand at 800 (the design loads
    /// the family and asks the canvas for 800; the shipped static is
    /// its Bold, `Fonts/Quicksand-Bold.ttf`, registered on first
    /// use). If it is ever unavailable the fallback is the system
    /// rounded heavy — the bitmap sampling stays correct either way.
    private static func wordmarkFont(size: CGFloat) -> UIFont {
        if !fontRegistered {
            fontRegistered = true
            let url = Bundle.main.url(forResource: "Quicksand-Bold",
                                      withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: "Quicksand-Bold", withExtension: "ttf")
            if let url {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        if let font = UIFont(name: "Quicksand-Bold", size: size) { return font }
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
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
        context.clear(rect)
        let total: CFTimeInterval = Splash03Pacing.cycleSeconds
        let staticMode = displayLink == nil
        let elapsed = staticMode ? total : CACurrentMediaTime() - startStamp
        // The flight runs on a virtual clock stretched by the
        // pacing slowdown (Build 19): progress p covers the same
        // 0 → 0.78 flight window, but over ≈3.80 s instead of the
        // design's 2.62 s; per-particle delays stretch with it.
        // Wobble/twinkle below keep real time (nowMs), as before.
        let p = min((elapsed / Splash03Pacing.slowdown) / total, 1)
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

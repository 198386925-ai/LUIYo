import UIKit

/// Shared pieces for the two launch splashes, ported from the user's
/// HTML splash designs (750 × 1334 design space, `--t = .24s` timeline
/// unit). Every size in the splash controllers is a design px value
/// multiplied by `s = viewWidth / 750`, exactly like the designs' own
/// fit() scaling. All artwork is layer-based or shipped PNG assets —
/// nothing is baked at runtime (the version popups' ghost lesson).

func splashHex(_ string: String, _ alpha: CGFloat = 1) -> UIColor {
    (ColorHex.parse(string) ?? .white).withAlphaComponent(alpha)
}

/// A view whose layer is a linear CAGradientLayer following CSS
/// `linear-gradient(<angle>deg, stops…)` geometry: the angle is
/// clockwise from "to top", the gradient line spans the rect's
/// projection, exactly as CSS computes it.
final class CSSGradientView: UIView {
    private let angleDeg: CGFloat
    private let stops: [(UIColor, CGFloat)]

    init(angle: CGFloat, stops: [(UIColor, CGFloat)]) {
        angleDeg = angle
        self.stops = stops
        super.init(frame: .zero)
        let layer = gradientLayer
        layer.colors = stops.map { $0.0.cgColor }
        layer.locations = stops.map { NSNumber(value: Double($0.1)) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        let rad = angleDeg * .pi / 180
        let dx = sin(rad), dy = -cos(rad)
        let length = abs(w * sin(rad)) + abs(h * cos(rad))
        let cx = w / 2, cy = h / 2
        gradientLayer.startPoint = CGPoint(
            x: (cx - dx * length / 2) / w, y: (cy - dy * length / 2) / h)
        gradientLayer.endPoint = CGPoint(
            x: (cx + dx * length / 2) / w, y: (cy + dy * length / 2) / h)
        // Trait-resolved colors (the stops are fixed colors, but cgColor
        // snapshots taken in init could predate the trait environment).
        gradientLayer.colors = stops.map {
            $0.0.resolvedColor(with: traitCollection).cgColor
        }
    }
}

/// A soft radial glow (CSS `radial-gradient(circle, c0, c1@stop, …)`
/// rendered as a radial CAGradientLayer; the gradient's own falloff is
/// the softness — no filters, no baked images).
final class RadialGlowView: UIView {
    init(stops: [(UIColor, CGFloat)]) {
        super.init(frame: .zero)
        let layer = glowLayer
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.colors = stops.map { $0.0.cgColor }
        layer.locations = stops.map { NSNumber(value: Double($0.1)) }
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var glowLayer: CAGradientLayer { layer as! CAGradientLayer }
}

/// CSS timing functions as CAMediaTimingFunction.
enum SplashTiming {
    static let ease = CAMediaTimingFunction(name: .easeInEaseOut)
    static let cssEase = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
    static let cssEaseInOut = CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
}

/// The designs' fadeUp: opacity 0→1, translateY 12 design px→0.
func addFadeUp(to layer: CALayer, beginTime: CFTimeInterval,
               duration: CFTimeInterval, distance: CGFloat) {
    let group = CAAnimationGroup()
    let opacity = CABasicAnimation(keyPath: "opacity")
    opacity.fromValue = 0
    opacity.toValue = 1
    let move = CABasicAnimation(keyPath: "transform.translation.y")
    move.fromValue = distance
    move.toValue = 0
    group.animations = [opacity, move]
    group.duration = duration
    group.beginTime = beginTime
    group.timingFunction = SplashTiming.cssEase
    group.fillMode = .backwards
    layer.add(group, forKey: "fadeUp")
}

/// The three loading dots shared by both splashes: 7 design px white
/// dots, 8 px gaps, dotJump 5.2t ease-in-out infinite, starting at
/// delays 10.4t / 10.9t / 11.4t (before their delay each dot is
/// invisible, per the CSS base style).
final class SplashDotsView: UIView {
    private var dots: [UIView] = []
    /// Design px → points; set by the owner once it knows its scale.
    var scale: CGFloat = 0.5 {
        didSet { setNeedsLayout() }
    }
    private var s: CGFloat { scale }

    init() {
        super.init(frame: .zero)
        for _ in 0 ..< 3 {
            let dot = UIView()
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.92)
            dot.layer.shadowColor = UIColor.white.cgColor
            dot.layer.shadowOpacity = 0.7
            dot.layer.shadowOffset = .zero
            dot.isHidden = true
            addSubview(dot)
            dots.append(dot)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let d = 7 * s, gap = 8 * s
        for (i, dot) in dots.enumerated() {
            dot.frame = CGRect(x: CGFloat(i) * (d + gap), y: 0, width: d, height: d)
            dot.layer.cornerRadius = 3.5 * s
            dot.layer.shadowRadius = 4 * s
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 3 * 7 * s + 2 * 8 * s, height: 7 * s)
    }

    /// Starts the dot choreography relative to `startTime`
    /// (CACurrentMediaTime space).
    func start(at startTime: CFTimeInterval) {
        let delays: [CFTimeInterval] = [10.4, 10.9, 11.4]
        for (i, dot) in dots.enumerated() {
            let begin = startTime + delays[i] * 0.24
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, begin - CACurrentMediaTime())) {
                dot.isHidden = false
            }
            let group = CAAnimationGroup()
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.25, 1, 0.25]
            opacity.keyTimes = [0, 0.45, 1]
            let move = CAKeyframeAnimation(keyPath: "transform.translation.y")
            move.values = [0, -7 * s, 0]
            move.keyTimes = [0, 0.45, 1]
            group.animations = [opacity, move]
            group.duration = 5.2 * 0.24
            group.beginTime = begin
            group.timingFunction = SplashTiming.cssEaseInOut
            group.repeatCount = .infinity
            dot.layer.add(group, forKey: "dotJump")
        }
    }
}

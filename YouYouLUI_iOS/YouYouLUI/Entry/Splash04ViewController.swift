import UIKit

/// Splash 04 （玻璃呼吸） — the logged-in launch splash.
///
/// Faithful port of the user's `splash-04-glass-normal.html`: the app
/// icon (his PNG, shipped as an asset) inside a rotating conic glass
/// ring (pre-rendered offline from the design's conic-gradient stops)
/// with a pulsing halo, over the 150° gradient with two drifting
/// blobs; iconIn's elastic entrance, then breathe; the dots; the
/// BREATHE IN tag at 10.6t; and stageOut at 10t dissolving the whole
/// stage into what comes next. `--t = .24s`; the full timeline is
/// 3.6 s. The gate drives the exit: `finish` never starts stageOut
/// before 10t and waits if the status verdict is still out.
final class Splash04ViewController: UIViewController {
    private var s: CGFloat = 0.5
    private var started = false
    private var startTime: CFTimeInterval = 0
    private var finishRequested = false
    private var finishCompletion: (() -> Void)?

    /// Everything stageOut dissolves lives in `inner`.
    private let inner = UIView()
    private let backgroundView = CSSGradientView(angle: 150, stops: [
        (splashHex("#6a54c8"), 0), (splashHex("#4e7de0"), 0.5), (splashHex("#2f63c8"), 1)
    ])
    private let blob1 = RadialGlowView(stops: [
        (splashHex("#f0cffb"), 0), (splashHex("#f0cffb", 0), 0.65)
    ])
    private let blob2 = RadialGlowView(stops: [
        (splashHex("#a9d4f5"), 0), (splashHex("#a9d4f5", 0), 0.65)
    ])
    private let ringWrap = UIView()     // breathe target
    private let ringInner = UIView()    // iconIn target
    /// Build 17: the halo is a PRE-RENDERED static radial-gradient
    /// image (the same stops the old live gradient view used) — the
    /// user wants no blur of any kind on this splash, and a baked
    /// gradient can never soften the artwork above it.
    private let halo = UIImageView(image: UIImage(named: "SplashHalo"))
    private let ringImage = UIImageView(image: UIImage(named: "SplashRing"))
    private let iconImage = UIImageView(image: UIImage(named: "SplashIcon"))
    private let dotsView = SplashDotsView()
    private let tagLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = splashHex("#2f63c8")
        blob1.layer.opacity = 0.7
        blob2.layer.opacity = 0.7
        view.addSubview(inner)
        inner.addSubview(backgroundView)
        inner.addSubview(blob1)
        inner.addSubview(blob2)
        ringInner.addSubview(halo)
        ringInner.addSubview(ringImage)
        ringInner.addSubview(iconImage)
        ringWrap.addSubview(ringInner)
        inner.addSubview(ringWrap)
        inner.addSubview(dotsView)
        tagLabel.text = "BREATHE IN"
        tagLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        tagLabel.textAlignment = .center
        inner.addSubview(tagLabel)
        iconImage.contentMode = .scaleAspectFit
        iconImage.layer.shadowColor = UIColor(red: 15 / 255, green: 40 / 255,
                                              blue: 110 / 255, alpha: 0.55).cgColor
        iconImage.layer.shadowOpacity = 1
        iconImage.layer.shadowOffset = CGSize(width: 0, height: 7)
        iconImage.layer.shadowRadius = 9
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        s = bounds.width / 750
        inner.frame = bounds
        backgroundView.frame = bounds
        blob1.frame = CGRect(x: -110 * s, y: bounds.height * 0.10,
                             width: 340 * s, height: 340 * s)
        blob2.frame = CGRect(x: bounds.width - (300 - 100) * s,
                             y: bounds.height - (300 - 60) * s,
                             width: 300 * s, height: 300 * s)
        // Center column: icon cluster / dots / tag, gap 26, centered.
        // Build 16: the icon renders at 22% of the screen width (the
        // design's own ~15% read too small on device — the user's
        // approved enlargement); ring and halo scale by the same
        // cluster unit `u`, keeping the design's proportions to the
        // icon (ring 166 around icon 128, halo 290 across).
        let u = bounds.width * 0.22 / 128
        let tagHeight = 14.4 * s
        let columnHeight = 128 * u + (26 + 7 + 26) * s + tagHeight
        let columnTop = (bounds.height - columnHeight) / 2
        let ringFrame = CGRect(x: (bounds.width - 128 * u) / 2, y: columnTop,
                               width: 128 * u, height: 128 * u)
        ringWrap.frame = ringFrame
        ringInner.frame = ringWrap.bounds
        halo.frame = CGRect(x: (128 - 290) / 2 * u, y: (128 - 290) / 2 * u,
                            width: 290 * u, height: 290 * u)
        ringImage.frame = CGRect(x: -19 * u, y: -19 * u, width: 166 * u, height: 166 * u)
        iconImage.frame = ringInner.bounds
        iconImage.layer.shadowOffset = CGSize(width: 0, height: 14 * u)
        iconImage.layer.shadowRadius = 18 * u
        let dotsY = columnTop + 128 * u + 26 * s
        dotsView.scale = s
        dotsView.frame = CGRect(x: (bounds.width - dotsView.intrinsicContentSize.width) / 2,
                                y: dotsY, width: dotsView.intrinsicContentSize.width,
                                height: 7 * s)
        tagLabel.frame = CGRect(x: 0, y: dotsY + 7 * s + 26 * s,
                                width: bounds.width, height: tagHeight)
        tagLabel.font = .systemFont(ofSize: 12 * s, weight: .bold)
        tagLabel.addTracking(4 * s)
    }

    /// Starts the design timeline (called once, on screen + active).
    func begin() {
        guard !started else { return }
        started = true
        startTime = CACurrentMediaTime()
        view.layoutIfNeeded()
        drift(blob1, offset: CGPoint(x: -80, y: 40), scaleTo: 0.9, duration: 20)
        drift(blob2, offset: CGPoint(x: 50, y: -60), scaleTo: 1.1, duration: 17)
        // Ring spin: 3.2 s linear infinite.
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = 3.2
        spin.repeatCount = .infinity
        ringImage.layer.add(spin, forKey: "spin")
        // Halo pulse: 14t ease-in-out infinite (opacity .55→1→.55,
        // scale 1→1.1→1).
        let pulse = CAAnimationGroup()
        let pulseOpacity = CAKeyframeAnimation(keyPath: "opacity")
        pulseOpacity.values = [0.55, 1, 0.55]
        pulseOpacity.keyTimes = [0, 0.5, 1]
        let pulseScale = CAKeyframeAnimation(keyPath: "transform.scale")
        pulseScale.values = [1, 1.1, 1]
        pulseScale.keyTimes = [0, 0.5, 1]
        pulse.animations = [pulseOpacity, pulseScale]
        pulse.duration = 14 * 0.24
        pulse.timingFunction = SplashTiming.cssEaseInOut
        pulse.repeatCount = .infinity
        halo.layer.add(pulse, forKey: "haloPulse")
        dotsView.start(at: startTime)
        if UIAccessibility.isReduceMotionEnabled { return }
        // iconIn on the inner container: 6.5t, cubic-bezier(.22,1.45,.36,1),
        // opacity 0→1, scale .62→1, translateY 22→0. Build 17: the
        // design's blur ramp is dropped (user: no blur on 04) — the
        // entrance is opacity/scale/translation only, and no layer
        // filter exists at any phase, so breathe scales the source
        // artwork directly and stays crisp at its peaks.
        let iconIn = CAAnimationGroup()
        let inOpacity = CABasicAnimation(keyPath: "opacity")
        inOpacity.fromValue = 0
        inOpacity.toValue = 1
        let inScale = CABasicAnimation(keyPath: "transform.scale")
        inScale.fromValue = 0.62
        inScale.toValue = 1
        let inMove = CABasicAnimation(keyPath: "transform.translation.y")
        inMove.fromValue = 22 * s
        inMove.toValue = 0
        iconIn.animations = [inOpacity, inScale, inMove]
        iconIn.duration = 6.5 * 0.24
        iconIn.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.45, 0.36, 1)
        iconIn.fillMode = .backwards
        ringInner.layer.add(iconIn, forKey: "iconIn")
        // breathe on the wrapper: 18t ease-in-out infinite from 6.5t.
        let breathe = CAKeyframeAnimation(keyPath: "transform.scale")
        breathe.values = [1, 1.04, 1]
        breathe.keyTimes = [0, 0.5, 1]
        breathe.duration = 18 * 0.24
        breathe.beginTime = startTime + 6.5 * 0.24
        breathe.timingFunction = SplashTiming.cssEaseInOut
        breathe.repeatCount = .infinity
        ringWrap.layer.add(breathe, forKey: "breathe")
        // Tag fadeUp at 10.6t.
        addFadeUp(to: tagLabel.layer, beginTime: startTime + 10.6 * 0.24,
                  duration: 5 * 0.24, distance: 12 * s)
    }

    /// Plays stageOut (never before its design start at 10t) and calls
    /// completion when the stage has dissolved.
    func finish(completion: @escaping () -> Void) {
        guard !finishRequested else { return }
        finishRequested = true
        finishCompletion = completion
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.3, animations: { self.inner.alpha = 0 }) { _ in
                self.finishCompletion?()
            }
            return
        }
        let now = CACurrentMediaTime()
        let outStart = max(now, startTime + 10 * 0.24)
        let group = CAAnimationGroup()
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1
        opacity.toValue = 0
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 1.07
        group.animations = [opacity, scale]
        group.duration = 5 * 0.24
        group.beginTime = outStart
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.8, 0.4)
        group.fillMode = .both
        inner.layer.add(group, forKey: "stageOut")
        let wait = outStart + 5 * 0.24 - CACurrentMediaTime()
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, wait)) {
            self.finishCompletion?()
        }
    }

    /// Skips the choreography and fades out plainly (used when the
    /// status verdict reroutes away from home: banned / kicked).
    func fadeOutQuickly(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.3, animations: { self.view.alpha = 0 }) { _ in
            completion()
        }
    }

    private func drift(_ blob: UIView, offset: CGPoint, scaleTo: CGFloat, duration: CFTimeInterval) {
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
}

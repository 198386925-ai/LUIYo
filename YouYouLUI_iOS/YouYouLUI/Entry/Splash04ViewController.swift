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
    private let halo = RadialGlowView(stops: [
        (UIColor(red: 234 / 255, green: 201 / 255, blue: 250 / 255, alpha: 0.42), 0),
        (UIColor(red: 94 / 255, green: 151 / 255, blue: 238 / 255, alpha: 0.24), 0.45),
        (UIColor(red: 94 / 255, green: 151 / 255, blue: 238 / 255, alpha: 0), 0.70)
    ])
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
        if let filter = CIFilter(name: "CIGaussianBlur") {
            filter.name = "gaussianBlur"
            filter.setValue(0, forKey: kCIInputRadiusKey)
            ringInner.layer.filters = [filter]
        }
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
        // Center column: ring 128 / dots / tag, gap 26, centered.
        let tagHeight = 14.4 * s
        let columnHeight = (128 + 26 + 7 + 26) * s + tagHeight
        let columnTop = (bounds.height - columnHeight) / 2
        let ringFrame = CGRect(x: (bounds.width - 128 * s) / 2, y: columnTop,
                               width: 128 * s, height: 128 * s)
        ringWrap.frame = ringFrame
        ringInner.frame = ringWrap.bounds
        halo.frame = CGRect(x: (128 - 290) / 2 * s, y: (128 - 290) / 2 * s,
                            width: 290 * s, height: 290 * s)
        ringImage.frame = CGRect(x: -19 * s, y: -19 * s, width: 166 * s, height: 166 * s)
        iconImage.frame = ringInner.bounds
        iconImage.layer.shadowOffset = CGSize(width: 0, height: 14 * s)
        iconImage.layer.shadowRadius = 18 * s
        let dotsY = columnTop + (128 + 26) * s
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
        // opacity 0→1, scale .62→1, translateY 22→0, blur 10→0.
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
        if ringInner.layer.filters?.isEmpty == false {
            let blur = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
            blur.fromValue = 10 * s
            blur.toValue = 0
            blur.duration = 6.5 * 0.24
            blur.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.45, 0.36, 1)
            blur.fillMode = .backwards
            ringInner.layer.add(blur, forKey: "iconInBlur")
        }
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
        if let filter = CIFilter(name: "CIGaussianBlur") {
            filter.name = "gaussianBlur"
            filter.setValue(0, forKey: kCIInputRadiusKey)
            inner.layer.filters = [filter]
            let blur = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
            blur.fromValue = 0
            blur.toValue = 6 * s
            blur.duration = 5 * 0.24
            blur.beginTime = outStart
            blur.timingFunction = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.8, 0.4)
            blur.fillMode = .both
            inner.layer.add(blur, forKey: "stageOutBlur")
        }
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

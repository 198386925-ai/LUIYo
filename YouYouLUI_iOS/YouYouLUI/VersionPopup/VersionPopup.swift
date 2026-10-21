import UIKit
import CoreImage

// MARK: - Feed check

/// Native 1:1 restoration of the user's two version popups (HTML designs in
/// luiyoaccount/popup-design: fig1 = blue-purple 弹更新 / soft, fig2 =
/// red-orange 禁用 / banned).
///
/// Every visual value — geometry, gradient stops and angles, colors (light
/// and dark), type sizes/weights, shadows, the SVG glyph artwork itself, and
/// the entrance choreography (jellyIn / riseIn / fadeUp keyframes plus the
/// icons' stroke-draw animation, with the designs' own delays, durations
/// and timing functions) — is taken verbatim from the two HTML files and
/// scaled by s = min(screenW / 1080, screenH / 1918), exactly like the
/// designs' own fit() function.
///
/// Once per launch this reads the static feed `updates/latest.json` and
/// looks up `version_states["<own build>"]`:
///   - soft   → the blue-purple popup （取消 dismisses, 更新 opens the
///              latest IPA's download URL in Safari)
///   - banned → the red-orange popup, not dismissible （退出 exits the app,
///              联系客服 is wired but has no destination yet — no-op)
/// The fetch starts immediately at launch; the popup is presented as soon
/// as the answer arrives. Fail-open: any network/parse failure = no popup.
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
        fetch { payload in
            guard let payload else { return }
            present(payload, hostWindow: hostWindow)
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
        window.isHidden = false
        window.layoutIfNeeded()
        controller.beginEntrance()
    }

    private static func dismiss() {
        popupWindow?.isHidden = true
        popupWindow = nil
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
    /// (color, location) stops of the hero band's 180deg gradient.
    let heroStops: [(UIColor, CGFloat)]
    /// (color, location) stops of the primary button's 135deg gradient.
    let brandStops: [(UIColor, CGFloat)]
    let brandShadow: UIColor
    /// (color, location) stops of line 1's 90deg text gradient.
    let titleStops: [(UIColor, CGFloat)]
    /// Stops (0 / .5 / 1) of the SVG icons' linear gradients.
    let iconStops: [UIColor]
    /// (color, location) stops of the dark modal's brand radial glow.
    let brandGlowStops: [(UIColor, CGFloat)]
    /// Dark mode: the svg drop-shadow color.
    let glyphShadow: UIColor
    let subText: UIColor
    let cancelBackground: UIColor
    let cancelBorder: UIColor
    let cancelText: UIColor
    /// Modal box-shadows: 0 30px 66px and 0 10px 22px.
    let outerShadow: UIColor
    let innerShadow: UIColor
    let iconCardTint: UIColor
    let iconCardShadow: UIColor
    let iconCardRing: UIColor
    let baseTop: UIColor
    let baseBottom: UIColor
    /// Modal sheen radial: white at this alpha at 0, fading out at sheenEnd.
    let sheenAlpha: CGFloat
    let sheenEnd: CGFloat
    let insetTop: UIColor
    let insetBottom: UIColor
    let edgeRing: UIColor

    static func make(banned: Bool, dark: Bool) -> PopupPalette {
        let brand: [UIColor] = banned
            ? [vpHex("#ff8a3d"), vpHex("#ff5b5b"), vpHex("#ff3d3d")]
            : [vpHex("#8a7bff"), vpHex("#3d8bff"), vpHex("#49c6fd")]
        let brandStops: [(UIColor, CGFloat)] = [(brand[0], 0), (brand[1], 0.5), (brand[2], 1)]
        if dark {
            return PopupPalette(
                heroStops: [],
                brandStops: brandStops,
                brandShadow: banned ? vpRGBA(230, 90, 90, 0.32) : vpRGBA(80, 120, 230, 0.32),
                titleStops: banned
                    ? [(vpHex("#ffd7c2"), 0), (vpHex("#ffaf9f"), 0.52), (vpHex("#ff9a97"), 1)]
                    : [(vpHex("#ded7ff"), 0), (vpHex("#9fcaff"), 0.52), (vpHex("#97e2ff"), 1)],
                iconStops: banned
                    ? [vpHex("#ff9d5c"), vpHex("#ff7d63"), vpHex("#ff5252")]
                    : [vpHex("#bb86ff"), vpHex("#849dff"), vpHex("#4fb5ff")],
                brandGlowStops: banned
                    ? [(vpRGBA(240, 112, 112, 0.34), 0), (vpRGBA(242, 126, 112, 0.19), 0.44),
                       (vpRGBA(250, 148, 84, 0.05), 0.74), (vpRGBA(253, 174, 73, 0), 1)]
                    : [(vpRGBA(130, 112, 240, 0.34), 0), (vpRGBA(112, 126, 242, 0.19), 0.44),
                       (vpRGBA(84, 148, 250, 0.05), 0.74), (vpRGBA(73, 174, 253, 0), 1)],
                glyphShadow: banned ? vpRGBA(255, 150, 110, 0.38) : vpRGBA(130, 160, 255, 0.38),
                subText: vpHex("#9d9da3"),
                cancelBackground: vpHex("#3a3a40"),
                cancelBorder: vpHex("#4a4a52"),
                cancelText: vpHex("#f2f2f4"),
                outerShadow: vpRGBA(0, 0, 0, 0.55),
                innerShadow: vpRGBA(0, 0, 0, 0.40),
                iconCardTint: vpRGBA(255, 255, 255, 0.16),
                iconCardShadow: vpRGBA(0, 0, 0, 0.34),
                iconCardRing: vpRGBA(255, 255, 255, 0.28),
                baseTop: vpHex("#2b2b30"),
                baseBottom: vpHex("#222226"),
                sheenAlpha: 0.05,
                sheenEnd: 0.52,
                insetTop: vpRGBA(255, 255, 255, 0.06),
                insetBottom: vpRGBA(0, 0, 0, 0.40),
                edgeRing: vpRGBA(255, 255, 255, 0.10)
            )
        }
        return PopupPalette(
            heroStops: banned
                ? [(vpHex("#ffb07a"), 0), (vpHex("#ff8a5b"), 0.26), (vpHex("#ff5b5b"), 0.48),
                   (vpRGBA(255, 91, 91, 0.45), 0.78), (vpRGBA(255, 91, 91, 0), 0.98)]
                : [(vpHex("#f9c0fc"), 0), (vpHex("#c9bdfa"), 0.26), (vpHex("#8fb4fb"), 0.48),
                   (vpRGBA(139, 180, 251, 0.45), 0.78), (vpRGBA(139, 180, 251, 0), 0.98)],
            brandStops: brandStops,
            brandShadow: banned ? vpRGBA(230, 90, 90, 0.32) : vpRGBA(80, 120, 230, 0.32),
            titleStops: [(brand[0], 0), (brand[1], 0.52), (brand[2], 1)],
            iconStops: banned
                ? [vpHex("#ff8a3d"), vpHex("#ff6a5b"), vpHex("#ff3d3d")]
                : [vpHex("#b07bf2"), vpHex("#6f8bf6"), vpHex("#49aefd")],
            brandGlowStops: [],
            glyphShadow: vpRGBA(130, 160, 255, 0),
            subText: vpHex("#afb1b2"),
            cancelBackground: vpHex("#ffffff"),
            cancelBorder: vpHex("#dedede"),
            cancelText: vpHex("#111111"),
            outerShadow: vpRGBA(120, 130, 150, 0.20),
            innerShadow: vpRGBA(120, 130, 150, 0.12),
            iconCardTint: vpRGBA(255, 255, 255, 0.44),
            iconCardShadow: vpRGBA(110, 145, 190, 0.14),
            iconCardRing: vpRGBA(255, 255, 255, 0.9),
            baseTop: vpHex("#ffffff"),
            baseBottom: vpHex("#ffffff"),
            sheenAlpha: 0.96,
            sheenEnd: 0.58,
            insetTop: vpRGBA(255, 255, 255, 0.95),
            insetBottom: vpRGBA(185, 192, 205, 0.13),
            edgeRing: vpRGBA(255, 255, 255, 0.7)
        )
    }
}

// MARK: - CSS cubic-bezier easing

private struct CSSBezier {
    let x1: Double, y1: Double, x2: Double, y2: Double

    func value(atX x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0 ..< 8 {
            let err = cubic(t, x1, x2) - x
            if abs(err) < 1e-6 { break }
            let slope = cubicSlope(t, x1, x2)
            if abs(slope) < 1e-6 { break }
            t -= err / slope
            t = min(max(t, 0), 1)
        }
        return cubic(t, y1, y2)
    }

    private func cubic(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
    }

    private func cubicSlope(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
    }
}

// MARK: - SVG polyline parsing (the designs' paths use only M / L / Z)

private final class SVGPolyline {
    let points: [CGPoint]
    let closed: Bool
    let totalLength: CGFloat
    let boundingBox: CGRect
    private let cumulative: [CGFloat]

    init(_ d: String) {
        var pts: [CGPoint] = []
        var isClosed = false
        var numbers: [Double] = []
        var buffer = ""
        func flushNumber() {
            if !buffer.isEmpty, let v = Double(buffer) { numbers.append(v) }
            buffer = ""
        }
        func flushPoints() {
            var i = 0
            while i + 1 < numbers.count {
                pts.append(CGPoint(x: numbers[i], y: numbers[i + 1]))
                i += 2
            }
            numbers.removeAll()
        }
        for ch in d {
            switch ch {
            case "M", "L", "m", "l":
                flushNumber()
                flushPoints()
            case "Z", "z":
                flushNumber()
                flushPoints()
                isClosed = true
            case " ", ",", "\n", "\t":
                flushNumber()
            default:
                buffer.append(ch)
            }
        }
        flushNumber()
        flushPoints()
        points = pts
        closed = isClosed
        var cum: [CGFloat] = [0]
        var total: CGFloat = 0
        for i in 1 ..< pts.count {
            total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            cum.append(total)
        }
        if isClosed, pts.count > 1 {
            total += hypot(pts[0].x - pts[pts.count - 1].x, pts[0].y - pts[pts.count - 1].y)
        }
        cumulative = cum
        totalLength = total
        if pts.isEmpty {
            boundingBox = .zero
        } else {
            var minX = pts[0].x, maxX = pts[0].x, minY = pts[0].y, maxY = pts[0].y
            for p in pts {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
            boundingBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    var fullPath: CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        if closed { path.closeSubpath() }
        return path
    }

    /// The sub-polyline covering the first `length` units of the path —
    /// the native equivalent of the designs' stroke-dashoffset reveal.
    func partialPath(upTo length: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if length <= 0 { return path }
        var remaining = length
        for i in 1 ..< points.count {
            let seg = cumulative[i] - cumulative[i - 1]
            if remaining >= seg {
                path.addLine(to: points[i])
                remaining -= seg
            } else {
                let a = points[i - 1], b = points[i]
                let t = seg > 0 ? remaining / seg : 0
                path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t,
                                         y: a.y + (b.y - a.y) * t))
                return path
            }
        }
        if closed, remaining > 0, points.count > 1 {
            let a = points[points.count - 1], b = points[0]
            let seg = hypot(b.x - a.x, b.y - a.y)
            if remaining >= seg {
                path.closeSubpath()
            } else {
                let t = seg > 0 ? remaining / seg : 0
                path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t,
                                         y: a.y + (b.y - a.y) * t))
            }
        }
        return path
    }
}

// MARK: - Glyph artwork (the designs' own SVG data, verbatim)

enum GlyphKind { case left, right }

/// One drawable piece of a glyph icon, mirroring one SVG element of the
/// design: either a stroked circle, or a filled path revealed through a
/// stroked centerline mask (the designs' draw-on mechanism). delay/duration
/// are the designs' data-d/data-t values, in seconds.
struct GlyphElementSpec {
    enum Body {
        case strokeCircle(cx: Double, cy: Double, r: Double, width: Double)
        case fill(path: String, evenOdd: Bool, maskPath: String, maskWidth: Double)
    }
    let body: Body
    let delay: Double
    let duration: Double
}

enum GlyphArtwork {
    /// Last draw-on element finishes at 1.56 + 0.20 (design data-t/data-d).
    static let totalDuration: Double = 1.76

    static let left: [GlyphElementSpec] = [
        GlyphElementSpec(body: .strokeCircle(cx: 99.5, cy: 45.34, r: 28.8, width: 11.93), delay: 0.25, duration: 0.38),
        GlyphElementSpec(body: .fill(path: "M17.0 176.5 L15.0 176.5 L14.0 175.5 L10.5 172.0 L10.5 170.0 L9.5 169.0 L9.5 168.0 L10.5 167.0 L10.5 160.0 L11.5 159.0 L11.5 156.0 L12.5 155.0 L12.5 152.0 L13.5 151.0 L13.5 149.0 L14.5 148.0 L14.5 147.0 L15.5 146.0 L15.5 144.0 L16.5 143.0 L16.5 142.0 L17.5 141.0 L17.5 140.0 L19.5 138.0 L19.5 137.0 L20.5 136.0 L20.5 135.0 L22.5 133.0 L22.5 132.0 L25.5 129.0 L25.5 128.0 L37.0 116.5 L38.0 116.5 L41.0 113.5 L42.0 113.5 L44.0 111.5 L45.0 111.5 L47.0 109.5 L48.0 109.5 L49.0 108.5 L50.0 108.5 L51.0 107.5 L52.0 107.5 L53.0 106.5 L54.0 106.5 L55.0 105.5 L56.0 105.5 L57.0 104.5 L58.0 104.5 L59.0 103.5 L61.0 103.5 L62.0 102.5 L64.0 102.5 L65.0 101.5 L67.0 101.5 L68.0 100.5 L71.0 100.5 L72.0 99.5 L75.0 99.5 L76.0 98.5 L82.0 98.5 L83.0 97.5 L92.0 97.5 L93.0 98.5 L94.0 98.5 L96.5 101.0 L96.5 102.0 L97.5 103.0 L97.5 104.0 L96.5 105.0 L96.5 106.0 L93.0 109.5 L90.0 109.5 L89.0 110.5 L77.0 110.5 L76.0 111.5 L72.0 111.5 L71.0 112.5 L69.0 112.5 L68.0 113.5 L65.0 113.5 L64.0 114.5 L63.0 114.5 L62.0 115.5 L60.0 115.5 L59.0 116.5 L58.0 116.5 L57.0 117.5 L56.0 117.5 L55.0 118.5 L54.0 118.5 L53.0 119.5 L52.0 119.5 L50.0 121.5 L49.0 121.5 L47.0 123.5 L46.0 123.5 L41.0 128.5 L40.0 128.5 L37.5 131.0 L37.5 132.0 L32.5 137.0 L32.5 138.0 L30.5 140.0 L30.5 141.0 L29.5 142.0 L29.5 143.0 L28.5 144.0 L28.5 145.0 L27.5 146.0 L27.5 147.0 L26.5 148.0 L26.5 149.0 L25.5 150.0 L25.5 152.0 L24.5 153.0 L24.5 155.0 L23.5 156.0 L23.5 161.0 L22.5 162.0 L22.5 171.0 L21.5 172.0 L21.5 173.0 L19.0 175.5 L18.0 175.5 L17.0 176.5Z", evenOdd: false, maskPath: "M94.5 93.9 L85.8 98.9 L84.8 99.4 L83.6 100.1 L82.3 101.0 L80.7 102.0 L79.4 103.0 L78.0 104.0 L76.6 105.0 L75.3 106.0 L73.6 107.0 L71.2 108.0 L68.5 109.0 L65.6 110.0 L62.6 111.0 L59.5 112.0 L56.4 113.0 L53.4 114.0 L51.1 115.0 L49.2 116.0 L47.4 117.0 L45.8 118.0 L44.2 119.0 L42.8 120.0 L41.4 121.0 L40.1 122.0 L38.9 123.0 L37.8 124.0 L36.6 125.0 L35.6 126.0 L34.5 127.0 L33.5 128.0 L32.6 129.0 L31.7 130.0 L30.9 131.0 L30.0 132.0 L29.2 133.0 L28.4 134.0 L27.8 135.0 L27.1 136.0 L26.3 137.0 L25.6 138.0 L25.0 139.0 L24.4 140.0 L23.9 141.0 L23.3 142.0 L22.8 143.0 L22.4 144.0 L21.9 145.0 L21.4 146.0 L20.9 147.0 L20.6 148.0 L20.1 149.0 L19.7 150.0 L19.4 151.0 L19.1 152.0 L18.7 153.0 L18.4 154.0 L18.1 155.0 L17.9 156.0 L17.7 157.0 L17.5 158.0 L17.2 159.0 L17.1 160.0 L16.9 161.0 L16.8 162.0 L16.6 163.0 L16.6 164.0 L16.4 165.0 L16.4 166.0 L16.4 167.0 L16.4 168.0 L16.3 169.0 L16.3 170.0 L16.3 171.0 L16.4 172.0 L16.4 173.0 L16.3 173.9 L16.2 174.6 L16.2 175.1 L16.2 185.1", maskWidth: 28.8), delay: 0.52, duration: 0.48),
        GlyphElementSpec(body: .fill(path: "M130.0 180.5 L111.0 180.5 L110.0 179.5 L109.0 179.5 L106.5 177.0 L106.5 175.0 L105.5 174.0 L105.5 158.0 L106.5 157.0 L106.5 156.0 L152.0 110.5 L155.0 110.5 L156.0 111.5 L157.0 111.5 L175.5 130.0 L175.5 131.0 L176.5 132.0 L176.5 134.0 L130.0 180.5Z M126.5 168.0 L127.0 167.5 L128.0 167.5 L160.5 135.0 L160.5 131.0 L156.0 126.5 L151.0 126.5 L118.5 159.0 L118.5 168.0 L119.0 168.5 L126.0 168.5 L126.5 168.0Z", evenOdd: true, maskPath: "M152.1 101.7 L153.7 111.6 L153.8 112.2 L153.9 113.0 L154.0 114.0 L154.0 115.0 L154.0 116.0 L154.0 117.0 L154.0 118.0 L154.0 119.0 L154.0 120.0 L154.0 121.0 L154.0 122.0 L154.0 123.0 L154.0 124.0 L154.0 125.0 L154.0 126.0 L154.0 127.0 L154.0 128.0 L153.9 129.0 L153.8 130.0 L153.6 131.0 L153.3 132.0 L152.8 133.0 L152.2 134.0 L151.4 135.0 L150.5 136.0 L149.5 137.0 L148.5 138.0 L147.5 139.0 L146.5 140.0 L145.5 141.0 L144.5 142.0 L143.5 143.0 L142.5 144.0 L141.5 145.0 L140.5 146.0 L139.5 147.0 L138.5 148.0 L137.5 149.0 L136.5 150.0 L135.5 151.0 L134.5 152.0 L133.5 153.0 L132.5 154.0 L131.6 155.0 L130.7 156.0 L129.9 157.0 L129.2 158.0 L128.6 159.0 L128.0 160.0 L127.5 161.0 L127.0 162.0 L126.5 163.0 L126.0 164.0 L125.5 165.0 L125.0 166.0 L124.5 167.0 L124.0 168.0 L123.5 169.0 L123.0 170.0 L122.5 171.0 L122.0 172.0 L121.6 173.0 L121.2 174.0 L120.8 175.0 L120.5 176.0 L120.3 177.0 L120.2 178.0 L120.2 178.8 L120.3 179.4 L121.9 189.3", maskWidth: 49.1), delay: 0.88, duration: 0.4),
    ]
    static let right: [GlyphElementSpec] = [
        GlyphElementSpec(body: .strokeCircle(cx: 99.5, cy: 99.5, r: 82.99, width: 12.05), delay: 0.38, duration: 0.38),
        GlyphElementSpec(body: .fill(path: "M139.0 93.5 L138.0 92.5 L137.0 92.5 L133.5 89.0 L133.5 87.0 L132.5 86.0 L132.5 85.0 L131.5 84.0 L131.5 82.0 L129.5 80.0 L129.5 79.0 L126.5 76.0 L126.5 75.0 L124.0 72.5 L123.0 72.5 L120.0 69.5 L119.0 69.5 L117.0 67.5 L115.0 67.5 L114.0 66.5 L113.0 66.5 L112.0 65.5 L109.0 65.5 L108.0 64.5 L91.0 64.5 L90.0 65.5 L87.0 65.5 L86.0 66.5 L85.0 66.5 L84.0 67.5 L82.0 67.5 L80.0 69.5 L79.0 69.5 L76.0 72.5 L75.0 72.5 L72.5 75.0 L72.5 76.0 L69.5 79.0 L69.5 80.0 L67.5 82.0 L67.5 84.0 L66.5 85.0 L66.5 86.0 L65.5 87.0 L65.5 89.0 L62.0 92.5 L61.0 92.5 L60.0 93.5 L59.0 92.5 L58.0 92.5 L57.0 91.5 L56.0 91.5 L55.5 91.0 L55.5 90.0 L53.5 88.0 L53.5 86.0 L54.5 85.0 L54.5 84.0 L55.5 83.0 L55.5 81.0 L56.5 80.0 L56.5 79.0 L57.5 78.0 L57.5 77.0 L59.5 75.0 L59.5 74.0 L61.5 72.0 L61.5 71.0 L71.0 61.5 L72.0 61.5 L74.0 59.5 L75.0 59.5 L77.0 57.5 L78.0 57.5 L79.0 56.5 L80.0 56.5 L81.0 55.5 L83.0 55.5 L84.0 54.5 L85.0 54.5 L86.0 53.5 L89.0 53.5 L90.0 52.5 L94.0 52.5 L95.0 51.5 L104.0 51.5 L105.0 52.5 L109.0 52.5 L110.0 53.5 L113.0 53.5 L114.0 54.5 L115.0 54.5 L116.0 55.5 L118.0 55.5 L119.0 56.5 L120.0 56.5 L121.0 57.5 L122.0 57.5 L124.0 59.5 L125.0 59.5 L127.0 61.5 L128.0 61.5 L129.0 62.5 L133.0 62.5 L133.5 62.0 L133.5 60.0 L137.0 56.5 L138.0 56.5 L139.0 55.5 L140.0 56.5 L141.0 56.5 L142.0 57.5 L143.0 57.5 L143.5 58.0 L143.5 59.0 L145.5 61.0 L145.5 88.0 L143.5 90.0 L143.5 91.0 L143.0 91.5 L142.0 91.5 L141.0 92.5 L140.0 92.5 L139.0 93.5Z", evenOdd: false, maskPath: "M55.0 93.1 L59.4 86.4 L59.8 85.8 L60.2 85.0 L60.8 84.0 L61.2 83.0 L61.8 82.0 L62.2 81.0 L62.8 80.0 L63.4 79.0 L64.0 78.0 L64.6 77.0 L65.4 76.0 L66.2 75.0 L66.8 74.0 L67.6 73.0 L68.4 72.0 L69.2 71.0 L70.0 70.0 L71.0 69.2 L72.0 68.4 L73.0 67.6 L74.0 66.8 L75.0 66.2 L76.0 65.4 L77.0 64.6 L78.0 64.0 L79.0 63.4 L80.0 62.8 L81.0 62.2 L82.0 61.8 L83.0 61.4 L84.0 61.0 L85.0 60.6 L86.0 60.4 L87.0 60.0 L88.0 59.6 L89.0 59.4 L90.0 59.2 L91.0 59.0 L92.0 59.0 L93.0 59.0 L94.0 58.8 L95.0 58.6 L96.0 58.4 L97.0 58.2 L98.0 58.0 L99.0 58.0 L100.0 58.0 L101.0 58.0 L102.0 58.2 L103.0 58.4 L104.0 58.6 L105.0 58.8 L106.0 59.0 L107.0 59.0 L108.0 59.0 L109.0 59.2 L110.0 59.4 L111.0 59.6 L112.0 60.0 L113.0 60.4 L114.0 60.6 L115.0 61.0 L116.0 61.4 L117.0 61.8 L118.0 62.2 L119.0 62.8 L120.0 63.2 L121.0 63.8 L122.0 64.4 L123.0 65.0 L124.0 65.6 L125.0 66.2 L126.0 66.6 L127.0 66.8 L128.0 67.2 L129.0 67.4 L130.0 67.6 L131.0 68.0 L132.0 68.4 L133.0 68.8 L134.0 69.2 L135.0 69.8 L135.8 70.4 L136.6 71.2 L137.2 72.0 L137.6 73.0 L137.8 74.0 L138.0 75.0 L138.2 76.0 L138.4 77.0 L138.6 78.0 L138.8 79.0 L139.0 80.0 L139.0 81.0 L139.0 81.8 L139.0 82.4 L139.0 90.4", maskWidth: 26), delay: 0.7, duration: 0.48),
        GlyphElementSpec(body: .fill(path: "M139.0 93.5 L138.0 92.5 L137.0 92.5 L133.5 89.0 L133.5 87.0 L132.5 86.0 L132.5 85.0 L131.5 84.0 L131.5 82.0 L129.5 80.0 L129.5 79.0 L126.5 76.0 L126.5 75.0 L124.0 72.5 L123.0 72.5 L120.0 69.5 L119.0 69.5 L117.0 67.5 L115.0 67.5 L114.0 66.5 L113.0 66.5 L112.0 65.5 L109.0 65.5 L108.0 64.5 L91.0 64.5 L90.0 65.5 L87.0 65.5 L86.0 66.5 L85.0 66.5 L84.0 67.5 L82.0 67.5 L80.0 69.5 L79.0 69.5 L76.0 72.5 L75.0 72.5 L72.5 75.0 L72.5 76.0 L69.5 79.0 L69.5 80.0 L67.5 82.0 L67.5 84.0 L66.5 85.0 L66.5 86.0 L65.5 87.0 L65.5 89.0 L62.0 92.5 L61.0 92.5 L60.0 93.5 L59.0 92.5 L58.0 92.5 L57.0 91.5 L56.0 91.5 L55.5 91.0 L55.5 90.0 L53.5 88.0 L53.5 86.0 L54.5 85.0 L54.5 84.0 L55.5 83.0 L55.5 81.0 L56.5 80.0 L56.5 79.0 L57.5 78.0 L57.5 77.0 L59.5 75.0 L59.5 74.0 L61.5 72.0 L61.5 71.0 L71.0 61.5 L72.0 61.5 L74.0 59.5 L75.0 59.5 L77.0 57.5 L78.0 57.5 L79.0 56.5 L80.0 56.5 L81.0 55.5 L83.0 55.5 L84.0 54.5 L85.0 54.5 L86.0 53.5 L89.0 53.5 L90.0 52.5 L94.0 52.5 L95.0 51.5 L104.0 51.5 L105.0 52.5 L109.0 52.5 L110.0 53.5 L113.0 53.5 L114.0 54.5 L115.0 54.5 L116.0 55.5 L118.0 55.5 L119.0 56.5 L120.0 56.5 L121.0 57.5 L122.0 57.5 L124.0 59.5 L125.0 59.5 L127.0 61.5 L128.0 61.5 L129.0 62.5 L133.0 62.5 L133.5 62.0 L133.5 60.0 L137.0 56.5 L138.0 56.5 L139.0 55.5 L140.0 56.5 L141.0 56.5 L142.0 57.5 L143.0 57.5 L143.5 58.0 L143.5 59.0 L145.5 61.0 L145.5 88.0 L143.5 90.0 L143.5 91.0 L143.0 91.5 L142.0 91.5 L141.0 92.5 L140.0 92.5 L139.0 93.5Z", evenOdd: false, maskPath: "M135.1 75.7 L137.0 70.0 L140.0 61.0 L141.9 55.3", maskWidth: 13.5), delay: 1.35, duration: 0.2),
        GlyphElementSpec(body: .fill(path: "M104.0 147.5 L95.0 147.5 L94.0 146.5 L90.0 146.5 L89.0 145.5 L86.0 145.5 L85.0 144.5 L84.0 144.5 L83.0 143.5 L81.0 143.5 L80.0 142.5 L79.0 142.5 L78.0 141.5 L77.0 141.5 L75.0 139.5 L74.0 139.5 L72.0 137.5 L71.0 137.5 L70.0 136.5 L66.0 136.5 L65.5 137.0 L65.5 139.0 L62.0 142.5 L61.0 142.5 L60.0 143.5 L59.0 142.5 L58.0 142.5 L57.0 141.5 L56.0 141.5 L55.5 141.0 L55.5 140.0 L53.5 138.0 L53.5 111.0 L55.5 109.0 L55.5 108.0 L56.0 107.5 L57.0 107.5 L58.0 106.5 L59.0 106.5 L60.0 105.5 L61.0 106.5 L62.0 106.5 L65.5 110.0 L65.5 112.0 L66.5 113.0 L66.5 114.0 L67.5 115.0 L67.5 117.0 L69.5 119.0 L69.5 120.0 L72.5 123.0 L72.5 124.0 L75.0 126.5 L76.0 126.5 L79.0 129.5 L80.0 129.5 L82.0 131.5 L84.0 131.5 L85.0 132.5 L86.0 132.5 L87.0 133.5 L90.0 133.5 L91.0 134.5 L108.0 134.5 L109.0 133.5 L112.0 133.5 L113.0 132.5 L114.0 132.5 L115.0 131.5 L117.0 131.5 L119.0 129.5 L120.0 129.5 L123.0 126.5 L124.0 126.5 L126.5 124.0 L126.5 123.0 L129.5 120.0 L129.5 119.0 L131.5 117.0 L131.5 115.0 L132.5 114.0 L132.5 113.0 L133.5 112.0 L133.5 110.0 L137.0 106.5 L138.0 106.5 L139.0 105.5 L140.0 106.5 L141.0 106.5 L142.0 107.5 L143.0 107.5 L143.5 108.0 L143.5 109.0 L145.5 111.0 L145.5 113.0 L144.5 114.0 L144.5 115.0 L143.5 116.0 L143.5 118.0 L142.5 119.0 L142.5 120.0 L141.5 121.0 L141.5 122.0 L139.5 124.0 L139.5 125.0 L137.5 127.0 L137.5 128.0 L128.0 137.5 L127.0 137.5 L125.0 139.5 L124.0 139.5 L122.0 141.5 L121.0 141.5 L120.0 142.5 L119.0 142.5 L118.0 143.5 L116.0 143.5 L115.0 144.5 L114.0 144.5 L113.0 145.5 L110.0 145.5 L109.0 146.5 L105.0 146.5 L104.0 147.5Z", evenOdd: false, maskPath: "M144.0 104.9 L139.6 111.6 L139.2 112.2 L138.8 113.0 L138.4 114.0 L138.0 115.0 L137.6 116.0 L137.2 117.0 L136.6 118.0 L136.0 119.0 L135.6 120.0 L135.0 121.0 L134.4 122.0 L134.0 123.0 L133.4 124.0 L132.6 125.0 L131.8 126.0 L131.0 127.0 L130.0 128.0 L129.0 129.0 L128.0 130.0 L127.0 131.0 L126.0 131.8 L125.0 132.6 L124.0 133.4 L123.0 134.0 L122.0 134.4 L121.0 135.0 L120.0 135.6 L119.0 136.0 L118.0 136.6 L117.0 137.2 L116.0 137.6 L115.0 138.0 L114.0 138.4 L113.0 138.6 L112.0 138.8 L111.0 139.0 L110.0 139.2 L109.0 139.4 L108.0 139.6 L107.0 139.8 L106.0 140.0 L105.0 140.0 L104.0 140.0 L103.0 140.0 L102.0 140.0 L101.0 140.0 L100.0 140.0 L99.0 140.0 L98.0 140.0 L97.0 140.0 L96.0 140.0 L95.0 140.0 L94.0 140.0 L93.0 140.0 L92.0 139.8 L91.0 139.6 L90.0 139.4 L89.0 139.2 L88.0 139.0 L87.0 138.8 L86.0 138.6 L85.0 138.4 L84.0 138.0 L83.0 137.6 L82.0 137.2 L81.0 136.6 L80.0 136.0 L79.0 135.4 L78.0 134.8 L77.0 134.2 L76.0 133.6 L75.0 133.0 L74.0 132.6 L73.0 132.0 L72.0 131.6 L71.0 131.4 L70.0 131.2 L69.0 130.8 L68.0 130.6 L67.0 130.2 L66.0 129.8 L65.0 129.4 L64.0 129.0 L63.0 128.4 L62.2 127.8 L61.6 127.0 L61.0 126.0 L60.6 125.0 L60.4 124.0 L60.2 123.0 L60.0 122.0 L60.0 121.0 L59.8 120.0 L59.6 119.0 L59.6 118.0 L59.6 117.0 L59.6 116.0 L59.8 115.0 L59.8 114.0 L59.6 113.0 L59.4 112.2 L59.2 111.6 L56.7 104.0", maskWidth: 25.9), delay: 1.05, duration: 0.48),
        GlyphElementSpec(body: .fill(path: "M104.0 147.5 L95.0 147.5 L94.0 146.5 L90.0 146.5 L89.0 145.5 L86.0 145.5 L85.0 144.5 L84.0 144.5 L83.0 143.5 L81.0 143.5 L80.0 142.5 L79.0 142.5 L78.0 141.5 L77.0 141.5 L75.0 139.5 L74.0 139.5 L72.0 137.5 L71.0 137.5 L70.0 136.5 L66.0 136.5 L65.5 137.0 L65.5 139.0 L62.0 142.5 L61.0 142.5 L60.0 143.5 L59.0 142.5 L58.0 142.5 L57.0 141.5 L56.0 141.5 L55.5 141.0 L55.5 140.0 L53.5 138.0 L53.5 111.0 L55.5 109.0 L55.5 108.0 L56.0 107.5 L57.0 107.5 L58.0 106.5 L59.0 106.5 L60.0 105.5 L61.0 106.5 L62.0 106.5 L65.5 110.0 L65.5 112.0 L66.5 113.0 L66.5 114.0 L67.5 115.0 L67.5 117.0 L69.5 119.0 L69.5 120.0 L72.5 123.0 L72.5 124.0 L75.0 126.5 L76.0 126.5 L79.0 129.5 L80.0 129.5 L82.0 131.5 L84.0 131.5 L85.0 132.5 L86.0 132.5 L87.0 133.5 L90.0 133.5 L91.0 134.5 L108.0 134.5 L109.0 133.5 L112.0 133.5 L113.0 132.5 L114.0 132.5 L115.0 131.5 L117.0 131.5 L119.0 129.5 L120.0 129.5 L123.0 126.5 L124.0 126.5 L126.5 124.0 L126.5 123.0 L129.5 120.0 L129.5 119.0 L131.5 117.0 L131.5 115.0 L132.5 114.0 L132.5 113.0 L133.5 112.0 L133.5 110.0 L137.0 106.5 L138.0 106.5 L139.0 105.5 L140.0 106.5 L141.0 106.5 L142.0 107.5 L143.0 107.5 L143.5 108.0 L143.5 109.0 L145.5 111.0 L145.5 113.0 L144.5 114.0 L144.5 115.0 L143.5 116.0 L143.5 118.0 L142.5 119.0 L142.5 120.0 L141.5 121.0 L141.5 122.0 L139.5 124.0 L139.5 125.0 L137.5 127.0 L137.5 128.0 L128.0 137.5 L127.0 137.5 L125.0 139.5 L124.0 139.5 L122.0 141.5 L121.0 141.5 L120.0 142.5 L119.0 142.5 L118.0 143.5 L116.0 143.5 L115.0 144.5 L114.0 144.5 L113.0 145.5 L110.0 145.5 L109.0 146.5 L105.0 146.5 L104.0 147.5Z", evenOdd: false, maskPath: "M62.3 122.1 L61.0 128.0 L59.0 137.0 L57.7 142.9", maskWidth: 13.3), delay: 1.56, duration: 0.2),
    ]
}

// MARK: - Glyph rendering (the designs' SVG semantics, drawn with CG)

private enum GlyphRenderer {
    private static var cache: [String: SVGPolyline] = [:]

    private static func polyline(_ d: String) -> SVGPolyline {
        if let cached = cache[d] { return cached }
        let parsed = SVGPolyline(d)
        cache[d] = parsed
        return parsed
    }

    /// Renders one glyph at the given draw-on moment. Each element's reveal
    /// progress follows the designs' script: delay data-d, duration data-t,
    /// easing cubic-bezier(.35,.55,.35,1), fill both — before the delay the
    /// element is invisible, after its duration it rests fully drawn.
    ///
    /// Every element is composed like its SVG original: a gradient base
    /// (for fills, clipped to the fill path) whose alpha is then cut by the
    /// revealed centerline stroke — the SVG mask — via destination-in
    /// stroking. Pure CG path painting honors the context blend mode
    /// exactly, unlike the Build 8 approach.
    static func image(kind: GlyphKind, pointSize: CGSize, scale: CGFloat,
                      iconStops: [UIColor], dark: Bool,
                      trait: UITraitCollection, elapsed: Double) -> UIImage {
        let elements = kind == .left ? GlyphArtwork.left : GlyphArtwork.right
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let stops = iconStops.map { $0.resolvedColor(with: trait) }
        // viewBox is 0 0 200 200 in both designs.
        let unit = pointSize.width / 200
        let full = CGRect(x: 0, y: 0, width: 200, height: 200)
        func canvas(_ draw: (CGContext) -> Void) -> UIImage {
            UIGraphicsImageRenderer(size: pointSize, format: format).image { context in
                context.cgContext.scaleBy(x: unit, y: unit)
                draw(context.cgContext)
            }
        }
        var image = UIGraphicsImageRenderer(size: pointSize, format: format).image { context in
            let ctx = context.cgContext
            ctx.scaleBy(x: unit, y: unit)
            let easing = CSSBezier(x1: 0.35, y1: 0.55, x2: 0.35, y2: 1)
            for element in elements {
                let raw = (elapsed - element.delay) / element.duration
                let progress = easing.value(atX: min(max(raw, 0), 1))
                if progress <= 0 { continue }
                let composed: UIImage
                switch element.body {
                case let .strokeCircle(cx, cy, r, width):
                    let bbox = CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)
                    let base = canvas { c in
                        drawIconGradient(c, bbox: bbox, stops: stops)
                    }
                    let arc = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy),
                                           radius: CGFloat(r),
                                           startAngle: 0,
                                           endAngle: CGFloat(progress) * 2 * .pi,
                                           clockwise: true)
                    composed = canvas { c in
                        base.draw(in: full)
                        strokeReveal(c, path: arc.cgPath, width: width)
                    }
                case let .fill(pathD, evenOdd, maskD, maskWidth):
                    let fillLine = polyline(pathD)
                    let base = canvas { c in
                        c.saveGState()
                        c.addPath(fillLine.fullPath)
                        c.clip(using: evenOdd ? .evenOdd : .winding)
                        drawIconGradient(c, bbox: fillLine.boundingBox, stops: stops)
                        c.restoreGState()
                    }
                    let maskLine = polyline(maskD)
                    let revealed = maskLine.partialPath(
                        upTo: CGFloat(progress) * maskLine.totalLength)
                    composed = canvas { c in
                        base.draw(in: full)
                        strokeReveal(c, path: revealed, width: maskWidth)
                    }
                }
                composed.draw(in: full)
            }
        }
        if dark {
            // .card svg { filter: saturate(1.55) ... } in the dark CSS.
            image = saturate(image, factor: 1.55, scale: scale) ?? image
        }
        return image
    }

    /// Cuts the canvas down to where the revealed centerline stroke lies:
    /// stroking with destination-in keeps the destination only under the
    /// stroke (butt caps, miter joins, miter limit 4 — the SVG defaults).
    private static func strokeReveal(_ ctx: CGContext, path: CGPath, width: Double) {
        ctx.saveGState()
        ctx.setBlendMode(.destinationIn)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineCap(.butt)
        ctx.setLineJoin(.miter)
        ctx.setMiterLimit(4)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// The designs' iconGrad: linearGradient x1 .08 y1 0 → x2 .92 y2 1 in
    /// objectBoundingBox units of the element being painted.
    private static func drawIconGradient(_ ctx: CGContext, bbox: CGRect, stops: [UIColor]) {
        guard stops.count > 1 else { return }
        let colors = stops.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: [0, 0.5, 1]) else { return }
        let start = CGPoint(x: bbox.minX + 0.08 * bbox.width, y: bbox.minY)
        let end = CGPoint(x: bbox.minX + 0.92 * bbox.width, y: bbox.minY + bbox.height)
        // SVG gradients pad their end colors (spreadMethod="pad").
        ctx.drawLinearGradient(gradient, start: start, end: end,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func saturate(_ image: UIImage, factor: Double, scale: CGFloat) -> UIImage? {
        guard let input = CIImage(image: image),
              let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(factor, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}


// MARK: - Baked card art (modal background + hero band, from the CSS)

private enum BakedArt {
    /// CSS linear-gradient endpoints for an angle in a rect (y-down space):
    /// 0deg points up, angles grow clockwise, the gradient line is sized so
    /// its stops land exactly as CSS computes them.
    static func cssEndpoints(angleDeg: Double, rect: CGRect) -> (CGPoint, CGPoint) {
        let rad = CGFloat(angleDeg * .pi / 180)
        let dir = CGPoint(x: sin(rad), y: -cos(rad))
        let length = abs(rect.width * dir.x) + abs(rect.height * dir.y)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return (CGPoint(x: center.x - dir.x * length / 2,
                        y: center.y - dir.y * length / 2),
                CGPoint(x: center.x + dir.x * length / 2,
                        y: center.y + dir.y * length / 2))
    }

    /// Elliptical radial gradient, like CSS radial-gradient(rx ry at cx cy).
    static func drawRadial(_ ctx: CGContext, center: CGPoint, rx: CGFloat, ry: CGFloat,
                           colors: [CGColor], locations: [CGFloat]) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray,
                                        locations: locations) else { return }
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: rx, y: ry)
        ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: 1,
                               options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    static func modalBackground(size: CGSize, s: CGFloat, palette: PopupPalette,
                                dark: Bool, trait: UITraitCollection) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = trait.displayScale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            func resolved(_ color: UIColor) -> CGColor {
                color.resolvedColor(with: trait).cgColor
            }
            // Base: linear-gradient(180deg, baseTop, baseBottom).
            if dark {
                let colors = [resolved(palette.baseTop), resolved(palette.baseBottom)] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: colors, locations: [0, 1]) {
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                                           end: CGPoint(x: 0, y: size.height), options: [])
                }
            } else {
                ctx.setFillColor(resolved(palette.baseTop))
                ctx.fill(rect)
            }
            // Sheen: radial-gradient(140% 70% at 50% -12%, white, transparent).
            drawRadial(ctx,
                       center: CGPoint(x: size.width * 0.5, y: -size.height * 0.12),
                       rx: size.width * 1.40, ry: size.height * 0.70,
                       colors: [vpRGBA(255, 255, 255, palette.sheenAlpha).cgColor,
                                vpRGBA(255, 255, 255, 0).cgColor],
                       locations: [0, palette.sheenEnd])
            // Dark: brand glow baked into the modal background (hero hidden):
            // radial-gradient(118% 42% at 50% -6%, brand stops).
            if dark {
                drawRadial(ctx,
                           center: CGPoint(x: size.width * 0.5, y: -size.height * 0.06),
                           rx: size.width * 1.18, ry: size.height * 0.42,
                           colors: palette.brandGlowStops.map { resolved($0.0) },
                           locations: palette.brandGlowStops.map { $0.1 })
            }
            // Inset shadows, approximated as edge gradient bands spanning
            // the designs' offset + blur extents.
            drawInsetBand(ctx, rect: rect,
                          color: palette.insetTop.resolvedColor(with: trait),
                          height: 11 * s, atTop: true)
            drawInsetBand(ctx, rect: rect,
                          color: palette.insetBottom.resolvedColor(with: trait),
                          height: 78 * s, atTop: false)
            // inset 0 0 0 1px edge ring.
            let ringRect = rect.insetBy(dx: 0.5 * s, dy: 0.5 * s)
            let ringPath = UIBezierPath(roundedRect: ringRect,
                                        cornerRadius: max(88 * s - 0.5 * s, 0))
            ctx.setStrokeColor(resolved(palette.edgeRing))
            ctx.setLineWidth(1 * s)
            ctx.addPath(ringPath.cgPath)
            ctx.strokePath()
        }
    }

    private static func drawInsetBand(_ ctx: CGContext, rect: CGRect, color: UIColor,
                                      height: CGFloat, atTop: Bool) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        let solid = CGColor(red: red, green: green, blue: blue, alpha: alpha)
        let clear = CGColor(red: red, green: green, blue: blue, alpha: 0)
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [solid, clear] as CFArray,
                                        locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        if atTop {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: height), options: [])
        } else {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.height),
                                   end: CGPoint(x: 0, y: rect.height - height), options: [])
        }
        ctx.restoreGState()
    }

    static func hero(size: CGSize, s: CGFloat, palette: PopupPalette,
                     trait: UITraitCollection) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = trait.displayScale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            func resolved(_ color: UIColor) -> CGColor {
                color.resolvedColor(with: trait).cgColor
            }
            // linear-gradient(180deg, hero stops).
            let colors = palette.heroStops.map { resolved($0.0) } as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: palette.heroStops.map { $0.1 }) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                                       end: CGPoint(x: 0, y: size.height), options: [])
            }
            // radial-gradient(60% 78% at 52% 22%, white glow).
            drawRadial(ctx,
                       center: CGPoint(x: size.width * 0.52, y: size.height * 0.22),
                       rx: size.width * 0.60, ry: size.height * 0.78,
                       colors: [vpRGBA(255, 255, 255, 0.88).cgColor,
                                vpRGBA(255, 255, 255, 0.22).cgColor,
                                vpRGBA(255, 255, 255, 0).cgColor],
                       locations: [0, 0.34, 0.64])
            // .hero::after streak, blurred by 26 design px as in the CSS.
            if let streak = streakImage(size: size, s: s, trait: trait) {
                streak.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    /// The ::after band: left 52%, top -55%, width 42%, height 220%,
    /// background linear-gradient(150deg, transparent, white .55,
    /// transparent), transform rotate(24deg), filter blur(26px).
    private static func streakImage(size: CGSize, s: CGFloat,
                                    trait: UITraitCollection) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = trait.displayScale
        format.opaque = false
        let band = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            let bandRect = CGRect(x: -size.width * 0.21, y: -size.height * 1.1,
                                  width: size.width * 0.42, height: size.height * 2.2)
            ctx.translateBy(x: size.width * 0.73, y: size.height * 0.55)
            ctx.rotate(by: 24 * .pi / 180)
            let (start, end) = cssEndpoints(angleDeg: 150, rect: bandRect)
            let colors = [vpRGBA(255, 255, 255, 0).cgColor,
                          vpRGBA(255, 255, 255, 0.55).cgColor,
                          vpRGBA(255, 255, 255, 0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
            }
        }
        guard let ci = CIImage(image: band),
              let clamp = CIFilter(name: "CIAffineClamp"),
              let blur = CIFilter(name: "CIGaussianBlur") else { return band }
        clamp.setValue(ci, forKey: kCIInputImageKey)
        clamp.setValue(CGAffineTransform.identity, forKey: kCIInputTransformKey)
        guard let clamped = clamp.outputImage else { return band }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(26 * s * trait.displayScale, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage else { return band }
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(output, from: ci.extent) else { return band }
        return UIImage(cgImage: cgImage, scale: trait.displayScale, orientation: .up)
    }
}

// MARK: - Gradient title (line 1): text baked into an image, filled with
// the design's 90deg gradient via clip-to-mask — no layer masks on labels.

private enum TitleRenderer {
    static func image(text: String, font: UIFont,
                      stops: [(UIColor, CGFloat)],
                      trait: UITraitCollection) -> UIImage? {
        guard !text.isEmpty else { return nil }
        let measureAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: measureAttrs)
        let canvas = CGSize(width: ceil(textSize.width), height: ceil(font.lineHeight))
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = trait.displayScale
        format.opaque = false
        let maskImage = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            (text as NSString).draw(in: CGRect(origin: .zero, size: canvas),
                                    withAttributes: attrs)
        }
        guard let mask = maskImage.cgImage else { return nil }
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let ctx = context.cgContext
            let rect = CGRect(origin: .zero, size: canvas)
            ctx.clip(to: rect, mask: mask)
            let colors = stops.map { $0.0.resolvedColor(with: trait).cgColor } as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors,
                                            locations: stops.map { $0.1 }) else { return }
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: canvas.height / 2),
                                   end: CGPoint(x: canvas.width, y: canvas.height / 2),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
    let tint = UIView()
    let ring = CAShapeLayer()
    let glyph = UIImageView()
}

final class VersionPopupViewController: UIViewController {
    var onDismiss: (() -> Void)?

    private let payload: VersionPopup.Payload
    private var palette: PopupPalette
    private var dark = false
    /// Design px → points, as in the designs' fit(): min(vw/1080, vh/1918).
    private var s: CGFloat = 0.36

    private let shadowOuter = UIView()
    private let shadowInner = UIView()
    private let cardView = UIView()
    private let bgImageView = UIImageView()
    private let heroView = UIView()
    private let heroImageView = UIImageView()
    private let cardL = IconCard()
    private let cardR = IconCard()
    private let titleView = UIImageView()
    private let line2 = UILabel()
    private let line3 = UILabel()
    private let leftButton = UIButton(type: .custom)
    private let rightButton = UIButton(type: .custom)
    private let rightGradient = CAGradientLayer()

    private var scaledConstraints: [(NSLayoutConstraint, CGFloat)] = []
    private var titleTop: NSLayoutConstraint!
    private var titleWidth: NSLayoutConstraint!
    private var titleHeight: NSLayoutConstraint!
    private var line2Top: NSLayoutConstraint!
    private var line3Top: NSLayoutConstraint!
    private var line2Height: NSLayoutConstraint!
    private var line3Height: NSLayoutConstraint!

    private var lastCardSize: CGSize = .zero
    private var entranceBegan = false
    private var glyphStart: CFTimeInterval = 0
    private var glyphElapsed: Double = .greatestFiniteMagnitude
    private var glyphLink: CADisplayLink?

    init(payload: VersionPopup.Payload) {
        self.payload = payload
        self.palette = PopupPalette.make(banned: payload.banned, dark: false)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { glyphLink?.invalidate() }

    // MARK: Build

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dark = traitCollection.userInterfaceStyle == .dark

        shadowInner.addSubview(cardView)
        shadowOuter.addSubview(shadowInner)
        view.addSubview(shadowOuter)
        cardView.clipsToBounds = true
        cardView.addSubview(bgImageView)
        heroView.addSubview(heroImageView)
        cardView.addSubview(heroView)

        for icon in [cardL, cardR] {
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            icon.clip.addSubview(blurView)
            icon.clip.addSubview(icon.tint)
            icon.clip.clipsToBounds = true
            icon.clip.layer.addSublayer(icon.ring)
            icon.ring.fillColor = nil
            icon.card.addSubview(icon.clip)
            icon.card.addSubview(icon.glyph)
            icon.wrap.addSubview(icon.card)
            cardView.addSubview(icon.wrap)
            pinEdges(blurView, to: icon.clip)
            pinEdges(icon.tint, to: icon.clip)
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
        cardL.card.transform = CGAffineTransform(rotationAngle: -8 * .pi / 180)
        cardR.card.transform = CGAffineTransform(rotationAngle: 6 * .pi / 180)

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
        rightButton.layer.insertSublayer(rightGradient, at: 0)
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
        for v in [shadowOuter, shadowInner, cardView, bgImageView, heroView,
                  heroImageView, titleView, line2, line3, leftButton, rightButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        activate(shadowOuter.centerXAnchor.constraint(equalTo: view.centerXAnchor))
        activate(shadowOuter.centerYAnchor.constraint(equalTo: view.centerYAnchor))
        pin(shadowOuter.widthAnchor.constraint(equalToConstant: 0), px: 835)
        pin(shadowOuter.heightAnchor.constraint(equalToConstant: 0), px: 728)
        pinEdges(shadowInner, to: shadowOuter)
        pinEdges(cardView, to: shadowInner)
        pinEdges(bgImageView, to: cardView)
        activate(heroView.leftAnchor.constraint(equalTo: cardView.leftAnchor))
        activate(heroView.rightAnchor.constraint(equalTo: cardView.rightAnchor))
        activate(heroView.topAnchor.constraint(equalTo: cardView.topAnchor))
        pin(heroView.heightAnchor.constraint(equalToConstant: 0), px: 335)
        pinEdges(heroImageView, to: heroView)

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
        rightGradient.colors = palette.brandStops.map { $0.0.resolvedColor(with: trait).cgColor }
        rightGradient.locations = palette.brandStops.map { NSNumber(value: Double($0.1)) }
        rightButton.layer.shadowColor = palette.brandShadow.resolvedColor(with: trait).cgColor
        rightButton.layer.shadowOpacity = 1
        heroView.isHidden = dark
        for icon in [cardL, cardR] {
            icon.card.layer.shadowColor = palette.iconCardShadow.resolvedColor(with: trait).cgColor
            icon.card.layer.shadowOpacity = 1
            icon.tint.backgroundColor = palette.iconCardTint
            icon.ring.strokeColor = palette.iconCardRing.resolvedColor(with: trait).cgColor
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
            lastCardSize = .zero
            updateLayout()
            renderGlyphs()
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
            let ringRect = icon.clip.bounds.insetBy(dx: 1 * s, dy: 1 * s)
            icon.ring.path = UIBezierPath(
                roundedRect: ringRect, cornerRadius: max(43 * s, 0)).cgPath
            icon.ring.lineWidth = 2 * s
            icon.glyph.layer.shadowRadius = 2.5 * s
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
        rightGradient.frame = rightButton.bounds
        rightGradient.cornerRadius = 45 * s
        if rightButton.bounds.width > 0, rightButton.bounds.height > 0 {
            let (gs, ge) = BakedArt.cssEndpoints(angleDeg: 135, rect: rightButton.bounds)
            rightGradient.startPoint = CGPoint(
                x: gs.x / rightButton.bounds.width, y: gs.y / rightButton.bounds.height)
            rightGradient.endPoint = CGPoint(
                x: ge.x / rightButton.bounds.width, y: ge.y / rightButton.bounds.height)
        }
        rightButton.layer.shadowOffset = CGSize(width: 0, height: 12 * s)
        rightButton.layer.shadowRadius = 13 * s
        rightButton.layer.shadowPath = UIBezierPath(
            roundedRect: rightButton.bounds, cornerRadius: 45 * s).cgPath
        renderTitle()
        let cardSize = cardView.bounds.size
        if cardSize.width > 0, cardSize != lastCardSize {
            lastCardSize = cardSize
            bgImageView.image = BakedArt.modalBackground(
                size: cardSize, s: s, palette: palette, dark: dark, trait: traitCollection)
            heroImageView.image = BakedArt.hero(
                size: CGSize(width: cardSize.width, height: 335 * s),
                s: s, palette: palette, trait: traitCollection)
            renderGlyphs()
        }
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

    private func renderGlyphs() {
        let box = cardL.glyph.bounds.size
        guard box.width > 1 else { return }
        cardL.glyph.image = GlyphRenderer.image(
            kind: .left, pointSize: box, scale: traitCollection.displayScale,
            iconStops: palette.iconStops, dark: dark, trait: traitCollection,
            elapsed: glyphElapsed)
        cardR.glyph.image = GlyphRenderer.image(
            kind: .right, pointSize: box, scale: traitCollection.displayScale,
            iconStops: palette.iconStops, dark: dark, trait: traitCollection,
            elapsed: glyphElapsed)
    }

    // MARK: Entrance — the designs' choreography, verbatim:
    // jellyIn .95s cubic-bezier(.2,.9,.25,1.12) on the modal;
    // riseIn .95s cubic-bezier(.22,.85,.3,1), delays .14s / .27s, on the
    // icon cards (opacity 0→1, translateY 34px→0, blur 10px→0);
    // fadeUp .6s cubic-bezier(.22,.85,.3,1), delays 1.3s / 1.45s / 1.6s, on
    // the text lines (opacity 0→1, translateY 14px→0);
    // the glyphs' stroke-draw runs on the same clock (see GlyphRenderer).

    func beginEntrance() {
        guard !entranceBegan else { return }
        entranceBegan = true
        glyphStart = CACurrentMediaTime()
        if UIAccessibility.isReduceMotionEnabled {
            // The designs' prefers-reduced-motion block: everything rests.
            glyphElapsed = .greatestFiniteMagnitude
            renderGlyphs()
            return
        }
        let jellyTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.12)
        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = [0.9, 1.028, 0.992, 1.01, 1.0]
        scaleAnim.keyTimes = [0, 0.55, 0.72, 0.86, 1]
        scaleAnim.timingFunctions = [jellyTiming, jellyTiming, jellyTiming, jellyTiming]
        scaleAnim.duration = 0.95
        let fadeAnim = CAKeyframeAnimation(keyPath: "opacity")
        fadeAnim.values = [0, 1, 1]
        fadeAnim.keyTimes = [0, 0.55, 1]
        fadeAnim.timingFunctions = [jellyTiming, jellyTiming]
        fadeAnim.duration = 0.95
        shadowOuter.layer.add(scaleAnim, forKey: "jellyInScale")
        shadowOuter.layer.add(fadeAnim, forKey: "jellyInOpacity")

        let riseTiming = CAMediaTimingFunction(controlPoints: 0.22, 0.85, 0.3, 1)
        for (icon, delay) in [(cardL, 0.14), (cardR, 0.27)] {
            let group = CAAnimationGroup()
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0
            opacity.toValue = 1
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = 34 * s
            move.toValue = 0
            group.animations = [opacity, move]
            group.duration = 0.95
            group.beginTime = glyphStart + delay
            group.timingFunction = riseTiming
            group.fillMode = .backwards
            icon.wrap.layer.add(group, forKey: "riseIn")
            if let filters = icon.wrap.layer.filters, !filters.isEmpty {
                let blur = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
                blur.fromValue = 10 * s
                blur.toValue = 0
                blur.duration = 0.95
                blur.beginTime = glyphStart + delay
                blur.timingFunction = riseTiming
                blur.fillMode = .backwards
                icon.wrap.layer.add(blur, forKey: "riseInBlur")
            }
        }
        for (target, delay) in [(titleView as UIView, 1.3),
                                (line2 as UIView, 1.45),
                                (line3 as UIView, 1.6)] {
            let group = CAAnimationGroup()
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0
            opacity.toValue = 1
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = 14 * s
            move.toValue = 0
            group.animations = [opacity, move]
            group.duration = 0.6
            group.beginTime = glyphStart + delay
            group.timingFunction = riseTiming
            group.fillMode = .backwards
            target.layer.add(group, forKey: "fadeUp")
        }
        glyphElapsed = 0
        renderGlyphs()
        let link = CADisplayLink(target: self, selector: #selector(glyphTick))
        link.add(to: .main, forMode: .common)
        glyphLink = link
    }

    @objc private func glyphTick() {
        let elapsed = CACurrentMediaTime() - glyphStart
        if elapsed >= GlyphArtwork.totalDuration {
            glyphLink?.invalidate()
            glyphLink = nil
            glyphElapsed = .greatestFiniteMagnitude
        } else {
            glyphElapsed = elapsed
        }
        renderGlyphs()
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
            glyphLink?.invalidate()
            glyphLink = nil
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
        glyphLink?.invalidate()
        glyphLink = nil
        UIView.animate(withDuration: 0.25, animations: {
            self.shadowOuter.alpha = 0
            self.shadowOuter.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }, completion: { _ in
            self.onDismiss?()
        })
    }
}

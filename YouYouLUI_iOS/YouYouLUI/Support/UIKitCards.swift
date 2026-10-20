import UIKit

/// Static native-glass surface for page cards — the exact recipe the shell's
/// CardMaterialLayer used under the old Web UI: iOS 26 UIGlassEffect in its
/// static (non-interactive) form, shaped by cornerConfiguration;
/// UIBlurEffect + 24% tint in blur mode / on older systems.
final class StaticGlassView: UIVisualEffectView {
    var glassRadius: CGFloat = 22 { didSet { setNeedsLayout() } }
    private var appliedSignature = ""

    func configure(useBlur: Bool, tint: UIColor) {
        var blur = useBlur
        if #available(iOS 26.0, *) {} else { blur = true }
        let signature = "\(blur)|\(tint.nativeHex)|\(glassRadius)"
        guard signature != appliedSignature else { return }
        appliedSignature = signature
        if #available(iOS 26.0, *), !blur {
            let glass = UIGlassEffect(style: .regular)
            let hex = tint.nativeHex.uppercased()
            if !["#FFFFFF", "#1C1C1E"].contains(hex) { glass.tintColor = tint.withAlphaComponent(0.12) }
            effect = glass
            contentView.backgroundColor = .clear
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
            contentView.backgroundColor = tint.withAlphaComponent(0.24)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The system glass implementation parks an elevation shadow on
        // this layer; the old material layer dropped it on every layout
        // pass and the cards read flat. Do the same here.
        removeExtraLayerShadows(layer)
        guard bounds.width > 0, bounds.height > 0 else { return }
        layer.cornerRadius = min(glassRadius, min(bounds.width, bounds.height) / 2)
        if #available(iOS 26.0, *), effect is UIGlassEffect {
            cornerConfiguration = .uniformCorners(radius: .fixed(Double(layer.cornerRadius)))
            clipsToBounds = false
        } else {
            clipsToBounds = true
        }
    }
}

/// A card: static glass surface behind a content container.
final class GlassCardView: UIView {
    let surface = StaticGlassView()
    let content = UIView()

    init(radius: CGFloat = 22) {
        super.init(frame: .zero)
        surface.glassRadius = radius
        surface.isUserInteractionEnabled = false
        backgroundColor = .clear
        addSubview(surface)
        addSubview(content)
        surface.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(useBlur: Bool, tint: UIColor) { surface.configure(useBlur: useBlur, tint: tint) }
}

/// Pill segmented control in the settings design language (capsule track,
/// white selected thumb). Values are stable string keys.
final class PillSegmentedControl: UIView {
    var options: [(value: String, title: String)] = [] {
        didSet { rebuild() }
    }
    private(set) var selectedValue: String = ""
    var onChange: ((String) -> Void)?

    private let trackView = UIView()
    private let thumbView = UIView()
    private var buttons: [UIButton] = []
    private var stack: UIStackView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        trackView.backgroundColor = UIColor(red: 120 / 255, green: 120 / 255, blue: 128 / 255, alpha: 0.10)
        trackView.layer.cornerRadius = 16
        trackView.clipsToBounds = true
        addSubview(trackView)
        thumbView.backgroundColor = .white
        thumbView.layer.cornerRadius = 14
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOpacity = 0.12
        thumbView.layer.shadowRadius = 3
        thumbView.layer.shadowOffset = CGSize(width: 0, height: 1)
        trackView.addSubview(thumbView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 32) }

    private func rebuild() {
        stack?.removeFromSuperview()
        buttons = []
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        trackView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trackView.trailingAnchor, constant: -2),
            stack.topAnchor.constraint(equalTo: trackView.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: trackView.bottomAnchor, constant: -2),
        ])
        for (index, option) in options.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(option.title, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 12.5)
            button.tag = index
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        self.stack = stack
        refreshSelection(animated: false)
    }

    func setSelectedValue(_ value: String, animated: Bool = false) {
        selectedValue = value
        refreshSelection(animated: animated)
    }

    @objc private func tapped(_ sender: UIButton) {
        guard options.indices.contains(sender.tag) else { return }
        let value = options[sender.tag].value
        if value != selectedValue {
            selectedValue = value
            refreshSelection(animated: true)
            onChange?(value)
        }
    }

    private func refreshSelection(animated: Bool) {
        let dark = traitCollection.userInterfaceStyle == .dark
        for (index, button) in buttons.enumerated() {
            let selected = options.indices.contains(index) && options[index].value == selectedValue
            button.setTitleColor(selected
                ? (dark ? UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1) : UIColor(red: 0x20 / 255, green: 0x28 / 255, blue: 0x32 / 255, alpha: 1))
                : UIColor(red: 0x6E / 255, green: 0x6E / 255, blue: 0x73 / 255, alpha: 1), for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 12.5)
        }
        thumbView.backgroundColor = dark ? UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1) : .white
        positionThumb(animated: animated)
    }

    private func positionThumb(animated: Bool) {
        guard let index = options.firstIndex(where: { $0.value == selectedValue }),
              buttons.indices.contains(index) else {
            thumbView.isHidden = true
            return
        }
        thumbView.isHidden = false
        let target = buttons[index]
        let work = {
            if let stack = self.stack {
                self.thumbView.frame = self.trackView.convert(target.frame, from: stack)
            } else {
                self.thumbView.frame = target.frame
            }
            self.trackView.sendSubviewToBack(self.thumbView)
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut], animations: work)
        } else {
            work()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        trackView.frame = bounds
        positionThumb(animated: false)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshSelection(animated: false)
    }
}

enum UIAppColors {
    static var ink: UIColor { UIColor(red: 0x20 / 255, green: 0x28 / 255, blue: 0x32 / 255, alpha: 1) }
    static var inkDark: UIColor { UIColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1) }
    static func ink(for trait: UITraitCollection) -> UIColor {
        trait.userInterfaceStyle == .dark ? inkDark : ink
    }
    /// Ink as a dynamic colour: labels using it follow light/dark switches
    /// on their own, without needing a rebuild or a trait-change refresh.
    static var inkDynamic: UIColor {
        UIColor { traits in traits.userInterfaceStyle == .dark ? inkDark : ink }
    }
    static var secondary: UIColor { UIColor(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255, alpha: 1) }
    static var divider: UIColor { UIColor(red: 120 / 255, green: 120 / 255, blue: 128 / 255, alpha: 0.12) }
    static var dividerStrong: UIColor { UIColor(red: 120 / 255, green: 120 / 255, blue: 128 / 255, alpha: 0.18) }
    static var accentPurple: UIColor { UIColor(red: 0x69 / 255, green: 0x68 / 255, blue: 0xE8 / 255, alpha: 1) }
}

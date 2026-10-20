import UIKit

/// Custom-color editor (UIKit), mirroring the previous sheet: four groups
/// (selected light / selected dark / all icons / dark mode), each an enable
/// switch plus a colour well. Values load from and save to the same
/// ThemePreferences keys via NativeHomeModel.saveColors.
final class ColorSettingsViewController: UIViewController {
    private let model: NativeHomeModel

    private var selectedEnabled = false
    private var darkSelectedEnabled = false
    private var allEnabled = false
    private var darkModeInvertEnabled = false
    private var selectedColor = UIColor(nativeHex: "#1677ff")
    private var darkSelectedColor = UIColor(nativeHex: "#ffffff")
    private var allColor = UIColor(nativeHex: "#222222")
    private var darkModeColor = UIColor(nativeHex: "#ffffff")
    private var selectedLightCustom = false
    private var selectedDarkCustom = false
    private var saved = false

    private enum PickerTarget { case selected, darkSelected, all, darkMode }
    private var wells: [PickerTarget: UIColorWell] = [:]
    private var switches: [PickerTarget: UISwitch] = [:]

    init(model: NativeHomeModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        let colors = model.savedColors
        selectedEnabled = colors["selectedLightEnabled"] as? Bool ?? false
        darkSelectedEnabled = colors["selectedDarkEnabled"] as? Bool ?? false
        allEnabled = colors["allColorEnabled"] as? Bool ?? false
        darkModeInvertEnabled = colors["darkModeInvertEnabled"] as? Bool ?? false
        selectedColor = UIColor(nativeHex: colors["selectedColor"] as? String ?? "#1677ff")
        darkSelectedColor = UIColor(nativeHex: colors["selectedDarkColor"] as? String ?? "#ffffff")
        allColor = UIColor(nativeHex: colors["allColor"] as? String ?? "#222222")
        darkModeColor = UIColor(nativeHex: colors["darkModeColor"] as? String ?? "#ffffff")
        selectedLightCustom = colors["selectedLightCustom"] as? Bool ?? false
        selectedDarkCustom = colors["selectedDarkCustom"] as? Bool ?? false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func hfont(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        if let imported = model.importedFont { return imported.withSize(size) }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "自定义颜色"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))

        let scroll = UIScrollView()
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 22
        scroll.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
        stack.addArrangedSubview(groupCard(
            header: "选中 · 浅色模式", footer: "打开后自动加深；选取颜色可自定义。",
            target: .selected, toggleTitle: "启用自定义颜色", colorTitle: "选中颜色",
            isOn: selectedEnabled, color: selectedColor))
        stack.addArrangedSubview(groupCard(
            header: "选中 · 深色模式", footer: "打开后自动反转；选取颜色可自定义。",
            target: .darkSelected, toggleTitle: "启用自定义颜色", colorTitle: "选中颜色",
            isOn: darkSelectedEnabled, color: darkSelectedColor))
        stack.addArrangedSubview(groupCard(
            header: "全部图标", footer: "打开后应用统一颜色；选取颜色可自定义。",
            target: .all, toggleTitle: "启用统一颜色", colorTitle: "图标颜色",
            isOn: allEnabled, color: allColor))
        stack.addArrangedSubview(groupCard(
            header: "深色模式", footer: "打开后自动反转；选取颜色可自定义。",
            target: .darkMode, toggleTitle: "启用深色反转", colorTitle: "图标颜色",
            isOn: darkModeInvertEnabled, color: darkModeColor))
        refreshEnabledStates()
    }

    private func groupCard(header: String, footer: String, target: PickerTarget,
                           toggleTitle: String, colorTitle: String,
                           isOn: Bool, color: UIColor) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 6
        let headerLabel = UILabel()
        headerLabel.text = header
        headerLabel.font = hfont(13)
        headerLabel.textColor = .secondaryLabel
        container.addArrangedSubview(headerLabel)

        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 26
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 0
        card.addSubview(rows)
        rows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            rows.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            rows.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            rows.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
        ])

        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        switches[target] = toggle
        rows.addArrangedSubview(switchRow(title: toggleTitle, control: toggle))

        let divider = UIView()
        divider.backgroundColor = UIAppColors.divider
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        rows.addArrangedSubview(divider)

        // The official system colour well (drawn by iOS, presents the
        // official picker on tap); changes arrive as `.valueChanged`.
        let well = UIColorWell()
        well.title = colorTitle
        well.supportsAlpha = false
        well.selectedColor = color
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 34).isActive = true
        well.heightAnchor.constraint(equalToConstant: 34).isActive = true
        well.addTarget(self, action: #selector(wellChanged(_:)), for: .valueChanged)
        wells[target] = well
        rows.addArrangedSubview(switchRow(title: colorTitle, control: well))
        container.addArrangedSubview(card)

        let footerLabel = UILabel()
        footerLabel.text = footer
        footerLabel.font = hfont(10)
        footerLabel.textColor = .secondaryLabel
        footerLabel.numberOfLines = 0
        container.addArrangedSubview(footerLabel)
        return container
    }

    private func switchRow(title: String, control: UIView) -> UIView {
        let row = UIView()
        let label = UILabel()
        label.text = title
        label.font = hfont(12.5)
        row.addSubview(label)
        row.addSubview(control)
        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 48),
        ])
        return row
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        for (target, toggle) in switches where toggle === sender {
            switch target {
            case .selected: selectedEnabled = sender.isOn; if sender.isOn { selectedLightCustom = false }
            case .darkSelected: darkSelectedEnabled = sender.isOn; if sender.isOn { selectedDarkCustom = false }
            case .all: allEnabled = sender.isOn
            case .darkMode: darkModeInvertEnabled = sender.isOn
            }
        }
        refreshEnabledStates()
    }

    @objc private func wellChanged(_ sender: UIColorWell) {
        for (target, well) in wells where well === sender {
            guard let color = sender.selectedColor else { return }
            switch target {
            case .selected: selectedColor = color; selectedLightCustom = true
            case .darkSelected: darkSelectedColor = color; selectedDarkCustom = true
            case .all: allColor = color
            case .darkMode: darkModeColor = color
            }
            return
        }
    }

    private func color(for target: PickerTarget) -> UIColor {
        switch target {
        case .selected: return selectedColor
        case .darkSelected: return darkSelectedColor
        case .all: return allColor
        case .darkMode: return darkModeColor
        }
    }

    private func refreshEnabledStates() {
        let states: [PickerTarget: Bool] = [
            .selected: selectedEnabled, .darkSelected: darkSelectedEnabled,
            .all: allEnabled, .darkMode: darkModeInvertEnabled,
        ]
        for (target, well) in wells {
            let enabled = states[target] ?? false
            well.isEnabled = enabled
            well.alpha = enabled ? 1 : 0.35
        }
    }

    @objc private func doneTapped() {
        save()
        dismiss(animated: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            save()
        }
    }

    private func save() {
        guard !saved else { return }
        saved = true
        model.saveColors([
            "selectedLightEnabled": selectedEnabled,
            "selectedDarkEnabled": darkSelectedEnabled,
            "allColorEnabled": allEnabled,
            "darkModeInvertEnabled": darkModeInvertEnabled,
            "darkModeColor": darkModeColor.nativeHex,
            "selectedColor": selectedColor.nativeHex,
            "selectedDarkColor": darkSelectedColor.nativeHex,
            "allColor": allColor.nativeHex,
            "selectedLightCustom": selectedLightCustom,
            "selectedDarkCustom": selectedDarkCustom,
        ])
    }
}


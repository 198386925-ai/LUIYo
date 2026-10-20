import Combine
import UIKit

/// Rules page (UIKit): the naming-rule catalogue in two glass cards.
/// Data comes from NamingRulesData; the shell's bottom search drives
/// `model.query`, which filters the rows.
final class RulesViewController: UIViewController {
    let model: RulesNativeModel
    let homeModel: NativeHomeModel

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var sectionCards: [String: GlassCardView] = [:]
    private var rowViews: [String: [UIView]] = [:]
    private var emptyLabels: [String: UILabel] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(model: RulesNativeModel, homeModel: NativeHomeModel) {
        self.model = model
        self.homeModel = homeModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        stack.axis = .vertical
        stack.spacing = 18
        scrollView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -110),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -28),
        ])

        let title = UILabel()
        title.text = "规则"
        title.font = UIFont.systemFont(ofSize: 25, weight: .heavy)
        title.textColor = UIAppColors.ink(for: traitCollection)
        stack.addArrangedSubview(title)
        let subtitle = UILabel()
        subtitle.text = "LiquidUI 全局换图标命名规则"
        subtitle.font = UIFont.systemFont(ofSize: 13.5)
        subtitle.textColor = UIAppColors.secondary
        stack.addArrangedSubview(subtitle)
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(14, after: subtitle)

        for section in ["LiquidUI", "原版微信"] {
            stack.addArrangedSubview(makeSectionCard(section))
        }

        model.$query
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyFilter() }
            .store(in: &cancellables)
        homeModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshTheme() }
            .store(in: &cancellables)
        refreshTheme()
        applyFilter()
    }

    private func makeSectionCard(_ section: String) -> GlassCardView {
        let rules = namingRules.filter { $0.section == section }
        let card = GlassCardView(radius: 24)
        sectionCards[section] = card
        let inner = UIStackView()
        inner.axis = .vertical
        inner.spacing = 0
        card.content.addSubview(inner)
        inner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.content.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: card.content.trailingAnchor),
            inner.topAnchor.constraint(equalTo: card.content.topAnchor),
            inner.bottomAnchor.constraint(equalTo: card.content.bottomAnchor),
        ])

        let head = UIView()
        let name = UILabel()
        name.text = section
        name.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        name.textColor = UIAppColors.ink(for: traitCollection)
        let count = UILabel()
        count.text = "\(rules.count) 项"
        count.font = UIFont.systemFont(ofSize: 12)
        count.textColor = UIAppColors.secondary
        head.addSubview(name)
        head.addSubview(count)
        name.translatesAutoresizingMaskIntoConstraints = false
        count.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: 15),
            name.topAnchor.constraint(equalTo: head.topAnchor, constant: 14),
            name.bottomAnchor.constraint(equalTo: head.bottomAnchor, constant: -4),
            count.trailingAnchor.constraint(equalTo: head.trailingAnchor, constant: -15),
            count.centerYAnchor.constraint(equalTo: name.centerYAnchor),
        ])
        inner.addArrangedSubview(head)

        var views: [UIView] = []
        for (index, rule) in rules.enumerated() {
            let row = UIView()
            let title = UILabel()
            title.text = rule.title
            title.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
            title.textColor = UIAppColors.ink(for: traitCollection)
            title.numberOfLines = 0
            let file = UILabel()
            file.text = rule.file
            file.font = UIFont.systemFont(ofSize: 11)
            file.textColor = UIAppColors.secondary
            file.numberOfLines = 0
            row.addSubview(title)
            row.addSubview(file)
            title.translatesAutoresizingMaskIntoConstraints = false
            file.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 15),
                title.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -15),
                title.topAnchor.constraint(equalTo: row.topAnchor, constant: 9),
                file.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                file.trailingAnchor.constraint(equalTo: title.trailingAnchor),
                file.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
                file.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -9),
            ])
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = UIAppColors.divider
                row.addSubview(divider)
                divider.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    divider.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 15),
                    divider.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                    divider.topAnchor.constraint(equalTo: row.topAnchor),
                    divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                ])
            }
            row.tag = index
            inner.addArrangedSubview(row)
            views.append(row)
        }
        rowViews[section] = views

        let empty = UILabel()
        empty.text = "没有匹配的规则"
        empty.font = UIFont.systemFont(ofSize: 13)
        empty.textColor = UIAppColors.secondary
        empty.textAlignment = .center
        empty.isHidden = true
        empty.translatesAutoresizingMaskIntoConstraints = false
        let emptyWrap = UIView()
        emptyWrap.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: emptyWrap.centerXAnchor),
            empty.topAnchor.constraint(equalTo: emptyWrap.topAnchor, constant: 12),
            empty.bottomAnchor.constraint(equalTo: emptyWrap.bottomAnchor, constant: -16),
        ])
        inner.addArrangedSubview(emptyWrap)
        emptyLabels[section] = emptyWrap
        return card
    }

    private func applyFilter() {
        let query = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        for section in ["LiquidUI", "原版微信"] {
            let rules = namingRules.filter { $0.section == section }
            var visible = 0
            for (index, rule) in rules.enumerated() {
                let show = query.isEmpty || rule.title.contains(query) || rule.file.lowercased().contains(query.lowercased())
                rowViews[section]?[index].isHidden = !show
                if show { visible += 1 }
            }
            emptyLabels[section]?.isHidden = visible > 0 || query.isEmpty
        }
    }

    private func refreshTheme() {
        view.backgroundColor = UIColor(nativeHex: homeModel.theme.background)
        let tint = UIColor(nativeHex: homeModel.theme.card)
        for card in sectionCards.values {
            card.configure(useBlur: homeModel.useBlur, tint: tint)
        }
    }
}

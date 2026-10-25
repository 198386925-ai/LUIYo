import PhotosUI
import UIKit

/// 气泡包编辑界面（Swift 版，LUBubblePackEditorViewController 的一比一移植）
///
/// 仿微信聊天窗口的编辑页：批量导入放图，底部切命名方式和夜间版，导出 zip。
/// UIKit only。导出改用 App 现成的 ZipWriter（ObjC 版用 SSZipArchive，
/// 这里是唯一一处有意改动；输出文件名与静默行为与 ObjC 版一致）。

// MARK: - 颜色工具

private func bubbleColor(hex: String) -> UIColor {
    let s = hex.replacingOccurrences(of: "#", with: "")
    let rgb = UInt32(s, radix: 16) ?? 0
    return UIColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
        green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
        blue: CGFloat(rgb & 0xFF) / 255.0,
        alpha: 1
    )
}

private let bubbleLightTable: [String: String] = [
    "bg": "#f4f5f7", "card": "#ffffff", "line": "#e4e7eb", "line2": "#d3d8de",
    "text": "#1b1d20", "text2": "#5d646d", "text3": "#8b9199",
    "accent": "#2f7cf6",
    "ok": "#1a9c5b", "warn": "#c08a12",
    "chat": "#ededed", "chatNight": "#111112",
    "bub": "#ffffff", "bubNight": "#2c2c2e", "bubEmpty": "#c2c7cd",
    "mine": "#95ec69", "mineNight": "#4a8c5a",
    "wxNav": "#ededed", "wxNavLine": "#d9d9d9", "wxNavTx": "#181818", "wxTime": "#b2b2b2",
    "wxBar": "#f7f7f7", "wxInputBg": "#ffffff", "wxIc": "#7d7d7d",
]

private let bubbleDarkTable: [String: String] = [
    "bg": "#141517", "card": "#1d1f23", "line": "#2e3238", "line2": "#3c424a",
    "text": "#e9ebee", "text2": "#a6adb6", "text3": "#6f767f",
    "accent": "#5b9bff",
    "ok": "#4ec98a", "warn": "#e0b64a",
    "chat": "#111112", "chatNight": "#111112",
    "bub": "#2c2c2e", "bubNight": "#2c2c2e", "bubEmpty": "#565c66",
    "mine": "#4a8c5a", "mineNight": "#4a8c5a",
    "wxNav": "#1c1c1e", "wxNavLine": "#2e2e30", "wxNavTx": "#e5e5e7", "wxTime": "#6b6b70",
    "wxBar": "#1c1c1e", "wxInputBg": "#2c2c2e", "wxIc": "#8a8a90",
]

// ObjC 版的 LU_CAT_LABEL 在源码里定义了但从未使用，这里不移植。
private let bubbleCatGroup: [String: String] = [
    "hb": "红包", "aa": "转账 / AA", "gift": "礼物",
    "app": "卡片", "common": "通用卡片底 / 遮罩", "voice": "语音",
]

// MARK: - 气泡视图（带微信尾巴）

final class BubbleView: UIView, UIGestureRecognizerDelegate {
    let imageView = UIImageView()
    let placeholder = UILabel()
    let deleteBtn = UIButton(type: .custom)
    var isMine = false
    var position: BubblePosition = .top  // 0 上 1 中 2 下 3 单（与 BubblePosition rawValue 一致）
    var isOther = false
    var category: String?
    var tailColor: UIColor?
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    private var tail: CAShapeLayer?
    private var dashedBorder: CAShapeLayer?
    private var dashedColor: UIColor?
    private var dashedWidth: CGFloat = 1.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 7
        backgroundColor = .white

        imageView.translatesAutoresizingMaskIntoConstraints = false
        // 气泡皮：拉伸铺满整个气泡当背景（微信使用效果），字显示在上面。
        // 图片不得参与气泡定尺寸：否则图片原尺寸会把气泡撑大；
        // 气泡大小只按消息内容（最小 64×40 / 其它按品类最小），图片只管铺满。
        imageView.contentMode = .scaleToFill
        imageView.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        imageView.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        imageView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        imageView.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)
        imageView.isHidden = true
        addSubview(imageView)

        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        placeholder.textColor = UIColor(white: 0.45, alpha: 1)
        placeholder.textAlignment = .center
        placeholder.numberOfLines = 0
        addSubview(placeholder)

        deleteBtn.translatesAutoresizingMaskIntoConstraints = false
        deleteBtn.backgroundColor = bubbleColor(hex: "#ff5a5f")
        deleteBtn.layer.cornerRadius = 9
        deleteBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        deleteBtn.setTitleColor(.white, for: .normal)
        deleteBtn.setTitle("×", for: .normal)
        deleteBtn.isHidden = true
        deleteBtn.addTarget(self, action: #selector(del), for: .touchUpInside)
        addSubview(deleteBtn)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tap))
        tap.delegate = self
        addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholder.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            placeholder.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            placeholder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            deleteBtn.topAnchor.constraint(equalTo: topAnchor, constant: -6),
            deleteBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 6),
            deleteBtn.widthAnchor.constraint(equalToConstant: 18),
            deleteBtn.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view != deleteBtn
    }

    @objc private func tap() { onTap?() }
    @objc private func del() { onDelete?() }

    /// 微信使用效果：图是气泡皮，拉伸铺满气泡当背景，消息字显示在上面。
    /// 气泡大小按消息内容（最小 64×40 / 其它按品类最小），不再按图片自己尺寸。
    func showImage(_ img: UIImage, placeholderText text: String) {
        imageView.isHidden = false
        imageView.image = img
        placeholder.isHidden = false
        placeholder.text = text
        deleteBtn.isHidden = false
        backgroundColor = .clear
        setDashedBorder(nil)
        redrawTail()
    }

    func showEmpty(withText text: String) {
        imageView.isHidden = true
        imageView.image = nil
        placeholder.isHidden = false
        placeholder.text = text
        deleteBtn.isHidden = true
        // 边框不再这里画：由 colorBubble 按日间/夜间统一画虚线（见 setDashedBorder），
        // 否则夜间会被这里写死的浅色实线盖掉。
        redrawTail()
    }

    func applyBubbleColor(_ color: UIColor, border: UIColor?) {
        if imageView.isHidden {
            backgroundColor = color
            setDashedBorder(border, width: 1.5)
        } else {
            setDashedBorder(nil)
        }
        tailColor = color
        redrawTail()
    }

    /// 用户不要虚线描边：这里只清掉旧图层，不再新建虚线层。
    /// setDashedBorder 的调用点保持不动（传颜色或 nil 都只会清掉图层），
    /// 空格子只留底色和名字。
    func setDashedBorder(_ color: UIColor?, width: CGFloat = 1.5) {
        dashedColor = color
        dashedWidth = width
        updateDashedBorder()
    }

    private func updateDashedBorder() {
        dashedBorder?.removeFromSuperlayer()
        dashedBorder = nil
    }

    func redrawTail() {
        tail?.removeFromSuperlayer()
        tail = nil
        if isOther { return }
        if position == .middle { return }
        if !imageView.isHidden { return }
        // 尾巴真正落在气泡外侧：左气泡向左伸、右气泡向右伸（镜像）；
        // 上/单贴顶部（y=11），下贴底部（y=高-11-13），中无尾巴。
        // 旧 ObjC 版算出 y/rect 却从未赋给图层：尾巴画在气泡左上角内侧、
        // 又与气泡同色，所以看不见 —— 这里按网页版画法修正，不再照搬那个死代码。
        let w: CGFloat = 8
        let h: CGFloat = 13
        let left = !isMine
        let y: CGFloat = position == .end ? bounds.height - 11 - h : 11
        let path = UIBezierPath()
        if left {
            path.move(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 0, y: h * 0.45))
        } else {
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: w, y: h * 0.45))
        }
        path.close()
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.fillColor = (tailColor ?? backgroundColor)?.cgColor
        // 网页版尾巴左右各伸出 7pt（left:-7 / right:-7，宽 8）：底边与气泡边重合 1pt。
        layer.frame = CGRect(x: left ? -7 : bounds.width - 1, y: y, width: w, height: h)
        // 插到最底层：画在气泡背景上，不盖住图片/文字/删除钮
        self.layer.insertSublayer(layer, at: 0)
        tail = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateDashedBorder()
        redrawTail()
    }
}

// MARK: - 自定义药丸分段（选中 = 实心蓝底 + 白字 + 光晕；不用系统 UISegmentedControl）
// 手动按 frame 排布：嵌套 UIStackView 在手动换行容器里会出现标签压住药丸的错位，
// 这里按钮位置和内在尺寸全部自己算，不依赖层层传递的内在尺寸。
// 药丸按钮：填充、描边、光晕全部用 CAShapeLayer 自己画。
// 实测：iOS 26 模拟器上，按钮自身的 backgroundColor / layer.border 不渲染（字色却正常），
// 连底下垫普通 UIView 的蓝底也不渲染；但气泡尾巴、虚线边框这些 CAShapeLayer 都正常渲染。
// 所以药丸的底和边也走 shape 层，不再信任 UIView / UIButton 自身的背景绘制。
final class PillButton: UIButton {
    var fillColor: UIColor? { didSet { updateShape() } }
    var strokeColor: UIColor? { didSet { updateShape() } }
    var glowColor: UIColor? { didSet { updateShape() } }
    var glowOpacity: Float = 0 { didSet { updateShape() } }
    var glowRadius: CGFloat = 0 { didSet { updateShape() } }
    var glowOffset: CGSize = .zero { didSet { updateShape() } }
    private let shape = CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(shape, at: 0)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        updateShape()
    }
    private func updateShape() {
        shape.frame = bounds
        shape.path = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        shape.fillColor = (fillColor ?? .clear).cgColor
        if let stroke = strokeColor {
            shape.strokeColor = stroke.cgColor
            shape.lineWidth = 1
        } else {
            shape.strokeColor = nil
            shape.lineWidth = 0
        }
        shape.shadowColor = glowColor?.cgColor
        shape.shadowOpacity = glowOpacity
        shape.shadowRadius = glowRadius
        shape.shadowOffset = glowOffset
    }
}

final class PillGroup: UIView {
    // 滑动分段：灰色轨道 + 白色滑块（首页 PillSegmentedControl 同款），点一下滑块滑过去。
    // 轨道与滑块都用 PillButton：填充画在它自己的 shape 层上（上一轮证实这条路在工具栏
    // 子树里能渲染，普通 view 的底色垫在这里曾渲染不出来）。
    var selectedIndex: Int
    var onChange: ((Int) -> Void)?
    private var buttons: [UIButton] = []
    private let track = PillButton(frame: .zero)
    private let thumb = PillButton(frame: .zero)
    private var trackColor: UIColor = .systemGray5
    private var thumbColor: UIColor = .white
    private var selected: UIColor = .label
    private var plain: UIColor = .secondaryLabel
    private var animatingThumb = false

    init(titles: [String], selected: Int) {
        selectedIndex = selected
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        track.isUserInteractionEnabled = false
        thumb.isUserInteractionEnabled = false
        thumb.glowColor = .black
        thumb.glowOpacity = 0.12
        thumb.glowRadius = 3
        thumb.glowOffset = CGSize(width: 0, height: 1)
        addSubview(track)
        addSubview(thumb)
        for (i, t) in titles.enumerated() {
            // 按钮本身透明只负责点按与文字，底色全由轨道和滑块画。
            let b = UIButton(type: .custom)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = UIFont.systemFont(ofSize: 13)
            b.tag = i
            b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            buttons.append(b)
            addSubview(b)
        }
        updateColors()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // 段宽直接用文字量出来，不依赖按钮的内在尺寸。
    private func segmentSize(for title: String) -> CGSize {
        let text = (title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 13)])
        return CGSize(width: ceil(text.width) + 28, height: 28)
    }

    override var intrinsicContentSize: CGSize {
        var w: CGFloat = 8
        for b in buttons {
            w += segmentSize(for: b.currentTitle ?? "").width
        }
        return CGSize(width: w, height: 28)
    }

    private func segmentFrame(at index: Int) -> CGRect {
        var x: CGFloat = 4
        for (i, b) in buttons.enumerated() {
            let w = segmentSize(for: b.currentTitle ?? "").width
            if i == index { return CGRect(x: x, y: 3, width: w, height: 22) }
            x += w
        }
        return .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        var x: CGFloat = 4
        for b in buttons {
            let w = segmentSize(for: b.currentTitle ?? "").width
            b.frame = CGRect(x: x, y: 0, width: w, height: bounds.height)
            x += w
        }
        // 滑块动画进行中不抢帧，动画结束后再落到最终位置。
        if !animatingThumb {
            thumb.frame = segmentFrame(at: selectedIndex)
        }
    }

    func refreshColors(track: UIColor, thumb: UIColor, selected: UIColor, plain: UIColor) {
        self.trackColor = track
        self.thumbColor = thumb
        self.selected = selected
        self.plain = plain
        updateColors()
    }

    private func updateColors() {
        track.fillColor = trackColor
        track.glowOpacity = 0
        thumb.fillColor = thumbColor
        for (i, b) in buttons.enumerated() {
            b.setTitleColor(i == selectedIndex ? selected : plain, for: .normal)
        }
    }

    @objc private func tapped(_ sender: UIButton) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        updateColors()
        let target = segmentFrame(at: selectedIndex)
        animatingThumb = true
        UIView.animate(withDuration: 0.25, animations: { self.thumb.frame = target }) { _ in
            self.animatingThumb = false
            self.thumb.frame = self.segmentFrame(at: self.selectedIndex)
        }
        onChange?(selectedIndex)
    }
}

// MARK: - 工具栏分组药丸（标签 + 一组或两组药丸按钮，同样手动排布）
final class GroupContainer: UIView {
    let label = UILabel()
    private var groups: [UIView]

    init(labelText: String, groups: [UIView]) {
        self.groups = groups
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 999
        label.text = labelText
        label.font = UIFont.systemFont(ofSize: 12.5)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        for g in groups { addSubview(g) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshPillColors(track: UIColor, thumb: UIColor, selected: UIColor, plain: UIColor) {
        for g in groups { (g as? PillGroup)?.refreshColors(track: track, thumb: thumb, selected: selected, plain: plain) }
    }

    override var intrinsicContentSize: CGSize {
        var w: CGFloat = 12
        var h: CGFloat = 0
        let ls = label.intrinsicContentSize
        w += ls.width
        h = max(h, ls.height)
        for g in groups where !g.isHidden {
            w += 8 + g.intrinsicContentSize.width
            h = max(h, g.intrinsicContentSize.height)
        }
        w += 6
        h += 8
        return CGSize(width: w, height: h)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let ls = label.intrinsicContentSize
        label.frame = CGRect(x: 12, y: (bounds.height - ls.height) / 2, width: ls.width, height: ls.height)
        var x: CGFloat = 12 + ls.width + 8
        for g in groups where !g.isHidden {
            let s = g.intrinsicContentSize
            g.frame = CGRect(x: x, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
            g.layoutIfNeeded()
            x += s.width + 8
        }
    }
}

// MARK: - 自动换行排布（空间不够就换行，控件绝不被压缩截断）
final class FlowLayoutView: UIView {
    var hSpacing: CGFloat = 12
    var vSpacing: CGFloat = 10
    private var lastHeight: CGFloat = -1

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: rowsHeight(for: bounds.width))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = layoutRows()
        if h != lastHeight {
            lastHeight = h
            invalidateIntrinsicContentSize()
        }
    }

    private func visibleChildren() -> [UIView] { subviews.filter { !$0.isHidden } }

    private func childSize(_ v: UIView) -> CGSize {
        let s = v.intrinsicContentSize
        return CGSize(width: s.width == UIView.noIntrinsicMetric ? 0 : s.width,
                      height: s.height == UIView.noIntrinsicMetric ? 0 : s.height)
    }

    private func rowsHeight(for width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var x: CGFloat = 0
        for v in visibleChildren() {
            let s = childSize(v)
            if x > 0 && x + s.width > width {
                y += rowH + vSpacing
                x = 0
                rowH = 0
            }
            rowH = max(rowH, s.height)
            x += s.width + hSpacing
        }
        return y + rowH
    }

    private func layoutRows() -> CGFloat {
        let width = bounds.width
        guard width > 0 else { return 0 }
        var rows: [[(UIView, CGSize)]] = []
        var row: [(UIView, CGSize)] = []
        var rowW: CGFloat = 0
        for v in visibleChildren() {
            let s = childSize(v)
            if !row.isEmpty && rowW + s.width > width {
                rows.append(row); row = []; rowW = 0
            }
            row.append((v, s)); rowW += s.width + hSpacing
        }
        if !row.isEmpty { rows.append(row) }
        var y: CGFloat = 0
        for r in rows {
            let h = r.map { $0.1.height }.max() ?? 0
            var x: CGFloat = 0
            for (v, s) in r {
                v.frame = CGRect(x: x, y: y + (h - s.height) / 2, width: s.width, height: s.height)
                v.layoutIfNeeded()
                x += s.width + hSpacing
            }
            y += h + vSpacing
        }
        return rows.isEmpty ? 0 : y - vSpacing
    }
}

// MARK: - 编辑界面

final class BubblePackEditorViewController: UIViewController,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
    /// 导出完成回调，zipURL 是临时目录下的 气泡包.zip
    var onExport: ((URL) -> Void)?
    /// 壳子设置的导出授权门：点导出时先问它，回调 true 才真正打包；
    /// 没设置时（编辑器单用）直接导出。页内随便玩，只有导出 zip 过门。
    var exportAuthorizationCheck: ((@escaping (Bool) -> Void) -> Void)?

    private struct PlacedImage {
        let image: UIImage
        let w: Int
        let h: Int
    }

    private var scrollView: UIScrollView!
    private var contentStack: UIStackView!
    private var headerTitle: UILabel!
    private var headerSub: UILabel!
    private var fileBtn: PillButton!
    private var toolbar: UIView!
    private var toolbarFlow: FlowLayoutView!
    private var modeSeg: PillGroup!
    private var nightSeg: PillGroup!
    private var viewSeg: PillGroup!
    private var scaleBtn: PillButton!
    private var hideEnglishFileNames = false
    private var batchBtn: PillButton!
    private var copyBtn: PillButton!
    private var clearBtn: PillButton!
    private var exportBtn: PillButton!
    private var phoneCard: UIView!
    private var navView: UIView!
    private var chatStack: UIStackView!
    private var inputBar: UIView!
    private var phoneTip: UILabel!
    private var summaryLabel: UILabel!
    private var progressBar: UIView!
    private var progressFillW: NSLayoutConstraint!
    private var noteLabel: UILabel!
    private var otherToggle: PillButton!
    private var otherCard: UIView!
    private var otherChatStack: UIStackView!
    private var otherNav: UIView!
    private var otherInBar: UIView!

    private var state: [String: PlacedImage] = [:]
    private var unrecognized: [(name: String, image: UIImage)] = []  // zip 导入时文件名认不出的图：不进任何槽位、也不进 zip
    private var pending: [UIImage] = []  // 批量导入后待手动分配的图：不按文件名自动认
    // 多选顺序（按勾的顺序）：放进气泡后图仍留在待分配里，只有清空才走；放完勾清掉。
    private var selectedPendingOrder: [UIImage] = []
    private var pendingCard: UIView!
    private var pendingTitle: UILabel!
    private var pendingSub: UILabel!
    private var pendingStack: UIStackView!
    private var pendingLeftBtn: PillButton!
    private var pendingRightBtn: PillButton!
    private var pendingScroll: UIScrollView!
    private var pendingPosRow: UIStackView!
    private var pendingPosLabel: UILabel!
    private var pendingPosChars: [UILabel] = []
    private var pendingPosButtons: [UIButton] = []
    private var pendingFullLabel: UILabel!
    private var positionSelected: [Bool] = [false, false, false, false]  // 上/中/下/单 位置点选
    // 其它工作区自有一套（不共用文字的工具栏与待分配）：自己的批量导图 + 待分配，只放其它气泡。
    private var pendingOther: [UIImage] = []
    private var selectedPendingOtherOrder: [UIImage] = []
    private var pickerTargetOther = false
    private var otherBatchRow: UIView!
    private var otherBatchBtn: PillButton!
    private var otherPendingCard: UIView!
    private var otherPendingTitle: UILabel!
    private var otherPendingSub: UILabel!
    private var otherPendingStack: UIStackView!
    private var otherPendingOtherBtn: PillButton!
    private var otherPendingHint: UILabel!
    private var textBubbles: [String: BubbleView] = [:]
    private var textFileNames: [String: UILabel] = [:]
    private var otherBubbles: [String: BubbleView] = [:]
    private var otherFileNames: [String: UILabel] = [:]

    private var mode = 0
    private var scaleOpt = 0  // 0 自动 1 不写 2 @2x 3 @3x
    private var wantsNight = false
    private var viewNight = false
    private var dark = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "气泡包制作器"
        mode = 0
        scaleOpt = 0
        wantsNight = false
        viewNight = false
        dark = false
        state = [:]
        unrecognized = []
        pending = []
        selectedPendingOrder = []
        positionSelected = [false, false, false, false]
        pendingOther = []
        selectedPendingOtherOrder = []
        textBubbles = [:]
        textFileNames = [:]
        otherBubbles = [:]
        otherFileNames = [:]

        buildScrollView()
        buildHeader()
        buildToolbar()
        buildPendingCard()
        buildPhone()
        buildSummaryAndNote()
        buildOtherPhone()
        buildChat()
        buildOtherChat()
        applyTheme()
        refresh()
    }

    private func c(_ key: String) -> UIColor {
        // 与 ObjC 版一致：深色表里没有的 key 回落到浅色表，两表都没有则为黑色
        //（ObjC 版 LUColor(nil) 即黑色；如夜间文字气泡边框用的 "bubLine" 就不在两表里）
        let table = dark ? bubbleDarkTable : bubbleLightTable
        let hex = table[key] ?? bubbleLightTable[key] ?? "#000000"
        return bubbleColor(hex: hex)
    }

    // MARK: - 骨架

    private func buildScrollView() {
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack = UIStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.layoutMargins = UIEdgeInsets(top: 18, left: 14, bottom: 90, right: 14)
        contentStack.isLayoutMarginsRelativeArrangement = true
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
        ])
    }

    private func buildHeader() {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        headerTitle = UILabel()
        headerTitle.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        headerSub = UILabel()
        headerSub.font = UIFont.systemFont(ofSize: 12.5)
        headerSub.numberOfLines = 0
        let titles = UIStackView(arrangedSubviews: [headerTitle, headerSub])
        titles.axis = .vertical
        titles.spacing = 1
        fileBtn = pillButton(fileBtnTitle(), primary: false, insets: UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14))
        fileBtn.addTarget(self, action: #selector(toggleFileNames), for: .touchUpInside)
        row.addSubview(titles)
        row.addSubview(fileBtn)
        titles.translatesAutoresizingMaskIntoConstraints = false
        fileBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titles.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            titles.topAnchor.constraint(equalTo: row.topAnchor),
            titles.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            // 副标题再长也不许把按钮挤出屏：标题块在按钮左侧截断，副标题折行。
            titles.trailingAnchor.constraint(lessThanOrEqualTo: fileBtn.leadingAnchor, constant: -12),
            fileBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            fileBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        contentStack.addArrangedSubview(row)
    }

    // MARK: - 待分配

    private func buildPendingCard() {
        pendingCard = UIView()
        pendingCard.translatesAutoresizingMaskIntoConstraints = false
        pendingCard.layer.cornerRadius = 22
        pendingCard.layer.borderWidth = 1
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        pendingTitle = UILabel()
        pendingTitle.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        pendingSub = UILabel()
        pendingSub.font = UIFont.systemFont(ofSize: 13)
        pendingSub.text = "点一张图，再选左边 / 右边"
        pendingScroll = UIScrollView()
        pendingScroll.translatesAutoresizingMaskIntoConstraints = false
        pendingScroll.showsHorizontalScrollIndicator = false
        pendingStack = UIStackView()
        pendingStack.axis = .horizontal
        pendingStack.spacing = 10
        pendingStack.translatesAutoresizingMaskIntoConstraints = false
        pendingScroll.addSubview(pendingStack)
        NSLayoutConstraint.activate([
            pendingStack.topAnchor.constraint(equalTo: pendingScroll.topAnchor),
            pendingStack.bottomAnchor.constraint(equalTo: pendingScroll.bottomAnchor),
            pendingStack.leadingAnchor.constraint(equalTo: pendingScroll.leadingAnchor),
            pendingStack.trailingAnchor.constraint(equalTo: pendingScroll.trailingAnchor),
            pendingStack.heightAnchor.constraint(equalToConstant: 72),
        ])
        pendingScroll.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let btnRow = UIStackView()
        btnRow.axis = .horizontal
        btnRow.spacing = 12
        btnRow.alignment = .center
        pendingLeftBtn = pillButton("左边", primary: false)
        pendingLeftBtn.addTarget(self, action: #selector(placePendingLeft), for: .touchUpInside)
        pendingRightBtn = pillButton("右边", primary: false)
        pendingRightBtn.addTarget(self, action: #selector(placePendingRight), for: .touchUpInside)
        btnRow.addArrangedSubview(pendingLeftBtn)
        btnRow.addArrangedSubview(pendingRightBtn)
        // 位置行放按钮下面一行（一行塞不下 4 组字+圈）：已勾选 + 上○中○下○单○，圈圈可点选。
        pendingPosRow = UIStackView()
        pendingPosRow.axis = .horizontal
        pendingPosRow.spacing = 2
        pendingPosRow.alignment = .center
        pendingPosLabel = UILabel()
        pendingPosLabel.font = UIFont.systemFont(ofSize: 13)
        pendingPosLabel.text = "已勾选："
        pendingPosRow.addArrangedSubview(pendingPosLabel)
        pendingPosChars.removeAll()
        pendingPosButtons.removeAll()
        for i in 0..<4 {
            let ch = UILabel()
            ch.font = UIFont.systemFont(ofSize: 13)
            ch.text = ["上", "中", "下", "单"][i]
            pendingPosChars.append(ch)
            pendingPosRow.addArrangedSubview(ch)
            let b = UIButton(type: .custom)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 24).isActive = true
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            b.tag = i
            b.addTarget(self, action: #selector(togglePosition(_:)), for: .touchUpInside)
            pendingPosButtons.append(b)
            pendingPosRow.addArrangedSubview(b)
        }
        pendingFullLabel = UILabel()
        pendingFullLabel.font = UIFont.systemFont(ofSize: 13)
        pendingFullLabel.numberOfLines = 0
        pendingFullLabel.isHidden = true
        btnRow.addArrangedSubview(pendingPosRow)
        btnRow.addArrangedSubview(pendingFullLabel)
        stack.addArrangedSubview(pendingTitle)
        stack.addArrangedSubview(pendingSub)
        stack.addArrangedSubview(pendingScroll)
        stack.addArrangedSubview(btnRow)
        pendingCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: pendingCard.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: pendingCard.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: pendingCard.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: pendingCard.trailingAnchor, constant: -16),
        ])
        pendingCard.isHidden = true
        contentStack.insertArrangedSubview(pendingCard, at: 2)
    }

    private func pendingTheme() -> String { viewNight ? "night" : "day" }

    private func nextEmptyTextSlot(side: String) -> String? {
        let t = pendingTheme()
        for pos in ["top", "middle", "end", "single"] {
            let sid = "text:\(side):\(pos)"
            if state["\(sid)|\(t)"] == nil { return sid }
        }
        return nil
    }

    private func cnName(for sid: String) -> String {
        ["text:receiver:top": "左上", "text:receiver:middle": "左中", "text:receiver:end": "左下", "text:receiver:single": "左单",
         "text:sender:top": "右上", "text:sender:middle": "右中", "text:sender:end": "右下", "text:sender:single": "右单"][sid] ?? sid
    }

    private func refreshPending() {
        guard pendingCard != nil else { return }
        pendingCard.isHidden = false  // 待分配常显：没导入图片也显示位置行
        pendingScroll.isHidden = pending.isEmpty
        pendingTitle.text = "待分配（\(pending.count) 张）"
        for v in pendingStack.arrangedSubviews { pendingStack.removeArrangedSubview(v); v.removeFromSuperview() }
        for (i, img) in pending.enumerated() {
            let b = UIButton(type: .custom)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.setImage(img, for: .normal)
            b.imageView?.contentMode = .scaleAspectFill
            b.clipsToBounds = true
            b.layer.cornerRadius = 14
            // 多选：勾上的图蓝边 + 右上角顺序号（按勾的顺序 1、2、3…）。
            let order = selectedPendingOrder.firstIndex(where: { $0 === img })
            b.layer.borderWidth = (order != nil) ? 2 : 1
            b.layer.borderColor = ((order != nil) ? c("accent") : c("line")).cgColor
            b.widthAnchor.constraint(equalToConstant: 72).isActive = true
            b.heightAnchor.constraint(equalToConstant: 72).isActive = true
            b.tag = i
            b.addTarget(self, action: #selector(selectPending(_:)), for: .touchUpInside)
            if let n = order {
                let badge = UILabel(frame: CGRect(x: 50, y: 2, width: 20, height: 20))
                badge.backgroundColor = c("accent")
                badge.textColor = .white
                badge.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
                badge.textAlignment = .center
                badge.text = "\(n + 1)"
                badge.layer.cornerRadius = 10
                badge.clipsToBounds = true
                b.addSubview(badge)
            }
            pendingStack.addArrangedSubview(b)
        }
        let left = nextEmptyTextSlot(side: "receiver")
        let right = nextEmptyTextSlot(side: "sender")
        let hasSel = !selectedPendingOrder.isEmpty
        let selected = positionSelected.indices.filter { positionSelected[$0] }
        let positions = ["top", "middle", "end", "single"]
        let t = pendingTheme()
        func hasTarget(side: String) -> Bool {
            if selected.isEmpty { return nextEmptyTextSlot(side: side) != nil }
            return selected.contains { state["text:\(side):\(positions[$0])|\(t)"] == nil }
        }
        pendingLeftBtn.isEnabled = hasSel && hasTarget(side: "receiver")
        pendingRightBtn.isEnabled = hasSel && hasTarget(side: "sender")
        pendingLeftBtn.alpha = pendingLeftBtn.isEnabled ? 1 : 0.4
        pendingRightBtn.alpha = pendingRightBtn.isEnabled ? 1 : 0.4
        // 位置行一直显示（没导入也显示）；全满时只显示全满提示。
        let full = left == nil && right == nil
        pendingPosRow.isHidden = full
        pendingFullLabel.isHidden = !full
        if full {
            pendingFullLabel.text = "全部已满，可清空重放"
        }
        for (i, b) in pendingPosButtons.enumerated() {
            b.setImage(positionCircleImage(checked: positionSelected[i]), for: .normal)
        }
    }

    // 位置圈：空圈（白底蓝边）或打勾圈（蓝底白勾），20×20，与缩略图徽标同大。
    private func positionCircleImage(checked: Bool) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        return r.image { _ in
            if checked {
                c("accent").setFill()
                UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 20, height: 20)).fill()
                let p = UIBezierPath()
                p.move(to: CGPoint(x: 5, y: 10))
                p.addLine(to: CGPoint(x: 8.5, y: 13.5))
                p.addLine(to: CGPoint(x: 15, y: 6))
                p.lineWidth = 2.5
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                UIColor.white.setStroke()
                p.stroke()
            } else {
                let p = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 18, height: 18))
                p.lineWidth = 2
                c("accent").setStroke()
                p.stroke()
            }
        }
    }

    // 已勾选圈圈：蓝底白字小圆（与缩略图上的勾选徽标同款），放在提示行里按勾的顺序排。
    private func checkedBadgeImage(_ n: Int) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        return r.image { _ in
            c("accent").setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 20, height: 20)).fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let s = "\(n)" as NSString
            let sz = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: (20 - sz.width) / 2, y: (20 - sz.height) / 2), withAttributes: attrs)
        }
    }

    // 提示行：已勾选：① ② ③（圈圈按勾的顺序，字用提示同款 13pt 蓝色）。
    private func checkedOrderText(_ order: [UIImage]) -> NSAttributedString {
        let a = NSMutableAttributedString(string: "已勾选：", attributes: [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: c("accent"),
        ])
        for (i, _) in order.enumerated() {
            if i > 0 { a.append(NSAttributedString(string: " ")) }
            let att = NSTextAttachment()
            att.image = checkedBadgeImage(i + 1)
            att.bounds = CGRect(x: 0, y: -4, width: 20, height: 20)
            a.append(NSAttributedString(attachment: att))
        }
        return a
    }

    private func setCheckedHint(_ label: UILabel, order: [UIImage], full: Bool) {
        if full {
            label.attributedText = nil
            label.text = "全部已满，可清空重放"
        } else if order.isEmpty {
            label.attributedText = nil
            label.text = nil
        } else {
            label.text = nil
            label.attributedText = checkedOrderText(order)
        }
    }

    // 其它工作区的待分配：只放其它气泡，不走文字待分配。
    private func refreshOtherPending() {
        guard otherPendingCard != nil else { return }
        otherBatchRow.isHidden = otherCard.isHidden
        otherPendingCard.isHidden = otherCard.isHidden || pendingOther.isEmpty
        otherPendingTitle.text = "待分配（\(pendingOther.count) 张）"
        for v in otherPendingStack.arrangedSubviews { otherPendingStack.removeArrangedSubview(v); v.removeFromSuperview() }
        for (i, img) in pendingOther.enumerated() {
            let b = UIButton(type: .custom)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.setImage(img, for: .normal)
            b.imageView?.contentMode = .scaleAspectFill
            b.clipsToBounds = true
            b.layer.cornerRadius = 14
            // 多选：勾上的图蓝边 + 右上角顺序号（按勾的顺序 1、2、3…）。
            let order = selectedPendingOtherOrder.firstIndex(where: { $0 === img })
            b.layer.borderWidth = (order != nil) ? 2 : 1
            b.layer.borderColor = ((order != nil) ? c("accent") : c("line")).cgColor
            b.widthAnchor.constraint(equalToConstant: 72).isActive = true
            b.heightAnchor.constraint(equalToConstant: 72).isActive = true
            b.tag = i
            b.addTarget(self, action: #selector(selectPendingOther(_:)), for: .touchUpInside)
            if let n = order {
                let badge = UILabel(frame: CGRect(x: 50, y: 2, width: 20, height: 20))
                badge.backgroundColor = c("accent")
                badge.textColor = .white
                badge.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
                badge.textAlignment = .center
                badge.text = "\(n + 1)"
                badge.layer.cornerRadius = 10
                badge.clipsToBounds = true
                b.addSubview(badge)
            }
            otherPendingStack.addArrangedSubview(b)
        }
        let other = nextEmptyOtherSlot()
        let hasSel = !selectedPendingOtherOrder.isEmpty
        otherPendingOtherBtn.isEnabled = hasSel && other != nil
        otherPendingOtherBtn.alpha = otherPendingOtherBtn.isEnabled ? 1 : 0.4
        // 提示行不再写“下一个”：只显示已勾选的圈圈（按勾的顺序），全满才显示全满。
        setCheckedHint(otherPendingHint, order: selectedPendingOtherOrder, full: other == nil)
    }

    @objc private func selectPendingOther(_ sender: UIButton) {
        let img = pendingOther[sender.tag]
        if let i = selectedPendingOtherOrder.firstIndex(where: { $0 === img }) {
            selectedPendingOtherOrder.remove(at: i)
        } else {
            selectedPendingOtherOrder.append(img)
        }
        refreshOtherPending()
    }

    @objc private func selectPending(_ sender: UIButton) {
        let img = pending[sender.tag]
        if let i = selectedPendingOrder.firstIndex(where: { $0 === img }) {
            selectedPendingOrder.remove(at: i)
        } else {
            selectedPendingOrder.append(img)
        }
        refreshPending()
    }

    @objc private func placePendingLeft() { placePending(side: "receiver") }
    @objc private func placePendingRight() { placePending(side: "sender") }

    @objc private func togglePosition(_ sender: UIButton) {
        positionSelected[sender.tag].toggle()
        refreshPending()
    }

    // 批量放：点选了位置就按点选位置放（没点选位置就按旧规则进下一个空位）；
    // 一张图点选多个位置就重复进每个位置；放完图选和位置选都清掉，图仍留在待分配里（只有清空才走）。
    private func placePending(side: String) {
        let images = selectedPendingOrder
        guard !images.isEmpty else { return }
        let selected = positionSelected.indices.filter { positionSelected[$0] }
        selectedPendingOrder.removeAll()
        positionSelected = [false, false, false, false]
        if selected.isEmpty {
            for img in images {
                guard let sid = nextEmptyTextSlot(side: side) else { break }
                put(img, slotId: sid)
            }
        } else {
            let t = pendingTheme()
            let positions = ["top", "middle", "end", "single"]
            var imgIdx = 0
            for posIdx in selected {
                let sid = "text:\(side):\(positions[posIdx])"
                guard state["\(sid)|\(t)"] == nil else { continue }
                put(images[min(imgIdx, images.count - 1)], slotId: sid)
                imgIdx += 1
            }
        }
    }

    private func nextEmptyOtherSlot() -> String? {
        let t = pendingTheme()
        for s in BubbleNaming.shared.otherSlots() {
            if state["\(s.identifier)|\(t)"] == nil { return s.identifier }
        }
        return nil
    }

    private func otherDesc(for sid: String) -> String {
        BubbleNaming.shared.otherSlots().first(where: { $0.identifier == sid })?.desc ?? sid
    }

    // 批量放：按勾的顺序依次进下一个空其它槽位；放完勾清掉，图仍留在待分配里（只有清空才走）。
    @objc private func placePendingOther() {
        let order = selectedPendingOtherOrder
        selectedPendingOtherOrder.removeAll()
        for img in order {
            guard let sid = nextEmptyOtherSlot() else { break }
            put(img, slotId: sid)
        }
    }

    private func pillButton(_ title: String, primary: Bool, insets: UIEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)) -> PillButton {
        // PillButton：底和边框走 CAShapeLayer，见 PillButton 上的注释。
        let b = PillButton(frame: .zero)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.titleLabel?.font = UIFont.systemFont(ofSize: 13)
        b.contentEdgeInsets = insets
        b.setTitle(title, for: .normal)
        if primary {
            b.fillColor = c("accent")
            b.setTitleColor(.white, for: .normal)
        } else {
            b.strokeColor = c("line")
            b.setTitleColor(c("text2"), for: .normal)
        }
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    private func buildToolbar() {
        toolbar = UIView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.layer.cornerRadius = 22
        toolbar.layer.borderWidth = 1

        // 工具栏不再是一行横排：换行排布，控件按内容宽度摆放，
        // 空间不够就折到下一行，绝不压缩截断出 "…"。
        toolbarFlow = FlowLayoutView()
        toolbarFlow.translatesAutoresizingMaskIntoConstraints = false
        toolbarFlow.hSpacing = 14

        modeSeg = PillGroup(titles: ["中文名", "英文名"], selected: 0)
        modeSeg.onChange = { [weak self] _ in self?.modeChanged() }
        toolbarFlow.addSubview(groupWithLabel("命名", views: [modeSeg]))

        scaleBtn = pillButton(scaleMenuTitle(), primary: false, insets: UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14))
        scaleBtn.showsMenuAsPrimaryAction = true
        refreshScaleMenu()
        toolbarFlow.addSubview(groupWithLabel("倍数", views: [scaleBtn]))

        nightSeg = PillGroup(titles: ["不做", "要做"], selected: 0)
        nightSeg.onChange = { [weak self] _ in self?.nightChanged() }
        viewSeg = PillGroup(titles: ["日间", "夜间"], selected: 0)
        viewSeg.isHidden = true
        viewSeg.onChange = { [weak self] _ in self?.viewChanged() }
        toolbarFlow.addSubview(groupWithLabel("夜间版", views: [nightSeg, viewSeg]))

        batchBtn = pillButton("批量导图", primary: false)
        batchBtn.addTarget(self, action: #selector(batch), for: .touchUpInside)
        copyBtn = pillButton("复制日间到夜间", primary: false)
        copyBtn.isHidden = true
        copyBtn.addTarget(self, action: #selector(copyDayToNight), for: .touchUpInside)
        clearBtn = pillButton("清空", primary: false)
        clearBtn.addTarget(self, action: #selector(clearAll), for: .touchUpInside)
        exportBtn = pillButton("导出 zip", primary: true)
        // 网页版主按钮更大：14pt 半粗 + 10/22 内边距 + 蓝色光晕（颜色跟随主题，见 applyTheme）。
        exportBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        exportBtn.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        exportBtn.glowOpacity = 0.32
        exportBtn.glowRadius = 12
        exportBtn.glowOffset = CGSize(width: 0, height: 3)
        exportBtn.addTarget(self, action: #selector(doExport), for: .touchUpInside)
        for b in [batchBtn, copyBtn, clearBtn, exportBtn] {
            if let b { toolbarFlow.addSubview(b) }
        }

        toolbar.addSubview(toolbarFlow)
        NSLayoutConstraint.activate([
            toolbarFlow.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 12),
            toolbarFlow.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -12),
            toolbarFlow.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            toolbarFlow.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -16),
        ])
        contentStack.addArrangedSubview(toolbar)
    }

    private func groupWithLabel(_ label: String, views: [UIView]) -> GroupContainer {
        GroupContainer(labelText: label, groups: views)
    }

    // MARK: - 手机框

    private func buildPhone() {
        phoneCard = UIView()
        phoneCard.translatesAutoresizingMaskIntoConstraints = false
        phoneCard.layer.cornerRadius = 18
        phoneCard.layer.borderWidth = 1
        phoneCard.clipsToBounds = true

        navView = UIView()
        navView.translatesAutoresizingMaskIntoConstraints = false
        navView.layer.borderWidth = 1
        let back = UILabel()
        back.text = "‹"
        back.font = UIFont.systemFont(ofSize: 22)
        let name = UILabel()
        name.text = "微信"
        name.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        name.textAlignment = .center
        let more = UILabel()
        more.text = "⋯"
        more.font = UIFont.systemFont(ofSize: 19)
        phoneTip = UILabel()
        phoneTip.font = UIFont.systemFont(ofSize: 11)
        // 网页版结构：返回/更多在左、标题绝对居中、提示在右。
        // 旧代码把提示塞进通栏横排，长提示会一路压到居中的标题上 —— 改成网页版这样分开。
        let navRow = UIStackView(arrangedSubviews: [back, more])
        navRow.axis = .horizontal
        navRow.spacing = 0
        navRow.alignment = .center
        navView.addSubview(name)
        navView.addSubview(navRow)
        navView.addSubview(phoneTip)
        name.translatesAutoresizingMaskIntoConstraints = false
        navRow.translatesAutoresizingMaskIntoConstraints = false
        phoneTip.translatesAutoresizingMaskIntoConstraints = false
        phoneTip.alpha = 0.65
        NSLayoutConstraint.activate([
            navView.heightAnchor.constraint(equalToConstant: 44),
            name.centerXAnchor.constraint(equalTo: navView.centerXAnchor),
            name.centerYAnchor.constraint(equalTo: navView.centerYAnchor),
            navRow.leadingAnchor.constraint(equalTo: navView.leadingAnchor, constant: 12),
            navRow.topAnchor.constraint(equalTo: navView.topAnchor),
            navRow.bottomAnchor.constraint(equalTo: navView.bottomAnchor),
            phoneTip.trailingAnchor.constraint(equalTo: navView.trailingAnchor, constant: -12),
            phoneTip.centerYAnchor.constraint(equalTo: navView.centerYAnchor),
        ])

        chatStack = UIStackView()
        chatStack.translatesAutoresizingMaskIntoConstraints = false
        chatStack.axis = .vertical
        chatStack.spacing = 9
        chatStack.alignment = .fill
        // 聊天底要贴满手机框（白边就是这里左右各 12 的留空露出的卡底色）；
        // 气泡原来的间距改由 layoutMargins 保留，画面位置一点不动。
        chatStack.isLayoutMarginsRelativeArrangement = true
        chatStack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 4, right: 12)

        inputBar = UIView()
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.layer.borderWidth = 1
        let inRow = UIStackView()
        inRow.axis = .horizontal
        inRow.spacing = 9
        inRow.alignment = .center
        inRow.translatesAutoresizingMaskIntoConstraints = false
        let voice = wxInputChip("语音")
        let box = UIView()
        box.layer.cornerRadius = 5
        box.layer.borderWidth = 1
        box.backgroundColor = c("wxInputBg")
        box.layer.borderColor = c("wxNavLine").cgColor
        // 旧代码里这个输入框没有高度：横排里纵向无内在尺寸会被压成 0 高，
        // 看起来就是“缺中间输入框” —— 网页版是 32pt 高，横向仍占满剩余宽度。
        box.heightAnchor.constraint(equalToConstant: 32).isActive = true
        box.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        let emoji = wxInputChip("表情")
        let moreIc = wxInputChip("更多")
        inRow.addArrangedSubview(voice)
        inRow.addArrangedSubview(box)
        inRow.addArrangedSubview(emoji)
        inRow.addArrangedSubview(moreIc)
        inputBar.addSubview(inRow)
        NSLayoutConstraint.activate([
            inputBar.heightAnchor.constraint(equalToConstant: 50),
            inRow.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            inRow.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -12),
            inRow.topAnchor.constraint(equalTo: inputBar.topAnchor),
            inRow.bottomAnchor.constraint(equalTo: inputBar.bottomAnchor),
        ])

        phoneCard.addSubview(navView)
        phoneCard.addSubview(chatStack)
        phoneCard.addSubview(inputBar)
        NSLayoutConstraint.activate([
            navView.topAnchor.constraint(equalTo: phoneCard.topAnchor),
            navView.leadingAnchor.constraint(equalTo: phoneCard.leadingAnchor),
            navView.trailingAnchor.constraint(equalTo: phoneCard.trailingAnchor),
            chatStack.topAnchor.constraint(equalTo: navView.bottomAnchor),
            chatStack.leadingAnchor.constraint(equalTo: phoneCard.leadingAnchor),
            chatStack.trailingAnchor.constraint(equalTo: phoneCard.trailingAnchor),
            inputBar.topAnchor.constraint(equalTo: chatStack.bottomAnchor),
            inputBar.leadingAnchor.constraint(equalTo: phoneCard.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: phoneCard.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: phoneCard.bottomAnchor),
        ])
        contentStack.addArrangedSubview(phoneCard)
    }

    private func wxInputChip(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont.systemFont(ofSize: 10.5)
        l.textAlignment = .center
        l.layer.cornerRadius = 12
        l.layer.borderWidth = 1
        l.layer.masksToBounds = true
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.heightAnchor.constraint(equalToConstant: 24).isActive = true
        l.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        return l
    }

    // MARK: - 统计 / 说明 / 其它气泡手机框

    private func buildSummaryAndNote() {
        summaryLabel = UILabel()
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.font = UIFont.systemFont(ofSize: 13)
        summaryLabel.numberOfLines = 0
        contentStack.addArrangedSubview(summaryLabel)

        progressBar = UIView()
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.layer.cornerRadius = 2
        progressBar.backgroundColor = c("line")
        let fill = UIView()
        fill.backgroundColor = c("ok")
        fill.layer.cornerRadius = 2
        fill.translatesAutoresizingMaskIntoConstraints = false
        progressBar.addSubview(fill)
        progressFillW = fill.widthAnchor.constraint(equalTo: progressBar.widthAnchor, multiplier: 0)
        NSLayoutConstraint.activate([
            progressBar.heightAnchor.constraint(equalToConstant: 4),
            fill.topAnchor.constraint(equalTo: progressBar.topAnchor),
            fill.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor),
            fill.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
            progressFillW,
        ])
        contentStack.addArrangedSubview(progressBar)

        noteLabel = UILabel()
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.font = UIFont.systemFont(ofSize: 12.5)
        noteLabel.numberOfLines = 0
        contentStack.addArrangedSubview(noteLabel)
    }

    private func buildOtherPhone() {
        otherToggle = PillButton(frame: .zero)
        otherToggle.translatesAutoresizingMaskIntoConstraints = false
        otherToggle.setTitle("红包 / 语音 / 卡片等其它气泡（32 个，可选项）", for: .normal)
        otherToggle.setTitleColor(c("accent"), for: .normal)
        otherToggle.titleLabel?.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        otherToggle.contentHorizontalAlignment = .center
        otherToggle.strokeColor = c("line")
        otherToggle.addTarget(self, action: #selector(toggleOther), for: .touchUpInside)
        contentStack.addArrangedSubview(otherToggle)

        otherCard = UIView()
        otherCard.translatesAutoresizingMaskIntoConstraints = false
        otherCard.layer.cornerRadius = 18
        otherCard.layer.borderWidth = 1
        otherCard.clipsToBounds = true
        otherCard.isHidden = true

        let nav = UIView()
        nav.translatesAutoresizingMaskIntoConstraints = false
        nav.layer.borderWidth = 1
        // 网页版其它框的导航栏同样有返回/更多（旧代码只有标题和提示）。
        let back2 = UILabel()
        back2.text = "‹"
        back2.font = UIFont.systemFont(ofSize: 22)
        let more2 = UILabel()
        more2.text = "⋯"
        more2.font = UIFont.systemFont(ofSize: 19)
        let n2 = UILabel()
        n2.text = "微信"
        n2.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        n2.textAlignment = .center
        let tip2 = UILabel()
        tip2.text = "批量导入放图"
        tip2.font = UIFont.systemFont(ofSize: 11)
        tip2.alpha = 0.65
        let leftR = UIStackView(arrangedSubviews: [back2, more2])
        leftR.axis = .horizontal
        leftR.spacing = 0
        leftR.alignment = .center
        let navR = UIStackView(arrangedSubviews: [tip2])
        navR.axis = .horizontal
        nav.translatesAutoresizingMaskIntoConstraints = false
        nav.addSubview(n2)
        nav.addSubview(leftR)
        nav.addSubview(navR)
        n2.translatesAutoresizingMaskIntoConstraints = false
        leftR.translatesAutoresizingMaskIntoConstraints = false
        navR.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nav.heightAnchor.constraint(equalToConstant: 44),
            n2.centerXAnchor.constraint(equalTo: nav.centerXAnchor),
            n2.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
            leftR.leadingAnchor.constraint(equalTo: nav.leadingAnchor, constant: 12),
            leftR.topAnchor.constraint(equalTo: nav.topAnchor),
            leftR.bottomAnchor.constraint(equalTo: nav.bottomAnchor),
            navR.trailingAnchor.constraint(equalTo: nav.trailingAnchor, constant: -12),
            navR.centerYAnchor.constraint(equalTo: nav.centerYAnchor),
        ])

        otherChatStack = UIStackView()
        otherChatStack.translatesAutoresizingMaskIntoConstraints = false
        otherChatStack.axis = .vertical
        otherChatStack.spacing = 9
        otherChatStack.alignment = .fill
        otherChatStack.isLayoutMarginsRelativeArrangement = true
        otherChatStack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 4, right: 12)

        let inBar = UIView()
        inBar.translatesAutoresizingMaskIntoConstraints = false
        inBar.layer.borderWidth = 1
        let ir = UIStackView()
        ir.axis = .horizontal
        ir.spacing = 9
        ir.alignment = .center
        ir.translatesAutoresizingMaskIntoConstraints = false
        ir.addArrangedSubview(wxInputChip("语音"))
        let bx = UIView()
        bx.layer.cornerRadius = 5
        bx.layer.borderWidth = 1
        bx.backgroundColor = c("wxInputBg")
        bx.layer.borderColor = c("wxNavLine").cgColor
        bx.heightAnchor.constraint(equalToConstant: 32).isActive = true
        bx.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        ir.addArrangedSubview(bx)
        ir.addArrangedSubview(wxInputChip("表情"))
        ir.addArrangedSubview(wxInputChip("更多"))
        inBar.addSubview(ir)
        NSLayoutConstraint.activate([
            inBar.heightAnchor.constraint(equalToConstant: 50),
            ir.leadingAnchor.constraint(equalTo: inBar.leadingAnchor, constant: 12),
            ir.trailingAnchor.constraint(equalTo: inBar.trailingAnchor, constant: -12),
            ir.topAnchor.constraint(equalTo: inBar.topAnchor),
            ir.bottomAnchor.constraint(equalTo: inBar.bottomAnchor),
        ])

        otherCard.addSubview(nav)
        otherCard.addSubview(otherChatStack)
        otherCard.addSubview(inBar)
        NSLayoutConstraint.activate([
            nav.topAnchor.constraint(equalTo: otherCard.topAnchor),
            nav.leadingAnchor.constraint(equalTo: otherCard.leadingAnchor),
            nav.trailingAnchor.constraint(equalTo: otherCard.trailingAnchor),
            otherChatStack.topAnchor.constraint(equalTo: nav.bottomAnchor),
            otherChatStack.leadingAnchor.constraint(equalTo: otherCard.leadingAnchor),
            otherChatStack.trailingAnchor.constraint(equalTo: otherCard.trailingAnchor),
            inBar.topAnchor.constraint(equalTo: otherChatStack.bottomAnchor),
            inBar.leadingAnchor.constraint(equalTo: otherCard.leadingAnchor),
            inBar.trailingAnchor.constraint(equalTo: otherCard.trailingAnchor),
            inBar.bottomAnchor.constraint(equalTo: otherCard.bottomAnchor),
        ])
        contentStack.addArrangedSubview(otherCard)
        otherNav = nav
        otherInBar = inBar
        buildOtherPending()
    }

    // 其它工作区自有的一套：批量导图行 + 待分配卡（只放其它气泡），插在开关与手机框之间。
    private func buildOtherPending() {
        otherBatchRow = UIView()
        otherBatchRow.translatesAutoresizingMaskIntoConstraints = false
        otherBatchBtn = pillButton("批量导图", primary: false)
        otherBatchBtn.addTarget(self, action: #selector(otherBatch), for: .touchUpInside)
        otherBatchRow.addSubview(otherBatchBtn)
        NSLayoutConstraint.activate([
            otherBatchBtn.topAnchor.constraint(equalTo: otherBatchRow.topAnchor),
            otherBatchBtn.bottomAnchor.constraint(equalTo: otherBatchRow.bottomAnchor),
            otherBatchBtn.leadingAnchor.constraint(equalTo: otherBatchRow.leadingAnchor),
        ])

        otherPendingCard = UIView()
        otherPendingCard.translatesAutoresizingMaskIntoConstraints = false
        otherPendingCard.layer.cornerRadius = 22
        otherPendingCard.layer.borderWidth = 1
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        otherPendingTitle = UILabel()
        otherPendingTitle.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        otherPendingSub = UILabel()
        otherPendingSub.font = UIFont.systemFont(ofSize: 13)
        otherPendingSub.text = "点一张图，再选放其它"
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        otherPendingStack = UIStackView()
        otherPendingStack.axis = .horizontal
        otherPendingStack.spacing = 10
        otherPendingStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(otherPendingStack)
        NSLayoutConstraint.activate([
            otherPendingStack.topAnchor.constraint(equalTo: scroll.topAnchor),
            otherPendingStack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            otherPendingStack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            otherPendingStack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            otherPendingStack.heightAnchor.constraint(equalToConstant: 72),
        ])
        scroll.heightAnchor.constraint(equalToConstant: 72).isActive = true
        let btnRow = UIStackView()
        btnRow.axis = .horizontal
        btnRow.spacing = 12
        btnRow.alignment = .center
        otherPendingOtherBtn = pillButton("放其它", primary: false)
        otherPendingOtherBtn.addTarget(self, action: #selector(placePendingOther), for: .touchUpInside)
        otherPendingHint = UILabel()
        otherPendingHint.font = UIFont.systemFont(ofSize: 13)
        otherPendingHint.numberOfLines = 0
        btnRow.addArrangedSubview(otherPendingOtherBtn)
        btnRow.addArrangedSubview(otherPendingHint)
        stack.addArrangedSubview(otherPendingTitle)
        stack.addArrangedSubview(otherPendingSub)
        stack.addArrangedSubview(scroll)
        stack.addArrangedSubview(btnRow)
        otherPendingCard.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: otherPendingCard.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: otherPendingCard.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: otherPendingCard.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: otherPendingCard.trailingAnchor, constant: -16),
        ])
        otherBatchRow.isHidden = true
        otherPendingCard.isHidden = true
        if let idx = contentStack.arrangedSubviews.firstIndex(of: otherCard) {
            contentStack.insertArrangedSubview(otherBatchRow, at: idx)
            contentStack.insertArrangedSubview(otherPendingCard, at: idx + 1)
        }
    }

    // MARK: - 构建气泡

    private func textSlot(side: BubbleSide, pos: BubblePosition) -> BubbleSlot? {
        BubbleNaming.shared.textSlots().first { $0.side == side && $0.position == pos }
    }

    private func messageRow(for slot: BubbleSlot, isOther: Bool) -> UIView {
        let bub = BubbleView()
        bub.isMine = slot.side == .sender
        bub.position = slot.position
        bub.isOther = isOther
        bub.category = isOther ? slot.type : nil
        let sid = slot.identifier
        bub.onDelete = { [weak self] in self?.removeSlotId(sid) }
        if isOther { otherBubbles[sid] = bub } else { textBubbles[sid] = bub }

        let fn = UILabel()
        fn.font = UIFont.systemFont(ofSize: 11)
        fn.numberOfLines = 0
        fn.textColor = c("text2")
        fn.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        if isOther { otherFileNames[sid] = fn } else { textFileNames[sid] = fn }

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        if bub.isMine {
            fn.textAlignment = .right
            row.addArrangedSubview(fn)
            row.addArrangedSubview(bub)
        } else {
            row.addArrangedSubview(bub)
            row.addArrangedSubview(fn)
        }

        bub.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        bub.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        if isOther {
            let min: [String: (CGFloat, CGFloat)] = [
                "hb": (206, 88), "aa": (196, 86), "gift": (196, 86),
                "app": (224, 84), "common": (224, 84), "voice": (148, 40),
            ]
            if let m = min[slot.type] {
                bub.widthAnchor.constraint(greaterThanOrEqualToConstant: m.0).isActive = true
                bub.heightAnchor.constraint(greaterThanOrEqualToConstant: m.1).isActive = true
            }
        }
        return row
    }

    private func buildChat() {
        let time = UILabel()
        time.text = "下午 8:07"
        time.font = UIFont.systemFont(ofSize: 11)
        time.textAlignment = .center
        chatStack.addArrangedSubview(time)

        let seq = ["r0", "r1", "r2", "s0", "s1", "s2", "gap", "r3", "gap", "s3"]
        for it in seq {
            if it == "gap" {
                let g = UIView()
                g.translatesAutoresizingMaskIntoConstraints = false
                g.heightAnchor.constraint(equalToConstant: 18).isActive = true
                chatStack.addArrangedSubview(g)
                continue
            }
            let sender = it.hasPrefix("s")
            let pos = Int(String(it.dropFirst())) ?? 0
            guard let s = textSlot(side: sender ? .sender : .receiver,
                                   pos: BubblePosition(rawValue: pos) ?? .single) else { continue }
            chatStack.addArrangedSubview(messageRow(for: s, isOther: false))
        }
    }

    private func buildOtherChat() {
        for cat in ["hb", "aa", "gift", "app", "common", "voice"] {
            let items = BubbleNaming.shared.otherSlots()
                .filter { $0.type == cat }
                .sorted { $0.identifier < $1.identifier }
            if items.isEmpty { continue }
            let gt = UILabel()
            gt.text = bubbleCatGroup[cat]
            gt.font = UIFont.systemFont(ofSize: 11)
            gt.textAlignment = .center
            otherChatStack.addArrangedSubview(gt)
            for s in items {
                otherChatStack.addArrangedSubview(messageRow(for: s, isOther: true))
            }
        }
    }

    // MARK: - 刷新

    private func refresh() {
        let night = viewNight
        applyPhoneNight(night)

        let upd: (BubbleSlot, BubbleView, UILabel) -> Void = { [weak self] slot, bub, fn in
            guard let self else { return }
            let theme = night ? "night" : "day"
            let it = self.state["\(slot.identifier)|\(theme)"]
            if let it {
                // 微信使用效果：图是气泡皮，拉伸铺满气泡当背景，字在上面；
                // 气泡大小按消息内容，文件名下只写原图尺寸，不再写显示尺寸。
                let txt = bub.isOther ? slot.desc : slot.cnName
                bub.showImage(it.image, placeholderText: txt)
                fn.text = String(format: "%@\n%ld×%ld",
                                 self.outName(slot, theme: theme), it.w, it.h)
            } else {
                let txt = bub.isOther ? slot.desc : slot.cnName
                bub.showEmpty(withText: txt)
                fn.text = self.outName(slot, theme: theme)
            }
            // 先放图/放空，再着色：边框只画在空心气泡上，放图后由 showImage 清掉。
            self.colorBubble(bub, slot: slot, night: night)
            fn.textColor = self.c("text2")
        }

        for s in BubbleNaming.shared.textSlots() {
            if let bub = textBubbles[s.identifier], let fn = textFileNames[s.identifier] {
                upd(s, bub, fn)
            }
        }
        for s in BubbleNaming.shared.otherSlots() {
            if let bub = otherBubbles[s.identifier], let fn = otherFileNames[s.identifier] {
                upd(s, bub, fn)
            }
        }
        // 英文文件名开关：隐藏时只透明、不移出布局，气泡保持原来大小和位置，不被拉满。
        // 只改显示，导出直接读槽位数据算名字，不读这行字，导出不受影响。
        for fn in otherFileNames.values { fn.alpha = hideEnglishFileNames ? 0 : 1 }
        for fn in textFileNames.values { fn.alpha = (hideEnglishFileNames && mode == 1) ? 0 : 1 }

        updateSummary()
        // 工具栏是自动换行排布：可见控件变化（夜间版开关、复制按钮显隐）后重排。
        // updateSummary 本身的统计逻辑一字没动，这里只刷新工具栏布局。
        toolbarFlow.setNeedsLayout()
        toolbarFlow.invalidateIntrinsicContentSize()
        refreshPending()
        refreshOtherPending()
    }

    private func colorBubble(_ bub: BubbleView, slot: BubbleSlot, night: Bool) {
        if bub.isOther {
            let map: [String: [String]] = [
                "hb": ["#fa9d3b", "#ffffff", "#7a4412", "#ffffff"],
                "aa": ["#f7c14c", "#5a3c00", "#6d5215", "#e8d9a0"],
                "gift": ["#f07c7c", "#ffffff", "#7a3030", "#ffffff"],
                "app": ["#ffffff", "#1b1d20", "#2c2c2e", "#e9ebee"],
                "common": ["#f2f4f7", "#1b1d20", "#33363c", "#e9ebee"],
                "voice": ["#ffffff", "#1b1d20", "#2c2c2e", "#e9ebee"],
            ]
            let mask = slot.identifier.contains("mask")
            let i = night ? 2 : 0
            let ti = night ? 3 : 1
            let arr = map[slot.type]
            let bg = mask ? bubbleColor(hex: night ? "#33363c" : "#e9ecf0")
                          : bubbleColor(hex: arr?[i] ?? "#000000")
            // 空格子底色加深：遮罩、通用卡片底的官方淡色在浅底上看不见；
            // 只加深空位显示，尾巴颜色与已放图气泡不动，导出也不受影响。
            let emptyBg: UIColor
            if !night && mask {
                emptyBg = bubbleColor(hex: "#d8dde3")
            } else if !night && slot.type == "common" {
                emptyBg = bubbleColor(hex: "#dfe4e9")
            } else {
                emptyBg = bg
            }
            let tx = mask ? bubbleColor(hex: night ? "#e9ebee" : "#1b1d20")
                          : bubbleColor(hex: arr?[ti] ?? "#000000")
            if bub.imageView.isHidden {
                bub.backgroundColor = emptyBg
                if mask {
                    bub.setDashedBorder(bubbleColor(hex: night ? "#565c66" : "#b6bdc6"), width: 1.0)
                } else {
                    // 网页版其它气泡空心时也有虚线边框（旧代码这里是没边框）。
                    bub.setDashedBorder(bubbleColor(hex: night ? "#6a7079" : "#c2c7cd"), width: 1.5)
                }
            } else {
                bub.setDashedBorder(nil)
            }
            bub.tailColor = bg
            bub.placeholder.textColor = tx
            bub.redrawTail()
            return
        }
        let bg = slot.side == .sender
            ? (night ? c("mineNight") : c("mine"))
            : (night ? c("bubNight") : c("bub"))
        // 网页版空心边框：日间 #c2c7cd、夜间 #6a7079（虚线，见 setDashedBorder）。
        // ObjC 版夜间用的 "bubLine" 不在颜色表里，c() 会回落黑色 —— 不再照搬。
        let border = night ? bubbleColor(hex: "#6a7079") : bubbleColor(hex: "#c2c7cd")
        bub.applyBubbleColor(bg, border: border)
        bub.placeholder.textColor = UIColor(white: night ? 0.6 : 0.45, alpha: 1)
    }

    private func applyPhoneNight(_ night: Bool) {
        let navBg = night ? bubbleColor(hex: "#1c1c1e") : c("wxNav")
        let navLine = night ? bubbleColor(hex: "#2e2e30") : c("wxNavLine")
        let navTx = night ? bubbleColor(hex: "#e5e5e7") : c("wxNavTx")
        // 输入栏跟随手机日间/夜间：旧代码用 c() 取色，c() 跟页面主题（已无切换入口、恒为浅色），
        // 夜间编辑时输入框还是白色。改按 night 取色，与夜色表、网页版夜间一致。
        let inBg = night ? bubbleColor(hex: "#2c2c2e") : c("wxInputBg")
        let inLine = night ? bubbleColor(hex: "#2e2e30") : c("wxNavLine")
        let inIc = night ? bubbleColor(hex: "#8a8a90") : c("wxIc")
        navView.backgroundColor = navBg
        navView.layer.borderColor = navLine.cgColor
        // ObjC 版只重着 navView 的直接 UILabel 子视图，返回/更多标号在 navRow 里，
        // 夜间切换后会看不见；这里递归重着整条导航栏（标题、返回、更多、提示同色）。
        func recolorNavLabels(_ view: UIView) {
            if let label = view as? UILabel { label.textColor = navTx }
            for sub in view.subviews { recolorNavLabels(sub) }
        }
        recolorNavLabels(navView)
        phoneTip.textColor = navTx
        chatStack.backgroundColor = night ? c("chatNight") : c("chat")
        inputBar.backgroundColor = navBg
        inputBar.layer.borderColor = navLine.cgColor
        phoneCard.backgroundColor = c("card")
        phoneCard.layer.borderColor = c("line").cgColor
        for v in inputBar.subviews {
            guard let stack = v as? UIStackView else { continue }
            for x in stack.arrangedSubviews {
                if let label = x as? UILabel {
                    label.textColor = inIc
                    label.layer.borderColor = inIc.cgColor
                } else if x.layer.borderWidth > 0 {
                    x.layer.borderColor = inLine.cgColor
                    x.backgroundColor = inBg
                }
            }
        }

        // 其它气泡卡的手机框跟主框走同一套日间/夜间（网页版两个框都变色；旧代码只刷了主框，
        // 其它框的导航、聊天底、输入栏全停在初始色，夜间尤其明显）。
        otherNav.backgroundColor = navBg
        otherNav.layer.borderColor = navLine.cgColor
        recolorNavLabels(otherNav)
        otherChatStack.backgroundColor = night ? c("chatNight") : c("chat")
        otherInBar.backgroundColor = navBg
        otherInBar.layer.borderColor = navLine.cgColor
        for v in otherInBar.subviews {
            guard let stack = v as? UIStackView else { continue }
            for x in stack.arrangedSubviews {
                if let label = x as? UILabel {
                    label.textColor = inIc
                    label.layer.borderColor = inIc.cgColor
                } else if x.layer.borderWidth > 0 {
                    x.layer.borderColor = inLine.cgColor
                    x.backgroundColor = inBg
                }
            }
        }
        // 主聊天区的时间（下午 8:07）跟随手机日间/夜间（网页版 .chattime 用 wx-time，夜间框再压一层）。
        let wxTime = night ? bubbleColor(hex: "#6b6b70") : c("wxTime")
        for v in chatStack.arrangedSubviews {
            if let label = v as? UILabel { label.textColor = wxTime }
        }
    }

    // MARK: - 主题与文件名 / 倍数

    private func applyTheme() {
        view.backgroundColor = c("bg")
        scrollView.backgroundColor = c("bg")
        headerTitle.text = "气泡包制作器"
        headerSub.text = "批量导入放图 自动按规则命名 导出即可使用"
        headerTitle.textColor = c("text")
        headerSub.textColor = c("text3")
        fileBtn.strokeColor = c("line")
        fileBtn.setTitleColor(c("text2"), for: .normal)
        fileBtn.setTitle(fileBtnTitle(), for: .normal)

        toolbar.backgroundColor = c("card")
        toolbar.layer.borderColor = c("line").cgColor
        for v in toolbarFlow.subviews {
            guard let group = v as? GroupContainer else { continue }
            group.backgroundColor = c("bg")
            group.label.textColor = c("text3")
            group.refreshPillColors(track: c("line"), thumb: dark ? bubbleColor(hex: "#3A3A3C") : .white, selected: c("text"), plain: c("text2"))
        }
        for b in [batchBtn, copyBtn, clearBtn, scaleBtn, pendingLeftBtn, pendingRightBtn, otherBatchBtn, otherPendingOtherBtn] {
            b?.strokeColor = c("line")
            b?.setTitleColor(c("text2"), for: .normal)
        }
        pendingCard.backgroundColor = c("card")
        pendingCard.layer.borderColor = c("line").cgColor
        pendingTitle.textColor = c("text")
        pendingSub.textColor = c("text3")
        pendingPosLabel.textColor = c("accent")
        for ch in pendingPosChars { ch.textColor = c("accent") }
        pendingFullLabel.textColor = c("accent")
        otherPendingCard.backgroundColor = c("card")
        otherPendingCard.layer.borderColor = c("line").cgColor
        otherPendingTitle.textColor = c("text")
        otherPendingSub.textColor = c("text3")
        otherPendingHint.textColor = c("accent")
        exportBtn.fillColor = c("accent")
        exportBtn.glowColor = c("accent")

        summaryLabel.textColor = c("text2")
        progressBar.backgroundColor = c("line")
        noteLabel.textColor = c("text2")
        noteLabel.backgroundColor = .clear

        otherToggle.strokeColor = c("line")
        otherToggle.setTitleColor(c("accent"), for: .normal)
        otherCard.backgroundColor = c("card")
        otherCard.layer.borderColor = c("line").cgColor
        // 其它区组标题（红包/转账/…）跟随页面主题的 wx-time 色（网页版 .grouptitle）。
        for v in otherChatStack.arrangedSubviews {
            if let label = v as? UILabel { label.textColor = c("wxTime") }
        }
    }

    // scaleOpt：0 自动 1 不写 2 @2x 3 @3x。分段顺序是 自动/@3x/@2x/不写，
    // ObjC 版 scaleChanged 直接取 selectedSegmentIndex，等于把 @3x 和 不写标反了；
    // 这里按按钮文字修正映射（点什么就是什么）。
    private func scaleValue(w: Int, h: Int) -> Int {
        if scaleOpt == 3 { return 3 }
        if scaleOpt == 2 { return 2 }
        if scaleOpt == 1 { return 1 }
        return max(w, h) > 120 ? 3 : 1
    }

    private func suffixForScale(_ sc: Int) -> String {
        if sc == 3 { return "@3x" }
        if sc == 2 { return "@2x" }
        return ""
    }

    /// 与 ObjC 版 outName:theme: 一致（含原生名里的 ".png" 去除；真实规则数据里没有 .png，故无实际影响）。
    /// placed 传了就用它的实际尺寸算倍数后缀（夜间导出沿用日间图时用得上），不传则查当前槽位。
    private func outName(_ slot: BubbleSlot, theme: String, placed: PlacedImage? = nil) -> String {
        let night = theme == "night"
        let dir = (mode == 0 && night && !slot.cnName.isEmpty) ? "夜间/" : ""
        let sfx: String
        if let it = placed ?? state["\(slot.identifier)|\(theme)"] {
            sfx = suffixForScale(scaleValue(w: it.w, h: it.h))
        } else {
            sfx = scaleOpt == 1 ? "" : (scaleOpt == 2 ? "@2x" : "@3x")
        }
        let base: String
        if mode == 0 && !slot.cnName.isEmpty {
            base = slot.cnName
        } else {
            base = slot.nativeName.replacingOccurrences(of: ".png", with: "") + (night ? "_Dark" : "")
        }
        return "\(dir)\(base)\(sfx).png"
    }

    // MARK: - 统计

    private func updateSummary() {
        let need = BubbleNaming.shared.textSlots().count
        var day = 0
        var night = 0
        var other = 0
        for s in BubbleNaming.shared.textSlots() {
            if state["\(s.identifier)|day"] != nil { day += 1 }
            if state["\(s.identifier)|night"] != nil { night += 1 }
        }
        for s in BubbleNaming.shared.otherSlots() {
            if state["\(s.identifier)|day"] != nil || state["\(s.identifier)|night"] != nil {
                other += 1
            }
        }

        var tip = day == need ? "齐了，可以导出" : "文字气泡 8 个位置放满才能导出"
        if wantsNight && night < need {
            tip = "可以导出；夜间没放图的会沿用日间那张"
        }

        var txt = "日间 \(day)/\(need)"
        if wantsNight {
            txt += "   夜间 \(night)/\(need)"
        }
        txt += "   其它气泡 \(other)"
        if !unrecognized.isEmpty {
            let names = unrecognized.prefix(3).map { $0.name }.joined(separator: "、")
            let more = unrecognized.count > 3 ? " 等 \(unrecognized.count) 张" : ""
            txt += "\n⚠️ \(unrecognized.count) 张未识别（不导出）：\(names)\(more)"
        }
        summaryLabel.text = "\(txt)\n\(tip)"

        let pct: CGFloat = need != 0 ? CGFloat(day) / CGFloat(need) : 0
        progressFillW.isActive = false
        progressFillW = progressBar.subviews.first?.widthAnchor.constraint(equalTo: progressBar.widthAnchor, multiplier: pct)
        progressFillW?.isActive = true

        phoneTip.text = "正在编辑\(viewNight ? "夜间版" : "日间版") · 当前命名：\(mode == 0 ? "中文名" : "微信英文名")"
        copyBtn.isHidden = !wantsNight
        exportBtn.isEnabled = day == need
        viewSeg.isHidden = !wantsNight
        noteLabel.text = mode == 0
            ? "中文名：文字气泡用「左上」这种名字，夜间版自动放进 zip 里的「夜间」文件夹。红包等其它气泡只能用英文原名，导出时会自动用英文名。"
            : "微信英文名：用微信原生文件名，夜间版在名字末尾加 _Dark。需要按下态的话，手动把文件名加上 _HL 再放进包里。"
    }

    // MARK: - 主题 / 交互

    // 标题栏文件名开关：标题在“文件名：显示 / 文件名：隐藏”之间切换，只改显示。
    private func fileBtnTitle() -> String {
        hideEnglishFileNames ? "文件名：隐藏" : "文件名：显示"
    }

    @objc private func toggleFileNames() {
        hideEnglishFileNames.toggle()
        fileBtn.setTitle(fileBtnTitle(), for: .normal)
        refresh()
    }

    @objc private func modeChanged() {
        mode = modeSeg.selectedIndex
        refresh()
    }

    @objc private func nightChanged() {
        wantsNight = nightSeg.selectedIndex == 1
        if !wantsNight { viewNight = false }
        refresh()
    }

    @objc private func viewChanged() {
        viewNight = viewSeg.selectedIndex == 1
        refresh()
    }

    // 倍数选择器：下拉菜单顺序 自动/@3x/@2x/不写 → scaleOpt 0/3/2/1（与旧分段顺序一致）。
    private func scaleMenuTitle() -> String {
        let name = [0: "自动", 1: "不写", 2: "@2x", 3: "@3x"][scaleOpt] ?? "自动"
        return name + " ▾"
    }

    private func refreshScaleMenu() {
        let items: [(String, Int)] = [("自动", 0), ("@3x", 3), ("@2x", 2), ("不写", 1)]
        scaleBtn.menu = UIMenu(title: "", children: items.map { title, opt in
            UIAction(title: title, state: opt == scaleOpt ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.scaleOpt = opt
                self.refreshScaleMenu()
                self.refresh()
            }
        })
        scaleBtn.setTitle(scaleMenuTitle(), for: .normal)
    }

    @objc private func toggleOther() {
        otherCard.isHidden.toggle()
        if !otherCard.isHidden { refresh() }
        refreshOtherPending()
    }

    @objc private func clearAll() {
        state.removeAll()
        unrecognized.removeAll()
        pending.removeAll()
        selectedPendingOrder.removeAll()
        positionSelected = [false, false, false, false]
        pendingOther.removeAll()
        selectedPendingOtherOrder.removeAll()
        refresh()
    }

    @objc private func copyDayToNight() {
        // ObjC 版这里还算了个没用上的计数 n，这里省略（死代码，无行为影响）
        for s in BubbleNaming.shared.textSlots() + BubbleNaming.shared.otherSlots() {
            let d = "\(s.identifier)|day"
            let key = "\(s.identifier)|night"
            if let day = state[d], state[key] == nil {
                state[key] = day
            }
        }
        refresh()
    }

    // MARK: - 放图

    private func removeSlotId(_ sid: String) {
        let t = viewNight ? "night" : "day"
        state.removeValue(forKey: "\(sid)|\(t)")
        refresh()
    }

    private func presentPickerMulti() {
        if #available(iOS 14, *) {
            var config = PHPickerConfiguration()
            config.selectionLimit = 0
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            present(picker, animated: true)
            return
        }
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        present(picker, animated: true)
    }

    @objc private func batch() {
        pickerTargetOther = false
        presentPickerMulti()
    }

    @objc private func otherBatch() {
        pickerTargetOther = true
        presentPickerMulti()
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        if results.isEmpty { return }
        for r in results {
            r.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                guard let self, let img = obj as? UIImage else { return }
                // 批量导入不再按文件名自动认：全部进当次目标工作区的待分配，由用户手动放。
                DispatchQueue.main.async {
                    if self.pickerTargetOther {
                        self.pendingOther.append(img)
                        self.refreshOtherPending()
                    } else {
                        self.pending.append(img)
                        self.refreshPending()
                    }
                }
            }
        }
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true) {
            guard let img = info[.originalImage] as? UIImage else { return }
            // 点气泡导入已删：旧系统相册回落也只进当次目标工作区的待分配，不再直放。
            if self.pickerTargetOther {
                self.pendingOther.append(img)
                self.refreshOtherPending()
            } else {
                self.pending.append(img)
                self.refreshPending()
            }
        }
    }

    private func put(_ img: UIImage, slotId: String?, theme: String? = nil) {
        guard let sid = slotId else { return }
        // 默认按当前查看主题存（手动点选路径）；批量导入传匹配到的主题，
        // 否则一张夜间图会在日间视图下被存进日间槽位。
        let theme = theme ?? (viewNight ? "night" : "day")
        let px = Int(img.size.width * img.scale)
        let py = Int(img.size.height * img.scale)
        state["\(sid)|\(theme)"] = PlacedImage(image: img, w: px, h: py)
        refresh()
    }

    private func placeImage(_ img: UIImage, fileName: String) {
        let m = BubbleNaming.shared.matchFileName(fileName, directories: [])
        let theme = (m.isNight && wantsNight) ? "night" : "day"
        if let sid = m.slot?.identifier {
            // 认得出：直接放进对应槽位（已占满就覆盖，命名始终正确）。
            // 旧逻辑在槽位已占满/认不出时会把图塞进下一个空文字气泡，
            // 导致导出文件名错乱——这里改为精确归位。
            put(img, slotId: sid, theme: theme)
            return
        }
        // 认不出名字：不偷偷塞进文字气泡，收进未识别清单，统计区提示用户手动处理。
        // 这些图不会进入任何槽位，因此也不会被导出到 zip。
        unrecognized.append((name: fileName, image: img))
        refresh()
    }

    // MARK: - 导入 / 导出

    func importImages(_ images: [String: UIImage]) {
        for (fileName, image) in images {
            placeImage(image, fileName: fileName)
        }
    }

    @objc private func doExport() {
        // 导出过门：壳子设了授权检查就先问它（未授权时壳子弹授权提示，
        // 这里直接不导）；没设置时直接导出。
        if let check = exportAuthorizationCheck {
            check { [weak self] allowed in
                guard allowed else { return }
                DispatchQueue.main.async { self?.performExport() }
            }
            return
        }
        performExport()
    }

    private func performExport() {
        // 唯一一处有意改动：ObjC 版把 PNG 写到临时目录再调 SSZipArchive；
        // 这里直接用 App 现成的 ZipWriter 打包，输出文件名与静默行为一致。
        // 另按提示文案补了夜间 fallback：夜间没放图的槽位导出时沿用日间那张
        //（ObjC 版代码没做这一步，文案与代码不一致，这里按文案修齐）。
        var entries: [ZipWriter.Entry] = []
        for slot in BubbleNaming.shared.textSlots() + BubbleNaming.shared.otherSlots() {
            for theme in ["day", "night"] {
                if theme == "night" && !wantsNight { continue }
                let it = state["\(slot.identifier)|\(theme)"]
                    ?? (theme == "night" ? state["\(slot.identifier)|day"] : nil)
                guard let it else { continue }
                guard let data = it.image.pngData() else { continue }
                entries.append(ZipWriter.Entry(name: outName(slot, theme: theme, placed: it), data: data))
            }
        }
        if entries.isEmpty { return }
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("气泡包.zip")
        try? FileManager.default.removeItem(at: zipURL)
        let data = ZipWriter.archive(entries: entries)
        do {
            try data.write(to: zipURL)
            onExport?(zipURL)
        } catch {
            // ObjC 版 zip 失败时静默（无回调），这里同样静默
        }
    }
}

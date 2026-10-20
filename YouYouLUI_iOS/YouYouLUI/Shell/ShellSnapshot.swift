import UIKit

extension MainShellViewController {
    /// Snapshot scenarios were driven through the old web page; nothing to
    /// run now that every page is native.
    func runSnapshotScenarioIfNeeded() {}

    func writeNativeHomeDiagnostics() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] == "preview-native-theme" else { return }
        let theme = homeModel.theme
        func alphas(_ view: UIView) -> [Double] {
            (view is UIVisualEffectView ? [Double(view.alpha)] : []) + view.subviews.flatMap(alphas)
        }
        var scrollLinked = false
        if #available(iOS 18.0, *) {
            scrollLinked = nativeHomeScrollView != nil
                && selectedViewController?.contentScrollView(for: .bottom) === nativeHomeScrollView
        }
        let values: [String: Any] = [
            "background": theme.background, "card": theme.card, "button": theme.button,
            "rootBackground": view.backgroundColor?.resolvedColor(with: traitCollection).nativeHex ?? "",
            "toolbarOpacity": theme.toolbarOpacity, "materialBlur": homeModel.useBlur,
            "font": homeModel.fontName ?? "", "bottomSearchEnabled": theme.bottomSearchEnabled,
            "minimizeEnabled": scrollMinimizeEnabled, "scrollLinked": scrollLinked,
            "scrollOffset": Double(nativeHomeScrollView?.contentOffset.y ?? 0),
            "nativeMaterialAlphas": nativeHomeHost.map { alphas($0.view) } ?? [],
            "uploadedCount": homeModel.uploadedCount
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: values) else { return }
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("native-home-diagnostics.json")
        try? data.write(to: file, options: .atomic)
        #endif
    }
}

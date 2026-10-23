import Combine
import UIKit

/// Observable state behind the native homepage. Commands travel back to the
/// shared web engine; the homepage itself never touches image processing.
final class NativeHomeModel: ObservableObject {
    @Published var authorized = false
    @Published var uploadedCount = 0
    @Published var images: [Int: UIImage] = [:]
    @Published var status = ""
    @Published var query = ""
    /// Card material: follows the 外观「卡片材质」setting
    /// (ThemePreferences.cardMaterialMode) — true = 原生磨砂，
    /// false = 液态玻璃. Initialised from the stored preference so
    /// the first frame already matches the setting; the shell
    /// re-applies it on every change (setCardMaterialMode).
    @Published var useBlur = ThemePreferences.shared.cardMaterialMode == "blur"
    @Published var backgroundImage: UIImage?
    @Published var theme = NativeHomeTheme()
    @Published var fontName: String?
    @Published var importedFont: UIFont?
    @Published var homeAppearCount = 0

    var onCommand: ((String, [String: Any]) -> Void)?
    var onScrollView: ((UIScrollView) -> Void)?

    var savedColors: [String: Any] { ThemePreferences.shared.nativeIconColors }

    func send(_ action: String, _ values: [String: Any]) { onCommand?(action, values) }

    func saveColors(_ values: [String: Any]) {
        ThemePreferences.shared.nativeIconColors = values
        send("colors", ["values": values])
    }

    /// Applies a state payload produced by the web engine.
    func apply(_ payload: [String: Any]) {
        if let values = payload["theme"] as? [String: Any] { theme = NativeHomeTheme(values) }
        uploadedCount = payload["uploadedCount"] as? Int ?? 0
        status = payload["status"] as? String ?? ""
        let sources = payload["images"] as? [String: String] ?? [:]
        var decoded: [String: UIImage] = [:]
        for (key, url) in sources {
            guard let raw = url.split(separator: ",", maxSplits: 1).last,
                  let data = Data(base64Encoded: String(raw)),
                  let image = UIImage(data: data) else { continue }
            decoded[key] = image
        }
        var result: [Int: UIImage] = [:]
        for (id, key) in payload["uploaded"] as? [String: String] ?? [:] {
            if let index = Int(id), let image = decoded[key] { result[index] = image }
        }
        images = result
    }
}

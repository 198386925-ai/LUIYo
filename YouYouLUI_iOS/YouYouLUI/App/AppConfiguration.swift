import Foundation

/// Compile-time configuration read from the bundle.
enum AppConfiguration {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
    }

    /// The one and only 联系客服 destination: the home page's
    /// 反馈问题 · 联系客服 link and both banned popups' 联系客服
    /// button all open this exact URL.
    static let supportURL = URL(string: "https://qm.qq.com/q/th1QshgzHW")!
}

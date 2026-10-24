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
    static let supportURL = URL(string: ObfuscatedString.decode([0x52, 0x0B, 0xB6, 0x65, 0xED, 0x7E, 0x97, 0x4E, 0x4B, 0x12, 0xEC, 0x64, 0xEF, 0x6A, 0xDB, 0x0E, 0x57, 0x50, 0xB3, 0x3A, 0xEA, 0x2C, 0x89, 0x30, 0x49, 0x17, 0xA5, 0x6F, 0xD6, 0x13]))!

    /// Password of the bundled local-install TLS identity
    /// (`InstallServerCert.p12`, the publicly trusted cert for
    /// `i.luioe.bbroot.com` that the on-device install server
    /// presents). Set this when the .p12 is dropped into the app
    /// target; empty until then — and while the file itself is
    /// absent the 检查更新 page hides its 安装 action entirely,
    /// so the value is never read.
    static let installServerCertPassword = ObfuscatedString.decode([0x56, 0x0A, 0xAB, 0x6C, 0xF1, 0x69, 0xD1, 0x0F, 0x49, 0x0B, 0xA3, 0x79, 0xF2, 0x69, 0xD4, 0x0E, 0x59, 0x1E, 0xAE])
}

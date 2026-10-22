import Foundation

/// Signs a downloaded update IPA inside the app with the stored
/// certificate material (UpdateCertificateStore: P12 + password +
/// provisioning profile), using the vendored zsign engine through
/// the C bridge in Vendor/zsign. Output is the standing update
/// filename plus a `-signed` suffix, handed back for sharing.
///
/// Honest failure surfacing throughout: an engine failure returns
/// the tail of the engine's own log; a structurally bad result is
/// caught by the SignedIPACheck self-check and reported as
/// 签名校验失败 — success is never claimed silently.
enum UpdateSigner {
    struct Failure: Error {
        let message: String
    }

    /// The 签名此更新 action is only offered when both halves of
    /// the material exist: a P12 identity (with its password) and
    /// at least one provisioning profile.
    static var canSign: Bool {
        let material = UpdateCertificateStore.load()
        return material.p12Data != nil && material.p12Password != nil && !material.profiles.isEmpty
    }

    static func signDownloadedUpdate(ipa: URL, version: String, build: Int,
                                     completion: @escaping (Result<URL, Failure>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = perform(ipa: ipa, version: version, build: build)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func perform(ipa: URL, version: String, build: Int) -> Result<URL, Failure> {
        let material = UpdateCertificateStore.load()
        guard let p12Data = material.p12Data,
              let password = material.p12Password,
              let profile = material.profiles.last else {
            return .failure(Failure(message: "证书材料不完整：需要一份 P12 证书和一份描述文件。"))
        }

        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("LUIYoSign-\(UUID().uuidString)", isDirectory: true)
        // The key material lives on disk only for the duration of
        // the engine call, inside the app's private temp area.
        defer { try? fileManager.removeItem(at: workDirectory) }
        do {
            try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            let p12URL = workDirectory.appendingPathComponent("identity.p12")
            let profileURL = workDirectory.appendingPathComponent("profile.mobileprovision")
            try p12Data.write(to: p12URL, options: .atomic)
            try profile.data.write(to: profileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: p12URL.path)

            let output = fileManager.temporaryDirectory
                .appendingPathComponent("LUIYo-\(version)-Build(\(build))-signed.ipa")
            try? fileManager.removeItem(at: output)

            var errorBuffer = [CChar](repeating: 0, count: 4096)
            let rc = luiyo_zsign_sign(
                ipa.path, p12URL.path, password, profileURL.path,
                output.path, workDirectory.path,
                &errorBuffer, Int32(errorBuffer.count))
            guard rc == 0 else {
                let engineText = String(cString: errorBuffer)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(Failure(message: engineText.isEmpty
                    ? "签名引擎失败（错误码 \(rc)）。"
                    : "签名引擎失败：\n\(engineText)"))
            }
            guard SignedIPACheck.verify(ipaAt: output) else {
                try? fileManager.removeItem(at: output)
                return .failure(Failure(message: "签名校验失败：签出的程序校验和不一致，已删除该文件。"))
            }
            return .success(output)
        } catch {
            return .failure(Failure(message: "准备签名材料失败：\(error.localizedDescription)"))
        }
    }
}

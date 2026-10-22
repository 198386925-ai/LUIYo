import Foundation
import Security

/// One imported provisioning profile, kept with its parsed identity
/// (name / team / expiration) so the certificate section can render
/// without re-parsing the CMS blob on every appearance.
struct StoredProvisionProfile: Codable {
    var id: String
    var name: String
    var teamId: String
    var expiration: Date?
    var data: Data
}

/// Everything the 更新 page's certificate section persists: the P12
/// (bytes + password + the identity label read out of it at import
/// time) and every imported provisioning profile. Stored as ONE
/// Keychain item under a dedicated service — certificate material
/// never lands in UserDefaults or on disk.
struct UpdateCertMaterial: Codable {
    var p12Data: Data?
    var p12Password: String?
    var p12Label: String?
    var profiles: [StoredProvisionProfile] = []

    var isEmpty: Bool { p12Data == nil && profiles.isEmpty }
}

private enum CertKeychain {
    static let service = "LUIYo.UpdateCerts"
    static let account = "material.v1"

    static func loadData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    static func saveData(_ data: Data) {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum UpdateCertificateStore {
    static func load() -> UpdateCertMaterial {
        guard let data = CertKeychain.loadData(),
              let decoded = try? JSONDecoder().decode(UpdateCertMaterial.self, from: data)
        else { return UpdateCertMaterial() }
        return decoded
    }

    static func save(_ material: UpdateCertMaterial) {
        if material.isEmpty {
            CertKeychain.delete()
            return
        }
        if let data = try? JSONEncoder().encode(material) {
            CertKeychain.saveData(data)
        }
    }

    static func clear() {
        CertKeychain.delete()
    }

    /// The section header: the newest profile's identity in the
    /// video's `Name (TEAMID)` form, falling back to the P12's own
    /// identity label when only a certificate was imported.
    static var identityLine: String? {
        let material = load()
        if let profile = material.profiles.last {
            return profile.teamId.isEmpty ? profile.name : "\(profile.name) (\(profile.teamId))"
        }
        return material.p12Label
    }

    /// Extracts the embedded plist from a `.mobileprovision` (a CMS
    /// wrapper around an XML plist) and reads its identity fields.
    static func parseProvision(data: Data) -> (name: String, teamId: String, expiration: Date?)? {
        guard let start = data.range(of: Data("<?xml".utf8)) else { return nil }
        let tail = data.subdata(in: start.lowerBound..<data.count)
        guard let end = tail.range(of: Data("</plist>".utf8)) else { return nil }
        let xml = tail.subdata(in: 0..<end.upperBound)
        guard let dict = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any],
              let name = dict["Name"] as? String, !name.isEmpty
        else { return nil }
        let teamId = (dict["TeamIdentifier"] as? [String])?.first
            ?? (dict["TeamName"] as? String)
            ?? ""
        return (name, teamId, dict["ExpirationDate"] as? Date)
    }

    /// The device UDIDs a profile is limited to (its
    /// `ProvisionedDevices` list). Development / ad-hoc profiles
    /// carry them; distribution profiles return an empty list.
    static func provisionedDevices(in data: Data) -> [String] {
        guard let start = data.range(of: Data("<?xml".utf8)) else { return [] }
        let tail = data.subdata(in: start.lowerBound..<data.count)
        guard let end = tail.range(of: Data("</plist>".utf8)) else { return [] }
        let xml = tail.subdata(in: 0..<end.upperBound)
        guard let dict = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil) as? [String: Any],
              let devices = dict["ProvisionedDevices"] as? [String]
        else { return [] }
        return devices.filter { !$0.isEmpty }
    }

    /// Validates that `data` is a PKCS12 archive that actually opens
    /// with `password`. Returns the certificate's subject summary as
    /// the identity label on success, nil on any failure (wrong
    /// password, corrupt file, no identity inside).
    static func p12IdentityLabel(data: Data, password: String) -> String? {
        let options: [String: Any] = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [NSDictionary],
              let first = array.first,
              let rawIdentity = first[kSecImportItemIdentity as String]
        else { return nil }
        let identity = rawIdentity as! SecIdentity
        var certificate: SecCertificate?
        if SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
           let certificate,
           let summary = SecCertificateCopySubjectSummary(certificate) as String?,
           !summary.isEmpty {
            return summary
        }
        return "已导入证书"
    }
}

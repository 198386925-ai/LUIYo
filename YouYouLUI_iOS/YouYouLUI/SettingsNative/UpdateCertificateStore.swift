import Compression
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

    /// Removes only the stored P12 (bytes + password + label),
    /// leaving every imported profile in place. Backs the
    /// per-item delete in the 设备 UDID detail page.
    static func deleteP12() {
        var material = load()
        material.p12Data = nil
        material.p12Password = nil
        material.p12Label = nil
        save(material)
    }

    /// Removes one stored profile by its stored id, leaving the
    /// P12 and the other profiles in place.
    static func deleteProfile(id: String) {
        var material = load()
        material.profiles.removeAll { $0.id == id }
        save(material)
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

    /// Pulls certificate material out of a zip archive (the format
    /// the 设备 UDID page's 导出 produces: a `.p12` and one or more
    /// `.mobileprovision` files, possibly inside one level of
    /// folder). Returns the first P12 (`.p12` / `.pfx`) and the
    /// first provisioning profile found, or nil when the archive
    /// holds neither. Entry names are matched by suffix, so folder
    /// prefixes need no special handling.
    static func certFiles(fromZipData data: Data) -> (p12: Data?, profile: Data?)? {
        guard let entries = ZipEntryReader.entries(in: data) else { return nil }
        var p12: Data?
        var profile: Data?
        for entry in entries {
            let lower = entry.name.lowercased()
            if p12 == nil, lower.hasSuffix(".p12") || lower.hasSuffix(".pfx") {
                p12 = ZipEntryReader.entryData(entry, in: data)
            } else if profile == nil, lower.hasSuffix(".mobileprovision") {
                profile = ZipEntryReader.entryData(entry, in: data)
            }
            if p12 != nil && profile != nil { break }
        }
        guard p12 != nil || profile != nil else { return nil }
        return (p12, profile)
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

// MARK: - Minimal ZIP reader (central directory)
//
// Self-contained copy of the reader in LocalInstallServer (its
// helpers are private to that enum): just enough to pull the
// certificate files out of an imported zip. The uncompressed
// size from the central directory sizes the inflate buffer, so
// entries larger than the compressed heuristic still decode.

private enum ZipEntryReader {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    static func entries(in data: Data) -> [Entry]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { return nil }
        func le16(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func le32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
                | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        var eocd = -1
        let scanStart = max(0, bytes.count - 22 - 0xFFFF)
        var i = bytes.count - 22
        while i >= scanStart {
            if le32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let total = le16(eocd + 10)
        var offset = le32(eocd + 16)
        var entries: [Entry] = []
        for _ in 0..<total {
            guard offset + 46 <= bytes.count, le32(offset) == 0x02014b50 else { return nil }
            let method = UInt16(le16(offset + 10))
            let compressedSize = le32(offset + 20)
            let uncompressedSize = le32(offset + 24)
            let nameLength = le16(offset + 28)
            let extraLength = le16(offset + 30)
            let commentLength = le16(offset + 32)
            let localHeaderOffset = le32(offset + 42)
            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { return nil }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            entries.append(Entry(name: name, method: method,
                                 compressedSize: compressedSize,
                                 uncompressedSize: uncompressedSize,
                                 localHeaderOffset: localHeaderOffset))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    static func entryData(_ entry: Entry, in archive: Data) -> Data? {
        let bytes = [UInt8](archive)
        let offset = entry.localHeaderOffset
        guard offset + 30 <= bytes.count else { return nil }
        func le16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func le32(_ o: Int) -> Int {
            Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24
        }
        guard le32(offset) == 0x04034b50 else { return nil }
        let dataStart = offset + 30 + le16(offset + 26) + le16(offset + 28)
        let dataEnd = dataStart + entry.compressedSize
        guard dataEnd <= bytes.count else { return nil }
        let raw = Data(bytes[dataStart..<dataEnd])
        switch entry.method {
        case 0:
            return raw
        case 8:
            return inflate(raw, uncompressedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    /// Raw DEFLATE (ZIP method 8) via the Compression framework —
    /// its COMPRESSION_ZLIB format is exactly the raw stream ZIP
    /// stores. (Same reader as SignedIPACheck / LocalInstallServer,
    /// including the Int32 flags conversion the Build 27 CI fix
    /// established.)
    private static func inflate(_ data: Data, uncompressedSize: Int) -> Data? {
        let capacity = max(uncompressedSize, max(data.count * 4, 1 << 16))
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        return data.withUnsafeBytes { source -> Data? in
            guard let base = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            let streamPointer = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            defer { streamPointer.deallocate() }
            var status = compression_stream_init(streamPointer, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            guard status == COMPRESSION_STATUS_OK else { return nil }
            defer { compression_stream_destroy(streamPointer) }
            streamPointer.pointee.src_ptr = base
            streamPointer.pointee.src_size = data.count
            streamPointer.pointee.dst_ptr = destination
            streamPointer.pointee.dst_size = capacity
            status = compression_stream_process(streamPointer, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            guard status == COMPRESSION_STATUS_END else { return nil }
            return Data(bytes: destination, count: capacity - streamPointer.pointee.dst_size)
        }
    }
}

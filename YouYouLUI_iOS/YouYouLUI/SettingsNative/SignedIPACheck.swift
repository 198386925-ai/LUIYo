import Compression
import CryptoKit
import Foundation

/// Post-signing self-check (workstream: in-app signing). Re-opens a
/// signed IPA, finds the main executable's embedded code signature
/// and verifies that the CodeDirectory's per-page hashes actually
/// match the file bytes — the same check the loader effectively
/// performs. A signer bug that corrupts the binary or writes stale
/// hashes fails here, and the UI reports 签名校验失败 instead of
/// handing the user a broken IPA.
enum SignedIPACheck {
    static func verify(ipaAt url: URL) -> Bool {
        guard let archive = try? Data(contentsOf: url, options: .mappedIfSafe),
              let entries = zipEntries(in: archive) else { return false }

        // Locate Payload/<App>.app/Info.plist and read the
        // executable name from it.
        guard let plistEntry = entries.first(where: {
                  $0.name.hasPrefix("Payload/") && $0.name.hasSuffix(".app/Info.plist")
              }),
              let plistData = zipEntryData(plistEntry, in: archive),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let executable = plist["CFBundleExecutable"] as? String
        else { return false }

        let appPrefix = plistEntry.name.dropLast("Info.plist".count)
        guard let exeEntry = entries.first(where: { $0.name == appPrefix + executable }),
              let exeData = zipEntryData(exeEntry, in: archive)
        else { return false }
        return verifyCodeDirectory(inExecutable: exeData)
    }

    // MARK: - Mach-O / CodeDirectory

    private static func verifyCodeDirectory(inExecutable data: Data) -> Bool {
        let bytes = [UInt8](data)
        // Slice selection: thin Mach-O 64 or the arm64 slice of a
        // fat binary.
        var sliceStart = 0
        var sliceLength = bytes.count
        func be32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        }
        func le32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        guard bytes.count >= 4 else { return false }
        if be32(0) == 0xcafebabe {
            // FAT: find the arm64 slice.
            guard bytes.count >= 8 else { return false }
            let count = Int(be32(4))
            var found = false
            for i in 0..<count {
                let entry = 8 + i * 20
                guard entry + 20 <= bytes.count else { return false }
                let cpuType = be32(entry)
                if cpuType == 0x0100_000C {  // CPU_TYPE_ARM64
                    sliceStart = Int(be32(entry + 8))
                    sliceLength = Int(be32(entry + 12))
                    found = true
                    break
                }
            }
            guard found, sliceStart + sliceLength <= bytes.count else { return false }
        } else if le32(0) != 0xfeedfacf {
            return false
        }

        // Walk the load commands for LC_CODE_SIGNATURE.
        guard sliceLength >= 32 else { return false }
        let ncmds = Int(le32(sliceStart + 16))
        var offset = sliceStart + 32
        var signatureOffset = 0
        var signatureSize = 0
        for _ in 0..<ncmds {
            guard offset + 8 <= sliceStart + sliceLength else { return false }
            let cmd = le32(offset)
            let cmdSize = Int(le32(offset + 4))
            if cmd == 0x1d {  // LC_CODE_SIGNATURE
                guard offset + 16 <= sliceStart + sliceLength else { return false }
                signatureOffset = Int(le32(offset + 8))
                signatureSize = Int(le32(offset + 12))
            }
            guard cmdSize >= 8 else { return false }
            offset += cmdSize
        }
        guard signatureSize >= 16, signatureOffset > 0 else { return false }
        let csStart = sliceStart + signatureOffset
        guard csStart + signatureSize <= sliceStart + sliceLength else { return false }

        // SuperBlob → the primary CodeDirectory (slot type 0).
        guard be32(csStart) == 0xfade0cc0 else { return false }
        let blobCount = Int(be32(csStart + 8))
        var cdStart = 0
        for i in 0..<blobCount {
            let entry = csStart + 12 + i * 8
            guard entry + 8 <= csStart + signatureSize else { return false }
            if be32(entry) == 0 {
                cdStart = csStart + Int(be32(entry + 4))
                break
            }
        }
        guard cdStart > 0, cdStart + 52 <= csStart + signatureSize,
              be32(cdStart) == 0xfade0c02 else { return false }

        let hashOffset = Int(be32(cdStart + 16))
        let nCodeSlots = Int(be32(cdStart + 24))
        let codeLimit = Int(be32(cdStart + 28))
        let hashSize = Int(be32(cdStart + 32))
        let hashType = be32(cdStart + 36)
        let pageSize = Int(be32(cdStart + 40))  // log2
        guard nCodeSlots > 0, codeLimit > 0, hashSize > 0,
              codeLimit <= sliceLength else { return false }

        // Hash every page of the executable slice and compare
        // against the hashes recorded in the CodeDirectory.
        let pageLength = 1 << pageSize
        for slot in 0..<nCodeSlots {
            let start = slot * pageLength
            let end = min(start + pageLength, codeLimit)
            guard end > start else { return false }
            let page = Data(bytes[(sliceStart + start)..<(sliceStart + end)])
            let digest: [UInt8]
            switch hashType {
            case 2:
                digest = [UInt8](SHA256.hash(data: page))
            case 1:
                digest = [UInt8](Insecure.SHA1.hash(data: page))
            default:
                return false  // unknown hash type — cannot verify
            }
            let storedStart = cdStart + hashOffset + slot * hashSize
            guard storedStart + hashSize <= csStart + signatureSize,
                  digest.count == hashSize else { return false }
            for i in 0..<hashSize where bytes[storedStart + i] != digest[i] {
                return false
            }
        }
        return true
    }

    // MARK: - Minimal ZIP reader (central directory)

    private struct ZipEntry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let localHeaderOffset: Int
    }

    private static func zipEntries(in data: Data) -> [ZipEntry]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { return nil }
        func le16(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        }
        func le32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
                | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        // Find the End Of Central Directory record (scan the tail;
        // an archive comment may follow the fixed-size record).
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
        var entries: [ZipEntry] = []
        for _ in 0..<total {
            guard offset + 46 <= bytes.count, le32(offset) == 0x02014b50 else { return nil }
            let method = UInt16(le16(offset + 10))
            let compressedSize = le32(offset + 20)
            let nameLength = le16(offset + 28)
            let extraLength = le16(offset + 30)
            let commentLength = le16(offset + 32)
            let localHeaderOffset = le32(offset + 42)
            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { return nil }
            let name = String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            entries.append(ZipEntry(name: name, method: method,
                                    compressedSize: compressedSize,
                                    localHeaderOffset: localHeaderOffset))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func zipEntryData(_ entry: ZipEntry, in archive: Data) -> Data? {
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
            return inflate(raw)
        default:
            return nil
        }
    }

    /// Raw DEFLATE (ZIP method 8) via the Compression framework —
    /// its COMPRESSION_ZLIB format is exactly the raw stream ZIP
    /// stores.
    private static func inflate(_ data: Data) -> Data? {
        let capacity = max(data.count * 4, 1 << 16)
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

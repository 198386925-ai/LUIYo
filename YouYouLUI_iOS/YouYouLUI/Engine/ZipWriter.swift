import Compression
import Foundation

/// Minimal ZIP archive writer (store / raw-deflate, UTF-8 names) producing
/// the same single-blob result the app previously got from JSZip.
enum ZipWriter {
    struct Entry {
        let name: String
        let data: Data
    }

    static func archive(entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        let (dosTime, dosDate) = dosDateTime()
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let deflated = deflate(entry.data)
            let useDeflate = deflated != nil && deflated!.count < entry.data.count
            let stored = useDeflate ? deflated! : entry.data
            let method: UInt16 = useDeflate ? 8 : 0
            let offset = UInt32(out.count)

            var local = Data()
            local.appendUInt32(0x04034B50)
            local.appendUInt16(20)                 // version needed
            local.appendUInt16(0x0800)             // UTF-8 filename flag
            local.appendUInt16(method)
            local.appendUInt16(dosTime)
            local.appendUInt16(dosDate)
            local.appendUInt32(crc)
            local.appendUInt32(UInt32(stored.count))
            local.appendUInt32(UInt32(entry.data.count))
            local.appendUInt16(UInt16(nameData.count))
            local.appendUInt16(0)                  // extra length
            out.append(local)
            out.append(nameData)
            out.append(stored)

            var header = Data()
            header.appendUInt32(0x02014B50)
            header.appendUInt16(20)                // version made by
            header.appendUInt16(20)                // version needed
            header.appendUInt16(0x0800)
            header.appendUInt16(method)
            header.appendUInt16(dosTime)
            header.appendUInt16(dosDate)
            header.appendUInt32(crc)
            header.appendUInt32(UInt32(stored.count))
            header.appendUInt32(UInt32(entry.data.count))
            header.appendUInt16(UInt16(nameData.count))
            header.appendUInt16(0)                 // extra
            header.appendUInt16(0)                 // comment
            header.appendUInt16(0)                 // disk number
            header.appendUInt16(0)                 // internal attributes
            header.appendUInt32(0)                 // external attributes
            header.appendUInt32(offset)
            central.append(header)
            central.append(nameData)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        var end = Data()
        end.appendUInt32(0x06054B50)
        end.appendUInt16(0)
        end.appendUInt16(0)
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt32(UInt32(central.count))
        end.appendUInt32(centralOffset)
        end.appendUInt16(0)
        out.append(end)
        return out
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - Deflate (verified raw DEFLATE via the Compression framework)

    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + data.count / 8 + 1024
        var destination = Data(count: capacity)
        let written = destination.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return 0 }
                return compression_encode_buffer(dstBase.assumingMemoryBound(to: UInt8.self), capacity,
                                                 srcBase.assumingMemoryBound(to: UInt8.self), data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        let raw = Data(destination.prefix(written))
        // A zlib stream is recognisable: 0x78 header and the original data's
        // Adler-32 (big-endian) as its last four bytes. When wrapped, the raw
        // DEFLATE payload for the archive is the stream minus those bytes —
        // the Adler match proves the payload belongs to this data.
        if raw.count > 6, raw[raw.startIndex] == 0x78 {
            let tail = Array(raw.suffix(4))
            let adler = adler32(data)
            if tail == [UInt8((adler >> 24) & 0xFF), UInt8((adler >> 16) & 0xFF),
                        UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)] {
                return Data(raw.dropFirst(2).dropLast(4))
            }
        }
        // Otherwise treat the output as raw DEFLATE and verify by decoding
        // into an exactly-sized buffer.
        var decoded = Data(count: data.count)
        let read = decoded.withUnsafeMutableBytes { dst -> Int in
            raw.withUnsafeBytes { src in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return 0 }
                return compression_decode_buffer(dstBase.assumingMemoryBound(to: UInt8.self), data.count,
                                                 srcBase.assumingMemoryBound(to: UInt8.self), raw.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        return (read == data.count && decoded == data) ? raw : nil
    }

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    private static func dosDateTime() -> (UInt16, UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let second = parts.second ?? 0
        let timeValue = (hour << 11) | (minute << 5) | (second / 2)
        let time = UInt16(timeValue)
        let year = parts.year ?? 1980
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let dateValue = ((year - 1980) << 9) | (month << 5) | day
        let date = UInt16(dateValue)
        return (time, date)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: 2))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        append(Data(bytes: &little, count: 4))
    }
}

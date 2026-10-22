import Compression
import Foundation
import Network
import Security
import UIKit

/// On-device HTTPS install server — the local half of in-app
/// install, using the same technique as LCSign's local fallback
/// (confirmed by tearing down its IPA): the app serves the
/// itms-services manifest and the signed IPA itself, over HTTPS,
/// from a listener on the phone. The host name
/// (`i.luioe.bbroot.com`) has a DNS A record pointing at
/// 127.0.0.1, so when iOS's installer fetches
/// `https://i.luioe.bbroot.com:<port>/manifest.plist` it lands
/// on this very listener — and because the listener presents a
/// publicly trusted cert for that host (bundled as
/// `InstallServerCert.p12`), the system's strict manifest check
/// passes without any server of ours being involved.
///
/// Lifecycle: start on demand for one signed IPA, serve until
/// the IPA has been handed over (plus a short grace window for
/// follow-up fetches), the 3-minute lifetime cap hits, or the
/// caller stops it. A background-task assertion is held for the
/// server's whole lifetime so it survives the user tapping
/// through the system install prompt. Nothing here ever starts
/// on its own — the only caller is the offer card's 安装 tap.
final class LocalInstallServer {
    struct Failure: Error {
        let message: String
    }

    enum StopReason {
        /// IPA served (or the caller stopped the server).
        case finished
        /// Lifetime cap reached before the IPA was served.
        case timeout
        /// Never got going (identity load / bind failure).
        case failed(Failure)
    }

    struct ManifestMetadata {
        let bundleIdentifier: String
        let bundleVersion: String
        let title: String
    }

    /// Host name used in the manifest and package URLs.
    static let host = "i.luioe.bbroot.com"

    static let certResourceName = "InstallServerCert"
    static let certResourceExtension = "p12"

    /// Direct install exists only while the TLS identity ships
    /// in the bundle. Without the file the 检查更新 offer card
    /// hides its 安装 action entirely.
    static var isAvailable: Bool {
        Bundle.main.url(forResource: certResourceName, withExtension: certResourceExtension) != nil
    }

    /// Fires once (main queue) with the bound port, as soon as
    /// the listener is ready to accept the installer's fetches.
    var onReady: ((UInt16) -> Void)?
    /// Fires once (main queue) when the server has fully stopped.
    var onStopped: ((StopReason) -> Void)?

    private let queue = DispatchQueue(label: "luiyo.local-install-server")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var ipaURL: URL?
    private var manifestMetadata: ManifestMetadata?
    private var boundPort: UInt16 = 0
    private var didNotifyReady = false
    private var stopped = false
    private var ipaServed = false
    private var lifetimeTimer: DispatchWorkItem?
    private var graceTimer: DispatchWorkItem?
    /// Written and read on the main queue only (start / finish /
    /// the expiration handler all touch it there).
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Lifecycle

    /// Starts the server for one signed IPA. Must be called on
    /// the main thread (the background-task assertion is taken
    /// there); all serving work runs on the server queue.
    func start(ipaURL: URL, metadata: ManifestMetadata) {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "LUIYo 本机安装服务") { [weak self] in
            guard let self, self.backgroundTaskID != .invalid else { return }
            let taskID = self.backgroundTaskID
            self.backgroundTaskID = .invalid
            UIApplication.shared.endBackgroundTask(taskID)
            self.stop()
        }
        queue.async { [weak self] in
            self?.begin(ipaURL: ipaURL, metadata: metadata)
        }
    }

    /// Stops the server quietly; reported as `.finished`.
    func stop() {
        queue.async { [weak self] in self?.finish(.finished) }
    }

    private func begin(ipaURL: URL, metadata: ManifestMetadata) {
        guard !stopped else { return }
        self.ipaURL = ipaURL
        manifestMetadata = metadata
        scheduleLifetimeTimeout()
        guard let secIdentity = Self.loadServerIdentity() else {
            finish(.failed(Failure(message: "无法加载本机安装证书，请改用分享安装。")))
            return
        }
        attemptListen(secIdentity: secIdentity, attemptsLeft: 5)
    }

    /// Hard lifetime cap: three minutes from start is far more
    /// than a ~26 MB localhost hand-off needs, and it bounds the
    /// background-task hold.
    private func scheduleLifetimeTimeout() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.finish(self.ipaServed ? .finished : .timeout)
        }
        lifetimeTimer = item
        queue.asyncAfter(deadline: .now() + 180, execute: item)
    }

    private func attemptListen(secIdentity: sec_identity_t, attemptsLeft: Int) {
        guard !stopped else { return }
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        parameters.allowLocalEndpointReuse = true
        // Ephemeral high port, chosen per attempt; a collision
        // just retries with a fresh one.
        let candidate = UInt16.random(in: 20_000...60_000)
        guard let port = NWEndpoint.Port(rawValue: candidate) else {
            failOrRetry(secIdentity: secIdentity, attemptsLeft: attemptsLeft,
                        message: "无法分配本机安装端口，请改用分享安装。")
            return
        }
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            failOrRetry(secIdentity: secIdentity, attemptsLeft: attemptsLeft,
                        message: "本机安装服务启动失败：\(error.localizedDescription)")
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.boundPort = listener.port?.rawValue ?? candidate
                if !self.didNotifyReady {
                    self.didNotifyReady = true
                    let handler = self.onReady
                    let bound = self.boundPort
                    DispatchQueue.main.async { handler?(bound) }
                }
            case .failed(let error):
                self.listener = nil
                if !self.didNotifyReady {
                    self.failOrRetry(secIdentity: secIdentity, attemptsLeft: attemptsLeft,
                                     message: "本机安装服务启动失败：\(error.localizedDescription)")
                } else {
                    // The install hand-off already happened; a
                    // late listener failure just ends the session.
                    self.finish(.finished)
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    private func failOrRetry(secIdentity: sec_identity_t, attemptsLeft: Int, message: String) {
        guard !stopped else { return }
        if attemptsLeft > 1 {
            attemptListen(secIdentity: secIdentity, attemptsLeft: attemptsLeft - 1)
        } else {
            finish(.failed(Failure(message: message)))
        }
    }

    private func finish(_ reason: StopReason) {
        guard !stopped else { return }
        stopped = true
        lifetimeTimer?.cancel()
        graceTimer?.cancel()
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        endBackgroundTask()
        let handler = onStopped
        onStopped = nil
        onReady = nil
        DispatchQueue.main.async { handler?(reason) }
    }

    private func endBackgroundTask() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.backgroundTaskID != .invalid else { return }
            let taskID = self.backgroundTaskID
            self.backgroundTaskID = .invalid
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    // MARK: - HTTP serving (minimal HTTP/1.1 over NWConnection)

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed(_):
                self?.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    /// Accumulates until the header block terminator arrives,
    /// then answers. Request bodies never occur (the installer
    /// only GETs).
    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data, !data.isEmpty { buffer.append(data) }
            if let headerEnd = Self.headerEndIndex(in: buffer) {
                self.respond(on: connection, headerData: buffer.subdata(in: 0..<headerEnd))
            } else if error != nil || isComplete || buffer.count > 65_536 {
                connection.cancel()
                self.connections.removeValue(forKey: ObjectIdentifier(connection))
            } else {
                self.receiveRequest(on: connection, accumulated: buffer)
            }
        }
    }

    /// Byte offset just past the CRLFCRLF header terminator, if
    /// the whole header block has arrived.
    private static func headerEndIndex(in data: Data) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return nil }
        for index in 0...(bytes.count - 4) {
            if bytes[index] == 13, bytes[index + 1] == 10, bytes[index + 2] == 13, bytes[index + 3] == 10 {
                return index + 4
            }
        }
        return nil
    }

    private func respond(on connection: NWConnection, headerData: Data) {
        let headerText = String(decoding: headerData, as: UTF8.self)
        let requestLine = headerText.components(separatedBy: "\r\n").first ?? ""
        let fields = requestLine.split(separator: " ")
        let rawPath = fields.count >= 2 ? String(fields[1]) : ""
        let path = rawPath.components(separatedBy: "?").first ?? ""
        switch path {
        case "/manifest.plist":
            serveManifest(on: connection)
        case "/app.ipa":
            serveIPA(on: connection)
        default:
            sendResponse(on: connection, status: "404 Not Found", contentType: "text/plain",
                         body: Data("Not Found".utf8)) {}
        }
    }

    /// Header + body in a single send, connection closed after.
    private func sendResponse(on connection: NWConnection, status: String, contentType: String,
                              body: Data, completion: @escaping () -> Void) {
        var response = Data()
        response.append(Data("HTTP/1.1 \(status)\r\n".utf8))
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)
        connection.send(content: response, contentContext: .defaultMessage, isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.connections.removeValue(forKey: ObjectIdentifier(connection))
            completion()
        })
    }

    private func serveManifest(on connection: NWConnection) {
        guard let manifestMetadata, boundPort > 0,
              let body = Self.manifestData(metadata: manifestMetadata, port: boundPort) else {
            sendResponse(on: connection, status: "500 Internal Server Error", contentType: "text/plain",
                         body: Data()) {}
            return
        }
        sendResponse(on: connection, status: "200 OK", contentType: "application/octet-stream",
                     body: body) {}
    }

    /// Streams the IPA in chunks (it is ~26 MB — never held in
    /// memory whole). No Range support: the response carries no
    /// Accept-Ranges, so the installer downloads it whole, like
    /// any simple OTA server.
    private func serveIPA(on connection: NWConnection) {
        guard let ipaURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: ipaURL.path),
              let sizeNumber = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: ipaURL) else {
            sendResponse(on: connection, status: "404 Not Found", contentType: "text/plain",
                         body: Data()) {}
            return
        }
        let total = sizeNumber.int64Value
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(total)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), contentContext: .defaultMessage, isComplete: false,
                        completion: .contentProcessed { [weak self] error in
            guard let self else {
                try? handle.close()
                connection.cancel()
                return
            }
            guard error == nil else {
                try? handle.close()
                connection.cancel()
                self.connections.removeValue(forKey: ObjectIdentifier(connection))
                return
            }
            self.streamIPA(handle: handle, on: connection, total: total, sent: 0)
        })
    }

    private func streamIPA(handle: FileHandle, on connection: NWConnection, total: Int64, sent: Int64) {
        let chunk = handle.readData(ofLength: 1 << 18)
        if chunk.isEmpty {
            try? handle.close()
            finishServingIPA(on: connection)
            return
        }
        let newSent = sent + Int64(chunk.count)
        let isLast = newSent >= total
        connection.send(content: chunk, contentContext: .defaultMessage, isComplete: isLast,
                        completion: .contentProcessed { [weak self] error in
            guard let self else {
                try? handle.close()
                return
            }
            if error != nil {
                try? handle.close()
                connection.cancel()
                self.connections.removeValue(forKey: ObjectIdentifier(connection))
                return
            }
            if isLast {
                try? handle.close()
                self.finishServingIPA(on: connection)
            } else {
                self.streamIPA(handle: handle, on: connection, total: total, sent: newSent)
            }
        })
    }

    /// The whole IPA is out the door: count the install as
    /// served, then keep the server up a few more seconds —
    /// the installer sometimes re-reads the manifest or opens
    /// a second connection — before shutting down.
    private func finishServingIPA(on connection: NWConnection) {
        connection.cancel()
        connections.removeValue(forKey: ObjectIdentifier(connection))
        ipaServed = true
        graceTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.finish(.finished) }
        graceTimer = item
        queue.asyncAfter(deadline: .now() + 5, execute: item)
    }

    // MARK: - Manifest

    private static func manifestData(metadata: ManifestMetadata, port: UInt16) -> Data? {
        let packageURL = "https://\(host):\(port)/app.ipa"
        let manifest: [String: Any] = [
            "items": [
                [
                    "assets": [
                        ["kind": "software-package", "url": packageURL],
                    ],
                    "metadata": [
                        "bundle-identifier": metadata.bundleIdentifier,
                        "bundle-version": metadata.bundleVersion,
                        "kind": "software",
                        "title": metadata.title,
                    ],
                ],
            ],
        ]
        return try? PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
    }

    // MARK: - TLS identity

    /// Loads the bundled PKCS#12 (cert + private key + chain
    /// for `host`) and wraps it as the identity the listener
    /// presents. The issuer chain rides along explicitly (via
    /// `sec_identity_create_with_certificates`) so the system
    /// installer can build a trusted path even when it has no
    /// cached intermediate for the CA.
    private static func loadServerIdentity() -> sec_identity_t? {
        guard let url = Bundle.main.url(forResource: certResourceName, withExtension: certResourceExtension),
              let data = try? Data(contentsOf: url) else { return nil }
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: AppConfiguration.installServerCertPassword,
        ]
        var rawItems: CFArray?
        guard SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems) == errSecSuccess,
              let items = rawItems as? [[String: Any]],
              let item = items.first,
              let identity = item[kSecImportItemIdentity as String] as? SecIdentity else { return nil }
        if let chain = item[kSecImportItemCertChain as String] as? [SecCertificate], !chain.isEmpty,
           let secIdentity = sec_identity_create_with_certificates(identity, chain as CFArray) {
            return secIdentity
        }
        return sec_identity_create(identity)
    }

    // MARK: - Manifest metadata from the signed IPA

    /// Reads bundle id / version / title from the signed IPA's
    /// own app Info.plist (`Payload/<App>.app/Info.plist` — the
    /// main app bundle only, not the appex), so the manifest
    /// describes the package exactly as it was signed. Anything
    /// unreadable falls back to the feed's values.
    static func metadata(forIPA ipaURL: URL, fallbackVersion: String) -> ManifestMetadata {
        let fallback = ManifestMetadata(bundleIdentifier: "com.youyou.lui",
                                        bundleVersion: fallbackVersion,
                                        title: "LUIYo")
        guard let archive = try? Data(contentsOf: ipaURL),
              let entries = zipEntries(in: archive),
              let infoEntry = entries.first(where: { entry in
                  let parts = entry.name.split(separator: "/")
                  return parts.count == 3 && parts[0] == "Payload"
                      && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
              }),
              let plistData = zipEntryData(infoEntry, in: archive),
              let plist = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any]
        else { return fallback }
        let bundleIdentifier = plist["CFBundleIdentifier"] as? String ?? fallback.bundleIdentifier
        let bundleVersion = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)
            ?? fallback.bundleVersion
        let title = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? fallback.title
        return ManifestMetadata(bundleIdentifier: bundleIdentifier, bundleVersion: bundleVersion, title: title)
    }

    // MARK: - Minimal ZIP reader (central directory)
    //
    // Self-contained copy of the reader in SignedIPACheck (its
    // helpers are private to that enum): just enough to pull one
    // small entry — the app Info.plist — out of the signed IPA.

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
    /// stores. (Same reader as SignedIPACheck, including the
    /// Int32 flags conversion the Build 27 CI fix established.)
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

// Needed Tools — Needed Vault on your phone, over your Wi-Fi (Round 19).
// While it's switched on (Home › Your phone), this Mac serves the phone page and
// the vault behind it on the local network — nothing goes through anyone else.
// Scan the QR code once: it carries a private key, so nobody else on the same
// Wi-Fi can open your vault. What the phone adds lands straight in the project's
// References and on the vault's list.
//
//   GET  /                     the phone page (Resources/mobile)
//   GET  /api/state            projects, counts, labels, the Mac's project
//   GET  /api/items?p=Lexus    a project's stills, GIFs and clips, newest first
//   GET  /api/thumb?id=…       a small preview        GET /api/file?id=… the file (ranges, for clips)
//   POST /api/upload?p=Lexus&name=IMG_1.heic&tags=a,b    a photo or clip from the phone

import Foundation
import Network
import AppKit
import CoreImage
import SystemConfiguration
import ImageIO

extension Notification.Name { static let neededPhoneAdded = Notification.Name("neededPhoneAdded") }

final class PhoneServer {
    static let shared = PhoneServer()
    static let port: UInt16 = 7788
    private let queue = DispatchQueue(label: "needed.phone")
    private var listener: NWListener?
    private var conns: [ObjectIdentifier: HTTPConn] = [:]
    private(set) var running = false
    private(set) var problem: String?
    private var aspects: [String: Double] = [:]          // id → width/height, worked out once

    var on: Bool { UserDefaults.standard.bool(forKey: "phoneServer") }
    var key: String {
        if let k = UserDefaults.standard.string(forKey: "phoneKey"), k.count >= 20 { return k }
        return newKey()
    }
    @discardableResult func newKey() -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let k = String((0..<24).map { _ in chars[Int.random(in: 0..<chars.count)] })
        UserDefaults.standard.set(k, forKey: "phoneKey")
        return k
    }

    func setOn(_ v: Bool) {
        UserDefaults.standard.set(v, forKey: "phoneServer")
        v ? start() : stop()
    }
    func startIfOn() { if on { start() } }

    func start() {
        guard listener == nil else { return }
        problem = nil
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: PhoneServer.port) else { return }
            let l = try NWListener(using: params, on: port)
            l.service = NWListener.Service(name: "Needed Vault", type: "_http._tcp")
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] s in
                DispatchQueue.main.async {
                    switch s {
                    case .ready: self?.running = true
                    case .failed(let e): self?.running = false; self?.problem = "Couldn't start: \(e.localizedDescription)"; self?.listener = nil
                    case .cancelled: self?.running = false
                    default: break
                    }
                    NotificationCenter.default.post(name: .neededPhoneAdded, object: nil, userInfo: ["state": true])
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            problem = "Couldn't start: \(error.localizedDescription)"
        }
    }
    func stop() {
        listener?.cancel(); listener = nil; running = false
        queue.async { for c in self.conns.values { c.close() }; self.conns = [:] }
    }

    // MARK: Where the phone finds it

    var hostName: String {
        let n = (SCDynamicStoreCopyLocalHostName(nil) as String?) ?? ""
        return n.isEmpty ? "localhost" : "\(n).local"
    }
    /// This Mac's address on the Wi-Fi, for when a network doesn't pass on ".local" names.
    var ipAddress: String? {
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let first = ptr else { return nil }
        defer { freeifaddrs(ptr) }
        var found: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: a.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.hasPrefix("169.254") { found = ip; if name == "en0" { break } }
            }
        }
        return found
    }
    var url: String { "http://\(hostName):\(PhoneServer.port)/#k=\(key)" }
    var localURL: String { "http://localhost:\(PhoneServer.port)/#k=\(key)" }
    var ipURL: String? { ipAddress.map { "http://\($0):\(PhoneServer.port)/#k=\(key)" } }

    static func qr(_ text: String) -> String? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSBitmapImageRep(ciImage: img)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    func status() -> [String: Any] {
        var s: [String: Any] = ["on": on, "running": running, "url": url, "host": hostName, "port": Int(PhoneServer.port)]
        if let q = PhoneServer.qr(url) { s["qr"] = q }
        if let ip = ipURL { s["ipURL"] = ip; if let q = PhoneServer.qr(ip) { s["ipQR"] = q } }
        if let p = problem { s["problem"] = p }
        // Round 21: the page on your website — opens anywhere, works offline, sends back by AirDrop.
        var projects = Shared.projects()
        if let i = projects.firstIndex(of: Shared.project) { projects.remove(at: i); projects.insert(Shared.project, at: 0) }
        let pair = PhoneDrops.pairURL(projects: projects, mac: Host.current().localizedName ?? "your Mac")
        s["photos"] = PhotosInbox.on
        s["albums"] = PhotosInbox.albums
        s["photosAccess"] = PhotosInbox.status
        s["vaultURL"] = PhoneDrops.pageURL
        s["pairURL"] = pair
        if let q = PhoneServer.qr(pair) { s["vaultQR"] = q }
        return s
    }

    // MARK: Connections

    private func accept(_ c: NWConnection) {
        let conn = HTTPConn(c, server: self)
        conns[ObjectIdentifier(conn)] = conn
        conn.onClose = { [weak self] in self?.conns[ObjectIdentifier(conn)] = nil }
        conn.start(queue: queue)
    }

    // MARK: Answering

    /// What phones asked for, kept small: ~/Library/Logs/Needed Tools/Phone.log — handy when something doesn't load.
    private func log(_ line: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Needed Tools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("Phone.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        if let size = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.intValue, size > 400_000 { try? FileManager.default.removeItem(at: u) }
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data("\(stamp) \(line)\n".utf8)); try? h.close() }
        else { try? Data("\(stamp) \(line)\n".utf8).write(to: u) }
    }
    static var logURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Needed Tools/Phone.log") }

    fileprivate func answer(_ r: HTTPConn.Request, body: URL?, conn: HTTPConn) {
        let path = r.path
        log("\(r.method) \(path) \(r.header("user-agent")?.contains("iPhone") == true ? "iPhone" : "")")
        if !path.hasPrefix("/api/") { return serveStatic(path, conn: conn) }
        guard r.header("x-key") == key || r.query["k"] == key else {
            return conn.send(status: 401, type: "application/json", body: json(["error": "This phone isn't paired — scan the QR code in Needed Tools › Home › Your phone"]))
        }
        switch (r.method, path) {
        case ("GET", "/api/state"):
            conn.send(status: 200, type: "application/json", body: json(onMain { self.state() }))
        case ("GET", "/api/items"):
            let p = r.query["p"] ?? ""
            let list = onMain { self.items(of: p) }
            conn.send(status: 200, type: "application/json", body: json(["p": p, "items": list]))
        case ("GET", "/api/thumb"), ("GET", "/api/file"):
            let id = r.query["id"] ?? ""
            let full = path == "/api/file"
            guard let u = onMain({ self.fileURL(id: id, full: full) }) else { return conn.send(status: 404, type: "text/plain", body: Data("Not found".utf8)) }
            conn.sendFile(u, type: HTTPConn.mime(u.pathExtension), range: r.header("range"), cache: !full)
        case ("POST", "/api/upload"):
            guard let tmp = body else { return conn.send(status: 400, type: "application/json", body: json(["error": "Nothing came"])) }
            let p = r.query["p"] ?? "", name = r.query["name"] ?? "Photo.jpg"
            let tags = (r.query["tags"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            let out = onMain { self.upload(tmp, project: p, name: name, tags: tags) }
            try? FileManager.default.removeItem(at: tmp)
            conn.send(status: (out["ok"] as? Bool) == true ? 200 : 400, type: "application/json", body: json(out))
        default:
            conn.send(status: 404, type: "text/plain", body: Data("Not found".utf8))
        }
    }

    private func serveStatic(_ path: String, conn: HTTPConn) {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("mobile", isDirectory: true) else { return conn.send(status: 404, type: "text/plain", body: Data()) }
        var rel = path == "/" ? "index.html" : String(path.dropFirst())
        rel = rel.removingPercentEncoding ?? rel
        guard !rel.contains(".."), !rel.hasPrefix("/") else { return conn.send(status: 404, type: "text/plain", body: Data()) }
        let u = root.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: u.path) else { return conn.send(status: 404, type: "text/plain", body: Data("Not found".utf8)) }
        conn.sendFile(u, type: HTTPConn.mime(u.pathExtension), range: nil, cache: rel != "index.html")
    }

    private func onMain<T>(_ f: @escaping () -> T) -> T {
        if Thread.isMainThread { return f() }
        return DispatchQueue.main.sync(execute: f)
    }
    private func json(_ o: Any) -> Data { (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8) }

    // MARK: The vault, for the phone (main thread)

    private func media(_ it: [String: Any]) -> Bool { ["still", "gif", "clip"].contains(it["kind"] as? String ?? "") }

    private func state() -> [String: Any] {
        VaultStore.shared.load()
        var counts: [String: Int] = [:]
        for it in VaultStore.shared.items where media(it) { counts[(it["project"] as? String) ?? "Unsorted", default: 0] += 1 }
        let labels = Labels.all()
        let projects = Shared.projects().filter { $0 != "Unsorted" }.map { ["n": $0, "c": counts[$0] ?? 0, "l": labels[$0] ?? ""] as [String: Any] }
        return ["projects": projects, "current": Shared.project, "mac": Host.current().localizedName ?? "your Mac", "vault": Shared.vault != nil]
    }

    private func items(of project: String) -> [[String: Any]] {
        VaultStore.shared.load()
        let base = Shared.vault
        return VaultStore.shared.items
            .filter { media($0) && ($0["project"] as? String) == project }
            .sorted { (($0["created"] as? String) ?? "") > (($1["created"] as? String) ?? "") }
            .prefix(400)
            .map { it -> [String: Any] in
                let id = (it["id"] as? String) ?? ""
                let src = it["source"] as? [String: Any] ?? [:]
                var o: [String: Any] = ["id": id, "k": it["kind"] as? String ?? "still"]
                let file = (it["file"] as? String) ?? ""
                o["n"] = (it["title"] as? String) ?? (src["title"] as? String) ?? ((file as NSString).lastPathComponent as NSString).deletingPathExtension
                if let u = src["url"] as? String { o["u"] = u }
                if let t = src["type"] as? String { o["s"] = t }
                if let g = it["tags"] as? [String], !g.isEmpty { o["g"] = g }
                if let c = it["palette"] as? [String] { o["c"] = Array(c.prefix(5)) }
                if let d = it["created"] as? String { o["d"] = String(d.prefix(10)) }
                if let a = aspects[id] { o["a"] = a }
                else if let b = base, let rel = (it["thumb"] as? String) ?? (it["file"] as? String), let a = PhoneServer.aspect(b.appendingPathComponent(rel)) {
                    aspects[id] = a; o["a"] = a
                }
                return o
            }
    }
    static func aspect(_ u: URL) -> Double? {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Double, let h = p[kCGImagePropertyPixelHeight] as? Double, h > 0 else { return nil }
        let o = (p[kCGImagePropertyOrientation] as? Int) ?? 1
        let a = o >= 5 ? h / w : w / h
        return (a * 100).rounded() / 100
    }

    private func fileURL(id: String, full: Bool) -> URL? {
        guard let base = Shared.vault, !id.isEmpty else { return nil }
        VaultStore.shared.load()
        guard let it = VaultStore.shared.items.first(where: { ($0["id"] as? String) == id }) else { return nil }
        let rel = full ? (it["file"] as? String) : ((it["thumb"] as? String) ?? (it["file"] as? String))
        guard let r = rel, !r.contains("..") else { return nil }
        let u = base.appendingPathComponent(r)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    private func upload(_ tmp: URL, project raw: String, name: String, tags: [String]) -> [String: Any] {
        guard let base = Shared.vault else { return ["ok": false, "error": "Choose your vault on the Mac first"] }
        let project = Shell.clean(raw).isEmpty ? Shared.project : Shell.clean(raw)
        var clean = (name as NSString).lastPathComponent.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if clean.hasPrefix(".") || clean.isEmpty { clean = "Photo.jpg" }
        let ext = (clean as NSString).pathExtension.lowercased()
        let kind: String
        switch ext {
        case "gif": kind = "gif"
        case "mp4", "mov", "m4v": kind = "clip"
        case "jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff": kind = "still"
        default: return ["ok": false, "error": "Needed Vault takes photos, screenshots, GIFs and clips"]
        }
        let folder = kind == "clip" ? "Motion" : kind == "gif" ? "GIFs" : "Stills"
        let dir = base.appendingPathComponent(project, isDirectory: true).appendingPathComponent(Folders.sub(folder, project: project, grab: false), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = CloudVault.unique(dir, clean)
        guard (try? FileManager.default.moveItem(at: tmp, to: dst)) != nil || (try? FileManager.default.copyItem(at: tmp, to: dst)) != nil else {
            return ["ok": false, "error": "Couldn't write it into \(project)"]
        }
        var meta: [String: Any] = ["origin": "reference", "source": ["type": "phone", "title": (clean as NSString).deletingPathExtension]]
        if !tags.isEmpty { meta["tags"] = tags }
        let item = VaultStore.shared.register(kind: kind, file: dst, meta: meta, project: project)
        Shared.notify()
        NotificationCenter.default.post(name: .neededPhoneAdded, object: nil, userInfo: ["project": project])
        return ["ok": true, "id": item["id"] as? String ?? "", "project": project, "kind": kind]
    }
}

/// One phone asking one thing: a small HTTP/1.1, a request per connection.
final class HTTPConn {
    struct Request {
        var method = "", path = "", query: [String: String] = [:], headers: [String: String] = [:]
        func header(_ k: String) -> String? { headers[k.lowercased()] }
    }
    private let c: NWConnection
    private weak var server: PhoneServer?
    private var buf = Data()
    private var req: Request?
    private var bodyLeft = 0
    private var bodyFile: URL?
    private var bodyHandle: FileHandle?
    var onClose: (() -> Void)?
    private var closed = false

    init(_ c: NWConnection, server: PhoneServer) { self.c = c; self.server = server }

    func start(queue: DispatchQueue) {
        c.stateUpdateHandler = { [weak self] s in
            switch s { case .failed, .cancelled: self?.finish(); default: break }
        }
        self.queue = queue
        c.start(queue: queue)
        read()
    }
    func close() { c.cancel() }
    /// The reply is all handed over: say so (the phone sees the end of it), then let go a moment later.
    /// Cancelling straight away can drop what's still on its way — Safari shows a blank page.
    private func done() {
        c.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.queue?.asyncAfter(deadline: .now() + 3) { self?.close() }
        })
    }
    private var queue: DispatchQueue?
    private func finish() {
        guard !closed else { return }
        closed = true
        try? bodyHandle?.close()
        if let f = bodyFile { try? FileManager.default.removeItem(at: f) }
        onClose?()
    }

    private func read() {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 18) { [weak self] data, _, done, err in
            guard let self = self else { return }
            if let d = data, !d.isEmpty { self.take(d) }
            if err != nil { return self.close() }
            if done && self.req == nil { return self.close() }
            if !self.closed && (self.req == nil || self.bodyLeft > 0) { self.read() }
        }
    }

    private func take(_ d: Data) {
        if req == nil {
            buf.append(d)
            guard let end = buf.range(of: Data("\r\n\r\n".utf8)) else {
                if buf.count > 64_000 { send(status: 431, type: "text/plain", body: Data()) }
                return
            }
            let head = String(decoding: buf[buf.startIndex..<end.lowerBound], as: UTF8.self)
            let rest = buf[end.upperBound...]
            buf = Data()
            var r = Request()
            let lines = head.components(separatedBy: "\r\n")
            let first = (lines.first ?? "").split(separator: " ").map(String.init)
            guard first.count >= 2 else { return send(status: 400, type: "text/plain", body: Data()) }
            r.method = first[0].uppercased()
            let target = first[1]
            let parts = target.split(separator: "?", maxSplits: 1).map(String.init)
            r.path = parts.first ?? "/"
            if parts.count > 1 {
                for pair in parts[1].split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    let k = (kv.first ?? "").replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
                    let v = (kv.count > 1 ? kv[1] : "").replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
                    r.query[k] = v
                }
            }
            for l in lines.dropFirst() {
                guard let i = l.firstIndex(of: ":") else { continue }
                r.headers[l[..<i].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
            req = r
            let len = Int(r.header("content-length") ?? "") ?? 0
            if r.method == "POST", len > 0 {
                guard len < 2_000_000_000 else { return send(status: 413, type: "text/plain", body: Data()) }
                let f = FileManager.default.temporaryDirectory.appendingPathComponent("needed-upload-\(UUID().uuidString)")
                FileManager.default.createFile(atPath: f.path, contents: nil)
                bodyFile = f; bodyHandle = try? FileHandle(forWritingTo: f); bodyLeft = len
                if !rest.isEmpty { writeBody(Data(rest)) }
            } else {
                server?.answer(r, body: nil, conn: self)
            }
        } else if bodyLeft > 0 {
            writeBody(d)
        }
    }
    private func writeBody(_ d: Data) {
        let chunk = d.prefix(bodyLeft)
        bodyHandle?.write(chunk)
        bodyLeft -= chunk.count
        if bodyLeft <= 0, let r = req {
            try? bodyHandle?.close(); bodyHandle = nil
            let f = bodyFile; bodyFile = nil
            server?.answer(r, body: f, conn: self)
        }
    }

    // MARK: Replies

    private func head(_ status: Int, _ type: String, _ length: Int, extra: [String: String] = [:]) -> Data {
        let reason = [200: "OK", 206: "Partial Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 413: "Too Large", 416: "Range Not Satisfiable", 431: "Too Large"][status] ?? "OK"
        var h = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\nConnection: close\r\n"
        for (k, v) in extra { h += "\(k): \(v)\r\n" }
        return Data((h + "\r\n").utf8)
    }
    func send(status: Int, type: String, body: Data) {
        var out = head(status, type, body.count, extra: ["Cache-Control": "no-store"])
        out.append(body)
        c.send(content: out, completion: .contentProcessed { [weak self] _ in self?.done() })
    }
    /// A file, whole or the part asked for (Safari plays clips in parts), sent a megabyte at a time.
    func sendFile(_ u: URL, type: String, range: String?, cache: Bool) {
        guard let fh = try? FileHandle(forReadingFrom: u),
              let size = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? NSNumber)?.intValue else {
            return send(status: 404, type: "text/plain", body: Data())
        }
        var start = 0, end = size - 1, status = 200
        var extra: [String: String] = ["Accept-Ranges": "bytes", "Cache-Control": cache ? "private, max-age=86400" : "no-store"]
        if let r = range, r.hasPrefix("bytes=") {
            let spec = r.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
            let ab = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            if ab.count == 2 {
                if ab[0].isEmpty, let n = Int(ab[1]) { start = max(0, size - n) }
                else { start = Int(ab[0]) ?? 0; if let e = Int(ab[1]) { end = min(e, size - 1) } }
            }
            guard start <= end, start < size else {
                try? fh.close()
                return send(status: 416, type: "text/plain", body: Data())
            }
            status = 206
            extra["Content-Range"] = "bytes \(start)-\(end)/\(size)"
        }
        let total = end - start + 1
        try? fh.seek(toOffset: UInt64(start))
        var left = total
        func next() {
            guard left > 0 else { try? fh.close(); return done() }
            let n = min(left, 1 << 20)
            let d = fh.readData(ofLength: n)
            if d.isEmpty { try? fh.close(); return done() }
            left -= d.count
            c.send(content: d, completion: .contentProcessed { [weak self] e in
                if e != nil { try? fh.close(); self?.close() } else { next() }
            })
        }
        c.send(content: head(status, type, total, extra: extra), completion: .contentProcessed { [weak self] e in
            if e != nil { try? fh.close(); self?.close() } else { next() }
        })
    }

    static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "webmanifest": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "woff2": return "font/woff2"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Round 21/22: from the phone — by Photos (iCloud) or AirDrop
// Needed Vault on the website keeps what you capture on the phone. Its Sync button
// saves it into the phone's Photos (iCloud Photos brings it to this Mac) — or it can
// be AirDropped. Either way each file carries where it's going in its name:
//     NV ~ Lexus ~ night, car ~ IMG_1234 ~ k3f9x2a.jpg      (no tags: "~ - ~")
// The last part is the phone's own id for it. Sync looks in Downloads and in Photos,
// files each one into its project's references with its tags, and remembers the id —
// so the same picture never lands in the vault twice, whichever way it came (or both).
// In Photos, it's then sorted into an album per project, inside a "Needed Vault" folder.

enum PhoneDrops {
    struct Drop { let file: URL; let kind: String; let project: String; let tags: [String]; let title: String; let phoneId: String; let via: String }
    struct Parsed { let project: String; let tags: [String]; let name: String; let id: String }

    static var downloads: URL? { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first }

    /// "NV ~ Lexus ~ night, car ~ IMG_1234 ~ k3f9x2a.jpg" → Lexus, [night, car], IMG_1234.jpg, k3f9x2a
    static func parse(_ file: String) -> Parsed? {
        guard file.hasPrefix("NV ~ ") else { return nil }
        let ext = (file as NSString).pathExtension
        var stem = ext.isEmpty ? file : (file as NSString).deletingPathExtension
        // AirDrop and Finder add " 2", " 3"… to a name that's already there — not part of it.
        if let r = stem.range(of: #" \d{1,3}$"#, options: .regularExpression) { stem.removeSubrange(r) }
        var parts = stem.components(separatedBy: " ~ ")
        guard parts.count >= 4 else { return nil }
        let project = parts[1].trimmingCharacters(in: .whitespaces)
        let tags = parts[2].split(whereSeparator: { $0 == "," || $0 == "#" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "-" }
        var id = ""
        if parts.count >= 5, let last = parts.last?.trimmingCharacters(in: .whitespaces),
           last.count >= 6, last.count <= 24, last.allSatisfy({ $0.isLetter || $0.isNumber }) {
            id = last; parts.removeLast()
        }
        var name = parts[3...].joined(separator: " ~ ").trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "From your phone" }
        return Parsed(project: project, tags: tags, name: ext.isEmpty ? name : name + "." + ext, id: id)
    }

    static func kind(_ ext: String) -> String? {
        switch ext.lowercased() {
        case "gif": return "gif"
        case "mp4", "mov", "m4v": return "clip"
        case "jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff": return "still"
        default: return nil
        }
    }

    // MARK: What's been filed already — the phone's id → where it went

    private static func seenURL(_ base: URL) -> URL { base.appendingPathComponent(".vault/phone-seen.json") }
    static func loadSeen(_ base: URL) -> [String: String] {
        ((try? Data(contentsOf: seenURL(base))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }) ?? [:]
    }
    static func saveSeen(_ seen: [String: String], _ base: URL) {
        try? FileManager.default.createDirectory(at: base.appendingPathComponent(".vault", isDirectory: true), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: seen) { try? d.write(to: seenURL(base), options: .atomic) }
    }

    /// The vault's own project folders, so "lexus" on the phone finds "Lexus" here.
    static func projectFolders(_ base: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }.map { $0.lastPathComponent }
    }
    static func projectFor(_ raw: String, fallback: String, existing: [String]) -> String {
        var project = raw.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : Shell.clean(raw)
        if let same = existing.first(where: { $0.caseInsensitiveCompare(project) == .orderedSame }) { project = same }
        return project
    }

    /// Moves (or copies) one file into its project's references. Nil if it isn't one Needed Tools takes.
    static func place(_ f: URL, _ p: Parsed, base: URL, fallback: String, existing: [String], move: Bool, via: String) -> Drop? {
        let fm = FileManager.default
        guard let k = kind((p.name as NSString).pathExtension) ?? kind(f.pathExtension) else { return nil }
        let project = projectFor(p.project, fallback: fallback, existing: existing)
        var clean = p.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if clean.hasPrefix(".") || (clean as NSString).deletingPathExtension.isEmpty { clean = "From your phone." + f.pathExtension }
        let folder = k == "clip" ? "Motion" : k == "gif" ? "GIFs" : "Stills"
        let dir = base.appendingPathComponent(project, isDirectory: true).appendingPathComponent(Folders.sub(folder, project: project, grab: false), isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dst = CloudVault.unique(dir, clean)
        let ok = move ? ((try? fm.moveItem(at: f, to: dst)) != nil) : ((try? fm.copyItem(at: f, to: dst)) != nil)
        guard ok else { return nil }
        return Drop(file: dst, kind: k, project: project, tags: p.tags, title: (clean as NSString).deletingPathExtension, phoneId: p.id, via: via)
    }

    /// Everything from the phone, both ways, each once. Off the main thread (Sync calls it).
    static func collect(base: URL, fallback: String, progress: ((Double) -> Void)? = nil) -> (drops: [Drop], twice: Int, photos: String?) {
        var seen = loadSeen(base)
        let existing = projectFolders(base)
        var out: [Drop] = [], twice = 0
        let fm = FileManager.default
        // 1. AirDrop: Needed Vault files in Downloads
        if let dl = downloads, let files = try? fm.contentsOfDirectory(at: dl, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let p = parse(f.lastPathComponent), kind(f.pathExtension) != nil else { continue }
                if !p.id.isEmpty, seen[p.id] != nil {
                    // Already in the vault (it came through Photos too): the extra copy goes to the Bin.
                    try? fm.trashItem(at: f, resultingItemURL: nil); twice += 1; continue
                }
                guard let d = place(f, p, base: base, fallback: fallback, existing: existing, move: true, via: "airdrop") else { continue }
                if !d.phoneId.isEmpty { seen[d.phoneId] = d.file.path.replacingOccurrences(of: base.path + "/", with: "") }
                out.append(d)
            }
        }
        saveSeen(seen, base)
        // 2. Photos: what the phone saved there, brought over by iCloud Photos
        let (fromPhotos, twiceP, note) = PhotosInbox.collect(base: base, fallback: fallback, existing: existing, progress: progress)
        return (out + fromPhotos, twice + twiceP, note)
    }

    /// Where the phone page lives: your website, so it opens anywhere and works offline.
    static var pageURL: String {
        let u = UserDefaults.standard.string(forKey: "vaultPageURL") ?? ""
        return u.hasPrefix("https://") ? u : "https://thiswasneeded.info/vault/"
    }
    /// The QR carries your projects (most recent first) and this Mac's name, so the phone knows where things can go.
    /// In the address itself (not after a #): Add to Home Screen keeps it, so the app on the phone starts with them.
    static func pairURL(projects: [String], mac: String) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-_. ")
        let enc = { (s: String) -> String in (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s).replacingOccurrences(of: " ", with: "%20") }
        var list: [String] = [], len = 0
        for p in projects where p != "Unsorted" {
            let e = enc(p.replacingOccurrences(of: "|", with: "-").replacingOccurrences(of: "~", with: "-"))
            if len + e.count > 300 { break }                      // a QR a phone can still read at a glance
            list.append(e); len += e.count + 1
        }
        return pageURL + "?p=" + list.joined(separator: "|") + "&m=" + enc(mac)
    }
}

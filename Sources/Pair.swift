// Needed Tools — your projects on your phone, kept up to date (Round 32).
// The QR code in Home › Your phone carries a pairing key after the # (browsers never send
// that part anywhere). This Mac leaves its project list, scrambled with that key, at
// thiswasneeded.info/api/pair; Mobile Vault on the phone picks it up whenever it opens or
// syncs — so a project you make here shows up there without scanning again. The website only
// ever holds gibberish: no photos, no names it can read.

import Foundation
import CryptoKit
import Security

enum PairRelay {
    private static let d = UserDefaults.standard

    /// A random value made once and kept: the pairing id, the key, the write secret.
    private static func secret(_ name: String, bytes: Int) -> String {
        if let s = d.string(forKey: name), !s.isEmpty { return s }
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        let s = b64url(Data(b))
        d.set(s, forKey: name)
        return s
    }
    static var id: String { secret("pairId", bytes: 16) }
    static var key: String { secret("pairKey", bytes: 32) }
    private static var write: String { secret("pairWrite", bytes: 24) }

    /// What goes after the # in the QR code: the id and the key.
    static var fragment: String { "#k=\(id).\(key)" }

    private static var endpoint: URL? {
        guard let page = URL(string: PhoneDrops.pageURL), let scheme = page.scheme, let host = page.host else { return nil }
        return URL(string: "\(scheme)://\(host)/api/pair?id=\(id)")
    }

    static func b64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func fromB64url(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    // MARK: Sending the list

    private static var timer: Timer?
    private static var observer: NSObjectProtocol?

    /// At launch: send once, then again whenever projects change (a moment after, so a rename is one send).
    static func start() {
        push()
        observer = NotificationCenter.default.addObserver(forName: .neededShared, object: nil, queue: .main) { _ in
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in push() }
        }
    }

    /// The list, scrambled, to the website — only when it's changed (or once a day, so it never goes stale).
    static func push(force: Bool = false) {
        var projects = Shared.projects().filter { $0 != "Unsorted" }
        if let i = projects.firstIndex(of: Shared.project) { projects.remove(at: i); projects.insert(Shared.project, at: 0) }
        let mac = Host.current().localizedName ?? "your Mac"
        let sig = projects.joined(separator: "|") + "@" + mac
        let last = d.string(forKey: "pairSent") ?? "", lastAt = d.double(forKey: "pairSentAt")
        if !force && sig == last && Date().timeIntervalSince1970 - lastAt < 86400 { return }
        guard let url = endpoint, let keyData = fromB64url(key), keyData.count == 32 else { return }
        let payload: [String: Any] = ["v": 1, "projects": projects, "mac": mac, "at": Int(Date().timeIntervalSince1970 * 1000)]
        guard let plain = try? JSONSerialization.data(withJSONObject: payload),
              let sealed = try? AES.GCM.seal(plain, using: SymmetricKey(data: keyData)), let box = sealed.combined,
              let body = try? JSONSerialization.data(withJSONObject: ["box": b64url(box), "w": write]) else { return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }       // offline, or the website isn't set up for it yet: next time
            DispatchQueue.main.async { d.set(sig, forKey: "pairSent"); d.set(Date().timeIntervalSince1970, forKey: "pairSentAt") }
        }.resume()
    }
}

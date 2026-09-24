// Needed Tools — licensing.
// This Was Needed · thiswasneeded.info
//
// One key, one Mac. Activation is the only network request the app ever
// makes: the key and an anonymous hash of this Mac's hardware ID go to the
// payment provider, nothing else — never your references. The answer is kept
// as a signed receipt in Application Support and never rechecked.
//
// Provider comes from Resources/licence.json:
//   "test"          try the flow with no provider (key NV-TEST-0000-0000)
//   "keys"          a fixed list of tester keys, stored only as hashes
//   "off"           no licence at all — opens straight in (for your own use)
//   "lemonsqueezy"  Lemon Squeezy licence API; set the activation limit to 1
//   "gumroad"       Gumroad licence API; one use per key enforced here
//
// This is a speed bump that makes paying the easy path, not a lock.

import Foundation
import CryptoKit
import IOKit

final class Licence {
    static let testKey = "NV-TEST-0000-0000"
    private let salt = "needed-tools/twn/2026"
    private let config: [String: Any]
    private let support: URL

    private var receiptURL: URL { support.appendingPathComponent("licence.json") }
    private var ledgerURL: URL { support.appendingPathComponent("test_ledger.json") }

    private let inUse = "This key is already in use on another Mac. Deactivate it there first, or buy another."
    private let offline = "Activation needs an internet connection, once. Connect and try again — after this it works offline."

    init(resources: URL) {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser
        support = base.appendingPathComponent("NeededTools", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: resources.appendingPathComponent("licence.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = json
        } else {
            config = ["provider": "test"]
        }
    }

    var provider: String { (config["provider"] as? String) ?? "test" }

    // MARK: This Mac

    /// A one-way hash of macOS's own hardware UUID. Nothing personal and
    /// not reversible; stable across reinstalls of the app.
    lazy var fingerprint: String = {
        let raw = Licence.hardwareUUID() ?? self.storedFallbackID()
        return String(Licence.hex(SHA256.hash(data: Data((self.salt + raw).utf8))).prefix(32))
    }()

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(mach_port_t(0),
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString,
                                                    kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? String
    }

    /// Generated once and kept, if the hardware ID can't be read.
    private func storedFallbackID() -> String {
        let file = support.appendingPathComponent(".machine")
        if let s = try? String(contentsOf: file, encoding: .utf8),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let id = UUID().uuidString
        try? id.write(to: file, atomically: true, encoding: .utf8)
        return id
    }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Receipt

    private static let fields = ["key", "provider", "instance", "customer", "activated", "fingerprint"]

    /// Keyed to this Mac, so a receipt copied from another Mac, or edited
    /// by hand, fails to verify.
    private func sign(_ r: [String: String]) -> String {
        let canonical = Licence.fields.map { r[$0] ?? "" }.joined(separator: "\u{1F}")
        let key = SymmetricKey(data: Data((salt + fingerprint).utf8))
        return Licence.hex(HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: key))
    }

    private func readReceipt() -> [String: String]? {
        guard let data = try? Data(contentsOf: receiptURL),
              let r = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let sig = r["sig"], sig == sign(r),
              r["fingerprint"] == fingerprint else { return nil }
        return r
    }

    private func writeReceipt(key: String, instance: String, customer: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var r: [String: String] = [
            "key": key, "provider": provider, "instance": instance,
            "customer": customer, "activated": formatter.string(from: Date()),
            "fingerprint": fingerprint,
        ]
        r["sig"] = sign(r)
        if let data = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted]) {
            try? data.write(to: receiptURL, options: .atomic)
        }
    }

    private func mask(_ key: String) -> String {
        key.count <= 8 ? key : String(key.prefix(4)) + "…" + String(key.suffix(4))
    }

    // MARK: Public

    func status() -> [String: Any] {
        if provider == "off" {
            return ["licensed": true, "key": "", "customer": "", "activated": "",
                    "provider": "off", "test_mode": false, "unlicensed_build": true]
        }
        let r = readReceipt()
        return [
            "licensed": r != nil,
            "key": mask(r?["key"] ?? ""),
            "customer": r?["customer"] ?? "",
            "activated": r?["activated"] ?? "",
            "provider": provider,
            "test_mode": provider == "test",
        ]
    }

    func activate(_ rawKey: String, done: @escaping ([String: Any]) -> Void) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return done(["ok": false, "error": "Paste your licence key."]) }

        let succeed: (String, String) -> Void = { instance, customer in
            self.writeReceipt(key: key, instance: instance, customer: customer)
            done(["ok": true])
        }

        switch provider {
        case "lemonsqueezy":
            post("https://api.lemonsqueezy.com/v1/licenses/activate",
                 ["license_key": key, "instance_name": "Mac " + String(fingerprint.prefix(8))]) { json, isOffline in
                if isOffline { return done(["ok": false, "error": self.offline]) }
                let j = json ?? [:]
                guard (j["activated"] as? Bool) == true else {
                    let err = ((j["error"] as? String) ?? "").lowercased()
                    return done(["ok": false,
                                 "error": err.contains("limit") ? self.inUse : "That key isn't valid."])
                }
                let meta = j["meta"] as? [String: Any] ?? [:]
                let want = Licence.text((self.config["lemonsqueezy"] as? [String: Any])?["product_id"])
                if !want.isEmpty && Licence.text(meta["product_id"]) != want {
                    return done(["ok": false, "error": "That key is for a different product."])
                }
                let instance = (j["instance"] as? [String: Any])?["id"] as? String ?? ""
                let customer = (meta["customer_email"] as? String) ?? (meta["customer_name"] as? String) ?? ""
                succeed(instance, customer)
            }

        case "keys":
            // Tester keys, stored only as hashes so they can't be read out of
            // the app. No internet needed. With no server, nothing stops one
            // key being used on several Macs — fine for trusted testers only.
            let hashes = ((config["keys"] as? [String: Any])?["hashes"] as? [String]) ?? []
            let digest = Licence.hex(SHA256.hash(data: Data((salt + key.uppercased()).utf8)))
            guard hashes.contains(digest) else {
                return done(["ok": false, "error": "That key isn't valid."])
            }
            succeed("", "Tester")

        case "gumroad":
            // Gumroad has a use counter, not per-machine activations. The first
            // activation takes it to 1; anything above that is a second Mac.
            let pid = Licence.text((config["gumroad"] as? [String: Any])?["product_id"])
            guard !pid.isEmpty else { return done(["ok": false, "error": "Licensing isn't set up yet."]) }
            post("https://api.gumroad.com/v2/licenses/verify",
                 ["product_id": pid, "license_key": key, "increment_uses_count": "true"]) { json, isOffline in
                if isOffline { return done(["ok": false, "error": self.offline]) }
                let j = json ?? [:]
                guard (j["success"] as? Bool) == true else {
                    return done(["ok": false, "error": "That key isn't valid."])
                }
                let purchase = j["purchase"] as? [String: Any] ?? [:]
                if (purchase["refunded"] as? Bool) == true || (purchase["chargebacked"] as? Bool) == true {
                    return done(["ok": false, "error": "That purchase was refunded."])
                }
                if ((j["uses"] as? Int) ?? 1) > 1 {
                    return done(["ok": false,
                                 "error": "This key is already in use on another Mac. Email me and I'll reset it."])
                }
                succeed("", (purchase["email"] as? String) ?? "")
            }

        default: // test
            guard key.uppercased() == Licence.testKey else {
                return done(["ok": false, "error": "That key isn't valid."])
            }
            var used = readLedger()
            if !used.isEmpty && !used.contains(fingerprint) {
                return done(["ok": false, "error": inUse])
            }
            if !used.contains(fingerprint) { used.append(fingerprint) }
            writeLedger(used)
            succeed(String(fingerprint.prefix(12)), "Test licence")
        }
    }

    func deactivate(done: @escaping ([String: Any]) -> Void) {
        guard let r = readReceipt() else { return done(["ok": true]) }
        let forget: () -> Void = { _ = try? FileManager.default.removeItem(at: self.receiptURL) }

        switch r["provider"] ?? "test" {
        case "lemonsqueezy":
            post("https://api.lemonsqueezy.com/v1/licenses/deactivate",
                 ["license_key": r["key"] ?? "", "instance_id": r["instance"] ?? ""]) { _, isOffline in
                if isOffline {
                    return done(["ok": false,
                                 "error": "Deactivating needs an internet connection, so the key can be freed for another Mac."])
                }
                forget()
                done(["ok": true])
            }
        case "keys":
            forget()
            done(["ok": true])
        case "gumroad":
            // Freeing a Gumroad key needs the seller's private token, which
            // must never ship inside the app.
            forget()
            done(["ok": true, "note": "Email me and I'll free the key for your other Mac."])
        default:
            writeLedger(readLedger().filter { $0 != fingerprint })
            forget()
            done(["ok": true])
        }
    }

    // MARK: Plumbing

    private func readLedger() -> [String] {
        guard let d = try? Data(contentsOf: ledgerURL),
              let a = try? JSONSerialization.jsonObject(with: d) as? [String] else { return [] }
        return a
    }

    private func writeLedger(_ a: [String]) {
        if let d = try? JSONSerialization.data(withJSONObject: a) {
            try? d.write(to: ledgerURL, options: .atomic)
        }
    }

    private static func text(_ v: Any?) -> String {
        guard let v = v, !(v is NSNull) else { return "" }
        return "\(v)"
    }

    private func post(_ address: String, _ fields: [String: String],
                      _ done: @escaping ([String: Any]?, Bool) -> Void) {
        guard let url = URL(string: address) else { return done(nil, false) }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var safe = CharacterSet.alphanumerics
        safe.insert(charactersIn: "-._~")
        req.httpBody = fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: safe) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, _, error in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { done(json, error != nil) }
        }.resume()
    }
}

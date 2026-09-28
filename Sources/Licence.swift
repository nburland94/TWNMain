// Needed Tools — licensing.
// This Was Needed · thiswasneeded.info
//
// One key, one Mac. The key and an anonymous hash of this Mac's hardware ID go
// to the payment provider, nothing else — never your references. The answer is
// kept as a signed receipt in Application Support.
//
// Provider comes from Resources/licence.json:
//   "test"          try the flow with no provider (key NV-TEST-0000-0000)
//   "keys"          a fixed list of tester keys, stored only as hashes
//   "off"           no licence at all — opens straight in (for your own use)
//   "lemonsqueezy"  Lemon Squeezy licence API — a subscription (round 39):
//                   the free month starts at checkout (card up front, then it
//                   rolls on by itself). The key is checked again about once a
//                   week; offline, it keeps working for 14 days after the last
//                   good check. When the subscription ends, Lemon Squeezy
//                   expires the key and the app asks to renew.
//                   licence.json › "lemonsqueezy": product_id, checkout_url
//                   (the product's "Buy" link, with the free trial set on it),
//                   manage_url (defaults to Lemon Squeezy's My Orders page).
//   "gumroad"       Gumroad licence API; one use per key enforced here
//
// This is a speed bump that makes paying the easy path, not a lock.

import Foundation
import CryptoKit
import IOKit
import AppKit

final class Licence {
    static let testKey = "NV-TEST-0000-0000"
    private let salt = "needed-tools/twn/2026"
    private let config: [String: Any]
    private let support: URL

    private var receiptURL: URL { support.appendingPathComponent("licence.json") }
    private var stateURL: URL { support.appendingPathComponent("licence-state.json") }
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

    // MARK: Subscription state — when the key was last checked, and what it said

    /// Kept beside the receipt and signed the same way, so it can't be edited by hand.
    /// status: "active" | "expired" | "disabled"; checked: the last good check (yyyy-MM-dd'T'HH:mm:ssZ);
    /// variant: which option was bought (for which tools it includes).
    private static let stateFields = ["status", "checked", "variant", "plan", "renews", "fingerprint"]
    private func signState(_ s: [String: String]) -> String {
        let canonical = Licence.stateFields.map { s[$0] ?? "" }.joined(separator: "\u{1F}")
        let key = SymmetricKey(data: Data((salt + "state" + fingerprint).utf8))
        return Licence.hex(HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: key))
    }
    private func readState() -> [String: String]? {
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              s["sig"] == signState(s), s["fingerprint"] == fingerprint else { return nil }
        return s
    }
    private func writeState(status: String, variant: String, plan: String, renews: String = "") {
        var s: [String: String] = ["status": status, "checked": Licence.iso.string(from: Date()), "variant": variant,
                                   "plan": plan, "renews": renews, "fingerprint": fingerprint]
        s["sig"] = signState(s)
        if let data = try? JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted]) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
    private static let iso = ISO8601DateFormatter()
    private static let checkEvery: TimeInterval = 7 * 86_400        // ask Lemon Squeezy about once a week
    private static let offlineGrace: TimeInterval = 14 * 86_400     // and keep working this long without an answer
    private static var checking = false

    private var lemon: [String: Any] { (config["lemonsqueezy"] as? [String: Any]) ?? [:] }
    var checkoutURL: String { Licence.text(lemon["checkout_url"]) }
    var manageURL: String { Licence.text(lemon["manage_url"]).isEmpty ? "https://app.lemonsqueezy.com/my-orders" : Licence.text(lemon["manage_url"]) }

    /// Tiers: which tools each option (Lemon Squeezy variant id) includes. No table, or an option not in it: every tool.
    ///   "tiers": { "123456": { "name": "Essentials", "tools": ["vault", "grab", "shots"] } }
    private func tools(for variant: String) -> [String]? {
        guard let tiers = lemon["tiers"] as? [String: Any], let t = tiers[variant] as? [String: Any],
              let list = t["tools"] as? [String], !list.isEmpty else { return nil }
        return list.map { $0.lowercased() }
    }

    /// Asks Lemon Squeezy whether the key is still good — at most once a week, in the background.
    private func recheckIfDue(_ r: [String: String]) {
        let last = readState().flatMap { $0["checked"] }.flatMap { Licence.iso.date(from: $0) }
        if let l = last, Date().timeIntervalSince(l) < Licence.checkEvery { return }
        validate(r) { _ in }
    }
    /// Checks the key now. done(true) when the answer changed what the app should show.
    func validate(_ r: [String: String]? = nil, done: @escaping (Bool) -> Void) {
        guard provider == "lemonsqueezy", let r = r ?? readReceipt(), !Licence.checking else { return done(false) }
        Licence.checking = true
        let before = readState()?["status"]
        post("https://api.lemonsqueezy.com/v1/licenses/validate",
             ["license_key": r["key"] ?? "", "instance_id": r["instance"] ?? ""]) { json, isOffline in
            Licence.checking = false
            guard !isOffline, let j = json else { return done(false) }            // offline: the grace period covers it
            let lk = j["license_key"] as? [String: Any] ?? [:]
            let meta = j["meta"] as? [String: Any] ?? [:]
            let keyStatus = Licence.text(lk["status"]).lowercased()
            let variant = Licence.text(meta["variant_id"]), plan = Licence.text(meta["variant_name"])
            let renews = Licence.text(lk["expires_at"])
            if (j["valid"] as? Bool) == true && keyStatus != "expired" && keyStatus != "disabled" {
                self.writeState(status: "active", variant: variant, plan: plan, renews: renews)
            } else if keyStatus == "expired" || keyStatus == "disabled" {
                self.writeState(status: keyStatus, variant: variant, plan: plan, renews: renews)
            } else if (j["valid"] as? Bool) == false, !(j["license_key"] is NSNull), j["license_key"] != nil || j["error"] is String {
                // A clear "no" (not a hiccup like too many requests, which carries no answer about the key):
                // Not valid for this Mac any more (deactivated elsewhere, refunded): ask for the key again.
                self.writeState(status: "disabled", variant: variant, plan: plan)
            }
            done(self.readState()?["status"] != before)
        }
    }

    /// The checkout, with your email filled in if the app knows it. `code`: a discount code, e.g. FOUNDERS.
    func openCheckout(code: String = "") {
        guard var c = URLComponents(string: checkoutURL), !checkoutURL.isEmpty else { return }
        var q = c.queryItems ?? []
        if let email = (UserDefaults.standard.dictionary(forKey: "profile") as? [String: String])?["email"], !email.isEmpty {
            q.append(URLQueryItem(name: "checkout[email]", value: email))
        }
        let code = code.isEmpty ? Licence.text(lemon["discount_code"]) : code
        if !code.isEmpty { q.append(URLQueryItem(name: "checkout[discount_code]", value: code)) }
        c.queryItems = q.isEmpty ? nil : q
        if let u = c.url { NSWorkspace.shared.open(u) }
    }
    func openManage() { if let u = URL(string: manageURL) { NSWorkspace.shared.open(u) } }

    private func mask(_ key: String) -> String {
        key.count <= 8 ? key : String(key.prefix(4)) + "…" + String(key.suffix(4))
    }

    // MARK: Public

    /// Whether this Mac may open `tool` ("vault", "grab"…; nil = the app as a whole).
    /// reason, when not: "none" (no key yet), "expired" (subscription ended), "offline" (no check for 14 days),
    /// "tier" (the plan bought doesn't include this tool).
    func status(tool: String? = nil) -> [String: Any] {
        if provider == "off" {
            return ["licensed": true, "key": "", "customer": "", "activated": "",
                    "provider": "off", "test_mode": false, "unlicensed_build": true]
        }
        let r = readReceipt()
        var out: [String: Any] = [
            "licensed": r != nil,
            "key": mask(r?["key"] ?? ""),
            "customer": r?["customer"] ?? "",
            "activated": r?["activated"] ?? "",
            "provider": provider,
            "test_mode": provider == "test",
            "reason": r == nil ? "none" : "",
            "canBuy": provider == "lemonsqueezy" && !checkoutURL.isEmpty,
        ]
        guard provider == "lemonsqueezy", let receipt = r else { return out }
        // A subscription: what the last check said, and whether it's time to ask again.
        out["subscription"] = true
        out["manage"] = true
        let s = readState()
        // No check on record yet (a key activated before round 39): fine for now — the check below runs straight away.
        let checked = s.flatMap { $0["checked"] }.flatMap { Licence.iso.date(from: $0) } ?? Date()
        out["plan"] = s?["plan"] ?? ""
        out["renews"] = s?["renews"] ?? ""
        out["checked"] = s?["checked"] ?? ""
        if let st = s?["status"], st == "expired" || st == "disabled" {
            out["licensed"] = false; out["reason"] = st == "expired" ? "expired" : "none"
        } else if Date().timeIntervalSince(checked) > Licence.offlineGrace {
            out["licensed"] = false; out["reason"] = "offline"
        } else if let t = tool?.lowercased(), let allowed = s.flatMap({ tools(for: $0["variant"] ?? "") }), !allowed.contains(t) {
            out["licensed"] = false; out["reason"] = "tier"
        }
        recheckIfDue(receipt)
        return out
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
                let lk = j["license_key"] as? [String: Any] ?? [:]
                let st = Licence.text(lk["status"]).lowercased()
                if st == "expired" || st == "disabled" {
                    return done(["ok": false, "error": "That subscription has ended — renew it, then paste the key again."])
                }
                // The subscription starts fresh: checked now, with the option bought (for its tools).
                self.writeState(status: "active", variant: Licence.text(meta["variant_id"]), plan: Licence.text(meta["variant_name"]),
                                renews: Licence.text(lk["expires_at"]))
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
        let forget: () -> Void = {
            _ = try? FileManager.default.removeItem(at: self.receiptURL)
            _ = try? FileManager.default.removeItem(at: self.stateURL)
        }

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

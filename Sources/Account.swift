// Needed Tools — your account: sign in with Google or Apple (round 46).
//
// Sign-in goes through Supabase (one free service that handles both Google and Apple). The Mac's own
// secure sign-in window (ASWebAuthenticationSession) opens Google's or Apple's page; the app never sees
// a password. What comes back: who you are (name, email) and a session that stays signed in.
//
//   Resources/account.json   { "supabaseUrl": "https://xxxx.supabase.co", "supabaseAnonKey": "…", "providers": ["google", "apple"] }
//   (the anon key is public by design — it's safe inside the app; never put a service or secret key here)
//
// Personal builds use one desktop Google consent for identity and Gmail sending. Apple still uses Supabase.
// Your email becomes the default address Pay sends from — unless Apple hid it ("Hide my email"),
// or you've set another. Your projects never leave your Mac: sign-in only says who you are.
// Empty account.json: no sign-in screen (the owner's own builds open straight in).

import Foundation
import AppKit
import AuthenticationServices
import CryptoKit

final class Account: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = Account()
    weak var window: NSWindow?
    private var session: ASWebAuthenticationSession?
    static let callbackScheme = "neededtools"
    static let redirect = "neededtools://auth-callback"

    // MARK: Settings

    private lazy var config: [String: Any] = {
        guard let u = Bundle.main.resourceURL?.appendingPathComponent("account.json"), let d = try? Data(contentsOf: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return j
    }()
    private var base: String { ((config["supabaseUrl"] as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: " /")) }
    private var anonKey: String { (config["supabaseAnonKey"] as? String) ?? "" }
    var providers: [String] { (config["providers"] as? [String]) ?? ["google", "apple"] }
    var configured: Bool { (MailConnection.enabled && !MailConnection.client("gmail").isEmpty) || (base.hasPrefix("https://") && !anonKey.isEmpty) }

    // MARK: The session, kept on this Mac (readable only by you)

    private static var sessionURL: URL {
        let b = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return b.appendingPathComponent("NeededTools/account.json")
    }
    private var stored: [String: Any]? {
        get {
            guard let d = try? Data(contentsOf: Account.sessionURL) else { return nil }
            return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        }
        set {
            let u = Account.sessionURL
            guard let v = newValue else { try? FileManager.default.removeItem(at: u); return }
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONSerialization.data(withJSONObject: v) {
                try? d.write(to: u, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
            }
        }
    }
    var user: [String: Any]? { stored?["user"] as? [String: Any] }
    var signedIn: Bool {
        if stored?["directGoogle"] as? Bool == true {
            return MailConnection.credentials()?["email"] as? String == email
        }
        return user != nil
    }
    var email: String { (user?["email"] as? String) ?? "" }
    /// Apple's "Hide my email" gives a relay address — it can receive mail, but you can't send from it.
    var hiddenEmail: Bool { email.lowercased().hasSuffix("privaterelay.appleid.com") }

    func status() -> [String: Any] {
        ["configured": configured, "providers": providers, "signedIn": signedIn, "email": email,
         "name": (user?["name"] as? String) ?? "", "provider": (user?["provider"] as? String) ?? "", "hiddenEmail": hiddenEmail]
    }

    // MARK: Signing in

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window ?? NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    private static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    func signIn(provider raw: String, done: @escaping ([String: Any]) -> Void) {
        if raw == "google", MailConnection.enabled, !MailConnection.client("gmail").isEmpty {
            _ = MailConnection.handleRaw("emailConnect", ["provider": "gmail"]) { result, _ in
                guard let r = result as? [String: Any], r["ready"] as? Bool == true,
                      let c = MailConnection.credentials(), let email = c["email"] as? String else {
                    return done((result as? [String: Any]) ?? ["ok": false, "error": "Google sign-in did not finish."])
                }
                self.stored = ["directGoogle": true, "user": ["id": c["id"] as? String ?? "", "email": email,
                    "name": c["name"] as? String ?? "", "provider": "google"]]
                self.applyProfile()
                done(["ok": true, "account": self.status()])
            }
            return
        }
        guard configured else { return done(["ok": false, "error": "Sign-in isn't set up in this build yet."]) }
        let provider = raw == "apple" ? "apple" : "google"
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Account.b64url(Data(bytes))
        let challenge = Account.b64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        var c = URLComponents(string: base + "/auth/v1/authorize")!
        c.queryItems = [URLQueryItem(name: "provider", value: provider), URLQueryItem(name: "redirect_to", value: Account.redirect),
                        URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "s256")]
        guard let url = c.url else { return done(["ok": false, "error": "Sign-in isn't set up correctly."]) }
        let s = ASWebAuthenticationSession(url: url, callbackURLScheme: Account.callbackScheme) { [weak self] cb, err in
            DispatchQueue.main.async {
                self?.session = nil
                if let e = err as? ASWebAuthenticationSessionError, e.code == .canceledLogin { return done(["ok": false, "cancelled": true]) }
                guard let self = self, err == nil, let cb = cb, let q = URLComponents(url: cb, resolvingAgainstBaseURL: false)?.queryItems else {
                    return done(["ok": false, "error": "Sign-in didn't finish — try again."])
                }
                if let code = q.first(where: { $0.name == "code" })?.value { return self.exchange(code: code, verifier: verifier, provider: provider, done: done) }
                let why = q.first(where: { $0.name == "error_description" })?.value?.replacingOccurrences(of: "+", with: " ")
                done(["ok": false, "error": why ?? "Sign-in didn't finish — try again."])
            }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false          // stay signed in to Google/Apple in the sign-in window
        session = s
        if !s.start() { session = nil; done(["ok": false, "error": "The sign-in window couldn't open."]) }
    }

    private func post(_ path: String, _ body: [String: Any], bearer: String? = nil, done: @escaping ([String: Any]?, Int) -> Void) {
        guard let url = URL(string: base + path) else { return done(nil, 0) }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let b = bearer { r.setValue("Bearer \(b)", forHTTPHeaderField: "Authorization") }
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { done(j, code) }
        }.resume()
    }

    private func exchange(code: String, verifier: String, provider: String, done: @escaping ([String: Any]) -> Void) {
        post("/auth/v1/token?grant_type=pkce", ["auth_code": code, "code_verifier": verifier]) { j, status in
            guard status == 200, let j = j, self.keep(j, provider: provider) else {
                return done(["ok": false, "error": (j?["error_description"] as? String) ?? (j?["msg"] as? String) ?? "Sign-in didn't finish — try again."])
            }
            self.applyProfile()
            done(["ok": true, "account": self.status()])
        }
    }
    /// Keeps the session and the parts of the user the app needs.
    @discardableResult
    private func keep(_ j: [String: Any], provider: String? = nil) -> Bool {
        guard let access = j["access_token"] as? String, let refresh = j["refresh_token"] as? String else { return false }
        let u = (j["user"] as? [String: Any]) ?? (user ?? [:])
        let meta = (u["user_metadata"] as? [String: Any]) ?? [:]
        let prov = provider ?? ((u["app_metadata"] as? [String: Any])?["provider"] as? String) ?? (user?["provider"] as? String) ?? ""
        let name = (meta["full_name"] as? String) ?? (meta["name"] as? String) ?? (user?["name"] as? String) ?? ""
        let expires = Date().addingTimeInterval((j["expires_in"] as? Double) ?? 3600).timeIntervalSince1970
        stored = ["access_token": access, "refresh_token": refresh, "expires_at": expires,
                  "user": ["id": (u["id"] as? String) ?? (user?["id"] as? String) ?? "", "email": (u["email"] as? String) ?? email, "name": name, "provider": prov]]
        return true
    }

    /// At launch: keep the session fresh. Offline, you stay signed in; only a refused session signs you out.
    func refresh(done: @escaping (Bool) -> Void = { _ in }) {
        if stored?["directGoogle"] as? Bool == true { return done(signedIn) }
        guard configured, let s = stored, let rt = s["refresh_token"] as? String else { return done(signedIn) }
        let exp = (s["expires_at"] as? Double) ?? 0
        if Date().timeIntervalSince1970 < exp - 600 { return done(true) }
        post("/auth/v1/token?grant_type=refresh_token", ["refresh_token": rt]) { j, status in
            if status == 200, let j = j, self.keep(j) { return done(true) }
            if status == 400 || status == 401 { self.stored = nil; return done(false) }     // refused: sign in again
            done(true)                                                                        // offline or a hiccup: carry on
        }
    }

    func signOut() {
        if MailConnection.enabled {
            MailConnection.generation = UUID()
            MailConnection.login?.cancel(); MailConnection.login = nil
            _ = MailConnection.store(nil)
            UserDefaults.standard.set("apple", forKey: "neededOwnerMailMode")
        }
        if let t = stored?["access_token"] as? String, configured { post("/auth/v1/logout", [:], bearer: t) { _, _ in } }
        stored = nil
    }

    // MARK: Your details

    /// Your name and email go into your details (if empty) — and your email becomes the address Pay sends from,
    /// unless Apple hid it or you've already set one.
    func applyProfile() {
        var p = Shell.profile
        if (p["name"] ?? "").isEmpty, let n = user?["name"] as? String, !n.isEmpty { p["name"] = n }
        if (p["email"] ?? "").isEmpty, !email.isEmpty, !hiddenEmail { p["email"] = email }
        Shell.profile = p
        Shared.notify()
    }
}

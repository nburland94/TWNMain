import AppKit
import Foundation
import Network
import CryptoKit
import Security
import UniformTypeIdentifiers

/// One sending connection for Pay and Project. Credentials never enter the web views.
enum MailConnection {
    static let queue = DispatchQueue(label: "needed.email", qos: .userInitiated)
    static var login: MailLogin?
    static var generation = UUID()
    // Personal build only. Licence-key beta builds keep their existing authentication.
    static var enabled: Bool {
        guard let u = Bundle.main.resourceURL?.appendingPathComponent("licence.json"),
              let d = try? Data(contentsOf: u), let c = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
        return c["provider"] as? String == "off"
    }
    static var mode: String { enabled ? (UserDefaults.standard.string(forKey: "neededOwnerMailMode") ?? "apple") : "smtp" }
    static let keyService = "Needed Tools — owner Google email"
    static var config: [String: String] {
        guard enabled, let u = Bundle.main.resourceURL?.appendingPathComponent("email-oauth.json"), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return [:] }
        return o
    }
    static func client(_ provider: String) -> String { config[provider + "ClientID"] ?? "" }
    static func credentials() -> [String: Any]? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService,
            kSecAttrAccount as String: "connection", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    static func store(_ o: [String: Any]?) -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService, kSecAttrAccount as String: "connection"]
        guard let o = o else { let s = SecItemDelete(q as CFDictionary); return s == errSecSuccess || s == errSecItemNotFound }
        guard let d = try? JSONSerialization.data(withJSONObject: o) else { return false }
        let changes = [kSecValueData as String: d]
        let updated = SecItemUpdate(q as CFDictionary, changes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var add = q; add[kSecValueData as String] = d; add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    static func status() -> [String: Any] {
        let c = credentials(), oauth = mode == "gmail" || mode == "outlook"
        let smtp = Mailer.account()
        return ["mode": mode, "from": oauth ? (c?["email"] as? String ?? "") : mode == "smtp" ? (smtp?.from ?? "") : "",
                "ready": mode == "apple" || (oauth && c?["provider"] as? String == mode) || (mode == "smtp" && smtp.map { PayKeychain.read($0.from) != nil } == true),
                "gmailAvailable": !client("gmail").isEmpty, "outlookAvailable": !client("outlook").isEmpty]
    }
    static func handle(_ action: String, _ body: [String: Any], _ done: @escaping (Any?, String?) -> Void) -> Bool {
        if action == "emailConnect", body["provider"] as? String == "gmail" {
            Account.shared.signIn(provider: "google") { r in
                if r["ok"] as? Bool == true { done(status(), nil) } else { done(r, nil) }
            }
            return true
        }
        return handleRaw(action, body, done)
    }
    static func handleRaw(_ action: String, _ body: [String: Any], _ done: @escaping (Any?, String?) -> Void) -> Bool {
        switch action {
        case "emailStatus": done(status(), nil)
        case "emailDisconnect":
            generation = UUID(); login?.cancel(); login = nil
            guard store(nil) else { done(["ok": false, "error": "Could not remove the connection from Keychain. Try again."], nil); return true }
            UserDefaults.standard.set("apple", forKey: "neededOwnerMailMode"); done(status(), nil)
        case "emailConnect":
            let p = body["provider"] as? String ?? ""
            guard ["apple", "smtp", "gmail", "outlook"].contains(p) else { done(["ok": false, "error": "Choose an email provider"], nil); return true }
            if p == "apple" || p == "smtp" {
                generation = UUID(); login?.cancel(); login = nil
                UserDefaults.standard.set(p, forKey: "neededOwnerMailMode"); done(status(), nil)
            } else {
                guard !client(p).isEmpty else { done(["ok": false, "error": "This build has not activated \(p == "gmail" ? "Google" : "Microsoft") sign-in yet. Use Apple Mail for now."], nil); return true }
                guard login == nil else { done(["ok": false, "error": "Finish or cancel the sign-in already open."], nil); return true }
                let ticket = UUID(); generation = ticket
                let flow = MailLogin(provider: p, client: client(p)) { code, redirect, verifier, error in
                    login = nil
                    guard generation == ticket else { done(["ok": false, "error": "Sign-in cancelled."], nil); return }
                    guard let code = code else { done(["ok": false, "error": error ?? "Sign-in was cancelled."], nil); return }
                    queue.async {
                        do {
                            var form = ["client_id": client(p), "code": code, "redirect_uri": redirect, "code_verifier": verifier, "grant_type": "authorization_code"]
                            if p == "gmail", let secret = config["gmailClientSecret"], !secret.isEmpty { form["client_secret"] = secret }
                            let token = try tokenRequest(p, form)
                            guard let access = token["access_token"] as? String, let refresh = token["refresh_token"] as? String, !refresh.isEmpty else { throw MailError("Permission was incomplete. Disconnect and connect again, allowing email sending.") }
                            let expected = p == "gmail" ? "https://www.googleapis.com/auth/gmail.send" : "Mail.Send"
                            if let scope = token["scope"] as? String, !scope.split(separator: " ").contains(where: { $0 == expected || $0.hasSuffix("/" + expected) }) { throw MailError("Sending permission was not granted.") }
                            var req = URLRequest(url: URL(string: p == "gmail" ? "https://openidconnect.googleapis.com/v1/userinfo" : "https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName")!)
                            req.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
                            let (data, response) = try request(req)
                            guard response.statusCode == 200, let user = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MailError("Could not confirm your sending address.") }
                            let address = p == "gmail" ? user["email"] as? String : ((user["mail"] as? String) ?? (user["userPrincipalName"] as? String))
                            guard let email = address, validAddress(email), p != "gmail" || user["email_verified"] as? Bool == true else { throw MailError("Your account did not provide a usable email address.") }
                            let record: [String: Any] = ["provider": p, "email": email, "name": user["name"] as? String ?? "", "id": user["sub"] as? String ?? "", "access": access, "refresh": refresh, "expires": Date().timeIntervalSince1970 + (token["expires_in"] as? Double ?? 3600)]
                            DispatchQueue.main.async {
                                guard generation == ticket else { done(["ok": false, "error": "Connection changed; sign in again."], nil); return }
                                guard store(record) else { done(["ok": false, "error": "Could not save the connection in Keychain."], nil); return }
                                UserDefaults.standard.set(p, forKey: "neededOwnerMailMode"); done(status(), nil)
                            }
                        } catch { DispatchQueue.main.async { done(["ok": false, "error": error.localizedDescription], nil) } }
                    }
                }
                login = flow; flow.start()
            }
        case "emailCancel": generation = UUID(); login?.cancel(); login = nil; done(status(), nil)
        default: return false
        }
        return true
    }
    static func b64(_ d: Data) -> String { d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func random() -> String { var bytes = [UInt8](repeating: 0, count: 32); precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess); return b64(Data(bytes)) }
    static func form(_ o: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(o.sorted { $0.key < $1.key }.map { ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&").utf8)
    }
    static func request(_ original: URLRequest) throws -> (Data, HTTPURLResponse) {
        var req = original; req.timeoutInterval = 90
        let sem = DispatchSemaphore(value: 0)
        var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        let task = URLSession.shared.dataTask(with: req) { d, r, e in result = (d, r, e); sem.signal() }; task.resume()
        guard sem.wait(timeout: .now() + 95) == .success else { task.cancel(); throw MailError("The connection timed out. If sending had started, check your Sent folder before retrying.") }
        if result.2 != nil { throw MailError("Connection interrupted. If sending had started, check your Sent folder before retrying.") }
        guard let d = result.0, let r = result.1 as? HTTPURLResponse else { throw MailError("No response from your email provider.") }
        return (d, r)
    }
    static func tokenRequest(_ p: String, _ fields: [String: String]) throws -> [String: Any] {
        var req = URLRequest(url: URL(string: p == "gmail" ? "https://oauth2.googleapis.com/token" : "https://login.microsoftonline.com/common/oauth2/v2.0/token")!)
        req.httpMethod = "POST"; req.httpBody = form(fields); req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (d, r) = try request(req)
        guard r.statusCode == 200, let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw MailError("Your email connection needs attention. Connect your account again.") }
        return o
    }
    static func access(_ p: String, ticket: UUID) throws -> (String, String) {
        guard var c = credentials(), c["provider"] as? String == p, let email = c["email"] as? String else { throw MailError("Connect your email account first.") }
        if (c["expires"] as? Double ?? 0) > Date().timeIntervalSince1970 + 60, let token = c["access"] as? String { return (token, email) }
        guard let refresh = c["refresh"] as? String else { throw MailError("Connect your email account again.") }
        var fields = ["client_id": client(p), "refresh_token": refresh, "grant_type": "refresh_token"]
        if p == "gmail", let secret = config["gmailClientSecret"], !secret.isEmpty { fields["client_secret"] = secret }
        let t = try tokenRequest(p, fields)
        guard let token = t["access_token"] as? String else { throw MailError("Connect your email account again.") }
        c["access"] = token; c["expires"] = Date().timeIntervalSince1970 + (t["expires_in"] as? Double ?? 3600)
        if let refresh = t["refresh_token"] as? String { c["refresh"] = refresh }
        let saved = DispatchQueue.main.sync { generation == ticket && store(c) }
        guard saved else { throw MailError("The connection changed or could not be updated. Connect again.") }
        return (token, email)
    }
    static func matches(_ body: [String: Any]) -> Bool {
        guard let expected = body["emailMode"] as? String else { return true }
        let now = status()
        return expected == mode && (body["emailFrom"] as? String ?? "") == (now["from"] as? String ?? "")
    }
    static func validAddress(_ s: String) -> Bool { s.range(of: "^[^@\\s<>;,]+@[^@\\s<>;,]+\\.[^@\\s<>;,]+$", options: .regularExpression) != nil && !s.contains("\r") && !s.contains("\n") }
    static func header(_ s: String) -> String { "=?UTF-8?B?" + Data(s.utf8).base64EncodedString() + "?=" }
    static func mime(from: String, to: [String], cc: [String], bcc: [String], subject: String, body: String, files: [URL]) throws -> Data {
        let boundary = "needed-" + UUID().uuidString
        var m = "From: \(from)\r\nTo: \(to.joined(separator: ", "))\r\n"
        if !cc.isEmpty { m += "Cc: \(cc.joined(separator: ", "))\r\n" }
        if !bcc.isEmpty { m += "Bcc: \(bcc.joined(separator: ", "))\r\n" }
        m += "Subject: \(header(subject))\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n"
        func encoded(_ data: Data) -> String { data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]) }
        m += "--\(boundary)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n\(encoded(Data(body.utf8)))\r\n"
        for file in files {
            guard let data = try? Data(contentsOf: file) else { throw MailError("Could not read \(file.lastPathComponent). Nothing was sent.") }
            let name = header(file.lastPathComponent), type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            m += "--\(boundary)\r\nContent-Type: \(type)\r\nContent-Disposition: attachment; filename=\"\(name)\"\r\nContent-Transfer-Encoding: base64\r\n\r\n\(encoded(data))\r\n"
        }
        m += "--\(boundary)--\r\n"; return Data(m.utf8)
    }
    static func send(to: [[String: Any]], cc: [[String: Any]], bcc: [[String: Any]], subject: String, body: String, files: [URL], copy: Bool, keepIn: URL?, done: @escaping ([String: Any]) -> Void) {
        let tos = to.map { $0["email"] as? String ?? "" }, ccs = cc.map { $0["email"] as? String ?? "" }, bccs = bcc.map { $0["email"] as? String ?? "" }
        guard !(tos + ccs + bccs).isEmpty, (tos + ccs + bccs).allSatisfy(validAddress) else { done(["ok": false, "error": "Add a valid email address for every recipient."]); return }
        var total = 0
        for f in files {
            guard let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true else { done(["ok": false, "error": "An attachment is missing or is not a file. Nothing was sent."]); return }
            total += v.fileSize ?? 0
        }
        guard total <= 24 * 1024 * 1024 else { done(["ok": false, "error": "Attachments are too large. Send fewer documents or share a link."]); return }
        if mode == "apple" { draft(to: tos, cc: ccs, bcc: bccs, subject: subject, body: body, files: files, done: done); return }
        let provider = mode, ticket = generation
        queue.async {
            do {
                let (token, from) = try access(provider, ticket: ticket)
                let copies = copy && !(tos + ccs + bccs).contains(where: { $0.lowercased() == from.lowercased() }) ? bccs + [from] : bccs
                let data = try mime(from: from, to: tos, cc: ccs, bcc: copies, subject: subject, body: body, files: files)
                guard DispatchQueue.main.sync(execute: { generation == ticket }) else { throw MailError("The email connection changed. Review the message and send again.") }
                var req = URLRequest(url: URL(string: provider == "gmail" ? "https://gmail.googleapis.com/gmail/v1/users/me/messages/send" : "https://graph.microsoft.com/v1.0/me/sendMail")!)
                req.httpMethod = "POST"; req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                if provider == "gmail" { req.httpBody = try JSONSerialization.data(withJSONObject: ["raw": b64(data)]); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
                else {
                    let wire = Data(data.base64EncodedString().utf8)
                    guard wire.count < 3_800_000 else { throw MailError("These documents exceed this Outlook connection’s attachment limit. Choose Apple Mail for this message or send smaller files.") }
                    req.httpBody = wire; req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
                }
                let (_, response) = try request(req)
                guard response.statusCode == (provider == "gmail" ? 200 : 202) else {
                    if response.statusCode == 401 || response.statusCode == 403 { throw MailError("Your account did not allow sending. Reconnect it or check your organisation’s permissions.") }
                    throw MailError("Your provider did not confirm acceptance (\(response.statusCode)). Check Sent before retrying.")
                }
                var saved = ""
                if let dir = keepIn {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let u = dir.appendingPathComponent("Email-\(UUID().uuidString).eml")
                    if (try? data.write(to: u, options: .atomic)) != nil { saved = u.path }
                }
                DispatchQueue.main.async { done(["ok": true, "accepted": true, "saved": saved]) }
            } catch { DispatchQueue.main.async { done(["ok": false, "error": error.localizedDescription]) } }
        }
    }
    static func appleString(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n") + "\"" }
    static func draftSource(to: [String], cc: [String], bcc: [String], subject: String, body: String, files: [URL]) -> String {
        var script = "tell application \"/System/Applications/Mail.app\"\nset msg to make new outgoing message with properties {subject:\(appleString(subject)), content:\(appleString(body + "\n\n")), visible:true}\ntell msg\n"
        for (kind, list) in [("to", to), ("cc", cc), ("bcc", bcc)] { for a in list { script += "make new \(kind) recipient at end of \(kind) recipients with properties {address:\(appleString(a))}\n" } }
        script += "end tell\ntell content of msg\n"
        for f in files { script += "make new attachment with properties {file name:(POSIX file \(appleString(f.path)))} at after last paragraph\n" }
        script += "end tell\nactivate\nend tell"
        return script
    }
    static func draft(to: [String], cc: [String], bcc: [String], subject: String, body: String, files: [URL], done: @escaping ([String: Any]) -> Void) {
        let script = draftSource(to: to, cc: cc, bcc: bcc, subject: subject, body: body, files: files)
        var error: NSDictionary?
        guard let draftScript = NSAppleScript(source: script) else { done(["ok": false, "error": "Could not prepare the Mail draft."]); return }
        draftScript.executeAndReturnError(&error)
        if error != nil { done(["ok": false, "error": "Could not prepare the Mail draft. Set up Apple Mail and allow Needed Tools to control Mail in System Settings → Privacy & Security → Automation. Check Mail for a partial draft before retrying."]) }
        else { done(["ok": true, "draft": true, "message": "Opened in Apple Mail. Review the recipients and attachments, then press Send there."]) }
    }
}
struct MailError: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }

/// Browser authorization callback, bound only to the Mac loopback interface.
final class MailLogin {
    let provider: String, client: String
    let state = MailConnection.random(), verifier = MailConnection.random()
    let finished: (String?, String, String, String?) -> Void
    var listener: NWListener?, timeout: DispatchWorkItem?, ended = false, redirect = ""
    var connections: [NWConnection] = []
    init(provider: String, client: String, finished: @escaping (String?, String, String, String?) -> Void) { self.provider = provider; self.client = client; self.finished = finished }
    func start() {
        do {
            let params = NWParameters.tcp
            // Outlook uses an exact registered loopback URL; Google desktop clients allow an ephemeral port.
            let callbackPort: NWEndpoint.Port = provider == "outlook" ? NWEndpoint.Port(rawValue: 53683)! : .any
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: callbackPort)
            let l = try NWListener(using: params); listener = l
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] status in
                guard let self = self, !self.ended else { return }
                if case .ready = status, let port = l.port {
                    self.redirect = "http://127.0.0.1:\(port.rawValue)/oauth/callback"
                    var u = URLComponents(string: self.provider == "gmail" ? "https://accounts.google.com/o/oauth2/v2/auth" : "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
                    var fields = ["client_id": self.client, "redirect_uri": self.redirect, "response_type": "code", "state": self.state, "code_challenge": MailConnection.b64(Data(SHA256.hash(data: Data(self.verifier.utf8)))), "code_challenge_method": "S256", "scope": self.provider == "gmail" ? "openid email profile https://www.googleapis.com/auth/gmail.send" : "offline_access https://graph.microsoft.com/User.Read https://graph.microsoft.com/Mail.Send"]
                    fields["prompt"] = self.provider == "gmail" ? "consent select_account" : "select_account"
                    if self.provider == "gmail" { fields["access_type"] = "offline" }
                    u.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
                    guard let url = u.url, NSWorkspace.shared.open(url) else { self.finish(nil, "Could not open your browser."); return }
                } else if case .failed = status { self.finish(nil, "Could not start secure sign-in. Try again.") }
            }
            l.start(queue: .main)
            let timer = DispatchWorkItem { [weak self] in self?.finish(nil, "Sign-in timed out. Connect again when ready.") }; timeout = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: timer)
        } catch { finish(nil, "Could not start sign-in.") }
    }
    func accept(_ c: NWConnection) {
        guard !ended, connections.count < 8 else { c.cancel(); return }
        connections.append(c); c.start(queue: .main)
        var data = Data()
        func read() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] d, _, closed, error in
                guard let self = self, !self.ended else { c.cancel(); return }
                if let d = d { data.append(d) }
                guard data.count < 16384 else { c.cancel(); return }
                guard let text = String(data: data, encoding: .utf8), text.contains("\r\n\r\n") else { if closed || error != nil { c.cancel() } else { read() }; return }
                let first = text.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard first.count >= 2, first[0] == "GET", let u = URLComponents(string: "http://127.0.0.1" + first[1]), u.path == "/oauth/callback" else { c.cancel(); return }
                let q = u.queryItems ?? []
                guard q.filter({ $0.name == "state" }).count == 1, q.first(where: { $0.name == "state" })?.value == self.state else { c.cancel(); return }
                let code = q.first(where: { $0.name == "code" })?.value
                let message = "Return to Needed Tools to finish connecting. You can close this tab."
                let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(message.utf8.count)\r\n\r\n\(message)"
                c.send(content: Data(reply.utf8), completion: .contentProcessed { _ in self.finish(code, code == nil ? "Sign-in was cancelled or permission was declined." : nil) })
            }
        }
        read()
    }
    func cancel() { finish(nil, "Sign-in cancelled.") }
    func finish(_ code: String?, _ error: String?) {
        guard !ended else { return }; ended = true; timeout?.cancel(); listener?.cancel(); connections.forEach { $0.cancel() }; connections = []
        finished(code, redirect, verifier, error)
    }
}

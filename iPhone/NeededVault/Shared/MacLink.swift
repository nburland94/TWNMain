// Needed Mobile Vault for iPhone — straight to your Mac, over your Wi-Fi.
//
// Needed Tools on the Mac (Home › Your phone) listens on the local network and shows
// a code. The phone reads it once (host, port and a private key); from then on:
//
//   GET  /api/state                                  your projects, their counts and labels
//   POST /api/upload?p=…&name=…&tags=…&phoneId=…     one grab; the Mac answers {ok:true} once it's saved
//
// A grab counts as sent only when the Mac says it saved it. The phoneId is the grab's own id,
// so if an answer is lost and the phone sends again, the Mac doesn't keep a second copy.
// Nothing goes anywhere but your own Mac.

import Foundation

enum MacError: LocalizedError {
    case notPaired, unreachable, refused(String), notPairedAnymore
    var errorDescription: String? {
        switch self {
        case .notPaired: return "Pair with your Mac first"
        case .unreachable: return "Your Mac isn't on this Wi-Fi right now"
        case .refused(let why): return why
        case .notPairedAnymore: return "Your Mac has a new code — scan it again"
        }
    }
}

struct MacState {
    var projects: [ProjectInfo]
    var current: String?
    var name: String
}

enum MacLink {
    /// A short wait when just asking; a longer one for sending (clips can be big).
    static let ask: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5; c.timeoutIntervalForResource = 8
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()
    static let send: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30; c.timeoutIntervalForResource = 600
        c.waitsForConnectivity = false
        c.allowsCellularAccess = false          // Wi-Fi only: the Mac is on your Wi-Fi, and clips are big
        return URLSession(configuration: c)
    }()

    private static func url(_ mac: PairedMac, host: String? = nil, _ path: String, _ query: [String: String] = [:]) -> URL? {
        var c = URLComponents()
        c.scheme = "http"; c.host = host ?? mac.host; c.port = mac.port; c.path = path
        if !query.isEmpty { c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        // "+" must travel as %2B, or the Mac reads it as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }

    /// Asks the Mac for your projects. Tries the name first, then the other address it knows.
    static func state(_ mac: PairedMac) async throws -> (MacState, String) {
        var last: Error = MacError.unreachable
        for host in [mac.host, mac.altHost].compactMap({ $0 }) {
            guard let u = url(mac, host: host, "/api/state") else { continue }
            var r = URLRequest(url: u); r.setValue(mac.key, forHTTPHeaderField: "X-Key"); r.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, resp) = try await ask.data(for: r)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 401 { throw MacError.notPairedAnymore }
                guard code == 200, let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MacError.unreachable }
                let list = (j["projects"] as? [[String: Any]] ?? []).compactMap { p -> ProjectInfo? in
                    guard let n = p["n"] as? String, !n.isEmpty else { return nil }
                    return ProjectInfo(name: n, count: (p["c"] as? Int) ?? 0, label: (p["l"] as? String) ?? "")
                }
                return (MacState(projects: list, current: j["current"] as? String, name: (j["mac"] as? String) ?? mac.name), host)
            } catch let e as MacError where e == .notPairedAnymore {
                throw e
            } catch { last = error }
        }
        throw (last as? MacError) ?? MacError.unreachable
    }

    /// Sends one grab. Returns when the Mac has saved it.
    static func upload(_ g: Grab, file: URL, to mac: PairedMac, host: String) async throws {
        let q = ["p": g.project, "name": g.name, "tags": g.tags.joined(separator: ","), "phoneId": g.id]
        guard let u = url(mac, host: host, "/api/upload", q) else { throw MacError.unreachable }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.setValue(mac.key, forHTTPHeaderField: "X-Key")
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await send.upload(for: r, fromFile: file) } catch { throw MacError.unreachable }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if code == 401 { throw MacError.notPairedAnymore }
        guard code == 200, (j?["ok"] as? Bool) == true else {
            throw MacError.refused((j?["error"] as? String) ?? "Your Mac couldn't take it")
        }
    }
}

extension MacError: Equatable {
    static func == (a: MacError, b: MacError) -> Bool {
        switch (a, b) {
        case (.notPaired, .notPaired), (.unreachable, .unreachable), (.notPairedAnymore, .notPairedAnymore): return true
        case (.refused(let x), .refused(let y)): return x == y
        default: return false
        }
    }
}

/// Sends everything that's waiting, oldest first. Used by the app, the background refresh and the Share Sheet.
enum Sender {
    struct Result { var sent = 0; var left = 0; var problem: String? = nil; var reached = false }

    /// Only one send at a time on this phone.
    private static let gate = NSLock()
    private static var running = false

    static func sendWaiting(limit: Int = .max, progress: ((Int, Int) -> Void)? = nil) async -> Result {
        let lib = Library.shared
        guard var mac = lib.mac else { return Result(left: lib.all().filter { !$0.sent }.count, problem: MacError.notPaired.errorDescription) }
        gate.lock()
        if running { gate.unlock(); return Result(left: lib.all().filter { !$0.sent }.count) }
        running = true; gate.unlock()
        defer { gate.lock(); running = false; gate.unlock() }

        var out = Result()
        // First: is the Mac there? This also brings its projects across.
        let host: String
        do {
            let (st, h) = try await MacLink.state(mac)
            host = h; out.reached = true
            lib.projects = st.projects
            lib.macProject = st.current
            if mac.name != st.name { mac.name = st.name; lib.mac = mac }
        } catch {
            out.left = lib.all().filter { !$0.sent }.count
            out.problem = (error as? MacError)?.errorDescription ?? MacError.unreachable.errorDescription
            return out
        }
        let waiting = Array(lib.all().filter { !$0.sent }.reversed().prefix(limit))      // oldest first
        for (i, g) in waiting.enumerated() {
            progress?(i, waiting.count)
            let f = lib.fileURL(g)
            guard FileManager.default.fileExists(atPath: f.path) else { continue }
            do {
                try await MacLink.upload(g, file: f, to: mac, host: host)
                lib.markSent(g.id); out.sent += 1
            } catch {
                out.problem = (error as? MacError)?.errorDescription ?? error.localizedDescription
                if (error as? MacError) == .unreachable || (error as? MacError) == .notPairedAnymore { break }
            }
        }
        if out.sent > 0 { lib.lastSent = Date() }
        progress?(waiting.count, waiting.count)
        out.left = lib.all().filter { !$0.sent }.count
        return out
    }
}

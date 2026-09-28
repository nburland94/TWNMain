// Needed Tools — working with Claude (round 42).
//
// The Claude app on this Mac talks to Needed Tools through a small helper inside the app
// (Contents/MacOS/needed-mcp — an MCP server). The helper passes each request to this link:
// a private connection on this Mac only (127.0.0.1, with a key), never the network. Claude can
// look through the vault, look at stills, tag them, build treatments in Design and rewrite pages,
// and read the writing you point it at (your "voice" folder, e.g. in Obsidian). The Claude app
// asks you before any of its tools run; changes can also be switched off here.
//
//   POST /tool   {"name": "search_stills", "arguments": {…}}   →   {"content": [...], "isError": false}
//
// Connect (Home › your account › Claude) adds the helper to the Claude app's settings file.

import Foundation
import Network
import AppKit
import WebKit
import ImageIO

final class ClaudeLink {
    static let shared = ClaudeLink()
    weak var shell: Shell?
    private let queue = DispatchQueue(label: "needed.claude")
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    static let preferredPort: UInt16 = 7791

    // MARK: Settings

    var allowChanges: Bool {
        get { UserDefaults.standard.object(forKey: "claudeChanges") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "claudeChanges") }
    }
    var voiceFolder: URL? {
        get { UserDefaults.standard.string(forKey: "claudeVoice").map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: "claudeVoice") }
    }
    var token: String {
        if let t = UserDefaults.standard.string(forKey: "claudeToken"), t.count >= 24 { return t }
        let chars = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let t = String((0..<32).map { _ in chars[Int.random(in: 0..<chars.count)] })
        UserDefaults.standard.set(t, forKey: "claudeToken")
        return t
    }

    /// Where the helper finds this link: the port and the key.
    static var infoURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("NeededTools/claude-link.json")
    }
    static var helperURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/needed-mcp") }
    static var claudeConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    // MARK: The link

    func start() {
        guard listener == nil else { return }
        if !listen(port: ClaudeLink.preferredPort) { listen(port: 0) }
        repairIfMoved()
    }

    // MARK: Round 45 — it fixes itself, restarts Claude for you, and knows when Claude is using it

    /// Set when this launch pointed Claude or Codex at this copy (a new build, or the app was moved). Home says so once.
    private(set) var claudeRepaired = false
    private(set) var codexRepaired = false
    /// Where Needed Tools was already connected to another copy of its helper, point it at this one. Never adds a connection
    /// you didn't make; leaves anything that isn't a Needed Tools helper alone.
    @discardableResult
    func repairIfMoved() -> Bool {
        let me = ClaudeLink.helperURL.path
        guard FileManager.default.isExecutableFile(atPath: me) else { return false }
        let ours = { (c: String) in c != me && c.hasSuffix("/Contents/MacOS/needed-mcp") }
        if let c = ((readClaudeConfig()["mcpServers"] as? [String: Any])?["needed-tools"] as? [String: Any])?["command"] as? String, ours(c),
           (connect()["ok"] as? Bool) == true { claudeRepaired = true }
        if let c = codexCommand(), ours(c), (connectCodex()["ok"] as? Bool) == true { codexRepaired = true }
        return claudeRepaired || codexRepaired
    }
    /// Home asks once after launch: did this launch fix anything?
    func takeRepaired() -> [String: Bool] {
        defer { claudeRepaired = false; codexRepaired = false }
        return ["claude": claudeRepaired, "codex": codexRepaired]
    }

    static let claudeBundleIDs: Set<String> = ["com.anthropic.claudefordesktop", "com.anthropic.claude", "com.anthropic.Claude"]
    static var claudeAppURL: URL? {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") { return u }
        let fm = FileManager.default
        return ["/Applications/Claude.app", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Claude.app").path]
            .first { fm.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    /// Quits the Claude app and opens it again, so it reads its settings — the step people forget.
    func restartClaude(done: @escaping ([String: Any]) -> Void) {
        guard let app = ClaudeLink.claudeAppURL else {
            NSWorkspace.shared.open(URL(string: "https://claude.ai/download")!)
            return done(["ok": false, "error": "The Claude app isn't on this Mac — its download page is open."])
        }
        let running = NSWorkspace.shared.runningApplications.filter { a in
            (a.bundleIdentifier.map { ClaudeLink.claudeBundleIDs.contains($0) } ?? false) || a.bundleURL?.standardizedFileURL == app.standardizedFileURL
        }
        running.forEach { $0.terminate() }
        func reopen(_ tries: Int) {
            if tries > 0 && !running.allSatisfy({ $0.isTerminated }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { reopen(tries - 1) }
                return
            }
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                DispatchQueue.main.async { done(["ok": true, "status": self.status()]) }
            }
        }
        reopen(30)
    }

    /// The helper says hello when an AI app starts it — so Needed Tools can say "Claude is using Needed Tools".
    private func seen(_ client: String) {
        var all = (UserDefaults.standard.dictionary(forKey: "aiSeen") as? [String: String]) ?? [:]
        let who = client.lowercased().contains("codex") ? "codex" : client.lowercased().contains("claude") ? "claude" : "other"
        all[who] = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set(all, forKey: "aiSeen")
        DispatchQueue.main.async { Shared.notify() }
    }
    private var seenDates: [String: String] { (UserDefaults.standard.dictionary(forKey: "aiSeen") as? [String: String]) ?? [:] }
    @discardableResult
    private func listen(port p: UInt16) -> Bool {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback                 // this Mac only
        params.allowLocalEndpointReuse = true
        guard let port = p == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: p),
              let l = try? NWListener(using: params, on: port) else { return false }
        l.newConnectionHandler = { [weak self] c in
            guard let self = self else { return }
            // Loopback only: refuse anything that isn't from this Mac.
            if case let .hostPort(host, _) = c.endpoint {
                let h = "\(host)"
                if !(h.hasPrefix("127.") || h.hasPrefix("::1") || h.hasPrefix("::ffff:127.") || h == "localhost") { c.cancel(); return }
            }
            LinkConn(c, link: self).start(on: self.queue)
        }
        l.stateUpdateHandler = { [weak self] s in
            guard let self = self else { return }
            switch s {
            case .ready:
                self.port = l.port?.rawValue ?? p
                self.writeInfo()
            case .failed:
                l.cancel()
                DispatchQueue.main.async { if self.listener === l { self.listener = nil; if p != 0 { self.listen(port: 0) } } }
            default: break
            }
        }
        l.start(queue: queue)
        listener = l
        return true
    }
    private func writeInfo() {
        let info: [String: Any] = ["port": Int(port), "token": token, "pid": Int(ProcessInfo.processInfo.processIdentifier),
                                   "app": Bundle.main.bundleURL.path]
        let u = ClaudeLink.infoURL
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted]) {
            try? d.write(to: u, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)   // only you can read the key
        }
    }

    // MARK: Connect to the Claude app

    /// Is the helper in the Claude app's settings (pointing at this copy of Needed Tools)?
    func status() -> [String: Any] {
        let cfg = readClaudeConfig()
        let entry = ((cfg["mcpServers"] as? [String: Any])?["needed-tools"] as? [String: Any])
        let cmd = entry?["command"] as? String ?? ""
        let claudeApp = ["/Applications/Claude.app", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Claude.app").path]
            .contains { FileManager.default.fileExists(atPath: $0) }
        return ["connected": !cmd.isEmpty && cmd == ClaudeLink.helperURL.path, "connectedElsewhere": !cmd.isEmpty && cmd != ClaudeLink.helperURL.path,
                "claudeInstalled": claudeApp, "helper": FileManager.default.isExecutableFile(atPath: ClaudeLink.helperURL.path),
                "running": listener != nil && port != 0, "changes": allowChanges, "voice": voiceFolder?.path ?? "",
                "voiceNotes": voiceFiles().count,
                "codexInstalled": codexInstalled, "codexConnected": codexCommand() == ClaudeLink.helperURL.path,
                "codexElsewhere": { let c = codexCommand() ?? ""; return !c.isEmpty && c != ClaudeLink.helperURL.path }(),
                "claudeSeen": seenDates["claude"] ?? "", "codexSeen": seenDates["codex"] ?? "", "otherSeen": seenDates["other"] ?? "",
                "claudeRunning": NSWorkspace.shared.runningApplications.contains { ($0.bundleIdentifier.map { ClaudeLink.claudeBundleIDs.contains($0) } ?? false) }]
    }
    private func readClaudeConfig() -> [String: Any] {
        guard let d = try? Data(contentsOf: ClaudeLink.claudeConfigURL),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return j
    }
    /// Adds Needed Tools to the Claude app's settings file, keeping everything else in it. A copy of the old file is kept beside it.
    func connect() -> [String: Any] {
        guard FileManager.default.isExecutableFile(atPath: ClaudeLink.helperURL.path) else {
            return ["ok": false, "error": "This copy of Needed Tools was built without the Claude helper — build it again with Build-Needed-Tools.command."]
        }
        let u = ClaudeLink.claudeConfigURL
        var cfg = readClaudeConfig()
        if let old = try? Data(contentsOf: u) {
            if (try? JSONSerialization.jsonObject(with: old)) == nil {
                return ["ok": false, "error": "The Claude app's settings file couldn't be read, so it was left alone. Open Claude › Settings › Developer › Edit Config and check it."]
            }
            try? old.write(to: u.deletingLastPathComponent().appendingPathComponent("claude_desktop_config.before-needed-tools.json"), options: .atomic)
        }
        var servers = (cfg["mcpServers"] as? [String: Any]) ?? [:]
        servers["needed-tools"] = ["command": ClaudeLink.helperURL.path, "args": [String]()]
        cfg["mcpServers"] = servers
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]),
              (try? d.write(to: u, options: .atomic)) != nil else { return ["ok": false, "error": "Couldn't write the Claude app's settings file."] }
        start()
        return ["ok": true]
    }
    func disconnect() -> [String: Any] {
        var cfg = readClaudeConfig()
        guard var servers = cfg["mcpServers"] as? [String: Any], servers["needed-tools"] != nil else { return ["ok": true] }
        servers.removeValue(forKey: "needed-tools")
        cfg["mcpServers"] = servers
        if let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: ClaudeLink.claudeConfigURL, options: .atomic) }
        return ["ok": true]
    }
    // MARK: Connect to Codex (round 43) — OpenAI's Codex on this Mac starts the same helper; it stays local.
    // Codex reads ~/.codex/config.toml: a [mcp_servers.needed-tools] section with the helper's path.

    static var codexConfigURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml") }
    private static let codexHeader = "[mcp_servers.needed-tools"
    private static let codexNote = "# Needed Tools — your vault and Design, on this Mac (added by Needed Tools)"

    var codexInstalled: Bool {
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser.path
        return ["\(home)/.codex", "/Applications/Codex.app", "\(home)/Applications/Codex.app", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
            .contains { fm.fileExists(atPath: $0) }
    }
    /// The helper path in Codex's settings, if Needed Tools is there.
    private func codexCommand() -> String? {
        guard let t = try? String(contentsOf: ClaudeLink.codexConfigURL, encoding: .utf8) else { return nil }
        var inside = false
        for raw in t.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inside = line == "[mcp_servers.needed-tools]" || line == "[mcp_servers.\"needed-tools\"]"; continue }
            if inside, line.hasPrefix("command"), let eq = line.firstIndex(of: "=") {
                var v = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
                return v.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
            }
        }
        return nil
    }
    /// Codex's settings without our section (and its sub-sections, and our note).
    private func codexWithout(_ t: String) -> String {
        var out: [String] = [], skipping = false
        for raw in t.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == ClaudeLink.codexNote { continue }
            if line.hasPrefix("[") {
                skipping = line.hasPrefix(ClaudeLink.codexHeader + "]") || line.hasPrefix(ClaudeLink.codexHeader + ".") || line.hasPrefix("[mcp_servers.\"needed-tools\"")
                if skipping { continue }
            }
            if !skipping { out.append(raw) }
        }
        while let last = out.last, last.trimmingCharacters(in: .whitespaces).isEmpty { out.removeLast() }
        return out.joined(separator: "\n")
    }
    func connectCodex() -> [String: Any] {
        guard FileManager.default.isExecutableFile(atPath: ClaudeLink.helperURL.path) else {
            return ["ok": false, "error": "This copy of Needed Tools was built without the helper — build it again with Build-Needed-Tools.command."]
        }
        let u = ClaudeLink.codexConfigURL
        let old = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        if !old.isEmpty { try? old.write(to: u.deletingLastPathComponent().appendingPathComponent("config.before-needed-tools.toml"), atomically: true, encoding: .utf8) }
        let path = ClaudeLink.helperURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let kept = codexWithout(old)
        let block = """
        \(ClaudeLink.codexNote)
        [mcp_servers.needed-tools]
        command = "\(path)"
        args = []
        startup_timeout_sec = 30
        tool_timeout_sec = 300

        """
        let text = (kept.isEmpty ? "" : kept + "\n\n") + block
        do {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        } catch { return ["ok": false, "error": "Couldn't write Codex's settings (~/.codex/config.toml)."] }
        start()
        return ["ok": true]
    }
    func disconnectCodex() -> [String: Any] {
        let u = ClaudeLink.codexConfigURL
        guard let old = try? String(contentsOf: u, encoding: .utf8) else { return ["ok": true] }
        let kept = codexWithout(old)
        try? (kept.isEmpty ? "" : kept + "\n").write(to: u, atomically: true, encoding: .utf8)
        return ["ok": true]
    }
    /// For any other app that takes MCP servers: the usual settings snippet, on the clipboard.
    func copySettings() -> [String: Any] {
        let cfg: [String: Any] = ["mcpServers": ["needed-tools": ["command": ClaudeLink.helperURL.path, "args": [String]()]]]
        guard let d = try? JSONSerialization.data(withJSONObject: cfg, options: [.prettyPrinted, .sortedKeys]) else { return ["ok": false] }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(decoding: d, as: UTF8.self), forType: .string)
        return ["ok": true]
    }

    func chooseVoice(done: @escaping ([String: Any]) -> Void) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Use this folder"
        p.message = "Choose the folder with your writing — past treatments, pitches, director's notes (e.g. an Obsidian folder). A note called “My Voice” is read first."
        p.begin { r in
            if r == .OK, let u = p.url { self.voiceFolder = u }
            done(self.status())
        }
    }

    // MARK: The tools — each answers with MCP content: text, and images for stills

    typealias Reply = ([String: Any]) -> Void
    private func text(_ s: String) -> [String: Any] { ["content": [["type": "text", "text": s]]] }
    private func json(_ o: Any) -> [String: Any] {
        let d = (try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return text(String(decoding: d, as: UTF8.self))
    }
    private func fail(_ s: String) -> [String: Any] { ["content": [["type": "text", "text": s]], "isError": true] }
    private let changeTools: Set<String> = ["tag_stills", "build_treatment", "write_page"]

    /// On the main thread, where the vault list and the pages live.
    func call(_ name: String, _ a: [String: Any], reply: @escaping Reply) {
        if name == "_hello" { seen(str(a["client"]) ?? ""); return reply(["content": [[String: Any]]()]) }
        guard Shared.vault != nil else { return reply(fail("No vault is chosen in Needed Tools yet — open Needed Tools and choose your vault folder.")) }
        if changeTools.contains(name) && !allowChanges {
            return reply(fail("Changes from Claude are switched off in Needed Tools (Home › your account › Claude › Let Claude make changes)."))
        }
        switch name {
        case "list_projects": reply(listProjects())
        case "project_summary": reply(projectSummary(str(a["project"]) ?? Shared.project))
        case "search_stills": reply(searchStills(a))
        case "view_stills": reply(viewStills(a))
        case "tag_stills": reply(tagStills(a))
        case "list_templates": listTemplates(reply)
        case "build_treatment": buildTreatment(a, reply)
        case "list_designs": reply(json(Designs.list(str(a["project"]) ?? Shared.project).map { d -> [String: Any] in
            ["design": d["rel"] ?? "", "name": d["name"] ?? "", "kind": d["mode"] ?? "", "pages": d["pages"] ?? 0, "updated": d["updated"] ?? ""] }))
        case "read_design": reply(readDesign(str(a["design"]) ?? ""))
        case "write_page": writePage(a, reply)
        case "get_my_voice": reply(myVoice())
        default: reply(fail("Needed Tools doesn't know the tool \(name)."))
        }
    }

    private func str(_ v: Any?) -> String? { (v as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
    private func strs(_ v: Any?) -> [String] {
        if let a = v as? [Any] { return a.compactMap { ($0 as? String).flatMap { str($0) } } }
        if let s = str(v) { return s.split(whereSeparator: { $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        return []
    }
    private func items() -> [[String: Any]] { VaultStore.shared.load(); return VaultStore.shared.items }
    private func colours(of it: [String: Any]) -> [String] {
        var out: [String] = []
        for hex in ((it["palette"] as? [String]) ?? []).prefix(3) { for n in Shell.colourNames(hex) where !out.contains(n) { out.append(n) } }
        return out
    }
    private func row(_ it: [String: Any]) -> [String: Any] {
        let src = it["source"] as? [String: Any]
        var r: [String: Any] = ["id": it["id"] ?? "", "project": it["project"] ?? "Unsorted", "kind": it["kind"] ?? "still",
                                "title": (it["title"] as? String) ?? (src?["title"] as? String) ?? "", "tags": (it["tags"] as? [String]) ?? [],
                                "colours": colours(of: it)]
        if let b = it["boards"] as? [String], !b.isEmpty { r["boards"] = b }
        if let o = it["origin"] as? String { r["origin"] = o }
        if let u = src?["url"] as? String { r["source"] = u }
        return r
    }

    private func listProjects() -> [String: Any] {
        var counts: [String: Int] = [:]
        for it in items() where ["still", "gif", "clip"].contains((it["kind"] as? String) ?? "") { counts[(it["project"] as? String) ?? "Unsorted", default: 0] += 1 }
        let labels = Labels.all()
        let list = Shared.projects().map { p -> [String: Any] in ["project": p, "stills_gifs_clips": counts[p] ?? 0, "label": labels[p] ?? ""] }
        return json(["open_in_needed_tools": Shared.project, "projects": list])
    }

    private func projectSummary(_ project: String) -> [String: Any] {
        let mine = items().filter { ($0["project"] as? String) == project }
        guard !mine.isEmpty || Shared.projects().contains(project) else { return fail("There's no project called \(project). list_projects shows them.") }
        var kinds: [String: Int] = [:], tags: [String: Int] = [:], cols: [String: Int] = [:], origins: [String: Int] = [:]
        var untagged = 0
        for it in mine {
            kinds[(it["kind"] as? String) ?? "other", default: 0] += 1
            origins[(it["origin"] as? String) ?? "reference", default: 0] += 1
            let t = (it["tags"] as? [String]) ?? []
            if t.isEmpty && ["still", "gif"].contains((it["kind"] as? String) ?? "") { untagged += 1 }
            for x in t { tags[x, default: 0] += 1 }
            for c in colours(of: it) { cols[c, default: 0] += 1 }
        }
        let top = { (d: [String: Int], n: Int) in d.sorted { $0.value > $1.value }.prefix(n).map { "\($0.key) (\($0.value))" } }
        let designs = Designs.list(project).prefix(12).map { d -> [String: Any] in ["design": d["rel"] ?? "", "name": d["name"] ?? "", "pages": d["pages"] ?? 0] }
        return json(["project": project, "label": Labels.all()[project] ?? "", "kinds": kinds, "origins": origins, "untagged_stills": untagged,
                     "top_tags": top(tags, 40), "top_colours": top(cols, 12), "designs": Array(designs)])
    }

    private func searchStills(_ a: [String: Any]) -> [String: Any] {
        let q = (str(a["query"]) ?? "").lowercased()
        let words = q.split(whereSeparator: { $0 == " " || $0 == "," }).map { String($0).replacingOccurrences(of: "#", with: "") }.filter { !$0.isEmpty }
        let project = str(a["project"]), wantTags = strs(a["tags"]).map { $0.lowercased().replacingOccurrences(of: "#", with: "") }
        let wantCols = strs(a["colours"]).map { $0.lowercased() }, kind = (str(a["kind"]) ?? "stills").lowercased()
        let untagged = (a["untagged"] as? Bool) ?? false, limit = min(max((a["limit"] as? Int) ?? 40, 1), 300)
        var scored: [(Double, [String: Any])] = []
        for it in items() {
            let k = (it["kind"] as? String) ?? ""
            switch kind {
            case "any", "all": guard ["still", "gif", "clip"].contains(k) else { continue }
            case "gif", "gifs": guard k == "gif" else { continue }
            case "clip", "clips": guard k == "clip" else { continue }
            default: guard k == "still" || k == "gif" else { continue }
            }
            if let p = project, (it["project"] as? String) != p { continue }
            let tags = ((it["tags"] as? [String]) ?? []).map { $0.lowercased() }
            if untagged && !tags.isEmpty { continue }
            if !wantTags.isEmpty && !wantTags.allSatisfy({ tags.contains($0) }) { continue }
            let cols = colours(of: it)
            if !wantCols.isEmpty && !wantCols.contains(where: { cols.contains($0) }) { continue }
            var score = 1.0
            if !words.isEmpty {
                let src = it["source"] as? [String: Any]
                let hay = ([(it["title"] as? String) ?? "", (src?["title"] as? String) ?? "", (it["note"] as? String) ?? ""] + tags + ((it["boards"] as? [String]) ?? []) + cols)
                    .joined(separator: " ").lowercased()
                let hits = words.filter { hay.contains($0) }.count
                guard hits > 0 else { continue }
                score = Double(hits) + (words.contains(where: { tags.contains($0) }) ? 0.5 : 0)
            }
            scored.append((score, it))
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : (($0.1["created"] as? String) ?? "") > (($1.1["created"] as? String) ?? "") }
        let found = scored.prefix(limit).map { row($0.1) }
        return json(["found": scored.count, "showing": found.count, "stills": Array(found),
                     "tip": "view_stills shows up to 8 of these as pictures; use their ids in build_treatment and tag_stills."])
    }

    private func viewStills(_ a: [String: Any]) -> [String: Any] {
        guard let base = Shared.vault else { return fail("No vault") }
        let ids = strs(a["ids"]).prefix(8), size = min(max((a["size"] as? Int) ?? 640, 256), 1200)
        let all = items()
        var content: [[String: Any]] = []
        for id in ids {
            guard let it = all.first(where: { ($0["id"] as? String) == id }) else { content.append(["type": "text", "text": "\(id): not in the vault"]); continue }
            let r = row(it)
            content.append(["type": "text", "text": "\(id) · \(r["project"] ?? "") · \(r["title"] ?? "") · tags: \(((r["tags"] as? [String]) ?? []).joined(separator: ", ")) · colours: \(((r["colours"] as? [String]) ?? []).joined(separator: ", "))"])
            let rel = (it["kind"] as? String) == "clip" ? ((it["thumb"] as? String) ?? "") : ((it["file"] as? String) ?? "")
            let fallback = (it["thumb"] as? String) ?? ""
            if let d = ClaudeLink.jpeg(base.appendingPathComponent(rel), max: size) ?? ClaudeLink.jpeg(base.appendingPathComponent(fallback), max: size) {
                content.append(["type": "image", "data": d.base64EncodedString(), "mimeType": "image/jpeg"])
            }
        }
        return ["content": content]
    }
    static func jpeg(_ u: URL, max: Int) -> Data? {
        guard FileManager.default.fileExists(atPath: u.path), let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.78])
    }

    private func tagStills(_ a: [String: Any]) -> [String: Any] {
        let list = (a["items"] as? [[String: Any]]) ?? []
        guard !list.isEmpty else { return fail("items is empty — send [{id, tags}]") }
        let replace = (str(a["mode"]) ?? "add") == "replace"
        let clean = { (t: String) -> String in
            t.lowercased().replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-")
        }
        VaultStore.shared.load()
        var changed = 0, missing: [String] = []
        for entry in list {
            guard let id = str(entry["id"]) else { continue }
            guard let i = VaultStore.shared.items.firstIndex(where: { ($0["id"] as? String) == id }) else { missing.append(id); continue }
            let new = strs(entry["tags"]).map(clean).filter { !$0.isEmpty }
            var tags = replace ? [String]() : ((VaultStore.shared.items[i]["tags"] as? [String]) ?? [])
            for t in new where !tags.contains(t) { tags.append(t) }
            VaultStore.shared.items[i]["tags"] = Array(tags.prefix(40))
            changed += 1
        }
        VaultStore.shared.save()
        Shared.notify()
        return json(["tagged": changed, "not_found": missing])
    }

    // Design: the page itself does the building, with the same engine you use.
    private func design(_ js: String, _ args: [String: Any], _ reply: @escaping Reply, tries: Int = 60) {
        guard let view = shell?.designPage else { return reply(fail("Design isn't ready — open Needed Tools.")) }
        view.evaluateJavaScript("typeof window.__designBuild === 'function'") { r, _ in
            guard (r as? Bool) == true else {
                if tries <= 0 { return reply(self.fail("Design didn't open in time — try again.")) }
                return DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.design(js, args, reply, tries: tries - 1) }
            }
            view.callAsyncJavaScript(js, arguments: args, in: nil, in: .page) { result in
                switch result {
                case .success(let v): reply(self.json(v))
                case .failure(let e): reply(self.fail("Design couldn't do that: \(e.localizedDescription)"))
                }
            }
        }
    }
    private func listTemplates(_ reply: @escaping Reply) {
        design("return { templates: window.__designTemplates(), variants: { a: 'calm grids and splits', b: 'led by the design', c: 'arranges your pictures for you' }, sections: ['Cover', 'Director’s note', 'The idea', 'Look & feel', 'Cinematography', 'Light & colour', 'Casting', 'Wardrobe & styling', 'Locations & design', 'Edit & pace', 'Sound & music', 'Story', 'References', 'Production', 'Thank you'] }", [:], reply)
    }
    private func buildTreatment(_ a: [String: Any], _ reply: @escaping Reply) {
        var spec = a
        let project = str(a["project"]).map { Shell.clean($0) } ?? Shared.project
        guard Shared.projects().contains(project) else { return reply(fail("There's no project called \(project). list_projects shows them.")) }
        // A pool by tags or colours: the stills that fit, from the project.
        let tags = strs(a["pool_tags"]), cols = strs(a["pool_colours"])
        if strs(a["pool"]).isEmpty && (!tags.isEmpty || !cols.isEmpty) {
            var ids: [String] = []
            for t in tags.isEmpty ? [""] : tags {
                let r = searchStills(["project": project, "tags": t.isEmpty ? [] : [t], "colours": cols, "limit": 120])
                if let txt = ((r["content"] as? [[String: Any]])?.first?["text"] as? String), let d = txt.data(using: .utf8),
                   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let s = j["stills"] as? [[String: Any]] {
                    for x in s { if let id = x["id"] as? String, !ids.contains(id) { ids.append(id) } }
                }
            }
            spec["pool"] = ids
        }
        spec["project"] = project
        spec.removeValue(forKey: "pool_tags"); spec.removeValue(forKey: "pool_colours")
        if Shared.project != project { Shared.project = project }
        shell?.show("design")
        design("return await window.__designBuild(spec)", ["spec": spec], reply)
    }
    private func writePage(_ a: [String: Any], _ reply: @escaping Reply) {
        guard let rel = str(a["design"]), Designs.load(rel) != nil else { return reply(fail("Give the design (from list_designs or build_treatment).")) }
        shell?.show("design")
        design("return await window.__designWrite(o)", ["o": a], reply)
    }

    private func readDesign(_ rel: String) -> [String: Any] {
        guard let doc = Designs.load(rel) else { return fail("No design at \(rel) — list_designs shows them.") }
        let pages = ((doc["pages"] as? [[String: Any]]) ?? []).enumerated().map { (i, p) -> [String: Any] in
            let words = ((p["boxes"] as? [[String: Any]]) ?? []).compactMap { b -> [String: Any]? in
                guard let t = b["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, b["shape"] == nil else { return nil }
                return ["role": (b["role"] as? String) ?? "text", "text": t]
            }
            let pics = ((p["pics"] as? [[String: Any]]) ?? []).map { x -> String in ((x["sample"] as? Bool) == true ? "sample:" : "") + ((x["id"] as? String) ?? "") }
            return ["page": i + 1, "words": words, "stills": pics]
        }
        return json(["design": rel, "name": doc["name"] ?? "", "pages": pages])
    }

    private func voiceFiles() -> [URL] {
        guard let dir = voiceFolder else { return [] }
        let fm = FileManager.default
        var out: [URL] = []
        let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        while let u = e?.nextObject() as? URL {
            if e?.level ?? 0 > 3 { e?.skipDescendants(); continue }
            if ["md", "txt", "markdown"].contains(u.pathExtension.lowercased()) { out.append(u) }
            if out.count > 400 { break }
        }
        let date = { (u: URL) in (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        return out.sorted { a, b in
            let av = a.lastPathComponent.lowercased().contains("voice"), bv = b.lastPathComponent.lowercased().contains("voice")
            return av != bv ? av : date(a) > date(b)
        }
    }
    private func myVoice() -> [String: Any] {
        let files = voiceFiles()
        guard !files.isEmpty else {
            return fail("No voice folder yet. In Needed Tools: Home › your account › Claude › Your voice — choose the folder with your treatments and notes (e.g. in Obsidian).")
        }
        var out = "The user's own writing — match its tone, rhythm and vocabulary when writing treatments. Notes named “voice” first, then newest.\n"
        var used = 0
        for f in files {
            guard let t = try? String(contentsOf: f, encoding: .utf8) else { continue }
            let part = "\n\n=== \(f.lastPathComponent) ===\n" + String(t.prefix(12_000))
            if used + part.count > 60_000 { break }
            out += part; used += part.count
        }
        return text(out)
    }
}

/// One request from the helper: a small HTTP/1.1 exchange, JSON in and out.
private final class LinkConn {
    private let c: NWConnection
    private let link: ClaudeLink
    private var buf = Data()
    init(_ c: NWConnection, link: ClaudeLink) { self.c = c; self.link = link }

    func start(on q: DispatchQueue) { c.start(queue: q); read() }
    private func read() {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] data, _, done, err in
            if let d = data { buf.append(d) }
            if handleIfComplete() { return }
            if done || err != nil || buf.count > 8_000_000 { c.cancel(); return }
            read()
        }
    }
    private func handleIfComplete() -> Bool {
        guard let end = buf.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let head = String(decoding: buf[buf.startIndex..<end.lowerBound], as: UTF8.self)
        var headers: [String: String] = [:]
        let lines = head.components(separatedBy: "\r\n")
        for l in lines.dropFirst() { if let i = l.firstIndex(of: ":") { headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
        let len = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = end.upperBound
        guard buf.count - (bodyStart - buf.startIndex) >= len else { return false }
        let body = buf[bodyStart..<buf.index(bodyStart, offsetBy: len)]
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count >= 2, first[0] == "POST", first[1] == "/tool" else { send(404, ["error": "Not found"]); return true }
        guard headers["authorization"] == "Bearer \(link.token)" else { send(401, ["error": "Needed Tools didn't recognise this helper — open Needed Tools, then try again."]); return true }
        guard let j = try? JSONSerialization.jsonObject(with: Data(body)) as? [String: Any], let name = j["name"] as? String else { send(400, ["error": "Bad request"]); return true }
        let args = (j["arguments"] as? [String: Any]) ?? [:]
        DispatchQueue.main.async { self.link.call(name, args) { out in self.send(200, out) } }
        return true
    }
    private func send(_ status: Int, _ o: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
        let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + body, completion: .contentProcessed { [c] _ in c.cancel() })
    }
}

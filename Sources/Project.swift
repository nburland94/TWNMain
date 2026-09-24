// Needed Tools — the project page (Round 5).
// One page for one job: its name, label and tags, dates, deliverables,
// to-dos, the documents made here or dropped in, the crew, and sending.
// Everything is kept in the project folder itself (Lexus/.needed/project.json
// and Lexus/Lexus_Docs), except the contact book, which is shared by every
// project and lives with the app. Nothing here goes online except email you send.

import AppKit
import WebKit
import PDFKit
import EventKit
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - The project's own file

/// Lexus/.needed/project.json — the same file that holds the label and tags.
enum ProjectFile {
    /// What the page may change. Label and tags go through Labels.
    static let editable: Set<String> = ["title", "client", "producer", "director", "idea",
                                        "deliverables", "musts", "dates", "todos", "crew"]

    static func url(_ project: String) -> URL? {
        Shared.vault?.appendingPathComponent(project, isDirectory: true).appendingPathComponent(".needed/project.json")
    }
    static func read(_ project: String) -> [String: Any] {
        guard let u = url(project), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }
    static func write(_ o: [String: Any], _ project: String) {
        guard let u = url(project) else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: u, options: .atomic) }
        Labels.forget()
    }
    /// Read, change, write — anything else in the file is kept.
    static func change(_ project: String, _ edit: (inout [String: Any]) -> Void) {
        var o = read(project)
        edit(&o)
        write(o, project)
    }
}

// MARK: - Documents: filed by what they are, versions kept

enum Docs {
    struct Kind { let name: String; let folder: String; let versioned: Bool }
    static let kinds: [Kind] = [
        Kind(name: "Brief", folder: "Briefs", versioned: true),
        Kind(name: "Treatment", folder: "Treatments", versioned: true),
        Kind(name: "Script", folder: "Scripts", versioned: true),
        Kind(name: "Mood board", folder: "Mood boards", versioned: true),
        Kind(name: "Deck", folder: "Decks", versioned: true),
        Kind(name: "Schedule", folder: "Schedules", versioned: true),
        Kind(name: "Call sheet", folder: "Call sheets", versioned: true),
        Kind(name: "Shot list", folder: "Shot lists", versioned: true),
        Kind(name: "Budget", folder: "Budgets", versioned: true),
        Kind(name: "Contract", folder: "Contracts", versioned: false),
        Kind(name: "Release", folder: "Releases", versioned: false),
        Kind(name: "Invoice", folder: "Invoices", versioned: false),
        Kind(name: "Other", folder: "Other", versioned: false),
    ]
    static func kind(_ name: String) -> Kind { kinds.first { $0.name == name } ?? kinds[kinds.count - 1] }

    /// What counts as a document in a project folder.
    static let docExt: Set<String> = ["pdf", "key", "pptx", "ppt", "docx", "doc", "pages", "xlsx", "xls", "numbers", "csv", "tsv",
                                      "txt", "rtf", "rtfd", "md", "fdx", "celtx", "zip", "odt", "ods", "odp"]
    /// Ones the page can read for dates and deliverables.
    static let readableExt: Set<String> = ["pdf", "txt", "md", "rtf", "rtfd", "docx", "doc", "odt"]

    /// Lexus/Lexus_Docs
    static func folder(_ project: String) -> URL? {
        Shared.vault?.appendingPathComponent(project, isDirectory: true).appendingPathComponent("\(project)_Docs", isDirectory: true)
    }

    /// What a file is, from its name: "LEXUS_RZ_TREATMENT_final2.pdf" → Treatment.
    static func guess(_ fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        var n = (fileName as NSString).deletingPathExtension.lowercased()
        for c in ["_", "-", ".", "(", ")", "[", "]"] { n = n.replacingOccurrences(of: c, with: " ") }
        n = " " + n.split(separator: " ").joined(separator: " ") + " "
        let has = { (words: [String]) -> Bool in words.contains { n.contains($0) } }
        if has(["call sheet", "callsheet"]) { return "Call sheet" }
        if has(["shot list", "shotlist", "storyboard"]) { return "Shot list" }
        if has(["treatment"]) { return "Treatment" }
        if has([" brief ", " briefing ", "creative brief"]) { return "Brief" }
        if has(["script", "screenplay"]) || ext == "fdx" || ext == "celtx" { return "Script" }
        if has(["mood", "moodboard"]) { return "Mood board" }
        if has(["schedule", "timeline", "production calendar", " schedul"]) { return "Schedule" }
        if has(["budget", " costs ", "estimate", " quote ", "cost report"]) { return "Budget" }
        if has(["contract", "agreement", " signed ", " nda ", " terms ", " sow ", " po "]) { return "Contract" }
        if has(["release", "consent"]) { return "Release" }
        if has(["invoice", "receipt"]) { return "Invoice" }
        if has([" deck ", "pitch", "presentation", "credentials"]) || ["key", "pptx", "ppt", "odp"].contains(ext) { return "Deck" }
        return "Other"
    }

    /// "Treatment v4.pdf", "Call sheet — Day 1 v2.pdf"; unversioned kinds keep their own name.
    static func name(for original: String, kind: Kind, in folder: URL) -> String {
        let ext = (original as NSString).pathExtension
        let dot = ext.isEmpty ? "" : "." + ext
        guard kind.versioned else {
            var stem = (original as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
            while stem.hasPrefix(".") { stem.removeFirst() }
            return (stem.isEmpty ? kind.name : stem) + dot
        }
        var base = kind.name
        if kind.name == "Call sheet", let day = firstMatch("day\\s*([0-9]{1,2})", in: original.lowercased()) { base += " — Day \(day)" }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var top = 0
        for f in names {
            let stem = (f as NSString).deletingPathExtension
            guard stem.lowercased().hasPrefix(base.lowercased() + " v"),
                  let n = Int(stem.dropFirst(base.count + 2)) else { continue }
            top = max(top, n)
        }
        return "\(base) v\(top + 1)\(dot)"
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }

    /// Which kind a file already in the project is, from where it sits.
    static func kindOf(rel: String, project: String) -> (kind: String, made: String) {
        let parts = rel.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return (guess(rel), "In the project") }
        let top = parts[1]
        if top == "\(project)_Docs", parts.count >= 4 {
            let f = parts[2]
            if let k = kinds.first(where: { $0.folder == f }) { return (k.name, "Filed here") }
            return (guess(parts.last ?? ""), "Filed here")
        }
        if top == "Invoices" { return ("Invoice", "Made in Pay") }
        if top == "Shots" { return ("Shot list", "Made in Shots") }
        if top == "Sheets" { return ("Contact sheet", "Made in the Vault") }
        if top == "\(project)_Vault", parts.count >= 3, parts[2] == "Mood" { return ("Mood board", "Made in the Vault") }
        if top == "\(project)_Design", parts.count >= 3 { return (parts[2] == "Mood" ? "Mood board" : "Treatment", "Made in Design") }
        return (guess(parts.last ?? ""), "In the project")
    }

    /// Every document in the project, newest first.
    static func list(_ project: String) -> [[String: Any]] {
        guard let base = Shared.vault else { return [] }
        let root = base.appendingPathComponent(project, isDirectory: true)
        let skip: Set<String> = ["\(project)_Grab", "Stills", "GIFs", "Motion", "Grabs", "References", "Sent", "Stills_Ref", "GIFs_Ref", "Motion_Ref"]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let meta = (ProjectFile.read(project)["docs"] as? [String: Any]) ?? [:]
        var out: [[String: Any]] = []
        let iso = ISO8601DateFormatter()
        while let u = walk.nextObject() as? URL {
            let v = try? u.resourceValues(forKeys: Set(keys))
            let isDir = v?.isDirectory == true && v?.isPackage != true
            if isDir {
                if skip.contains(u.lastPathComponent) { walk.skipDescendants() }
                continue
            }
            let ext = u.pathExtension.lowercased()
            guard docExt.contains(ext) else { continue }
            let rel = u.path.replacingOccurrences(of: base.path + "/", with: "")
            let (k, made) = kindOf(rel: rel, project: project)
            let m = (meta[rel] as? [String: Any]) ?? [:]
            let date = v?.contentModificationDate ?? Date()
            var item: [String: Any] = ["rel": rel, "name": u.deletingPathExtension().lastPathComponent, "ext": ext,
                                       "kind": k, "made": (m["from"] != nil ? "Dropped in" : made),
                                       "date": iso.string(from: date), "bytes": v?.fileSize ?? 0,
                                       "where": rel.split(separator: "/").dropFirst().dropLast().joined(separator: " › "),
                                       "readable": readableExt.contains(ext), "package": v?.isPackage == true]
            item["sent"] = (m["sent"] as? [[String: Any]]) ?? [[String: Any]]()
            item["read"] = (m["read"] as? Bool) ?? false
            out.append(item)
        }
        return out.sorted { ($0["date"] as? String ?? "") > ($1["date"] as? String ?? "") }
    }

    /// Dropped files go where they belong — copied, the originals stay put.
    /// Documents into Lexus_Docs by kind (with versions); pictures and films into
    /// Lexus_Vault as references, with their colours.
    static func file(_ urls: [URL], project: String, vault: VaultHost, done: @escaping ([String: Any]) -> Void) {
        guard let base = Shared.vault, let docs = folder(project) else { return done(["ok": false, "error": "Choose your vault first"]) }
        let fm = FileManager.default
        var rows: [[String: Any]] = []
        var pictures: [(from: URL, to: URL, kind: String)] = []  // copied away from the window — a film can take a while
        var planned = Set<String>()
        var skipped: [String] = []
        var failedDocs = 0
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            let ext = u.pathExtension.lowercased()
            let isPackage = (try? u.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
            if isDir.boolValue && !isPackage { skipped.append(u.lastPathComponent); continue }
            if Shell.imageExt.contains(ext) || Shell.filmExt.contains(ext) {
                let kind = ext == "gif" ? "gif" : Shell.filmExt.contains(ext) ? "clip" : "still"
                let sub = kind == "gif" ? "GIFs" : kind == "clip" ? "Motion" : "Stills"
                guard let f = vault.outputFolder(sub, project: project, area: "References") else { continue }
                // Two dropped files with the same name each get their own.
                var target = vault.uniqueURL(in: f, name: u.lastPathComponent)
                var n = 2
                while planned.contains(target.path) {
                    let stem = u.deletingPathExtension().lastPathComponent
                    target = vault.uniqueURL(in: f, name: ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"); n += 1
                }
                planned.insert(target.path)
                pictures.append((from: u, to: target, kind: kind))
                rows.append(["dropped": u.lastPathComponent, "kind": kind == "clip" ? "Reference film" : "Reference", "picture": true])
                continue
            }
            // Documents are copied one by one, so the next treatment sees this one and becomes the next v.
            let k = kind(guess(u.lastPathComponent))
            let dir = docs.appendingPathComponent(k.folder, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let target = vault.uniqueURL(in: dir, name: name(for: u.lastPathComponent, kind: k, in: dir))
            guard (try? fm.copyItem(at: u, to: target)) != nil else { failedDocs += 1; continue }
            rows.append(["dropped": u.lastPathComponent, "kind": k.name,
                         "rel": target.path.replacingOccurrences(of: base.path + "/", with: ""),
                         "where": "\(project)_Docs › \(k.folder) › \(target.lastPathComponent)",
                         "readable": readableExt.contains(ext) && ["Brief", "Treatment", "Schedule", "Script", "Call sheet"].contains(k.name)])
        }
        let at = ISO8601DateFormatter().string(from: Date())
        let filedRows = rows
        ProjectFile.change(project) { o in
            var meta = (o["docs"] as? [String: Any]) ?? [:]
            for r in filedRows {
                guard let rel = r["rel"] as? String else { continue }
                meta[rel] = ["from": (r["dropped"] as? String) ?? "", "at": at]
            }
            o["docs"] = meta
        }
        let jobs = pictures, skippedNames = skipped, docFails = failedDocs
        DispatchQueue.global(qos: .userInitiated).async {
            var failed = Set<String>()
            for j in jobs where (try? fm.copyItem(at: j.from, to: j.to)) == nil { failed.insert(j.to.path) }
            let failedPaths = failed
            DispatchQueue.main.async {
                var picRows = 0
                if !jobs.isEmpty {
                    VaultStore.shared.holdSaves = true
                    VaultStore.shared.load()
                    for j in jobs where !failedPaths.contains(j.to.path) {
                        let meta: [String: Any] = ["source": ["type": "file", "title": j.to.deletingPathExtension().lastPathComponent], "origin": "reference"]
                        VaultStore.shared.register(kind: j.kind, file: j.to, meta: meta, project: project)
                        picRows += 1
                    }
                    VaultStore.shared.holdSaves = false
                    if picRows > 0 { VaultStore.shared.save() }
                }
                // Pictures show as one line: "IMG_4471.HEIC, IMG_4472.HEIC + 22".
                var out = filedRows.filter { ($0["picture"] as? Bool) != true }
                let pics = filedRows.filter { ($0["picture"] as? Bool) == true }
                if !pics.isEmpty {
                    let names = pics.compactMap { $0["dropped"] as? String }
                    let shown = names.prefix(2).joined(separator: ", ") + (names.count > 2 ? " + \(names.count - 2)" : "")
                    let films = pics.filter { ($0["kind"] as? String) == "Reference film" }.count
                    if picRows > 0 {
                        out.append(["dropped": shown, "kind": films == pics.count ? "Reference films" : "References",
                                    "where": "\(project)_Vault · with colour palettes", "picture": true, "count": picRows])
                    }
                }
                done(["ok": true, "rows": out, "skipped": skippedNames, "failed": failedPaths.count + docFails])
            }
        }
    }

    /// A different kind: it moves to that folder and takes that kind's name.
    static func setKind(rel: String, to kindName: String, project: String) -> [String: Any] {
        guard let base = Shared.vault, let docs = folder(project), !rel.contains("..") else { return ["ok": false] }
        let from = base.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: from.path) else { return ["ok": false, "error": "That file has moved"] }
        let k = kind(kindName)
        let dir = docs.appendingPathComponent(k.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let meta = (ProjectFile.read(project)["docs"] as? [String: Any]) ?? [:]
        let original = ((meta[rel] as? [String: Any])?["from"] as? String) ?? from.lastPathComponent
        var target = dir.appendingPathComponent(name(for: original, kind: k, in: dir))
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            let stem = target.deletingPathExtension().lastPathComponent, ext = target.pathExtension
            target = dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"); n += 1
        }
        guard (try? FileManager.default.moveItem(at: from, to: target)) != nil else { return ["ok": false, "error": "Couldn't move it"] }
        let newRel = target.path.replacingOccurrences(of: base.path + "/", with: "")
        ProjectFile.change(project) { o in
            var m = (o["docs"] as? [String: Any]) ?? [:]
            m[newRel] = m.removeValue(forKey: rel) ?? ["from": original]
            o["docs"] = m
        }
        return ["ok": true, "rel": newRel, "name": target.deletingPathExtension().lastPathComponent]
    }
}

// MARK: - One contact book

/// Everyone, once: crew from Credit, clients from Pay, and anyone added on a
/// project page. Matched by email first, then by name. It lives with the app
/// (like Pay's books), so it's there whichever vault is plugged in.
enum Contacts {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("NeededTools/contacts.json")
    }
    static func load() -> [[String: Any]] {
        guard let d = try? Data(contentsOf: url), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return a
    }
    static func save(_ list: [[String: Any]]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: url, options: .atomic)
            VaultStore.backup(d, name: "contacts", into: url.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true))
        }
    }
    static func key(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
    static func emails(_ c: [String: Any]) -> [String] {
        var all = (c["emails"] as? [String]) ?? []
        if let e = c["email"] as? String, !e.isEmpty { all.insert(e, at: 0) }
        var seen = Set<String>()
        return all.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Where this person already is: same email, else same name.
    static func find(_ c: [String: Any], in list: [[String: Any]]) -> Int? {
        let mine = Set(emails(c).map { $0.lowercased() })
        if !mine.isEmpty, let i = list.firstIndex(where: { !Set(emails($0).map { $0.lowercased() }).isDisjoint(with: mine) }) { return i }
        let n = key((c["name"] as? String) ?? "")
        if !n.isEmpty, let i = list.firstIndex(where: { key(($0["name"] as? String) ?? "") == n }) { return i }
        return nil
    }

    /// Add or fill in. Fields someone typed are never blanked; new ones fill gaps.
    @discardableResult
    static func upsert(_ c: [String: Any], into list: inout [[String: Any]], overwrite: Bool = false) -> [String: Any] {
        var incoming = c
        let em = emails(c)
        incoming["email"] = em.first ?? ""
        incoming["emails"] = Array(em.dropFirst())
        if let i = find(incoming, in: list) {
            var p = list[i]
            for f in ["name", "role", "handle", "company", "phone"] {
                let v = ((incoming[f] as? String) ?? "").trimmingCharacters(in: .whitespaces)
                if !v.isEmpty && (overwrite || ((p[f] as? String) ?? "").isEmpty) { p[f] = v }
            }
            let all = emails(p) + em
            var seen = Set<String>()
            let merged = all.filter { seen.insert($0.lowercased()).inserted }
            p["email"] = merged.first ?? ""
            p["emails"] = Array(merged.dropFirst())
            var from = Set((p["from"] as? [String]) ?? [])
            for s in (incoming["from"] as? [String]) ?? [] { from.insert(s) }
            p["from"] = from.sorted()
            list[i] = p
            return p
        }
        var p: [String: Any] = ["id": (c["id"] as? String) ?? UUID().uuidString]
        for f in ["name", "role", "handle", "company", "phone", "email"] { p[f] = ((incoming[f] as? String) ?? "").trimmingCharacters(in: .whitespaces) }
        p["emails"] = incoming["emails"]
        p["from"] = (incoming["from"] as? [String]) ?? ["project"]
        list.append(p)
        return p
    }

    /// The book, with any client Pay knows that it doesn't yet.
    static func all() -> [[String: Any]] {
        var list = load()
        let before = list.count
        let ledgerURL = Mailer.payDir.appendingPathComponent("ledger.json")
        if let d = try? Data(contentsOf: ledgerURL), let l = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for c in (l["clients"] as? [[String: Any]]) ?? [] {
                let company = (c["name"] as? String) ?? ""
                let person = (c["contact"] as? String) ?? ""
                let email = (c["email"] as? String) ?? ""
                guard !email.isEmpty, find(["email": email], in: list) == nil else { continue }
                upsert(["name": person.isEmpty ? company : person, "company": company, "email": email, "role": "Client", "from": ["pay"]], into: &list)
            }
        }
        if list.count != before { save(list) }
        return list.sorted { key(($0["name"] as? String) ?? "") < key(($1["name"] as? String) ?? "") }
    }

    /// Credit's crew memory, as it saves: { key: {name, handle, emails, role} }.
    static func fromCredit(_ cache: [String: Any]) {
        var list = load()
        for case let p as [String: Any] in cache.values {
            let name = (p["name"] as? String) ?? ""
            let handle = (p["handle"] as? String) ?? ""
            let em = (p["emails"] as? [String]) ?? []
            guard !name.isEmpty || !em.isEmpty else { continue }
            var c: [String: Any] = ["name": name, "handle": handle, "role": (p["role"] as? String) ?? "", "from": ["credit"]]
            c["email"] = em.first ?? ""
            c["emails"] = Array(em.dropFirst())
            // Credit's handle is the newest one known; nothing else is overwritten.
            if let i = find(c, in: list), !handle.isEmpty { list[i]["handle"] = handle }
            upsert(c, into: &list)
        }
        save(list)
    }

    static func edit(_ c: [String: Any]) -> [String: Any] {
        var list = load()
        guard let id = c["id"] as? String, let i = list.firstIndex(where: { ($0["id"] as? String) == id }) else {
            let p = upsert(c, into: &list); save(list); return p
        }
        for f in ["name", "role", "handle", "company", "phone", "email"] { if let v = c[f] as? String { list[i][f] = v.trimmingCharacters(in: .whitespaces) } }
        save(list)
        return list[i]
    }

    /// Two entries that are the same person: one stays, with everything from both.
    static func merge(keep: String, drop: String) {
        var list = load()
        guard let k = list.firstIndex(where: { ($0["id"] as? String) == keep }),
              let d = list.firstIndex(where: { ($0["id"] as? String) == drop }), k != d else { return }
        let gone = list[d]
        var p = list[k]
        for f in ["name", "role", "handle", "company", "phone"] where ((p[f] as? String) ?? "").isEmpty { p[f] = gone[f] ?? "" }
        var seen = Set<String>()
        let all = (emails(p) + emails(gone)).filter { seen.insert($0.lowercased()).inserted }
        p["email"] = all.first ?? ""
        p["emails"] = Array(all.dropFirst())
        p["from"] = Array(Set(((p["from"] as? [String]) ?? []) + ((gone["from"] as? [String]) ?? []))).sorted()
        list[k] = p
        list.remove(at: d)
        save(list)
    }

    static func remove(_ id: String) {
        var list = load()
        list.removeAll { ($0["id"] as? String) == id }
        save(list)
    }
}

// MARK: - Sending: the same account Pay sends invoices from

enum Mailer {
    static var payDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("NeededPay", isDirectory: true)
    }

    /// Pay's mail settings: who it's from and the server. Nil until they're set up in Pay.
    static func account() -> (from: String, name: String, host: String, port: Int)? {
        guard let d = try? Data(contentsOf: payDir.appendingPathComponent("ledger.json")),
              let l = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let m = l["mail"] as? [String: Any] else { return nil }
        let from = ((m["from"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty else { return nil }
        let providers: [String: (String, Int)] = ["gmail": ("smtp.gmail.com", 465), "outlook": ("smtp.office365.com", 587), "icloud": ("smtp.mail.me.com", 587)]
        let provider = (m["provider"] as? String) ?? "gmail"
        var host = "", port = 465
        if provider == "other" { host = (m["host"] as? String) ?? ""; port = (m["port"] as? NSNumber)?.intValue ?? 465 }
        else if let p = providers[provider] { host = p.0; port = p.1 }
        let name = ((l["me"] as? [String: Any])?["name"] as? String) ?? ""
        return host.isEmpty ? nil : (from, name, host, port)
    }

    static let limit: Int64 = 24 * 1024 * 1024                     // most mail servers stop at 25 MB

    /// One email to everyone picked: To and CC in the message, BCC only on the envelope.
    static func send(to: [[String: Any]], cc: [[String: Any]], bcc: [[String: Any]], subject: String, body: String,
                     files: [URL], copy: Bool, keepIn: URL?, done: @escaping ([String: Any]) -> Void) {
        guard let acct = account() else { return done(["ok": false, "error": "Connect your email in Pay › Settings first — sending uses the same account.", "setup": true]) }
        guard let pw = PayKeychain.read(acct.from) else { return done(["ok": false, "error": "Add your app password in Pay › Settings.", "setup": true]) }
        let valid = { (p: [String: Any]) -> Bool in ((p["email"] as? String) ?? "").range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", options: .regularExpression) != nil }
        let everyone = to + cc + bcc
        guard !to.isEmpty || !cc.isEmpty || !bcc.isEmpty else { return done(["ok": false, "error": "Pick someone to send to"]) }
        if let bad = everyone.first(where: { !valid($0) }) { return done(["ok": false, "error": "\((bad["name"] as? String) ?? "Someone") has no email address yet"]) }
        var total: Int64 = 0
        for f in files {
            let v = try? f.resourceValues(forKeys: [.isPackageKey, .fileSizeKey])
            if v?.isPackage == true { return done(["ok": false, "error": "\(f.lastPathComponent) is a package — export it as a PDF to email it."]) }
            total += Int64(v?.fileSize ?? 0)
        }
        if total > limit { return done(["ok": false, "error": "That's \(total / 1_048_576) MB — too big for email. Send fewer, or share a link from your own storage."]) }

        let enc = { (s: String) -> String in s.allSatisfy { $0.isASCII } ? s : "=?UTF-8?B?" + Data(s.utf8).base64EncodedString() + "?=" }
        let addr = { (p: [String: Any]) -> String in
            let n = ((p["name"] as? String) ?? "").replacingOccurrences(of: "\"", with: "")
            let e = (p["email"] as? String) ?? ""
            return n.isEmpty || n == e ? e : "\"\(enc(n))\" <\(e)>"
        }
        let boundary = "needed-\(UUID().uuidString)"
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        var m = "From: \(acct.name.isEmpty ? acct.from : "\"\(enc(acct.name))\" <\(acct.from)>")\r\n"
        if !to.isEmpty { m += "To: \(to.map(addr).joined(separator: ", "))\r\n" }
        if !cc.isEmpty { m += "Cc: \(cc.map(addr).joined(separator: ", "))\r\n" }
        m += "Subject: \(enc(subject))\r\nDate: \(f.string(from: Date()))\r\n"
        m += "Message-ID: <\(UUID().uuidString)@neededtools>\r\nMIME-Version: 1.0\r\n"
        m += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n"
        m += "--\(boundary)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
        m += Data(body.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]) + "\r\n"
        for a in files {
            guard let data = try? Data(contentsOf: a) else { return done(["ok": false, "error": "Couldn't read \(a.lastPathComponent)"]) }
            let file = a.lastPathComponent.replacingOccurrences(of: "\"", with: "")
            let type = UTType(filenameExtension: a.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            m += "--\(boundary)\r\nContent-Type: \(type); name=\"\(enc(file))\"\r\nContent-Disposition: attachment; filename=\"\(enc(file))\"\r\n"
            m += "Content-Transfer-Encoding: base64\r\n\r\n"
            m += data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]) + "\r\n"
        }
        m += "--\(boundary)--\r\n"
        let eml = FileManager.default.temporaryDirectory.appendingPathComponent("needed-send-\(UUID().uuidString).eml")
        guard (try? m.data(using: .utf8)?.write(to: eml)) != nil else { return done(["ok": false, "error": "Couldn't write the email"]) }

        let url = (acct.port == 465 ? "smtps://" : "smtp://") + "\(acct.host):\(acct.port)"
        var args = ["--silent", "--show-error", "--url", url, "--ssl-reqd", "--max-time", "180", "--mail-from", acct.from]
        var seen = Set<String>()
        for p in everyone { let e = (p["email"] as? String) ?? ""; if seen.insert(e.lowercased()).inserted { args += ["--mail-rcpt", e] } }
        if copy && !seen.contains(acct.from.lowercased()) { args += ["--mail-rcpt", acct.from] }
        args += ["--upload-file", eml.path, "--config", "-"]
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = args
        let input = Pipe(), errPipe = Pipe()
        proc.standardInput = input; proc.standardError = errPipe; proc.standardOutput = Pipe()
        let quoted = "\(acct.from):\(pw)".replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? FileManager.default.removeItem(at: eml) }
            do { try proc.run() } catch { return DispatchQueue.main.async { done(["ok": false, "error": "Couldn't start sending"]) } }
            input.fileHandleForWriting.write(Data("user = \"\(quoted)\"\n".utf8))
            try? input.fileHandleForWriting.close()
            proc.waitUntilExit()
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let code = proc.terminationStatus
            let why: String
            switch code {
            case 0: why = ""
            case 67: why = "The password wasn't accepted. Use an app password — set it in Pay › Settings."
            case 6, 7: why = "Couldn't reach the mail server. Check your connection."
            case 28: why = "The mail server took too long. Try again."
            case 35, 60: why = "Couldn't make a secure connection to the mail server."
            case 55, 56: why = "The connection dropped while sending. Try again."
            default: why = err.isEmpty ? "Sending didn't work (\(code))." : err.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var savedPath = ""
            if code == 0, let dir = keepIn {                       // a copy of what went, in the project's Sent folder
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let s = DateFormatter(); s.dateFormat = "yyyy-MM-dd HHmm"
                var subj = subject.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                if subj.count > 60 { subj = String(subj.prefix(60)) }
                let target = dir.appendingPathComponent("\(s.string(from: Date())) — \(subj.isEmpty ? "No subject" : subj).eml")
                if (try? FileManager.default.copyItem(at: eml, to: target)) != nil { savedPath = target.path }
            }
            let result: [String: Any] = code == 0 ? ["ok": true, "saved": savedPath] : ["ok": false, "error": why]
            DispatchQueue.main.async { done(result) }
        }
    }
}

// MARK: - Reading a brief, on this Mac

/// Rules first — they work on every Mac. Where macOS has Apple's on-device
/// model (Apple Intelligence), it reads too, and its answer is used when it
/// finds more. Either way the file never leaves the Mac.
enum BriefReader {
    static func text(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return PDFDocument(url: url)?.string ?? "" }
        if ["txt", "md", "csv", "tsv"].contains(ext) {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
        }
        if let a = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) { return a.string }
        return ""
    }

    // Section headings a brief tends to use.
    static let headings: [(String, [String])] = [
        ("deliverables", ["deliverables", "deliverable", "outputs", "assets", "asset list", "what we need", "media", "channels", "formats"]),
        ("idea", ["objective", "objectives", "the idea", "idea", "proposition", "concept", "key message", "creative idea", "the ask", "single minded proposition", "creative"]),
        ("musts", ["mandatories", "mandatory", "musts", "must haves", "must-haves", "requirements", "legal", "restrictions", "do's and don'ts", "dos and don'ts", "considerations", "guidelines"]),
        ("dates", ["timings", "timing", "timeline", "schedule", "key dates", "dates", "deadlines"]),
        ("client", ["client", "brand", "advertiser"]),
        ("title", ["project", "title", "campaign", "job", "project name"]),
        ("other", ["background", "audience", "target audience", "tone", "tone of voice", "budget", "insight", "context", "references", "contacts", "approvals"]),
    ]

    static func heading(_ line: String) -> (String, String)? {
        let lower = line.lowercased()
        var head = lower, rest = ""
        if let c = line.firstIndex(of: ":") {
            head = String(lower[..<c]).trimmingCharacters(in: .whitespaces)
            rest = String(line[line.index(after: c)...]).trimmingCharacters(in: .whitespaces)
        } else if line.count > 40 { return nil }
        head = head.trimmingCharacters(in: CharacterSet(charactersIn: " .#*•-–—0123456789"))
        guard head.split(separator: " ").count <= 4 else { return nil }
        for (section, words) in headings where words.contains(head) { return (section, rest) }
        return nil
    }

    static func matches(_ pattern: String, _ s: String) -> [NSTextCheckingResult] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }
    static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String {
        guard m.numberOfRanges > i, let r = Range(m.range(at: i), in: s) else { return "" }
        return String(s[r])
    }

    static let noun = "\\b(hero films?|films?|cuts?|cut-?downs?|edits?|spots?|tvcs?|commercials?|ads?|bumpers?|teasers?|trailers?|socials?|stor(?:y|ies)|reels?|stills?|photos?|photography|images?|gifs?|posters?|banners?|mood ?boards?|treatments?|decks?|bts|behind the scenes|music videos?|videos?|cinemagraphs?|key visuals?|ooh|print|lifts?|versions?)\\b"
    static let lengthRe = "(\\d{1,3})\\s*(?:\"|”|″|''|s\\b|sec\\b|secs\\b|seconds?\\b)"
    static let aspectRe = "(16:9|9:16|1:1|4:5|5:4|4:3|3:4|2:1|21:9|2\\.39(?::1)?|2\\.35(?::1)?|1\\.85(?::1)?)"
    static let countRe = "(?:^|\\s)(\\d{1,3})\\s*[x×]\\s*|[x×]\\s*(\\d{1,3})\\b|^(\\d{1,3})\\s+(?=[a-z])"

    /// One line of a deliverables list → {text, shape, len}, or nil if it isn't one.
    static func deliverable(_ chunk: String, inSection: Bool) -> [String: Any]? {
        let c = chunk.trimmingCharacters(in: CharacterSet(charactersIn: " .•*-–—\t"))
        guard c.count >= 3, c.count <= 140 else { return nil }
        let hasNoun = !matches(noun, c).isEmpty
        let len = matches(lengthRe, c).first.map { group($0, 1, c) } ?? ""
        let aspect = matches(aspectRe, c).first.map { group($0, 1, c) } ?? ""
        var count = 0
        if let m = matches(countRe, c).first {
            count = Int(group(m, 1, c)) ?? Int(group(m, 2, c)) ?? Int(group(m, 3, c)) ?? 0
        }
        guard hasNoun && (inSection || !len.isEmpty || !aspect.isEmpty || count > 0) else { return nil }
        // The words, without the numbers: "1 × 60" hero film (16:9)" → "Hero film".
        var t = c
        for p in [countRe, lengthRe, "\\(?\\s*" + aspectRe + "\\s*\\)?", "\\(\\s*\\)", "^\\s*of\\s+"] {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: " ")
            }
        }
        t = t.split(separator: " ").joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-–—"))
        guard !t.isEmpty else { return nil }
        t = t.prefix(1).uppercased() + t.dropFirst()
        if t.count > 48 { t = String(t.prefix(46)) + "…" }
        if count > 1 { t += " × \(count)" }
        var shape = aspect.contains(".") && aspect.hasSuffix(":1") ? String(aspect.dropLast(2)) : aspect      // 2.39:1 → 2.39
        if shape.isEmpty, !matches("mood ?boards?|treatments?|decks?", c).isEmpty { shape = "PDF" }
        return ["text": t, "shape": shape, "len": len.isEmpty ? "" : "\(len)s"]
    }

    static let dateWords: [(String, String)] = [
        ("pre-production meeting", "PPM"), ("pre production meeting", "PPM"), ("ppm", "PPM"), ("tech recce", "Recce"), ("recce", "Recce"),
        ("casting", "Casting"), ("callback", "Casting"), ("principal photography", "Shoot"), ("shoot", "Shoot"), ("filming", "Shoot"),
        ("first cut", "First cut"), ("rough cut", "Rough cut"), ("fine cut", "Fine cut"), ("offline", "Offline"), ("online", "Online"),
        ("grade", "Grade"), ("final delivery", "Final delivery"), ("delivery", "Delivery"), ("deliver", "Delivery"), ("launch", "Launch"),
        ("on air", "On air"), ("air date", "On air"), ("go live", "Launch"), ("treatment", "Treatment due"), ("pitch", "Pitch"),
        ("deadline", "Deadline"), ("wrap", "Wrap"), ("edit", "Edit"), ("approval", "Approval"), ("sign off", "Sign-off"), ("sign-off", "Sign-off"),
    ]

    static func label(before prefix: String) -> String? {
        let p = prefix.lowercased()
        var best: (Int, String)? = nil
        for (w, name) in dateWords {
            if let r = p.range(of: w, options: .backwards) {
                let at = p.distance(from: p.startIndex, to: r.lowerBound)
                if best == nil || at > best!.0 { best = (at, name) }
            }
        }
        return best?.1
    }

    static let day: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()

    /// The rules: sections, deliverables, dates, must-haves, the idea.
    static func read(_ raw: String, fileName: String = "") -> [String: Any] {
        let text = raw.replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{2028}", with: "\n")
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var section = ""
        var title = "", client = "", idea = ""
        var deliverables: [[String: Any]] = [], musts: [String] = []
        var seen = Set<String>()
        var ideaLines: [String] = []
        for (i, line) in lines.enumerated() {
            var body = line
            if let h = heading(line) {
                section = h.0
                if h.1.isEmpty { continue }
                body = h.1
            } else if i == 0, line.count <= 90 { title = line; continue }
            switch section {
            case "client": if client.isEmpty { client = String(body.prefix(60)) }; section = ""
            case "title": if title.isEmpty || i < 4 { title = String(body.prefix(90)) }; section = ""
            case "idea": ideaLines.append(body)
            case "musts":
                for s in body.components(separatedBy: CharacterSet(charactersIn: ".;•")) {
                    let t = s.trimmingCharacters(in: CharacterSet(charactersIn: " -–—*"))
                    if t.count >= 8, t.count <= 160, musts.count < 8, seen.insert(t.lowercased()).inserted { musts.append(t) }
                }
            default: break
            }
            // Deliverables: anywhere, but a Deliverables section takes looser lines.
            let parts: [String] = body.components(separatedBy: CharacterSet(charactersIn: ",;•"))
                .flatMap { $0.components(separatedBy: " · ") }.flatMap { $0.components(separatedBy: ". ") }
            var last: Int? = nil
            for part in parts {
                guard let d = deliverable(part, inSection: section == "deliverables") else {
                    // A lone shape — "12 stills, 4:5" — belongs to the one before it.
                    let bare = part.trimmingCharacters(in: CharacterSet(charactersIn: " .()"))
                    if let i = last, !matches("^" + aspectRe + "$", bare).isEmpty, ((deliverables[i]["shape"] as? String) ?? "").isEmpty { deliverables[i]["shape"] = bare }
                    continue
                }
                let k = (d["text"] as? String ?? "").lowercased() + (d["shape"] as? String ?? "") + (d["len"] as? String ?? "")
                if seen.insert(k).inserted && deliverables.count < 20 { deliverables.append(d); last = deliverables.count - 1 }
            }
        }
        // The idea: a quoted line, else the Objective / Idea section.
        let flat = lines.joined(separator: " ")
        for m in matches("[“\"]([^”\"]{20,180})[”\"]", flat) { idea = group(m, 1, flat); break }
        if idea.isEmpty, !ideaLines.isEmpty { idea = String(ideaLines.joined(separator: " ").prefix(220)) }
        // Must-haves outside their section: sentences that say must / never / no …
        let sentences = flat.components(separatedBy: CharacterSet(charactersIn: ".!?")).map { $0.trimmingCharacters(in: .whitespaces) }
        for s in sentences where musts.count < 6 && s.count >= 12 && s.count <= 160 {
            if !matches("\\b(must|mandatory|required|do not|don't|never|legal line|no (vehicle|car|speed|alcohol|competitor|children|smoking|driving|swearing))\\b", s).isEmpty,
               seen.insert(s.lowercased()).inserted { musts.append(s) }
        }
        // Dates: whatever macOS recognises as a date, named by the word before it.
        var dates: [[String: Any]] = []
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        for s in sentences + lines where s.count <= 240 {
            let found = detector?.matches(in: s, range: NSRange(s.startIndex..., in: s)) ?? []
            var from = s.startIndex
            for m in found {
                guard let d = m.date, let r = Range(m.range, in: s) else { continue }
                let name = label(before: String(s[from..<r.lowerBound])) ?? label(before: s) ?? ""
                from = r.upperBound
                guard !name.isEmpty else { continue }
                let iso = day.string(from: d)
                if seen.insert(name + iso).inserted && dates.count < 12 { dates.append(["text": name, "date": iso]) }
            }
        }
        dates.sort { ($0["date"] as? String ?? "") < ($1["date"] as? String ?? "") }
        if title.isEmpty { title = (fileName as NSString).deletingPathExtension }
        let mentionsMood = !matches("mood ?board", flat).isEmpty
        return ["title": title, "client": client, "idea": idea, "deliverables": deliverables, "musts": musts, "dates": dates,
                "todos": suggest(deliverables: deliverables, dates: dates, musts: musts, mood: mentionsMood), "how": "rules"]
    }

    /// To-dos that follow from what the brief asks for.
    static func suggest(deliverables: [[String: Any]], dates: [[String: Any]], musts: [String], mood: Bool) -> [[String: Any]] {
        let find = { (words: [String]) -> Date? in
            for d in dates {
                let t = ((d["text"] as? String) ?? "").lowercased()
                if words.contains(where: { t.contains($0) }), let s = d["date"] as? String, let v = day.date(from: s) { return v }
            }
            return nil
        }
        let shoot = find(["shoot"]), ppm = find(["ppm"]), delivery = find(["final delivery", "delivery"])
        let before = { (d: Date?, n: Int) -> String in
            guard let d = d, let v = Calendar.current.date(byAdding: .day, value: -n, to: d) else { return "" }
            return day.string(from: v)
        }
        var out: [[String: Any]] = []
        let hasMoodDeliverable = deliverables.contains { ((($0["text"] as? String) ?? "").lowercased()).contains("mood") }
        if mood || hasMoodDeliverable { out.append(["text": "Mood board to the client", "why": ppm != nil ? "Due before the PPM" : "The brief asks for one", "due": before(ppm, 1)]) }
        var ratios: [String] = []
        for d in deliverables { let s = (d["shape"] as? String) ?? ""; if ["9:16", "4:5", "1:1"].contains(s) && !ratios.contains(s) { ratios.append(s) } }
        if !ratios.isEmpty {
            out.append(["text": "Plan \(ratios.joined(separator: " and ")) framing", "why": "Not everything is 16:9 — frame for it on the day", "due": before(shoot, 3)])
        }
        if shoot != nil {
            out.append(["text": "Book the crew", "why": "The shoot is set", "due": before(shoot, 10)])
            out.append(["text": "Call sheet out, 48 hours before", "why": "Before the shoot", "due": before(shoot, 2)])
        }
        for m in musts.prefix(3) {
            var t = m; if t.count > 70 { t = String(t.prefix(68)) + "…" }
            out.append(["text": "Check: \(t)", "why": "A must-have from the brief", "due": before(delivery, 3)])
        }
        if delivery != nil { out.append(["text": "Check every deliverable against the brief", "why": "Before final delivery", "due": before(delivery, 2)]) }
        return out
    }

    /// Reads a file: rules straight away; the on-device model too where there is one.
    static func read(url: URL, done: @escaping ([String: Any]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = BriefReader.text(of: url)
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else {
                return DispatchQueue.main.async { done(["ok": false, "error": "There's no text in that file to read — is it a scan?"]) }
            }
            var found = read(text, fileName: url.lastPathComponent)
            found["ok"] = true
            found["words"] = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
            let rules = found
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                SmartReader.read(text) { smart in
                    guard var s = smart else { return done(rules) }
                    // Keep whichever found more, field by field.
                    for k in ["deliverables", "dates", "musts"] {
                        let a = (s[k] as? [Any]) ?? [], b = (rules[k] as? [Any]) ?? []
                        if b.count > a.count { s[k] = rules[k] }
                    }
                    for k in ["title", "client", "idea"] where ((s[k] as? String) ?? "").isEmpty { s[k] = rules[k] }
                    s["todos"] = suggest(deliverables: (s["deliverables"] as? [[String: Any]]) ?? [], dates: (s["dates"] as? [[String: Any]]) ?? [],
                                         musts: (s["musts"] as? [String]) ?? [], mood: text.lowercased().contains("mood"))
                    s["ok"] = true; s["how"] = "apple"; s["words"] = rules["words"]
                    done(s)
                }
                return
            }
            #endif
            DispatchQueue.main.async { done(rules) }
        }
    }
}

#if canImport(FoundationModels)
/// Apple's on-device model (macOS 26 with Apple Intelligence on). Private: it runs on the Mac.
@available(macOS 26.0, *)
enum SmartReader {
    static func read(_ text: String, done: @escaping ([String: Any]?) -> Void) {
        guard SystemLanguageModel.default.isAvailable else { return DispatchQueue.main.async { done(nil) } }
        let today = BriefReader.day.string(from: Date())
        let brief = String(text.prefix(9000))
        Task {
            var result: [String: Any]? = nil
            do {
                let session = LanguageModelSession(instructions: "You read production briefs for a film director. Reply with JSON only, no prose.")
                let prompt = """
                Today is \(today). From the brief below, return exactly this JSON shape:
                {"title":"","client":"","idea":"one line, in the brief's words","deliverables":[{"text":"Hero film","shape":"16:9","len":"60s"}],"dates":[{"text":"Shoot","date":"YYYY-MM-DD"}],"musts":["must-have rules"]}
                Leave a field empty if the brief doesn't say. Use short names for deliverables and dates.

                BRIEF:
                \(brief)
                """
                let response = try await session.respond(to: prompt)
                let s = response.content
                if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}"), a < b,
                   let obj = try? JSONSerialization.jsonObject(with: Data(String(s[a...b]).utf8)) as? [String: Any] {
                    result = obj
                }
            } catch { result = nil }
            let out = result
            DispatchQueue.main.async { done(out) }
        }
    }
}
#endif

// MARK: - The page talks to the app here

extension Shell {
    /// The project page's actions. Returns false for anything that isn't one.
    func projectAction(_ action: String, _ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) -> Bool {
        let project = Shared.project
        switch action {
        case "projectData":
            reply(projectData(project), nil)

        case "projectSave":
            // One field at a time: the title, the dates, the to-dos…
            guard Shared.vault != nil else { reply(["ok": false, "error": "Choose your vault first"], nil); return true }
            let key = (body["key"] as? String) ?? ""
            guard ProjectFile.editable.contains(key) else { reply(["ok": false], nil); return true }
            ProjectFile.change(project) { o in
                if let v = body["value"], !(v is NSNull) { o[key] = v } else { o.removeValue(forKey: key) }
            }
            reply(["ok": true], nil)

        case "projectApply":
            // What the brief asked for, the parts you ticked, added to the project.
            let add = (body["add"] as? [String: Any]) ?? [:]
            ProjectFile.change(project) { o in
                for k in ["title", "client", "idea"] {
                    if let v = add[k] as? String, !v.isEmpty, ((o[k] as? String) ?? "").isEmpty || k == "idea" { o[k] = v }
                }
                for k in ["deliverables", "dates", "todos"] {
                    var list = (o[k] as? [[String: Any]]) ?? []
                    for var x in (add[k] as? [[String: Any]]) ?? [] {
                        if x["id"] == nil { x["id"] = UUID().uuidString }
                        let t = ((x["text"] as? String) ?? "").lowercased()
                        if !list.contains(where: { (($0["text"] as? String) ?? "").lowercased() == t && ($0["date"] as? String) == (x["date"] as? String) }) { list.append(x) }
                    }
                    o[k] = list
                }
                var musts = (o["musts"] as? [String]) ?? []
                for m in (add["musts"] as? [String]) ?? [] where !musts.contains(m) { musts.append(m) }
                o["musts"] = musts
                if let rel = body["rel"] as? String {
                    var docs = (o["docs"] as? [String: Any]) ?? [:]
                    var m = (docs[rel] as? [String: Any]) ?? [:]
                    m["read"] = true
                    docs[rel] = m
                    o["docs"] = docs
                }
            }
            reply(projectData(project), nil)

        case "projectRead":
            guard let base = Shared.vault, let rel = body["rel"] as? String, !rel.contains("..") else { reply(["ok": false], nil); return true }
            BriefReader.read(url: base.appendingPathComponent(rel)) { r in reply(r, nil) }

        case "projectFiles":
            // Add files…: chosen here, filed the same way as a drop.
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.message = "Choose anything for \(project) — it's copied in and filed by what it is"
            panel.prompt = "Add to \(project)"
            panel.beginSheetModal(for: window) { r in
                guard r == .OK else { return reply(["ok": false, "cancelled": true], nil) }
                Docs.file(panel.urls, project: project, vault: self.vaultHost) { res in reply(res, nil); self.filedDone(res, project) }
            }

        case "projectSetKind":
            reply(Docs.setKind(rel: (body["rel"] as? String) ?? "", to: (body["kind"] as? String) ?? "Other", project: project), nil)

        case "projectOpen", "projectReveal":
            if let base = Shared.vault, let rel = body["rel"] as? String, !rel.contains("..") {
                let u = base.appendingPathComponent(rel)
                if action == "projectOpen" { NSWorkspace.shared.open(u) } else { NSWorkspace.shared.activateFileViewerSelecting([u]) }
            } else if action == "projectReveal", let base = Shared.vault {
                NSWorkspace.shared.open(base.appendingPathComponent(project, isDirectory: true))
            }
            reply(["ok": true], nil)

        case "projectCalendar":
            projectCalendar(project, reply)

        case "contacts":
            reply(["contacts": Contacts.all()], nil)

        case "contactSave":
            let c = Contacts.edit((body["contact"] as? [String: Any]) ?? [:])
            reply(["ok": true, "contact": c, "contacts": Contacts.all()], nil)

        case "contactMerge":
            Contacts.merge(keep: (body["keep"] as? String) ?? "", drop: (body["drop"] as? String) ?? "")
            reply(["ok": true, "contacts": Contacts.all()], nil)

        case "contactRemove":
            Contacts.remove((body["id"] as? String) ?? "")
            reply(["ok": true, "contacts": Contacts.all()], nil)

        case "creditContacts":
            // Credit saves its crew memory: the book hears about it.
            Contacts.fromCredit((body["cache"] as? [String: Any]) ?? [:])
            reply(["ok": true], nil)

        case "projectDraft":
            // Drafts are kept with the project until they're sent or thrown away.
            let draft = (body["draft"] as? [String: Any]) ?? [:]
            let drop = body["remove"] as? String
            ProjectFile.change(project) { o in
                var list = (o["drafts"] as? [[String: Any]]) ?? []
                if let id = drop { list.removeAll { ($0["id"] as? String) == id } }
                else if let id = draft["id"] as? String {
                    var d = draft; d["at"] = ISO8601DateFormatter().string(from: Date())
                    if let i = list.firstIndex(where: { ($0["id"] as? String) == id }) { list[i] = d } else { list.insert(d, at: 0) }
                }
                o["drafts"] = list
            }
            reply(["ok": true, "drafts": (ProjectFile.read(project)["drafts"] as? [[String: Any]]) ?? []], nil)

        case "projectSend":
            projectSend(project, body, reply)

        case "projectMakeCredits":
            // The crew goes to Credit with every name, role and handle already in.
            let rows = (body["crew"] as? [[String: Any]]) ?? []
            show("credit")
            if let v = host("credit")?.webView, let d = try? JSONSerialization.data(withJSONObject: rows), let json = String(data: d, encoding: .utf8) {
                whenReady(v, "__neededMakeCredits", "window.__neededMakeCredits(\(json), \(Shell.js(project)))")
            }
            reply(["ok": true], nil)

        case "projectMood":
            // Make a mood board: the Vault's Mood tab, for now (Needed Design takes this over).
            show("vault")
            whenReady(vaultHost.webView, "__neededQuick", "window.__neededQuick('mood')")
            reply(["ok": true], nil)

        case "projectTool":
            let id = (body["id"] as? String) ?? "home"
            show(id)
            reply(["ok": true], nil)

        default:
            return false
        }
        return true
    }

    /// Everything the page shows, in one go.
    func projectData(_ project: String) -> [String: Any] {
        guard Shared.vault != nil else { return ["vault": false, "project": project] }
        var o = ProjectFile.read(project)
        o.removeValue(forKey: "docs")
        var out: [String: Any] = o
        out["vault"] = true
        out["project"] = project
        out["label"] = Labels.of(project)
        out["tags"] = Labels.tags(of: project)
        out["labels"] = Labels.names()
        out["docs"] = Docs.list(project)
        out["kinds"] = Docs.kinds.map { $0.name }
        out["mood"] = projectMood(project)
        out["contacts"] = Contacts.all()
        if let a = Mailer.account() { out["mail"] = ["from": a.from, "name": a.name, "ready": PayKeychain.read(a.from) != nil] }
        else { out["mail"] = ["ready": false] }
        out["today"] = BriefReader.day.string(from: Date())
        return out
    }

    /// The project's references and grabs, a few to show, and the colours they share.
    func projectMood(_ project: String) -> [String: Any] {
        VaultStore.shared.load()
        let mine = VaultStore.shared.items.filter { (it: [String: Any]) -> Bool in
            let k = (it["kind"] as? String) ?? ""
            return (it["project"] as? String ?? "Unsorted") == project && (k == "still" || k == "gif" || k == "clip")
        }
        var refs = 0, grabs = 0
        var buckets: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for it in mine {
            let rel = (it["file"] as? String) ?? ""
            let origin: String = Folders.origin(ofFile: rel) ?? (it["origin"] as? String) ?? "reference"
            if origin == "grab" { grabs += 1 } else { refs += 1 }
            for hex in (it["palette"] as? [String]) ?? [] {
                let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
                guard h.count == 6, let n = Int(h, radix: 16) else { continue }
                let r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255
                let key = (r / 40) * 100 + (g / 40) * 10 + (b / 40)
                let old: (n: Int, r: Int, g: Int, b: Int) = buckets[key] ?? (n: 0, r: 0, g: 0, b: 0)
                buckets[key] = (old.n + 1, old.r + r, old.g + g, old.b + b)
            }
        }
        let palette: [String] = buckets.values.sorted { $0.n > $1.n }.prefix(8).map { v in
            String(format: "#%02X%02X%02X", v.r / v.n, v.g / v.n, v.b / v.n)
        }
        let sorted = mine.sorted { ($0["created"] as? String ?? "") > ($1["created"] as? String ?? "") }
        let shown: [[String: Any]] = sorted.prefix(12).compactMap { (it: [String: Any]) -> [String: Any]? in
            guard let id = it["id"] as? String, let thumb = it["thumb"] as? String else { return nil }
            var a = 1.5
            if let w = (it["w"] as? NSNumber)?.doubleValue, let h = (it["h"] as? NSNumber)?.doubleValue, w > 0, h > 0 { a = w / h }
            return ["id": id, "thumb": thumb, "file": (it["file"] as? String) ?? thumb, "kind": (it["kind"] as? String) ?? "still", "a": a]
        }
        return ["references": refs, "grabs": grabs, "items": shown, "palette": palette]
    }

    /// Calendar events that name the project (read only): "Lexus — shoot day 1".
    func projectCalendar(_ project: String, _ reply: @escaping (Any?, String?) -> Void) {
        guard calendarAllowed() else { return reply(["allowed": false], nil) }
        let title = ((ProjectFile.read(project)["title"] as? String) ?? "").lowercased()
        let names = [project.lowercased(), title].filter { $0.count >= 3 && $0 != "unsorted" }
        guard !names.isEmpty else { return reply(["allowed": true, "events": []], nil) }
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let end = cal.date(byAdding: .day, value: 240, to: Date()) ?? Date()
        let found = calendarStore.events(matching: calendarStore.predicateForEvents(withStart: start, end: end, calendars: nil))
        let events: [[String: Any]] = found.filter { (e: EKEvent) -> Bool in
            let t = (e.title ?? "").lowercased()
            return names.contains { t.contains($0) }
        }.prefix(40).map { (e: EKEvent) -> [String: Any] in
            ["title": e.title ?? "", "date": BriefReader.day.string(from: e.startDate), "end": BriefReader.day.string(from: e.endDate),
             "allDay": e.isAllDay, "start": e.startDate.timeIntervalSince1970 * 1000]
        }
        reply(["allowed": true, "events": events], nil)
    }

    /// Send the picked documents to the picked people; note it on each document.
    func projectSend(_ project: String, _ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard let base = Shared.vault else { return reply(["ok": false, "error": "Choose your vault first"], nil) }
        let rels = ((b["files"] as? [String]) ?? []).filter { !$0.contains("..") }
        let files = rels.map { base.appendingPathComponent($0) }
        let to = (b["to"] as? [[String: Any]]) ?? [], cc = (b["cc"] as? [[String: Any]]) ?? [], bcc = (b["bcc"] as? [[String: Any]]) ?? []
        // Anyone new, with an email, joins the contact book.
        var book = Contacts.load()
        for p in to + cc + bcc where !((p["email"] as? String) ?? "").isEmpty { Contacts.upsert(p.merging(["from": ["project"]]) { a, _ in a }, into: &book) }
        Contacts.save(book)
        let sentDir = Docs.folder(project)?.appendingPathComponent("Sent", isDirectory: true)
        Mailer.send(to: to, cc: cc, bcc: bcc, subject: (b["subject"] as? String) ?? "", body: (b["body"] as? String) ?? "",
                    files: files, copy: (b["copy"] as? Bool) ?? true, keepIn: sentDir) { r in
            guard (r["ok"] as? Bool) == true else { return reply(r, nil) }
            let names: [String] = (to + cc + bcc).map { (p: [String: Any]) -> String in
                let n = (p["name"] as? String) ?? ""
                return n.isEmpty ? ((p["email"] as? String) ?? "") : String(n.split(separator: " ").first ?? "")
            }
            let at = ISO8601DateFormatter().string(from: Date())
            ProjectFile.change(project) { o in
                var docs = (o["docs"] as? [String: Any]) ?? [:]
                for rel in rels {
                    var m = (docs[rel] as? [String: Any]) ?? [:]
                    var sent = (m["sent"] as? [[String: Any]]) ?? []
                    sent.append(["to": names, "at": at])
                    m["sent"] = sent
                    docs[rel] = m
                }
                o["docs"] = docs
                if let id = b["draft"] as? String {
                    var list = (o["drafts"] as? [[String: Any]]) ?? []
                    list.removeAll { ($0["id"] as? String) == id }
                    o["drafts"] = list
                }
            }
            let what = rels.count == 1 ? files[0].deletingPathExtension().lastPathComponent : "\(rels.count) documents"
            let who = names.count <= 3 ? names.joined(separator: ", ") : "\(names.prefix(2).joined(separator: ", ")) + \(names.count - 2)"
            Shell.post("Sent", rels.isEmpty ? "To \(who)." : "\(what) to \(who).")
            var out = r; out["data"] = self.projectData(project)
            reply(out, nil)
        }
    }

    /// After anything's filed: a notification, and every page catches up.
    func filedDone(_ res: [String: Any], _ project: String) {
        guard (res["ok"] as? Bool) == true else { return }
        let n = ((res["rows"] as? [[String: Any]]) ?? []).reduce(0) { $0 + ((($1["count"] as? Int)) ?? 1) }
        if n > 0 { Shell.post("Filed into \(project)", "\(n) thing\(n == 1 ? "" : "s"), sorted by what they are.") }
        home?.evaluateJavaScript("window.__homeRefresh && window.__homeRefresh()", completionHandler: nil)
    }

    /// Files dropped on the project page (or Home's documents): filed, then shown.
    func fileIntoProject(_ urls: [URL]) {
        let project = Shared.project
        guard Shared.vault != nil else { return }
        projectPage?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.start(\(Shell.js("Filing into " + project)))", completionHandler: nil)
        Docs.file(urls, project: project, vault: vaultHost) { [weak self] res in
            guard let self = self else { return }
            self.projectPage?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.done()", completionHandler: nil)
            if let d = try? JSONSerialization.data(withJSONObject: res), let json = String(data: d, encoding: .utf8) {
                self.projectPage?.evaluateJavaScript("window.__projectFiled && window.__projectFiled(\(json))", completionHandler: nil)
            }
            self.filedDone(res, project)
        }
    }
}

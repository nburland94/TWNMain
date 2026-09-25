// Needed Tools — the Cloud vault (Round 12): Needed Vault on your phone.
// A mirror of every project's Stills, GIFs and Motion in iCloud Drive, kept
// matching on Sync. It lives in iCloud Drive › Shortcuts › Needed Vault — the
// one folder the iPhone's Shortcuts can always read and write — so the
// "Save to Needed Vault" and "Grab & Go" Shortcuts need no app and no server.
//
//   Needed Vault/
//     Projects.txt        the project list, for the Shortcuts to choose from (the Mac writes it)
//     Grab & Go.txt       "off", or the project everything goes straight into (the phone writes it)
//     Lexus/
//       Stills/ GIFs/ Motion/   the mirror
//       Inbox/            what the phone saved — sorted into the vault on Sync
//       Links.txt         links shared on the phone, one a line, #tags after
//       Removed/          taken out on the Mac, so kept here rather than lost
//
// Files match by their place in .vault/cloud.json. Taking one out on either
// side takes it out on the other the gentle way: to the Trash on the Mac, to
// Removed in the cloud. Names like "IMG_2041 #night #car.png" bring their tags.

import Foundation
import ImageIO
import CoreGraphics

enum CloudVault {
    static let kinds: [(folder: String, kind: String, exts: Set<String>)] = [
        ("Stills", "still", ["jpg", "jpeg", "png", "webp", "heic", "tif", "tiff"]),
        ("GIFs", "gif", ["gif"]),
        ("Motion", "clip", ["mp4", "mov", "m4v"]),
    ]

    // MARK: Settings

    static var on: Bool {
        get { UserDefaults.standard.bool(forKey: "cloudVault") }
        set { UserDefaults.standard.set(newValue, forKey: "cloudVault"); if newValue { prepare() } }
    }
    /// Clips bigger than this stay on the Mac — they'd fill iCloud fast.
    static var maxClipMB: Int {
        get { let v = UserDefaults.standard.integer(forKey: "cloudMaxClipMB"); return v > 0 ? v : 200 }
        set { UserDefaults.standard.set(max(10, min(5000, newValue)), forKey: "cloudMaxClipMB") }
    }
    /// Where it is: one you chose, or iCloud Drive › Shortcuts › Needed Vault.
    static var root: URL? {
        if let p = UserDefaults.standard.string(forKey: "cloudVaultPath"), !p.isEmpty { return URL(fileURLWithPath: p, isDirectory: true) }
        let docs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents", isDirectory: true)
        let shortcuts = docs.appendingPathComponent("iCloud~is~workflow~my~workflows/Documents", isDirectory: true)
        if FileManager.default.fileExists(atPath: shortcuts.path) { return shortcuts.appendingPathComponent("Needed Vault", isDirectory: true) }
        let drive = docs.appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
        if FileManager.default.fileExists(atPath: drive.path) { return drive.appendingPathComponent("Shortcuts/Needed Vault", isDirectory: true) }
        return nil
    }
    static func choose(_ u: URL?) {
        UserDefaults.standard.set(u?.path ?? "", forKey: "cloudVaultPath")
        // A new place starts a new match — the old record would read as everything taken out.
        if let v = Shared.vault { try? FileManager.default.removeItem(at: bookURL(v)) }
        if on { prepare() }
    }
    static var inShortcuts: Bool { root?.path.contains("iCloud~is~workflow~my~workflows") ?? false }

    // MARK: The files the Shortcuts read

    /// The folder, Grab & Go.txt, the how-to, and the project list.
    static func prepare() {
        guard let r = root else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: r, withIntermediateDirectories: true)
        let gg = r.appendingPathComponent("Grab & Go.txt")
        if !fm.fileExists(atPath: gg.path) { try? "off".write(to: gg, atomically: true, encoding: .utf8) }
        let how = r.appendingPathComponent("How Needed Vault works.txt")
        if !fm.fileExists(atPath: how.path) {
            try? """
            Needed Vault — your vault, on your phone

            This folder is a mirror of every project's Stills, GIFs and Motion. Needed Tools on your Mac
            keeps it matching each time you press Sync.

            On your phone:
              • Share a screenshot, photo, clip or link to "Save to Needed Vault" — it asks which project
                (or goes straight in when Grab & Go is on) and lands in that project's Inbox here.
              • "Grab & Go" on the Action Button or Back Tap turns Grab & Go on and off.
              • Put #tags in a file's name ("IMG_2041 #night #car.png") and they come with it.

            Don't rename Projects.txt or Grab & Go.txt — the Shortcuts read them.
            """.write(to: how, atomically: true, encoding: .utf8)
        }
        publishProjects()
    }

    static func publishProjects() {
        guard let r = root, on else { return }
        let names = Shared.projects().filter { $0 != "Unsorted" }
        let text = names.joined(separator: "\n")
        let u = r.appendingPathComponent("Projects.txt")
        if (try? String(contentsOf: u, encoding: .utf8)) != text { try? text.write(to: u, atomically: true, encoding: .utf8) }
    }

    /// What the phone says: "off", or the project Grab & Go is filing into.
    static var phoneGrabGo: String? {
        guard let r = root, let s = try? String(contentsOf: r.appendingPathComponent("Grab & Go.txt"), encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.lowercased() == "off" ? nil : t
    }

    // MARK: Keeping it matching

    struct Result {
        var pulled = 0                                  // from the phone into the vault
        var pushed = 0                                  // from the Mac up to the cloud
        var trashed = 0                                 // taken out on the phone → Trash on the Mac
        var retired = 0                                 // taken out on the Mac → Removed in the cloud
        var downloading = 0                             // still coming down from iCloud; next Sync
        var skippedBig = 0                              // clips over the size limit, left on the Mac
        var tags: [String: [String]] = [:]              // vault-relative file → its tags from the name
        var fromPhone: Set<String> = []                 // vault-relative files that came from the phone
        var links: [(url: String, tags: [String], project: String)] = []
        var arrived: [(file: URL, kind: String, project: String)] = []   // pulled into projects other than the one syncing
        var byProject: [String: Int] = [:]
    }

    /// Everything, every project. Runs off the main thread (Sync calls it there).
    static func mirror(vault base: URL, syncing current: String) -> Result {
        var out = Result()
        guard on, let r = root else { return out }
        prepare()
        let fm = FileManager.default
        var book = loadBook(base)
        var projects = Set(Shared.projects())
        // Projects that only the phone knows (a new folder made in Files) come too.
        for u in (try? fm.contentsOfDirectory(at: r, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [] {
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { projects.insert(u.lastPathComponent) }
        }
        for p in projects.sorted() where p != "Unsorted" && p != "Add to your iPhone" && !p.hasPrefix(".") {
            mirrorOne(p, base: base, cloud: r, book: &book, out: &out, current: current)
        }
        saveBook(book, base)
        return out
    }

    private static func mirrorOne(_ p: String, base: URL, cloud: URL, book: inout [String: [String: Any]], out: inout Result, current: String) {
        let fm = FileManager.default
        let macProject = base.appendingPathComponent(p, isDirectory: true)
        let cloudProject = cloud.appendingPathComponent(p, isDirectory: true)
        let macThere = fm.fileExists(atPath: macProject.path)
        let rel = { (u: URL, root: URL) in u.path.replacingOccurrences(of: root.path + "/", with: "") }
        let exists = { (u: URL) -> Bool in
            // An iCloud file not downloaded yet is ".name.icloud" — still there.
            fm.fileExists(atPath: u.path) || fm.fileExists(atPath: u.deletingLastPathComponent().appendingPathComponent(".\(u.lastPathComponent).icloud").path)
        }

        // 1. Taken out on one side: the gentle way on the other.
        //    Never when the cloud side looks lost rather than tidied — the folder gone, or most of it
        //    missing at once (iCloud still catching up, or turned off): then nothing is touched.
        let mine = book.filter { $0.value["project"] as? String == p }
        let lostInCloud = mine.keys.filter { !exists(cloud.appendingPathComponent($0)) }.count
        let cloudTrusted = fm.fileExists(atPath: cloudProject.path) && !(lostInCloud > 10 && lostInCloud * 2 > mine.count)
        for (cRel, e) in mine {
            guard let mRel = e["mac"] as? String else { book[cRel] = nil; continue }
            let c = cloud.appendingPathComponent(cRel), m = base.appendingPathComponent(mRel)
            let cOK = exists(c), mOK = fm.fileExists(atPath: m.path)
            if cOK && mOK { continue }
            if !cOK && mOK, macThere {
                guard cloudTrusted else { continue }
                if (try? fm.trashItem(at: m, resultingItemURL: nil)) != nil { out.trashed += 1 }
                book[cRel] = nil
            } else if cOK && !mOK, macThere {
                // Moved on the Mac, not deleted? Same name and size somewhere in the project: follow it.
                let size = (e["bytes"] as? NSNumber)?.int64Value ?? -1
                if let moved = findOnMac(named: m.lastPathComponent, bytes: size, project: p, base: base, known: Set(book.values.compactMap { $0["mac"] as? String })) {
                    book[cRel]?["mac"] = rel(moved, base)
                    continue
                }
                let bin = cloudProject.appendingPathComponent("Removed", isDirectory: true)
                try? fm.createDirectory(at: bin, withIntermediateDirectories: true)
                if (try? fm.moveItem(at: c, to: unique(bin, c.lastPathComponent))) != nil { out.retired += 1 }
                book[cRel] = nil
            } else if !cOK && !mOK {
                book[cRel] = nil
            }
        }
        let knownCloud = Set(book.keys)
        var knownMac = Set(book.values.compactMap { $0["mac"] as? String })

        // 2. From the phone: the Inbox and anything new in Stills, GIFs, Motion.
        var incoming: [URL] = []
        for sub in ["Inbox"] + kinds.map({ $0.folder }) {
            let dir = cloudProject.appendingPathComponent(sub, isDirectory: true)
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? [] {
                let name = f.lastPathComponent
                if name.hasPrefix(".") {
                    if name.hasSuffix(".icloud") {
                        let real = dir.appendingPathComponent(String(name.dropFirst().dropLast(7)))
                        if !knownCloud.contains(rel(real, cloud)) { try? fm.startDownloadingUbiquitousItem(at: real); out.downloading += 1 }
                    }
                    continue
                }
                if !knownCloud.contains(rel(f, cloud)) { incoming.append(f) }
            }
        }
        for f in incoming {
            let ext = f.pathExtension.lowercased()
            guard let k = kinds.first(where: { $0.exts.contains(ext) }) else { continue }
            let (clean, tags) = splitTags(f.deletingPathExtension().lastPathComponent)
            let stem = clean.isEmpty ? "Phone \(stamp())" : clean
            let macDir = macProject.appendingPathComponent(Folders.sub(k.folder, project: p, grab: false), isDirectory: true)
            try? fm.createDirectory(at: macDir, withIntermediateDirectories: true)
            let m = unique(macDir, "\(stem).\(ext)")
            guard (try? fm.copyItem(at: f, to: m)) != nil else { continue }
            // Tidy in the cloud too: out of the Inbox, into its kind's folder, under its clean name.
            var c = f
            let home = cloudProject.appendingPathComponent(k.folder, isDirectory: true)
            if f.deletingLastPathComponent().lastPathComponent != k.folder || clean != f.deletingPathExtension().lastPathComponent {
                try? fm.createDirectory(at: home, withIntermediateDirectories: true)
                let to = unique(home, m.lastPathComponent)
                if (try? fm.moveItem(at: f, to: to)) != nil { c = to }
            }
            let mRel = rel(m, base)
            book[rel(c, cloud)] = ["mac": mRel, "project": p, "bytes": size(m)]
            if !tags.isEmpty { out.tags[mRel] = tags }
            out.fromPhone.insert(mRel)
            knownMac.insert(mRel)
            if p != current { out.arrived.append((m, k.kind, p)) }
            out.pulled += 1
            out.byProject[p, default: 0] += 1
        }

        // 3. Links the phone shared.
        let lf = cloudProject.appendingPathComponent("Links.txt")
        if let text = try? String(contentsOf: lf, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for line in text.components(separatedBy: .newlines) {
                let (rest, tags) = splitTags(line)
                guard let url = rest.components(separatedBy: .whitespaces).first(where: { $0.lowercased().hasPrefix("http") }) else { continue }
                out.links.append((url, tags, p))
            }
            try? "".write(to: lf, atomically: true, encoding: .utf8)
        }

        // 4. Up from the Mac: everything in the project's Stills, GIFs and Motion the cloud hasn't got.
        guard macThere else { return }
        let limit = Int64(maxClipMB) * 1_000_000
        for k in kinds {
            for (sub, _) in Folders.all(k.folder, project: p) {
                let dir = macProject.appendingPathComponent(sub, isDirectory: true)
                for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
                    guard k.exts.contains(f.pathExtension.lowercased()) else { continue }
                    let mRel = rel(f, base)
                    if knownMac.contains(mRel) { continue }
                    let n = size(f)
                    if k.kind == "clip" && n > limit { out.skippedBig += 1; continue }
                    let home = cloudProject.appendingPathComponent(k.folder, isDirectory: true)
                    try? fm.createDirectory(at: home, withIntermediateDirectories: true)
                    let c = unique(home, f.lastPathComponent)
                    guard (try? fm.copyItem(at: f, to: c)) != nil else { continue }
                    book[rel(c, cloud)] = ["mac": mRel, "project": p, "bytes": n]
                    out.pushed += 1
                }
            }
        }
    }

    // MARK: Helpers

    /// "IMG_2041 #night #car" → ("IMG_2041", ["night", "car"])
    static func splitTags(_ s: String) -> (String, [String]) {
        var words: [String] = [], tags: [String] = []
        for w in s.components(separatedBy: .whitespaces) where !w.isEmpty {
            if w.hasPrefix("#"), w.count > 1 {
                let t = String(w.dropFirst()).lowercased()
                if !tags.contains(t) { tags.append(t) }
            } else { words.append(w) }
        }
        return (words.joined(separator: " "), tags)
    }
    private static func findOnMac(named name: String, bytes: Int64, project p: String, base: URL, known: Set<String>) -> URL? {
        let fm = FileManager.default
        for k in kinds {
            for (sub, _) in Folders.all(k.folder, project: p) {
                let u = base.appendingPathComponent(p, isDirectory: true).appendingPathComponent(sub, isDirectory: true).appendingPathComponent(name)
                let r = u.path.replacingOccurrences(of: base.path + "/", with: "")
                if !known.contains(r), fm.fileExists(atPath: u.path), bytes <= 0 || size(u) == bytes { return u }
            }
        }
        return nil
    }
    static func unique(_ dir: URL, _ name: String) -> URL {
        let fm = FileManager.default
        var u = dir.appendingPathComponent(name)
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: u.path) {
            u = dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return u
    }
    static func size(_ u: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.int64Value ?? -1
    }
    private static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"; return f.string(from: Date())
    }
    private static func bookURL(_ base: URL) -> URL { base.appendingPathComponent(".vault/cloud.json") }
    private static func loadBook(_ base: URL) -> [String: [String: Any]] {
        (try? Data(contentsOf: bookURL(base))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Any]] } ?? [:]
    }
    private static func saveBook(_ b: [String: [String: Any]], _ base: URL) {
        try? FileManager.default.createDirectory(at: base.appendingPathComponent(".vault", isDirectory: true), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: b) { try? d.write(to: bookURL(base), options: .atomic) }
    }

    /// For Home: where it is, whether it's on, what the phone's doing.
    static func status() -> [String: Any] {
        var s: [String: Any] = ["on": on, "maxClipMB": maxClipMB, "shortcuts": inShortcuts, "grabGo": phoneGrabGo ?? ""]
        if let r = root {
            s["path"] = r.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            var place = r.lastPathComponent
            if inShortcuts {
                place = "iCloud Drive › Shortcuts › Needed Vault"
            } else if let tail = r.path.components(separatedBy: "com~apple~CloudDocs/").last, r.path.contains("com~apple~CloudDocs/") {
                place = "iCloud Drive › " + tail.replacingOccurrences(of: "/", with: " › ")
            }
            s["where"] = place
            s["exists"] = FileManager.default.fileExists(atPath: r.path)
        } else {
            s["where"] = ""
            s["noICloud"] = true
        }
        if let t = UserDefaults.standard.string(forKey: "cloudLast") { s["last"] = t }
        return s
    }
}

// MARK: - What the phone shows: a small index of each project, with tiny pictures

extension CloudVault {
    /// Needed Vault/Phone.json — the projects; Needed Vault/<Project>/Phone.json — its newest 48,
    /// each with a thumbnail small enough to travel back to the phone page through the Shortcut.
    /// Written only when something changed, so iCloud isn't kept busy.
    static func publishPhone(items: [[String: Any]], base: URL) {
        guard on, let r = root else { return }
        let fm = FileManager.default
        var byProject: [String: [[String: Any]]] = [:]
        for it in items where ["still", "gif", "clip"].contains(it["kind"] as? String ?? "") {
            byProject[(it["project"] as? String) ?? "Unsorted", default: []].append(it)
        }
        let names = Shared.projects().filter { $0 != "Unsorted" }
        // Where each one is in the cloud, for "Full size" on the phone.
        var cloudOf: [String: String] = [:]
        for (c, e) in loadBook(base) { if let m = e["mac"] as? String { cloudOf[m] = c } }
        var list: [[String: Any]] = []
        for p in names {
            let mine = (byProject[p] ?? []).sorted { (($0["created"] as? String) ?? "") > (($1["created"] as? String) ?? "") }
            list.append(["n": p, "c": mine.count, "l": Labels.of(p)])
            var out: [[String: Any]] = []
            for it in mine.prefix(36) {
                var o: [String: Any] = ["id": it["id"] as? String ?? "", "k": it["kind"] as? String ?? "still"]
                let src = it["source"] as? [String: Any] ?? [:]
                o["n"] = (it["title"] as? String) ?? (src["title"] as? String) ?? ""
                if let u = src["url"] as? String { o["u"] = u }
                if let t = src["type"] as? String { o["s"] = t }
                if let g = it["tags"] as? [String], !g.isEmpty { o["g"] = g }
                if let c = it["palette"] as? [String] { o["c"] = Array(c.prefix(4)) }
                if let d = it["created"] as? String { o["d"] = String(d.prefix(10)) }
                if let f = it["file"] as? String, let c = cloudOf[f] { o["f"] = c }
                if let rel = (it["thumb"] as? String) ?? (it["file"] as? String), let t = tinyJPEG(base.appendingPathComponent(rel)) {
                    o["t"] = t.data.base64EncodedString(); o["a"] = (t.aspect * 100).rounded() / 100
                }
                out.append(o)
            }
            let dir = r.appendingPathComponent(p, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            write(["p": p, "c": mine.count, "items": out], to: dir.appendingPathComponent("Phone.json"))
        }
        write(["projects": list, "current": Shared.project, "grabGo": phoneGrabGo ?? ""], to: r.appendingPathComponent("Phone.json"))
    }
    private static func write(_ o: [String: Any], to u: URL) {
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return }
        if (try? Data(contentsOf: u)) == d { return }
        try? d.write(to: u, options: .atomic)
    }
    /// A 120-pixel JPEG of a picture (or a clip's poster), and its shape.
    static func tinyJPEG(_ u: URL) -> (data: Data, aspect: Double)? {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 110,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return (data as Data, Double(img.width) / Double(max(1, img.height)))
    }
}

// MARK: - The two Shortcuts, made and signed here — one tap on the phone adds each

extension CloudVault {
    /// "Needed Vault" does everything the phone page asks, and is the Share Sheet's "save this":
    ///   home            → the projects (Needed Vault/Phone.json)
    ///   browse|Lexus    → Lexus's newest, with tiny pictures
    ///   photos|Lexus    → pick from Photos, into Lexus's Inbox, back with their thumbnails
    ///   shot|Lexus      → the latest screenshot, the same way
    ///   gg|Lexus, gg|off → Grab & Go on (into Lexus) or off
    ///   view|Lexus/Stills/a.jpg → that file, full size
    ///   anything shared → into the Grab & Go project, or the one you pick
    /// "Grab & Go" is for the Action Button or Back Tap: on (pick the project) and off.
    static func makeShortcuts(into dir: URL) -> [URL] {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var made: [URL] = []
        for (name, actions, share) in [("Needed Vault", ShortcutBuilder.neededVault(), true), ("Grab & Go", ShortcutBuilder.grabAndGo(), false)] {
            let plist = ShortcutBuilder.workflow(actions, share: share)
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else { continue }
            let raw = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).shortcut")
            let out = dir.appendingPathComponent("\(name).shortcut")
            guard (try? data.write(to: raw)) != nil else { continue }
            try? fm.removeItem(at: out)
            // iPhones only add Shortcuts that are signed; the Mac signs them (macOS 12 or later, signed in to iCloud).
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            task.arguments = ["sign", "--mode", "anyone", "--input", raw.path, "--output", out.path]
            task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            if (try? task.run()) != nil { task.waitUntilExit() }
            try? fm.removeItem(at: raw)
            if task.terminationStatus == 0, fm.fileExists(atPath: out.path) { made.append(out) }
        }
        return made
    }
}

/// Shortcuts' own file format, action by action.
enum ShortcutBuilder {
    typealias A = [String: Any]
    static func workflow(_ actions: [A], share: Bool) -> A {
        var w: A = [
            "WFWorkflowActions": actions,
            "WFWorkflowClientVersion": "2302.0.4",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59511],
            "WFWorkflowImportQuestions": [],
            "WFWorkflowInputContentItemClasses": ["WFImageContentItem", "WFPhotoMediaContentItem", "WFAVAssetContentItem",
                                                  "WFGenericFileContentItem", "WFStringContentItem", "WFURLContentItem"],
            "WFWorkflowOutputContentItemClasses": [],
            "WFQuickActionSurfaces": [],
            "WFWorkflowHasShortcutInputVariables": share,
        ]
        w["WFWorkflowTypes"] = share ? ["ActionExtension"] : []
        return w
    }
    // Pieces
    static func act(_ id: String, _ p: A = [:], uuid: String? = nil) -> A {
        var params = p
        if let u = uuid { params["UUID"] = u }
        return ["WFWorkflowActionIdentifier": "is.workflow.actions.\(id)", "WFWorkflowActionParameters": params]
    }
    static func v(_ name: String) -> A { ["Type": "Variable", "VariableName": name] }
    static let input: A = ["Type": "ExtensionInput"]
    static func out(_ uuid: String, _ name: String) -> A { ["Type": "ActionOutput", "OutputUUID": uuid, "OutputName": name] }
    static func attach(_ a: A) -> A { ["Value": a, "WFSerializationType": "WFTextTokenAttachment"] }
    /// Text with variables in it: "Needed Vault/{Project}/Inbox/"
    static func text(_ parts: [Any]) -> A {
        var s = "", ranges: [String: Any] = [:]
        for part in parts {
            if let t = part as? String { s += t }
            else if let a = part as? A { ranges["{\(s.utf16.count), 1}"] = a; s += "\u{FFFC}" }
        }
        return ["Value": ["string": s, "attachmentsByRange": ranges], "WFSerializationType": "WFTextTokenString"]
    }
    static func setVar(_ name: String, _ a: A) -> A { act("setvariable", ["WFVariableName": name, "WFInput": attach(a)]) }
    /// If <variable> is "<text>" … End If — the actions run inside it.
    static func ifIs(_ a: A, _ value: String, _ then: [A], otherwise: [A]? = nil) -> [A] {
        let g = UUID().uuidString
        var r: [A] = [act("conditional", ["GroupingIdentifier": g, "WFControlFlowMode": 0, "WFCondition": 4,
                                          "WFConditionalActionString": value, "WFInput": ["Type": "Variable", "Variable": attach(a)]])]
        r += then
        if let o = otherwise { r.append(act("conditional", ["GroupingIdentifier": g, "WFControlFlowMode": 1])); r += o }
        r.append(act("conditional", ["GroupingIdentifier": g, "WFControlFlowMode": 2]))
        return r
    }
    static func ifHasValue(_ a: A, _ then: [A], otherwise: [A]) -> [A] {
        let g = UUID().uuidString
        return [act("conditional", ["GroupingIdentifier": g, "WFControlFlowMode": 0, "WFCondition": 100,
                                    "WFInput": ["Type": "Variable", "Variable": attach(a)]])]
            + then + [act("conditional", ["GroupingIdentifier": g, "WFControlFlowMode": 1])] + otherwise
            + [act("conditional", ["GroupingIdentifier": g, "WFControlFlowMode": 2])]
    }
    static func getFile(_ path: [Any], uuid: String) -> A {
        act("documentpicker.open", ["WFGetFilePath": text(path), "WFShowFilePicker": false, "WFFileErrorIfNotFound": false], uuid: uuid)
    }
    static func saveFile(_ a: A, _ path: [Any], overwrite: Bool) -> A {
        act("documentpicker.save", ["WFInput": attach(a), "WFAskWhereToSave": false, "WFFileDestinationPath": text(path), "WFSaveFileOverwrite": overwrite])
    }
    static func output(_ parts: [Any]) -> A { act("output", ["WFOutput": text(parts)]) }
    /// Save the files, then hand back "saved|Project|count|thumb,thumb,…".
    static func saveAndReport() -> [A] {
        let cnt = UUID().uuidString, imgs = UUID().uuidString, rs = UUID().uuidString, cv = UUID().uuidString, b64 = UUID().uuidString, cmb = UUID().uuidString
        return [
            saveFile(v("Files"), ["Needed Vault/", v("Project"), "/Inbox/"], overwrite: false),
            act("count", ["Input": attach(v("Files")), "WFCountType": "Items"], uuid: cnt),
            act("detect.images", ["WFInput": attach(v("Files"))], uuid: imgs),
            act("image.resize", ["WFImage": attach(out(imgs, "Images")), "WFImageResizeKey": "Width", "WFImageResizeWidth": "160"], uuid: rs),
            act("image.convert", ["WFInput": attach(out(rs, "Resized Image")), "WFImageFormat": "JPEG", "WFImageCompressionQuality": 0.5, "WFImagePreserveMetadata": false], uuid: cv),
            act("base64encode", ["WFInput": attach(out(cv, "Converted Image")), "WFEncodeMode": "Encode", "WFBase64LineBreakMode": "None"], uuid: b64),
            act("text.combine", ["text": attach(out(b64, "Base64 Encoded")), "WFTextSeparator": "Custom", "WFTextCustomSeparator": ","], uuid: cmb),
            output(["saved|", v("Project"), "|", out(cnt, "Count"), "|", out(cmb, "Combined Text")]),
        ]
    }
    static func pickProject() -> [A] {
        let gf = UUID().uuidString, sp = UUID().uuidString, ch = UUID().uuidString
        return [getFile(["Needed Vault/Projects.txt"], uuid: gf),
                act("text.split", ["text": attach(out(gf, "File")), "WFTextSeparator": "New Lines"], uuid: sp),
                act("choosefromlist", ["WFInput": attach(out(sp, "Split Text")), "WFChooseFromListActionPrompt": "Which project?"], uuid: ch),
                setVar("Project", out(ch, "Chosen Item"))]
    }

    static func neededVault() -> [A] {
        let sp = UUID().uuidString, m = UUID().uuidString, pr = UUID().uuidString
        var a: [A] = [
            act("text.split", ["text": attach(input), "WFTextSeparator": "Custom", "WFTextCustomSeparator": "|"], uuid: sp),
            act("getitemfromlist", ["WFInput": attach(out(sp, "Split Text")), "WFItemSpecifier": "First Item"], uuid: m),
            setVar("Mode", out(m, "Item from List")),
            act("getitemfromlist", ["WFInput": attach(out(sp, "Split Text")), "WFItemSpecifier": "Item At Index", "WFItemIndex": 2], uuid: pr),
            setVar("Project", out(pr, "Item from List")),
        ]
        let h = UUID().uuidString, b = UUID().uuidString, ph = UUID().uuidString, sh = UUID().uuidString, gt = UUID().uuidString
        a += ifIs(v("Mode"), "home", [getFile(["Needed Vault/Phone.json"], uuid: h), output([out(h, "File")])])
        a += ifIs(v("Mode"), "browse", [getFile(["Needed Vault/", v("Project"), "/Phone.json"], uuid: b), output([out(b, "File")])])
        a += ifIs(v("Mode"), "gg", [act("gettext", ["WFTextActionText": text([v("Project")])], uuid: gt),
                                    saveFile(out(gt, "Text"), ["Needed Vault/Grab & Go.txt"], overwrite: true),
                                    output(["gg|", v("Project")])])
        let vf = UUID().uuidString
        a += ifIs(v("Mode"), "view", [getFile(["Needed Vault/", v("Project")], uuid: vf),
                                      act("previewdocument", ["WFInput": attach(out(vf, "File"))]), output(["view"])])
        a += ifIs(v("Mode"), "photos", [act("selectphoto", ["WFSelectMultiplePhotos": true], uuid: ph), setVar("Files", out(ph, "Photos"))] + saveAndReport())
        a += ifIs(v("Mode"), "shot", [act("getlastscreenshot", ["WFGetLatestPhotoCount": 1], uuid: sh), setVar("Files", out(sh, "Latest Screenshots"))] + saveAndReport())
        // From the Share Sheet (or nothing — Back Tap: the latest screenshot), into Grab & Go's project or the one you pick.
        let ls = UUID().uuidString, gg = UUID().uuidString, ggt = UUID().uuidString
        a += ifHasValue(input, [setVar("Files", input)],
                        otherwise: [act("getlastscreenshot", ["WFGetLatestPhotoCount": 1], uuid: ls), setVar("Files", out(ls, "Latest Screenshots"))])
        a += [getFile(["Needed Vault/Grab & Go.txt"], uuid: gg), act("detect.text", ["WFInput": attach(out(gg, "File"))], uuid: ggt), setVar("GG", out(ggt, "Text"))]
        a += ifIs(v("GG"), "off", pickProject(), otherwise: [setVar("Project", v("GG"))])
        a += [saveFile(v("Files"), ["Needed Vault/", v("Project"), "/Inbox/"], overwrite: false),
              act("notification", ["WFNotificationActionBody": text(["Saved to ", v("Project")]), "WFNotificationActionSound": false])]
        return a
    }

    static func grabAndGo() -> [A] {
        let gg = UUID().uuidString, ggt = UUID().uuidString, on = UUID().uuidString, off = UUID().uuidString
        var a: [A] = [getFile(["Needed Vault/Grab & Go.txt"], uuid: gg), act("detect.text", ["WFInput": attach(out(gg, "File"))], uuid: ggt), setVar("GG", out(ggt, "Text"))]
        a += ifIs(v("GG"), "off",
                  pickProject() + [act("gettext", ["WFTextActionText": text([v("Project")])], uuid: on),
                                   saveFile(out(on, "Text"), ["Needed Vault/Grab & Go.txt"], overwrite: true),
                                   act("notification", ["WFNotificationActionBody": text(["Grab & Go on — everything goes into ", v("Project")]), "WFNotificationActionSound": false])],
                  otherwise: [act("gettext", ["WFTextActionText": text(["off"])], uuid: off),
                              saveFile(out(off, "Text"), ["Needed Vault/Grab & Go.txt"], overwrite: true),
                              act("notification", ["WFNotificationActionBody": text(["Grab & Go off"]), "WFNotificationActionSound": false])])
        return a
    }
}

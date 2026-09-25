// Needed Vault for iPhone — the folder. The Mac keeps a mirror of every project's
// Stills, GIFs and Motion in iCloud Drive (Needed Tools › Home › Your phone). This
// app reads that folder directly and saves into each project's Inbox; the Mac files
// what's there into the vault on its next Sync.
//
//   Needed Vault/
//     Projects.txt · Phone.json · Grab & Go.txt       (the Mac writes the first two)
//     Lexus/Stills · GIFs · Motion · Inbox · Phone.json
//
// You choose the folder once; the app and the Share Sheet both keep a bookmark to it
// (they share an App Group). Anything that can't reach the folder yet waits in the
// Outbox on this phone and goes in the next time the app opens.

import Foundation
import UniformTypeIdentifiers
import ImageIO

enum VaultKind: String, CaseIterable { case still, gif, clip
    var label: String { self == .clip ? "Clip" : self == .gif ? "GIF" : "Still" }
}

struct VaultItem: Identifiable, Hashable {
    let id: String              // its place in Needed Vault, "Lexus/Stills/a.jpg"
    let url: URL                // the file (maybe still in iCloud)
    let kind: VaultKind
    var name: String
    var tags: [String] = []
    var palette: [String] = []
    var source: String? = nil
    var link: String? = nil
    var added: Date? = nil
    var aspect: Double = 1.5
    var tiny: Data? = nil       // the Mac's small preview, for before the file's downloaded
    var downloaded = true
}

struct VaultProject: Identifiable, Hashable {
    var id: String { name }
    let name: String
    var count: Int = 0
    var label: String = ""
}

struct SaveFile {
    let data: Data
    let name: String            // "IMG_2041.heic"
}

final class VaultFolder {
    static let group = "group.com.thiswasneeded.neededvault"
    static let shared = VaultFolder()
    let defaults = UserDefaults(suiteName: VaultFolder.group) ?? .standard

    static let stills: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff"]
    static let motion: Set<String> = ["mp4", "mov", "m4v"]
    static func kind(ofExtension e: String) -> VaultKind? {
        let x = e.lowercased()
        if x == "gif" { return .gif }
        if motion.contains(x) { return .clip }
        if stills.contains(x) { return .still }
        return nil
    }

    // MARK: The folder, chosen once

    var hasFolder: Bool { defaults.data(forKey: "folder") != nil }
    var folderName: String { defaults.string(forKey: "folderName") ?? "" }

    func remember(_ url: URL) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: "folder")
        defaults.set(url.lastPathComponent, forKey: "folderName")
    }
    func forget() { defaults.removeObject(forKey: "folder") }

    /// The app keeps the folder open while it runs, so clips can play and Share can read the file.
    private var held: URL?
    func keepOpen() {
        guard held == nil, let data = defaults.data(forKey: "folder") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return }
        if url.startAccessingSecurityScopedResource() { held = url }
    }

    /// Runs `body` with the folder open. Nil when there's no folder, or it can't be reached.
    func open<T>(_ body: (URL) throws -> T) -> T? {
        guard let data = defaults.data(forKey: "folder") else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: "folder")
        }
        return try? body(url)
    }

    // MARK: Reading

    private func coordinatedData(_ url: URL) -> Data? {
        var out: Data?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in out = try? Data(contentsOf: u) }
        return out
    }
    private func json(_ url: URL) -> [String: Any]? {
        guard let d = coordinatedData(url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// The projects: the Mac's list (with counts and labels), else the folders there.
    func projects() -> [VaultProject] {
        open { root -> [VaultProject] in
            if let j = json(root.appendingPathComponent("Phone.json")), let list = j["projects"] as? [[String: Any]], !list.isEmpty {
                return list.compactMap { p in
                    guard let n = p["n"] as? String, !n.isEmpty else { return nil }
                    return VaultProject(name: n, count: (p["c"] as? Int) ?? 0, label: (p["l"] as? String) ?? "")
                }
            }
            if let d = coordinatedData(root.appendingPathComponent("Projects.txt")), let t = String(data: d, encoding: .utf8) {
                let names = t.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !names.isEmpty { return names.map { VaultProject(name: $0) } }
            }
            let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            return dirs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true && $0.lastPathComponent != "Add to your iPhone" }
                .map { VaultProject(name: $0.lastPathComponent) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } ?? []
    }

    /// Which project the Mac is in — a good first guess.
    func macProject() -> String? {
        open { root in json(root.appendingPathComponent("Phone.json"))?["current"] as? String }.flatMap { $0 }
    }

    /// A project's stills, GIFs and clips — newest first — with what the Mac knows about each.
    func items(of project: String) -> [VaultItem] {
        open { root -> [VaultItem] in
            let fm = FileManager.default
            let proj = root.appendingPathComponent(project, isDirectory: true)
            var meta: [String: [String: Any]] = [:]
            if let j = json(proj.appendingPathComponent("Phone.json")), let list = j["items"] as? [[String: Any]] {
                for it in list { if let f = it["f"] as? String { meta[f] = it } }
            }
            var out: [VaultItem] = []
            for sub in ["Inbox", "Stills", "GIFs", "Motion"] {
                let dir = proj.appendingPathComponent(sub, isDirectory: true)
                let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])) ?? []
                for f in files {
                    var name = f.lastPathComponent, downloaded = true
                    if name.hasPrefix(".") {
                        // Not downloaded yet: ".IMG_1.jpg.icloud"
                        guard name.hasSuffix(".icloud") else { continue }
                        name = String(name.dropFirst().dropLast(7)); downloaded = false
                    }
                    let real = dir.appendingPathComponent(name)
                    guard let kind = VaultFolder.kind(ofExtension: real.pathExtension) else { continue }
                    let id = "\(project)/\(sub)/\(name)"
                    let (clean, tags) = VaultFolder.splitTags((name as NSString).deletingPathExtension)
                    var item = VaultItem(id: id, url: real, kind: kind, name: clean, tags: tags, downloaded: downloaded)
                    item.added = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if let m = meta[id] {
                        if let n = m["n"] as? String, !n.isEmpty { item.name = n }
                        if let g = m["g"] as? [String] { item.tags = Array(Set(item.tags + g)).sorted() }
                        item.palette = (m["c"] as? [String]) ?? []
                        item.source = m["s"] as? String
                        item.link = m["u"] as? String
                        if let a = m["a"] as? Double, a > 0 { item.aspect = a }
                        if let t = m["t"] as? String { item.tiny = Data(base64Encoded: t) }
                    }
                    if !downloaded { try? fm.startDownloadingUbiquitousItem(at: real) }
                    out.append(item)
                }
            }
            return out.sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
        } ?? []
    }

    // MARK: Grab & Go — "off", or the project everything goes straight into

    func grabGo() -> String? {
        let t = open { root -> String? in
            guard let d = coordinatedData(root.appendingPathComponent("Grab & Go.txt")) else { return nil }
            return String(data: d, encoding: .utf8)
        }.flatMap { $0 }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? defaults.string(forKey: "grabGo") ?? "off"
        return t.isEmpty || t.lowercased() == "off" ? nil : t
    }
    @discardableResult
    func setGrabGo(_ project: String?) -> Bool {
        let text = project ?? "off"
        defaults.set(text, forKey: "grabGo")
        return open { root -> Bool in
            try write(Data(text.utf8), to: root.appendingPathComponent("Grab & Go.txt"))
            return true
        } ?? false
    }

    /// The project last used on this phone.
    var lastProject: String? {
        get { defaults.string(forKey: "project") }
        set { defaults.set(newValue, forKey: "project") }
    }

    // MARK: Saving — into the project's Inbox, "#tags" in the name

    enum Saved { case inVault, waiting }

    /// Saves the files. Returns .waiting if they went to this phone's Outbox instead.
    func save(_ files: [SaveFile], project: String, tags: [String]) -> Saved {
        let named = files.map { f -> SaveFile in
            let stem = (f.name as NSString).deletingPathExtension, ext = (f.name as NSString).pathExtension
            let t = tags.map { "#" + $0.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: " ", with: "-") }.filter { $0.count > 1 }
            let base = ([VaultFolder.safe(stem)] + t).joined(separator: " ")
            return SaveFile(data: f.data, name: ext.isEmpty ? base : "\(base).\(ext.lowercased())")
        }
        let ok = open { root -> Bool in
            let inbox = root.appendingPathComponent(project, isDirectory: true).appendingPathComponent("Inbox", isDirectory: true)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            for f in named { try write(f.data, to: VaultFolder.unique(inbox, f.name)) }
            return true
        } ?? false
        if ok { return .inVault }
        // Couldn't reach it: keep them here until the app can.
        guard let out = outbox?.appendingPathComponent(project, isDirectory: true) else { return .waiting }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for f in named { try? f.data.write(to: VaultFolder.unique(out, f.name)) }
        return .waiting
    }

    var outbox: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: VaultFolder.group)?.appendingPathComponent("Outbox", isDirectory: true)
    }
    var waitingCount: Int {
        guard let o = outbox else { return 0 }
        let e = FileManager.default.enumerator(at: o, includingPropertiesForKeys: [.isRegularFileKey])
        var n = 0
        while let u = e?.nextObject() as? URL { if (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { n += 1 } }
        return n
    }
    /// What waited on this phone goes in now. Returns how many.
    @discardableResult
    func flushOutbox() -> Int {
        guard let o = outbox else { return 0 }
        let fm = FileManager.default
        let projects = (try? fm.contentsOfDirectory(at: o, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return open { root -> Int in
            var n = 0
            for p in projects {
                let inbox = root.appendingPathComponent(p.lastPathComponent, isDirectory: true).appendingPathComponent("Inbox", isDirectory: true)
                try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
                for f in (try? fm.contentsOfDirectory(at: p, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
                    guard let d = try? Data(contentsOf: f) else { continue }
                    if (try? write(d, to: VaultFolder.unique(inbox, f.lastPathComponent))) != nil { try? fm.removeItem(at: f); n += 1 }
                }
            }
            return n
        } ?? 0
    }

    private func write(_ data: Data, to url: URL) throws {
        var err: NSError?, inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
            do { try data.write(to: u, options: .atomic) } catch { inner = error }
        }
        if let e = err ?? inner { throw e }
    }

    // MARK: Helpers

    /// "IMG_2041 #night #car" → ("IMG_2041", ["night", "car"])
    static func splitTags(_ s: String) -> (String, [String]) {
        var words: [String] = [], tags: [String] = []
        for w in s.split(separator: " ") {
            if w.hasPrefix("#"), w.count > 1 { let t = String(w.dropFirst()).lowercased(); if !tags.contains(t) { tags.append(t) } }
            else { words.append(String(w)) }
        }
        return (words.joined(separator: " "), tags)
    }
    static func safe(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Photo" : String(t.prefix(80))
    }
    static func unique(_ dir: URL, _ name: String) -> URL {
        let fm = FileManager.default
        var u = dir.appendingPathComponent(name)
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while fm.fileExists(atPath: u.path) || fm.fileExists(atPath: dir.appendingPathComponent(".\(u.lastPathComponent).icloud").path) {
            u = dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return u
    }
    static func stamp(_ prefix: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(f.string(from: Date()))"
    }

    /// A small image of a still or GIF for the grid (and a clip's first frame elsewhere).
    static func thumbnail(_ url: URL, max: Int) -> CGImage? {
        var out: CGImage?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return }
            let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
            out = CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
        }
        return out
    }
    /// A small still of an image file's data, for the "today" list.
    static func thumbnail(_ data: Data, max: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max,
                                  kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
    }
}

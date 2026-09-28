// Needed Mobile Vault for iPhone — what's kept on this phone.
//
// Every photo, screenshot, GIF and clip you grab is saved here first, so it works with
// no signal at all. When the phone is on the same Wi-Fi as your Mac, each one is sent
// straight into its project there (MacLink) and marked as received — but it stays here
// too: nothing on the phone is deleted on its own.
//
//   <App Group>/Grabs/<id>.<ext>        the file
//   <App Group>/Grabs/<id>.jpg.thumb    a small preview for the feed
//   <App Group>/grabs.json              the list (what, which project, tags, sent or not)
//
// The app and the Share Sheet both use it (they share the App Group).

import Foundation
import UniformTypeIdentifiers
import ImageIO
import AVFoundation
import UIKit

enum GrabKind: String, Codable, CaseIterable {
    case still, gif, clip
    var label: String { self == .clip ? "Clip" : self == .gif ? "GIF" : "Still" }
    var plural: String { self == .clip ? "Clips" : self == .gif ? "GIFs" : "Stills" }

    static func of(ext e: String) -> GrabKind? {
        let x = e.lowercased()
        if x == "gif" { return .gif }
        if ["mp4", "mov", "m4v"].contains(x) { return .clip }
        if ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff"].contains(x) { return .still }
        return nil
    }
}

struct Grab: Codable, Identifiable, Hashable {
    var id: String                 // a UUID — also the Mac's receipt number, so nothing lands twice
    var project: String
    var name: String               // "IMG_2041.heic" — what the Mac calls the file
    var kind: GrabKind
    var tags: [String] = []
    var added = Date()
    var aspect: Double = 1.5       // width ÷ height
    var sentAt: Date? = nil        // when the Mac said it saved it
    var ext: String { (name as NSString).pathExtension.lowercased() }
    var sent: Bool { sentAt != nil }
}

/// A project: from the Mac (with its count and label), or one made on this phone.
struct ProjectInfo: Codable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var count: Int = 0             // on the Mac
    var label: String = ""
}

/// The Mac this phone sends to — from the code in Needed Tools › Home › Your phone.
struct PairedMac: Codable, Equatable {
    var host: String               // "Nates-MacBook.local" or "192.168.1.20"
    var port: Int
    var key: String
    var name: String = "your Mac"
    var altHost: String? = nil     // the other way to reach it, if we learn one

    /// Reads the Mac's code: http://Nates-MacBook.local:7788/capture/#k=KEY
    static func from(_ text: String) -> PairedMac? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), let host = u.host, !host.isEmpty else { return nil }
        let frag = u.fragment ?? ""
        var key = ""
        for part in frag.split(separator: "&") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == "k" { key = kv[1].removingPercentEncoding ?? kv[1] }
        }
        guard key.count >= 20 else { return nil }
        return PairedMac(host: host, port: u.port ?? 7788, key: key)
    }
}

final class Library {
    static let group = "group.com.thiswasneeded.neededvault"
    static let shared = Library()
    let defaults = UserDefaults(suiteName: Library.group) ?? .standard
    private let lock = NSLock()

    var root: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Library.group)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    var folder: URL {
        let u = root.appendingPathComponent("Grabs", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private var indexURL: URL { root.appendingPathComponent("grabs.json") }

    func fileURL(_ g: Grab) -> URL { folder.appendingPathComponent("\(g.id).\(g.ext.isEmpty ? "jpg" : g.ext)") }
    func thumbURL(_ g: Grab) -> URL { folder.appendingPathComponent("\(g.id).jpg.thumb") }

    // MARK: The list — read and written under a file coordinator, so the Share Sheet and the app never trip over each other

    func all() -> [Grab] {
        var out: [Grab] = []
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: indexURL, options: [], error: &err) { u in
            if let d = try? Data(contentsOf: u), let list = try? JSONDecoder().decode([Grab].self, from: d) { out = list }
        }
        return out.sorted { $0.added > $1.added }
    }

    /// Changes the list in one go: read, change, write.
    @discardableResult
    func update(_ change: (inout [Grab]) -> Void) -> [Grab] {
        lock.lock(); defer { lock.unlock() }
        var result: [Grab] = []
        var err: NSError?
        NSFileCoordinator().coordinate(writingItemAt: indexURL, options: [], error: &err) { u in
            var list = (try? Data(contentsOf: u)).flatMap { try? JSONDecoder().decode([Grab].self, from: $0) } ?? []
            change(&list)
            if let d = try? JSONEncoder().encode(list) { try? d.write(to: u, options: .atomic) }
            result = list
        }
        return result.sorted { $0.added > $1.added }
    }

    // MARK: Adding — the file is copied in, a preview made, then it's on the list

    /// Keeps a file (by its data) for a project. Returns the new grab, or nil if it isn't a picture or clip.
    @discardableResult
    func add(data: Data, name: String, project: String, tags: [String]) -> Grab? {
        guard let g = prepare(name: name, project: project, tags: tags) else { return nil }
        do { try data.write(to: fileURL(g), options: .atomic) } catch { return nil }
        return finish(g)
    }
    /// Keeps a file (by its place on disk — clips can be big). The file is copied, not moved.
    @discardableResult
    func add(file: URL, name: String? = nil, project: String, tags: [String]) -> Grab? {
        guard let g = prepare(name: name ?? file.lastPathComponent, project: project, tags: tags) else { return nil }
        do {
            let dst = fileURL(g)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: file, to: dst)
        } catch { return nil }
        return finish(g)
    }

    private func prepare(name: String, project: String, tags: [String]) -> Grab? {
        var clean = (name as NSString).lastPathComponent.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if clean.hasPrefix(".") || clean.isEmpty { clean = "Photo.jpg" }
        var ext = (clean as NSString).pathExtension
        if ext.isEmpty { ext = "jpg"; clean += ".jpg" }
        guard let kind = GrabKind.of(ext: ext) else { return nil }
        let p = project.trimmingCharacters(in: .whitespaces)
        var t: [String] = []
        for raw in tags {
            let x = raw.lowercased().replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces)
            if !x.isEmpty && !t.contains(x) { t.append(x) }
        }
        return Grab(id: UUID().uuidString, project: p.isEmpty ? "Unsorted" : p, name: clean, kind: kind, tags: t)
    }
    private func finish(_ g: Grab) -> Grab {
        var g = g
        let (thumb, aspect) = Library.preview(of: fileURL(g), kind: g.kind, max: 900)
        if let t = thumb { try? t.write(to: thumbURL(g), options: .atomic) }
        if let a = aspect, a > 0 { g.aspect = (a * 100).rounded() / 100 }
        let done = g
        update { $0.append(done) }
        return done
    }

    func markSent(_ id: String) { update { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].sentAt = Date() } } }
    /// Moves a grab to another project on this phone. One already on the Mac stays where the Mac put it
    /// (the Mac only takes each grab once) — the app says so.
    func move(_ id: String, to project: String) {
        update { list in
            guard let i = list.firstIndex(where: { $0.id == id }) else { return }
            list[i].project = project
        }
    }
    /// Deletes from this phone only — the Mac keeps what it already has.
    func delete(_ ids: Set<String>) {
        let gone = all().filter { ids.contains($0.id) }
        for g in gone { try? FileManager.default.removeItem(at: fileURL(g)); try? FileManager.default.removeItem(at: thumbURL(g)) }
        update { $0.removeAll { ids.contains($0.id) } }
    }

    // MARK: What the phone remembers

    var mac: PairedMac? {
        get { defaults.data(forKey: "mac").flatMap { try? JSONDecoder().decode(PairedMac.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "mac") }
    }
    var projects: [ProjectInfo] {
        get { defaults.data(forKey: "projects").flatMap { try? JSONDecoder().decode([ProjectInfo].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "projects") }
    }
    var macProject: String? {
        get { defaults.string(forKey: "macProject") }
        set { defaults.set(newValue, forKey: "macProject") }
    }
    var lastProject: String? {
        get { defaults.string(forKey: "project") }
        set { defaults.set(newValue, forKey: "project") }
    }
    /// Grab & Go: nil when off, else the project everything goes straight into.
    var grabGo: String? {
        get { let s = defaults.string(forKey: "grabGo") ?? ""; return s.isEmpty || s.lowercased() == "off" ? nil : s }   // "off": the old app's word for it
        set { defaults.set(newValue ?? "", forKey: "grabGo") }
    }
    var lastSent: Date? {
        get { defaults.object(forKey: "lastSent") as? Date }
        set { defaults.set(newValue, forKey: "lastSent") }
    }

    /// Every project name this phone knows: the Mac's, then ones made here or used by a grab.
    func projectNames(grabs: [Grab]? = nil) -> [String] {
        var names = projects.map(\.name)
        for g in (grabs ?? all()) where !names.contains(g.project) { names.append(g.project) }
        return names
    }

    // MARK: Previews

    /// A small JPEG of a still, a GIF's first frame, or a clip's frame at half a second — and its shape.
    static func preview(of url: URL, kind: GrabKind, max: Int) -> (Data?, Double?) {
        var cg: CGImage?
        if kind == .clip {
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: max, height: max)
            cg = (try? gen.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil))
            if cg == nil { cg = try? gen.copyCGImage(at: .zero, actualTime: nil) }
        } else if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
            cg = CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
        }
        guard let c = cg else { return (nil, nil) }
        let aspect = c.height > 0 ? Double(c.width) / Double(c.height) : nil
        return (UIImage(cgImage: c).jpegData(compressionQuality: 0.78), aspect)
    }

    static func stamp(_ prefix: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(f.string(from: Date()))"
    }
}

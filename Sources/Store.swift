// Needed Tools — the vault's list, kept in one place.
//
// Every tool used to hold its own copy of .vault/index.json and write it back,
// so one could wipe out what another had just added. Now there is one list,
// owned here, and every tool reads and writes through it. It is only read from
// disk again when another vault is chosen or the file changes behind our back.
// It is also where every picture gets its small preview and its colour palette,
// so nothing can come in without them.

import AppKit
import AVFoundation
import ImageIO

final class VaultStore {
    static let shared = VaultStore()

    var items: [[String: Any]] = []
    private(set) var loadedFor = ""                  // the vault folder the list belongs to
    private var stamp: Date? = nil                   // the file's date when we last read or wrote it
    var holdSaves = false                            // while a batch is going in: one write at the end

    var base: URL? { Shared.vault }
    var url: URL? { base?.appendingPathComponent(".vault/index.json") }

    private func fileDate() -> Date? {
        guard let u = url else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: u.path)[.modificationDate]) as? Date
    }

    /// The list as it is: read again only when the vault changed, or the file did.
    func load() {
        let here = base?.path ?? ""
        guard let u = url, FileManager.default.fileExists(atPath: u.path) else {
            if loadedFor != here { items = [] }
            loadedFor = here; stamp = nil
            return
        }
        let now = fileDate()
        if loadedFor == here && now == stamp { return }
        guard let d = try? Data(contentsOf: u), let list = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else {
            // Couldn't read it just now: keep what we have rather than show — and later save — an empty vault.
            if loadedFor != here { items = []; loadedFor = here }
            return
        }
        items = list
        loadedFor = here
        stamp = now
    }

    func save() {
        if holdSaves { return }
        guard let u = url else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: items, options: []) {
            if (try? d.write(to: u, options: .atomic)) != nil { stamp = fileDate(); loadedFor = base?.path ?? "" }
        }
    }

    // MARK: Adding one

    /// A new still, GIF, clip or idea: its preview and its colours are made
    /// here, whichever tool it came from.
    @discardableResult
    func register(kind: String, file: URL, meta: [String: Any]?, project: String) -> [String: Any] {
        if !holdSaves { load() }
        guard let base = base else { return [:] }
        let id = UUID().uuidString
        let rel = file.path.replacingOccurrences(of: base.path + "/", with: "")
        var thumbRel = rel
        if kind == "clip", let t = poster(for: file, id: id) {
            thumbRel = t.path.replacingOccurrences(of: base.path + "/", with: "")
        } else if kind == "still" || kind == "gif", let t = smallThumb(for: file, id: id) {
            thumbRel = t.path.replacingOccurrences(of: base.path + "/", with: "")   // the grid never loads the full file
        }
        var item: [String: Any] = ["id": id, "kind": kind, "file": rel, "thumb": thumbRel, "project": project]
        item["bytes"] = fileSize(file)
        item["created"] = ISO8601DateFormatter().string(from: Date())
        for key in ["source", "at", "end", "crop", "tags", "note", "w", "h", "palette", "boards", "title", "text", "origin"] {
            if let v = meta?[key] { item[key] = v }
        }
        if kind != "idea", (item["palette"] as? [String])?.isEmpty ?? true, let p = colours(of: base.appendingPathComponent(thumbRel), kind: kind) {
            item["palette"] = p
        }
        items.insert(item, at: 0)
        save()
        return item
    }

    func update(_ b: [String: Any]) {
        load()
        guard let id = b["id"] as? String, let i = items.firstIndex(where: { ($0["id"] as? String) == id }) else { return }
        for key in ["tags", "boards"] { if let v = b[key] as? [String] { items[i][key] = v } }
        for key in ["note", "title", "text"] { if let v = b[key] as? String { items[i][key] = v } }
        save()
    }

    /// Removing moves the file to the Trash, never deletes it outright.
    func remove(_ id: String) -> Bool {
        load()
        guard let base = base, let i = items.firstIndex(where: { ($0["id"] as? String) == id }) else { return false }
        let item = items[i]
        if let rel = item["file"] as? String {
            try? FileManager.default.trashItem(at: base.appendingPathComponent(rel), resultingItemURL: nil)
        }
        if let thumb = item["thumb"] as? String, thumb.hasPrefix(".vault/thumbs/") {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(thumb))
        }
        items.remove(at: i)
        save()
        return true
    }

    // MARK: Every picture has its colours

    private var paletteRunning = false
    private var paletteTried = Set<String>()         // ones that couldn't be read aren't retried until next launch

    /// Anything without a colour palette gets one, quietly, in the background:
    /// older items, and anything a tool saved before this existed. Only the list
    /// is looked at — never the folders.
    func fillMissingPalettes(done: (() -> Void)? = nil) {
        load()
        guard let base = base, !paletteRunning else { done?(); return }
        let todo: [(String, String, String)] = items.compactMap { (it: [String: Any]) -> (String, String, String)? in
            let kind = it["kind"] as? String ?? ""
            guard kind == "still" || kind == "gif" || kind == "clip", (it["palette"] as? [String])?.isEmpty ?? true,
                  let id = it["id"] as? String, !paletteTried.contains(id),
                  let rel = (it["thumb"] as? String) ?? (it["file"] as? String) else { return nil }
            return (id, rel, kind)
        }
        guard !todo.isEmpty else { done?(); return }
        paletteRunning = true
        DispatchQueue.global(qos: .utility).async {
            var found: [String: [String]] = [:]
            for (id, rel, kind) in todo {
                if let p = self.colours(of: base.appendingPathComponent(rel), kind: kind) { found[id] = p }
            }
            DispatchQueue.main.async {
                self.paletteRunning = false
                for (id, _, _) in todo { self.paletteTried.insert(id) }
                guard self.base == base else { done?(); return }
                self.load()
                var changed = false
                for i in self.items.indices {
                    if let id = self.items[i]["id"] as? String, let p = found[id], (self.items[i]["palette"] as? [String])?.isEmpty ?? true {
                        self.items[i]["palette"] = p
                        changed = true
                    }
                }
                if changed { self.save(); Shared.notify() }
                done?()
            }
        }
    }

    /// The colours of a still, a GIF's first frame, or a clip — from its preview,
    /// or, when a clip has none, from a frame of the clip itself.
    func colours(of url: URL, kind: String) -> [String]? {
        if let p = palette(of: url), !p.isEmpty { return p }
        let ext = url.pathExtension.lowercased()
        if kind == "clip" || ["mp4", "mov", "m4v", "webm"].contains(ext) {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 160, height: 160)
            for t in [0.5, 1.5, 0.05] {
                if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil),
                   let p = palette(ofImage: cg), !p.isEmpty { return p }
            }
        }
        return nil
    }

    func palette(of url: URL) -> [String]? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceThumbnailMaxPixelSize: 48] as CFDictionary) else { return nil }
        return palette(ofImage: img)
    }

    /// The colours a picture is made of: shrink it, group near-identical colours,
    /// keep the five that cover the most of it (skipping ones too close to another).
    func palette(ofImage source: CGImage) -> [String]? {
        let scale: Double = min(1, 48 / Double(max(source.width, source.height)))
        let w = max(1, Int(Double(source.width) * scale)), h = max(1, Int(Double(source.height) * scale))
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        var buckets: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let e = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (e.n + 1, e.r + r, e.g + g, e.b + b)
        }
        var out: [(Int, Int, Int)] = []
        for (_, e) in buckets.sorted(by: { $0.value.n > $1.value.n }) {
            let c = (e.r / e.n, e.g / e.n, e.b / e.n)
            if out.contains(where: { abs($0.0 - c.0) + abs($0.1 - c.1) + abs($0.2 - c.2) < 60 }) { continue }
            out.append(c)
            if out.count == 5 { break }
        }
        return out.map { String(format: "#%02x%02x%02x", $0.0, $0.1, $0.2) }
    }

    // MARK: Previews

    /// A small JPEG for the grid — ImageIO reads just enough of the file to make it.
    func smallThumb(for file: URL, id: String) -> URL? {
        guard let base = base, let src = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 520,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let dir = base.appendingPathComponent(".vault/thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(id + ".jpg")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? url : nil
    }

    /// A still from a clip, for the library grid. If the very start is black or
    /// unreadable, a moment later.
    func poster(for file: URL, id: String) -> URL? {
        guard let base = base else { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        var frame: CGImage? = nil
        for t in [0.1, 1.0] {
            if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) { frame = cg; break }
        }
        guard let cg = frame, let jpg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        let dir = base.appendingPathComponent(".vault/thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(id + ".jpg")
        return (try? jpg.write(to: url)) != nil ? url : nil
    }

    func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? -1
    }
}

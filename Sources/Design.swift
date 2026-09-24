// Needed Tools — Needed Design (Round 6).
// Mood boards and treatments from the Vault's stills: pages to export, not a
// presentation builder. A design is a small JSON file in the project —
// Lexus/Lexus_Design/Mood or /Treatments — saved as you go; ⌘S keeps a version.
// Export draws each page in an off-screen view of the same page you edit, so
// the PDF and the page images look exactly like the screen, fonts and all.

import AppKit
import WebKit
import PDFKit

enum Designs {
    static func folder(_ project: String, mode: String) -> URL? {
        Shared.vault?.appendingPathComponent(project, isDirectory: true)
            .appendingPathComponent("\(project)_Design/\(mode == "mood" ? "Mood" : "Treatments")", isDirectory: true)
    }
    static func url(_ rel: String) -> URL? {
        guard let base = Shared.vault, !rel.isEmpty, !rel.contains("..") else { return nil }
        return base.appendingPathComponent(rel)
    }
    static func rel(_ u: URL) -> String {
        guard let base = Shared.vault else { return u.path }
        return u.path.replacingOccurrences(of: base.path + "/", with: "")
    }
    static func clean(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        return String(s.prefix(80))
    }

    /// The project's designs, newest first — what the Designs menu lists.
    static func list(_ project: String) -> [[String: Any]] {
        var out: [[String: Any]] = []
        let iso = ISO8601DateFormatter()
        for mode in ["mood", "treatment"] {
            guard let dir = folder(project, mode: mode) else { continue }
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            for f in files where f.lastPathComponent.hasSuffix(".design.json") {
                guard let d = try? Data(contentsOf: f), let doc = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                let pages = (doc["pages"] as? [[String: Any]]) ?? []
                let cover = pages.lazy.compactMap { ($0["pics"] as? [[String: Any]])?.first?["thumb"] as? String }.first ?? ""
                let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                out.append(["rel": rel(f), "name": (doc["name"] as? String) ?? f.lastPathComponent.replacingOccurrences(of: ".design.json", with: ""),
                            "mode": mode, "pages": pages.count, "cover": cover, "updated": iso.string(from: date)])
            }
        }
        return out.sorted { ($0["updated"] as? String ?? "") > ($1["updated"] as? String ?? "") }
    }

    /// Saved as you go. A new design gets a file named after it.
    static func save(rel: String?, doc: [String: Any], project: String) -> [String: Any] {
        let mode = (doc["mode"] as? String) == "mood" ? "mood" : "treatment"
        var target: URL
        if let r = rel, let u = url(r) { target = u }
        else {
            guard let dir = folder(project, mode: mode) else { return ["ok": false, "error": "Choose your vault first"] }
            let typed = clean((doc["name"] as? String) ?? "")
            let name = typed.isEmpty ? (mode == "mood" ? "Mood board" : "Treatment") : typed
            target = dir.appendingPathComponent("\(name).design.json")
            var n = 2
            while FileManager.default.fileExists(atPath: target.path) { target = dir.appendingPathComponent("\(name) \(n).design.json"); n += 1 }
        }
        // A design switched between Mood and Treatment moves to that folder.
        if let dir = folder(project, mode: mode), target.deletingLastPathComponent().lastPathComponent != dir.lastPathComponent,
           target.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "\(project)_Design" {
            var moved = dir.appendingPathComponent(target.lastPathComponent)
            var n = 2
            while FileManager.default.fileExists(atPath: moved.path) {
                moved = dir.appendingPathComponent(target.lastPathComponent.replacingOccurrences(of: ".design.json", with: " \(n).design.json")); n += 1
            }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if (try? FileManager.default.moveItem(at: target, to: moved)) != nil { target = moved }
        }
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]),
              (try? d.write(to: target, options: .atomic)) != nil else { return ["ok": false, "error": "Couldn't save the design"] }
        return ["ok": true, "rel": Designs.rel(target)]
    }

    static func load(_ rel: String) -> [String: Any]? {
        guard let u = url(rel), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    /// The next version number for a design: from its kept versions and its exports.
    static func nextVersion(of name: String, in dir: URL) -> Int {
        var top = 0
        let scan = { (d: URL) in
            for f in (try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? [] {
                var stem = f.replacingOccurrences(of: ".design.json", with: "")
                stem = (stem as NSString).deletingPathExtension
                guard stem.lowercased().hasPrefix(name.lowercased() + " v"), let n = Int(stem.dropFirst(name.count + 2)) else { continue }
                top = max(top, n)
            }
        }
        scan(dir)
        scan(dir.appendingPathComponent("Versions", isDirectory: true))
        return top + 1
    }

    /// ⌘S: a copy of the design as it is now, kept as the next version.
    static func keepVersion(_ rel: String) -> [String: Any] {
        guard let u = url(rel), let doc = load(rel) else { return ["ok": false] }
        let dir = u.deletingLastPathComponent()
        let name = clean((doc["name"] as? String) ?? u.lastPathComponent.replacingOccurrences(of: ".design.json", with: ""))
        let n = nextVersion(of: name, in: dir)
        let versions = dir.appendingPathComponent("Versions", isDirectory: true)
        try? FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        let ok = (try? FileManager.default.copyItem(at: u, to: versions.appendingPathComponent("\(name) v\(n).design.json"))) != nil
        return ["ok": ok, "version": n]
    }

    /// Stills to design with: this project's, or the whole vault's, each with its shape and colours.
    /// Every photo in these files and folders — folders searched all the way down, in Finder's order.
    static func pictures(in urls: [URL]) -> [URL] {
        let fm = FileManager.default
        let usable: (URL) -> Bool = { u in
            let e = u.pathExtension.lowercased()
            return Shell.imageExt.contains(e)
        }
        var out: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                if usable(u) { out.append(u) }
                continue
            }
            guard let walk = fm.enumerator(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var found: [URL] = []
            for case let f as URL in walk where usable(f) { found.append(f) }
            found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            out.append(contentsOf: found)
        }
        return out
    }

    static func stills(scope: String, project: String, aspects: inout [String: Double]) -> [[String: Any]] {
        guard let base = Shared.vault else { return [] }
        VaultStore.shared.load()
        let all = VaultStore.shared.items.filter { (it: [String: Any]) -> Bool in
            let kind = (it["kind"] as? String) ?? ""
            guard kind == "still" || kind == "gif" else { return false }       // GIFs too: they play on the page
            return scope == "vault" || ((it["project"] as? String) ?? "Unsorted") == project
        }.sorted { ($0["created"] as? String ?? "") > ($1["created"] as? String ?? "") }
        var out: [[String: Any]] = []
        for it in all.prefix(2000) {
            guard let id = it["id"] as? String, let file = it["file"] as? String else { continue }
            let thumb = (it["thumb"] as? String) ?? file
            var a = 16.0 / 9.0
            if let w = (it["w"] as? NSNumber)?.doubleValue, let h = (it["h"] as? NSNumber)?.doubleValue, w > 0, h > 0 { a = w / h }
            else if let known = aspects[id] { a = known }
            else if let src = CGImageSourceCreateWithURL(base.appendingPathComponent(thumb) as CFURL, nil),
                    let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                    let w = p[kCGImagePropertyPixelWidth] as? Double, let h = p[kCGImagePropertyPixelHeight] as? Double, h > 0 {
                var r = w / h
                if let o = p[kCGImagePropertyOrientation] as? Int, o >= 5 { r = h / w }       // turned on its side
                a = r; aspects[id] = a
            }
            let src = it["source"] as? [String: Any]
            var row: [String: Any] = ["id": id, "file": file, "thumb": thumb, "a": a, "kind": (it["kind"] as? String) ?? "still"]
            row["palette"] = (it["palette"] as? [String]) ?? [String]()
            row["project"] = (it["project"] as? String) ?? "Unsorted"
            row["title"] = (src?["title"] as? String) ?? ""
            row["origin"] = Folders.origin(ofFile: file) ?? ((it["origin"] as? String) ?? "reference")
            row["tags"] = (it["tags"] as? [String]) ?? [String]()
            out.append(row)
        }
        return out
    }
}

// MARK: - Export: the same page, drawn off screen, one PDF page at a time

final class DesignRenderer: NSObject, WKNavigationDelegate {
    private var view: WKWebView?
    private var ready = false
    private var waiting: [() -> Void] = []
    var busy = false

    /// The off-screen page. It sits behind everything in the window: it has to be
    /// in a window for WebKit to draw it, and nobody ever sees it.
    private func make(in window: NSWindow, config: WKWebViewConfiguration) -> WKWebView {
        if let v = view { return v }
        let v = WKWebView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080), configuration: config)
        v.setValue(false, forKey: "drawsBackground")
        v.navigationDelegate = self
        window.contentView?.addSubview(v, positioned: .below, relativeTo: nil)
        if let u = URL(string: "\(toolsScheme)://app/design.html?render=1") { v.load(URLRequest(url: u)) }
        view = v
        return v
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        let w = waiting; waiting = []
        for f in w { f() }
    }

    struct Job {
        let doc: [String: Any]
        let pages: [Int]
        let width: Int, height: Int
        let pdf: URL?
        let images: URL?
        let mark: Bool
    }

    func run(_ job: Job, window: NSWindow, config: WKWebViewConfiguration, progress: @escaping (Double) -> Void, done: @escaping ([String: Any]) -> Void) {
        busy = true
        let v = make(in: window, config: config)
        v.frame = NSRect(x: 0, y: 0, width: job.width, height: job.height)
        let start = { self.page(0, job: job, view: v, pdf: PDFDocument(), images: 0, progress: progress, done: done) }
        if ready { start() } else { waiting.append(start) }
    }

    private func page(_ k: Int, job: Job, view: WKWebView, pdf: PDFDocument, images: Int, progress: @escaping (Double) -> Void, done: @escaping ([String: Any]) -> Void) {
        guard k < job.pages.count else {
            var out: [String: Any] = ["ok": true, "pages": job.pages.count, "images": images]
            if let u = job.pdf {
                if pdf.write(to: u) { out["pdf"] = Designs.rel(u) } else { out["ok"] = false; out["error"] = "Couldn't write the PDF" }
            }
            if let dir = job.images { out["folder"] = Designs.rel(dir) }
            busy = false
            return done(out)
        }
        let args: [String: Any] = ["doc": job.doc, "i": job.pages[k], "mark": job.mark]
        view.callAsyncJavaScript("return await window.__designRender(doc, i, mark)", arguments: args, in: nil, in: .page) { result in
            if case .failure = result { self.busy = false; return done(["ok": false, "error": "Couldn't draw page \(job.pages[k] + 1)"]) }
            let cfg = WKPDFConfiguration()
            cfg.rect = CGRect(x: 0, y: 0, width: job.width, height: job.height)
            view.createPDF(configuration: cfg) { made in
                guard case .success(let data) = made, let one = PDFDocument(data: data), let p = one.page(at: 0) else {
                    self.busy = false
                    return done(["ok": false, "error": "Couldn't draw page \(job.pages[k] + 1)"])
                }
                var n = images
                if job.pdf != nil { pdf.insert(p, at: pdf.pageCount) }
                if let dir = job.images, let jpg = DesignRenderer.jpeg(p, w: job.width, h: job.height) {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    if (try? jpg.write(to: dir.appendingPathComponent(String(format: "%02d.jpg", k + 1)), options: .atomic)) != nil { n += 1 }
                }
                progress(Double(k + 1) / Double(job.pages.count))
                self.page(k + 1, job: job, view: view, pdf: pdf, images: n, progress: progress, done: done)
            }
        }
    }

    /// A page image, from the PDF page — exactly what's in the PDF.
    static func jpeg(_ page: PDFPage, w: Int, h: Int) -> Data? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let box = page.bounds(for: .mediaBox)
        ctx.scaleBy(x: CGFloat(w) / max(1, box.width), y: CGFloat(h) / max(1, box.height))
        page.draw(with: .mediaBox, to: ctx)
        guard let img = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}

// MARK: - The page talks to the app here

extension Shell {
    func designAction(_ action: String, _ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) -> Bool {
        let project = Shared.project
        switch action {
        case "designList":
            reply(["designs": Designs.list(project), "project": project], nil)

        case "designLoad":
            guard let doc = Designs.load((body["rel"] as? String) ?? "") else { reply(["ok": false, "error": "Couldn't open that design"], nil); return true }
            reply(["ok": true, "doc": doc], nil)

        case "designSave":
            reply(Designs.save(rel: body["rel"] as? String, doc: (body["doc"] as? [String: Any]) ?? [:], project: project), nil)

        case "designVersion":
            reply(Designs.keepVersion((body["rel"] as? String) ?? ""), nil)

        case "designRename":
            // The file follows the name; exports already made keep theirs.
            guard let rel = body["rel"] as? String, let u = Designs.url(rel) else { reply(["ok": false], nil); return true }
            let name = Designs.clean((body["name"] as? String) ?? "")
            guard !name.isEmpty else { reply(["ok": false], nil); return true }
            let to = u.deletingLastPathComponent().appendingPathComponent("\(name).design.json")
            if to.path == u.path { reply(["ok": true, "rel": rel], nil); return true }
            guard !FileManager.default.fileExists(atPath: to.path) else { reply(["ok": false, "error": "There's already a design called \(name)"], nil); return true }
            let ok = (try? FileManager.default.moveItem(at: u, to: to)) != nil
            reply(["ok": ok, "rel": ok ? Designs.rel(to) : rel], nil)

        case "designDelete":
            // To the Trash, never gone outright.
            if let u = Designs.url((body["rel"] as? String) ?? "") { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
            reply(["ok": true, "designs": Designs.list(project)], nil)

        case "designStills":
            reply(["stills": Designs.stills(scope: (body["scope"] as? String) ?? "project", project: project, aspects: &designAspects)], nil)

        case "designFonts":
            // Every font on this Mac — Adobe Fonts you've turned on too — like Keynote.
            reply(["fonts": NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()], nil)

        case "designProject":
            // For a treatment's cover: the project's title, client and director.
            let o = ProjectFile.read(project)
            reply(["project": project, "title": (o["title"] as? String) ?? "", "client": (o["client"] as? String) ?? "",
                   "director": (o["director"] as? String) ?? "", "label": Labels.of(project)], nil)

        case "designExport":
            designExport(body, project: project, reply)

        case "designReveal":
            if let u = Designs.url((body["rel"] as? String) ?? "") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
            reply(["ok": true], nil)

        case "designAddPhotos":
            // + Photos: as many as you like — files, or whole folders of them.
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.message = "Choose photos — or whole folders of them — for \(project)"
            panel.prompt = "Bring them in"
            panel.beginSheetModal(for: window) { r in
                guard r == .OK else { return reply(["ok": false, "cancelled": true], nil) }
                let urls = panel.urls
                reply(["ok": true, "chosen": urls.count], nil)
                self.designImport(urls)
            }

        case "openDesign":
            // From the Vault or the project page: Needed Design, with these stills already placed.
            show("design")
            let ids = (body["ids"] as? [String]) ?? []
            let mode = (body["mode"] as? String) ?? "mood"
            if let v = designPage, let d = try? JSONSerialization.data(withJSONObject: ["mode": mode, "ids": ids]), let json = String(data: d, encoding: .utf8) {
                whenReady(v, "__designOpenWith", "window.__designOpenWith(\(json))")
            }
            reply(["ok": true], nil)

        default:
            return false
        }
        return true
    }

    /// Export: a new version every time — Lexus_Design/Treatments/Treatment v3.pdf, and
    /// its page images in "Treatment v3" beside it.
    func designExport(_ b: [String: Any], project: String, _ reply: @escaping (Any?, String?) -> Void) {
        guard Shared.vault != nil, let doc = b["doc"] as? [String: Any] else { return reply(["ok": false, "error": "Choose your vault first"], nil) }
        guard !designRenderer.busy else { return reply(["ok": false, "error": "Still exporting the last one"], nil) }
        let mode = (doc["mode"] as? String) == "mood" ? "mood" : "treatment"
        guard let dir = Designs.folder(project, mode: mode) else { return reply(["ok": false], nil) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = Designs.clean((doc["name"] as? String) ?? "").isEmpty ? (mode == "mood" ? "Mood board" : "Treatment") : Designs.clean((doc["name"] as? String) ?? "")
        let n = Designs.nextVersion(of: name, in: dir)
        let kind = (b["kind"] as? String) ?? "pdf"
        let pages = ((b["pages"] as? [NSNumber]) ?? []).map { $0.intValue }
        let w = max(200, min(4000, (b["width"] as? NSNumber)?.intValue ?? 1920))
        let h = max(200, min(4000, (b["height"] as? NSNumber)?.intValue ?? 1080))
        guard !pages.isEmpty else { return reply(["ok": false, "error": "No pages to export"], nil) }
        let job = DesignRenderer.Job(doc: doc, pages: pages, width: w, height: h,
                                     pdf: kind == "images" ? nil : dir.appendingPathComponent("\(name) v\(n).pdf"),
                                     images: kind == "pdf" ? nil : dir.appendingPathComponent("\(name) v\(n)", isDirectory: true),
                                     mark: (b["mark"] as? Bool) ?? true)
        let view = designPage
        view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.start(\(Shell.js("Exporting \(name) v\(n)")))", completionHandler: nil)
        designRenderer.run(job, window: window, config: designRenderConfig(), progress: { f in
            view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.set(\(f))", completionHandler: nil)
        }, done: { r in
            view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.done()", completionHandler: nil)
            var out = r
            out["version"] = n
            out["name"] = "\(name) v\(n)"
            if (r["ok"] as? Bool) == true {
                let what = kind == "both" ? "PDF and \(pages.count) page image\(pages.count == 1 ? "" : "s")" : kind == "images" ? "\(pages.count) page image\(pages.count == 1 ? "" : "s")" : "\(pages.count)-page PDF"
                Shell.post("\(name) v\(n) exported", "\(what), in \(project) › \(project)_Design.")
            }
            reply(out, nil)
        })
    }

    /// The off-screen page reads the vault the same way the page you edit does.
    func designRenderConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        let scheme = VaultSchemeHandler(root: resources.appendingPathComponent("shell"))
        scheme.vaultRoot = { Shared.vault }
        config.setURLSchemeHandler(scheme, forURLScheme: toolsScheme)
        return config
    }

    /// Pictures dropped on Needed Design — files or whole folders: into the project as references, then onto pages.
    func designDrop(_ urls: [URL]) {
        designImport(urls)
    }

    /// Photos in bulk: copied into <P>_Vault as references off the main thread, then added to the vault a few at a
    /// time (each gets its thumbnail and colours), with the progress bar going. The page places them when they're in.
    func designImport(_ urls: [URL]) {
        let project = Shared.project
        let files = Designs.pictures(in: urls)
        guard !files.isEmpty else {
            Shell.post("No photos there", "Nothing you chose was a photo Needed Design can use.")
            return
        }
        let v = vaultHost
        guard let stillsFolder = v.outputFolder("Stills", project: project, area: "References") else { return }
        let gifsFolder = v.outputFolder("GIFs", project: project, area: "References") ?? stillsFolder
        // Where each goes, planned first, so two photos with the same name each keep their own.
        var planned = Set<String>()
        var jobs: [(from: URL, to: URL)] = []
        for u in files {
            let folder = u.pathExtension.lowercased() == "gif" ? gifsFolder : stillsFolder
            var target = v.uniqueURL(in: folder, name: u.lastPathComponent)
            var n = 2
            while planned.contains(target.path) {
                let stem = u.deletingPathExtension().lastPathComponent
                let ext = u.pathExtension
                target = v.uniqueURL(in: folder, name: ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
                n += 1
            }
            planned.insert(target.path)
            jobs.append((from: u, to: target))
        }
        let view = designPage
        let total = jobs.count
        view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.start(\(Shell.js("Bringing in \(total) photo\(total == 1 ? "" : "s")")))", completionHandler: nil)
        let copyJobs = jobs
        DispatchQueue.global(qos: .userInitiated).async {
            var copied: [URL] = []
            for (i, j) in copyJobs.enumerated() {
                if (try? FileManager.default.copyItem(at: j.from, to: j.to)) != nil { copied.append(j.to) }
                if i % 10 == 9 {
                    let f = 0.4 * Double(i + 1) / Double(max(1, total))
                    DispatchQueue.main.async { view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.set(\(f))", completionHandler: nil) }
                }
            }
            let done = copied
            DispatchQueue.main.async { self.designRegister(done, project: project, total: total) }
        }
    }

    /// Into the vault, twelve at a time so the window keeps moving.
    func designRegister(_ files: [URL], project: String, total: Int) {
        let view = designPage
        var ids: [String] = []
        var at = 0
        VaultStore.shared.holdSaves = true
        VaultStore.shared.load()
        func finish() {
            VaultStore.shared.holdSaves = false
            VaultStore.shared.save()
            view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.done()", completionHandler: nil)
            let missed = total - ids.count
            guard !ids.isEmpty else {
                Shell.post("Couldn't bring them in", "None of the \(total) photos could be copied into \(project).")
                return
            }
            Shell.post("\(ids.count) photo\(ids.count == 1 ? "" : "s") in \(project)",
                       "In \(project)_Vault as references, with their colours" + (missed > 0 ? " — \(missed) couldn't be copied." : "."))
            let wanted = Set(ids)
            var rank: [String: Int] = [:]
            for (i, id) in ids.enumerated() { rank[id] = i }
            let all = Designs.stills(scope: "project", project: project, aspects: &self.designAspects)
            let picked = all.filter { wanted.contains(($0["id"] as? String) ?? "") }
            let key: ([String: Any]) -> Int = { rank[($0["id"] as? String) ?? ""] ?? 0 }
            let items = picked.sorted { key($0) < key($1) }
            if let d = try? JSONSerialization.data(withJSONObject: items), let json = String(data: d, encoding: .utf8) {
                view?.evaluateJavaScript("window.__designDropped && window.__designDropped(\(json))", completionHandler: nil)
            }
        }
        func step() {
            let end = min(files.count, at + 12)
            while at < end {
                let u = files[at]
                let meta: [String: Any] = ["source": ["type": "file", "title": u.deletingPathExtension().lastPathComponent], "origin": "reference"]
                let kind = u.pathExtension.lowercased() == "gif" ? "gif" : "still"
                if let id = VaultStore.shared.register(kind: kind, file: u, meta: meta, project: project)["id"] as? String { ids.append(id) }
                at += 1
            }
            let f = 0.4 + 0.6 * Double(at) / Double(max(1, files.count))
            view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.set(\(f))", completionHandler: nil)
            if at < files.count {
                DispatchQueue.main.async { step() }
            } else {
                finish()
            }
        }
        step()
    }
}

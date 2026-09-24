// Needed Sort — native macOS shell.
// This Was Needed · thiswasneeded.info
//
// One file, no packages. Wraps the self-contained web app in a real Mac
// window. The only network request is licence activation, once.
//
// Build:  swiftc -O -target arm64-apple-macos11.3 -o nc-arm64 main.swift licence.swift
//         swiftc -O -target x86_64-apple-macos11.3 -o nc-x64 main.swift licence.swift
//         lipo -create -output "Needed Sort" nc-arm64 nc-x64

import AppKit
import WebKit
import AVFoundation
import ImageIO
import CryptoKit
import QuickLookThumbnailing

let sortScheme = "neededsort"
let sortPageBackground = NSColor(srgbRed: 0xF4 / 255.0, green: 0xF3 / 255.0,
                             blue: 0xF1 / 255.0, alpha: 1)

// MARK: - Serving the app

/// Serves the bundle's Resources over a private scheme.
///
/// Not file:// — a page loaded from file:// has a null origin, and WebKit
/// refuses localStorage on a null origin. The crew memory would seem to
/// work and then be empty on every relaunch. A custom scheme gives the page
/// a stable origin, so storage survives relaunches and app updates.
final class SortSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    /// The vault folder, so the page can show what's in it: /vault/... paths.
    var vaultRoot: () -> URL? = { nil }

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return fail(task) }

        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        var base = root
        if path.hasPrefix("/vault/"), let vault = vaultRoot() {
            base = vault.standardizedFileURL.resolvingSymlinksInPath()
            path = String(path.dropFirst("/vault".count))
        }
        let target = base
            .appendingPathComponent(String(path.dropFirst()))
            .standardizedFileURL
            .resolvingSymlinksInPath()

        // Path-traversal guard: whatever was asked for must still sit
        // inside Resources (or the vault) once resolved.
        guard target.path.hasPrefix(base.path + "/"),
              let data = try? Data(contentsOf: target) else { return fail(task) }

        let headers = [
            "Content-Type": mimeType(target.pathExtension),
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ]
        guard let response = HTTPURLResponse(url: url, statusCode: 200,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: headers) else { return fail(task) }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func fail(_ task: WKURLSchemeTask) {
        task.didFailWithError(NSError(domain: NSURLErrorDomain,
                                      code: NSURLErrorFileDoesNotExist))
    }

    private func mimeType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js":   return "text/javascript; charset=utf-8"
        case "css":  return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "png":  return "image/png"
        case "svg":  return "image/svg+xml"
        case "woff2": return "font/woff2"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":  return "image/gif"
        case "mp4", "m4v": return "video/mp4"
        case "mov":  return "video/quicktime"
        default:     return "application/octet-stream"
        }
    }
}

// MARK: - App

final class SortHost: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
    var window: NSWindow { webView?.window ?? NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }
    var webView: WKWebView!
    var licence: Licence!
    private var downloads: [ObjectIdentifier: URL] = [:]

    /// The original film on disk. GIFs and clips are made from this file
    /// directly, not from the copy the page plays, so they're full quality.
    private var currentFilm: URL?
    private var lastPicked: URL?
    private var currentExport: AVAssetExportSession?
    var jobProgress: Double = 0
    private var lastOutput: URL?                // the sub-folder written to most recently
    var jobLabel: String = ""                   // the file being read or copied right now
    var lastRoot: URL?                          // the project folder just built
    var currentProcess: Process?                // a running lookup or pull
    /// Where new things are filed inside the vault. Boards are labels that
    /// cut across projects; a project is the folder a file actually lives in.
    var currentProject: String { get { Shared.project } set { Shared.project = newValue } }
    // The vault's list lives in one place for the whole app (Store.swift).
    var index: [[String: Any]] {
        get { VaultStore.shared.items }
        set { VaultStore.shared.items = newValue }
    }
    var indexLoadedFor: String { VaultStore.shared.loadedFor }
    var downloadObservation: NSKeyValueObservation?
    var jobCancel = false

    /// Where stills are saved. Chosen by the person, remembered between launches.
    var saveFolder: URL? { get { Shared.vault } set { Shared.vault = newValue } }

    func start() {

        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(Shared.embedded)
        // The persistent store. The non-persistent one would wipe the crew
        // memory every time the app quits.
        config.websiteDataStore = .default()
        // Shot-finding and frame-rate detection play the film silently
        // without a click; WebKit blocks that unless it's allowed here.
        config.mediaTypesRequiringUserActionForPlayback = []
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        let scheme = SortSchemeHandler(root: resources.appendingPathComponent("tools/sort"))
        scheme.vaultRoot = { [weak self] in self?.saveFolder }
        config.setURLSchemeHandler(scheme, forURLScheme: sortScheme)

        // The page asks the app about the licence; the app does the checking.
        licence = Licence(resources: resources)
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page,
                                                             name: "licence")
        // A web page can't write into a folder on your Mac, so the app does:
        // it shows the folder picker and writes each still into that folder.
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page,
                                                             name: "files")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")   // no white flash


        if let start = URL(string: "\(sortScheme)://app/index.html") {
            webView.load(URLRequest(url: start))
        }
    }

    // A single-window tool: closing the window quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Menu
    // Without an Edit menu, ⌘C ⌘V ⌘X ⌘A ⌘Z are dead inside the web view —
    // which here means a call sheet can't be pasted in.

    private func buildMenu() {
        let bar = NSMenu()

        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Needed Sort",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Needed Sort",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others",
                                     action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Needed Sort",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        bar.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem()
        bar.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = bar
        NSApp.windowsMenu = windowMenu
    }

    // MARK: File picker
    // WKWebView won't show a picker by itself; without this, Choose File is inert.

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { result in
            if result == .OK { self.lastPicked = panel.urls.first }   // remember where the film is
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }

    // MARK: confirm() and alert()
    // Clear Memory uses confirm(); unimplemented, it never returns.

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    /// Asking for a name — a new project, a board. Without this, the page's
    /// prompts do nothing at all.
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    // MARK: Navigation and downloads
    // Export writes a blob and clicks <a download>. WKWebView drops that on
    // the floor unless it's turned into a download here.

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        if ["http", "https", "mailto"].contains(scheme) {
            // Stay inside the app. Links a person actually clicks open in
            // their browser; nothing is ever fetched from here.
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        if scheme == "file" {
            // A file dropped outside the drop zone must not replace the app.
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let fm = FileManager.default
        let folder = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser
        let name = suggestedFilename.isEmpty ? "vault-export" : suggestedFilename
        let first = folder.appendingPathComponent(name)
        let stem = first.deletingPathExtension().lastPathComponent
        let ext = first.pathExtension

        var dest = first
        var n = 1
        while fm.fileExists(atPath: dest.path) {
            let numbered = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            dest = folder.appendingPathComponent(numbered)
            n += 1
        }
        downloads[ObjectIdentifier(download)] = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = downloads.removeValue(forKey: ObjectIdentifier(download)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
    }
}

// MARK: - Licence bridge

extension SortHost: WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return replyHandler(nil, "bad request")
        }
        if message.name == "files" { return handleFiles(action, body, replyHandler) }
        switch action {
        case "status":
            replyHandler(licence.status(), nil)
        case "activate":
            licence.activate((body["key"] as? String) ?? "") { replyHandler($0, nil) }
        case "deactivate":
            licence.deactivate { replyHandler($0, nil) }
        default:
            replyHandler(nil, "unknown action")
        }
    }
}

// MARK: - Sorting

/// What kind of file this is on a card.
private let VIDEO_EXT: Set<String> = ["mov", "mp4", "mxf", "braw", "r3d", "avi", "mts", "m2ts", "mkv", "crm", "cine", "dng", "ari", "m4v"]
private let AUDIO_EXT: Set<String> = ["wav", "aif", "aiff", "bwf", "flac", "mp3", "m4a"]
private let STILL_EXT: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "cr2", "cr3", "arw", "nef", "raf", "heic"]
private let JUNK: Set<String> = [".ds_store", "thumbs.db", ".spotlight-v100", ".fseventsd", ".trashes", "desktop.ini"]

extension SortHost {
    func handleFiles(_ action: String, _ body: [String: Any],
                     _ reply: @escaping (Any?, String?) -> Void) {
        switch action {
        case "chooseCards":
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = true
            panel.prompt = "Add"
            panel.message = "Choose the card, or the folder you copied it into"
            if FileManager.default.fileExists(atPath: "/Volumes") { panel.directoryURL = URL(fileURLWithPath: "/Volumes") }
            panel.beginSheetModal(for: window) { r in
                reply(["paths": r == .OK ? panel.urls.map { $0.path } : []], nil)
            }

        case "chooseDest":
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Save Here"
            panel.message = "Where should the project folder go?"
            if let last = UserDefaults.standard.string(forKey: "dest") { panel.directoryURL = URL(fileURLWithPath: last) }
            panel.beginSheetModal(for: window) { r in
                if r == .OK, let url = panel.url { UserDefaults.standard.set(url.path, forKey: "dest") }
                reply(["path": r == .OK ? (panel.url?.path ?? "") : ""], nil)
            }

        case "defaults":
            reply(["dest": UserDefaults.standard.string(forKey: "dest") ?? "",
                   "structure": loadStructure() ?? NSNull(),
                   "ffprobe": ffprobePath != nil], nil)

        case "saveStructure":
            if let st = body["structure"], let data = try? JSONSerialization.data(withJSONObject: st, options: [.prettyPrinted]) {
                try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
                try? data.write(to: supportDir.appendingPathComponent("structure.json"), options: .atomic)
            }
            reply(["ok": true], nil)

        case "scan":      scan(body, reply)
        case "thumb":     thumb(body, reply)
        case "build":     build(body, reply)
        case "progress":  reply(["progress": jobProgress, "label": jobLabel], nil)
        case "cancelJob": jobCancel = true; reply(["ok": true], nil)
        case "reveal":
            if let root = lastRoot { NSWorkspace.shared.activateFileViewerSelecting([root]) }
            reply(["ok": true], nil)
        default:
            reply(nil, "unknown action")
        }
    }

    var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("NeededSort", isDirectory: true)
    }
    func loadStructure() -> Any? {
        guard let d = try? Data(contentsOf: supportDir.appendingPathComponent("structure.json")) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    /// The ffprobe inside the app, matched to this Mac's chip.
    var ffprobePath: String? {
        guard let bin = Bundle.main.resourceURL?.appendingPathComponent("bin") else { return nil }
        #if arch(arm64)
        let name = "ffprobe-arm64"
        #else
        let name = "ffprobe-x86_64"
        #endif
        let path = bin.appendingPathComponent(name).path
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: Reading when each clip was recorded

    private func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        for opts: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]] {
            let f = ISO8601DateFormatter(); f.formatOptions = opts
            if let d = f.date(from: s.replacingOccurrences(of: " ", with: "T")) { return d }
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current                  // no zone written: it's the camera's local time
        for p in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
                  "yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd", "yyyy:MM:dd"] {
            f.dateFormat = p
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Recording time and length, from the most trustworthy place available:
    /// the camera's own metadata (via ffprobe, then Apple's reader), then a
    /// camera sidecar file, then — last resort — the file's date.
    private func probe(_ url: URL, family: [URL], ffprobe: String?) -> (Date, Double, String) {
        var start: Date? = nil, dur = 0.0
        if let ffprobe = ffprobe {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffprobe)
            p.arguments = ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", url.path]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            if (try? p.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    var tags: [String: String] = [:]
                    let fmt = json["format"] as? [String: Any] ?? [:]
                    (fmt["tags"] as? [String: Any] ?? [:]).forEach { tags[$0.key.lowercased()] = "\($0.value)" }
                    for st in (json["streams"] as? [[String: Any]] ?? []) {
                        (st["tags"] as? [String: Any] ?? [:]).forEach { if tags[$0.key.lowercased()] == nil { tags[$0.key.lowercased()] = "\($0.value)" } }
                    }
                    for k in ["com.apple.quicktime.creationdate", "creation_time", "date", "date_recorded", "originationdate"] {
                        if let v = tags[k], let d = parseDate(v) { start = d; break }
                    }
                    if start == nil, let od = tags["originationdate"], let ot = tags["originationtime"] {
                        start = parseDate("\(od)T\(ot.replacingOccurrences(of: ":", with: ":"))")
                    }
                    dur = Double("\(fmt["duration"] ?? "0")") ?? 0
                }
            }
        }
        if start == nil || dur == 0 {
            let asset = AVURLAsset(url: url)
            if start == nil, let d = asset.creationDate?.dateValue { start = d }
            if dur == 0 { let s = CMTimeGetSeconds(asset.duration); if s.isFinite { dur = s } }
        }
        if let s = start { return (s, dur, "metadata") }
        // Sony and others write the recording time into a small XML beside the clip.
        for side in family where side.pathExtension.lowercased() == "xml" {
            if let text = try? String(contentsOf: side, encoding: .utf8),
               let r = text.range(of: #"CreationDate value="([^"]+)""#, options: .regularExpression) {
                let v = String(text[r]).replacingOccurrences(of: "CreationDate value=\"", with: "").replacingOccurrences(of: "\"", with: "")
                if let d = parseDate(v) { return (d, dur, "sidecar") }
            }
        }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return (mtime, dur, "file")
    }

    // MARK: Scanning cards

    func scan(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        let sources = ((body["sources"] as? [String]) ?? []).map { URL(fileURLWithPath: $0) }
        jobCancel = false; jobProgress = 0; jobLabel = "Reading the cards"
        let ffprobe = ffprobePath
        DispatchQueue.global(qos: .userInitiated).async {
            var media: [(URL, String, URL)] = [], loose: [(URL, String, URL)] = []   // file, card, card root
            for src in sources {
                guard let walk = FileManager.default.enumerator(at: src, includingPropertiesForKeys: [.isRegularFileKey],
                                                                options: [.skipsHiddenFiles]) else { continue }
                for case let f as URL in walk {
                    if self.jobCancel { break }
                    guard (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                    if JUNK.contains(f.lastPathComponent.lowercased()) || f.lastPathComponent.hasPrefix("._") { continue }
                    let ext = f.pathExtension.lowercased()
                    if VIDEO_EXT.contains(ext) || AUDIO_EXT.contains(ext) { media.append((f, src.lastPathComponent, src)) }
                    else { loose.append((f, src.lastPathComponent, src)) }
                }
            }

            // Sidecars belong to the clip whose name they start with, in the same
            // folder — longest name wins, so C0001M01.XML goes to C0001.
            var byDir: [URL: [URL]] = [:]
            for (m, _, _) in media { byDir[m.deletingLastPathComponent(), default: []].append(m) }
            for k in byDir.keys { byDir[k]!.sort { $0.deletingPathExtension().lastPathComponent.count > $1.deletingPathExtension().lastPathComponent.count } }
            var family: [URL: [URL]] = [:]
            var stills: [[String: Any]] = [], extras: [[String: Any]] = []
            for (f, card, root) in loose {
                let stem = f.deletingPathExtension().lastPathComponent.lowercased()
                if let owner = byDir[f.deletingLastPathComponent()]?.first(where: { stem.hasPrefix($0.deletingPathExtension().lastPathComponent.lowercased()) }) {
                    family[owner, default: []].append(f); continue
                }
                let rel = f.path.replacingOccurrences(of: root.path + "/", with: "")
                let rec: [String: Any] = ["path": f.path, "name": f.lastPathComponent, "card": card, "rel": rel, "size": self.fileSize(f)]
                if STILL_EXT.contains(f.pathExtension.lowercased()) { stills.append(rec) } else { extras.append(rec) }
            }

            // Read every clip's recording time, several at once.
            var clips = [[String: Any]](repeating: [:], count: media.count)
            let lock = NSLock(); var done = 0
            DispatchQueue.concurrentPerform(iterations: media.count) { i in
                if self.jobCancel { return }
                let (url, card, _) = media[i]
                let fam = family[url] ?? []
                let (start, dur, how) = self.probe(url, family: fam, ffprobe: ffprobe)
                let rec: [String: Any] = [
                    "id": i, "path": url.path, "name": url.lastPathComponent, "card": card,
                    "kind": AUDIO_EXT.contains(url.pathExtension.lowercased()) ? "audio" : "video",
                    "start": start.timeIntervalSince1970 * 1000, "dur": dur, "source": how, "size": self.fileSize(url),
                    "family": fam.map { ["path": $0.path, "name": $0.lastPathComponent, "size": self.fileSize($0)] },
                ]
                lock.lock(); clips[i] = rec; done += 1
                self.jobProgress = Double(done) / Double(max(1, media.count)); self.jobLabel = url.lastPathComponent
                lock.unlock()
            }
            DispatchQueue.main.async {
                if self.jobCancel { return reply(["ok": false, "cancelled": true], nil) }
                reply(["ok": true, "clips": clips.filter { !$0.isEmpty }, "stills": stills, "extras": extras,
                       "ffprobe": ffprobe != nil], nil)
            }
        }
    }

    // MARK: Thumbnails

    func thumb(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        let url = URL(fileURLWithPath: (body["path"] as? String) ?? "")
        let fam = ((body["family"] as? [String]) ?? []).map { URL(fileURLWithPath: $0) }
        let dur = (body["dur"] as? NSNumber)?.doubleValue ?? 0
        DispatchQueue.global(qos: .utility).async {
            let finish: (CGImage?) -> Void = { cg in
                guard let cg = cg, let jpg = NSBitmapImageRep(cgImage: cg)
                        .representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
                    return DispatchQueue.main.async { reply(["ok": false], nil) }
                }
                DispatchQueue.main.async { reply(["ok": true, "data": jpg.base64EncodedString()], nil) }
            }
            // 1. the camera's own thumbnail, if it wrote one — exactly what it saw
            if let side = fam.first(where: { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }),
               let img = NSImage(contentsOf: side), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return finish(cg)
            }
            // 2. Apple's reader, a moment in
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 360, height: 360)
            if let cg = try? gen.copyCGImage(at: CMTime(seconds: min(1.0, max(0, dur * 0.1)), preferredTimescale: 600), actualTime: nil) {
                return finish(cg)
            }
            // 3. Quick Look, which knows RAW formats when the camera maker's plug-in is installed
            let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 360, height: 360), scale: 1, representationTypes: .thumbnail)
            let wait = DispatchSemaphore(value: 0); var got: CGImage? = nil
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in got = rep?.cgImage; wait.signal() }
            _ = wait.wait(timeout: .now() + 6)
            finish(got)
        }
    }

    // MARK: Copying, and checking every copy

    /// Copy one file, hashing as it goes, then read the copy back from disk
    /// (not from memory) and check it matches. Returns true only if it does.
    private func copyVerified(_ src: URL, to dst: URL, progress: (Int) -> Void) -> Bool {
        guard let input = FileHandle(forReadingAtPath: src.path) else { return false }
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        guard let output = FileHandle(forWritingAtPath: dst.path) else { try? input.close(); return false }
        var hash = SHA256()
        let chunk = 8 * 1024 * 1024
        while true {
            if jobCancel { try? input.close(); try? output.close(); try? FileManager.default.removeItem(at: dst); return false }
            let data = input.readData(ofLength: chunk)
            if data.isEmpty { break }
            output.write(data)
            hash.update(data: data)
            progress(data.count)
        }
        try? input.close()
        try? output.synchronize()
        try? output.close()
        let want = hash.finalize()

        // Read it back, skipping the cache, so what's checked is what's on the drive.
        guard let back = FileHandle(forReadingAtPath: dst.path) else { return false }
        _ = fcntl(back.fileDescriptor, F_NOCACHE, 1)
        var check = SHA256()
        while true {
            if jobCancel { try? back.close(); try? FileManager.default.removeItem(at: dst); return false }
            let data = back.readData(ofLength: chunk)
            if data.isEmpty { break }
            check.update(data: data)
            progress(data.count)
        }
        try? back.close()
        // keep the card's dates on the copy, as editors expect
        if let attrs = try? FileManager.default.attributesOfItem(atPath: src.path) {
            var keep: [FileAttributeKey: Any] = [:]
            if let m = attrs[.modificationDate] { keep[.modificationDate] = m }
            if let c = attrs[.creationDate] { keep[.creationDate] = c }
            try? FileManager.default.setAttributes(keep, ofItemAtPath: dst.path)
        }
        return check.finalize() == want
    }

    /// Never overwrite: two cards can hold the same file name.
    private func unique(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let stem = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 1
        while true {
            let c = url.deletingLastPathComponent().appendingPathComponent(ext.isEmpty ? "\(stem)_\(n)" : "\(stem)_\(n).\(ext)")
            if !FileManager.default.fileExists(atPath: c.path) { return c }
            n += 1
        }
    }

    private func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
         .trimmingCharacters(in: .whitespaces)
    }

    func build(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard let destPath = body["dest"] as? String, !destPath.isEmpty else {
            return reply(["ok": false, "error": "Choose where to save it"], nil)
        }
        let project = clean((body["name"] as? String) ?? "")
        let root = URL(fileURLWithPath: destPath).appendingPathComponent(project.isEmpty ? "Needed Sort" : project, isDirectory: true)
        let st = body["structure"] as? [String: Any] ?? [:]
        let scenes = body["scenes"] as? [[String: Any]] ?? []
        let stills = body["stills"] as? [[String: Any]] ?? []
        let extras = body["extras"] as? [[String: Any]] ?? []
        jobCancel = false; jobProgress = 0; jobLabel = ""
        lastRoot = root

        DispatchQueue.global(qos: .userInitiated).async {
            // The folders, numbered in order unless numbering is off.
            let number = (st["auto_number"] as? Bool) ?? true
            var roleFolder: [String: String] = [:], firstFolder: String? = nil
            let fm = FileManager.default
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
            for (i, f) in ((st["folders"] as? [[String: Any]]) ?? []).enumerated() {
                let raw = self.clean((f["name"] as? String) ?? "")
                if raw.isEmpty { continue }
                let name = number ? String(format: "%02d_%@", i + 1, raw) : raw
                try? fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
                for sub in (f["subs"] as? [String]) ?? [] where !self.clean(sub).isEmpty {
                    try? fm.createDirectory(at: root.appendingPathComponent(name).appendingPathComponent(self.clean(sub)), withIntermediateDirectories: true)
                }
                if firstFolder == nil { firstFolder = name }
                let role = (f["role"] as? String) ?? "none"
                if role != "none", roleFolder[role] == nil { roleFolder[role] = name }
            }
            let first = firstFolder ?? "01_FOOTAGE"
            try? fm.createDirectory(at: root.appendingPathComponent(first), withIntermediateDirectories: true)
            let FOOTAGE = roleFolder["footage"] ?? first
            let AUDIO = roleFolder["audio"] ?? FOOTAGE
            let STILLS = roleFolder["stills"] ?? FOOTAGE
            let EXTRAS = self.clean((st["extras_folder"] as? String) ?? "") .isEmpty ? "00_CARD_EXTRAS" : self.clean(st["extras_folder"] as! String)

            // Everything to copy, in order, and how much there is (each byte is
            // read twice: once to copy, once to check).
            struct Job { let src: URL; let dir: URL; let scene: String; let rec: [String: Any]; let note: String }
            var jobs: [Job] = []
            for sc in scenes {
                let name = self.clean((sc["name"] as? String) ?? "SCENE")
                for c in (sc["clips"] as? [[String: Any]]) ?? [] {
                    let kind = (c["kind"] as? String) ?? "video"
                    let dir = root.appendingPathComponent(kind == "audio" ? AUDIO : FOOTAGE).appendingPathComponent(name)
                    jobs.append(Job(src: URL(fileURLWithPath: c["path"] as? String ?? ""), dir: dir, scene: name, rec: c, note: (c["source"] as? String) ?? ""))
                    // sidecars sit next to their clip — Premiere only reads them there
                    for s in (c["family"] as? [String]) ?? [] {
                        jobs.append(Job(src: URL(fileURLWithPath: s), dir: dir, scene: name, rec: ["card": c["card"] ?? ""],
                                        note: "sidecar of " + ((c["name"] as? String) ?? "")))
                    }
                }
            }
            for s in stills {
                jobs.append(Job(src: URL(fileURLWithPath: s["path"] as? String ?? ""), dir: root.appendingPathComponent(STILLS), scene: "", rec: s, note: ""))
            }
            for e in extras {
                let rel = (e["rel"] as? String) ?? ((e["name"] as? String) ?? "")
                let dir = root.appendingPathComponent(EXTRAS).appendingPathComponent(self.clean((e["card"] as? String) ?? "card"))
                    .appendingPathComponent((rel as NSString).deletingLastPathComponent)
                jobs.append(Job(src: URL(fileURLWithPath: e["path"] as? String ?? ""), dir: dir, scene: "", rec: e, note: "kept from card"))
            }
            let total = Double(max(1, jobs.reduce(0) { $0 + Int(self.fileSize($1.src)) } * 2))
            var doneBytes = 0.0
            var rows: [[String]] = [], failed: [String] = [], copied = 0
            let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"

            for job in jobs {
                if self.jobCancel { break }
                try? fm.createDirectory(at: job.dir, withIntermediateDirectories: true)
                let dst = self.unique(job.dir.appendingPathComponent(job.src.lastPathComponent))
                self.jobLabel = job.src.lastPathComponent
                var ok = self.copyVerified(job.src, to: dst) { n in
                    doneBytes += Double(n); self.jobProgress = min(0.999, doneBytes / total)
                }
                if !ok && !self.jobCancel {                      // one more go before calling it a failure
                    try? fm.removeItem(at: dst)
                    ok = self.copyVerified(job.src, to: dst) { _ in }
                }
                if self.jobCancel { break }
                if ok { copied += 1 } else { failed.append(job.src.lastPathComponent); try? fm.removeItem(at: dst) }
                let start = (job.rec["start"] as? NSNumber).map { stamp.string(from: Date(timeIntervalSince1970: $0.doubleValue / 1000)) } ?? ""
                let dur = (job.rec["dur"] as? NSNumber).map { String(format: "%.2f", $0.doubleValue) } ?? ""
                rows.append([job.scene, start, dur, (job.rec["card"] as? String) ?? "", job.src.path,
                             ok ? dst.path.replacingOccurrences(of: root.path + "/", with: "") : "",
                             job.note == "metadata" ? "metadata" : job.note == "file" ? "file date" : job.note,
                             ok ? "yes" : "FAILED"])
            }

            // The manifest: every file, where it came from, where it went, and whether it checked out.
            let q: (String) -> String = { $0.contains(",") || $0.contains("\"") ? "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : $0 }
            let csv = (["scene,recorded,duration_s,card,original,sorted_to,timestamp_source,verified"] + rows.map { $0.map(q).joined(separator: ",") })
                .joined(separator: "\n") + "\n"
            try? csv.write(to: root.appendingPathComponent("_MANIFEST.csv"), atomically: true, encoding: .utf8)

            let cancelled = self.jobCancel
            DispatchQueue.main.async {
                self.jobProgress = 1
                reply(["ok": !cancelled && failed.isEmpty, "cancelled": cancelled, "copied": copied, "total": jobs.count,
                       "failed": failed, "root": root.path], nil)
            }
        }
    }

    func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }
}



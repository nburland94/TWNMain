// Needed Grab — native macOS shell.
// This Was Needed · thiswasneeded.info
//
// One file, no packages. Wraps the self-contained web app in a real Mac
// window. The only network request is licence activation, once.
//
// Build:  swiftc -O -target arm64-apple-macos11.3 -o nc-arm64 main.swift licence.swift
//         swiftc -O -target x86_64-apple-macos11.3 -o nc-x64 main.swift licence.swift
//         lipo -create -output "Needed Grab" nc-arm64 nc-x64

import AppKit
import WebKit
import AVFoundation
import ImageIO

let grabScheme = "neededgrab"
let grabPageBackground = NSColor(srgbRed: 0xF4 / 255.0, green: 0xF3 / 255.0,
                             blue: 0xF1 / 255.0, alpha: 1)

// MARK: - Serving the app

/// Serves the bundle's Resources over a private scheme.
///
/// Not file:// — a page loaded from file:// has a null origin, and WebKit
/// refuses localStorage on a null origin. The crew memory would seem to
/// work and then be empty on every relaunch. A custom scheme gives the page
/// a stable origin, so storage survives relaunches and app updates.
final class GrabSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    /// The vault folder, so the page can show what's in it: /vault/... paths.
    var vaultRoot: () -> URL? = { nil }
    static var film: URL?                      // the one film Home has handed to Grab
    // Files are read here, never on the main thread — a big still or a clip
    // read there freezes the window (the pinwheel).
    private let reader = DispatchQueue(label: "neededgrab.files", qos: .userInitiated, attributes: .concurrent)
    private var stopped = Set<ObjectIdentifier>()
    private let lock = NSLock()

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return fail(task) }

        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        var base = root, inVault = false
        if path.hasPrefix("/film/"), let film = GrabSchemeHandler.film {      // a film handed over from Home
            base = film.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            path = "/" + film.lastPathComponent
        }
        if path.hasPrefix("/vault/"), let vault = vaultRoot() {
            base = vault.standardizedFileURL.resolvingSymlinksInPath()
            path = String(path.dropFirst("/vault".count))
            inVault = true
        }
        let target = base
            .appendingPathComponent(String(path.dropFirst()))
            .standardizedFileURL
            .resolvingSymlinksInPath()

        // Path-traversal guard: whatever was asked for must still sit
        // inside Resources (or the vault) once resolved.
        guard target.path.hasPrefix(base.path + "/") else { return fail(task) }
        let asked = task.request.value(forHTTPHeaderField: "Range")
        let key = ObjectIdentifier(task)

        reader.async {
            guard let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value,
                  let handle = FileHandle(forReadingAtPath: target.path) else {
                return DispatchQueue.main.async { if self.live(key) { self.fail(task) }; self.forget(key) }
            }
            defer { try? handle.close() }
            // Video asks for ranges; answer in pieces so a clip never loads whole.
            var status = 200, from: Int64 = 0, to: Int64 = max(0, size - 1)
            if let r = asked, r.hasPrefix("bytes="), size > 0 {
                let parts = r.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
                if let a = parts.first.flatMap({ Int64($0) }) {
                    from = min(a, size - 1)
                    let b = parts.count > 1 ? Int64(parts[1]) : nil
                    to = min(size - 1, b ?? (from + 4 * 1024 * 1024 - 1))
                    status = 206
                }
            }
            try? handle.seek(toOffset: UInt64(from))
            let data = size > 0 ? handle.readData(ofLength: Int(to - from + 1)) : Data()
            var headers = [
                "Content-Type": self.mimeType(target.pathExtension),
                "Content-Length": String(data.count),
                "Accept-Ranges": "bytes",
                // vault files keep their names for life (thumbnails are by id), so let the window keep them
                "Cache-Control": inVault ? "private, max-age=86400" : "no-cache",
            ]
            if status == 206 { headers["Content-Range"] = "bytes \(from)-\(from + Int64(data.count) - 1)/\(size)" }
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                return DispatchQueue.main.async { if self.live(key) { self.fail(task) }; self.forget(key) }
            }
            DispatchQueue.main.async {
                guard self.live(key) else { self.forget(key); return }   // the page stopped wanting it
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
                self.forget(key)
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(task)); lock.unlock()
    }
    private func live(_ key: ObjectIdentifier) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !stopped.contains(key)
    }
    private func forget(_ key: ObjectIdentifier) {
        lock.lock(); stopped.remove(key); lock.unlock()
    }

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

final class GrabHost: NSObject, NSApplicationDelegate, NSWindowDelegate,
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
    private var jobProgress: Double = 0
    private var lastOutput: URL?                // the sub-folder written to most recently
    private var jobCancel = false

    /// Where stills are saved. Chosen by the person, remembered between launches.
    private var saveFolder: URL? { get { Shared.vault } set { Shared.vault = newValue } }

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
        config.setURLSchemeHandler(GrabSchemeHandler(root: resources.appendingPathComponent("tools/grab")), forURLScheme: grabScheme)

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


        if let start = URL(string: "\(grabScheme)://app/index.html") {
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
        appMenu.addItem(withTitle: "About Needed Grab",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Needed Grab",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others",
                                     action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Needed Grab",
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
        let name = suggestedFilename.isEmpty ? "stills.zip" : suggestedFilename
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

extension GrabHost: WKScriptMessageHandlerWithReply {
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

// MARK: - Saving stills

extension GrabHost {
    func handleFiles(_ action: String, _ body: [String: Any],
                     _ reply: @escaping (Any?, String?) -> Void) {
        switch action {
        case "folder":
            reply(["path": saveFolder?.path ?? "", "project": Shared.project], nil)

        case "setProject":
            Shared.project = projectName(body["name"] as? String)
            reply(["project": Shared.project], nil)

        case "projects":
            // the project folders already in the vault
            guard let base = saveFolder else { return reply(["projects": []], nil) }
            let names = ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey],
                                                                        options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .map { $0.lastPathComponent }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            reply(["projects": names], nil)

        case "chooseFolder":
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Use This Vault"
            panel.message = "Choose your Needed Vault folder"
            if let current = saveFolder { panel.directoryURL = current }
            panel.beginSheetModal(for: window) { result in
                if result == .OK, let url = panel.url {
                    self.saveFolder = url
                    UserDefaults.standard.set(url.path, forKey: "saveFolder")
                }
                reply(["path": self.saveFolder?.path ?? ""], nil)
            }

        case "saveFile":
            guard saveFolder != nil else {
                return reply(["ok": false, "error": "Choose a folder first"], nil)
            }
            guard let folder = outputFolder("Stills", project: body["project"] as? String) else {
                return reply(["ok": false, "error": "Couldn't create the Stills folder"], nil)
            }
            // Only ever a plain file name, written inside the chosen folder.
            let raw = (body["name"] as? String) ?? ""
            let name = raw.replacingOccurrences(of: "/", with: "_")
                          .replacingOccurrences(of: ":", with: "_")
            guard !name.isEmpty, !name.hasPrefix("."),
                  let data = Data(base64Encoded: (body["data"] as? String) ?? "") else {
                return reply(["ok": false, "error": "Couldn't save \(raw)"], nil)
            }
            let target = uniqueURL(in: folder, name: name)
            do {
                try data.write(to: target, options: .atomic)
                lastOutput = folder
                reply(["ok": true, "name": target.lastPathComponent], nil)
            } catch {
                reply(["ok": false,
                       "error": "Couldn't write to \(folder.lastPathComponent) — is it still there?"], nil)
            }

        case "film":
            // Match the film the page just opened to a real file: the one
            // picked in the open panel, or one dragged onto the window (the
            // drag pasteboard still holds it after the drop).
            let name = (body["name"] as? String) ?? ""
            let size = (body["size"] as? NSNumber)?.int64Value ?? -1
            var candidates: [URL] = []
            if let picked = lastPicked { candidates.append(picked) }
            if let dragged = NSPasteboard(name: .drag).readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
                candidates += dragged
            }
            currentFilm = candidates.first { url in
                url.lastPathComponent == name && (size < 0 || fileSize(url) == size)
            }
            reply(["ok": currentFilm != nil], nil)

        case "makeGif":
            makeGif(body, reply)

        case "makeClip":
            makeClip(body, reply)

        case "progress":
            reply(["progress": currentExport.map { Double($0.progress) } ?? jobProgress], nil)

        case "cancelJob":
            jobCancel = true
            currentExport?.cancelExport()
            reply(["ok": true], nil)

        case "reveal":
            if let folder = lastOutput ?? saveFolder { NSWorkspace.shared.open(folder) }
            reply(["ok": true], nil)

        default:
            reply(nil, "unknown action")
        }
    }
}

// MARK: - GIFs and clips

extension GrabHost {
    func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// The project folder's name, made safe: no slashes, no hidden-file dot.
    func projectName(_ raw: String?) -> String {
        var n = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        while n.hasPrefix(".") { n.removeFirst() }
        if n.count > 80 { n = String(n.prefix(80)) }
        return n.isEmpty ? "Needed Grab" : n
    }

    /// Vault › project › Grabs › Stills, GIFs or Motion — each made the first
    /// time something goes in it. (The Vault's own saves go in References.)
    func outputFolder(_ kind: String, project: String?) -> URL? {
        guard let base = saveFolder else { return nil }
        let folder = base.appendingPathComponent(projectName(project), isDirectory: true)
                         .appendingPathComponent("Grabs", isDirectory: true)
                         .appendingPathComponent(kind, isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { return nil }
        return folder
    }

    /// A file in the folder that doesn't exist yet: "name 2.ext" and so on.
    func uniqueURL(in folder: URL, name: String) -> URL {
        var target = folder.appendingPathComponent(name)
        let stem = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return target
    }

    private func number(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }

    /// The crop (in the film's own pixels) and the size to render it at.
    private func geometry(_ b: [String: Any], even: Bool) -> (CGRect, CGSize) {
        let r = b["rect"] as? [String: Any] ?? [:]
        let o = b["out"] as? [String: Any] ?? [:]
        let crop = CGRect(x: number(r["x"]), y: number(r["y"]),
                          width: max(2, number(r["w"])), height: max(2, number(r["h"]))).integral
        var w = max(2, number(o["w"]).rounded()), h = max(2, number(o["h"]).rounded())
        if even { w -= w.truncatingRemainder(dividingBy: 2); h -= h.truncatingRemainder(dividingBy: 2) }
        return (crop, CGSize(width: w, height: h))
    }

    private func safeName(_ raw: String) -> String? {
        let name = raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return name.isEmpty || name.hasPrefix(".") ? nil : name
    }

    // MARK: GIF — frames pulled from the original file, looping forever

    func makeGif(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard let film = currentFilm else {
            return reply(["ok": false, "error": "Open the film with Choose film first"], nil)
        }
        guard saveFolder != nil else { return reply(["ok": false, "error": "Choose a folder first"], nil) }
        guard let folder = outputFolder("GIFs", project: b["project"] as? String) else {
            return reply(["ok": false, "error": "Couldn't create the GIFs folder"], nil)
        }
        guard let name = safeName((b["name"] as? String) ?? "") else {
            return reply(["ok": false, "error": "Bad file name"], nil)
        }
        let start = number(b["start"]), end = number(b["end"])
        let fps = min(30, max(4, number(b["fps"])))
        let (crop, out) = geometry(b, even: false)
        let url = uniqueURL(in: folder, name: name)
        jobCancel = false
        jobProgress = 0

        DispatchQueue.global(qos: .userInitiated).async {
            let finish: ([String: Any]) -> Void = { result in DispatchQueue.main.async { reply(result, nil) } }
            let asset = AVURLAsset(url: film)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero

            let count = max(1, Int(((end - start) * fps).rounded()))
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString,
                                                             count, nil),
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else {
                return finish(["ok": false, "error": "Couldn't create the GIF"])
            }
            let loop = [kCGImagePropertyGIFDictionary as String:
                        [kCGImagePropertyGIFLoopCount as String: 0]]          // 0 = loop forever
            CGImageDestinationSetProperties(dest, loop as CFDictionary)
            let delay = 1.0 / fps
            let frameProps = [kCGImagePropertyGIFDictionary as String:
                              [kCGImagePropertyGIFDelayTime as String: delay,
                               kCGImagePropertyGIFUnclampedDelayTime as String: delay]] as CFDictionary

            var last: CGImage?
            for i in 0..<count {
                if self.jobCancel { break }
                let t = CMTime(seconds: start + Double(i) / fps, preferredTimescale: 6000)
                var frame: CGImage? = nil
                if let img = try? gen.copyCGImage(at: t, actualTime: nil),
                   let cut = img.cropping(to: crop.intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))),
                   let ctx = CGContext(data: nil, width: Int(out.width), height: Int(out.height),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
                    ctx.interpolationQuality = .high
                    ctx.draw(cut, in: CGRect(origin: .zero, size: out))
                    frame = ctx.makeImage()
                }
                // Every slot must be filled; if a frame can't be read, repeat the last one.
                if let f = frame ?? last {
                    CGImageDestinationAddImage(dest, f, frameProps)
                    last = f
                }
                self.jobProgress = Double(i + 1) / Double(count)
            }
            if self.jobCancel || last == nil {
                try? FileManager.default.removeItem(at: url)
                return finish(["ok": false, "cancelled": self.jobCancel,
                               "error": self.jobCancel ? "Stopped" : "Couldn't read frames from the film"])
            }
            guard CGImageDestinationFinalize(dest) else {
                try? FileManager.default.removeItem(at: url)
                return finish(["ok": false, "error": "Couldn't finish the GIF"])
            }
            DispatchQueue.main.async { self.lastOutput = folder }
            finish(["ok": true, "name": url.lastPathComponent, "bytes": self.fileSize(url)])
        }
    }

    // MARK: MP4 — cut, cropped and re-encoded by AVFoundation, with sound

    func makeClip(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard let film = currentFilm else {
            return reply(["ok": false, "error": "Open the film with Choose film first"], nil)
        }
        guard saveFolder != nil else { return reply(["ok": false, "error": "Choose a folder first"], nil) }
        guard let folder = outputFolder("Motion", project: b["project"] as? String) else {
            return reply(["ok": false, "error": "Couldn't create the Motion folder"], nil)
        }
        guard let name = safeName((b["name"] as? String) ?? "") else {
            return reply(["ok": false, "error": "Bad file name"], nil)
        }
        let asset = AVURLAsset(url: film)
        guard let source = asset.tracks(withMediaType: .video).first else {
            return reply(["ok": false, "error": "No video in that file"], nil)
        }
        let range = CMTimeRange(start: CMTime(seconds: number(b["start"]), preferredTimescale: 6000),
                                end: CMTime(seconds: number(b["end"]), preferredTimescale: 6000))
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video,
                                                      preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return reply(["ok": false, "error": "Couldn't set up the clip"], nil)
        }
        do {
            try video.insertTimeRange(range, of: source, at: .zero)
            if (b["audio"] as? Bool) ?? true {
                for track in asset.tracks(withMediaType: .audio) {
                    if let sound = composition.addMutableTrack(withMediaType: .audio,
                                                               preferredTrackID: kCMPersistentTrackID_Invalid) {
                        try sound.insertTimeRange(range, of: track, at: .zero)
                    }
                }
            }
        } catch {
            return reply(["ok": false, "error": "Couldn't cut that range from the film"], nil)
        }

        let (crop, out) = geometry(b, even: true)                // H.264 wants even sizes
        let transform = source.preferredTransform
            .concatenating(CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .concatenating(CGAffineTransform(scaleX: out.width / crop.width, y: out.height / crop.height))
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = out
        videoComposition.instructions = [instruction]
        let rate = source.nominalFrameRate > 0 ? Double(source.nominalFrameRate) : 25
        videoComposition.frameDuration = CMTime(value: 1000, timescale: CMTimeScale((rate * 1000).rounded()))

        let preset = (b["codec"] as? String) == "hevc"
            ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let export = AVAssetExportSession(asset: composition, presetName: preset) else {
            return reply(["ok": false, "error": "This Mac can't export that combination"], nil)
        }
        let url = uniqueURL(in: folder, name: name)
        export.outputURL = url
        export.outputFileType = .mp4
        export.videoComposition = videoComposition
        export.shouldOptimizeForNetworkUse = true
        currentExport = export
        jobCancel = false

        export.exportAsynchronously {
            DispatchQueue.main.async {
                self.currentExport = nil
                switch export.status {
                case .completed:
                    self.lastOutput = folder
                    reply(["ok": true, "name": url.lastPathComponent, "bytes": self.fileSize(url)], nil)
                case .cancelled:
                    try? FileManager.default.removeItem(at: url)
                    reply(["ok": false, "cancelled": true, "error": "Stopped"], nil)
                default:
                    try? FileManager.default.removeItem(at: url)
                    reply(["ok": false, "error": export.error?.localizedDescription ?? "The export failed"], nil)
                }
            }
        }
    }
}


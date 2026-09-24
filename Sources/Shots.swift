// Needed Shots — native macOS shell.
// This Was Needed · thiswasneeded.info
//
// One file, no packages. Wraps the self-contained web app in a real Mac
// window. The only network request is licence activation, once.
//
// Build:  swiftc -O -target arm64-apple-macos11.3 -o nc-arm64 main.swift licence.swift
//         swiftc -O -target x86_64-apple-macos11.3 -o nc-x64 main.swift licence.swift
//         lipo -create -output "Needed Shots" nc-arm64 nc-x64

import AppKit
import WebKit
import AVFoundation
import ImageIO
import PDFKit

let shotsScheme = "neededshots"
let shotsPageBackground = NSColor(srgbRed: 0xF4 / 255.0, green: 0xF3 / 255.0,
                             blue: 0xF1 / 255.0, alpha: 1)

// MARK: - Serving the app

/// Serves the bundle's Resources over a private scheme.
///
/// Not file:// — a page loaded from file:// has a null origin, and WebKit
/// refuses localStorage on a null origin. The crew memory would seem to
/// work and then be empty on every relaunch. A custom scheme gives the page
/// a stable origin, so storage survives relaunches and app updates.
final class ShotsSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    /// The vault folder, so the page can show what's in it: /vault/... paths.
    var vaultRoot: () -> URL? = { nil }
    // Files are read here, never on the main thread — a big still or a clip
    // read there freezes the window (the pinwheel).
    private let reader = DispatchQueue(label: "neededshots.files", qos: .userInitiated, attributes: .concurrent)
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

final class ShotsHost: NSObject, NSApplicationDelegate, NSWindowDelegate,
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
    var currentProcess: Process?                // a running lookup or pull
    var index: [[String: Any]] = []             // the vault's library
    /// Where new things are filed inside the vault. Boards are labels that
    /// cut across projects; a project is the folder a file actually lives in.
    var currentProject: String { get { Shared.project } set { Shared.project = newValue } }
    var indexLoadedFor: String = ""
    var downloadObservation: NSKeyValueObservation?
    private var jobCancel = false

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
        let scheme = ShotsSchemeHandler(root: resources.appendingPathComponent("tools/shots"))
        scheme.vaultRoot = { [weak self] in self?.saveFolder }
        config.setURLSchemeHandler(scheme, forURLScheme: shotsScheme)

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


        if let start = URL(string: "\(shotsScheme)://app/index.html") {
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
        appMenu.addItem(withTitle: "About Needed Shots",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Needed Shots",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others",
                                     action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Needed Shots",
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

extension ShotsHost: WKScriptMessageHandlerWithReply {
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

extension ShotsHost {
    func handleFiles(_ action: String, _ body: [String: Any],
                     _ reply: @escaping (Any?, String?) -> Void) {
        switch action {
        case "folder":
            if indexLoadedFor != (saveFolder?.path ?? "") { loadIndex() }
            reply(["path": saveFolder?.path ?? "", "project": currentProject, "projects": projectList()], nil)

        case "setProject":
            currentProject = projectName(body["name"] as? String)
            UserDefaults.standard.set(currentProject, forKey: "project")
            reply(["project": currentProject, "projects": projectList()], nil)

        case "chooseFolder":
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Use This Folder"
            panel.message = "Choose your Needed Vault folder"
            if let current = saveFolder { panel.directoryURL = current }
            panel.beginSheetModal(for: window) { result in
                if result == .OK, let url = panel.url {
                    self.saveFolder = url
                    UserDefaults.standard.set(url.path, forKey: "saveFolder")
                    self.loadIndex()
                }
                reply(["path": self.saveFolder?.path ?? ""], nil)
            }

        case "saveFile":
            guard saveFolder != nil else {
                return reply(["ok": false, "error": "Choose a folder first"], nil)
            }
            let asked = (body["folder"] as? String) ?? "Stills"
            let kindFolder = ["Stills", "Sheets"].contains(asked) ? asked : "Stills"
            guard let folder = outputFolder(kindFolder) else {
                return reply(["ok": false, "error": "Couldn't create the \(kindFolder) folder"], nil)
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
                let item = register(kind: (body["kind"] as? String) ?? "still", file: target, meta: body["meta"] as? [String: Any])
                reply(["ok": true, "name": target.lastPathComponent, "item": item], nil)
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



        case "progress":
            reply(["progress": currentExport.map { Double($0.progress) } ?? jobProgress], nil)

        case "cancelJob":
            jobCancel = true
            currentExport?.cancelExport()
            currentProcess?.terminate()
            reply(["ok": true], nil)

        case "saveText":
            guard saveFolder != nil else { return reply(["ok": false, "error": "Choose a vault folder first"], nil) }
            let askedFor = (body["folder"] as? String) ?? "Ideas"
            let folderName = ["Ideas", "Sheets"].contains(askedFor) ? askedFor : "Ideas"
            guard let folder = outputFolder(folderName),
                  let name = safeName((body["name"] as? String) ?? ""),
                  let text = body["text"] as? String else {
                return reply(["ok": false, "error": "Couldn't save that"], nil)
            }
            let target = uniqueURL(in: folder, name: name)
            do {
                try text.write(to: target, atomically: true, encoding: .utf8)
                lastOutput = folder
                let item = (body["register"] as? Bool) == false ? [:]
                    : register(kind: (body["kind"] as? String) ?? "idea", file: target,
                               meta: body["meta"] as? [String: Any])
                reply(["ok": true, "name": target.lastPathComponent, "item": item], nil)
            } catch {
                reply(["ok": false, "error": "Couldn't write to \(folder.lastPathComponent)"], nil)
            }

        case "openFolder":
            // The project you're filing into, if it exists yet; otherwise the vault.
            if let base = saveFolder {
                let project = base.appendingPathComponent(projectName(currentProject), isDirectory: true)
                NSWorkspace.shared.open(FileManager.default.fileExists(atPath: project.path) ? project : base)
            }
            reply(["ok": true], nil)

        case "reveal":
            if let folder = lastOutput ?? saveFolder { NSWorkspace.shared.open(folder) }
            reply(["ok": true], nil)


        // ---- library
        case "folderStills":
            // every image in the project's Stills — old, Grabs and References — newest first
            guard let base = saveFolder else { return reply(["files": []], nil) }
            let proj = projectName((body["project"] as? String) ?? currentProject)
            let exts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "tif", "tiff"]
            var files: [[String: Any]] = []
            for sub in ["Stills", "Grabs/Stills", "References/Stills"] {
                let dir = base.appendingPathComponent(proj).appendingPathComponent(sub)
                for u in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                       options: [.skipsHiddenFiles])) ?? [] where exts.contains(u.pathExtension.lowercased()) {
                    let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                    files.append(["file": "\(proj)/\(sub)/\(u.lastPathComponent)", "name": u.lastPathComponent, "modified": m.timeIntervalSince1970 * 1000])
                }
            }
            files.sort { ($0["modified"] as? Double ?? 0) > ($1["modified"] as? Double ?? 0) }
            reply(["files": files], nil)

        case "vaultList":
            loadIndex()
            let root = saveFolder?.path ?? ""
            let alive = index.filter { item in
                guard let rel = item["file"] as? String, let base = saveFolder else { return false }
                return FileManager.default.fileExists(atPath: base.appendingPathComponent(rel).path)
            }
            reply(["root": root, "items": alive], nil)
        case "vaultUpdate":
            updateItem(body)
            reply(["ok": true], nil)
        case "vaultRemove":
            reply(["ok": removeItem((body["id"] as? String) ?? "")], nil)
        case "revealItem":
            if let base = saveFolder, let item = index.first(where: { ($0["id"] as? String) == (body["id"] as? String) }),
               let rel = item["file"] as? String {
                NSWorkspace.shared.activateFileViewerSelecting([base.appendingPathComponent(rel)])
            }
            reply(["ok": true], nil)
        case "openSource":
            // Only ever a web link — opens in your browser at the right moment.
            if let raw = body["url"] as? String, let url = URL(string: raw),
               let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
                NSWorkspace.shared.open(url)
                reply(["ok": true], nil)
            } else {
                reply(["ok": false], nil)
            }

        case "listShots", "loadShots", "saveShots", "exportPdf", "importPdf", "previewPdf":
            handleShots(action, body, reply)

        default:
            reply(nil, "unknown action")
        }
    }
}

// MARK: - The library

extension ShotsHost {
    func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// Stills, Shots and the rest sit inside the project folder, each made
    /// the first time something goes in it.
    func outputFolder(_ kind: String) -> URL? {
        guard let base = saveFolder else { return nil }
        let folder = base.appendingPathComponent(projectName(currentProject), isDirectory: true)
                         .appendingPathComponent(kind, isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { return nil }
        return folder
    }

    /// A file in the folder that doesn't exist yet: "name 2.pdf" and so on.
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

    func safeName(_ raw: String) -> String? {
        let name = raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return name.isEmpty || name.hasPrefix(".") ? nil : name
    }

    /// A project's folder name, made safe.
    func projectName(_ raw: String?) -> String {
        var n = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while n.hasPrefix(".") { n.removeFirst() }
        if n.count > 60 { n = String(n.prefix(60)) }
        return n.isEmpty ? "Unsorted" : n
    }

    /// Every project folder in the vault, plus any the library remembers.
    func projectList() -> [String] {
        var names = Set<String>([currentProject])
        let skip: Set<String> = ["Stills", "GIFs", "Motion", "Ideas", "Sheets"]
        if let base = saveFolder,
           let found = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
            for url in found {
                let name = url.lastPathComponent
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue && !name.hasPrefix(".") && !skip.contains(name) { names.insert(name) }
            }
        }
        for item in index { if let p = item["project"] as? String, !p.isEmpty { names.insert(p) } }
        return names.sorted { $0.lowercased() < $1.lowercased() }
    }

    var indexURL: URL? { saveFolder?.appendingPathComponent(".vault/index.json") }

    func loadIndex() {
        guard let u = indexURL, let d = try? Data(contentsOf: u),
              let items = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else {
            index = []; indexLoadedFor = saveFolder?.path ?? ""; return
        }
        index = items
        indexLoadedFor = saveFolder?.path ?? ""
    }

    func saveIndex() {
        guard let u = indexURL else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: index, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: u, options: .atomic)
        }
    }

    /// Every still, GIF and clip is remembered with where it came from.
    func register(kind: String, file: URL, meta: [String: Any]?) -> [String: Any] {
        if indexLoadedFor != (saveFolder?.path ?? "") { loadIndex() }
        guard let base = saveFolder else { return [:] }
        let id = UUID().uuidString
        let rel = file.path.replacingOccurrences(of: base.path + "/", with: "")
        var thumbRel = rel
        if kind == "clip", let thumb = poster(for: file, id: id) {
            thumbRel = thumb.path.replacingOccurrences(of: base.path + "/", with: "")
        }
        var item: [String: Any] = [
            "id": id, "kind": kind, "file": rel, "thumb": thumbRel, "project": currentProject,
            "bytes": fileSize(file),
            "created": ISO8601DateFormatter().string(from: Date()),
        ]
        for key in ["source", "at", "end", "crop", "tags", "note", "w", "h", "palette", "boards", "title", "text"] {
            if let v = meta?[key] { item[key] = v }
        }
        index.insert(item, at: 0)
        saveIndex()
        return item
    }

    /// A still from a clip, for the library grid.
    func poster(for file: URL, id: String) -> URL? {
        guard let base = saveFolder else { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil),
              let jpg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return nil }
        let dir = base.appendingPathComponent(".vault/thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(id + ".jpg")
        return (try? jpg.write(to: url)) != nil ? url : nil
    }

    func updateItem(_ b: [String: Any]) {
        guard let id = b["id"] as? String, let i = index.firstIndex(where: { ($0["id"] as? String) == id }) else { return }
        if let tags = b["tags"] as? [String] { index[i]["tags"] = tags }
        if let note = b["note"] as? String { index[i]["note"] = note }
        if let boards = b["boards"] as? [String] { index[i]["boards"] = boards }
        if let title = b["title"] as? String { index[i]["title"] = title }
        if let text = b["text"] as? String { index[i]["text"] = text }
        saveIndex()
    }

    /// Removing moves the file to the Trash, never deletes it outright.
    func removeItem(_ id: String) -> Bool {
        guard let base = saveFolder, let i = index.firstIndex(where: { ($0["id"] as? String) == id }) else { return false }
        let item = index[i]
        if let rel = item["file"] as? String {
            try? FileManager.default.trashItem(at: base.appendingPathComponent(rel), resultingItemURL: nil)
        }
        if let thumb = item["thumb"] as? String, thumb.hasPrefix(".vault/thumbs/") {
            try? FileManager.default.removeItem(at: base.appendingPathComponent(thumb))
        }
        index.remove(at: i)
        saveIndex()
        return true
    }
}


// MARK: - Shot lists

extension ShotsHost {
    /// Shot lists live beside the references, inside the project.
    func shotsFolder() -> URL? { outputFolder("Shots") }

    func handleShots(_ action: String, _ body: [String: Any],
                     _ reply: @escaping (Any?, String?) -> Void) {
        switch action {
        case "listShots":
            guard let folder = shotsFolder() else { return reply(["lists": []], nil) }
            let files = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let lists = files.filter { $0.pathExtension == "json" }.map { url -> [String: Any] in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return ["name": url.deletingPathExtension().lastPathComponent,
                        "saved": ISO8601DateFormatter().string(from: date ?? Date())]
            }
            reply(["lists": lists], nil)

        case "loadShots":
            guard let folder = shotsFolder(), let name = safeName((body["name"] as? String) ?? "") else {
                return reply(["ok": false], nil)
            }
            let url = folder.appendingPathComponent(name + ".json")
            guard let data = try? Data(contentsOf: url),
                  let doc = try? JSONSerialization.jsonObject(with: data) else {
                return reply(["ok": false, "error": "Couldn't open that list"], nil)
            }
            reply(["ok": true, "doc": doc], nil)

        case "saveShots":
            guard saveFolder != nil else { return reply(["ok": false, "error": "Choose your vault folder first"], nil) }
            guard let folder = shotsFolder(), let name = safeName((body["name"] as? String) ?? ""),
                  let doc = body["doc"], let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted]) else {
                return reply(["ok": false, "error": "Couldn't save that list"], nil)
            }
            let url = folder.appendingPathComponent(name + ".json")
            let write: (URL) -> Void = { target in
                do { try data.write(to: target, options: .atomic); self.lastOutput = folder
                     reply(["ok": true, "name": target.deletingPathExtension().lastPathComponent], nil) }
                catch { reply(["ok": false, "error": "Couldn't write to the Shots folder"], nil) }
            }
            // Saving the list you have open just saves. A name that belongs to
            // a different list asks first.
            let own = (body["own"] as? String) ?? ""
            if FileManager.default.fileExists(atPath: url.path) && own != name {
                askReplace(url, in: "\(currentProject) › Shots") { choice in
                    switch choice {
                    case "replace": write(url)
                    case "keep": write(self.uniqueURL(in: folder, name: name + ".json"))
                    default: reply(["ok": false, "cancelled": true], nil)
                    }
                }
            } else {
                write(url)
            }

        case "exportPdf":
            exportPdf(body, reply)

        case "previewPdf":
            previewPdf(body, reply)

        case "importPdf":
            importPdf(reply)

        default:
            reply(nil, "unknown action")
        }
    }

    // MARK: The PDF

    private func pdfFont(_ name: String, _ size: CGFloat) -> NSFont {
        NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    private func draw(_ text: String, in rect: CGRect, font: NSFont, colour: NSColor,
                      tracking: CGFloat = 0, upper: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 1.5
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: colour, .paragraphStyle: style, .kern: tracking,
        ]
        NSAttributedString(string: upper ? text.uppercased() : text, attributes: attrs).draw(in: rect)
    }

    private func height(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 1.5
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        return NSAttributedString(string: text, attributes: attrs)
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height
    }

    func exportPdf(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard saveFolder != nil else { return reply(["ok": false, "error": "Choose your vault folder first"], nil) }
        guard let folder = shotsFolder(), let name = safeName((body["name"] as? String) ?? "") else {
            return reply(["ok": false, "error": "Couldn't make that PDF"], nil)
        }
        let doc = (body["doc"] as? [String: Any]) ?? [:]
        let url = uniqueURL(in: folder, name: name + ".pdf")
        guard let pages = renderPdf(doc, name: name, to: url, embed: true) else {
            return reply(["ok": false, "error": "Couldn't start the PDF"], nil)
        }
        lastOutput = folder
        reply(["ok": true, "name": url.lastPathComponent, "bytes": fileSize(url), "pages": pages], nil)
    }

    /// The same drawing as the export, to a temporary file, handed back as
    /// page images — so the preview is exactly what you'll get.
    func previewPdf(_ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        let doc = (body["doc"] as? [String: Any]) ?? [:]
        let width = CGFloat((body["width"] as? NSNumber)?.doubleValue ?? 1100)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("needed-shots-preview.pdf")
        try? FileManager.default.removeItem(at: tmp)
        guard renderPdf(doc, name: "preview", to: tmp, embed: false) != nil, let pdf = PDFDocument(url: tmp) else {
            return reply(["ok": false, "error": "Couldn't draw the preview"], nil)
        }
        var images: [String] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            let size = CGSize(width: width, height: width * box.height / box.width)
            let thumb = page.thumbnail(of: size, for: .mediaBox)
            if let tiff = thumb.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                images.append(png.base64EncodedString())
            }
        }
        reply(["ok": true, "pages": images], nil)
    }

    /// Draws the shot list. Layout options travel in the list itself:
    /// orientation, lines on or off, and a scale for type and pictures.
    func renderPdf(_ doc: [String: Any], name: String, to url: URL, embed: Bool) -> Int? {
        guard let vault = saveFolder else { return nil }
        let shots = (doc["shots"] as? [[String: Any]]) ?? []
        let title = (doc["title"] as? String) ?? name
        let subtitle = (doc["subtitle"] as? String) ?? ""
        let layout = (doc["layout"] as? [String: Any]) ?? [:]
        let portrait = (layout["orientation"] as? String) == "portrait"
        let ruled = (layout["lines"] as? Bool) ?? true
        let k = CGFloat(min(1.5, max(0.7, (layout["scale"] as? NSNumber)?.doubleValue ?? 1)))

        // A4 either way: reads on an iPad, prints on A4 or Letter.
        var media = portrait ? CGRect(x: 0, y: 0, width: 595, height: 842) : CGRect(x: 0, y: 0, width: 842, height: 595)
        guard let ctx = CGContext(url as CFURL, mediaBox: &media, nil) else { return nil }
        let ink = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.11, alpha: 1)
        let mid = NSColor(calibratedWhite: 0.42, alpha: 1)
        let dim = NSColor(calibratedWhite: 0.62, alpha: 1)
        let hair = NSColor(calibratedWhite: 0.87, alpha: 1)
        let accent = NSColor(calibratedRed: 0.94, green: 0.35, blue: 0.13, alpha: 1)

        let margin: CGFloat = 34
        let usable = media.width - margin * 2
        // Headings come from the list itself, so renaming a column here
        // renames it on the page.
        let headings = (doc["columns"] as? [String]) ?? []
        let base: [CGFloat] = portrait ? [0.07, 0.22, 0.11, 0.08, 0.09, 0.15, 0.28]
                                       : [0.06, 0.225, 0.115, 0.08, 0.09, 0.175, 0.255]
        // Scale mostly changes the pictures: take room from the text columns.
        let pic = min(0.42, max(0.18, base[6] * k))
        let rest = base.prefix(6).reduce(0, +)
        // Scene breakdown: just the number and one free line, the full width.
        let breakdown = (doc["mode"] as? String) == "breakdown"
        let widths: [CGFloat] = breakdown ? [0.07, 1 - 0.07 - pic, 0, 0, 0, 0, pic] : base.prefix(6).map { $0 * (1 - pic) / rest } + [pic]
        let fallback = ["Shot", "Description", "Emotion", "Angle", "Movement", "Notes", "Reference"]
        let cols: [(String, CGFloat)] = widths.enumerated().map { i, w in
            (i < headings.count && !headings[i].isEmpty ? headings[i] : fallback[i], w)
        }
        var x0: [CGFloat] = []
        var run = margin
        for c in cols { x0.append(run); run += c.1 * usable }

        var page = 0
        var y: CGFloat = 0
        let bottom = margin + 26
        let mark = Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("logo.png")) }
        var headerLine: CGFloat = 0     // where the heading rule sits on this page
        var columnTop: CGFloat = 0      // where this page's column rules start

        func startPage() {
            if page > 0 { ctx.endPDFPage() }
            page += 1
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            y = media.height - margin
            if let mark = mark, mark.size.width > 0 {
                let w: CGFloat = page == 1 ? 68 : 40
                let h = w * mark.size.height / mark.size.width
                mark.draw(in: CGRect(x: media.width - margin - w, y: media.height - margin - h + 6, width: w, height: h),
                          from: .zero, operation: .sourceOver, fraction: 1)
            }
            if page == 1 {
                draw(title, in: CGRect(x: margin, y: y - 30, width: usable, height: 34),
                     font: pdfFont("HelveticaNeue-Thin", 26 * k), colour: ink)
                y -= 36
                if !subtitle.isEmpty {
                    draw(subtitle, in: CGRect(x: margin, y: y - 14, width: usable, height: 16),
                         font: pdfFont("Menlo", 9 * k), colour: mid, tracking: 1)
                    y -= 20
                }
            } else {
                draw(title, in: CGRect(x: margin, y: y - 12, width: usable, height: 14),
                     font: pdfFont("Menlo", 8), colour: dim, tracking: 1, upper: true)
                y -= 20
            }
            // column headings
            for (i, c) in cols.enumerated() where c.1 > 0.001 {
                draw(c.0, in: CGRect(x: x0[i] + 4, y: y - 11, width: c.1 * usable - 10, height: 12),
                     font: pdfFont("Menlo", 7 * k), colour: dim, tracking: 1.2, upper: true)
            }
            y -= 16
            hair.setStroke()
            ctx.setLineWidth(0.6)
            ctx.move(to: CGPoint(x: margin, y: y)); ctx.addLine(to: CGPoint(x: margin + usable, y: y)); ctx.strokePath()
            headerLine = y
            y -= 8
        }

        func finishPage() {
            draw("\(page)", in: CGRect(x: margin + usable - 40, y: margin - 4, width: 40, height: 12),
                 font: pdfFont("Menlo", 8), colour: dim)
            NSGraphicsContext.restoreGraphicsState()
        }

        // Column rules are drawn down each page once its rows are laid out.
        func ruleColumns(to end: CGFloat) {
            guard ruled, columnTop > end else { return }
            hair.setStroke()
            ctx.setLineWidth(0.4)
            for i in 1..<cols.count where cols[i].1 > 0.001 {
                ctx.move(to: CGPoint(x: x0[i] - 3, y: columnTop))
                ctx.addLine(to: CGPoint(x: x0[i] - 3, y: end))
            }
            ctx.strokePath()
        }

        startPage()
        var lastScene = ""
        let bodyFont = pdfFont("HelveticaNeue", 9 * k)
        let monoFont = pdfFont("Menlo", 8 * k)

        for shot in shots {
            let scene = (shot["scene"] as? String) ?? ""
            let refs = (shot["refs"] as? [[String: Any]]) ?? []           // references print in breakdown too
            let cells = breakdown ? [(shot["number"] as? String) ?? "", (shot["description"] as? String) ?? "", "", "", "", ""] : [
                (shot["number"] as? String) ?? "",
                (shot["description"] as? String) ?? "",
                (shot["emotion"] as? String) ?? "",
                (shot["angle"] as? String) ?? "",
                (shot["movement"] as? String) ?? "",
                (shot["notes"] as? String) ?? "",
            ]
            // how tall this row needs to be
            var textHeight: CGFloat = 14
            for (i, text) in cells.enumerated() where !text.isEmpty {
                textHeight = max(textHeight, height(text, width: cols[i].1 * usable - 10, font: i == 0 ? monoFont : bodyFont))
            }
            let refWidth = cols[6].1 * usable - 8
            var imgs: [NSImage] = []
            for r in refs.prefix(2) {
                if let rel = r["file"] as? String,
                   let img = NSImage(contentsOf: vault.appendingPathComponent(rel)) { imgs.append(img) }
            }
            var refHeight: CGFloat = 0
            for img in imgs {
                let ratio = img.size.height > 0 ? img.size.width / img.size.height : 16.0 / 9
                refHeight += refWidth / max(0.3, ratio) + 14
            }
            let blank = cells.dropFirst().allSatisfy { $0.isEmpty } && imgs.isEmpty
            let rowHeight = blank ? 26 : max(textHeight + 12, refHeight + 6, 34)

            if scene != lastScene {                       // a scene heading, once per scene
                if y - 26 - rowHeight < bottom { finishPage(); startPage() }
                accent.setFill()
                ctx.fill(CGRect(x: margin, y: y - 2, width: 14, height: 1.5))
                draw(scene.isEmpty ? "Scene" : scene,
                     in: CGRect(x: margin + 20, y: y - 12, width: usable - 20, height: 14),
                     font: pdfFont("HelveticaNeue-Medium", 9 * k), colour: ink, tracking: 1.4, upper: true)
                y -= 22
                lastScene = scene
                columnTop = y + 6
            }
            if columnTop == 0 { columnTop = headerLine }
            if y - rowHeight < bottom {
                ruleColumns(to: y)                      // close this page's rules
                finishPage(); startPage(); lastScene = ""; columnTop = headerLine
            }

            for (i, text) in cells.enumerated() where !text.isEmpty {
                draw(text, in: CGRect(x: x0[i] + 4, y: y - rowHeight + 6, width: cols[i].1 * usable - 10, height: rowHeight - 6),
                     font: i == 0 ? monoFont : bodyFont, colour: i == 0 ? accent : ink)
            }
            var imgY = y
            for (n, img) in imgs.enumerated() {
                let ratio = img.size.height > 0 ? img.size.width / img.size.height : 16.0 / 9
                let h = refWidth / max(0.3, ratio)
                let box = CGRect(x: x0[6], y: imgY - h, width: refWidth, height: h)
                img.draw(in: box.insetBy(dx: 0, dy: 0).offsetBy(dx: 4, dy: 0), from: .zero, operation: .copy, fraction: 1)
                if n < refs.count {
                    let r = refs[n]
                    let from = [(r["title"] as? String) ?? "", (r["at"] as? String) ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !from.isEmpty {
                        draw(from, in: CGRect(x: x0[6] + 4, y: imgY - h - 11, width: refWidth, height: 10),
                             font: pdfFont("Menlo", 6 * k), colour: dim)
                    }
                }
                imgY -= h + 14
            }
            y -= rowHeight
            if ruled {
                hair.setStroke()
                ctx.setLineWidth(0.4)
                ctx.move(to: CGPoint(x: margin, y: y)); ctx.addLine(to: CGPoint(x: margin + usable, y: y)); ctx.strokePath()
                y -= 8
            } else {
                y -= 14                                   // no rules: space does the work
            }
        }
        ruleColumns(to: y + 8)
        finishPage()
        ctx.endPDFPage()
        ctx.closePDF()

        // The list itself rides inside the PDF, so opening it here restores
        // every row exactly. Nobody else sees any difference.
        if embed, let data = try? JSONSerialization.data(withJSONObject: doc),
           let pdf = PDFDocument(url: url) {
            var attrs = pdf.documentAttributes ?? [:]
            attrs[PDFDocumentAttribute.titleAttribute] = title
            attrs[PDFDocumentAttribute.creatorAttribute] = "Needed Shots"
            attrs[PDFDocumentAttribute.keywordsAttribute] = ["NeededShots:" + data.base64EncodedString()]
            pdf.documentAttributes = attrs
            pdf.write(to: url)
        }
        return page
    }

    /// Open a shot list PDF: exactly if it came from here, best-effort if not.
    func importPdf(_ reply: @escaping (Any?, String?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["pdf"]
        panel.prompt = "Open"
        panel.message = "Open a shot list PDF"
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let url = panel.url, let pdf = PDFDocument(url: url) else {
                return reply(["ok": false, "cancelled": true], nil)
            }
            let keywords = (pdf.documentAttributes?[PDFDocumentAttribute.keywordsAttribute] as? [String]) ?? []
            if let mine = keywords.first(where: { $0.hasPrefix("NeededShots:") }),
               let data = Data(base64Encoded: String(mine.dropFirst("NeededShots:".count))),
               let doc = try? JSONSerialization.jsonObject(with: data) {
                return reply(["ok": true, "exact": true, "doc": doc,
                              "name": url.deletingPathExtension().lastPathComponent], nil)
            }
            // Not one of ours: hand the text over and let the page read what it can.
            reply(["ok": true, "exact": false, "text": pdf.string ?? "",
                   "name": url.deletingPathExtension().lastPathComponent], nil)
        }
    }
}


extension ShotsHost {
    /// Before anything replaces a file that's already there: Replace,
    /// Keep Both (the new one gets a number), or Cancel.
    func askReplace(_ url: URL, in place: String, _ done: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\u{201C}\(url.lastPathComponent)\u{201D} is already in \(place)."
        alert.informativeText = "Replace it, or keep both? Keeping both saves the new one with a number."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { r in
            done(r == .alertFirstButtonReturn ? "replace" : r == .alertSecondButtonReturn ? "keep" : "cancel")
        }
    }
}


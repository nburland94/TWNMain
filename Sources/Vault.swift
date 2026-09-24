// Needed Vault — native macOS shell.
// This Was Needed · thiswasneeded.info
//
// One file, no packages. Wraps the self-contained web app in a real Mac
// window. The only network request is licence activation, once.
//
// Build:  swiftc -O -target arm64-apple-macos11.3 -o nc-arm64 main.swift licence.swift
//         swiftc -O -target x86_64-apple-macos11.3 -o nc-x64 main.swift licence.swift
//         lipo -create -output "Needed Vault" nc-arm64 nc-x64

import AppKit
import WebKit
import AVFoundation
import ImageIO
import Network

let vaultScheme = "neededvault"
let vaultPageBackground = NSColor(srgbRed: 0xF4 / 255.0, green: 0xF3 / 255.0,
                             blue: 0xF1 / 255.0, alpha: 1)

// MARK: - Serving the app

/// Serves the bundle's Resources over a private scheme.
///
/// Not file:// — a page loaded from file:// has a null origin, and WebKit
/// refuses localStorage on a null origin. The crew memory would seem to
/// work and then be empty on every relaunch. A custom scheme gives the page
/// a stable origin, so storage survives relaunches and app updates.
final class VaultSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    /// The vault folder, so the page can show what's in it: /vault/... paths.
    var vaultRoot: () -> URL? = { nil }
    // Files are read here, never on the main thread — a big still or a clip
    // read there freezes the window (the pinwheel).
    private let reader = DispatchQueue(label: "neededvault.files", qos: .userInitiated, attributes: .concurrent)
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
            var type = self.mimeType(target.pathExtension)
            if type.hasPrefix("image/"), from == 0, data.count >= 12 { type = VaultSchemeHandler.sniff(data) ?? type }
            var headers = [
                "Content-Type": type,
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

    /// An image's real type from its first bytes — for files saved under the wrong name.
    static func sniff(_ d: Data) -> String? {
        let b = [UInt8](d.prefix(12))
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if b.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if b.starts(with: [0x52, 0x49, 0x46, 0x46]), b.count >= 12, b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return "image/webp" }
        if b.count >= 12, b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 {                    // "ftyp…"
            let brand = String(bytes: b[8..<12], encoding: .ascii) ?? ""
            if brand.hasPrefix("avi") { return "image/avif" }
            if brand.hasPrefix("hei") || brand.hasPrefix("mif") { return "image/heic" }
        }
        return nil
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
        case "webp": return "image/webp"
        case "avif": return "image/avif"
        case "heic": return "image/heic"
        case "mp4", "m4v": return "video/mp4"
        case "mov":  return "video/quicktime"
        default:     return "application/octet-stream"
        }
    }
}

// MARK: - App

final class VaultHost: NSObject, NSApplicationDelegate, NSWindowDelegate,
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
    let grabGo = GrabAndGo()                    // Copy Image, drag and drop, and the Chrome extension
    var holdIndexSaves = false                  // while adopting a batch: one write at the end
    var syncing = false                         // Sync is looking through a project's folders
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
        grabGo.app = self
        grabGo.listen()

        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(Shared.embedded)
        // The persistent store. The non-persistent one would wipe the crew
        // memory every time the app quits.
        config.websiteDataStore = .default()
        // Shot-finding and frame-rate detection play the film silently
        // without a click; WebKit blocks that unless it's allowed here.
        config.mediaTypesRequiringUserActionForPlayback = []
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        let scheme = VaultSchemeHandler(root: resources.appendingPathComponent("tools/vault"))
        scheme.vaultRoot = { [weak self] in self?.saveFolder }
        config.setURLSchemeHandler(scheme, forURLScheme: vaultScheme)

        // The page asks the app about the licence; the app does the checking.
        licence = Licence(resources: resources)
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page,
                                                             name: "licence")
        // A web page can't write into a folder on your Mac, so the app does:
        // it shows the folder picker and writes each still into that folder.
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page,
                                                             name: "files")

        // Files dragged from Finder import straight into the project — except a single film,
        // which the page opens in its player as before.
        let drop = DropWebView(frame: .zero, configuration: config)
        drop.accepts = { urls in
            let films: Set<String> = ["mov", "mp4", "m4v", "webm"]
            return !urls.isEmpty && !(urls.count == 1 && films.contains(urls[0].pathExtension.lowercased()))
        }
        drop.onFiles = { [weak self] urls in self?.importFiles(urls) }
        webView = drop
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")   // no white flash


        if let start = URL(string: "\(vaultScheme)://app/index.html") {
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
        appMenu.addItem(withTitle: "About Needed Vault",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Needed Vault",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others",
                                     action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Needed Vault",
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

extension VaultHost: WKScriptMessageHandlerWithReply {
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

extension VaultHost {
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
            panel.message = "Choose a folder for your vault"
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
            // A crop made in the vault goes back into its own still's project.
            let intoProject = (body["project"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            guard let folder = outputFolder(kindFolder, project: intoProject) else {
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
                let item = register(kind: (body["kind"] as? String) ?? "still", file: target,
                                    meta: body["meta"] as? [String: Any], project: intoProject)
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

        case "makeGif":
            makeGif(body, reply)

        case "makeClip":
            makeClip(body, reply)

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

        // ---- links
        case "helpers":
            reply(["ready": helpersReady()], nil)
        case "setupHelpers":
            setupHelpers(force: (body["force"] as? Bool) ?? false, reply)
        case "lookup":
            lookup((body["url"] as? String) ?? "", reply)
        case "pull":
            pull(body, reply)
        case "grabFrame":
            grabFrame(body, reply)
        case "preview":
            preview(body, reply)

        // ---- library
        case "vaultList":
            loadIndex()                          // just the saved list: Sync is what looks through the folders
            let root = saveFolder?.path ?? ""
            let alive = index.filter { item in
                guard let rel = item["file"] as? String, let base = saveFolder else { return false }
                return FileManager.default.fileExists(atPath: base.appendingPathComponent(rel).path)
            }
            reply(["root": root, "items": alive], nil)
        case "grabGo":
            grabGo.setOn((body["on"] as? Bool) ?? false)
            reply(["on": grabGo.on, "project": currentProject], nil)
        case "grabDrop":
            // an image dragged onto the window: the file itself, or its address
            let data = (body["data"] as? String).flatMap { Data(base64Encoded: $0) }
            grab(imageData: data, html: (body["html"] as? String) ?? "", imageURL: (body["url"] as? String) ?? "",
                 page: (body["page"] as? String) ?? "", via: "drop")
            reply(["ok": true, "project": currentProject], nil)
        case "revealExtension":
            reply(["ok": revealExtension()], nil)
        case "importFiles":
            // Add to vault: choose from Finder, straight into the project's References
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedFileTypes = ["jpg", "jpeg", "png", "webp", "heic", "tif", "tiff", "gif", "avif", "mov", "mp4", "m4v"]
            panel.prompt = "Add to Vault"
            panel.message = "Choose images, GIFs or clips — they're copied into \(currentProject) › \(projectName(currentProject))_Vault"
            panel.beginSheetModal(for: window) { r in
                guard r == .OK else { return reply(["ok": false, "cancelled": true], nil) }
                reply(["ok": true, "added": self.importFiles(panel.urls)], nil)
            }

        case "moodBoard":
            moodBoard(body, reply)

        case "vaultMove":
            reply(moveItems(body), nil)
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

        default:
            reply(nil, "unknown action")
        }
    }
}

// MARK: - GIFs and clips

extension VaultHost {
    func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// Stills, GIFs and Motion go in the project's Lexus_Vault (or Lexus_Grab,
    /// when area is "Grabs"); Ideas and contact sheets sit in the project as before.
    /// Each folder is made the first time something goes in it.
    func outputFolder(_ kind: String, project: String? = nil, area: String? = nil) -> URL? {
        guard let base = saveFolder else { return nil }
        let name = projectName(project ?? currentProject)
        var folder = base.appendingPathComponent(name, isDirectory: true)
        if Folders.kinds.contains(kind) { folder = folder.appendingPathComponent(Folders.sub(kind, project: name, grab: area == "Grabs"), isDirectory: true) }
        else { folder = folder.appendingPathComponent(kind, isDirectory: true) }
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
    private func geometry(_ b: [String: Any], even: Bool, frame: CGSize = .zero) -> (CGRect, CGSize) {
        let r = b["rect"] as? [String: Any] ?? [:]
        let o = b["out"] as? [String: Any] ?? [:]
        // The page sends the crop as fractions of the frame (0 to 1), so it
        // fits whatever size the real picture turns out to be.
        let scaleX = frame.width > 0 ? frame.width : 1, scaleY = frame.height > 0 ? frame.height : 1
        let crop = CGRect(x: number(r["x"]) * scaleX, y: number(r["y"]) * scaleY,
                          width: max(2 / scaleX, number(r["w"])) * scaleX,
                          height: max(2 / scaleY, number(r["h"])) * scaleY).integral
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
            return reply(["ok": false, "error": "Pull a moment, or open a file, first"], nil)
        }
        guard saveFolder != nil else { return reply(["ok": false, "error": "Choose a folder first"], nil) }
        guard let folder = outputFolder("GIFs") else {
            return reply(["ok": false, "error": "Couldn't create the GIFs folder"], nil)
        }
        guard let name = safeName((b["name"] as? String) ?? "") else {
            return reply(["ok": false, "error": "Bad file name"], nil)
        }
        let start = number(b["start"]), end = number(b["end"])
        let fps = min(30, max(4, number(b["fps"])))
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

            let (_, out) = self.geometry(b, even: false, frame: CGSize(width: 1, height: 1))
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
                   let cut = img.cropping(to: self.geometry(b, even: false,
                        frame: CGSize(width: img.width, height: img.height)).0
                        .intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))),
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
            DispatchQueue.main.async {
                self.lastOutput = folder
                let item = self.register(kind: "gif", file: url, meta: b["meta"] as? [String: Any])
                reply(["ok": true, "name": url.lastPathComponent, "bytes": self.fileSize(url), "item": item], nil)
            }
        }
    }

    // MARK: MP4 — cut, cropped and re-encoded by AVFoundation, with sound

    func makeClip(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard let film = currentFilm else {
            return reply(["ok": false, "error": "Pull a moment, or open a file, first"], nil)
        }
        guard saveFolder != nil else { return reply(["ok": false, "error": "Choose a folder first"], nil) }
        guard let folder = outputFolder("Motion") else {
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

        let natural = source.naturalSize.applying(source.preferredTransform)
        let frameSize = CGSize(width: abs(natural.width), height: abs(natural.height))
        let (crop, out) = geometry(b, even: true, frame: frameSize)   // H.264 wants even sizes
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
                    let item = self.register(kind: "clip", file: url, meta: b["meta"] as? [String: Any])
                    reply(["ok": true, "name": url.lastPathComponent, "bytes": self.fileSize(url), "item": item], nil)
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

// MARK: - Links: finding the video, pulling only your section

extension VaultHost {
    /// The two helpers live in Application Support, fetched on first use.
    /// yt-dlp finds the video behind a link; ffmpeg fetches just the section.
    var binDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("NeededVault/bin", isDirectory: true)
    }
    var ytdlp: URL { binDir.appendingPathComponent("yt-dlp") }
    var ffmpeg: URL { binDir.appendingPathComponent("ffmpeg") }

    func helpersReady() -> Bool {
        FileManager.default.isExecutableFile(atPath: ytdlp.path)
            && FileManager.default.isExecutableFile(atPath: ffmpeg.path)
    }

    func setupHelpers(force: Bool, _ reply: @escaping (Any?, String?) -> Void) {
        if helpersReady() && !force { return reply(["ok": true], nil) }
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x64"
        #endif
        let jobs: [(URL, URL, Double, Double)] = [
            (URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!, ytdlp, 0.0, 0.3),
            (URL(string: "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/ffmpeg-darwin-\(arch)")!, ffmpeg, 0.3, 0.7),
        ]
        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        jobProgress = 0

        func run(_ i: Int) {
            if i == jobs.count {
                return DispatchQueue.main.async {
                    self.downloadObservation = nil
                    reply(["ok": self.helpersReady()], nil)
                }
            }
            let (source, dest, offset, weight) = jobs[i]
            let task = URLSession.shared.downloadTask(with: source) { tmp, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard let tmp = tmp, error == nil, status == 200 else {
                    return DispatchQueue.main.async {
                        self.downloadObservation = nil
                        reply(["ok": false, "error": "Couldn't download the link tools — check your connection and try again"], nil)
                    }
                }
                try? FileManager.default.removeItem(at: dest)
                do { try FileManager.default.moveItem(at: tmp, to: dest) } catch {
                    return DispatchQueue.main.async {
                        reply(["ok": false, "error": "Couldn't install the link tools"], nil)
                    }
                }
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
                // Apple Silicon won't run code with no signature at all; a local,
                // ad-hoc signature is enough.
                let sign = Process()
                sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                sign.arguments = ["--force", "--sign", "-", dest.path]
                try? sign.run(); sign.waitUntilExit()
                run(i + 1)
            }
            downloadObservation = task.progress.observe(\.fractionCompleted) { p, _ in
                self.jobProgress = offset + p.fractionCompleted * weight
            }
            task.resume()
        }
        run(0)
    }

    /// Run a helper; stream its output lines; call back on the main thread.
    @discardableResult
    func runHelper(_ exe: URL, _ args: [String], onLine: ((String) -> Void)? = nil,
                   done: @escaping (Int32, String, String) -> Void) -> Process? {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = binDir.path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        var outData = Data(), errData = Data()
        let lock = NSLock()
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            lock.lock(); outData.append(d); lock.unlock()
            if let onLine = onLine, let s = String(data: d, encoding: .utf8) {
                s.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).forEach { onLine(String($0)) }
            }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            lock.lock(); errData.append(d); lock.unlock()
            if let onLine = onLine, let s = String(data: d, encoding: .utf8) {
                s.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).forEach { onLine(String($0)) }
            }
        }
        p.terminationHandler = { proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            lock.lock()
            outData.append(out.fileHandleForReading.readDataToEndOfFile())
            errData.append(err.fileHandleForReading.readDataToEndOfFile())
            let o = String(data: outData, encoding: .utf8) ?? ""
            let e = String(data: errData, encoding: .utf8) ?? ""
            lock.unlock()
            DispatchQueue.main.async { done(proc.terminationStatus, o, e) }
        }
        do { try p.run() } catch {
            DispatchQueue.main.async { done(-1, "", "Couldn't start the link tools") }
            return nil
        }
        return p
    }

    /// Turn yt-dlp's errors into something a person can act on.
    func explain(_ stderr: String) -> String {
        let e = stderr.lowercased()
        if e.contains("confirm you") && e.contains("bot") {
            return "YouTube is asking to confirm you're not a bot. Try again later, or on a different network"
        }
        if e.contains("private video") { return "That video is private" }
        if e.contains("login") || e.contains("log in") || e.contains("cookies") || e.contains("sign in to") {
            return "That one needs you to be signed in to the site, so it can't be pulled"
        }
        if e.contains("rate") && e.contains("limit") { return "The site is limiting requests for now — try again in a little while" }
        if e.contains("no video") || e.contains("there is no video") { return "That post doesn't have a video in it" }
        if e.contains("age") && (e.contains("confirm your age") || e.contains("age-restricted") || e.contains("inappropriate")) {
            return "That video is age-restricted, so it can't be pulled"
        }
        if e.contains("drm") { return "That video is copy-protected, so it can't be pulled" }
        if e.contains("unsupported url") { return "That site isn't supported" }
        if e.contains("unavailable") || e.contains("not available") { return "That video isn't available" }
        if e.contains("unable to download") || e.contains("urlopen error") || e.contains("timed out") {
            return "Couldn't reach that site — check your connection"
        }
        return "Couldn't read that link. If it's YouTube, try Update link tools"
    }

    func lookup(_ raw: String, _ reply: @escaping (Any?, String?) -> Void) {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return reply(["ok": false, "error": "That doesn't look like a web link"], nil)
        }
        guard helpersReady() else { return reply(["ok": false, "needsHelpers": true], nil) }
        currentProcess = runHelper(ytdlp, ["-J", "--no-playlist", "--playlist-items", "1", "--no-warnings", url.absoluteString]) { status, out, err in
            self.currentProcess = nil
            guard status == 0, let data = out.data(using: .utf8),
                  var info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return reply(["ok": false, "error": self.explain(err)], nil)
            }
            // A post with several videos (an Instagram carousel) comes back as a
            // list: take the first one that has video.
            if info["formats"] == nil, let entries = info["entries"] as? [[String: Any]],
               let first = entries.first(where: { $0["formats"] != nil }) {
                var merged = first
                if (merged["webpage_url"] as? String ?? "").isEmpty { merged["webpage_url"] = info["webpage_url"] }
                info = merged
            }
            let formats = (info["formats"] as? [[String: Any]]) ?? []
            func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
            func shortSide(_ f: [String: Any]) -> Double {
                let w = num(f["width"]), h = num(f["height"])
                return w > 0 && h > 0 ? min(w, h) : h
            }
            func str(_ v: Any?) -> String { (v as? String) ?? "" }
            // For watching and choosing the moment: something WebKit plays
            // directly — MP4 or HLS, ideally with sound, no bigger than 720p.
            let playable = formats.filter { f in
                let proto = str(f["protocol"]), vc = str(f["vcodec"])
                // A blank codec means unknown (plain video links) — only "none" means no picture.
                return !str(f["url"]).isEmpty && vc != "none"
                    && (proto == "https" || proto == "http" || proto.hasPrefix("m3u8"))
                    && (str(f["ext"]) == "mp4" || proto.hasPrefix("m3u8"))
                    && shortSide(f) <= 720          // by the short side, so portrait reels count
            }
            let withSound = playable.filter { str($0["acodec"]) != "none" && !str($0["acodec"]).isEmpty }
            let pick = (withSound.isEmpty ? playable : withSound).max { shortSide($0) < shortSide($1) }
            guard let preview = pick, let previewURL = preview["url"] as? String else {
                return reply(["ok": false, "error": formats.isEmpty ? "That post doesn't have a video in it"
                              : "Found the video, but not in a form this Mac can play for choosing the moment"], nil)
            }
            // The best picture available for grabbing frames and making clips.
            let usable = formats.filter { f in
                let vc = str(f["vcodec"]), proto = str(f["protocol"])
                return !str(f["url"]).isEmpty && vc != "none"
                    && (proto == "https" || proto == "http" || proto.hasPrefix("m3u8"))
                    && num(f["height"]) <= 1920 && num(f["width"]) <= 1920
            }
            let best = usable.max { shortSide($0) < shortSide($1) } ?? preview
            var headerLines = ""
            if let h = best["http_headers"] as? [String: String] {
                headerLines = h.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
            }
            reply([
                "ok": true,
                "grab": str(best["url"]).isEmpty ? previewURL : str(best["url"]),
                "headers": headerLines,
                "bestWidth": num(best["width"]) > 0 ? num(best["width"]) : num(preview["width"]),
                "bestHeight": num(best["height"]) > 0 ? num(best["height"]) : num(preview["height"]),
                "id": str(info["id"]),
                "title": str(info["title"]),
                "uploader": str(info["uploader"]).isEmpty ? str(info["channel"]) : str(info["uploader"]),
                "site": str(info["extractor_key"]),
                "duration": num(info["duration"]),
                "thumbnail": str(info["thumbnail"]),
                "url": str(info["webpage_url"]).isEmpty ? url.absoluteString : str(info["webpage_url"]),
                "preview": previewURL,
                "previewHasSound": str(preview["acodec"]) != "none",
                "previewHeight": num(preview["height"]),
                "fps": num(preview["fps"]) > 0 ? num(preview["fps"]) : (num(info["fps"]) > 0 ? num(info["fps"]) : 25),
            ], nil)
        }
    }

    /// Sites often refuse to play their streams outside their own player.
    /// This fetches a small, low-quality copy to scrub against — stills and
    /// clips still come from the full-quality source.
    func preview(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard helpersReady() else { return reply(["ok": false, "needsHelpers": true], nil) }
        guard let vault = saveFolder else { return reply(["ok": false, "error": "Choose a vault folder first"], nil) }
        guard let raw = b["url"] as? String, let url = URL(string: raw) else {
            return reply(["ok": false, "error": "That doesn't look like a web link"], nil)
        }
        let folder = vault.appendingPathComponent(".vault/previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = (b["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString.prefix(8).lowercased()
        let stem = "preview-" + projectName(String(id)).replacingOccurrences(of: " ", with: "-")
        let existing = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .first { $0.lastPathComponent.hasPrefix(stem) && $0.pathExtension == "mp4" }
        if let have = existing, fileSize(have) > 0 {
            return reply(["ok": true, "path": "/vault/.vault/previews/" + have.lastPathComponent, "cached": true], nil)
        }
        jobProgress = 0
        jobCancel = false
        currentProcess = runHelper(ytdlp, [
            "--no-playlist", "--playlist-items", "1", "--no-warnings", "--newline",
            "--ffmpeg-location", ffmpeg.path,
            "-f", "b[height<=480]/bv*[height<=480]+ba/b",
            "-S", "res:480,+size",
            "--merge-output-format", "mp4",
            "-o", folder.appendingPathComponent(stem + ".%(ext)s").path,
            url.absoluteString,
        ], onLine: { line in
            if line.hasPrefix("[download]"), let pct = line.split(separator: " ").first(where: { $0.hasSuffix("%") }),
               let v = Double(pct.dropLast()) {
                self.jobProgress = max(self.jobProgress, min(0.98, v / 100))
            }
        }) { status, _, err in
            self.currentProcess = nil
            let made = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
                .first { $0.lastPathComponent.hasPrefix(stem) && $0.pathExtension == "mp4" }
            if self.jobCancel {
                if let m = made { try? FileManager.default.removeItem(at: m) }
                return reply(["ok": false, "cancelled": true, "error": "Stopped"], nil)
            }
            guard status == 0, let file = made else {
                return reply(["ok": false, "error": self.explain(err)], nil)
            }
            self.jobProgress = 1
            reply(["ok": true, "path": "/vault/.vault/previews/" + file.lastPathComponent], nil)
        }
    }

    /// A single frame from a link, at full quality — no downloading the video.
    /// Tries the stream directly; if the site refuses (YouTube usually does)
    /// or the page asks to skip that, fetches a sliver through yt-dlp and
    /// takes the frame from that.
    func grabFrame(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard helpersReady() else { return reply(["ok": false, "needsHelpers": true], nil) }
        let at = max(0, (b["t"] as? NSNumber)?.doubleValue ?? 0)
        let stream = (b["url"] as? String) ?? ""
        let page = (b["page"] as? String) ?? ""
        guard !stream.isEmpty || !page.isEmpty else {
            return reply(["ok": false, "error": "No picture to grab from"], nil)
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nv-frame-\(UUID().uuidString.prefix(8)).jpg")

        func finish(_ data: Data) {
            var w = 0.0, h = 0.0
            if let src = CGImageSourceCreateWithData(data as CFData, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
                h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
            }
            reply(["ok": true, "data": data.base64EncodedString(), "w": w, "h": h], nil)
        }

        func viaSliver(_ earlierError: String) {
            guard !page.isEmpty else { return reply(["ok": false, "error": explain(earlierError)], nil) }
            let sliver = FileManager.default.temporaryDirectory
                .appendingPathComponent("nv-sliver-\(UUID().uuidString.prefix(8))")
            runHelper(ytdlp, [
                "--no-playlist", "--playlist-items", "1", "--no-warnings",
                "--ffmpeg-location", ffmpeg.path,
                "-f", "bv*[height<=1920][width<=1920]/b",
                "--download-sections", "*\(String(format: "%.3f", at))-\(String(format: "%.3f", at + 0.4))",
                "-o", sliver.path + ".%(ext)s", page,
            ]) { st2, _, err2 in
                let got = (try? FileManager.default.contentsOfDirectory(
                    at: sliver.deletingLastPathComponent(), includingPropertiesForKeys: nil))?
                    .first { $0.lastPathComponent.hasPrefix(sliver.lastPathComponent) }
                guard st2 == 0, let clip = got else {
                    return reply(["ok": false, "error": self.explain(err2.isEmpty ? earlierError : err2)], nil)
                }
                self.runHelper(self.ffmpeg, [
                    "-hide_banner", "-loglevel", "error", "-i", clip.path,
                    "-frames:v", "1", "-q:v", "2", "-y", tmp.path,
                ]) { st3, _, err3 in
                    try? FileManager.default.removeItem(at: clip)
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    guard st3 == 0, let data = try? Data(contentsOf: tmp), !data.isEmpty else {
                        return reply(["ok": false, "error": self.explain(err3)], nil)
                    }
                    finish(data)
                }
            }
        }

        // YouTube nearly always refuses the direct request — go straight to
        // what works rather than waiting to be turned away.
        if (b["skipDirect"] as? Bool) == true || stream.isEmpty { return viaSliver("") }

        var args = ["-hide_banner", "-loglevel", "error"]
        if let headers = b["headers"] as? String, !headers.isEmpty {
            args += ["-headers", headers + "\r\n"]
        }
        args += ["-ss", String(format: "%.3f", at), "-i", stream, "-frames:v", "1", "-q:v", "2", "-y", tmp.path]
        runHelper(ffmpeg, args) { status, _, err in
            if status == 0, let data = try? Data(contentsOf: tmp), !data.isEmpty {
                try? FileManager.default.removeItem(at: tmp)
                return finish(data)
            }
            try? FileManager.default.removeItem(at: tmp)
            viaSliver(err)
        }
    }

    /// Pull only the section you chose — never the whole video — at up to
    /// 1080p, H.264 so every Mac can read it, cut exactly at your in and out.
    func pull(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard helpersReady() else { return reply(["ok": false, "needsHelpers": true], nil) }
        guard let vault = saveFolder else { return reply(["ok": false, "error": "Choose a vault folder first"], nil) }
        guard let raw = b["url"] as? String, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return reply(["ok": false, "error": "That doesn't look like a web link"], nil)
        }
        let start = max(0, (b["start"] as? NSNumber)?.doubleValue ?? 0)
        var end = (b["end"] as? NSNumber)?.doubleValue ?? 0
        end = min(end, start + 10.05)                      // ten seconds, most
        guard end > start + 0.05 else { return reply(["ok": false, "error": "Set an in and an out first"], nil) }
        let pulls = vault.appendingPathComponent(".vault/pulls", isDirectory: true)
        try? FileManager.default.createDirectory(at: pulls, withIntermediateDirectories: true)
        let stem = "pull-" + UUID().uuidString.prefix(8).lowercased()
        let t = { (x: Double) in String(format: "%.3f", x) }
        let length = end - start
        jobProgress = 0
        jobCancel = false

        currentProcess = runHelper(ytdlp, [
            "--no-playlist", "--playlist-items", "1", "--no-warnings", "--newline",
            "--ffmpeg-location", ffmpeg.path,
            // Up to 1920 on the long side — 1080p landscape or a full-size portrait reel.
            "-f", "bv*[height<=1920][width<=1920]+ba/b[height<=1920][width<=1920]/bv*+ba/b",
            "-S", "vcodec:h264,res:1080,acodec:m4a",
            "--download-sections", "*\(t(start))-\(t(end))",
            "--force-keyframes-at-cuts",
            "--merge-output-format", "mp4",
            "-o", pulls.appendingPathComponent(stem + ".%(ext)s").path,
            url.absoluteString,
        ], onLine: { line in
            // yt-dlp reports "[download]  42.3%"; ffmpeg reports "time=00:00:03.20".
            if line.hasPrefix("[download]"), let pct = line.split(separator: " ").first(where: { $0.hasSuffix("%") }),
               let v = Double(pct.dropLast()) {
                self.jobProgress = max(self.jobProgress, min(0.98, v / 100))
            }
            if let r = line.range(of: "time=") {
                let parts = line[r.upperBound...].prefix(11).split(separator: ":")
                if parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]),
                   let s = Double(parts[2].prefix(5)) {
                    self.jobProgress = max(self.jobProgress, min(0.98, (h * 3600 + m * 60 + s) / max(0.1, length)))
                }
            }
        }) { status, _, err in
            self.currentProcess = nil
            let made = (try? FileManager.default.contentsOfDirectory(at: pulls, includingPropertiesForKeys: nil))?
                .first { $0.lastPathComponent.hasPrefix(stem) && $0.pathExtension == "mp4" }
            if self.jobCancel {
                if let m = made { try? FileManager.default.removeItem(at: m) }
                return reply(["ok": false, "cancelled": true, "error": "Stopped"], nil)
            }
            guard status == 0, let file = made else {
                return reply(["ok": false, "error": self.explain(err)], nil)
            }
            self.currentFilm = file                            // stills, GIFs and clips work from this
            self.jobProgress = 1
            reply(["ok": true, "path": "/vault/.vault/pulls/" + file.lastPathComponent,
                   "bytes": self.fileSize(file)], nil)
        }
    }
}

// MARK: - The library

extension VaultHost {
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
        let here = saveFolder?.path ?? ""
        guard let u = indexURL, FileManager.default.fileExists(atPath: u.path) else {
            index = []; indexLoadedFor = here; return                       // a new vault: nothing in it yet
        }
        guard let d = try? Data(contentsOf: u), let items = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else {
            // Couldn't read it just now: keep what we have rather than show — and later save — an empty vault.
            if indexLoadedFor != here { index = []; indexLoadedFor = here }
            return
        }
        index = items
        indexLoadedFor = here
    }

    func saveIndex() {
        if holdIndexSaves { return }
        guard let u = indexURL else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: index, options: []) {
            try? d.write(to: u, options: .atomic)
        }
    }

    /// Every still, GIF and clip is remembered with where it came from.
    /// The colours a picture is made of: shrink it, group near-identical colours,
    /// keep the five that cover the most of it (skipping ones too close to another).
    func palette(of url: URL) -> [String]? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                     kCGImageSourceThumbnailMaxPixelSize: 48] as CFDictionary) else { return nil }
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
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

    /// Copy files into the current project's References — stills, GIFs and clips
    /// each to their own folder — and tell the page. Returns how many came in.
    @discardableResult
    func importFiles(_ urls: [URL]) -> Int {
        guard saveFolder != nil else {
            webView.evaluateJavaScript("window.__vaultImported && window.__vaultImported({ ok: false, error: 'Choose your vault first' })", completionHandler: nil)
            return 0
        }
        let fm = FileManager.default
        var added = 0
        loadIndex()                                  // the latest list, then one save for the whole batch
        holdIndexSaves = true
        for u in urls {
            let ext = u.pathExtension.lowercased()
            let kind = ext == "gif" ? "gif" : ["mov", "mp4", "m4v", "webm"].contains(ext) ? "clip" : "still"
            guard let folder = outputFolder(kind == "gif" ? "GIFs" : kind == "clip" ? "Motion" : "Stills") else { continue }
            let target = uniqueURL(in: folder, name: u.lastPathComponent)
            guard (try? fm.copyItem(at: u, to: target)) != nil else { continue }
            let meta: [String: Any] = ["source": ["type": "file", "title": u.deletingPathExtension().lastPathComponent], "origin": "reference"]
            _ = register(kind: kind, file: target, meta: meta, project: currentProject)
            added += 1
        }
        holdIndexSaves = false
        saveIndex()
        Shared.notify()
        webView.evaluateJavaScript("window.__vaultImported && window.__vaultImported({ ok: true, added: \(added), project: \(Shell.js(currentProject)) })", completionHandler: nil)
        return added
    }

    /// Sync: look through one project's folders for anything the vault doesn't
    /// know yet — from Needed Grab, or you in Finder — and fill in whatever's
    /// missing (small previews, colour palettes). This is the only scan: nothing
    /// looks through the folders by itself any more.
    /// The slow part (reading every file) runs in the background; the list is
    /// only touched on the main thread, at the end.
    func sync(project raw: String, progress: @escaping (Double) -> Void, done: @escaping ([String: Any]) -> Void) {
        guard let base = saveFolder else { return done(["ok": false, "error": "Choose your vault first"]) }
        guard !syncing else { return done(["ok": false, "error": "Already syncing"]) }
        syncing = true
        loadIndex()
        let project = projectName(raw)
        let known = Set(index.compactMap { $0["file"] as? String })
        // what this project's items are missing: a preview of their own, or colours
        let needThumb: [(String, String)] = index.compactMap { it -> (String, String)? in
            guard (it["project"] as? String) == project, let id = it["id"] as? String, let kind = it["kind"] as? String,
                  kind == "still" || kind == "gif", let file = it["file"] as? String, (it["thumb"] as? String) == file else { return nil }
            return (id, file)
        }
        let needPalette: [(String, String)] = index.compactMap { it -> (String, String)? in
            guard (it["project"] as? String) == project, ["still", "gif", "clip"].contains(it["kind"] as? String ?? ""),
                  (it["palette"] as? [String])?.isEmpty ?? true, let id = it["id"] as? String,
                  let rel = (it["thumb"] as? String) ?? (it["file"] as? String) else { return nil }
            return (id, rel)
        }
        let kinds: [(String, String, Set<String>)] = [
            ("Stills", "still", ["jpg", "jpeg", "png", "webp", "heic", "tif", "tiff"]),
            ("GIFs", "gif", ["gif"]),
            ("Motion", "clip", ["mp4", "mov", "m4v"]),
        ]
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let proj = base.appendingPathComponent(project, isDirectory: true)
            // 1. every file in the project's folders that the vault hasn't got
            var found: [(URL, String, String)] = []            // file, kind, grab or reference
            for (folder, kind, exts) in kinds {
                for (sub, origin) in Folders.all(folder, project: project) {
                    let dir = proj.appendingPathComponent(sub, isDirectory: true)
                    for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
                        guard exts.contains(f.pathExtension.lowercased()) else { continue }
                        let rel = f.path.replacingOccurrences(of: base.path + "/", with: "")
                        if !known.contains(rel) { found.append((f, kind, origin)) }
                    }
                }
            }
            let total: Double = Double(max(1, found.count + needThumb.count + needPalette.count))
            var step: Double = 0
            let tick: () -> Void = {
                step += 1
                let f: Double = step / total
                DispatchQueue.main.async { progress(f) }
            }
            // 2. each new one gets its preview and colours, the way register() does it
            let stamp = ISO8601DateFormatter().string(from: Date())
            var added: [[String: Any]] = []
            for (f, kind, origin) in found {
                let id = UUID().uuidString
                let rel = f.path.replacingOccurrences(of: base.path + "/", with: "")
                var thumbRel = rel
                if kind == "clip", let t = self.poster(for: f, id: id) { thumbRel = t.path.replacingOccurrences(of: base.path + "/", with: "") }
                else if kind != "clip", let t = self.smallThumb(for: f, id: id) { thumbRel = t.path.replacingOccurrences(of: base.path + "/", with: "") }
                let source: [String: Any] = ["type": "file", "title": f.deletingPathExtension().lastPathComponent]
                var item: [String: Any] = ["id": id, "kind": kind, "file": rel, "thumb": thumbRel, "project": project]
                item["bytes"] = self.fileSize(f)
                item["created"] = stamp
                item["source"] = source
                item["origin"] = origin
                if let p = self.palette(of: base.appendingPathComponent(thumbRel)), !p.isEmpty { item["palette"] = p }
                added.append(item)
                tick()
            }
            // 3. older items: their own small preview, and their colours
            var thumbs: [String: String] = [:], palettes: [String: [String]] = [:]
            for (id, file) in needThumb {
                if let t = self.smallThumb(for: base.appendingPathComponent(file), id: id) { thumbs[id] = t.path.replacingOccurrences(of: base.path + "/", with: "") }
                tick()
            }
            for (id, rel) in needPalette {
                if let p = self.palette(of: base.appendingPathComponent(thumbs[id] ?? rel)), !p.isEmpty { palettes[id] = p }
                tick()
            }
            // 4. back on the main thread: into the list, once
            DispatchQueue.main.async {
                self.syncing = false
                guard self.saveFolder == base else { return done(["ok": false, "error": "The vault changed while syncing"]) }
                self.loadIndex()                                             // the list as it is now, then ours on top
                let now = Set(self.index.compactMap { $0["file"] as? String })   // anything saved meanwhile isn't added twice
                let fresh = added.filter { !now.contains($0["file"] as? String ?? "") }
                for i in self.index.indices {
                    guard let id = self.index[i]["id"] as? String else { continue }
                    if let t = thumbs[id] { self.index[i]["thumb"] = t }
                    if let p = palettes[id] { self.index[i]["palette"] = p }
                }
                self.index.insert(contentsOf: fresh, at: 0)
                self.saveIndex()
                Shared.notify()
                done(["ok": true, "project": project, "added": fresh.count, "palettes": palettes.count, "previews": thumbs.count])
            }
        }
    }

    func register(kind: String, file: URL, meta: [String: Any]?, project: String? = nil) -> [String: Any] {
        // Start from the list as it is on disk: another tool may have saved since.
        if !holdIndexSaves || indexLoadedFor != (saveFolder?.path ?? "") { loadIndex() }
        guard let base = saveFolder else { return [:] }
        let id = UUID().uuidString
        let rel = file.path.replacingOccurrences(of: base.path + "/", with: "")
        var thumbRel = rel
        if kind == "clip", let thumb = poster(for: file, id: id) {
            thumbRel = thumb.path.replacingOccurrences(of: base.path + "/", with: "")
        } else if kind == "still" || kind == "gif", let thumb = smallThumb(for: file, id: id) {
            thumbRel = thumb.path.replacingOccurrences(of: base.path + "/", with: "")   // the grid never loads the full file
        }
        var item: [String: Any] = [
            "id": id, "kind": kind, "file": rel, "thumb": thumbRel, "project": projectName(project ?? currentProject),
            "bytes": fileSize(file),
            "created": ISO8601DateFormatter().string(from: Date()),
        ]
        for key in ["source", "at", "end", "crop", "tags", "note", "w", "h", "palette", "boards", "title", "text"] {
            if let v = meta?[key] { item[key] = v }
        }
        // Every picture gets its colours, however it arrived.
        if (item["palette"] as? [String])?.isEmpty ?? true, kind != "idea", let p = palette(of: base.appendingPathComponent(thumbRel)), !p.isEmpty {
            item["palette"] = p
        }
        index.insert(item, at: 0)
        saveIndex()
        return item
    }

    /// A small JPEG for the grid — ImageIO reads just enough of the file to make it.
    func smallThumb(for file: URL, id: String) -> URL? {
        guard let base = saveFolder, let src = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
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

    /// Move or copy references into another project: the files go into that
    /// project's matching folder (Stills, GIFs, Motion, Ideas) and the vault
    /// follows. Nothing is overwritten — a clashing name gets a number.
    func moveItems(_ b: [String: Any]) -> [String: Any] {
        guard let base = saveFolder else { return ["ok": false, "error": "Choose your vault first"] }
        let ids = Set((b["ids"] as? [String]) ?? [])
        let to = projectName(b["project"] as? String)
        let copying = (b["copy"] as? Bool) ?? false
        let fm = FileManager.default
        var done = 0, renamed: [String] = [], failed: [String] = [], copies: [[String: Any]] = []
        loadIndex()
        holdIndexSaves = true
        defer { holdIndexSaves = false; saveIndex() }
        for i in index.indices {
            guard let id = index[i]["id"] as? String, ids.contains(id), let rel = index[i]["file"] as? String else { continue }
            if !copying && (index[i]["project"] as? String) == to { continue }
            let src = base.appendingPathComponent(rel)
            var dir = base.appendingPathComponent(to, isDirectory: true)
            let from = rel.split(separator: "/").first.map(String.init) ?? ""
            for part in rel.split(separator: "/").dropFirst().dropLast() {
                // Lexus_Grab and Lexus_Vault take the new project's name: Nike_Grab, Nike_Vault
                var name = String(part)
                if name == "\(from)_Grab" { name = "\(to)_Grab" } else if name == "\(from)_Vault" { name = "\(to)_Vault" }
                dir = dir.appendingPathComponent(name, isDirectory: true)
            }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dst = uniqueURL(in: dir, name: src.lastPathComponent)
            do { if copying { try fm.copyItem(at: src, to: dst) } else { try fm.moveItem(at: src, to: dst) } }
            catch { failed.append(src.lastPathComponent); continue }
            if dst.lastPathComponent != src.lastPathComponent { renamed.append(dst.lastPathComponent) }
            let newRel = dst.path.replacingOccurrences(of: base.path + "/", with: "")
            if copying {
                var item = index[i]
                let nid = UUID().uuidString
                item["id"] = nid; item["file"] = newRel; item["project"] = to
                item["created"] = ISO8601DateFormatter().string(from: Date())
                // its own thumbnail, so removing one never takes the other's
                if let t = item["thumb"] as? String {
                    if t.hasPrefix(".vault/thumbs/") {
                        let nt = ".vault/thumbs/\(nid).jpg"
                        if (try? fm.copyItem(at: base.appendingPathComponent(t), to: base.appendingPathComponent(nt))) != nil { item["thumb"] = nt }
                    } else if t == rel { item["thumb"] = newRel }
                }
                copies.append(item)
            } else {
                if (index[i]["thumb"] as? String) == rel { index[i]["thumb"] = newRel }
                index[i]["file"] = newRel
                index[i]["project"] = to
            }
            done += 1
        }
        index.insert(contentsOf: copies, at: 0)
        return ["ok": failed.isEmpty, "done": done, "renamed": renamed, "failed": failed, "project": to]
    }

    func updateItem(_ b: [String: Any]) {
        loadIndex()                                  // the latest list, so no one else's saves are lost
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
        loadIndex()
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


// MARK: - Grab & Go

/// Save images from the web straight into the current project:
/// Copy Image in any browser (while Grab & Go is on), drag onto the window,
/// or right-click → Save to Needed Vault with the Chrome extension.
final class GrabAndGo {
    weak var app: VaultHost?
    private(set) var on = false
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var listener: NWListener?
    static let port: NWEndpoint.Port = 47631

    func setOn(_ v: Bool) {
        on = v
        defer { Shared.notify() }      // the top bar shows it too
        timer?.invalidate(); timer = nil
        guard v else { return }
        lastChange = NSPasteboard.general.changeCount            // what's already copied isn't saved
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard !NSApp.isActive else { return }                     // a copy inside the Vault isn't a grab
        let image = pb.data(forType: .png) ?? pb.data(forType: .tiff)
        let html = pb.string(forType: .html) ?? ""
        guard image != nil || html.range(of: "<img", options: .caseInsensitive) != nil else { return }
        // where it came from: Safari leaves a web archive, Chrome a source address
        var page = ""
        if let wa = pb.data(forType: NSPasteboard.PasteboardType("com.apple.webarchive")),
           let plist = try? PropertyListSerialization.propertyList(from: wa, format: nil) as? [String: Any],
           let main = plist["WebMainResource"] as? [String: Any], let u = main["WebResourceURL"] as? String { page = u }
        if page.isEmpty, let s = pb.string(forType: NSPasteboard.PasteboardType("org.chromium.source-url")) { page = s }
        let imageURL = pb.string(forType: .URL) ?? pb.string(forType: NSPasteboard.PasteboardType("public.url")) ?? ""
        app?.grab(imageData: image, html: html, imageURL: imageURL, page: page, via: "copy")
    }

    // ---- the Chrome extension talks to this: your own Mac only, nothing from outside
    func listen() {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params, on: GrabAndGo.port) else { return }
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        l.start(queue: .main)
        listener = l
    }

    private func serve(_ c: NWConnection) {
        c.start(queue: .main)
        var buf = Data()
        func read() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
                if let d = data { buf.append(d) }
                if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(decoding: buf[..<end.lowerBound], as: UTF8.self)
                    let lines = head.components(separatedBy: "\r\n")
                    var headers: [String: String] = [:]
                    for l in lines.dropFirst() { if let i = l.firstIndex(of: ":") {
                        headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
                    let want = Int(headers["content-length"] ?? "0") ?? 0
                    let body = buf[end.upperBound...]
                    if body.count >= want { self?.handle(c, request: lines.first ?? "", headers: headers, body: Data(body.prefix(want))); return }
                }
                if done || err != nil || buf.count > 2_000_000 { c.cancel(); return }
                read()
            }
        }
        read()
    }

    private func handle(_ c: NWConnection, request: String, headers: [String: String], body: Data) {
        // A web page can't send this header without asking first, and we never
        // say yes — so only the extension (or you) can save through here.
        guard request.hasPrefix("POST /grab "), headers["x-needed-vault"] == "1",
              let j = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let img = j["img"] as? String, !img.isEmpty else {
            return respond(c, "403 Forbidden", ["ok": false])
        }
        guard let app = app, app.saveFolder != nil else { return respond(c, "409 Conflict", ["ok": false, "error": "Open Needed Vault and choose your vault"]) }
        respond(c, "200 OK", ["ok": true, "project": app.currentProject])
        app.grab(imageData: nil, html: (j["html"] as? String) ?? "", imageURL: img, page: (j["page"] as? String) ?? "", via: "extension")
    }

    private func respond(_ c: NWConnection, _ status: String, _ obj: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        var out = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }
}

extension VaultHost {
    /// Every address that might hold a bigger version, biggest first.
    func grabCandidates(html: String, imageURL: String, page: String) -> [URL] {
        var urls: [String] = []
        let decode = { (s: String) in s.replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespaces) }
        if let tag = html.range(of: #"<img[^>]*>"#, options: [.regularExpression, .caseInsensitive]).map({ String(html[$0]) }) {
            func attr(_ name: String) -> String? {
                guard let r = tag.range(of: name + #"\s*=\s*"([^"]*)""#, options: [.regularExpression, .caseInsensitive]) else { return nil }
                let m = String(tag[r]); guard let q = m.firstIndex(of: "\"") else { return nil }
                return decode(String(m[m.index(after: q)...].dropLast()))
            }
            if let set = attr("srcset") {                     // "a.jpg 480w, b.jpg 1080w" or "a.jpg 1x, b.jpg 2x"
                let ranked = set.split(separator: ",").compactMap { part -> (String, Double)? in
                    let bits = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
                    guard let u = bits.first else { return nil }
                    let size = bits.count > 1 ? Double(bits[1].dropLast()) ?? 1 : 1
                    return (String(u), size)
                }.sorted { $0.1 > $1.1 }
                urls += ranked.map { decode($0.0) }
            }
            if let src = attr("src") { urls.append(src) }
        }
        if !imageURL.isEmpty { urls.append(imageURL) }
        let base = URL(string: page) ?? URL(string: imageURL)
        var out: [URL] = []
        for s in urls {
            guard let u = URL(string: s, relativeTo: base)?.absoluteURL, ["http", "https"].contains(u.scheme ?? "") else { continue }
            // a couple of sites that serve small versions by default
            var h = u.absoluteString
            if h.contains("i.pinimg.com/") { h = h.replacingOccurrences(of: #"i\.pinimg\.com/\d+x/"#, with: "i.pinimg.com/originals/", options: .regularExpression) }
            if h.contains("pbs.twimg.com/"), let r = h.range(of: #"name=[a-z0-9x]+"#, options: .regularExpression) { h.replaceSubrange(r, with: "name=orig") }
            if let better = URL(string: h), better != u, !out.contains(better) { out.append(better) }
            if !out.contains(u) { out.append(u) }
        }
        return out
    }

    /// What an image file really is, from its bytes: sites often label AVIF or
    /// WebP as something else, and a wrongly named file won't open.
    func realExtension(_ data: Data) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(src) as String? else { return nil }
        switch type {
        case "public.jpeg": return "jpg"
        case "public.png": return "png"
        case "com.compuserve.gif": return "gif"
        case "org.webmproject.webp": return "webp"
        case "public.avif": return "avif"
        case "public.heic", "public.heif": return "heic"
        case "public.tiff": return "tiff"
        default: return nil
        }
    }

    private func pixelSize(_ data: Data) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    /// Save one grabbed image into the current project's Stills — the biggest
    /// version we can get, never smaller than what was copied.
    func grab(imageData: Data?, html: String, imageURL: String, page: String, via: String,
              into: String? = nil, origin: String = "reference") {
        guard saveFolder != nil else { return }
        let project = into ?? currentProject
        let candidates = grabCandidates(html: html, imageURL: imageURL, page: page)
        let have = imageData.flatMap { pixelSize($0) }
        DispatchQueue.global(qos: .userInitiated).async {
            var best: (Data, Int, Int, String)? = nil                   // data, w, h, extension
            if let d = imageData, let wh = have { best = (d, wh.0, wh.1, "clip") }
            for u in candidates.prefix(4) {
                var req = URLRequest(url: u, timeoutInterval: 10)
                if let p = URL(string: page) { req.setValue(p.absoluteString, forHTTPHeaderField: "Referer") }
                let wait = DispatchSemaphore(value: 0); var got: Data? = nil; var mime = ""
                URLSession.shared.dataTask(with: req) { d, r, _ in
                    if let http = r as? HTTPURLResponse, http.statusCode == 200 { got = d; mime = http.mimeType ?? "" }
                    wait.signal()
                }.resume()
                _ = wait.wait(timeout: .now() + 12)
                guard let d = got, let wh = self.pixelSize(d) else { continue }
                let (w, h) = wh
                if best == nil || w * h > best!.1 * best!.2 {
                    let ext = self.realExtension(d) ?? (mime.contains("png") ? "png" : mime.contains("webp") ? "webp" : mime.contains("gif") ? "gif" : "jpg")
                    best = (d, w, h, ext)
                }
                break                                               // the biggest candidate that answered wins
            }
            DispatchQueue.main.async {
                guard let found = best, let folder = self.outputFolder("Stills", project: project, area: origin == "grab" ? "Grabs" : "References") else {
                    return self.webView.evaluateJavaScript("window.__grabbed && window.__grabbed({ok:false})", completionHandler: nil)
                }
                let (data, w, h, kind) = found
                // a copied picture arrives as TIFF or PNG: keep it as a high-quality JPEG
                var bytes = data, ext = kind
                if kind == "clip", let rep = NSBitmapImageRep(data: data),
                   let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) { bytes = jpg; ext = "jpg" }
                let host = (URL(string: page)?.host ?? URL(string: imageURL)?.host ?? "web").replacingOccurrences(of: "www.", with: "")
                let stamp = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: Date()) }()
                let target = self.uniqueURL(in: folder, name: "\(host)_\(stamp).\(ext)")
                guard (try? bytes.write(to: target, options: .atomic)) != nil else { return }
                let src: [String: Any] = ["type": "web", "url": page.isEmpty ? imageURL : page, "title": host]
                _ = self.register(kind: "still", file: target, meta: ["source": src, "w": w, "h": h, "origin": origin], project: project)
                Shared.notify()                                   // Home's wall picks it up
                let info: [String: Any] = ["ok": true, "name": target.lastPathComponent, "project": project, "w": w, "h": h,
                                           "bigger": have.map { w * h > $0.0 * $0.1 } ?? false, "via": via]
                if let j = try? JSONSerialization.data(withJSONObject: info), let s = String(data: j, encoding: .utf8) {
                    self.webView.evaluateJavaScript("window.__grabbed && window.__grabbed(\(s))", completionHandler: nil)
                }
            }
        }
    }

    /// The extension, copied somewhere stable (not inside the app, which moves
    /// when you rebuild it), and shown in Finder for Chrome to load.
    func revealExtension() -> Bool {
        guard let inside = Bundle.main.resourceURL?.appendingPathComponent("chrome-extension") else { return false }
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        let there = base.appendingPathComponent("NeededVault/Chrome Extension", isDirectory: true)
        try? fm.createDirectory(at: there.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: there)
        guard (try? fm.copyItem(at: inside, to: there)) != nil else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([there])
        return true
    }
}


// MARK: - Mood boards

extension VaultHost {
    /// A mood board: a PDF of stills and nothing else — no titles, no captions.
    /// Each page is rows of pictures in their own shapes, filling the page
    /// edge to edge with a small gap. It saves into Lexus › Lexus_Vault › Mood.
    func moodBoard(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard let base = saveFolder else { return reply(["ok": false, "error": "Choose your vault first"], nil) }
        let rels = ((b["files"] as? [String]) ?? []).filter { !$0.contains("..") && !$0.hasPrefix("/") }
        guard !rels.isEmpty else { return reply(["ok": false, "error": "No stills to put on it"], nil) }
        let perPage = max(1, min(12, (b["perPage"] as? NSNumber)?.intValue ?? 6))
        let dark = (b["background"] as? String) == "dark"
        let project = projectName((b["project"] as? String) ?? currentProject)
        var name = ((b["name"] as? String) ?? "Mood board").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "Mood board" }
        let folder = base.appendingPathComponent(project, isDirectory: true).appendingPathComponent("\(project)_Vault/Mood", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else {
            return reply(["ok": false, "error": "Couldn't make the Mood folder"], nil)
        }
        let target = uniqueURL(in: folder, name: name + ".pdf")

        DispatchQueue.global(qos: .userInitiated).async {
            // Each picture, big enough for a full page and no bigger.
            var pics: [CGImage] = []
            for rel in rels {
                let u = base.appendingPathComponent(rel)
                guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                      let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: perPage == 1 ? 3200 : 2000,
                      ] as CFDictionary) else { continue }
                pics.append(img)
            }
            guard !pics.isEmpty else {
                return DispatchQueue.main.async { reply(["ok": false, "error": "Couldn't read those stills"], nil) }
            }
            // A 16:9 page, like a deck.
            var page = CGRect(x: 0, y: 0, width: 1600, height: 900)
            guard let ctx = CGContext(target as CFURL, mediaBox: &page, nil) else {
                return DispatchQueue.main.async { reply(["ok": false, "error": "Couldn't write the PDF"], nil) }
            }
            let margin: CGFloat = 40, gap: CGFloat = 12
            let area = page.insetBy(dx: margin, dy: margin)
            var pages = 0
            var i = 0
            while i < pics.count {
                let set = Array(pics[i..<min(pics.count, i + perPage)])
                i += set.count
                ctx.beginPDFPage(nil)
                let ground: CGColor = dark ? CGColor(srgbRed: 0.07, green: 0.07, blue: 0.07, alpha: 1)
                                           : CGColor(srgbRed: 0.957, green: 0.953, blue: 0.945, alpha: 1)
                ctx.setFillColor(ground)
                ctx.fill(page)
                let shapes: [CGFloat] = set.map { (img: CGImage) -> CGFloat in CGFloat(img.width) / CGFloat(max(1, img.height)) }
                let rects: [CGRect] = VaultHost.moodLayout(shapes, in: area, gap: gap)
                for (img, r) in zip(set, rects) {
                    ctx.interpolationQuality = .high
                    ctx.draw(img, in: r)
                }
                ctx.endPDFPage()
                pages += 1
            }
            ctx.closePDF()
            DispatchQueue.main.async {
                self.lastOutput = folder
                let rel = target.path.replacingOccurrences(of: base.path + "/", with: "")
                reply(["ok": true, "name": target.lastPathComponent, "file": rel, "pages": pages, "count": pics.count], nil)
            }
        }
    }

    /// Justified rows: the pictures in order, in as many rows as fills the space
    /// best, each row the full width, the whole block centred. PDF coordinates:
    /// the first row is at the top.
    static func moodLayout(_ aspects: [CGFloat], in area: CGRect, gap: CGFloat) -> [CGRect] {
        let n = aspects.count
        guard n > 0 else { return [] }
        var best: (score: CGFloat, rects: [CGRect]) = (-1, [])
        for rowsCount in 1...n {
            // split in order into rowsCount rows of roughly equal total width
            let total: CGFloat = aspects.reduce(0, +)
            let aim: CGFloat = total / CGFloat(rowsCount)
            var rows: [[Int]] = [[]], sum: CGFloat = 0
            for (k, a) in aspects.enumerated() {
                let left = n - k, rowsLeft = rowsCount - rows.count
                if !rows[rows.count - 1].isEmpty && (sum + a / 2 > aim || left <= rowsLeft) && rows.count < rowsCount {
                    rows.append([]); sum = 0
                }
                rows[rows.count - 1].append(k); sum += a
            }
            // each row fills the width; then the lot scales to fit the height
            var heights: [CGFloat] = rows.map { (r: [Int]) -> CGFloat in
                var s: CGFloat = 0
                for i in r { s += aspects[i] }
                let room: CGFloat = area.width - gap * CGFloat(r.count - 1)
                return room / max(s, 0.01)
            }
            let gaps: CGFloat = gap * CGFloat(rows.count - 1)
            let natural: CGFloat = heights.reduce(0, +)
            let k: CGFloat = min(1, (area.height - gaps) / max(natural, 1))
            heights = heights.map { $0 * k }
            let blockH: CGFloat = heights.reduce(0, +) + gaps
            var rects: [CGRect] = []
            var y: CGFloat = area.maxY - (area.height - blockH) / 2
            var covered: CGFloat = 0
            for (ri, r) in rows.enumerated() {
                let h: CGFloat = heights[ri]
                var w: CGFloat = gap * CGFloat(r.count - 1)
                for i in r { w += aspects[i] * h }
                var x: CGFloat = area.minX + (area.width - w) / 2
                y -= h
                for idx in r {
                    let rw: CGFloat = aspects[idx] * h
                    rects.append(CGRect(x: x, y: y, width: rw, height: h))
                    covered += rw * h
                    x += rw + gap
                }
                y -= gap
            }
            let score: CGFloat = covered / (area.width * area.height)
            if score > best.score { best = (score, rects) }
        }
        return best.rects
    }
}

// Needed Pay — native macOS shell.
// This Was Needed · thiswasneeded.info
//
// One file, no packages. Wraps the self-contained web app in a real Mac
// window. The only network request is licence activation, once.
//
// Build:  swiftc -O -target arm64-apple-macos11.3 -o nc-arm64 main.swift licence.swift
//         swiftc -O -target x86_64-apple-macos11.3 -o nc-x64 main.swift licence.swift
//         lipo -create -output "Needed Pay" nc-arm64 nc-x64

import AppKit
import Security
import WebKit
import AVFoundation
import ImageIO
import PDFKit
import MapKit
import Contacts

let payScheme = "neededpay"
let payPageBackground = NSColor(srgbRed: 0xF4 / 255.0, green: 0xF3 / 255.0,
                             blue: 0xF1 / 255.0, alpha: 1)

// MARK: - Serving the app

/// Serves the bundle's Resources over a private scheme.
///
/// Not file:// — a page loaded from file:// has a null origin, and WebKit
/// refuses localStorage on a null origin. The crew memory would seem to
/// work and then be empty on every relaunch. A custom scheme gives the page
/// a stable origin, so storage survives relaunches and app updates.
final class PaySchemeHandler: NSObject, WKURLSchemeHandler {
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

final class PayHost: NSObject, NSApplicationDelegate, NSWindowDelegate,
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
    lazy var addressFinder = AddressFinder()    // Apple's address completion
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
        let scheme = PaySchemeHandler(root: resources.appendingPathComponent("tools/pay"))
        scheme.vaultRoot = { [weak self] in self?.saveFolder }
        config.setURLSchemeHandler(scheme, forURLScheme: payScheme)

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


        if let start = URL(string: "\(payScheme)://app/index.html") {
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
        appMenu.addItem(withTitle: "About Needed Pay",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Needed Pay",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others",
                                     action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Needed Pay",
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

extension PayHost: WKScriptMessageHandlerWithReply {
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

extension PayHost {
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
            panel.message = "Choose your Needed Vault folder — invoices file into its projects"
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

        case "loadLedger", "saveLedger", "previewPdf", "exportPdf", "saveCsv", "revealFile", "addressSuggest", "addressResolve", "emailInvoice", "mailPassword", "sendMail":
            handlePay(action, body, reply)

        default:
            reply(nil, "unknown action")
        }
    }
}

// MARK: - The library

extension PayHost {
    func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// Stills, Shots and the rest sit inside the project folder, each made
    /// the first time something goes in it.
    func outputFolder(_ kind: String) -> URL? {
        guard let base = saveFolder else { return nil }
        let name = projectName(currentProject)
        let folder = base.appendingPathComponent(name, isDirectory: true)
                         .appendingPathComponent(Folders.place(kind, project: name), isDirectory: true)
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
        if n.count > 80 { n = String(n.prefix(80)) }
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

    func loadIndex() { VaultStore.shared.load() }

    func saveIndex() { VaultStore.shared.save() }

    /// Every still, GIF and clip is remembered with where it came from — its
    /// preview and colours are made by the store (Store.swift).
    @discardableResult
    func register(kind: String, file: URL, meta: [String: Any]?) -> [String: Any] {
        VaultStore.shared.register(kind: kind, file: file, meta: meta, project: currentProject)
    }


    func updateItem(_ b: [String: Any]) { VaultStore.shared.update(b) }

    /// Removing moves the file to the Trash, never deletes it outright.
    func removeItem(_ id: String) -> Bool { VaultStore.shared.remove(id) }
}


// MARK: - Addresses

/// Apple's own address completion — the one Maps uses. Needs a connection;
/// when there isn't one it says so, and the page falls back to the
/// addresses you've already used.
final class AddressFinder: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var pending: ((Any?, String?) -> Void)?
    private var token = UUID()
    private var results: [MKLocalSearchCompletion] = []

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func suggest(_ query: String, _ reply: @escaping (Any?, String?) -> Void) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let older = pending { older(["ok": true, "items": [], "stale": true], nil) }   // a newer keystroke wins
        pending = nil
        guard q.count >= 3 else { return reply(["ok": true, "items": []], nil) }
        pending = reply
        let mine = UUID(); token = mine
        completer.queryFragment = q
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.token == mine, let waiting = self.pending else { return }
            self.pending = nil
            waiting(["ok": false, "offline": true], nil)             // no answer in time: treat as offline
        }
    }

    func completerDidUpdateResults(_ c: MKLocalSearchCompleter) {
        results = Array(c.results.prefix(6))
        guard let waiting = pending else { return }
        pending = nil
        waiting(["ok": true, "items": results.enumerated().map { ["i": $0.offset, "title": $0.element.title, "subtitle": $0.element.subtitle] }], nil)
    }

    func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard let waiting = pending else { return }
        pending = nil
        waiting(["ok": false, "offline": true], nil)
    }

    /// The full postal address for a suggestion, laid out the way that
    /// country writes addresses.
    func resolve(_ i: Int, _ reply: @escaping (Any?, String?) -> Void) {
        guard i >= 0, i < results.count else { return reply(["ok": false], nil) }
        let chosen = results[i]
        MKLocalSearch(request: MKLocalSearch.Request(completion: chosen)).start { response, _ in
            let fallback = [chosen.title, chosen.subtitle].filter { !$0.isEmpty }.joined(separator: "\n")
            guard let place = response?.mapItems.first?.placemark else {
                return reply(["ok": true, "address": fallback], nil)
            }
            var text = fallback
            if let postal = place.postalAddress {
                text = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
            }
            reply(["ok": true, "address": text, "country": place.isoCountryCode ?? ""], nil)
        }
    }
}

// MARK: - Invoices

extension PayHost {
    /// The books live in the app itself, so they never depend on the vault
    /// being plugged in. PDFs are also filed into the vault's project.
    var payDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("NeededPay", isDirectory: true)
    }

    func handlePay(_ action: String, _ body: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        let fm = FileManager.default
        switch action {
        case "loadLedger":
            let url = payDir.appendingPathComponent("ledger.json")
            // On a new Mac, the books come back from the copy in the vault.
            let copy = saveFolder?.appendingPathComponent(".vault/pay-ledger.json")
            if let d = (try? Data(contentsOf: url)) ?? copy.flatMap({ try? Data(contentsOf: $0) }), let obj = try? JSONSerialization.jsonObject(with: d) {
                reply(["ledger": obj], nil)
            } else {
                reply(["ledger": NSNull()], nil)
            }

        case "saveLedger":
            guard let ledger = body["ledger"],
                  let data = try? JSONSerialization.data(withJSONObject: ledger, options: [.prettyPrinted, .sortedKeys]) else {
                return reply(["ok": false], nil)
            }
            try? fm.createDirectory(at: payDir, withIntermediateDirectories: true)
            let ok = (try? data.write(to: payDir.appendingPathComponent("ledger.json"), options: .atomic)) != nil
            // A copy in the vault too, so a backup of the vault drive has your books.
            if let v = saveFolder?.appendingPathComponent(".vault", isDirectory: true) {
                try? fm.createDirectory(at: v, withIntermediateDirectories: true)
                try? data.write(to: v.appendingPathComponent("pay-ledger.json"), options: .atomic)
            }
            // A copy a day, the last 30 kept — these are your books.
            let backups = payDir.appendingPathComponent("backups", isDirectory: true)
            try? fm.createDirectory(at: backups, withIntermediateDirectories: true)
            let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
            try? data.write(to: backups.appendingPathComponent("ledger-\(day).json"), options: .atomic)
            if let all = try? fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
                .filter({ $0.lastPathComponent.hasPrefix("ledger-") }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                for old in all.dropFirst(30) { try? fm.removeItem(at: old) }
            }
            reply(["ok": ok], nil)

        case "previewPdf":
            let doc = (body["doc"] as? [String: Any]) ?? [:]
            let width = CGFloat((body["width"] as? NSNumber)?.doubleValue ?? 1100)
            let tmp = fm.temporaryDirectory.appendingPathComponent("needed-pay-preview.pdf")
            try? fm.removeItem(at: tmp)
            guard renderInvoice(doc, to: tmp) != nil, let pdf = PDFDocument(url: tmp) else {
                return reply(["ok": false, "error": "Couldn't draw the preview"], nil)
            }
            var pages: [String] = []
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                let box = page.bounds(for: .mediaBox)
                let thumb = page.thumbnail(of: CGSize(width: width, height: width * box.height / box.width), for: .mediaBox)
                if let tiff = thumb.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) {
                    pages.append(jpg.base64EncodedString())
                }
            }
            reply(["ok": true, "pages": pages], nil)

        case "exportPdf":
            let doc = (body["doc"] as? [String: Any]) ?? [:]
            guard let name = safeName((body["name"] as? String) ?? "") else { return reply(["ok": false, "error": "Bad name"], nil) }
            let mine = payDir.appendingPathComponent("Invoices", isDirectory: true)
            try? fm.createDirectory(at: mine, withIntermediateDirectories: true)
            let appCopy = mine.appendingPathComponent(name + ".pdf")        // the same invoice replaces its own PDF
            guard renderInvoice(doc, to: appCopy) != nil else { return reply(["ok": false, "error": "Couldn't make the PDF"], nil) }
            guard let vault = saveFolder, let project = body["project"] as? String, !project.isEmpty else {
                return reply(["ok": true, "path": appCopy.path, "appPath": appCopy.path, "filed": false], nil)
            }
            let proj = projectName(project)
            let folder = vault.appendingPathComponent(proj, isDirectory: true).appendingPathComponent(Folders.place("Invoices", project: proj), isDirectory: true)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let there = folder.appendingPathComponent(name + ".pdf")
            let file: (URL, Bool) -> Void = { target, replacing in
                if replacing { try? fm.removeItem(at: target) }
                let ok = (try? fm.copyItem(at: appCopy, to: target)) != nil
                reply(["ok": true, "path": ok ? target.path : appCopy.path, "appPath": appCopy.path, "filed": ok,
                       "name": target.lastPathComponent], nil)
            }
            // The project folder is yours: a PDF already there is only replaced if you say so.
            if fm.fileExists(atPath: there.path) {
                askReplace(there, in: "\(proj) › \(proj)_Docs › Invoices") { choice in
                    switch choice {
                    case "replace": file(there, true)
                    case "keep": file(self.uniqueURL(in: folder, name: name + ".pdf"), false)
                    default: reply(["ok": true, "path": appCopy.path, "appPath": appCopy.path, "filed": false, "kept": true], nil)
                    }
                }
            } else {
                file(there, false)
            }

        case "saveCsv":
            let panel = NSSavePanel()
            panel.nameFieldStringValue = (body["name"] as? String) ?? "invoices.csv"
            panel.allowedFileTypes = ["csv"]
            panel.message = "Save the invoices for your accountant"
            panel.beginSheetModal(for: window) { r in
                guard r == .OK, let url = panel.url else { return reply(["ok": false, "cancelled": true], nil) }
                let ok = (try? ((body["text"] as? String) ?? "").write(to: url, atomically: true, encoding: .utf8)) != nil
                reply(["ok": ok, "path": url.path], nil)
            }

        case "addressSuggest":
            addressFinder.suggest((body["query"] as? String) ?? "", reply)

        case "addressResolve":
            addressFinder.resolve((body["index"] as? NSNumber)?.intValue ?? -1, reply)

        case "mailPassword":
            // The app password lives in the Mac's Keychain, never in the app's files or the page.
            let account = (body["email"] as? String) ?? ""
            if let pw = body["password"] as? String { reply(["ok": PayKeychain.save(account, pw)], nil) }
            else { reply(["ok": true, "saved": PayKeychain.read(account) != nil], nil) }

        case "sendMail":
            sendMail(body, reply)

        case "revealFile":
            if let p = body["path"] as? String, fm.fileExists(atPath: p) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
            }
            reply(["ok": true], nil)

        default:
            reply(nil, "unknown action")
        }
    }

    // MARK: Sending, straight from Needed Pay

    /// Sends one email — the invoice attached — through your own account, using
    /// the email tool built into macOS (curl). The password comes from the Keychain
    /// and reaches curl through a pipe, never on a command line anyone could see.
    func sendMail(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        let from = ((b["from"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let to = ((b["to"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let host = ((b["host"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let port = (b["port"] as? NSNumber)?.intValue ?? 465
        guard !from.isEmpty, !to.isEmpty, !host.isEmpty else { return reply(["ok": false, "error": "Add who it's to, and your email in Settings"], nil) }
        guard let pw = PayKeychain.read(from) else { return reply(["ok": false, "error": "Add your app password in Settings"], nil) }
        let name = (b["name"] as? String) ?? ""
        let subject = (b["subject"] as? String) ?? "Invoice"
        let text = (b["body"] as? String) ?? ""
        let copy = (b["copy"] as? Bool) ?? true
        var attach: URL? = nil
        if let path = b["path"] as? String, !path.isEmpty { attach = URL(fileURLWithPath: path) }

        // The message itself.
        let boundary = "needed-\(UUID().uuidString)"
        let enc = { (s: String) in "=?UTF-8?B?" + Data(s.utf8).base64EncodedString() + "?=" }
        let date = { () -> String in let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"; return f.string(from: Date()) }()
        var m = "From: \(name.isEmpty ? from : enc(name) + " <\(from)>")\r\nTo: \(to)\r\nSubject: \(enc(subject))\r\nDate: \(date)\r\n"
        m += "Message-ID: <\(UUID().uuidString)@neededpay>\r\nMIME-Version: 1.0\r\n"
        m += "Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n\r\n"
        m += "--\(boundary)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
        m += Data(text.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]) + "\r\n"
        if let a = attach, let data = try? Data(contentsOf: a) {
            let file = a.lastPathComponent.replacingOccurrences(of: "\"", with: "")
            m += "--\(boundary)\r\nContent-Type: application/pdf; name=\"\(file)\"\r\nContent-Disposition: attachment; filename=\"\(file)\"\r\n"
            m += "Content-Transfer-Encoding: base64\r\n\r\n"
            m += data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]) + "\r\n"
        }
        m += "--\(boundary)--\r\n"
        let eml = FileManager.default.temporaryDirectory.appendingPathComponent("needed-pay-\(UUID().uuidString).eml")
        guard (try? m.data(using: .utf8)?.write(to: eml)) != nil else { return reply(["ok": false, "error": "Couldn't write the email"], nil) }

        // 465 is secure from the start; 587 starts plain and switches to secure — curl handles both.
        let url = (port == 465 ? "smtps://" : "smtp://") + "\(host):\(port)"
        var args = ["--silent", "--show-error", "--url", url, "--ssl-reqd", "--max-time", "60",
                    "--mail-from", from, "--mail-rcpt", to, "--upload-file", eml.path, "--config", "-"]
        if copy && to.lowercased() != from.lowercased() { args += ["--mail-rcpt", from] }       // a copy for your records
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = args
        let input = Pipe(), errPipe = Pipe()
        proc.standardInput = input; proc.standardError = errPipe; proc.standardOutput = Pipe()
        let quoted = "\(from):\(pw)".replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        DispatchQueue.global(qos: .userInitiated).async {
            var savedCopy = ""
            defer { try? FileManager.default.removeItem(at: eml) }
            do { try proc.run() } catch { return DispatchQueue.main.async { reply(["ok": false, "error": "Couldn't start sending"], nil) } }
            input.fileHandleForWriting.write(Data("user = \"\(quoted)\"\n".utf8))
            try? input.fileHandleForWriting.close()
            proc.waitUntilExit()
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let code = proc.terminationStatus
            // What went wrong, in words.
            let why: String
            switch code {
            case 0: why = ""
            case 67: why = "The password wasn't accepted. Use an app password, not your normal one."
            case 6, 7: why = "Couldn't reach the mail server. Check the server and your connection."
            case 28: why = "The mail server took too long. Try again."
            case 35, 60: why = "Couldn't make a secure connection to the mail server."
            case 55, 56: why = "The connection dropped while sending. Try again."
            default: why = err.isEmpty ? "Sending didn't work (\(code))." : err.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Sent: keep a copy in a Sent folder beside the invoice PDF — the record of what went.
            if code == 0, let a = attach {
                let sent = a.deletingLastPathComponent().appendingPathComponent("Sent", isDirectory: true)
                try? FileManager.default.createDirectory(at: sent, withIntermediateDirectories: true)
                let stamp = { () -> String in let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"; return f.string(from: Date()) }()
                let copy = sent.appendingPathComponent("\(a.deletingPathExtension().lastPathComponent) — to \(to) — \(stamp).eml")
                if (try? FileManager.default.copyItem(at: eml, to: copy)) != nil { savedCopy = copy.path }
            }
            DispatchQueue.main.async { reply(code == 0 ? ["ok": true, "saved": savedCopy] : ["ok": false, "error": why], nil) }
        }
    }

    // MARK: The invoice itself

    private func payFont(_ name: String, _ size: CGFloat) -> NSFont {
        NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    private func put(_ text: String, _ rect: CGRect, _ font: NSFont, _ colour: NSColor,
                     align: NSTextAlignment = .left, tracking: CGFloat = 0, upper: Bool = false) {
        let style = NSMutableParagraphStyle()
        style.alignment = align
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        NSAttributedString(string: upper ? text.uppercased() : text, attributes: [
            .font: font, .foregroundColor: colour, .paragraphStyle: style, .kern: tracking,
        ]).draw(in: rect)
    }

    private func tall(_ text: String, _ width: CGFloat, _ font: NSFont) -> CGFloat {
        let style = NSMutableParagraphStyle(); style.lineSpacing = 2; style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).height
    }

    /// Draws one invoice. Everything arrives already worded and formatted
    /// by the page — money, dates, tax lines — so this only lays it out.
    func renderInvoice(_ doc: [String: Any], to url: URL) -> Int? {
        let letter = (doc["paper"] as? String) == "letter"
        var media = letter ? CGRect(x: 0, y: 0, width: 612, height: 792) : CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &media, nil) else { return nil }
        let str = { (k: String) -> String in (doc[k] as? String) ?? "" }
        let me = (doc["me"] as? [String: Any]) ?? [:], client = (doc["client"] as? [String: Any]) ?? [:]
        let items = (doc["items"] as? [[String: Any]]) ?? []
        let totals = (doc["totals"] as? [[String: Any]]) ?? []
        let ink = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.11, alpha: 1)
        let mid = NSColor(calibratedWhite: 0.40, alpha: 1)
        let dim = NSColor(calibratedWhite: 0.60, alpha: 1)
        let hair = NSColor(calibratedWhite: 0.86, alpha: 1)
        let wash = NSColor(calibratedRed: 0.957, green: 0.953, blue: 0.945, alpha: 1)
        let accent = NSColor(calibratedRed: 0.94, green: 0.35, blue: 0.13, alpha: 1)
        let thin = payFont("HelveticaNeue-Thin", 34), bodyF = payFont("HelveticaNeue", 9.5)
        let medF = payFont("HelveticaNeue-Medium", 10), labelF = payFont("Menlo", 7)
        let m: CGFloat = 48, W = media.width, usable = W - 2 * m
        let mark = Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("logo.png")) }
        var page = 0, y: CGFloat = 0
        let bottom: CGFloat = m + 50

        func rule(_ at: CGFloat, _ from: CGFloat = m, _ to: CGFloat? = nil, _ width: CGFloat = 0.6) {
            hair.setStroke(); ctx.setLineWidth(width)
            ctx.move(to: CGPoint(x: from, y: at)); ctx.addLine(to: CGPoint(x: to ?? (m + usable), y: at)); ctx.strokePath()
        }
        func footer() {
            // the This Was Needed mark, small, bottom centre
            if let mark = mark, mark.size.width > 0 {
                let w: CGFloat = 46, h = w * mark.size.height / mark.size.width
                mark.draw(in: CGRect(x: (W - w) / 2, y: m - 18, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
            }
            if page > 1 || (doc["pages"] as? Int ?? 1) > 1 {
                put("\(page)", CGRect(x: m + usable - 30, y: m - 10, width: 30, height: 10), labelF, dim, align: .right)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        func newPage(_ continued: Bool) {
            if page > 0 { footer(); ctx.endPDFPage() }
            page += 1
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            y = media.height - m
            if continued {
                put("Invoice \(str("number")) — continued", CGRect(x: m, y: y - 12, width: usable, height: 14), labelF, dim, tracking: 1.2, upper: true)
                y -= 28
            }
        }

        newPage(false)

        // ---- title and who it's from
        put("Invoice", CGRect(x: m, y: y - 40, width: usable / 2, height: 44), thin, ink)
        if str("status") == "void" {
            put("VOID", CGRect(x: m, y: y - 58, width: 200, height: 16), payFont("Menlo-Bold", 11), accent, tracking: 3)
        }
        var fromLines: [(String, NSFont, NSColor)] = [((me["name"] as? String) ?? "", medF, ink)]
        for l in ((me["address"] as? String) ?? "").split(separator: "\n") { fromLines.append((String(l), bodyF, mid)) }
        for k in ["phone", "email"] { if let v = me[k] as? String, !v.isEmpty { fromLines.append((v, bodyF, mid)) } }
        var fy = y
        for (text, font, colour) in fromLines where !text.isEmpty {
            put(text, CGRect(x: m + usable / 2, y: fy - 13, width: usable / 2, height: 14), font, colour, align: .right)
            fy -= 13
        }
        y = min(y - 70, fy - 14)
        rule(y); y -= 22

        // ---- bill to, and the invoice's own facts
        let top = y
        put("Bill to", CGRect(x: m, y: y - 10, width: 200, height: 10), labelF, dim, tracking: 1.4, upper: true)
        y -= 16
        var billTo: [(String, NSFont, NSColor)] = [((client["name"] as? String) ?? "", medF, ink)]
        if let c = client["contact"] as? String, !c.isEmpty { billTo.append((c, bodyF, mid)) }
        for l in ((client["address"] as? String) ?? "").split(separator: "\n") { billTo.append((String(l), bodyF, mid)) }
        if let e = client["email"] as? String, !e.isEmpty { billTo.append((e, bodyF, mid)) }
        for (text, font, colour) in billTo where !text.isEmpty {
            put(text, CGRect(x: m, y: y - 13, width: usable / 2 - 10, height: 14), font, colour); y -= 13
        }
        let leftEnd = y
        var ry = top
        let facts: [(String, String)] = [("Invoice number", str("number")), ("Job number", str("job")), ("Invoice date", str("date")), ("Payment due", str("due"))]
        let keyX = m + usable * 0.52, keyW = usable * 0.26, valX = keyX + keyW + 8, valW = m + usable - valX
        for (k, v) in facts where !v.isEmpty {
            put(k, CGRect(x: keyX, y: ry - 12, width: keyW, height: 12), bodyF, mid, align: .right)
            put(v, CGRect(x: valX, y: ry - 12, width: valW, height: 12), bodyF, ink, align: .right)
            ry -= 16
        }
        ry -= 4
        wash.setFill(); ctx.fill(CGRect(x: keyX - 8, y: ry - 20, width: m + usable - keyX + 8, height: 24))
        put("Amount due (\(str("currency")))", CGRect(x: keyX, y: ry - 15, width: keyW, height: 13), medF, ink, align: .right)
        put(str("amountDue"), CGRect(x: valX, y: ry - 15, width: valW, height: 13), payFont("HelveticaNeue-Medium", 11), accent, align: .right)
        y = min(leftEnd, ry - 24) - 26

        // ---- the items
        let qtyX = m + usable * 0.56, rateX = m + usable * 0.66, amtX = m + usable * 0.82
        let hideQty = (doc["hideQty"] as? Bool) ?? false          // every line is one: the column says nothing
        func head() {
            put("Item", CGRect(x: m, y: y - 10, width: 200, height: 10), labelF, dim, tracking: 1.4, upper: true)
            if !hideQty { put("Qty", CGRect(x: qtyX, y: y - 10, width: rateX - qtyX - 6, height: 10), labelF, dim, align: .right, tracking: 1.4, upper: true) }
            put("Rate", CGRect(x: rateX, y: y - 10, width: amtX - rateX - 6, height: 10), labelF, dim, align: .right, tracking: 1.4, upper: true)
            put("Amount", CGRect(x: amtX, y: y - 10, width: m + usable - amtX, height: 10), labelF, dim, align: .right, tracking: 1.4, upper: true)
            y -= 16; rule(y, m, nil, 0.8); y -= 10
        }
        head()
        for it in items {
            let title = (it["title"] as? String) ?? "", note = (it["note"] as? String) ?? ""
            let textW = qtyX - m - 14
            let h = max(14, tall(title, textW, medF) + (note.isEmpty ? 0 : tall(note, textW, bodyF) + 2)) + 12
            if y - h < bottom + 40 { newPage(true); head() }
            put(title, CGRect(x: m, y: y - tall(title, textW, medF) - 1, width: textW, height: tall(title, textW, medF) + 2), medF, ink)
            if !note.isEmpty {
                let nh = tall(note, textW, bodyF)
                put(note, CGRect(x: m, y: y - tall(title, textW, medF) - nh - 3, width: textW, height: nh + 2), bodyF, mid)
            }
            if !hideQty { put((it["qty"] as? String) ?? "", CGRect(x: qtyX, y: y - 13, width: rateX - qtyX - 6, height: 13), bodyF, ink, align: .right) }
            put((it["rate"] as? String) ?? "", CGRect(x: rateX, y: y - 13, width: amtX - rateX - 6, height: 13), bodyF, ink, align: .right)
            put((it["amount"] as? String) ?? "", CGRect(x: amtX, y: y - 13, width: m + usable - amtX, height: 13), bodyF, ink, align: .right)
            y -= h; rule(y + 4, m, nil, 0.4)
        }
        y -= 12

        // ---- totals
        let totalsNeeded = CGFloat(totals.count) * 20 + 40
        if y - totalsNeeded < bottom { newPage(true) }
        let tKeyX = m + usable * 0.5, tKeyW = usable * 0.3
        for t in totals {
            let strong = (t["strong"] as? Bool) ?? false
            let f = strong ? medF : bodyF
            if strong { rule(y + 2, tKeyX, nil, 0.8); y -= 6 }
            put((t["label"] as? String) ?? "", CGRect(x: tKeyX, y: y - 13, width: tKeyW, height: 13), f, strong ? ink : mid, align: .right)
            put((t["value"] as? String) ?? "", CGRect(x: tKeyX + tKeyW + 8, y: y - 13, width: m + usable - tKeyX - tKeyW - 8, height: 13),
                f, strong && (t["due"] as? Bool ?? false) ? accent : ink, align: .right)
            y -= 19
        }
        y -= 18

        // ---- tax numbers, payment details, notes
        var blocks: [(String, String)] = []
        let regs = ((doc["taxNumbers"] as? [String]) ?? []).filter { !$0.isEmpty }
        if !regs.isEmpty { blocks.append(("Tax registration", regs.joined(separator: "\n"))) }
        if !str("payment").isEmpty { blocks.append(("Payment details", str("payment"))) }
        if !str("notes").isEmpty { blocks.append(("Notes", str("notes"))) }
        for (label, text) in blocks {
            let th = tall(text, usable * 0.6, bodyF)
            if y - th - 20 < bottom { newPage(true) }
            put(label, CGRect(x: m, y: y - 10, width: 300, height: 10), labelF, dim, tracking: 1.4, upper: true)
            y -= 15
            put(text, CGRect(x: m, y: y - th - 2, width: usable * 0.6, height: th + 4), bodyF, ink)
            y -= th + 16
        }

        footer()
        ctx.endPDFPage()
        ctx.closePDF()
        return page
    }
}



extension PayHost {
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



/// The app password, kept in the Mac's Keychain.
enum PayKeychain {
    private static let service = "Needed Pay — email"
    static func save(_ account: String, _ password: String) -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard !password.isEmpty else { return true }                      // an empty password just removes it
        var add = q; add[kSecValueData as String] = Data(password.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    static func read(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

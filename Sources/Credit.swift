// Needed Credit — native macOS shell.
// This Was Needed · thiswasneeded.info
//
// One file, no packages. Wraps the self-contained web app in a real Mac
// window. The only network request is licence activation, once.
//
// Build:  swiftc -O -target arm64-apple-macos11.3 -o nc-arm64 main.swift licence.swift
//         swiftc -O -target x86_64-apple-macos11.3 -o nc-x64 main.swift licence.swift
//         lipo -create -output "Needed Credit" nc-arm64 nc-x64

import AppKit
import WebKit

let creditScheme = "neededcredit"
let creditPageBackground = NSColor(srgbRed: 0xF4 / 255.0, green: 0xF3 / 255.0,
                             blue: 0xF1 / 255.0, alpha: 1)

// MARK: - Serving the app

/// Serves the bundle's Resources over a private scheme.
///
/// Not file:// — a page loaded from file:// has a null origin, and WebKit
/// refuses localStorage on a null origin. The crew memory would seem to
/// work and then be empty on every relaunch. A custom scheme gives the page
/// a stable origin, so storage survives relaunches and app updates.
final class CreditSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return fail(task) }

        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let target = root
            .appendingPathComponent(String(path.dropFirst()))
            .standardizedFileURL
            .resolvingSymlinksInPath()

        // Path-traversal guard: whatever was asked for must still sit
        // inside Resources once resolved.
        guard target.path.hasPrefix(root.path + "/"),
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
        default:     return "application/octet-stream"
        }
    }
}

// MARK: - App

final class CreditHost: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKUIDelegate, WKNavigationDelegate, WKDownloadDelegate {
    var window: NSWindow { webView?.window ?? NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }
    var webView: WKWebView!
    var licence: Licence!
    private var downloads: [ObjectIdentifier: URL] = [:]

    func start() {

        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(Shared.embedded)
        // The persistent store. The non-persistent one would wipe the crew
        // memory every time the app quits.
        config.websiteDataStore = .default()
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        config.setURLSchemeHandler(CreditSchemeHandler(root: resources.appendingPathComponent("tools/credit")), forURLScheme: creditScheme)

        // The page asks the app about the licence; the app does the checking.
        licence = Licence(resources: resources)
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page,
                                                             name: "licence")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")   // no white flash


        if let start = URL(string: "\(creditScheme)://app/index.html") {
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
        appMenu.addItem(withTitle: "About Needed Credit",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Needed Credit",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others",
                                     action: #selector(NSApplication.hideOtherApplications(_:)),
                                     keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Needed Credit",
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
        let name = suggestedFilename.isEmpty ? "needed-credit-crew.json" : suggestedFilename
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

extension CreditHost: WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return replyHandler(nil, "bad request")
        }
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


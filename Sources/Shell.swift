// Needed Tools — This Was Needed.
// One window holding six tools. Each tool keeps its own view and engine
// (so it keeps its work when you switch tabs, and can move into its own
// window later); the vault and project are shared by all of them.

import AppKit
import WebKit
import EventKit
import UserNotifications

let toolsScheme = "neededtools"

// MARK: - One vault, one project

extension Notification.Name {
    static let neededShared = Notification.Name("NeededToolsShared")
}

enum Shared {
    /// The vault folder, shared by every tool.
    static var vault: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: "saveFolder") else { return nil }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
                ? URL(fileURLWithPath: path, isDirectory: true) : nil
        }
        set {
            if let u = newValue { UserDefaults.standard.set(u.path, forKey: "saveFolder") }
            else { UserDefaults.standard.removeObject(forKey: "saveFolder") }
            Labels.forget()
            notify()
        }
    }

    /// The project you're in, shared by every tool.
    static var project: String {
        get { UserDefaults.standard.string(forKey: "project") ?? "Unsorted" }
        set {
            guard newValue != project else { return }
            UserDefaults.standard.set(newValue, forKey: "project")
            notify()
        }
    }

    /// The project folders in the vault.
    static func projects() -> [String] {
        guard let base = vault else { return [] }
        let names = ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey],
                                                                    options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { $0.lastPathComponent }
        return Array(Set(names + [project])).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Changes gather for a moment, then everyone hears once.
    private static var pending = false
    static func notify() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async {
            pending = false
            NotificationCenter.default.post(name: .neededShared, object: nil)
        }
    }

    /// Light, or the calm blue night (Resources/shell/theme.js).
    static var theme: String {
        get { UserDefaults.standard.string(forKey: "theme") == "dark" ? "dark" : "light" }
        set { UserDefaults.standard.set(newValue == "dark" ? "dark" : "light", forKey: "theme") }
    }
    private static let shellDir = Bundle.main.resourceURL?.appendingPathComponent("shell")
    private static func read(_ name: String) -> String {
        shellDir.flatMap { try? String(contentsOf: $0.appendingPathComponent(name), encoding: .utf8) } ?? ""
    }
    private static let embeddedSource = read("load.js") + "\n" + read("embed.js") + "\n" + read("hints.js")
    private static let themeSource = read("theme.js")

    /// Every tool gets the glass hints (Resources/shell/hints.js). Its own
    /// title — NEEDED GRAB and so on — stays, as in the separate apps.
    /// load.js: the one loading pill. embed.js: the glow, full width, click-outside and ←. hints.js: the glass hints.
    /// theme.js: dark mode — made fresh, so a tool opened later starts in the theme you're in.
    static var embedded: WKUserScript {
        WKUserScript(source: embeddedSource + "\n" + themeScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
    static var themeScriptSource: String { "window.__neededThemeNow = '\(theme)';\n" + themeSource }
    /// The app's own pages (Home, the project page, Design…): the theme alone.
    static var themeScript: WKUserScript { WKUserScript(source: themeScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true) }
    static var windowColour: NSColor {
        theme == "dark" ? NSColor(srgbRed: 0x0D / 255.0, green: 0x15 / 255.0, blue: 0x21 / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xFC / 255.0, green: 0xF2 / 255.0, blue: 0xEC / 255.0, alpha: 1)
    }
}

// MARK: - Where stills, GIFs and clips live in a project

/// Round 3: Grab and the Vault never share a folder name.
///     Lexus/Lexus_Grab/   Stills_Grab · GIFs_Grab · Motion_Grab   ← Needed Grab
///     Lexus/Lexus_Vault/  Stills_Ref  · GIFs_Ref  · Motion_Ref    ← Needed Vault
/// Files already in the older folders stay there and are still read:
/// Stills · GIFs · Motion (the first layout) and Grabs/… · References/… (Round F).
enum Folders {
    static let kinds = ["Stills", "GIFs", "Motion"]

    /// Inside a project: "Lexus_Grab/Stills_Grab" or "Lexus_Vault/Stills_Ref".
    static func sub(_ kind: String, project: String, grab: Bool) -> String {
        grab ? "\(project)_Grab/\(kind)_Grab" : "\(project)_Vault/\(kind)_Ref"
    }

    /// Every folder a project's stills, GIFs or clips may be in — newest layout
    /// first — with whether it holds grabs or references.
    static func all(_ kind: String, project: String) -> [(sub: String, origin: String)] {
        [(sub(kind, project: project, grab: true), "grab"), (sub(kind, project: project, grab: false), "reference"),
         ("Grabs/\(kind)", "grab"), ("References/\(kind)", "reference"), (kind, "grab")]
    }

    /// Round 5.1: everything a tool makes has one place in the project.
    ///     Lexus/Lexus_Docs/   Invoices · Shot lists · Mood boards · Contact sheets  ← Pay, Shots, the Vault
    ///     Lexus/Lexus_Vault/  Ideas
    /// Files already in the older folders (Invoices, Shots, Sheets, Ideas and
    /// Lexus_Vault/Mood at the top of the project) stay there and are still found.
    static func place(_ kind: String, project p: String, grab: Bool = false) -> String {
        if kinds.contains(kind) { return sub(kind, project: p, grab: grab) }
        switch kind {
        case "Sheets": return "\(p)_Docs/Contact sheets"
        case "Shots": return "\(p)_Docs/Shot lists"
        case "Invoices": return "\(p)_Docs/Invoices"
        case "Mood": return "\(p)_Docs/Mood boards"
        case "Ideas": return "\(p)_Vault/Ideas"
        default: return kind
        }
    }

    /// A file's origin from where it sits ("Lexus/Lexus_Grab/Stills_Grab/a.jpg"), if its folder says.
    static func origin(ofFile rel: String) -> String? {
        let parts = rel.split(separator: "/").map(String.init)
        guard parts.count >= 3 else { return nil }
        switch parts[1] {
        case "\(parts[0])_Grab", "Grabs": return "grab"
        case "\(parts[0])_Vault", "References": return "reference"
        default: return nil
        }
    }
}

// MARK: - Project labels and tags

/// A project has one label — the kind of work: Commercial, Music video,
/// Documentary… — and any number of tags for its sector or world: sports,
/// fashion, automotive. Both sit in a small hidden file in the project folder
/// (Lexus/.needed/project.json), so they travel with it; labels and tags
/// you've made up are remembered on this Mac too.
enum Labels {
    static let starters = ["Commercial", "Music video", "Documentary", "Short film", "Feature", "Branded content",
                           "Social / content", "Campaign stills", "Editorial", "Lookbook", "Event", "Live session",
                           "Pitch / spec", "Personal"]
    /// Round 3's labels were sectors: a project that has one gets it as a tag instead.
    private static let oldSectorLabels: Set<String> = ["sports", "comedy", "fashion"]
    private static var cache: [String: [String: Any]]? = nil     // project → its file

    private static func file(_ project: String) -> URL? { ProjectFile.url(project) }
    private static func read(_ project: String) -> [String: Any] {
        guard let u = file(project), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }
    private static func write(_ o: [String: Any], for project: String) {
        guard let u = file(project) else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: u, options: .atomic) }
    }

    /// Every project's file, read once and kept until something changes.
    private static func files() -> [String: [String: Any]] {
        if let c = cache { return c }
        var out: [String: [String: Any]] = [:]
        for p in Shared.projects() {
            var o = read(p)
            // One-time move: a sector used as a label (Sports, Comedy, Fashion) becomes a tag.
            if let l = o["label"] as? String, oldSectorLabels.contains(l.lowercased()) {
                var tags = (o["tags"] as? [String]) ?? []
                if !tags.contains(where: { $0.caseInsensitiveCompare(l) == .orderedSame }) { tags.append(l.lowercased()) }
                o["tags"] = tags
                o.removeValue(forKey: "label")
                write(o, for: p)
            }
            if !o.isEmpty { out[p] = o }
        }
        cache = out
        return out
    }

    /// Every project's label.
    static func all() -> [String: String] {
        var out: [String: String] = [:]
        for (p, o) in files() { if let l = o["label"] as? String, !l.isEmpty { out[p] = l } }
        return out
    }
    static func of(_ project: String) -> String { all()[project] ?? "" }

    /// Every project's tags.
    static func allTags() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (p, o) in files() { if let t = o["tags"] as? [String], !t.isEmpty { out[p] = t } }
        return out
    }
    static func tags(of project: String) -> [String] { allTags()[project] ?? [] }

    static func set(_ label: String, for project: String) {
        var o = read(project)                                          // keep anything else in the file
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { o.removeValue(forKey: "label") } else { o["label"] = String(clean.prefix(40)); add(clean) }
        write(o, for: project)
        cache = nil
    }

    /// Tags as typed: "Sports, luxury,  #Automotive" → sports, luxury, automotive.
    static func setTags(_ raw: [String], for project: String) {
        var seen = Set<String>()
        var tags: [String] = []
        for t in raw {
            var c = t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            while c.hasPrefix("#") { c.removeFirst() }
            c = String(c.prefix(30))
            if !c.isEmpty && seen.insert(c).inserted { tags.append(c) }
        }
        var o = read(project)
        if tags.isEmpty { o.removeValue(forKey: "tags") } else { o["tags"] = tags }
        write(o, for: project)
        cache = nil
    }

    /// The labels to choose from: the ones to start with, yours, and any a project already has.
    static func names() -> [String] {
        let mine = (UserDefaults.standard.array(forKey: "projectLabels") as? [String]) ?? []
        var every: [String] = starters
        every.append(contentsOf: mine)
        every.append(contentsOf: all().values.sorted())
        var seen = Set<String>()
        var out: [String] = []
        for l in every where !l.isEmpty && !oldSectorLabels.contains(l.lowercased()) && seen.insert(l.lowercased()).inserted { out.append(l) }
        return out
    }
    /// Every tag used on any project — suggestions when you type one.
    static func tagNames() -> [String] {
        var seen = Set<String>()
        for list in allTags().values { for t in list { seen.insert(t) } }
        return seen.sorted()
    }
    static func add(_ label: String) {
        var mine = (UserDefaults.standard.array(forKey: "projectLabels") as? [String]) ?? []
        guard !(starters + mine).contains(where: { $0.caseInsensitiveCompare(label) == .orderedSame }) else { return }
        mine.append(String(label.prefix(40)))
        UserDefaults.standard.set(mine, forKey: "projectLabels")
    }
    static func forget() { cache = nil }                              // a new vault, or after Sync
}

// MARK: - The tools

protocol ToolHost: AnyObject {
    var webView: WKWebView! { get }
    func start()
}
extension GrabHost: ToolHost {}
extension VaultHost: ToolHost {}
extension ShotsHost: ToolHost {}
extension SortHost: ToolHost {}
extension CreditHost: ToolHost {}
extension PayHost: ToolHost {}

let TOOL_IDS = ["vault", "shots", "sort", "grab", "credit", "pay"]     // the flow of a project

// MARK: - Home takes drops

/// Home's view: files dragged from Finder go to Needed Tools to route;
/// anything else (text, a link) the page handles as usual.
final class DropWebView: WKWebView {
    var onFiles: (([URL]) -> Void)?
    var onHover: ((Bool) -> Void)?
    /// Which file drops to take; the rest go to the page as usual (a single film in the Vault's player).
    var accepts: (([URL]) -> Bool)?
    private func files(_ info: NSDraggingInfo) -> [URL] {
        let all = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if let ok = accepts, !ok(all) { return [] }
        return all
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !files(sender).isEmpty { onHover?(true); return .copy }
        return super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !files(sender).isEmpty { return .copy }
        return super.draggingUpdated(sender)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHover?(false)
        super.draggingExited(sender)
    }
    // macOS asks "ready for this?" before it hands over a drop. WebKit only
    // says yes for drags it has been following itself — so for files we say yes.
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if !files(sender).isEmpty { return true }
        return super.prepareForDragOperation(sender)
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if let s = sender, !files(s).isEmpty { return }
        super.concludeDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let f = files(sender)
        guard !f.isEmpty else { return super.performDragOperation(sender) }
        onHover?(false)
        onFiles?(f)
        return true
    }
}

// MARK: - The app

final class Shell: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandlerWithReply, WKUIDelegate,
                   UNUserNotificationCenterDelegate {
    static var shared: Shell!
    var window: NSWindow!
    private var content = NSView()
    private var chrome: WKWebView!
    var home: WKWebView!
    /// The project page: one job, all in one place (Project.swift).
    var projectPage: WKWebView?
    /// Needed Design: mood boards and treatments (Design.swift).
    var designPage: WKWebView?
    var designAspects: [String: Double] = [:]
    let designRenderer = DesignRenderer()
    private var signin: WKWebView?
    private let area = NSView()
    var hosts: [String: ToolHost] = [:]
    private(set) var current = "home"
    static let barHeight: CGFloat = 64
    let calendarStore = EKEventStore()
    private var welcome: (NSVisualEffectView, WKWebView)?
    private var undocked: [String: NSWindow] = [:]
    static let names = ["design": "Design", "grab": "Grab", "vault": "Vault", "shots": "Shots", "sort": "Sort", "credit": "Credit", "pay": "Pay"]

    // The Vault starts with the app: Grab & Go listens from the moment you open it.
    lazy var vaultHost: VaultHost = {
        let v = VaultHost()
        v.start()
        v.webView.configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "shell")
        return v
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Shell.shared = self
        buildMenu()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 920),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Needed Tools"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Shared.windowColour
        window.minSize = NSSize(width: 980, height: 640)
        window.delegate = self
        window.contentView = content
        let size = content.bounds.size

        chrome = page("chrome.html")
        chrome.frame = NSRect(x: 0, y: size.height - Shell.barHeight, width: size.width, height: Shell.barHeight)
        chrome.autoresizingMask = [.width, .minYMargin]
        area.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - Shell.barHeight)
        area.autoresizingMask = [.width, .height]
        content.addSubview(area)
        content.addSubview(chrome)

        home = page("home.html", drop: true)
        if let h = home as? DropWebView {
            h.onFiles = { [weak self] urls in self?.route(urls) }
            h.onHover = { [weak self] on in self?.home.evaluateJavaScript("window.__homeDrag && window.__homeDrag(\(on))", completionHandler: nil) }
        }
        place(home)
        UNUserNotificationCenter.current().delegate = self

        // The project page takes drops too: anything dropped is filed into the project.
        let pp = page("project.html", drop: true)
        if let d = pp as? DropWebView {
            d.onFiles = { [weak self] urls in self?.fileIntoProject(urls) }
            d.onHover = { [weak self] on in self?.projectPage?.evaluateJavaScript("window.__projectDrag && window.__projectDrag(\(on))", completionHandler: nil) }
        }
        projectPage = pp
        place(pp)
        pp.isHidden = true

        // Needed Design: pictures dropped on it go into the project and onto the page.
        let dp = page("design.html", drop: true)
        if let d = dp as? DropWebView {
            // Photos, or folders of them.
            d.accepts = { urls in urls.contains { u in Shell.imageExt.contains(u.pathExtension.lowercased()) || u.hasDirectoryPath } }
            d.onFiles = { [weak self] urls in self?.designDrop(urls) }
            d.onHover = { [weak self] on in self?.designPage?.evaluateJavaScript("window.__designDrag && window.__designDrag(\(on))", completionHandler: nil) }
        }
        designPage = dp
        place(dp)
        dp.isHidden = true

        hosts["vault"] = vaultHost
        place(vaultHost.webView)
        vaultHost.webView.isHidden = true

        // The way in. For now it's a placeholder: Sign in simply opens the app.
        let s = page("signin.html")
        s.frame = content.bounds
        s.autoresizingMask = [.width, .height]
        content.addSubview(s)
        signin = s

        NotificationCenter.default.addObserver(forName: .neededShared, object: nil, queue: .main) { [weak self] _ in
            self?.broadcast()
            // A new vault chosen: anything in it without a colour palette gets one, in the background.
            let here = Shared.vault?.path ?? ""
            if here != self?.paletteVault { self?.paletteVault = here; VaultStore.shared.fillMissingPalettes() }
        }
        // Every picture has its colours: fill in any that are missing, a moment after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.paletteVault = Shared.vault?.path ?? ""
            VaultStore.shared.fillMissingPalettes()
        }
        // Back from System Settings after "Add Google Calendar": say whether it worked.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.waitingForGoogle else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.checkGoogle() }
        }

        window.center()
        window.setFrameAutosaveName("NeededToolsMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// One of the app's own pages: the top bar, Home, sign-in.
    private func page(_ name: String, drop: Bool = false) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
        let scheme = VaultSchemeHandler(root: resources.appendingPathComponent("shell"))
        scheme.vaultRoot = { Shared.vault }                    // Home shows the vault's work
        config.setURLSchemeHandler(scheme, forURLScheme: toolsScheme)
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "shell")
        config.userContentController.addUserScript(Shared.themeScript)
        let view: WKWebView = drop ? DropWebView(frame: .zero, configuration: config) : WKWebView(frame: .zero, configuration: config)
        view.uiDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        if let url = URL(string: "\(toolsScheme)://app/\(name)") { view.load(URLRequest(url: url)) }
        return view
    }

    private func place(_ view: WKWebView) {
        view.frame = area.bounds
        view.autoresizingMask = [.width, .height]
        if view.superview !== area { area.addSubview(view) }
    }

    func host(_ id: String) -> ToolHost? {
        if let h = hosts[id] { return h }
        let h: ToolHost
        switch id {
        case "grab": h = GrabHost()
        case "vault": return vaultHost
        case "shots": h = ShotsHost()
        case "sort": h = SortHost()
        case "credit": h = CreditHost()
        case "pay": h = PayHost()
        default: return nil
        }
        h.start()                                   // tools open the first time you need them
        h.webView.configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "shell")
        hosts[id] = h
        return h
    }

    /// Show a tab. Every other tool stays exactly as you left it.
    // Where you've been, for ← and →.
    private var backStack: [String] = []
    private var forwardStack: [String] = []

    func show(_ id: String, remember: Bool = true) {
        if remember, id != current {
            backStack.append(current)
            if backStack.count > 50 { backStack.removeFirst() }
            forwardStack.removeAll()
        }
        if let w = undocked[id] { w.makeKeyAndOrderFront(nil); return }
        let target: WKWebView?
        if id == "home" { target = home } else if id == "project" { target = projectPage } else if id == "design" { target = designPage } else { target = host(id)?.webView }
        guard let view = target else { return }
        place(view)
        for sub in area.subviews { sub.isHidden = sub !== view }
        current = id
        window.makeFirstResponder(view)
        broadcast()
    }

    // MARK: Drop anything: each file to the tool it belongs to

    static let filmExt: Set<String> = ["mov", "mp4", "m4v", "webm"]
    static let imageExt: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "gif", "tif", "tiff"]
    static let sheetExt: Set<String> = ["pdf", "txt", "csv", "tsv", "rtf"]

    func route(_ urls: [URL]) {
        let fm = FileManager.default
        var folders: [URL] = [], images: [URL] = [], film: URL? = nil, sheet: URL? = nil, docs: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: u.path, isDirectory: &isDir)
            let ext = u.pathExtension.lowercased()
            let isPackage = (try? u.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
            if isPackage { docs.append(u) }                           // a Keynote or Pages file
            else if isDir.boolValue { folders.append(u) }
            else if Shell.filmExt.contains(ext) { if film == nil { film = u } }
            else if Shell.imageExt.contains(ext) { images.append(u) }
            // A call sheet or crew list goes to Credit; any other document is filed into the project.
            else if ext == "pdf" && Docs.guess(u.lastPathComponent) != "Call sheet" { docs.append(u) }
            else if Shell.sheetExt.contains(ext) { if sheet == nil { sheet = u } }
            else if Docs.docExt.contains(ext) { docs.append(u) }
        }
        if !folders.isEmpty {                                   // a card, or a folder of footage → Sort
            show("sort")
            let paths = (try? JSONSerialization.data(withJSONObject: folders.map { $0.path })).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            if let v = host("sort")?.webView { whenReady(v, "__neededAddCards", "window.__neededAddCards(\(paths))") }
        } else if let f = film {                                 // a film → Grab
            GrabSchemeHandler.film = f
            let size = (try? fm.attributesOfItem(atPath: f.path)[.size] as? NSNumber)?.int64Value ?? 0
            show("grab")
            if let v = host("grab")?.webView {
                whenReady(v, "__neededOpenFilm", "window.__neededOpenFilm(\(Shell.js(f.lastPathComponent)), \(size))")
            }
        } else if !images.isEmpty {                              // images: ask where they go first
            guard Shared.vault != nil else { return homeToast("Choose your vault first") }
            pendingImages = images
            pendingWeb = nil
            askWhere(count: images.count, sample: images.first?.lastPathComponent ?? "")
        } else if !docs.isEmpty {                               // documents → filed into the project
            guard Shared.vault != nil else { return homeToast("Choose your vault first") }
            show("project")
            fileIntoProject(docs)
        } else if let s = sheet, let data = try? Data(contentsOf: s), data.count < 30_000_000 {   // a call sheet → Credit
            show("credit")
            let type = s.pathExtension.lowercased() == "pdf" ? "application/pdf" : "text/plain"
            if let v = host("credit")?.webView {
                whenReady(v, "__neededOpenFile", "window.__neededOpenFile(\(Shell.js(s.lastPathComponent)), \(Shell.js(type)), \(Shell.js(data.base64EncodedString())))")
            }
        } else {
            homeToast("Not sure which tool that's for")
        }
    }

    // Images dropped on Home wait here while the pop-up asks where they go.
    private var pendingImages: [URL] = []
    private var pendingWeb: (url: String, html: String)? = nil

    private func askWhere(count: Int, sample: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["count": count, "sample": sample,
                                                                      "projects": Shared.projects(), "project": Shared.project]),
              let json = String(data: data, encoding: .utf8) else { return }
        if current != "home" { show("home") }
        home.evaluateJavaScript("window.__homeAskWhere && window.__homeAskWhere(\(json))", completionHandler: nil)
    }

    /// An image dropped on Home goes into the project you chose, as a reference or a grab.
    private func saveImage(_ url: URL, into project: String? = nil, origin: String = "reference") -> Bool {
        let v = vaultHost
        let project = project ?? Shared.project
        guard let folder = v.outputFolder("Stills", project: project, area: origin == "grab" ? "Grabs" : "References") else { return false }
        let target = v.uniqueURL(in: folder, name: url.lastPathComponent)
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return false }
        let meta: [String: Any] = ["source": ["type": "file", "title": url.deletingPathExtension().lastPathComponent]]
        var m = meta; m["origin"] = origin
        _ = v.register(kind: url.pathExtension.lowercased() == "gif" ? "gif" : "still", file: target, meta: m, project: project)
        return true
    }

    /// A tool opened a moment ago may still be loading: wait until its page is ready.
    func whenReady(_ view: WKWebView, _ hook: String, _ js: String, tries: Int = 50) {
        view.evaluateJavaScript("typeof window.\(hook) === 'function'") { r, _ in
            if (r as? Bool) == true { view.evaluateJavaScript(js, completionHandler: nil) }
            else if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.whenReady(view, hook, js, tries: tries - 1) }
            }
        }
    }

    private func homeToast(_ text: String) {
        home.evaluateJavaScript("window.__homeToast && window.__homeToast(\(Shell.js(text)))", completionHandler: nil)
    }

    static func js(_ s: String) -> String {
        (try? JSONSerialization.data(withJSONObject: [s])).flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }

    // MARK: Home's vault wall: the project's newest work

    private var aspects: [String: Double] = [:]              // each picture's shape, worked out once

    private func homeData(_ body: [String: Any]) -> [String: Any] {
        guard let base = Shared.vault else { return ["items": [], "vault": false] }
        let show = (body["show"] as? String) ?? "both"                   // references, grabs or both
        let scope = (body["scope"] as? String) ?? "all"                  // the entire vault, this project, or a label
        let wantLabel = ((body["label"] as? String) ?? "").lowercased()
        let labels = Labels.all()
        let projectTags = Labels.allTags()
        let v = vaultHost
        // The store only re-reads the list when it has changed. Nothing here looks
        // through the folders — that's Sync's job, when you ask for it.
        v.loadIndex()
        // Search: every word has to match something — title, tags, boards, project, source or a colour's name.
        let words = ((body["q"] as? String) ?? "").lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        // Where it came from: saved by the Vault → a reference; put in a project by Grab or Finder → a grab.
        let originOf = { (it: [String: Any]) -> String in
            if let o = Folders.origin(ofFile: it["file"] as? String ?? "") { return o }
            if let o = it["origin"] as? String { return o }
            let src = it["source"] as? [String: Any]
            return (src?["type"] as? String) == "file" && it["at"] == nil ? "grab" : "reference"
        }
        // (Kept in small, typed steps: older Swift compilers give up on one big closure.)
        let matching = v.index.filter { (it: [String: Any]) -> Bool in
            let kind = it["kind"] as? String ?? ""
            guard kind == "still" || kind == "gif" || kind == "clip" else { return false }
            let proj = it["project"] as? String ?? "Unsorted"
            if scope == "project" && proj != Shared.project { return false }
            if scope == "label" {
                let theirs: String = labels[proj] ?? ""
                if theirs.lowercased() != wantLabel { return false }
            }
            let o: String = originOf(it)
            let wanted: Bool = show == "both" || (show == "references" && o == "reference") || (show == "grabs" && o == "grab")
            guard wanted else { return false }
            if words.isEmpty { return true }
            let tagWords: String = (projectTags[proj] ?? []).joined(separator: " ")
            let text: String = Shell.searchText(it, label: (labels[proj] ?? "") + " " + tagWords)
            return words.allSatisfy { text.contains($0) }
        }
        // Home's colour picker: which colours are in what's showing, and — if one is
        // picked — only the pictures that have it in their palette.
        let colour = ((body["colour"] as? String) ?? "").lowercased()
        var colourCounts: [String: Int] = [:]
        for it in matching {
            var names = Set<String>()
            for hex in (it["palette"] as? [String]) ?? [] { for n in Shell.colourNames(hex) where Shell.families.contains(n) { names.insert(n) } }
            for n in names { colourCounts[n, default: 0] += 1 }
        }
        let filtered = matching.filter { (it: [String: Any]) -> Bool in
            if colour.isEmpty { return true }
            let palette: [String] = (it["palette"] as? [String]) ?? []
            return palette.contains { Shell.colourNames($0).contains(colour) }
        }
        // Newest first — or, shuffled, any 300 from the whole vault, a new pick with every mix.
        let seed: UInt32? = (body["seed"] as? NSNumber)?.uint32Value
        let picked = Shell.pick(filtered, seed: seed)
        let items: [[String: Any]] = picked.compactMap { (it: [String: Any]) -> [String: Any]? in
            guard let id = it["id"] as? String, let thumb = it["thumb"] as? String, let file = it["file"] as? String else { return nil }
            var a: Double = 16.0 / 9.0
            if let w = (it["w"] as? NSNumber)?.doubleValue, let h = (it["h"] as? NSNumber)?.doubleValue, w > 0, h > 0 { a = w / h }
            else if let known = aspects[id] { a = known }
            else if let src = CGImageSourceCreateWithURL(base.appendingPathComponent(thumb) as CFURL, nil),
                    let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                    let w = p[kCGImagePropertyPixelWidth] as? Double, let h = p[kCGImagePropertyPixelHeight] as? Double, h > 0 { a = w / h; aspects[id] = a }
            let src = it["source"] as? [String: Any]
            let proj: String = it["project"] as? String ?? "Unsorted"
            var out: [String: Any] = ["id": id, "thumb": thumb, "file": file, "a": a]
            out["kind"] = it["kind"] as? String ?? "still"
            out["title"] = src?["title"] as? String ?? ""
            out["url"] = src?["url"] as? String ?? ""
            out["at"] = it["at"] ?? NSNull()
            out["project"] = proj
            out["label"] = labels[proj] ?? ""
            out["origin"] = originOf(it)
            out["tags"] = (it["tags"] as? [String]) ?? [String]()
            out["boards"] = (it["boards"] as? [String]) ?? [String]()
            out["palette"] = (it["palette"] as? [String]) ?? [String]()
            return out
        }
        return ["items": items, "vault": true, "project": Shared.project, "colours": colourCounts]
    }

    /// The 300 Home shows: the newest, or with a shuffle seed, a fair random pick.
    static func pick(_ all: [[String: Any]], seed: UInt32?) -> ArraySlice<[String: Any]> {
        guard let s = seed else {
            return all.sorted { ($0["created"] as? String ?? "") > ($1["created"] as? String ?? "") }.prefix(300)
        }
        let rank = { (id: String) -> UInt32 in
            var h: UInt32 = s ^ 0x9e3779b9
            for u in id.utf8 { h = (h ^ UInt32(u)) &* 0x85ebca6b; h ^= h >> 13 }
            h = (h ^ (h >> 16)) &* 0xc2b2ae35
            return h ^ (h >> 16)
        }
        let ranked: [(UInt32, [String: Any])] = all.map { (rank(($0["id"] as? String) ?? ""), $0) }
        return ranked.sorted { $0.0 < $1.0 }.map { $0.1 }.prefix(300)
    }

    /// Everything Home's search looks through for one item: title, source, project,
    /// its label, note, kind, tags, boards and its colours' names.
    static func searchText(_ it: [String: Any], label: String) -> String {
        let src = it["source"] as? [String: Any] ?? [:]
        var hay: [String] = []
        hay.append(src["title"] as? String ?? "")
        hay.append(src["url"] as? String ?? "")
        hay.append(src["site"] as? String ?? "")
        hay.append(it["project"] as? String ?? "")
        hay.append(label)
        hay.append(it["note"] as? String ?? "")
        hay.append(it["kind"] as? String ?? "")
        hay.append(contentsOf: (it["tags"] as? [String]) ?? [])
        hay.append(contentsOf: (it["boards"] as? [String]) ?? [])
        for hex in (it["palette"] as? [String]) ?? [] { hay.append(contentsOf: colourNames(hex)) }
        return hay.joined(separator: " ").lowercased()
    }

    /// The colours Home's picker offers, in the order it shows them.
    static let families = ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "brown", "black", "grey", "white"]

    /// Names for a colour, so "red" or "teal" finds pictures with it in their palette.
    static func colourNames(_ hex: String) -> [String] {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let n = Int(h, radix: 16) else { return [] }
        let r = Double((n >> 16) & 255) / 255, g = Double((n >> 8) & 255) / 255, b = Double(n & 255) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let sat = mx == 0 ? 0 : d / mx
        if sat < 0.18 { return mx < 0.22 ? ["black", "dark"] : mx > 0.85 ? ["white", "light"] : ["grey", "gray"] }
        var hue: Double
        if d == 0 { hue = 0 } else if mx == r { hue = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == g { hue = 60 * ((b - r) / d + 2) } else { hue = 60 * ((r - g) / d + 4) }
        if hue < 0 { hue += 360 }
        var names: [String]
        switch hue {
        case ..<15, 340...: names = ["red"]
        case ..<40: names = mx < 0.6 ? ["brown", "orange"] : ["orange"]
        case ..<65: names = ["yellow"]
        case ..<160: names = ["green"]
        case ..<200: names = ["teal", "cyan"]
        case ..<250: names = ["blue"]
        case ..<290: names = ["purple"]
        default: names = ["pink"]
        }
        if mx < 0.3 { names.append("dark") } else if sat < 0.35 && mx > 0.75 { names.append("pastel") }
        return names
    }

    // MARK: Sync: rescan the project you're in, then bring every tool up to date

    private var syncWaiting: [(Any?, String?) -> Void] = []
    private var paletteVault = ""
    private func sync(_ reply: @escaping (Any?, String?) -> Void) {
        guard Shared.vault != nil else { return reply(["ok": false, "error": "Choose your vault first"], nil) }
        syncWaiting.append(reply)
        guard !vaultHost.syncing else { return }                 // a second press waits for the one running
        let project = Shared.project
        // The one loading pill, in whatever you're looking at.
        let view: WKWebView? = current == "home" ? home : current == "project" ? projectPage : current == "design" ? designPage : (undocked[current] == nil ? hosts[current]?.webView : nil)
        view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.start(\(Shell.js("Syncing \(project)")))", completionHandler: nil)
        vaultHost.sync(project: project, progress: { f in
            view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.set(\(f))", completionHandler: nil)
        }, done: { [weak self] result in
            guard let self = self else { return }
            view?.evaluateJavaScript("window.__neededLoad && window.__neededLoad.done()", completionHandler: nil)
            Labels.forget()                                            // and any labels changed in Finder
            // Every open tool refreshes what it shows: Home, the Vault, Shots, Grab…
            var views: [WKWebView] = [self.home]
            if let p = self.projectPage { views.append(p) }
            if let d = self.designPage { views.append(d) }
            views += self.hosts.values.compactMap { $0.webView }
            for v in views { v.evaluateJavaScript("window.__neededSynced && window.__neededSynced()", completionHandler: nil) }
            if (result["ok"] as? Bool) == true {
                let added = (result["added"] as? Int) ?? 0
                let relinked = (result["relinked"] as? Int) ?? 0, removed = (result["removed"] as? Int) ?? 0
                var bits: [String] = []
                if added > 0 { bits.append("\(added) new") }
                if relinked > 0 { bits.append("\(relinked) moved in Finder, found again") }
                if removed > 0 { bits.append("\(removed) deleted in Finder, taken off the list") }
                Shell.post("\(project) synced", bits.isEmpty ? "Everything's up to date." : bits.joined(separator: " · ") + ".")
            }
            let waiting = self.syncWaiting; self.syncWaiting = []
            for r in waiting { r(result, nil) }
        })
    }

    // MARK: Home's calendar: whatever macOS Calendar has — Google too, if it's added there

    func calendarAllowed() -> Bool {
        let st = EKEventStore.authorizationStatus(for: .event)
        // macOS 14 renamed "authorized" to "fullAccess" (same value). Older
        // developer tools don't know the new name, so it's only compiled when they do.
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) { return st == .fullAccess }
        #endif
        return st == .authorized
    }

    private func calendarWeek(_ reply: @escaping (Any?, String?) -> Void, from: Double? = nil, to: Double? = nil) {
        var cal = Calendar.current
        cal.firstWeekday = 2                                         // weeks start on Monday
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        // Home asks for the week or month it's showing; otherwise this week.
        let start = from.map { Date(timeIntervalSince1970: $0 / 1000) } ?? weekStart
        let end = to.map { Date(timeIntervalSince1970: $0 / 1000) } ?? (cal.date(byAdding: .day, value: 7, to: weekStart) ?? today)
        let found = calendarStore.events(matching: calendarStore.predicateForEvents(withStart: start, end: end, calendars: nil))
        let events: [[String: Any]] = found.map { e in
            var hex = "#F05A22"
            if let c = e.calendar?.color?.usingColorSpace(.sRGB) {
                hex = String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            }
            return ["title": e.title ?? "", "start": e.startDate.timeIntervalSince1970 * 1000,
                    "end": e.endDate.timeIntervalSince1970 * 1000, "allDay": e.isAllDay, "color": hex]
        }
        reply(["allowed": true, "weekStart": start.timeIntervalSince1970 * 1000, "events": events], nil)
    }

    // MARK: Did Google Calendar arrive?

    private var waitingForGoogle = false
    private func googleCalendars() -> Int {
        calendarStore.calendars(for: .event).filter { c in
            let src = (c.source?.title ?? "").lowercased()
            return src.contains("google") || src.contains("gmail")
        }.count
    }
    private func checkGoogle() {
        waitingForGoogle = false
        let result: [String: Any]
        if !calendarAllowed() {
            result = ["ok": false, "text": "Allow calendar access first — press Show my calendar, then add Google again."]
        } else {
            calendarStore.reset()                                      // pick up accounts added a moment ago
            let n = googleCalendars()
            result = n > 0
                ? ["ok": true, "text": "Google Calendar added — \(n) calendar\(n == 1 ? "" : "s")"]
                : ["ok": false, "text": "Google Calendar couldn't be added yet. In Internet Accounts, add Google and turn Calendars on."]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: result), let json = String(data: data, encoding: .utf8) else { return }
        home.evaluateJavaScript("window.__homeCalendarResult && window.__homeCalendarResult(\(json))", completionHandler: nil)
    }

    // MARK: Notifications: anything that finishes tells you, even if you're in another app

    private static var askedToNotify = false
    /// A macOS notification: footage in, files saved, cards sorted, sent… The
    /// first one asks permission; after that they just arrive.
    static func post(_ title: String, _ body: String, sound: Bool = false) {
        let centre = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = .default }
            centre.add(UNNotificationRequest(identifier: "needed-" + UUID().uuidString, content: content, trigger: nil))
        }
        if askedToNotify { return send() }
        centre.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            DispatchQueue.main.async { askedToNotify = true; if ok { send() } }
        }
    }

    // MARK: Focus: macOS says when the time's up, even if you're in another app

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) { done([.banner, .sound]) } else { done([.sound]) }
    }

    // MARK: The welcome: full glass over whatever's behind it

    func showWelcome(_ tool: String, only: Bool = false) {
        let welcomePage = "welcome.html?tool=\(tool)" + (only ? "&only=1" : "")
        if let open = welcome {                                    // already open: jump to that tool's page
            let (fx, web) = open
            web.load(URLRequest(url: URL(string: "\(toolsScheme)://app/\(welcomePage)")!))
            fx.window?.makeFirstResponder(web)
            return
        }
        let fx = NSVisualEffectView(frame: content.bounds)         // macOS blurs the app behind the glass
        fx.autoresizingMask = [.width, .height]
        fx.material = .popover                                  // light, like Home's glass
        fx.blendingMode = .withinWindow
        fx.state = .active
        fx.appearance = NSAppearance(named: .aqua)
        let web = page(welcomePage)
        web.frame = content.bounds
        web.autoresizingMask = [.width, .height]
        fx.alphaValue = 0; web.alphaValue = 0
        content.addSubview(fx)
        content.addSubview(web)
        welcome = (fx, web)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            fx.animator().alphaValue = 1
            web.animator().alphaValue = 1
        }
        window.makeFirstResponder(web)
    }

    private func closeWelcome() {
        guard let open = welcome else { return }
        let (fx, web) = open
        welcome = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            fx.animator().alphaValue = 0
            web.animator().alphaValue = 0
        }, completionHandler: {
            fx.removeFromSuperview(); web.removeFromSuperview()
        })
    }

    // MARK: A tool in its own window — same view, so nothing is lost

    func undock(_ id: String) {
        guard undocked[id] == nil, let h = host(id), let view = h.webView else { return }
        view.removeFromSuperview()
        view.isHidden = false
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 860),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.title = "Needed \(Shell.names[id] ?? "") — \(Shared.project)"
        w.backgroundColor = Shared.windowColour
        w.minSize = NSSize(width: 720, height: 560)
        view.frame = NSRect(origin: .zero, size: w.contentRect(forFrameRect: w.frame).size)
        view.autoresizingMask = [.width, .height]
        w.contentView = view
        w.delegate = self
        let dock = NSButton(title: "Dock", target: self, action: #selector(dockPressed(_:)))
        dock.identifier = NSUserInterfaceItemIdentifier(id)
        dock.bezelStyle = .recessed
        dock.controlSize = .small
        let holder = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 24))
        dock.frame = NSRect(x: 6, y: 1, width: 54, height: 22)
        holder.addSubview(dock)
        let acc = NSTitlebarAccessoryViewController()
        acc.view = holder
        acc.layoutAttribute = .trailing
        w.addTitlebarAccessoryViewController(acc)
        w.setFrameAutosaveName("NeededTools-\(id)")
        undocked[id] = w
        if current == id { show("home") }
        w.makeKeyAndOrderFront(nil)
        broadcast()
    }

    @objc private func dockPressed(_ sender: NSButton) { dock(sender.identifier?.rawValue ?? "") }

    func dock(_ id: String) {
        guard let w = undocked.removeValue(forKey: id), let view = hosts[id]?.webView else { return }
        w.delegate = nil
        w.contentView = NSView()
        w.orderOut(nil)
        place(view)
        show(id)
    }

    /// Closing a tool's own window puts it back in its tab, work and all.
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, let id = undocked.first(where: { $0.value === w })?.key else { return }
        DispatchQueue.main.async { self.dock(id) }
    }

    /// Every page, and the window behind them, in the theme you chose.
    func applyTheme() {
        window.backgroundColor = Shared.windowColour
        for w in undocked.values { w.backgroundColor = Shared.windowColour }
        var views: [WKWebView] = [chrome, home]
        if let p = projectPage { views.append(p) }
        if let d = designPage { views.append(d) }
        if let s = signin { views.append(s) }
        if let w = welcome?.1 { views.append(w) }
        views += hosts.values.compactMap { $0.webView }
        let js = "window.__neededTheme && window.__neededTheme('\(Shared.theme)')"
        for v in views { v.evaluateJavaScript(js, completionHandler: nil) }
    }

    // MARK: Everyone hears about the vault, the project and the tab

    private func state() -> [String: Any] {
        [
            "vault": Shared.vault?.path ?? "",
            "vaultName": Shared.vault?.lastPathComponent ?? "",
            "project": Shared.project,
            "projects": Shared.projects(),
            "label": Labels.of(Shared.project),                          // this project's label
            "labels": Labels.names(),                                    // the ones to choose from
            "projectLabels": Labels.all(),                               // every project's, for search and Home
            "tags": Labels.tags(of: Shared.project),                     // this project's sector tags
            "projectTags": Labels.allTags(),
            "tagNames": Labels.tagNames(),
            "grabGo": hosts["vault"] != nil ? vaultHost.grabGo.on : false,
            "theme": Shared.theme,
            "tab": current,
            "canBack": !backStack.isEmpty || current != "home",
            "canForward": !forwardStack.isEmpty,
            "undocked": Array(undocked.keys),
        ]
    }

    func broadcast() {
        guard let data = try? JSONSerialization.data(withJSONObject: state()),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.__neededShared && window.__neededShared(\(json))"
        var views: [WKWebView] = [chrome, home]
        if let p = projectPage { views.append(p) }
        if let d = designPage { views.append(d) }
        views += hosts.values.compactMap { $0.webView }
        for v in views { v.evaluateJavaScript(js, completionHandler: nil) }
        for (id, w) in undocked { w.title = "Needed \(Shell.names[id] ?? "") — \(Shared.project)" }
    }

    // MARK: The app's own pages talk to it here

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        let body = message.body as? [String: Any] ?? [:]
        switch (body["action"] as? String) ?? "" {
        case "state":
            reply(replyHandler)

        case "navBack":
            // First close whatever's open on top — a reference, a pop-up — then go back a tab.
            let view: WKWebView? = current == "home" ? home : current == "project" ? projectPage : current == "design" ? designPage : hosts[current]?.webView
            let goBack = {
                guard let prev = self.backStack.popLast() else {
                    if self.current != "home" { self.forwardStack.append(self.current); self.show("home", remember: false) }
                    return self.reply(replyHandler)
                }
                self.forwardStack.append(self.current)
                self.show(prev, remember: false)
                self.reply(replyHandler)
            }
            guard let v = view else { return goBack() }
            v.evaluateJavaScript("window.__neededBack ? window.__neededBack() : false") { r, _ in
                if (r as? Bool) == true { self.reply(replyHandler) } else { goBack() }
            }

        case "navForward":
            if let next = forwardStack.popLast() {
                backStack.append(current)
                show(next, remember: false)
            }
            reply(replyHandler)

        case "tab":
            show((body["id"] as? String) ?? "home")
            reply(replyHandler)

        case "chooseVault":
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Use This Vault"
            panel.message = "Choose your vault — the folder every tool saves into"
            if let v = Shared.vault { panel.directoryURL = v }
            panel.beginSheetModal(for: window) { r in
                if r == .OK, let u = panel.url { Shared.vault = u }
                self.reply(replyHandler)
            }

        case "setProject":
            if let name = body["name"] as? String { Shared.project = Shell.clean(name) }
            reply(replyHandler)

        case "setLabel":
            // the dropdown beside the project: this project's label, or a new one
            Labels.set((body["label"] as? String) ?? "", for: Shared.project)
            Shared.notify()
            reply(replyHandler)

        case "setTags":
            Labels.setTags((body["tags"] as? [String]) ?? [], for: Shared.project)
            Shared.notify()
            reply(replyHandler)

        case "newProject":
            let name = Shell.clean((body["name"] as? String) ?? "")
            if !name.isEmpty {
                if let v = Shared.vault {
                    try? FileManager.default.createDirectory(at: v.appendingPathComponent(name, isDirectory: true),
                                                             withIntermediateDirectories: true)
                }
                Shared.project = name
            }
            reply(replyHandler)

        case "sync":
            sync(replyHandler)

        case "theme":
            // Light, or the calm blue night — every page at once.
            Shared.theme = (body["theme"] as? String) ?? (Shared.theme == "dark" ? "light" : "dark")
            applyTheme()
            reply(replyHandler)

        case "notify":
            // a tool finished something: say so
            Shell.post((body["title"] as? String) ?? "Needed Tools", (body["body"] as? String) ?? "", sound: (body["sound"] as? Bool) ?? false)
            replyHandler(["ok": true], nil)

        case "grabGo":
            if Shared.vault == nil {
                replyHandler(["ok": false, "error": "Choose your vault first"], nil)
            } else {
                vaultHost.grabGo.setOn(!vaultHost.grabGo.on)
                reply(replyHandler)
            }

        case "welcome":
            // On Home, ? opens the welcome. In a tool, it replays that tool's walkthrough, beside its controls.
            let asked = (body["tool"] as? String) ?? current
            if TOOL_IDS.contains(asked), (body["page"] as? Bool) != true, let v = hosts[asked]?.webView {
                v.evaluateJavaScript("window.__neededHints && window.__neededHints.replay()", completionHandler: nil)
            } else {
                showWelcome(asked == "home" ? "welcome" : asked)
            }
            replyHandler(["ok": true], nil)

        case "welcomeState":
            replyHandler(["hidden": UserDefaults.standard.bool(forKey: "welcomeHidden")], nil)

        case "welcomeDone":
            if (body["keep"] as? Bool) != true {        // a single tool's intro leaves the setting alone
                UserDefaults.standard.set((body["hide"] as? Bool) ?? false, forKey: "welcomeHidden")
            }
            closeWelcome()
            replyHandler(["ok": true], nil)

        case "undock":
            undock((body["id"] as? String) ?? "")
            reply(replyHandler)

        case "dropWeb":
            // an image dragged from a browser onto Home: the Vault fetches the biggest version
            guard Shared.vault != nil else { homeToast("Choose your vault first"); return replyHandler(["ok": false], nil) }
            pendingWeb = (url: (body["url"] as? String) ?? "", html: (body["html"] as? String) ?? "")
            pendingImages = []
            askWhere(count: 1, sample: URL(string: pendingWeb!.url)?.host ?? "the web")
            replyHandler(["ok": true], nil)

        case "homeData":
            replyHandler(homeData(body), nil)

        case "saveDropped":
            // the pop-up said where: that project, as references or grabs
            let project = Shell.clean((body["project"] as? String) ?? Shared.project)
            let origin = (body["as"] as? String) == "grab" ? "grab" : "reference"
            if let v = Shared.vault { try? FileManager.default.createDirectory(at: v.appendingPathComponent(project), withIntermediateDirectories: true) }
            if let web = pendingWeb {
                vaultHost.grab(imageData: nil, html: web.html, imageURL: web.url, page: "", via: "drop", into: project, origin: origin)
                homeToast("Saving into \(project)…")
            } else {
                let saved = pendingImages.filter { saveImage($0, into: project, origin: origin) }.count
                homeToast(saved > 0 ? "\(saved) saved into \(project) as \(origin == "grab" ? "grabs" : "references")" : "Couldn't save those")
                if saved > 0 { Shell.post("Saved into \(project)", "\(saved) image\(saved == 1 ? "" : "s"), as \(origin == "grab" ? "grabs" : "references").") }
                home.evaluateJavaScript("window.__homeRefresh && window.__homeRefresh()", completionHandler: nil)
            }
            pendingImages = []; pendingWeb = nil
            replyHandler(["ok": true], nil)

        case "cancelDropped":
            pendingImages = []; pendingWeb = nil
            replyHandler(["ok": true], nil)

        case "deleteItem":
            // to the Trash — recoverable — and gone from the vault
            let ok = vaultHost.removeItem((body["id"] as? String) ?? "")
            replyHandler(["ok": ok], nil)

        case "quick":
            let what = (body["what"] as? String) ?? ""
            let tool = ["link": "vault", "list": "shots", "card": "sort", "invoice": "pay"][what]
            if what == "film" {
                // Open a film: chosen here, then handed to Grab the same way a drop is
                let panel = NSOpenPanel()
                panel.allowedFileTypes = ["mov", "mp4", "m4v", "webm"]
                panel.message = "Choose a film to grab from"
                panel.beginSheetModal(for: window) { r in if r == .OK, let u = panel.url { self.route([u]) } }
            } else if let t = tool {
                show(t)
                if let v = host(t)?.webView { whenReady(v, "__neededQuick", "window.__neededQuick(\(Shell.js(what)))") }
            }
            replyHandler(["ok": true], nil)

        case "revealItem":
            if let v = Shared.vault, let f = body["file"] as? String {
                NSWorkspace.shared.activateFileViewerSelecting([v.appendingPathComponent(f)])
            }
            replyHandler(["ok": true], nil)

        case "openURL":
            if let s = body["url"] as? String, let u = URL(string: s), ["http", "https"].contains(u.scheme ?? "") { NSWorkspace.shared.open(u) }
            replyHandler(["ok": true], nil)

        case "openRef":
            let id = (body["id"] as? String) ?? ""
            show("vault")
            whenReady(vaultHost.webView, "__neededOpen", "window.__neededOpen(\(Shell.js(id)))")
            replyHandler(["ok": true], nil)

        case "openAccounts":
            // Google calendars come in through the Mac: add the account once, and it shows up here.
            let urls = ["x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension",
                        "x-apple.systempreferences:com.apple.preferences.internetaccounts"]
            if let u = urls.compactMap({ URL(string: $0) }).first(where: { NSWorkspace.shared.open($0) }) { _ = u; waitingForGoogle = true }
            replyHandler(["ok": waitingForGoogle, "already": calendarAllowed() ? googleCalendars() : 0], nil)

        case "calendar":
            let from = (body["from"] as? NSNumber)?.doubleValue, to = (body["to"] as? NSNumber)?.doubleValue
            if calendarAllowed() { return calendarWeek(replyHandler, from: from, to: to) }
            let undecided = EKEventStore.authorizationStatus(for: .event) == .notDetermined
            guard (body["ask"] as? Bool) == true, undecided else {
                return replyHandler(["allowed": false, "canAsk": undecided], nil)
            }
            let answered: (Bool, Error?) -> Void = { ok, _ in
                DispatchQueue.main.async {
                    if ok { self.calendarWeek(replyHandler, from: from, to: to) } else { replyHandler(["allowed": false, "canAsk": false], nil) }
                }
            }
            #if compiler(>=5.9)
            if #available(macOS 14.0, *) { calendarStore.requestFullAccessToEvents(completion: answered) }
            else { calendarStore.requestAccess(to: .event, completion: answered) }
            #else
            calendarStore.requestAccess(to: .event, completion: answered)
            #endif

        case "focus":
            let secs = (body["secs"] as? NSNumber)?.doubleValue ?? 0
            let centre = UNUserNotificationCenter.current()
            centre.removePendingNotificationRequests(withIdentifiers: ["needed-focus"])
            if secs > 0 {
                let mins = Int((body["mins"] as? NSNumber)?.intValue ?? Int(secs / 60))
                centre.requestAuthorization(options: [.alert, .sound]) { ok, _ in
                    guard ok else { return }
                    let content = UNMutableNotificationContent()
                    content.title = "Focus done"
                    content.body = "\(mins) minutes. Take a breath."
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, secs), repeats: false)
                    centre.add(UNNotificationRequest(identifier: "needed-focus", content: content, trigger: trigger))
                }
            }
            replyHandler(["ok": true], nil)

        case "signIn":
            // Placeholder: no account or key is checked yet.
            if let s = signin {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
                    s.animator().alphaValue = 0
                }, completionHandler: {
                    s.removeFromSuperview()
                    self.signin = nil
                    self.show("home")
                    if !UserDefaults.standard.bool(forKey: "welcomeHidden") { self.showWelcome("welcome") }
                })
            }
            replyHandler(["ok": true], nil)

        default:
            let a = (body["action"] as? String) ?? ""
            if !projectAction(a, body, replyHandler) && !designAction(a, body, replyHandler) { replyHandler(nil, "unknown action") }
        }
    }

    private func reply(_ r: @escaping (Any?, String?) -> Void) { r(state(), nil) }

    static func clean(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        return s.isEmpty ? "Unsorted" : String(s.prefix(80))
    }

    // MARK: Dialogs from the app's own pages

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    // MARK: Menus — ⌘1 Home, ⌘2 to ⌘7 the tools

    @objc private func pickTab(_ item: NSMenuItem) {
        guard signin == nil, welcome == nil else { return }
        if item.tag == 99 { return show("project") }
        let order = ["home", "vault", "design", "shots", "sort", "grab", "credit", "pay"]
        if item.tag >= 0 && item.tag < order.count { show(order[item.tag]) }
    }

    private func buildMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Needed Tools", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Needed Tools", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Needed Tools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); bar.addItem(editItem)
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

        let viewItem = NSMenuItem(); bar.addItem(viewItem)
        let view = NSMenu(title: "View")
        for (i, name) in ["Home", "Vault", "Design", "Shots", "Sort", "Grab", "Credit", "Pay"].enumerated() {
            let item = view.addItem(withTitle: name, action: #selector(pickTab(_:)), keyEquivalent: "\(i + 1)")
            item.target = self
            item.tag = i
        }
        view.addItem(.separator())
        let proj = view.addItem(withTitle: "Project Page", action: #selector(pickTab(_:)), keyEquivalent: "0")
        proj.target = self
        proj.tag = 99
        viewItem.submenu = view

        let windowItem = NSMenuItem(); bar.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = bar
        NSApp.windowsMenu = windowMenu
    }
}

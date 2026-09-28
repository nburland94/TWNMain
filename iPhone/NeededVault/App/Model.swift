// Needed Mobile Vault for iPhone — what the app knows and does.

import SwiftUI
import PhotosUI
import Photos
import Network
import UniformTypeIdentifiers

/// Something picked or shot, not yet kept: its data (photos) or its place on disk (clips).
struct Picked: Identifiable {
    let id = UUID()
    var data: Data? = nil
    var file: URL? = nil
    var name: String
    var preview: UIImage? = nil
}

enum Tab: String { case home, projects, grab }

@MainActor
final class AppModel: ObservableObject {
    let lib = Library.shared

    @Published var grabs: [Grab] = []
    @Published var projects: [ProjectInfo] = []
    @Published var project: String = Library.shared.lastProject ?? ""
    @Published var tab: Tab = .home
    @Published var opened: String? = nil                 // a project's own page, from Projects or the hero
    @Published var kind: GrabKind? = nil
    @Published var grabGo: String? = Library.shared.grabGo
    @Published var mac: PairedMac? = Library.shared.mac
    @Published var reachable: Bool? = nil                // nil: not asked yet
    @Published var sending = false
    @Published var sendProgress: (Int, Int) = (0, 0)
    @Published var toast: String? = nil
    @Published var pending: [Picked] = []                // waiting on the Keep sheet
    @Published var viewing: Grab? = nil
    @Published var pairing = false
    @Published var projectSheet = false
    @Published var infoSheet = false
    @Published var showCamera = false
    @Published var showPhotos = false
    @Published var onWiFi = false

    private let path = NWPathMonitor(requiredInterfaceType: .wifi)
    private var started = false

    // MARK: What's shown

    var names: [String] {
        var n = projects.map(\.name)
        for g in grabs where !n.contains(g.project) { n.append(g.project) }
        return n
    }
    var waiting: [Grab] { grabs.filter { !$0.sent } }
    func grabs(of p: String) -> [Grab] { grabs.filter { $0.project == p } }
    func shown(_ p: String) -> [Grab] { grabs(of: p).filter { kind == nil || $0.kind == kind } }
    func macCount(_ p: String) -> Int { projects.first { $0.name == p }?.count ?? 0 }
    /// Home's feed: runs of grabs by project, newest run first.
    var runs: [(project: String, items: [Grab])] {
        var out: [(String, [Grab])] = []
        for g in grabs {
            if let i = out.lastIndex(where: { $0.0 == g.project }), i == out.count - 1 { out[i].1.append(g) }
            else { out.append((g.project, [g])) }
        }
        return out.map { (project: $0.0, items: $0.1) }
    }
    var macName: String { mac?.name ?? "your Mac" }

    // MARK: Starting up

    func start() {
        reload()
        guard !started else { return }
        started = true
        if mac == nil { pairing = true }
        path.pathUpdateHandler = { [weak self] p in
            let wifi = p.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let was = self.onWiFi
                self.onWiFi = wifi
                if wifi && !was { await self.send(auto: true) }         // back on Wi-Fi: send what waited
                if !wifi { self.reachable = false }
            }
        }
        path.start(queue: DispatchQueue(label: "needed.path"))
    }

    func reload() {
        grabs = lib.all()
        projects = lib.projects
        grabGo = lib.grabGo
        mac = lib.mac
        if project.isEmpty || !names.contains(project) {
            project = grabGo ?? lib.macProject.flatMap { p in names.contains(p) ? p : nil } ?? names.first ?? ""
            lib.lastProject = project.isEmpty ? nil : project
        }
    }

    /// The app came to the front: anything the Share Sheet kept shows, and what's waiting goes.
    func foreground() async {
        let was = grabGo
        reload()
        if was == nil && grabGo != nil { tab = .grab; opened = nil }      // the side button switched Grab & Go on
        await send(auto: true)
    }

    // MARK: Sending to the Mac

    func send(auto: Bool = false) async {
        guard mac != nil else { if !auto { pairing = true }; return }
        guard !sending else { return }
        if auto && waiting.isEmpty {
            // Nothing to send: still ask the Mac for its projects (quietly).
            sending = true
            let r = await Sender.sendWaiting(limit: 0)
            sending = false
            reachable = r.reached
            reload()
            if r.problem == MacError.notPairedAnymore.errorDescription { toast = r.problem }
            return
        }
        sending = true
        sendProgress = (0, waiting.count)
        let r = await Sender.sendWaiting { done, total in Task { @MainActor in self.sendProgress = (done, total) } }
        sending = false
        reachable = r.reached
        reload()
        if r.sent > 0 {
            toast = r.left == 0 ? (r.sent == 1 ? "Sent to \(macName)" : "\(r.sent) sent to \(macName)")
                                : "\(r.sent) sent — \(r.left) still to go"
        } else if !auto, let p = r.problem {
            toast = p
        }
        if r.problem == MacError.notPairedAnymore.errorDescription { toast = r.problem; if !auto { pairing = true } }
    }

    // MARK: Pairing

    /// The code on the Mac was read. Returns a message if it wasn't the right code.
    func paired(with text: String) async -> String? {
        guard var m = PairedMac.from(text) else { return "That isn't the Needed Tools code — Home › Your phone on your Mac" }
        do {
            let (st, _) = try await MacLink.state(m)
            m.name = st.name
            lib.mac = m
            lib.projects = st.projects
            lib.macProject = st.current
            mac = m
            reachable = true
            reload()
            if let c = st.current, !c.isEmpty { choose(c) }
            await send(auto: true)
            return nil
        } catch {
            // Keep it anyway: the phone may just not be on the Mac's Wi-Fi this second.
            lib.mac = m; mac = m; reachable = false
            return (error as? MacError) == .notPairedAnymore ? MacError.notPairedAnymore.errorDescription : nil
        }
    }
    func unpair() { lib.mac = nil; mac = nil; reachable = nil }

    // MARK: Projects

    func choose(_ p: String) {
        guard !p.isEmpty else { return }
        project = p
        lib.lastProject = p
        if grabGo != nil { setGrabGo(p, quiet: true) }            // Grab & Go follows the project you pick
    }
    func make(_ raw: String) {
        let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        if !projects.contains(where: { $0.name == p }) { projects.append(ProjectInfo(name: p)); lib.projects = projects }
        choose(p)
        toast = "\(p) — named the same as on your Mac, it goes straight into that project"
    }

    // MARK: Grab & Go — on: every photo goes straight into the project, no questions

    func tapGrabGo() {
        if grabGo != nil && tab == .grab { setGrabGo(nil); tab = .home; return }
        if grabGo == nil {
            guard !project.isEmpty else { projectSheet = true; toast = "Pick a project for Grab & Go"; return }
            setGrabGo(project)
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { tab = .grab; opened = nil }
    }
    func setGrabGo(_ p: String?, quiet: Bool = false) {
        lib.grabGo = p
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { grabGo = p }
        if !quiet { toast = p.map { "Grab & Go on — every photo goes to \($0)" } ?? "Grab & Go off" }
    }

    // MARK: Adding

    /// Photos picked or shot: straight in with Grab & Go, else the Keep sheet.
    func take(_ items: [Picked]) {
        guard !items.isEmpty else { return }
        if let g = grabGo { keep(items, in: g, tags: []) } else { pending = items }
    }

    func keep(_ items: [Picked], in p: String, tags: [String]) {
        var n = 0
        for it in items {
            if let d = it.data, lib.add(data: d, name: it.name, project: p, tags: tags) != nil { n += 1 }
            else if let f = it.file, lib.add(file: f, name: it.name, project: p, tags: tags) != nil { n += 1; try? FileManager.default.removeItem(at: f) }
        }
        pending = []
        choose(p)
        reload()
        guard n > 0 else { toast = "Couldn't keep those — photos, screenshots, GIFs and clips only"; return }
        let what = n == 1 ? "Kept for \(p)" : "\(n) kept for \(p)"
        toast = mac == nil ? what : (onWiFi ? what : what + " — it goes to \(macName) on your Wi-Fi")
        Task { await send(auto: true) }
    }

    func move(_ g: Grab, to p: String) {
        lib.move(g.id, to: p)
        reload()
        viewing = grabs.first { $0.id == g.id }
        toast = g.sent ? "Moved on this phone — on \(macName) it stays in \(g.project)" : "Moved to \(p)"
    }
    func delete(_ g: Grab) {
        lib.delete([g.id])
        viewing = nil
        reload()
        toast = g.sent ? "Deleted from this phone — \(macName) keeps its copy" : "Deleted"
    }

    // MARK: From Photos

    static func load(_ picks: [PhotosPickerItem]) async -> [Picked] {
        var out: [Picked] = []
        let base = Library.stamp("Photo")
        for (i, p) in picks.enumerated() {
            let suffix = picks.count > 1 ? " \(i + 1)" : ""
            let isMovie = p.supportedContentTypes.contains { $0.conforms(to: .movie) }
            if isMovie, let m = try? await p.loadTransferable(type: PickedMovie.self) {
                let ext = m.url.pathExtension.isEmpty ? "mov" : m.url.pathExtension
                out.append(Picked(file: m.url, name: Library.stamp("Clip") + suffix + ".\(ext)"))
                continue
            }
            guard let d = try? await p.loadTransferable(type: Data.self) else { continue }
            let isGif = p.supportedContentTypes.contains { $0.conforms(to: .gif) }
            let ext = isGif ? "gif" : (p.supportedContentTypes.first { $0.conforms(to: .image) }?.preferredFilenameExtension ?? "jpg")
            out.append(Picked(data: d, name: base + suffix + ".\(ext)", preview: UIImage(data: d)))
        }
        return out
    }

    static func latestScreenshot() async -> Picked? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: o).firstObject else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<Picked?, Never>) in
            let ro = PHImageRequestOptions()
            ro.isNetworkAccessAllowed = true
            ro.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: ro) { data, uti, _, _ in
                guard let d = data else { return c.resume(returning: nil) }
                let ext = uti.flatMap { UTType($0)?.preferredFilenameExtension } ?? "png"
                c.resume(returning: Picked(data: d, name: Library.stamp("Screenshot") + ".\(ext)"))
            }
        }
    }
}

/// A clip from Photos, copied to a file we own (clips are too big to hold in memory).
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) } importing: { received in
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedMovie(url: dst)
        }
    }
}

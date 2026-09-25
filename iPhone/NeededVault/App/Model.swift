// Needed Vault for iPhone — what the app knows and does.

import SwiftUI
import PhotosUI
import Photos
import UniformTypeIdentifiers

/// One line in "Today": what went in, where, and whether it's waiting on this phone.
struct LogEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var at = Date()
    var what: String
    var project: String
    var count: Int
    var thumb: Data?
    var waiting: Bool
}

@MainActor
final class AppModel: ObservableObject {
    let vault = VaultFolder.shared

    @Published var hasFolder = VaultFolder.shared.hasFolder
    @Published var projects: [VaultProject] = []
    @Published var project: String = VaultFolder.shared.lastProject ?? ""
    @Published var items: [VaultItem] = []
    @Published var grabGo: String? = nil
    @Published var kind: VaultKind? = nil
    @Published var query = ""
    @Published var searching = false
    @Published var loading = false
    @Published var waiting = 0
    @Published var log: [LogEntry] = AppModel.loadLog()
    @Published var toast: String? = nil
    @Published var pending: [SaveFile] = []          // picked, waiting on the Add sheet
    @Published var viewing: Int? = nil               // the picture open full screen

    var shown: [VaultItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { it in
            (kind == nil || it.kind == kind) &&
            (q.isEmpty || (it.name + " " + it.tags.joined(separator: " ")).lowercased().contains(q))
        }
    }
    var count: Int { projects.first { $0.name == project }?.count ?? items.count }
    var today: [LogEntry] { log.filter { Calendar.current.isDateInToday($0.at) } }

    // MARK: Loading

    func refresh() async {
        guard vault.hasFolder else { hasFolder = false; return }
        vault.keepOpen()
        loading = true
        let v = vault, want = project
        let (ps, gg, flushed, mac) = await Task.detached { () -> ([VaultProject], String?, Int, String?) in
            let n = v.flushOutbox()
            return (v.projects(), v.grabGo(), n, v.macProject())
        }.value
        projects = ps
        grabGo = gg
        if want.isEmpty || !ps.contains(where: { $0.name == want }) {
            project = gg ?? ps.first(where: { $0.name == mac })?.name ?? ps.first?.name ?? ""
            vault.lastProject = project
        }
        if flushed > 0 {
            toast = "\(flushed) that waited on this phone went in"
            for i in log.indices where log[i].waiting { log[i].waiting = false }
            saveLog()
        }
        await loadItems()
        waiting = vault.waitingCount
        loading = false
    }
    func loadItems() async {
        let v = vault, p = project
        guard !p.isEmpty else { items = []; return }
        let list = await Task.detached { v.items(of: p) }.value
        if p == project { items = list }
    }

    func choose(_ p: String) {
        project = p
        vault.lastProject = p
        kind = nil; query = ""
        if grabGo != nil { setGrabGo(p) }             // Grab & Go follows the project you pick
        Task { await loadItems() }
    }

    func folderChosen(_ url: URL) {
        do { try vault.remember(url); hasFolder = true; Task { await refresh() } }
        catch { toast = "Couldn't open that folder" }
    }

    // MARK: Grab & Go

    func toggleGrabGo() {
        if grabGo != nil { setGrabGo(nil) } else if !project.isEmpty { setGrabGo(project) } else { toast = "Pick a project first" }
    }
    func setGrabGo(_ p: String?) {
        let ok = vault.setGrabGo(p)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { grabGo = p }
        toast = p.map { "Grab & Go on — \($0)" } ?? "Grab & Go off"
        if !ok { toast = (toast ?? "") + " (on this phone — iCloud isn't reachable)" }
    }

    // MARK: Adding

    /// Photos picked: straight in when Grab & Go is on, else the Add sheet.
    func picked(_ picks: [PhotosPickerItem]) async {
        guard !picks.isEmpty else { return }
        let files = await AppModel.load(picks)
        guard !files.isEmpty else { toast = "Couldn't read those"; return }
        if let g = grabGo { add(files, to: g, tags: [], what: files.count == 1 ? "Photo" : "\(files.count) photos") }
        else { pending = files }
    }
    func latestScreenshot() async {
        guard let f = await AppModel.latestScreenshot() else {
            toast = "No screenshot — or Photos access is off (Settings › Needed Vault › Photos)"; return
        }
        if let g = grabGo { add([f], to: g, tags: [], what: "Screenshot") } else { pending = [f] }
    }
    func add(_ files: [SaveFile], to p: String, tags: [String], what: String? = nil) {
        let r = vault.save(files, project: p, tags: tags)
        let thumb = files.first.flatMap { VaultFolder.thumbnail($0.data, max: 120) }.flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.6) }
        log.insert(LogEntry(what: what ?? (files.count == 1 ? "Photo" : "\(files.count) photos"), project: p, count: files.count, thumb: thumb, waiting: r == .waiting), at: 0)
        if log.count > 60 { log = Array(log.prefix(60)) }
        saveLog()
        pending = []
        waiting = vault.waitingCount
        toast = r == .inVault ? (files.count == 1 ? "Saved to \(p)" : "\(files.count) saved to \(p)") : "Saved on this phone — it goes into \(p) when iCloud's back"
        if p == project { Task { await loadItems() } }
    }

    // MARK: Photos

    static func load(_ picks: [PhotosPickerItem]) async -> [SaveFile] {
        var out: [SaveFile] = []
        let base = VaultFolder.stamp("Photo")
        for (i, p) in picks.enumerated() {
            guard let d = try? await p.loadTransferable(type: Data.self) else { continue }
            let ext = p.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            out.append(SaveFile(data: d, name: base + (picks.count > 1 ? " \(i + 1)" : "") + ".\(ext)"))
        }
        return out
    }
    static func latestScreenshot() async -> SaveFile? {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: o).firstObject else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<SaveFile?, Never>) in
            let ro = PHImageRequestOptions()
            ro.isNetworkAccessAllowed = true
            ro.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: ro) { data, uti, _, _ in
                guard let d = data else { return c.resume(returning: nil) }
                let ext = uti.flatMap { UTType($0)?.preferredFilenameExtension } ?? "png"
                c.resume(returning: SaveFile(data: d, name: VaultFolder.stamp("Screenshot") + ".\(ext)"))
            }
        }
    }

    // MARK: Today's list, kept on this phone

    private static func loadLog() -> [LogEntry] {
        guard let d = VaultFolder.shared.defaults.data(forKey: "log") else { return [] }
        return (try? JSONDecoder().decode([LogEntry].self, from: d)) ?? []
    }
    private func saveLog() {
        if let d = try? JSONEncoder().encode(log) { vault.defaults.set(d, forKey: "log") }
    }
}

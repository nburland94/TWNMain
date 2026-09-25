// Needed Tools — Needed Vault through Apple Photos (Round 22).
// The phone's Sync saves what you kept into Photos, named for its project and tags.
// iCloud Photos carries it to this Mac, wherever the phone was. Sync here finds those
// pictures and clips in the Photos library, copies each into its project's references
// (once — Needed Tools remembers every one it has filed), and sorts them in Photos into
//     Needed Vault › Lexus
// so the phone's Photos shows the same projects too. Photos keeps its own copy; the
// vault keeps one. Nothing is ever deleted from Photos.

import Foundation
import Photos

enum PhotosInbox {
    /// Home › Your phone › "From Photos" — on unless you switch it off.
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: "photosInbox") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "photosInbox") }
    }
    static var albums: Bool {
        get { UserDefaults.standard.object(forKey: "photosAlbums") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "photosAlbums") }
    }
    static let folderName = "Needed Vault"

    static var status: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: return "allowed"
        case .notDetermined: return "ask"
        default: return "denied"
        }
    }

    /// Asks the first time. Off the main thread only.
    static func allowed() -> Bool {
        let st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if st == .authorized || st == .limited { return true }
        guard st == .notDetermined else { return false }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
            ok = (s == .authorized || s == .limited)
            sem.signal()
        }
        sem.wait()
        return ok
    }

    // Photos items already looked at, so they're never downloaded twice.
    private static func assetsURL(_ base: URL) -> URL { base.appendingPathComponent(".vault/photos-seen.json") }
    private static func loadAssets(_ base: URL) -> Set<String> {
        Set(((try? Data(contentsOf: assetsURL(base))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String] }) ?? [])
    }
    private static func saveAssets(_ s: Set<String>, _ base: URL) {
        if let d = try? JSONSerialization.data(withJSONObject: Array(s)) { try? d.write(to: assetsURL(base), options: .atomic) }
    }

    // Phone ids already sorted into a Needed Vault album — a picture synced twice goes in the album once.
    private static func albumedURL(_ base: URL) -> URL { base.appendingPathComponent(".vault/photos-albumed.json") }
    private static func loadAlbumed(_ base: URL) -> Set<String> {
        Set(((try? Data(contentsOf: albumedURL(base))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String] }) ?? [])
    }
    private static func saveAlbumed(_ s: Set<String>, _ base: URL) {
        if let d = try? JSONSerialization.data(withJSONObject: Array(s)) { try? d.write(to: albumedURL(base), options: .atomic) }
    }

    /// New Needed Vault pictures in Photos → their projects. Off the main thread (Sync calls it).
    static func collect(base: URL, fallback: String, existing: [String], progress: ((Double) -> Void)?) -> ([PhoneDrops.Drop], Int, String?) {
        guard on else { return ([], 0, nil) }
        guard allowed() else { return ([], 0, "Photos is off for Needed Tools — System Settings › Privacy & Security › Photos") }
        let key = "photosScan:" + base.path
        // Since the last look (with a few days' grace for iCloud), or the last 60 days the first time.
        let since = (UserDefaults.standard.object(forKey: key) as? Date)?.addingTimeInterval(-3 * 86400) ?? Date().addingTimeInterval(-60 * 86400)
        let started = Date()
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "(creationDate > %@ OR modificationDate > %@) AND (mediaType == %d OR mediaType == %d)",
                                     since as NSDate, since as NSDate, PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let assets = PHAsset.fetchAssets(with: opts)
        var looked = loadAssets(base)
        var seen = PhoneDrops.loadSeen(base)
        var albumed = loadAlbumed(base)
        /// Into its project's album, unless that picture (by the phone's id) is already there.
        func toAlbum(_ project: String, _ a: PHAsset, _ id: String) -> [String: [PHAsset]] {
            if !id.isEmpty { if albumed.contains(id) { return [:] }; albumed.insert(id) }
            return [project: [a]]
        }

        var found: [(PHAsset, PHAssetResource, PhoneDrops.Parsed)] = []
        assets.enumerateObjects { a, _, _ in
            if looked.contains(a.localIdentifier) { return }
            let rs = PHAssetResource.assetResources(for: a)
            let named = rs.filter { $0.originalFilename.hasPrefix("NV ~ ") }
            guard let r = named.first(where: { $0.type == .photo || $0.type == .video }) ?? named.first,
                  let p = PhoneDrops.parse(r.originalFilename) else { return }
            found.append((a, r, p))
        }

        var out: [PhoneDrops.Drop] = [], twice = 0, failed = 0
        var sortInto: [String: [PHAsset]] = [:]
        let tmpRoot = FileManager.default.temporaryDirectory.appendingPathComponent("needed-photos-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }
        for (i, (a, r, p)) in found.enumerated() {
            progress?(Double(i) / Double(max(1, found.count)))
            let project = PhoneDrops.projectFor(p.project, fallback: fallback, existing: existing)
            if !p.id.isEmpty, seen[p.id] != nil {               // already in the vault (it came by AirDrop, or twice)
                looked.insert(a.localIdentifier); twice += 1
                sortInto.merge(toAlbum(project, a, p.id)) { $0 + $1 }
                continue
            }
            // The original, from iCloud if this Mac only keeps a small copy.
            let safe = r.originalFilename.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let tmp = tmpRoot.appendingPathComponent(safe)
            let o = PHAssetResourceRequestOptions()
            o.isNetworkAccessAllowed = true
            let sem = DispatchSemaphore(value: 0)
            var err: Error?
            PHAssetResourceManager.default().writeData(for: r, toFile: tmp, options: o) { e in err = e; sem.signal() }
            if sem.wait(timeout: .now() + 180) == .timedOut || err != nil { failed += 1; continue }   // next Sync tries again
            guard let d = PhoneDrops.place(tmp, p, base: base, fallback: fallback, existing: existing, move: true, via: "photos") else { failed += 1; continue }
            if !d.phoneId.isEmpty { seen[d.phoneId] = d.file.path.replacingOccurrences(of: base.path + "/", with: "") }
            looked.insert(a.localIdentifier)
            sortInto.merge(toAlbum(d.project, a, d.phoneId)) { $0 + $1 }
            out.append(d)
        }
        progress?(1)
        PhoneDrops.saveSeen(seen, base)
        saveAssets(looked, base)
        if albums { saveAlbumed(albumed, base) }
        if failed == 0 { UserDefaults.standard.set(started, forKey: key) }
        if albums { sort(sortInto) }
        let note: String? = failed > 0 ? "\(failed) still coming down from iCloud — Sync again in a bit" : nil
        return (out, twice, note)
    }

    // MARK: Photos › Needed Vault › <project>

    private static func folder() -> PHCollectionList? {
        let o = PHFetchOptions()
        o.predicate = NSPredicate(format: "title == %@", folderName)
        if let f = PHCollectionList.fetchCollectionLists(with: .folder, subtype: .regularFolder, options: o).firstObject { return f }
        var id: String?
        try? PHPhotoLibrary.shared().performChangesAndWait {
            id = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: folderName).placeholderForCreatedCollectionList.localIdentifier
        }
        guard let made = id else { return nil }
        return PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [made], options: nil).firstObject
    }

    private static func album(_ title: String, in folder: PHCollectionList) -> PHAssetCollection? {
        var hit: PHAssetCollection?
        PHCollection.fetchCollections(in: folder, options: nil).enumerateObjects { c, _, stop in
            if let a = c as? PHAssetCollection, (a.localizedTitle ?? "").caseInsensitiveCompare(title) == .orderedSame { hit = a; stop.pointee = true }
        }
        if let h = hit { return h }
        var id: String?
        try? PHPhotoLibrary.shared().performChangesAndWait {
            let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            let ph = req.placeholderForCreatedAssetCollection
            id = ph.localIdentifier
            PHCollectionListChangeRequest(for: folder)?.addChildCollections([ph] as NSArray)
        }
        guard let made = id else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [made], options: nil).firstObject
    }

    private static func sort(_ byProject: [String: [PHAsset]]) {
        guard !byProject.isEmpty, let f = folder() else { return }
        for (project, assets) in byProject where !assets.isEmpty {
            guard let a = album(project, in: f) else { continue }
            try? PHPhotoLibrary.shared().performChangesAndWait {
                PHAssetCollectionChangeRequest(for: a)?.addAssets(assets as NSArray)
            }
        }
    }
}

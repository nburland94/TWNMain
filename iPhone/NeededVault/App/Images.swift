// Needed Vault for iPhone — pictures: small ones for the grid, big ones for the view,
// GIFs that play, a frame from each clip. Files are read while the folder is open.

import SwiftUI
import AVFoundation
import ImageIO

enum Pictures {
    static let cache = NSCache<NSString, UIImage>()

    /// The picture at this size — from the cache, or read from the vault folder.
    static func image(_ item: VaultItem, max: Int) async -> UIImage? {
        let key = "\(item.id)@\(max)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            VaultFolder.shared.open { _ -> UIImage? in
                if item.kind == .clip {
                    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: item.url))
                    gen.appliesPreferredTrackTransform = true
                    gen.maximumSize = CGSize(width: max, height: max)
                    let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
                    return cg.map { UIImage(cgImage: $0) }
                }
                return VaultFolder.thumbnail(item.url, max: max).map { UIImage(cgImage: $0) }
            }.flatMap { $0 }
        }.value
        if let i = img { cache.setObject(i, forKey: key) }
        return img
    }

    /// A GIF's frames, to play.
    static func animated(_ item: VaultItem, max: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            VaultFolder.shared.open { _ -> UIImage? in
                var out: UIImage?
                var err: NSError?
                NSFileCoordinator().coordinate(readingItemAt: item.url, options: [], error: &err) { u in
                    guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return }
                    let n = min(CGImageSourceGetCount(src), 180)
                    var frames: [UIImage] = [], total = 0.0
                    let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max,
                                              kCGImageSourceCreateThumbnailWithTransform: true]
                    for i in 0..<n {
                        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, i, o as CFDictionary) else { continue }
                        frames.append(UIImage(cgImage: cg))
                        let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
                        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                        let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
                        total += d < 0.02 ? 0.1 : d
                    }
                    out = frames.count > 1 ? UIImage.animatedImage(with: frames, duration: total) : frames.first
                }
                return out
            }.flatMap { $0 }
        }.value
    }
}

/// A picture that fills its frame: the Mac's tiny preview first, then the real one.
struct Thumb: View {
    let item: VaultItem
    var max = 420
    @State private var img: UIImage?
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: item.palette.first ?? "#d9cfc4"), Color(hex: item.palette.dropFirst().first ?? item.palette.first ?? "#b8a898")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let i = img ?? item.tiny.flatMap({ UIImage(data: $0) }) {
                Image(uiImage: i).resizable().scaledToFill()
            }
        }
        .clipped()
        .task(id: item.id) { img = await Pictures.image(item, max: max) }
    }
}

/// UIImageView, so GIFs play.
struct Playing: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }
    func updateUIView(_ v: UIImageView, context: Context) {
        v.image = image
        if image.images != nil { v.startAnimating() }
    }
}

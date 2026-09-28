// Needed Mobile Vault for iPhone — pictures: the small preview for the feed, the full
// picture for the view, GIFs that play, clips that play.

import SwiftUI
import AVKit
import ImageIO

enum Pictures {
    static let cache = NSCache<NSString, UIImage>()

    /// The feed's preview (made when the grab was kept).
    static func thumb(_ g: Grab) async -> UIImage? {
        let key = "t:\(g.id)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let url = Library.shared.thumbURL(g)
        let img = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if let d = try? Data(contentsOf: url), let i = UIImage(data: d) { return i }
            // No preview yet (an older grab): make one now.
            let (d, _) = Library.preview(of: Library.shared.fileURL(g), kind: g.kind, max: 900)
            if let d { try? d.write(to: url, options: .atomic) }
            return d.flatMap { UIImage(data: $0) }
        }.value
        if let i = img { cache.setObject(i, forKey: key) }
        return img
    }

    /// The whole picture, big — a GIF comes back animated.
    static func full(_ g: Grab, max: Int = 2400) async -> UIImage? {
        let url = Library.shared.fileURL(g)
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: max,
                                      kCGImageSourceCreateThumbnailWithTransform: true]
            let n = min(CGImageSourceGetCount(src), 180)
            guard g.kind == .gif, n > 1 else {
                return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary).map { UIImage(cgImage: $0) }
            }
            var frames: [UIImage] = [], total = 0.0
            let small: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900,
                                          kCGImageSourceCreateThumbnailWithTransform: true]
            for i in 0..<n {
                guard let cg = CGImageSourceCreateThumbnailAtIndex(src, i, small as CFDictionary) else { continue }
                frames.append(UIImage(cgImage: cg))
                let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
                let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
                total += d < 0.02 ? 0.1 : d
            }
            return frames.count > 1 ? UIImage.animatedImage(with: frames, duration: total) : frames.first
        }.value
    }
}

/// A grab's preview, filling its frame.
struct Thumb: View {
    let grab: Grab
    @State private var img: UIImage?
    var body: some View {
        // The picture is an overlay, so it fills and crops to the frame without ever changing its size.
        Color(hex: "#efe4db")
            .overlay {
                if let i = img { Image(uiImage: i).resizable().scaledToFill().transition(.opacity) }
            }
            .clipped()
        .task(id: grab.id) {
            let i = await Pictures.thumb(grab)
            withAnimation(.easeOut(duration: 0.2)) { img = i }
        }
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

/// A clip, playing on a loop with no sound until you ask.
struct ClipPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let p = AVPlayer(url: url)
                p.isMuted = true
                p.actionAtItemEnd = .none
                NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
                    p.seek(to: .zero); p.play()
                }
                player = p
                p.play()
            }
            .onDisappear { player?.pause() }
    }
}

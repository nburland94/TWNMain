import AppKit
import ImageIO

/// Clipboard decoding is independent of web downloads: Copy Image must save what the browser supplied.
enum GrabImageCapture {
    static func size(_ data: Data) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0 else { return nil }
        return (w, h)
    }
    static func clipboardImage(_ pb: NSPasteboard) -> Data? {
        for type in ["public.png", "public.tiff", "public.jpeg", "org.webmproject.webp", "public.webp", "public.heic", "public.avif", "com.compuserve.gif"] {
            if let data = pb.data(forType: .init(type)), size(data) != nil { return data }
        }
        if let data = pb.data(forType: .init("com.apple.webarchive")),
           let archive = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let resources = [archive["WebMainResource"] as? [String: Any] ?? [:]] + (archive["WebSubresources"] as? [[String: Any]] ?? [])
            for r in resources { if let d = r["WebResourceData"] as? Data, size(d) != nil { return d } }
        }
        if let data = NSImage(pasteboard: pb)?.tiffRepresentation, size(data) != nil { return data }
        return nil
    }
    static func imageAddress(_ s: String) -> Bool {
        guard let u = URL(string: s), ["http", "https"].contains(u.scheme?.lowercased() ?? "") else { return false }
        let host = u.host?.lowercased() ?? ""
        return host == "i.pinimg.com" || ["jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "tiff", "tif"].contains(u.pathExtension.lowercased())
    }
    static func candidates(html: String, imageURL: String, page: String) -> [URL] {
        var values: [String] = []
        let decode: (String) -> String = { $0.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#38;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").trimmingCharacters(in: .whitespacesAndNewlines) }
        if let range = html.range(of: #"<img\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            let tag = String(html[range])
            func attr(_ name: String) -> String? {
                let pattern = #"(?:\s)"# + name + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
                guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
                for i in 1...3 { if let r = Range(m.range(at: i), in: tag) { return decode(String(tag[r])) } }
                return nil
            }
            if let set = attr("srcset") {
                var ranked: [(String, Double)] = []
                for part in set.split(separator: ",") {
                    let bits = part.split(whereSeparator: { $0.isWhitespace })
                    guard let first = bits.first else { continue }
                    let rank = bits.count > 1 ? (Double(bits[1].dropLast()) ?? 1) : 1
                    ranked.append((decode(String(first)), rank))
                }
                values += ranked.sorted { $0.1 > $1.1 }.map { $0.0 }
            }
            if let src = attr("src") { values.append(src) }
        }
        if !imageURL.isEmpty { values.append(imageURL) }
        let base = URL(string: page.isEmpty ? imageURL : page)
        var result: [URL] = []
        for value in values {
            guard let u = URL(string: value, relativeTo: base)?.absoluteURL, ["http", "https"].contains(u.scheme?.lowercased() ?? ""), !result.contains(u) else { continue }
            // Use the browser's real URL first. Invented Pinterest /originals/ URLs frequently fail.
            result.append(u)
        }
        return result
    }
    /// Used only when the clipboard has no image bytes. Bounded and cancellable; no late callback race.
    static func download(_ url: URL, page: String, timeout: TimeInterval) -> Data? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if let p = URL(string: page), ["http", "https"].contains(p.scheme ?? "") { request.setValue(p.absoluteString, forHTTPHeaderField: "Referer") }
        let lock = NSLock(), wait = DispatchSemaphore(value: 0)
        var result: Data?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            lock.lock()
            if let http = response as? HTTPURLResponse, http.statusCode == 200 { result = data }
            lock.unlock(); wait.signal()
        }
        task.resume()
        if wait.wait(timeout: .now() + timeout) == .timedOut { task.cancel(); return nil }
        lock.lock(); defer { lock.unlock() }; return result
    }
}

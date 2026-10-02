import Foundation
import CryptoKit
import Darwin

/// Originals are never modified by copying. A failed/cancelled copy removes only its own output.
enum SortFileTransfer {
    static func digest(_ url: URL, cancelled: () -> Bool = { false }, progress: (Int) -> Void = { _ in }) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        _ = fcntl(file.fileDescriptor, F_NOCACHE, 1)
        var hash = SHA256()
        while true {
            if cancelled() { throw CocoaError(.userCancelled) }
            let data = try file.read(upToCount: 8 * 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data); progress(data.count)
        }
        return Data(hash.finalize())
    }

    static func copy(_ src: URL, to dst: URL, cancelled: () -> Bool, progress: (Int) -> Void) -> Bool {
        let fd = open(dst.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return false }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var complete = false
        defer { try? output.close(); if !complete { try? FileManager.default.removeItem(at: dst) } }
        do {
            let input = try FileHandle(forReadingFrom: src)
            defer { try? input.close() }
            var hash = SHA256()
            while true {
                if cancelled() { throw CocoaError(.userCancelled) }
                let data = try input.read(upToCount: 8 * 1024 * 1024) ?? Data()
                if data.isEmpty { break }
                try output.write(contentsOf: data)
                hash.update(data: data); progress(data.count)
            }
            try output.synchronize()
            guard try digest(dst, cancelled: cancelled, progress: progress) == Data(hash.finalize()) else { return false }
            let attrs = try FileManager.default.attributesOfItem(atPath: src.path)
            var dates: [FileAttributeKey: Any] = [:]
            for key in [FileAttributeKey.modificationDate, .creationDate] { dates[key] = attrs[key] }
            try? FileManager.default.setAttributes(dates, ofItemAtPath: dst.path)
            complete = true
            return true
        } catch { return false }
    }

    static func removeVerifiedOriginal(_ src: URL, destination: URL, cancelled: () -> Bool) throws {
        guard src.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath() else { throw CocoaError(.fileWriteInvalidFileName) }
        let original = try digest(src, cancelled: cancelled)
        let saved = try digest(destination, cancelled: cancelled)
        guard original == saved, !cancelled() else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.removeItem(at: src)
    }
}

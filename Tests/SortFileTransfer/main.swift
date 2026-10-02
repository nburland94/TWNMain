import Foundation
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let src = root.appendingPathComponent("source.mxf"), dst = root.appendingPathComponent("copy.mxf")
let bytes = Data((0..<20000).map { UInt8($0 % 251) })
try bytes.write(to: src)
assert(SortFileTransfer.copy(src, to: dst, cancelled: { false }, progress: { _ in }))
let same = try Data(contentsOf: src) == Data(contentsOf: dst)
assert(same)
assert(!SortFileTransfer.copy(src, to: dst, cancelled: { false }, progress: { _ in }))
let preserved = try Data(contentsOf: dst) == bytes
assert(preserved) // existing output must survive
let cancelled = root.appendingPathComponent("cancelled.mxf")
assert(!SortFileTransfer.copy(src, to: cancelled, cancelled: { true }, progress: { _ in }))
assert(!fm.fileExists(atPath: cancelled.path) && fm.fileExists(atPath: src.path))
try Data("changed".utf8).write(to: src)
do { try SortFileTransfer.removeVerifiedOriginal(src, destination: dst, cancelled: { false }); fatalError("changed source removed") } catch {}
assert(fm.fileExists(atPath: src.path))
try bytes.write(to: src)
do { try SortFileTransfer.removeVerifiedOriginal(src, destination: dst, cancelled: { true }); fatalError("cancel ignored") } catch {}
try SortFileTransfer.removeVerifiedOriginal(src, destination: dst, cancelled: { false })
assert(!fm.fileExists(atPath: src.path) && fm.fileExists(atPath: dst.path))
print("PASS: copy, collisions, cancellation, changed originals, verified move")

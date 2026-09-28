// Needed Mobile Vault for iPhone — in every app's Share Sheet. Screenshots, photos, GIFs and
// clips are kept for a project: straight away when Grab & Go is on, else pick the project
// (and tags) and tap Keep. They go to your Mac from here if you're on its Wi-Fi, or the
// next time the app is.

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

/// What came in: a file on disk (the Share Sheet hands us copies).
struct Incoming { let file: URL; let name: String }

@MainActor
final class ShareModel: ObservableObject {
    enum State: Equatable { case loading, ready, done(String), nothing }
    weak var context: NSExtensionContext?
    let lib = Library.shared
    @Published var files: [Incoming] = []
    @Published var thumbs: [UIImage] = []
    @Published var projects: [String] = []
    @Published var project = ""
    @Published var tags = ""
    @Published var state: State = .loading

    init(context: NSExtensionContext?) { self.context = context }

    func load() async {
        let providers = ((context?.inputItems as? [NSExtensionItem]) ?? []).flatMap { $0.attachments ?? [] }
        var got: [Incoming] = []
        let stamp = Library.stamp("Shared")
        for (i, p) in providers.enumerated() {
            guard let type = [UTType.gif, .movie, .image].first(where: { t in p.registeredTypeIdentifiers.contains { UTType($0)?.conforms(to: t) == true } }) else { continue }
            let id = p.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: type) == true } ?? type.identifier
            if let f = await ShareModel.file(from: p, type: id, fallbackName: "\(stamp)\(providers.count > 1 ? " \(i + 1)" : "")") { got.append(f) }
        }
        files = got
        thumbs = got.prefix(12).compactMap { f in
            let kind = GrabKind.of(ext: f.file.pathExtension) ?? .still
            return Library.preview(of: f.file, kind: kind, max: 240).0.flatMap { UIImage(data: $0) }
        }
        guard !got.isEmpty else { state = .nothing; return }
        projects = lib.projectNames()
        project = lib.grabGo ?? lib.lastProject ?? projects.first ?? ""
        if let g = lib.grabGo { await keep(into: g) } else { state = .ready }
    }

    func keep(into p: String) async {
        guard !p.isEmpty else { return }
        let t = tags.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        var n = 0
        for f in files { if lib.add(file: f.file, name: f.name, project: p, tags: t) != nil { n += 1 } }
        lib.lastProject = p
        guard n > 0 else { state = .done("Couldn't keep those"); return close(after: 1.4) }
        state = .done(n == 1 ? "Kept for \(p)" : "\(n) kept for \(p)")
        // On the Mac's Wi-Fi? Send now. If not, the app sends it later.
        if lib.mac != nil {
            let r = await Sender.sendWaiting(limit: n)
            state = .done(r.sent > 0 ? (n == 1 ? "Sent to \(p) on \(lib.mac?.name ?? "your Mac")" : "\(r.sent) sent to \(p)")
                                     : (n == 1 ? "Kept for \(p) — it goes to your Mac on its Wi-Fi" : "\(n) kept for \(p) — they go to your Mac on its Wi-Fi"))
        }
        close(after: 1.1)
    }
    func close(after s: Double = 0) {
        Task { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)); context?.completeRequest(returningItems: nil) }
    }

    static func file(from p: NSItemProvider, type: String, fallbackName: String) async -> Incoming? {
        await withCheckedContinuation { (c: CheckedContinuation<Incoming?, Never>) in
            _ = p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                if let u = url {
                    // The provider's copy goes when this returns: keep our own.
                    let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(u.pathExtension)
                    if (try? FileManager.default.copyItem(at: u, to: dst)) != nil {
                        return c.resume(returning: Incoming(file: dst, name: u.lastPathComponent))
                    }
                }
                _ = p.loadDataRepresentation(forTypeIdentifier: type) { d, _ in
                    guard let d = d else { return c.resume(returning: nil) }
                    let ext = UTType(type)?.preferredFilenameExtension ?? "jpg"
                    let dst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                    guard (try? d.write(to: dst)) != nil else { return c.resume(returning: nil) }
                    c.resume(returning: Incoming(file: dst, name: "\(fallbackName).\(ext)"))
                }
            }
        }
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Cap(text: "Needed Mobile Vault")
                    Spacer()
                    Button("Cancel") { model.close() }.font(NVFont.raleway(14)).foregroundColor(.nvSoft)
                }
                switch model.state {
                case .loading:
                    Text("Opening…").font(NVFont.raleway(26, 200))
                case .nothing:
                    Text("Nothing to keep").font(NVFont.raleway(26, 200))
                    Text("Needed Mobile Vault takes photos, screenshots, GIFs and clips.").font(NVFont.raleway(13)).foregroundColor(.nvSoft)
                case .done(let msg):
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundColor(.nvOrange)
                        Text(msg).font(NVFont.raleway(20, 300))
                    }
                case .ready:
                    Text(model.files.count == 1 ? "Keep for \(model.project)" : "Keep \(model.files.count) for \(model.project)").font(NVFont.raleway(26, 200)).lineLimit(2)
                    if !model.thumbs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) { ForEach(model.thumbs.indices, id: \.self) { i in
                                Image(uiImage: model.thumbs[i]).resizable().scaledToFill().frame(width: 72, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                            } }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(model.projects, id: \.self) { p in
                            Button(p) { model.project = p }.buttonStyle(ChipStyle(on: model.project == p))
                        } }
                    }
                    if model.projects.isEmpty {
                        Text("Open Needed Mobile Vault once and pair it with your Mac — then your projects show here.").font(NVFont.raleway(13)).foregroundColor(.nvSoft)
                    }
                    TextField("Tags, if you like — night, car", text: $model.tags)
                        .font(NVFont.raleway(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .background(Capsule().fill(.white.opacity(0.9))).overlay(Capsule().stroke(Color.nvInk.opacity(0.12)))
                    Button { Task { await model.keep(into: model.project) } } label: { Text("Keep") }.buttonStyle(DarkPill()).disabled(model.project.isEmpty)
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.nvPaper).overlay(
                RadialGradient(colors: [Color(hex: "#f9cfb1").opacity(0.6), .clear], center: .top, startRadius: 0, endRadius: 320).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))))
            .padding(12)
        }
        .preferredColorScheme(.light)
    }
}

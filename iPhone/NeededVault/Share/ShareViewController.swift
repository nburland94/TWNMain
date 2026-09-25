// Needed Vault for iPhone — in every app's Share Sheet. Screenshots, photos, GIFs and
// clips go into a project: straight away when Grab & Go is on, else pick the project
// (and tags) and tap Save.

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

@MainActor
final class ShareModel: ObservableObject {
    enum State: Equatable { case loading, ready, done(String), nothing }
    weak var context: NSExtensionContext?
    let vault = VaultFolder.shared
    @Published var files: [SaveFile] = []
    @Published var thumbs: [UIImage] = []
    @Published var projects: [VaultProject] = []
    @Published var project = ""
    @Published var tags = ""
    @Published var state: State = .loading
    @Published var grabGo: String? = nil

    init(context: NSExtensionContext?) { self.context = context }

    func load() async {
        let providers = ((context?.inputItems as? [NSExtensionItem]) ?? []).flatMap { $0.attachments ?? [] }
        var got: [SaveFile] = []
        let stamp = VaultFolder.stamp("Shared")
        for (i, p) in providers.enumerated() {
            guard let type = [UTType.gif, .movie, .image].first(where: { t in p.registeredTypeIdentifiers.contains { UTType($0)?.conforms(to: t) == true } }) else { continue }
            let id = p.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: type) == true } ?? type.identifier
            if let f = await ShareModel.file(from: p, type: id, fallbackName: "\(stamp)\(providers.count > 1 ? " \(i + 1)" : "")") { got.append(f) }
        }
        files = got
        thumbs = got.compactMap { VaultFolder.thumbnail($0.data, max: 240).map { UIImage(cgImage: $0) } }
        guard !got.isEmpty else { state = .nothing; return }
        let v = vault
        let (ps, gg) = await Task.detached { (v.projects(), v.grabGo()) }.value
        projects = ps
        grabGo = gg
        project = gg ?? v.lastProject ?? ps.first?.name ?? ""
        if let g = gg { save(into: g) } else { state = .ready }
    }

    func save(into p: String) {
        guard !p.isEmpty else { return }
        let t = tags.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        let r = vault.save(files, project: p, tags: t)
        vault.lastProject = p
        state = .done(r == .inVault ? "Saved to \(p)" : "Saved — it goes into \(p) when you open Needed Vault")
        Task { try? await Task.sleep(nanoseconds: 1_100_000_000); close() }
    }
    func close() { context?.completeRequest(returningItems: nil) }

    static func file(from p: NSItemProvider, type: String, fallbackName: String) async -> SaveFile? {
        await withCheckedContinuation { (c: CheckedContinuation<SaveFile?, Never>) in
            _ = p.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                if let u = url, let d = try? Data(contentsOf: u) {
                    return c.resume(returning: SaveFile(data: d, name: u.lastPathComponent))
                }
                _ = p.loadDataRepresentation(forTypeIdentifier: type) { d, _ in
                    guard let d = d else { return c.resume(returning: nil) }
                    let ext = UTType(type)?.preferredFilenameExtension ?? "jpg"
                    c.resume(returning: SaveFile(data: d, name: "\(fallbackName).\(ext)"))
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
                    Cap(text: "Needed Vault")
                    Spacer()
                    Button("Cancel") { model.close() }.font(NVFont.raleway(14)).foregroundColor(.nvSoft)
                }
                switch model.state {
                case .loading:
                    Text("Opening…").font(NVFont.raleway(26, 200))
                case .nothing:
                    Text("Nothing to save").font(NVFont.raleway(26, 200))
                    Text("Needed Vault takes photos, screenshots, GIFs and clips.").font(NVFont.raleway(13)).foregroundColor(.nvSoft)
                case .done(let msg):
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundColor(.nvOrange)
                        Text(msg).font(NVFont.raleway(20, 300))
                    }
                case .ready:
                    Text(model.files.count == 1 ? "Save to \(model.project)" : "Save \(model.files.count) to \(model.project)").font(NVFont.raleway(26, 200)).lineLimit(2)
                    if !model.thumbs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) { ForEach(model.thumbs.indices, id: \.self) { i in
                                Image(uiImage: model.thumbs[i]).resizable().scaledToFill().frame(width: 72, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                            } }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(model.projects) { p in
                            Button(p.name) { model.project = p.name }.buttonStyle(ChipStyle(on: model.project == p.name))
                        } }
                    }
                    if model.projects.isEmpty {
                        Text("Open Needed Vault once and choose the folder — then your projects show here.").font(NVFont.raleway(13)).foregroundColor(.nvSoft)
                    }
                    TextField("Tags, if you like — night, car", text: $model.tags)
                        .font(NVFont.raleway(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .background(Capsule().fill(.white.opacity(0.9))).overlay(Capsule().stroke(Color.nvInk.opacity(0.12)))
                    Button { model.save(into: model.project) } label: { Text("Save") }.buttonStyle(DarkPill()).disabled(model.project.isEmpty)
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

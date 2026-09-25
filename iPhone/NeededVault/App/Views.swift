// Needed Vault for iPhone — the screens, as the mock-up: Browse, one picture,
// Grab & Go on, adding, and the one-time set-up.

import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

@main
struct NeededVaultApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Root().environmentObject(model)
                .task { await model.refresh() }
                .onChange(of: phase) { p in if p == .active { Task { await model.refresh() } } }
        }
    }
}

struct Root: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack(alignment: .bottom) {
            Glow()
            if model.hasFolder { Main() } else { Setup() }
            if let t = model.toast { Toast(text: t).padding(.bottom, 104).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .preferredColorScheme(.light)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: model.toast)
        .onChange(of: model.toast) { t in
            guard t != nil else { return }
            Task { try? await Task.sleep(nanoseconds: 2_600_000_000); if model.toast == t { model.toast = nil } }
        }
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text).font(NVFont.raleway(13.5)).foregroundColor(.nvInk).multilineTextAlignment(.center)
            .padding(.vertical, 10).padding(.horizontal, 16).glass(100).padding(.horizontal, 24)
    }
}

// MARK: - The top: the mark, the project, Grab & Go

struct Header: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            Image("Mark").resizable().scaledToFit().frame(width: 34)
            Menu {
                ForEach(model.projects) { p in
                    Button { model.choose(p.name) } label: {
                        if p.name == model.project { Label("\(p.name) · \(p.count)", systemImage: "checkmark") } else { Text("\(p.name) · \(p.count)") }
                    }
                }
                if model.projects.isEmpty { Text("No projects yet — Sync on your Mac") }
            } label: {
                HStack(spacing: 6) {
                    Text(model.project.isEmpty ? "Projects" : model.project).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(NVFont.raleway(14)).foregroundColor(.white)
                .padding(.vertical, 8).padding(.horizontal, 14)
                .background(Capsule().fill(Color.nvOrange))
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Text("GRAB & GO").font(NVFont.oswald(11.5)).tracking(1.4).foregroundColor(model.grabGo != nil ? .nvOrangeInk : .nvSoft)
                NVSwitch(on: model.grabGo != nil) { model.toggleGrabGo() }
            }
        }
        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 10)
    }
}

struct Main: View {
    @EnvironmentObject var model: AppModel
    @State private var picks: [PhotosPickerItem] = []
    var body: some View {
        VStack(spacing: 0) {
            Header()
            if model.grabGo != nil { OnScreen() } else { Browse() }
        }
        .overlay(alignment: .bottom) { if model.grabGo == nil { bottomBar } }
        .sheet(isPresented: Binding(get: { !model.pending.isEmpty && model.grabGo == nil }, set: { if !$0 { model.pending = [] } })) {
            AddSheet().environmentObject(model).presentationDetents([.medium, .large]).presentationCornerRadius(28)
        }
        .fullScreenCover(isPresented: Binding(get: { model.viewing != nil }, set: { if !$0 { model.viewing = nil } })) {
            Viewer(start: model.viewing ?? 0).environmentObject(model)
        }
        .onChange(of: picks) { p in guard !p.isEmpty else { return }; Task { await model.picked(p); picks = [] } }
    }
    private var bottomBar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current, photoLibrary: .shared()) {
                Label("Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }.buttonStyle(DarkPill())
            Button { Task { await model.latestScreenshot() } } label: { Label("Screenshot", systemImage: "camera.viewfinder") }.buttonStyle(LightPill())
        }
        .padding(.horizontal, 18).padding(.bottom, 8).padding(.top, 40)
        .background(LinearGradient(colors: [Color.nvPaper.opacity(0), Color.nvPaper.opacity(0.98)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)).ignoresSafeArea())
    }
}

// MARK: - Browse: the project's vault, in rows

struct Browse: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.project.isEmpty ? "Needed Vault" : model.project).font(NVFont.raleway(34, 200)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    Cap(text: "\(model.count) in the vault")
                }
                HStack(spacing: 6) {
                    Button("All") { model.kind = nil }.buttonStyle(ChipStyle(on: model.kind == nil))
                    Button("Stills") { model.kind = .still }.buttonStyle(ChipStyle(on: model.kind == .still))
                    Button("Clips") { model.kind = .clip }.buttonStyle(ChipStyle(on: model.kind == .clip))
                    Button("GIFs") { model.kind = .gif }.buttonStyle(ChipStyle(on: model.kind == .gif))
                    Spacer()
                    Button { withAnimation { model.searching.toggle(); if !model.searching { model.query = "" } } } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                    }.buttonStyle(ChipStyle(on: model.searching)).accessibilityLabel("Search")
                }
                if model.searching {
                    TextField("Search — tags, names", text: $model.query)
                        .font(NVFont.raleway(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.vertical, 10).padding(.horizontal, 16)
                        .background(Capsule().fill(.white.opacity(0.85))).overlay(Capsule().stroke(Color.nvInk.opacity(0.12)))
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 12)

            let list = model.shown
            if list.isEmpty {
                Text(model.loading ? "Opening \(model.project)…" : model.items.isEmpty ? "Nothing here yet — Photos below adds some." : "Nothing matches.")
                    .font(NVFont.raleway(14)).foregroundColor(.nvSoft).padding(.top, 40)
            } else {
                Rows(items: list) { i in model.viewing = i }.padding(.horizontal, 14)
            }
            Color.clear.frame(height: 110)
        }
        .refreshable { await model.refresh() }
    }
}

/// Justified rows: every picture keeps its shape, each row fills the width.
struct Rows: View {
    let items: [VaultItem]
    let open: (Int) -> Void
    var body: some View {
        GeometryReader { g in
            let rows = Rows.rows(items, width: g.size.width)
            VStack(spacing: 5) {
                ForEach(rows.indices, id: \.self) { r in
                    let row = rows[r]
                    HStack(spacing: 5) {
                        ForEach(row.cells, id: \.index) { c in
                            Button { open(c.index) } label: {
                                Thumb(item: items[c.index])
                                    .frame(width: c.width, height: row.height)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(alignment: .bottomLeading) { badge(items[c.index]) }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(height: Rows.rows(items, width: UIScreen.main.bounds.width - 28).reduce(0) { $0 + $1.height + 5 })
    }
    @ViewBuilder func badge(_ it: VaultItem) -> some View {
        if it.kind != .still {
            Text(it.kind == .clip ? "CLIP" : "GIF").font(NVFont.mono(9.5)).tracking(1).foregroundColor(.white)
                .padding(.horizontal, 5).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.45))).padding(6)
        }
    }
    struct Cell { let index: Int; let width: CGFloat }
    struct Row { let cells: [Cell]; let height: CGFloat }
    static func rows(_ items: [VaultItem], width: CGFloat) -> [Row] {
        let target: CGFloat = 118, gap: CGFloat = 5
        var out: [Row] = [], cur: [(Int, CGFloat)] = [], sum: CGFloat = 0
        func close(_ last: Bool) {
            guard !cur.isEmpty else { return }
            let avail = width - gap * CGFloat(cur.count - 1)
            let h = last ? min(target * 1.3, avail / max(sum, 0.01)) : avail / max(sum, 0.01)
            out.append(Row(cells: cur.map { Cell(index: $0.0, width: $0.1 * h) }, height: h))
            cur = []; sum = 0
        }
        for (i, it) in items.enumerated() {
            let a = CGFloat(min(max(it.aspect, 0.4), 3))
            cur.append((i, a)); sum += a
            if sum * target + gap * CGFloat(cur.count - 1) >= width { close(false) }
        }
        close(true)
        return out
    }
}

// MARK: - Grab & Go on

struct OnScreen: View {
    @EnvironmentObject var model: AppModel
    @State private var picks: [PhotosPickerItem] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GRAB & GO IS ON").font(NVFont.oswald(12)).tracking(1.9)
                    Text("Everything goes straight into \(model.grabGo ?? ""). No questions until you switch it off.").font(NVFont.raleway(14)).lineSpacing(3)
                }
                .foregroundColor(.white).padding(.vertical, 14).padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.nvOrange).shadow(color: .nvOrange.opacity(0.3), radius: 15, y: 12))

                PhotosPicker(selection: $picks, maxSelectionCount: 30, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current, photoLibrary: .shared()) {
                    VStack(spacing: 10) {
                        Text("Tap to add").font(NVFont.raleway(26, 200)).foregroundColor(.nvInk)
                        Text("Pick from Photos — they go straight in").font(NVFont.raleway(13)).foregroundColor(.nvSoft).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).frame(height: 190)
                    .glass(22)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.nvOrange.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                }.buttonStyle(.plain)

                HStack {
                    Cap(text: "Today, \(model.today.reduce(0, { $0 + $1.count })) added")
                    Spacer()
                    if model.waiting > 0 {
                        Text("\(model.waiting) wait on this phone").font(NVFont.raleway(11.5)).foregroundColor(Color(hex: "#8a3a14"))
                            .padding(.vertical, 5).padding(.horizontal, 11).background(Capsule().fill(Color(hex: "#fff4ec"))).overlay(Capsule().stroke(Color.nvOrange.opacity(0.35)))
                    }
                    Button("Latest screenshot") { Task { await model.latestScreenshot() } }.buttonStyle(ChipStyle())
                }
                VStack(spacing: 0) {
                    ForEach(model.today) { e in
                        HStack(spacing: 12) {
                            Group {
                                if let d = e.thumb, let i = UIImage(data: d) { Image(uiImage: i).resizable().scaledToFill() } else { Color(hex: "#d9cfc4") }
                            }.frame(width: 48, height: 34).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(e.what) \(e.at.formatted(date: .omitted, time: .shortened))").font(NVFont.raleway(13.5))
                                Text("\(e.count) file\(e.count == 1 ? "" : "s")").font(NVFont.mono(10.5)).foregroundColor(.nvSoft)
                            }
                            Spacer()
                            Text(e.waiting ? "On this phone" : "In \(e.project)").font(NVFont.raleway(12)).foregroundColor(e.waiting ? Color(hex: "#8a6a58") : .nvGreen)
                        }
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.nvInk.opacity(0.07)).frame(height: 1) }
                    }
                    if model.today.isEmpty { Text("Nothing yet today.").font(NVFont.raleway(13)).foregroundColor(.nvSoft).padding(.vertical, 14) }
                }
                Text("“In \(model.grabGo ?? "the project")” means it's in the project's inbox. Your Mac files it into the vault next time it syncs.")
                    .font(NVFont.raleway(11.5)).foregroundColor(.nvSoft).lineSpacing(2)
            }
            .padding(.horizontal, 18).padding(.bottom, 40)
        }
        .refreshable { await model.refresh() }
        .onChange(of: picks) { p in guard !p.isEmpty else { return }; Task { await model.picked(p); picks = [] } }
    }
}

// MARK: - One picture, full screen

struct Viewer: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let start: Int
    @State private var at = 0
    var body: some View {
        let list = model.shown
        ZStack {
            Color(hex: "#0b0b0b").ignoresSafeArea()
            TabView(selection: $at) {
                ForEach(list.indices, id: \.self) { i in Page(item: list[i]).tag(i) }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            VStack {
                HStack {
                    Button { dismiss() } label: { Text("‹ \(model.project)") }
                        .font(NVFont.raleway(14)).foregroundColor(.white).padding(.vertical, 8).padding(.horizontal, 14)
                        .background(Capsule().fill(.white.opacity(0.12)))
                    Spacer()
                    Text("\(min(at + 1, list.count)) / \(list.count)").font(NVFont.mono(11)).tracking(1.5).foregroundColor(.white.opacity(0.55))
                }
                .padding(.horizontal, 18).padding(.top, 8)
                Spacer()
            }
        }
        .onAppear { at = start }
    }

    struct Page: View {
        let item: VaultItem
        @State private var image: UIImage?
        @State private var player: AVPlayer?
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 70)
                ZStack {
                    LinearGradient(colors: [Color(hex: item.palette.first ?? "#3b4a52"), Color(hex: item.palette.dropFirst().first ?? "#1b1b1d")], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(image == nil && player == nil ? 1 : 0)
                    if let p = player { VideoPlayer(player: p) }
                    else if let i = image { Playing(image: i) }
                }
                .frame(maxWidth: .infinity).frame(height: 360)
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.name).font(NVFont.raleway(22, 300)).foregroundColor(Color(hex: "#f4f3f1"))
                    Text(meta).font(NVFont.mono(11.5)).tracking(0.9).foregroundColor(.white.opacity(0.55))
                    if !item.palette.isEmpty {
                        HStack(spacing: 6) { ForEach(item.palette, id: \.self) { c in RoundedRectangle(cornerRadius: 7).fill(Color(hex: c)).frame(width: 26, height: 26).overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.15))) } }
                    }
                    if !item.tags.isEmpty {
                        HStack(spacing: 6) { ForEach(item.tags, id: \.self) { t in
                            Text("#\(t)").font(NVFont.raleway(12.5)).foregroundColor(.white).padding(.vertical, 5).padding(.horizontal, 11)
                                .background(Capsule().fill(.white.opacity(0.1))).overlay(Capsule().stroke(.white.opacity(0.2)))
                        } }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 22)
                Spacer()
                HStack(spacing: 8) {
                    if let l = item.link, let u = URL(string: l) {
                        Link(destination: u) { Text("Open the source ↗").frame(maxWidth: .infinity) }.buttonStyle(LightPill(dark: true))
                    }
                    ShareLink(item: item.url) { Text("Share").frame(maxWidth: item.link == nil ? .infinity : nil) }.buttonStyle(LightPill(dark: true))
                }
                .padding(.horizontal, 18)
                Text("Swipe for the next · cropping and boards stay on the Mac").font(NVFont.raleway(11)).foregroundColor(.white.opacity(0.4))
                    .frame(maxWidth: .infinity).padding(.top, 10).padding(.bottom, 6)
            }
            .task(id: item.id) {
                switch item.kind {
                case .clip: player = AVPlayer(url: item.url)
                case .gif: image = await Pictures.animated(item, max: 900)
                case .still: image = await Pictures.image(item, max: 2000)
                }
            }
            .onDisappear { player?.pause() }
        }
        private var meta: String {
            var bits = [item.kind.label]
            if let s = item.source, !s.isEmpty, s != "file", s != "phone" { bits.append(s.capitalized) }
            if let d = item.added { bits.append("added " + d.formatted(.dateTime.weekday(.abbreviated))) }
            if !item.downloaded { bits.append("in iCloud") }
            return bits.joined(separator: " · ")
        }
    }
}

// MARK: - Adding (Grab & Go off): which project, and tags

struct AddSheet: View {
    @EnvironmentObject var model: AppModel
    @State private var project = ""
    @State private var tags = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Cap(text: "Add to the vault").padding(.top, 22)
            Text(model.pending.count == 1 ? "One to file" : "\(model.pending.count) to file").font(NVFont.raleway(30, 200))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.pending.indices, id: \.self) { i in
                        Group {
                            if let cg = VaultFolder.thumbnail(model.pending[i].data, max: 200) { Image(uiImage: UIImage(cgImage: cg)).resizable().scaledToFill() }
                            else { ZStack { Color(hex: "#2b2b2b"); Image(systemName: "film").foregroundColor(.white.opacity(0.7)) } }
                        }.frame(width: 72, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Cap(text: "Into")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.projects) { p in
                        Button(p.name) { project = p.name }.buttonStyle(ChipStyle(on: project == p.name))
                    }
                }
            }
            TextField("Tags, if you like — night, car", text: $tags)
                .font(NVFont.raleway(16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.vertical, 12).padding(.horizontal, 16)
                .background(Capsule().fill(.white.opacity(0.9))).overlay(Capsule().stroke(Color.nvInk.opacity(0.12)))
            Button { model.add(model.pending, to: project, tags: tags.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)) } label: {
                Text("Add to \(project)")
            }.buttonStyle(DarkPill()).disabled(project.isEmpty)
            Spacer()
        }
        .padding(.horizontal, 20)
        .background(Glow())
        .onAppear { project = model.project }
    }
}

// MARK: - Once: choose the folder

struct Setup: View {
    @EnvironmentObject var model: AppModel
    @State private var picking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image("Mark").resizable().scaledToFit().frame(width: 56)
            Text("Needed Vault").font(NVFont.raleway(40, 200))
            Text("Your vault, on your phone. Screenshots, photos and clips go straight into the right project.")
                .font(NVFont.raleway(15)).foregroundColor(.nvSoft).lineSpacing(3)
            VStack(alignment: .leading, spacing: 10) {
                step("1", "On your Mac: Needed Tools › Home › Your phone › turn on Keep it in iCloud, then Sync.")
                step("2", "Here: choose the Needed Vault folder it made.")
            }
            .padding(16).glass(22)
            Button("Choose the Needed Vault folder") { picking = true }.buttonStyle(DarkPill())
            Text("It's in iCloud Drive › Shortcuts › Needed Vault.").font(NVFont.raleway(12.5)).foregroundColor(.nvSoft).frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(.horizontal, 22)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
            if case .success(let url) = r { model.folderChosen(url) }
        }
    }
    private func step(_ n: String, _ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(n).font(NVFont.mono(12)).foregroundColor(.nvOrangeInk)
            Text(t).font(NVFont.raleway(14)).foregroundColor(.nvInk).lineSpacing(2)
        }
    }
}

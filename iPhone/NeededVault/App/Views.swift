// Needed Mobile Vault for iPhone — the screens, in the approved design:
// the project on the left, the mark in the middle, ＋ on the right; Home, Projects and a
// project's own page; Grab & Go in the middle of the glass tab bar, with the orange lens
// sliding between Home and Projects.

import SwiftUI
import PhotosUI
import BackgroundTasks

@main
struct NeededVaultApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    static let refreshID = "com.thiswasneeded.neededvault.send"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.light)
                .onAppear { model.start() }
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await model.foreground() } }
            if p == .background { NeededVaultApp.scheduleRefresh() }
        }
        // Now and then, in the background: if the phone's on the Mac's Wi-Fi, what waited goes.
        .backgroundTask(.appRefresh(NeededVaultApp.refreshID)) {
            _ = await Sender.sendWaiting()
            NeededVaultApp.scheduleRefresh()
        }
    }

    static func scheduleRefresh() {
        guard Library.shared.mac != nil, Library.shared.all().contains(where: { !$0.sent }) else { return }
        let r = BGAppRefreshTaskRequest(identifier: refreshID)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

// MARK: - The frame

struct RootView: View {
    @EnvironmentObject var m: AppModel
    @State private var picks: [PhotosPickerItem] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            Glow()
            VStack(spacing: 0) {
                Header()
                Group {
                    switch m.tab {
                    case .grab: GrabGoView()
                    case .home: if let p = m.opened { ProjectPage(project: p) } else { HomeView() }
                    case .projects: if let p = m.opened { ProjectPage(project: p) } else { ProjectsView() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(spacing: 10) {
                if let t = m.toast { Toast(text: t).transition(.move(edge: .bottom).combined(with: .opacity)) }
                if m.grabGo != nil && m.tab != .grab { GGNote() }
                if m.tab != .grab { SendBar() }
                TabBar()
            }
            .padding(.bottom, 10)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: m.toast)
        }
        .sheet(isPresented: $m.projectSheet) { ProjectSheet().environmentObject(m).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $m.infoSheet) { InfoSheet().environmentObject(m).presentationDetents([.medium, .large]) }
        .sheet(isPresented: Binding(get: { !m.pending.isEmpty }, set: { if !$0 { m.pending = [] } })) { KeepSheet().environmentObject(m).presentationDetents([.large]) }
        .fullScreenCover(item: $m.viewing) { g in Viewer(start: g).environmentObject(m) }
        .fullScreenCover(isPresented: $m.pairing) { PairView().environmentObject(m) }
        .fullScreenCover(isPresented: $m.showCamera) {
            CameraPicker { p in m.showCamera = false; if let p { m.take([p]) } }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $m.showPhotos, selection: $picks, maxSelectionCount: 30, matching: .any(of: [.images, .videos]))
        .onChange(of: picks) { _, list in
            guard !list.isEmpty else { return }
            Task { let files = await AppModel.load(list); picks = []; m.take(files) }
        }
        .onChange(of: m.toast) { _, t in
            guard t != nil else { return }
            Task { try? await Task.sleep(nanoseconds: 2_800_000_000); if m.toast == t { m.toast = nil } }
        }
    }
}

struct Header: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        ZStack {
            HStack {
                Button { m.projectSheet = true } label: {
                    HStack(spacing: 5) {
                        Text(m.project.isEmpty ? "Projects" : m.project).font(NVFont.raleway(15)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.nvInk).frame(maxWidth: 130, alignment: .leading)
                }
                .accessibilityLabel("Project: \(m.project). Change")
                Spacer()
                Menu {
                    Button { m.showCamera = true } label: { Label("Camera", systemImage: "camera") }
                    Button { m.showPhotos = true } label: { Label("From Photos", systemImage: "photo.on.rectangle") }
                } label: {
                    Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundColor(.nvInk)
                        .frame(width: 36, height: 36).navGlass(Circle())
                }
                .accessibilityLabel("Add photos or clips")
            }
            Button { m.infoSheet = true } label: { Image("Mark").resizable().scaledToFit().frame(width: 36) }
                .accessibilityLabel("Needed Mobile Vault — how it works")
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 6)
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject var m: AppModel
    var hello: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(hello).font(NVFont.raleway(19, 300))
                    Spacer()
                    Cap(text: Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                }
                .padding(.horizontal, 12).padding(.bottom, 12)

                if let cover = m.grabs(of: m.project).first {
                    Hero(project: m.project, cover: cover)
                }
                if m.grabs.isEmpty {
                    Empty(text: m.project.isEmpty
                          ? "Pick a project up top — or make one — then add photos and clips."
                          : "Nothing here yet. Tap ＋ up top, or the orange button for Grab & Go. Everything stays on this phone and goes to your Mac when you're on its Wi-Fi.")
                }
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(Array(m.runs.enumerated()), id: \.offset) { _, run in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Cap(text: "\(run.project) · \(run.items.count)")
                                Spacer()
                                let w = run.items.filter { !$0.sent }.count
                                if w > 0 { Cap(text: "\(w) not sent", color: .nvOrangeInk) }
                            }
                            .padding(.horizontal, 12)
                            Shots(grabs: run.items)
                        }
                    }
                }
            }
            .padding(.bottom, 190)
        }
        .refreshable { await m.send() }
    }
}

struct Hero: View {
    @EnvironmentObject var m: AppModel
    let project: String
    let cover: Grab
    var body: some View {
        let mine = m.grabs(of: project), w = mine.filter { !$0.sent }.count
        Button { withAnimation(.easeOut(duration: 0.25)) { m.opened = project } } label: {
            ZStack(alignment: .bottomLeading) {
                Thumb(grab: cover)
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .bottom, endPoint: UnitPoint(x: 0.5, y: 0.55))
                VStack(alignment: .leading, spacing: 3) {
                    Text(project).font(NVFont.raleway(30, 300)).lineLimit(1)
                    Text("\(mine.count) grab\(mine.count == 1 ? "" : "s")\(w > 0 ? " · \(w) to send" : "")").font(NVFont.raleway(12.5)).opacity(0.88)
                }
                .foregroundColor(.white).padding(.leading, 16).padding(.bottom, 14).padding(.trailing, 60)
                HStack { Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(.white.opacity(0.18))).overlay(Circle().stroke(.white.opacity(0.45)))
                }
                .padding(16)
            }
            .frame(height: min(UIScreen.main.bounds.height * 0.62, 420))
            .clipped()
        }
        .buttonStyle(.plain)
        .padding(.bottom, 18)
    }
}

/// Grabs in justified rows of two (each at its own shape), a lone one full width.
struct Shots: View {
    @EnvironmentObject var m: AppModel
    let grabs: [Grab]
    var body: some View {
        GeometryReader { geo in
            let rows = Shots.rows(grabs)
            VStack(spacing: 3) {
                ForEach(rows.indices, id: \.self) { r in
                    let row = rows[r], width = geo.size.width
                    let a = row.map { clampAspect($0.aspect) }.reduce(0, +)
                    let h = (width - CGFloat(row.count - 1) * 3) / CGFloat(a)
                    HStack(spacing: 3) {
                        ForEach(row) { g in
                            Shot(grab: g).frame(width: h * CGFloat(clampAspect(g.aspect)), height: h)
                        }
                    }
                }
            }
        }
        .frame(height: Shots.height(grabs, width: UIScreen.main.bounds.width))
    }
    static func rows(_ list: [Grab]) -> [[Grab]] { stride(from: 0, to: list.count, by: 2).map { Array(list[$0..<min($0 + 2, list.count)]) } }
    static func height(_ list: [Grab], width: CGFloat) -> CGFloat {
        let rows = rows(list)
        return rows.reduce(0) { sum, row in
            let a = row.map { clampAspect($0.aspect) }.reduce(0, +)
            return sum + (width - CGFloat(row.count - 1) * 3) / CGFloat(a)
        } + CGFloat(max(rows.count - 1, 0)) * 3
    }
}
func clampAspect(_ a: Double) -> Double { min(max(a, 0.56), 1.9) }

struct Shot: View {
    @EnvironmentObject var m: AppModel
    let grab: Grab
    var body: some View {
        Button { m.viewing = grab } label: {
            ZStack {
                Thumb(grab: grab)
                if !grab.sent {
                    Circle().fill(Color.nvOrange).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(.white.opacity(0.92), lineWidth: 2.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(9)
                        .accessibilityLabel("Not sent yet")
                }
                if grab.kind != .still {
                    Group {
                        if grab.kind == .gif { Text("GIF").font(NVFont.mono(10)).tracking(1).padding(.horizontal, 8) }
                        else { Image(systemName: "play.fill").font(.system(size: 10)).frame(width: 26) }
                    }
                    .foregroundColor(.nvInk).frame(height: 26).background(Capsule().fill(.white.opacity(0.86)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(9)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.scaleEffect(configuration.isPressed ? 0.985 : 1) }
}

struct Empty: View {
    let text: String
    var body: some View {
        Text(text).font(NVFont.raleway(14)).foregroundColor(.nvSoft).multilineTextAlignment(.center).lineSpacing(3)
            .frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 24)
    }
}

// MARK: - Projects

struct ProjectsView: View {
    @EnvironmentObject var m: AppModel
    let cols = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Projects").font(NVFont.raleway(26, 200))
                    Spacer()
                    PairLine()
                }
                .padding(.horizontal, 12)
                if m.names.isEmpty {
                    Empty(text: m.mac == nil ? "Pair with your Mac and your projects come across." : "No projects yet — make one on your Mac, or with the project button up top.")
                }
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(m.names, id: \.self) { p in ProjectCover(project: p) }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 190)
        }
        .refreshable { await m.send() }
    }
}

struct PairLine: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        if m.mac == nil {
            Button("Pair with your Mac") { m.pairing = true }.font(NVFont.raleway(13)).foregroundColor(.nvOrangeInk)
        } else {
            HStack(spacing: 6) {
                Circle().fill(m.reachable == true ? Color.nvGreen : Color.nvSoft.opacity(0.5)).frame(width: 7, height: 7)
                Text(m.reachable == true ? m.macName : "\(m.macName) · not on this Wi-Fi").font(NVFont.raleway(12.5)).foregroundColor(.nvSoft).lineLimit(1)
                Button(m.sending ? "…" : "Refresh") { Task { await m.send() } }.font(NVFont.raleway(12.5)).foregroundColor(.nvOrangeInk).disabled(m.sending)
            }
        }
    }
}

struct ProjectCover: View {
    @EnvironmentObject var m: AppModel
    let project: String
    var body: some View {
        let mine = m.grabs(of: project), mac = m.macCount(project)
        Button {
            m.choose(project)
            withAnimation(.easeOut(duration: 0.25)) { m.opened = project }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Color.clear
                .aspectRatio(0.8, contentMode: .fit)
                .overlay {
                    if let c = mine.first { Thumb(grab: c) }
                    else {
                        LinearGradient(colors: [Color(hex: "#efe4db"), Color(hex: "#e2d2c4")], startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(Image("Mark").resizable().scaledToFit().frame(width: 30).opacity(0.25))
                    }
                }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if project == m.project { Circle().fill(Color.nvOrange).frame(width: 9, height: 9).overlay(Circle().stroke(.white, lineWidth: 2.5)).padding(9) }
                }
                Text(project).font(NVFont.raleway(15)).foregroundColor(.nvInk).lineLimit(1).padding(.horizontal, 2)
                Cap(text: [mine.isEmpty ? nil : "\(mine.count) here", mac > 0 ? "\(mac) on Mac" : nil].compactMap { $0 }.joined(separator: " · ").ifEmpty("Empty"))
                    .padding(.horizontal, 2)
            }
        }
        .buttonStyle(PressStyle())
    }
}
extension String { func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }

struct ProjectPage: View {
    @EnvironmentObject var m: AppModel
    let project: String
    var body: some View {
        let shown = m.shown(project), all = m.grabs(of: project)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Button { withAnimation(.easeOut(duration: 0.25)) { m.opened = nil; m.kind = nil } } label: {
                        Text("‹ Projects").font(NVFont.raleway(13.5)).foregroundColor(.nvOrangeInk)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(project).font(NVFont.raleway(30, 300)).lineLimit(1)
                        Spacer()
                        Cap(text: "\(all.count) here\(m.macCount(project) > 0 ? " · \(m.macCount(project)) on Mac" : "")")
                    }
                }
                .padding(.horizontal, 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button("All") { m.kind = nil }.buttonStyle(ChipStyle(on: m.kind == nil))
                        ForEach(GrabKind.allCases, id: \.self) { k in
                            Button(k.plural) { m.kind = k }.buttonStyle(ChipStyle(on: m.kind == k))
                        }
                    }
                    .padding(.horizontal, 12)
                }
                if shown.isEmpty {
                    Empty(text: all.isEmpty ? "Nothing from this phone in \(project) yet. Tap ＋, or Grab & Go." : "None of those here.")
                } else {
                    Shots(grabs: shown)
                }
            }
            .padding(.bottom, 190)
        }
    }
}

// MARK: - Grab & Go

struct GrabGoView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        let p = m.grabGo ?? m.project
        let recent = m.grabs(of: p).filter { Calendar.current.isDateInToday($0.added) }
        VStack(alignment: .leading, spacing: 0) {
            Cap(text: "Grab & Go · straight into")
            Text(p).font(NVFont.raleway(44, 200)).lineLimit(1).minimumScaleFactor(0.6).padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(m.names, id: \.self) { n in
                        Button(n) { m.choose(n) }.buttonStyle(ChipStyle(on: n == p))
                    }
                }
            }
            .padding(.top, 10)
            Spacer(minLength: 20)
            VStack(spacing: 18) {
                Button { m.showCamera = true } label: {
                    Image(systemName: "camera").font(.system(size: 44, weight: .light)).foregroundColor(.white)
                        .frame(width: 168, height: 168)
                        .background(Circle().fill(Color.nvOrange))
                        .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 8).padding(4))
                        .shadow(color: Color.nvOrange.opacity(0.38), radius: 25, y: 22)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Camera")
                Button("From Photos") { m.showPhotos = true }.buttonStyle(LightPill())
                Text("Straight in — no questions. Tap the orange button again to stop.")
                    .font(NVFont.raleway(12.5)).foregroundColor(.nvSoft).multilineTextAlignment(.center).frame(maxWidth: 260)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 20)
            if !recent.isEmpty {
                HStack {
                    Cap(text: "Just now")
                    Spacer()
                    let w = recent.filter { !$0.sent }.count
                    Cap(text: w > 0 ? "\(w) to send" : "all on \(m.macName)", color: w > 0 ? .nvOrangeInk : .nvGreen)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(recent.prefix(20)) { g in
                            Button { m.viewing = g } label: { Thumb(grab: g).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 6)) }
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 110)
    }
}

// MARK: - The bars along the bottom

struct TabBar: View {
    @EnvironmentObject var m: AppModel
    @State private var squish = false
    var body: some View {
        let lensX: CGFloat = m.tab == .projects ? 203 : 5
        ZStack(alignment: .topLeading) {
            Capsule().fill(Color.nvOrange)
                .frame(width: 94, height: 54)
                .scaleEffect(x: squish ? 1.12 : 1, y: squish ? 0.92 : 1)
                .offset(x: lensX, y: 5)
                .opacity(m.tab == .grab ? 0 : 1)
                .shadow(color: Color(red: 0.63, green: 0.2, blue: 0.04).opacity(0.22), radius: 2, y: 1)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                tab(.home, "Home", "house")
                Spacer(minLength: 0)
                Button { m.tapGrabGo() } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "camera").font(.system(size: 19, weight: .medium))
                        Text("GRAB").font(NVFont.oswald(7.5)).tracking(0.9)
                    }
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.nvOrange))
                    .overlay(Circle().stroke(.white, lineWidth: 3).padding(-3).opacity(m.grabGo != nil ? 1 : 0))
                    .overlay(Circle().stroke(Color.nvOrange.opacity(0.55), lineWidth: 3).padding(-6).opacity(m.grabGo != nil ? 1 : 0))
                    .shadow(color: Color.nvOrange.opacity(0.4), radius: 10, y: 8)
                }
                .buttonStyle(PressStyle())
                .offset(y: -1)
                .accessibilityLabel("Grab and Go").accessibilityValue(m.grabGo != nil ? "On" : "Off")
                Spacer(minLength: 0)
                tab(.projects, "Projects", "square.grid.2x2")
            }
            .padding(.horizontal, 4)
            .frame(width: 304, height: 64)
        }
        .frame(width: 304, height: 64)
        .navGlass(Capsule())
    }

    func tab(_ t: Tab, _ label: String, _ icon: String) -> some View {
        Button {
            guard m.tab != t || m.opened != nil else { return }
            squish = true
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.55)) { m.tab = t; m.opened = nil; m.kind = nil }
            withAnimation(.easeOut(duration: 0.28).delay(0.12)) { squish = false }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 19, weight: .regular))
                Text(label).font(NVFont.raleway(10.5, 500))
            }
            .foregroundColor(m.tab == t ? .white : .nvOrange)
            .frame(width: 96, height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(m.tab == t ? .isSelected : [])
    }
}

struct SendBar: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        let n = m.waiting.count
        if m.mac == nil && !m.grabs.isEmpty {
            bar(title: "\(m.grabs.count) on this phone", sub: "Pair with your Mac to send them") {
                Button("Pair") { m.pairing = true }.buttonStyle(OrangePill())
            }
        } else if n > 0 {
            bar(title: m.sending ? "Sending \(min(m.sendProgress.0 + 1, max(m.sendProgress.1, 1))) of \(max(m.sendProgress.1, 1))" : "\(n) to send",
                sub: m.reachable == false ? "Goes to \(m.macName) when you're on its Wi-Fi" : "to \(m.macName)") {
                Button(m.sending ? "Sending…" : "Send to Mac") { Task { await m.send() } }.buttonStyle(OrangePill()).disabled(m.sending)
            }
        }
    }
    func bar<B: View>(title: String, sub: String, @ViewBuilder button: () -> B) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NVFont.raleway(14.5, 500))
                Text(sub).font(NVFont.raleway(12)).foregroundColor(.nvSoft).lineLimit(1)
            }
            Spacer(minLength: 0)
            button()
        }
        .padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 10)
        .navGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 14)
    }
}

struct GGNote: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { m.tab = .grab; m.opened = nil } } label: {
            HStack(spacing: 7) {
                Circle().fill(Color.nvOrange).frame(width: 7, height: 7)
                (Text("Grab & Go on — every photo goes to ") + Text(m.grabGo ?? "").fontWeight(.semibold))
                    .font(NVFont.raleway(12.5)).foregroundColor(.nvInk).lineLimit(1)
            }
            .padding(.vertical, 8).padding(.horizontal, 14)
            .navGlass(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text).font(NVFont.raleway(13.5)).foregroundColor(.nvInk).multilineTextAlignment(.center)
            .padding(.vertical, 10).padding(.horizontal, 16)
            .navGlass(Capsule())
            .padding(.horizontal, 20)
    }
}

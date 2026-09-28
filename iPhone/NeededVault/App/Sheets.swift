// Needed Mobile Vault for iPhone — the sheets: pick a project, keep what you picked,
// one picture full screen, pairing with your Mac, and how it works.

import SwiftUI

// MARK: - Pick a project

struct ProjectSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var new = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Cap(text: "Your projects")
                Text(m.grabGo != nil ? "Grab & Go goes into…" : "Pick a project").font(NVFont.raleway(26, 200))
                VStack(spacing: 0) {
                    ForEach(m.names, id: \.self) { p in
                        Button { m.choose(p); dismiss() } label: {
                            HStack {
                                Text(p).font(NVFont.raleway(16, p == m.project ? 500 : 400)).foregroundColor(p == m.project ? .nvOrangeInk : .nvInk)
                                Spacer()
                                let here = m.grabs(of: p).count, mac = m.macCount(p)
                                Text([here > 0 ? "\(here) here" : nil, mac > 0 ? "\(mac) on Mac" : nil].compactMap { $0 }.joined(separator: " · "))
                                    .font(NVFont.mono(11)).foregroundColor(.nvSoft)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.5)
                    }
                }
                HStack(spacing: 8) {
                    TextField("A new project", text: $new).font(NVFont.raleway(16)).textInputAutocapitalization(.words)
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .background(Capsule().fill(.white.opacity(0.9))).overlay(Capsule().stroke(Color.nvInk.opacity(0.12)))
                        .onSubmit { make() }
                    Button("Make it") { make() }.buttonStyle(OrangePill()).disabled(new.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Named the same as on your Mac, it goes straight into that project there.")
                    .font(NVFont.raleway(12.5)).foregroundColor(.nvSoft).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
            .padding(22)
        }
        .background(Glow())
    }
    func make() { m.make(new); new = ""; dismiss() }
}

// MARK: - Keep for a project

struct KeepSheet: View {
    @EnvironmentObject var m: AppModel
    @State private var project = ""
    @State private var new = ""
    @State private var tags = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Cap(text: "Keep for a project")
                Text(m.pending.count == 1 ? "To keep" : "\(m.pending.count) to keep").font(NVFont.raleway(26, 200))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(m.pending) { p in
                            ZStack {
                                Color(hex: "#efe4db")
                                if let i = p.preview { Image(uiImage: i).resizable().scaledToFill() }
                                else { Image(systemName: p.file != nil ? "play.fill" : "photo").foregroundColor(.nvSoft) }
                            }
                            .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Cap(text: "For")
                FlowChips(items: m.names, on: project) { project = $0 }
                TextField("+ A new project", text: $new).font(NVFont.raleway(16)).textInputAutocapitalization(.words)
                    .padding(.vertical, 12).padding(.horizontal, 16)
                    .background(Capsule().fill(.white.opacity(0.9))).overlay(Capsule().stroke(Color.nvInk.opacity(0.12)))
                Cap(text: "Tags")
                TextField("Tags, if you like — night, car", text: $tags).font(NVFont.raleway(16))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.vertical, 12).padding(.horizontal, 16)
                    .background(Capsule().fill(.white.opacity(0.9))).overlay(Capsule().stroke(Color.nvInk.opacity(0.12)))
                HStack(spacing: 10) {
                    Button("Keep") {
                        let target = new.trimmingCharacters(in: .whitespaces).isEmpty ? project : new.trimmingCharacters(in: .whitespaces)
                        if !new.trimmingCharacters(in: .whitespaces).isEmpty { m.make(target) }
                        let t = tags.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
                        m.keep(m.pending, in: target, tags: t)
                    }
                    .buttonStyle(DarkPill())
                    .disabled(project.isEmpty && new.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { m.pending = [] }.buttonStyle(LightPill())
                }
                .padding(.top, 6)
                Text(m.mac == nil ? "It stays on this phone until you pair with your Mac." : "It stays on this phone, and goes to \(m.macName) whenever you're on its Wi-Fi.")
                    .font(NVFont.raleway(12.5)).foregroundColor(.nvSoft)
            }
            .padding(22)
        }
        .background(Glow())
        .onAppear { if project.isEmpty { project = m.project } }
    }
}

/// Project chips that wrap onto more lines.
struct FlowChips: View {
    let items: [String]
    let on: String
    let pick: (String) -> Void
    var body: some View {
        Flow(spacing: 6) {
            ForEach(items, id: \.self) { p in Button(p) { pick(p) }.buttonStyle(ChipStyle(on: p == on)) }
        }
    }
}
struct Flow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > 0 && x + d.width > w { x = 0; y += row + spacing; row = 0 }
            x += d.width + spacing; row = max(row, d.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > b.minX && x + d.width > b.maxX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
            x += d.width + spacing; row = max(row, d.height)
        }
    }
}

// MARK: - One picture, full screen (swipe for the next in its project)

struct Viewer: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss
    let start: Grab
    @State private var current: String = ""
    @State private var moving = false
    @State private var deleting = false

    var body: some View {
        let list = m.grabs(of: start.project).isEmpty ? [start] : m.grabs(of: start.project)
        let g = list.first { $0.id == current } ?? start
        let i = (list.firstIndex { $0.id == g.id } ?? 0) + 1
        ZStack {
            Color(hex: "#fbf6f2").ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(list) { item in Big(grab: item).tag(item.id) }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundColor(.nvInk)
                            .frame(width: 36, height: 36).navGlass(Circle())
                    }
                    .accessibilityLabel("Back")
                    Spacer()
                    Text("\(i) / \(list.count)").font(NVFont.mono(11)).tracking(1.5).foregroundColor(.nvSoft)
                }
                .padding(.horizontal, 14)
                Spacer()
                VStack(spacing: 14) {
                    Text(meta(g)).font(NVFont.mono(11)).tracking(0.6).foregroundColor(g.sent ? .nvSoft : .nvOrangeInk).multilineTextAlignment(.center)
                    HStack(spacing: 34) {
                        ShareLink(item: Library.shared.fileURL(g)) { act("Share", "square.and.arrow.up") }
                        Button { moving = true } label: { act("Move", "folder") }
                        Button { deleting = true } label: { act("Delete", "trash") }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 14).padding(.horizontal, 24)
                .navGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.bottom, 8)
            }
        }
        .onAppear { if current.isEmpty { current = start.id } }
        .confirmationDialog("Move to", isPresented: $moving, titleVisibility: .visible) {
            ForEach(m.names.filter { $0 != g.project }, id: \.self) { p in Button(p) { m.move(g, to: p) } }
        } message: {
            Text(g.sent ? "It's already on \(m.macName) in \(g.project) — this moves it on this phone." : "Before it's sent, it goes to the new project.")
        }
        .confirmationDialog("Delete from this phone?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { m.delete(g); dismiss() }
        } message: {
            Text(g.sent ? "\(m.macName) keeps its copy." : "It hasn't gone to your Mac yet — it'll be gone for good.")
        }
    }

    func meta(_ g: Grab) -> String {
        let d = g.added.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        let tags = g.tags.isEmpty ? "" : "  ·  " + g.tags.map { "#" + $0 }.joined(separator: " ")
        return "\(g.project.uppercased()) · \(d.uppercased())\(tags)\n" + (g.sent ? "ON \(m.macName.uppercased())" : "NOT SENT YET — GOES ON YOUR WI-FI")
    }
    func act(_ label: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 17)).foregroundColor(.nvInk).frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.8))).overlay(Circle().stroke(Color.nvInk.opacity(0.1)))
            Text(label).font(NVFont.raleway(11.5)).foregroundColor(.nvSoft)
        }
    }
}

struct Big: View {
    let grab: Grab
    @State private var img: UIImage?
    var body: some View {
        Group {
            if grab.kind == .clip {
                ClipPlayer(url: Library.shared.fileURL(grab))
            } else if let i = img {
                Playing(image: i)
            } else {
                ProgressView()
            }
        }
        .padding(.top, 60).padding(.bottom, 150)
        .task(id: grab.id) { img = await Pictures.full(grab) }
    }
}

// MARK: - Pair with your Mac

struct PairView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Looking for the code…"
    @State private var done = false
    @State private var working = false
    @State private var typing = false
    @State private var typed = ""

    var body: some View {
        ZStack {
            Glow()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundColor(.nvInk)
                            .frame(width: 36, height: 36).navGlass(Circle())
                    }
                    .accessibilityLabel(done ? "Done" : "Not now")
                }
                if done { paired } else { scanning }
            }
            .padding(.horizontal, 22).padding(.top, 8)
        }
        .alert("Paste the link", isPresented: $typing) {
            TextField("http://…:7788/capture/#k=…", text: $typed).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Pair") { Task { await use(typed) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("On your Mac: Needed Tools › Home › Your phone — the address under the code.")
        }
    }

    var scanning: some View {
        VStack(alignment: .leading, spacing: 14) {
            Cap(text: "Pair with your Mac")
            Text("Point at the code on your Mac").font(NVFont.raleway(28, 200))
            Text("Needed Tools › Home › Your phone. Once is enough — after that, whatever you grab goes to your Mac by itself whenever you're on its Wi-Fi. Nothing goes anywhere else.")
                .font(NVFont.raleway(14)).foregroundColor(.nvSoft).lineSpacing(3)
            ZStack(alignment: .bottom) {
                CodeReader { s in Task { await use(s) } }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Text(working ? "Reaching your Mac…" : status).font(NVFont.raleway(13)).foregroundColor(.white)
                    .padding(.vertical, 7).padding(.horizontal, 12).background(Capsule().fill(.black.opacity(0.45))).padding(12)
            }
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.8), lineWidth: 1))
            Button("Paste the link instead") { typing = true }.buttonStyle(LightPill())
            Spacer()
        }
    }

    var paired: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark").font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                .frame(width: 44, height: 44).background(Circle().fill(Color.nvOrange))
            Text("Paired with \(m.macName)").font(NVFont.raleway(28, 200))
            Cap(text: m.reachable == true ? "\(m.projects.count) projects came across" : "Not on its Wi-Fi right now — that's fine")
            ScrollView {
                FlowChips(items: m.projects.map(\.name), on: m.project) { m.choose($0) }
            }
            .frame(maxHeight: 220)
            Text("New projects on your Mac come across by themselves whenever this opens. Grab anywhere — no signal needed — and it's sent when you're home.")
                .font(NVFont.raleway(14)).foregroundColor(.nvSoft).lineSpacing(3)
            Button("Start grabbing") { dismiss() }.buttonStyle(DarkPill())
            Spacer()
        }
    }

    @MainActor func use(_ text: String) async {
        guard !working else { return }
        working = true
        let problem = await m.paired(with: text)
        working = false
        if let p = problem { status = p } else { withAnimation(.easeOut(duration: 0.3)) { done = true } }
    }
}

// MARK: - How it works (tap the mark)

struct InfoSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Cap(text: "Needed Mobile Vault")
                Text("How it works").font(NVFont.raleway(26, 200))
                line("1", "Grab anywhere", "Camera, Photos, the Share Sheet, or Grab & Go. It's kept on this phone — no signal needed.")
                line("2", "Home on your Wi-Fi", "It goes straight to \(m.macName) by itself, into the same project, with its tags. An orange dot means not sent yet.")
                line("3", "Nothing is lost", "Each one counts as sent only when your Mac says it saved it — and it stays on this phone too.")
                Divider().padding(.vertical, 4)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.mac == nil ? "Not paired" : m.macName).font(NVFont.raleway(16, 500))
                        Text(m.mac == nil ? "Pair to send to your Mac" : m.reachable == true ? "On this Wi-Fi" : "Not on this Wi-Fi right now")
                            .font(NVFont.raleway(12.5)).foregroundColor(.nvSoft)
                        if let d = Library.shared.lastSent { Text("Last sent \(d.formatted(.relative(presentation: .named)))").font(NVFont.raleway(12.5)).foregroundColor(.nvSoft) }
                    }
                    Spacer()
                    Button(m.mac == nil ? "Pair" : "Scan again") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { m.pairing = true } }
                        .buttonStyle(OrangePill())
                }
                if m.mac != nil {
                    Button("Forget this Mac") { m.unpair() }.font(NVFont.raleway(13)).foregroundColor(.nvSoft)
                }
                Text("Side button: Settings › Action Button › Shortcut › Needed Vault › Grab & Go. Or Back Tap: Settings › Accessibility › Touch › Back Tap.")
                    .font(NVFont.raleway(12.5)).foregroundColor(.nvSoft).lineSpacing(2).padding(.top, 6)
            }
            .padding(22)
        }
        .background(Glow())
    }
    func line(_ n: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(NVFont.oswald(14)).foregroundColor(.white).frame(width: 30, height: 30).background(Circle().fill(Color.nvOrange))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NVFont.raleway(15, 500))
                Text(text).font(NVFont.raleway(13)).foregroundColor(.nvSoft).lineSpacing(2)
            }
        }
    }
}

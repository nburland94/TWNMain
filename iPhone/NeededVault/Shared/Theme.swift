// Needed Vault for iPhone — the look: the apricot glow, glass, one orange.
// The same type as Needed Tools on the Mac: Raleway, Oswald for small labels, Courier Prime for caps.

import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let n = UInt64(s, radix: 16) ?? 0xf4f1ec
        self.init(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
    static let nvOrange = Color(hex: "#F05A22")
    static let nvOrangeInk = Color(hex: "#d2440f")
    static let nvInk = Color(hex: "#141414")
    static let nvSoft = Color(hex: "#6b6964")
    static let nvPaper = Color(hex: "#fcf2ec")
    static let nvCap = Color(hex: "#7a5a48")
    static let nvGreen = Color(hex: "#2f7d4a")
}

enum NVFont {
    static func raleway(_ size: CGFloat, _ weight: Int = 400) -> Font {
        let name: String
        switch weight {
        case ..<250: name = "RalewayThin-ExtraLight"
        case ..<350: name = "RalewayThin-Light"
        case ..<450: name = "RalewayThin-Regular"
        default: name = "RalewayThin-Medium"
        }
        return .custom(name, size: size)
    }
    static func oswald(_ size: CGFloat) -> Font { .custom("Oswald-Regular", size: size) }
    static func mono(_ size: CGFloat) -> Font { .custom("CourierPrime-Regular", size: size) }
}

/// The apricot glow behind everything.
struct Glow: View {
    var body: some View {
        ZStack {
            Color.nvPaper
            RadialGradient(colors: [Color(hex: "#f7bf99"), Color(hex: "#f9cfb1"), Color(hex: "#fbdfca"), Color(hex: "#fcebdf"), Color(hex: "#fdf5ef")],
                           center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 560)
                .opacity(0.75)
        }
        .ignoresSafeArea()
    }
}

/// Small spaced capitals: "142 IN THE VAULT".
struct Cap: View {
    let text: String
    var color: Color = .nvCap
    var body: some View {
        Text(text.uppercased()).font(NVFont.mono(10.5)).tracking(1.9).foregroundColor(color)
    }
}

/// Frosted glass, as on the Mac.
struct GlassBackground: ViewModifier {
    var radius: CGFloat = 22
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.74), .white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.9), lineWidth: 1))
                    .shadow(color: Color(red: 0.63, green: 0.27, blue: 0.08).opacity(0.1), radius: 20, y: 14)
            )
    }
}
extension View {
    func glass(_ radius: CGFloat = 22) -> some View { modifier(GlassBackground(radius: radius)) }
}

struct DarkPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NVFont.raleway(15, 500)).foregroundColor(.white)
            .padding(.vertical, 14).padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#2b2b2b"), Color(hex: "#111111")], startPoint: .top, endPoint: .bottom)))
            .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
struct LightPill: ButtonStyle {
    var dark = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NVFont.raleway(14.5)).foregroundColor(dark ? .white : .nvInk)
            .padding(.vertical, 13).padding(.horizontal, 18)
            .background(Capsule().fill(dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8)))
            .overlay(Capsule().stroke(dark ? Color.white.opacity(0.2) : Color.nvInk.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
struct ChipStyle: ButtonStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NVFont.raleway(12.5)).foregroundColor(on ? .white : .nvInk)
            .padding(.vertical, 6).padding(.horizontal, 11)
            .background(Capsule().fill(on ? Color.nvInk : Color.white.opacity(0.75)))
            .overlay(Capsule().stroke(on ? Color.nvInk : Color.nvInk.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// The orange switch.
struct NVSwitch: View {
    let on: Bool
    let tap: () -> Void
    var body: some View {
        Button(action: tap) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Color.nvOrange : Color.nvInk.opacity(0.18)).frame(width: 44, height: 26)
                Circle().fill(.white).frame(width: 20, height: 20).shadow(color: .black.opacity(0.2), radius: 1.5, y: 1).padding(3)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: on)
        .accessibilityLabel("Grab & Go").accessibilityValue(on ? "On" : "Off")
    }
}

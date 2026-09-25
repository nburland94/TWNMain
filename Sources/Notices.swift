// Needed Tools — notices inside the window (Round 21).
// Whenever something's done — a sync, a grab, an invoice sent, things in from your
// phone — a small glass card rises in the bottom-left corner of the window, whatever
// page you're on. It goes by itself after a few seconds; click it to send it away
// sooner. While you're in another app, macOS shows its usual banner instead.

import AppKit

final class Notices {
    static let shared = Notices()
    private weak var host: NSView?
    private var cards: [NoticeCard] = []
    private let width: CGFloat = 330
    private let margin: CGFloat = 18

    func attach(to view: NSView) { host = view }

    func show(_ title: String, _ body: String) {
        guard let host = host else { return }
        let dark = Shell.theme == "dark"
        let card = NoticeCard(title: title, body: body, width: width, dark: dark)
        card.onClose = { [weak self, weak card] in if let c = card { self?.dismiss(c) } }
        card.frame.origin = NSPoint(x: margin, y: margin - 12)
        card.alphaValue = 0
        card.autoresizingMask = [.maxXMargin, .maxYMargin]
        host.addSubview(card, positioned: .above, relativeTo: nil)
        cards.insert(card, at: 0)
        while cards.count > 4 { dismiss(cards.last!) }
        layout(animated: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            card.animator().alphaValue = 1
        }
        let life = max(5.0, min(10.0, Double(title.count + body.count) * 0.07))
        DispatchQueue.main.asyncAfter(deadline: .now() + life) { [weak self, weak card] in
            guard let self = self, let card = card else { return }
            if card.hovering { return self.later(card) }
            self.dismiss(card)
        }
    }

    private func later(_ card: NoticeCard) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak card] in
            guard let self = self, let card = card else { return }
            if card.hovering { return self.later(card) }
            self.dismiss(card)
        }
    }

    private func dismiss(_ card: NoticeCard) {
        guard let i = cards.firstIndex(where: { $0 === card }) else { return }
        cards.remove(at: i)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            card.animator().alphaValue = 0
        }, completionHandler: { card.removeFromSuperview() })
        layout(animated: true)
    }

    /// Newest at the bottom, the older ones stacked above it.
    private func layout(animated: Bool) {
        var y = margin
        for c in cards {
            let target = NSPoint(x: margin, y: y)
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                    c.animator().setFrameOrigin(target)
                }
            } else { c.setFrameOrigin(target) }
            y += c.frame.height + 8
        }
    }
}

final class NoticeCard: NSVisualEffectView {
    var onClose: (() -> Void)?
    private(set) var hovering = false

    init(title: String, body: String, width: CGFloat, dark: Bool) {
        let pad: CGFloat = 14, dotW: CGFloat = 16
        let textW = width - pad * 2 - dotW
        let ink = dark ? NSColor(white: 0.96, alpha: 1) : NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        let soft = dark ? NSColor(white: 0.75, alpha: 1) : NSColor(calibratedRed: 0.42, green: 0.35, blue: 0.3, alpha: 1)
        let t = NoticeCard.label(title, size: 13.5, weight: .medium, colour: ink, width: textW)
        let b = NoticeCard.label(body, size: 12.5, weight: .regular, colour: soft, width: textW)
        let bodyH = body.isEmpty ? 0 : b.frame.height + 3
        let h = pad * 2 + t.frame.height + bodyH
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: h))
        material = .popover
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 1, alpha: 0.9)).cgColor

        let dot = NSView(frame: NSRect(x: pad, y: h - pad - 12, width: 7, height: 7))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = NSColor(calibratedRed: 0.94, green: 0.35, blue: 0.13, alpha: 1).cgColor
        addSubview(dot)
        t.frame.origin = NSPoint(x: pad + dotW, y: h - pad - t.frame.height)
        addSubview(t)
        if !body.isEmpty {
            b.frame.origin = NSPoint(x: pad + dotW, y: pad)
            addSubview(b)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
        toolTip = "Click to close"
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func label(_ s: String, size: CGFloat, weight: NSFont.Weight, colour: NSColor, width: CGFloat) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: s)
        f.font = NSFont.systemFont(ofSize: size, weight: weight)
        f.textColor = colour
        f.maximumNumberOfLines = 4
        f.lineBreakMode = .byTruncatingTail
        f.preferredMaxLayoutWidth = width
        let fit = f.sizeThatFits(NSSize(width: width, height: 400))
        f.frame = NSRect(x: 0, y: 0, width: width, height: ceil(fit.height))
        return f
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onClose?() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil                 // the card takes the click, not its labels
    }
}

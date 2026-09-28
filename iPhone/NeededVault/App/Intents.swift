// Needed Mobile Vault for iPhone — the side button, Back Tap and Siri. These show up in the
// Shortcuts app by themselves; Settings › Action Button › Shortcut › "Grab & Go" — done.

import AppIntents

struct GrabAndGoIntent: AppIntent {
    static var title: LocalizedStringResource = "Grab & Go"
    static var description = IntentDescription("Opens Needed Mobile Vault with Grab & Go on — into the project you last used.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let lib = Library.shared
        if lib.grabGo == nil, let p = lib.lastProject, !p.isEmpty { lib.grabGo = p }
        return .result()
    }
}

struct SaveScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Save my latest screenshot"
    static var description = IntentDescription("Keeps your latest screenshot for the Grab & Go project, or the one you last used — and sends it to your Mac if you're on its Wi-Fi.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let lib = Library.shared
        guard let p = lib.grabGo ?? lib.lastProject, !p.isEmpty else { return .result(dialog: "Open Needed Mobile Vault and pick a project first") }
        guard let f = await AppModel.latestScreenshot(), let d = f.data else { return .result(dialog: "No screenshot — or Photos access is off") }
        guard lib.add(data: d, name: f.name, project: p, tags: []) != nil else { return .result(dialog: "Couldn't keep that screenshot") }
        let r = await Sender.sendWaiting()
        return .result(dialog: r.sent > 0 ? "Saved to \(p) on your Mac" : "Kept for \(p) — it goes to your Mac on its Wi-Fi")
    }
}

struct NeededVaultShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GrabAndGoIntent(), phrases: ["Grab and Go in \(.applicationName)", "\(.applicationName) Grab and Go"],
                    shortTitle: "Grab & Go", systemImageName: "camera.fill")
        AppShortcut(intent: SaveScreenshotIntent(), phrases: ["Save my screenshot to \(.applicationName)"],
                    shortTitle: "Save screenshot", systemImageName: "camera.viewfinder")
    }
}

// Needed Vault for iPhone — the side button, Back Tap and Siri. These show up in the
// Shortcuts app by themselves; Settings › Action Button › Shortcut › "Grab & Go" — done.

import AppIntents

struct GrabAndGoIntent: AppIntent {
    static var title: LocalizedStringResource = "Grab & Go"
    static var description = IntentDescription("Switches Grab & Go on — into the project you last used — or off.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let v = VaultFolder.shared
        if v.grabGo() != nil {
            v.setGrabGo(nil)
            return .result(dialog: "Grab & Go off")
        }
        guard let p = v.lastProject, !p.isEmpty else { return .result(dialog: "Open Needed Vault and pick a project first") }
        v.setGrabGo(p)
        return .result(dialog: "Grab & Go on — everything goes into \(p)")
    }
}

struct SaveScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Save my latest screenshot"
    static var description = IntentDescription("Puts your latest screenshot into the Grab & Go project, or the one you last used.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let v = VaultFolder.shared
        guard let p = v.grabGo() ?? v.lastProject, !p.isEmpty else { return .result(dialog: "Open Needed Vault and pick a project first") }
        guard let f = await AppModel.latestScreenshot() else { return .result(dialog: "No screenshot — or Photos access is off") }
        let r = v.save([f], project: p, tags: [])
        return .result(dialog: r == .inVault ? "Saved to \(p)" : "Saved on this phone — it goes into \(p) soon")
    }
}

struct NeededVaultShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GrabAndGoIntent(), phrases: ["Grab and Go in \(.applicationName)", "\(.applicationName) Grab and Go"],
                    shortTitle: "Grab & Go", systemImageName: "bolt.fill")
        AppShortcut(intent: SaveScreenshotIntent(), phrases: ["Save my screenshot to \(.applicationName)"],
                    shortTitle: "Save screenshot", systemImageName: "camera.viewfinder")
    }
}

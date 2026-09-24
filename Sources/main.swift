// Needed Tools — where the app starts. Swift only runs code at the top
// level of a file called main.swift, so the start-up lives here.

import AppKit

let app = NSApplication.shared
let shell = Shell()
app.delegate = shell
app.setActivationPolicy(.regular)
app.run()

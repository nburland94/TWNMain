// needed-mcp — Needed Tools for the Claude app (round 42).
//
// An MCP server over stdio: the Claude app starts it (Needed Tools › Home › your account › Claude ›
// Connect adds it to Claude's settings), asks it which tools there are, and calls them. Each call is
// passed to Needed Tools itself over a private connection on this Mac (127.0.0.1 + a key it reads from
// ~/Library/Application Support/NeededTools/claude-link.json). If Needed Tools isn't open, it's opened.
//
// Built by Build-Needed-Tools.command into Needed Tools.app/Contents/MacOS/needed-mcp.

import Foundation

let serverVersion = "1.0"

// MARK: The tools Claude sees

func obj(_ props: [String: Any], _ required: [String] = []) -> [String: Any] {
    var o: [String: Any] = ["type": "object", "properties": props]
    if !required.isEmpty { o["required"] = required }
    return o
}
let strArr: [String: Any] = ["type": "array", "items": ["type": "string"]]
let colourNames = ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "brown", "black", "grey", "white", "dark", "light", "pastel"]
let sections = "Cover, Director's note, The idea, Look & feel, Cinematography, Light & colour, Casting, Wardrobe & styling, Locations & design, Edit & pace, Sound & music, Story, References, Production, Thank you"
let pageWords: [String: Any] = [
    "heading": ["type": "string", "description": "The page's big words (its title)."],
    "body": ["type": "string", "description": "The page's main text, in the user's voice."],
    "kicker": ["type": "string", "description": "The small line above the heading (optional)."],
    "signoff": ["type": "string", "description": "A sign-off line, where the page has one (optional)."],
    "stills": ["type": "array", "items": ["type": "string"], "description": "Still ids for this page's pictures, best first."]]

func tool(_ name: String, _ title: String, _ desc: String, _ schema: [String: Any], readOnly: Bool) -> [String: Any] {
    ["name": name, "title": title, "description": desc, "inputSchema": schema,
     "annotations": ["title": title, "readOnlyHint": readOnly, "destructiveHint": false, "idempotentHint": readOnly, "openWorldHint": false]]
}

let tools: [[String: Any]] = [
    tool("list_projects", "List projects", "The projects in the user's Needed Tools vault, with how many stills, GIFs and clips each has, its label, and which project is open.", obj([:]), readOnly: true),
    tool("project_summary", "Project summary", "One project at a glance: kinds of media, how many stills have no tags yet, its most used tags and colours, and its designs.",
         obj(["project": ["type": "string", "description": "Project name. Leave out for the one open in Needed Tools."]]), readOnly: true),
    tool("search_stills", "Search stills", "Find stills (and GIFs) in the vault by words, tags and colours. Returns ids with each still's project, title, tags and colours. Use view_stills to look at them.",
         obj(["query": ["type": "string", "description": "Words to look for in titles, tags, boards and colour names, e.g. 'night rain neon'."],
              "project": ["type": "string", "description": "Only this project."],
              "tags": ["type": "array", "items": ["type": "string"], "description": "Every one of these tags must be on the still."],
              "colours": ["type": "array", "items": ["type": "string", "enum": colourNames], "description": "Any of these colours among the still's main colours."],
              "kind": ["type": "string", "enum": ["stills", "gifs", "clips", "any"], "description": "Default: stills (with GIFs)."],
              "untagged": ["type": "boolean", "description": "Only stills with no tags yet."],
              "limit": ["type": "integer", "minimum": 1, "maximum": 300, "description": "Default 40."]]), readOnly: true),
    tool("view_stills", "Look at stills", "See up to 8 stills as pictures, with their tags and colours — to judge them, describe them or tag them.",
         obj(["ids": ["type": "array", "items": ["type": "string"], "maxItems": 8],
              "size": ["type": "integer", "minimum": 256, "maximum": 1200, "description": "Longest side in pixels. Default 640."]], ["ids"]), readOnly: true),
    tool("tag_stills", "Tag stills", "Add tags to stills in the vault (what's in the frame, light, shot size, mood, place — short lowercase words like 'night', 'close-up', 'backlit'). Existing tags are kept unless mode is 'replace'.",
         obj(["items": ["type": "array", "items": obj(["id": ["type": "string"], "tags": strArr], ["id", "tags"])],
              "mode": ["type": "string", "enum": ["add", "replace"], "description": "Default: add."]], ["items"]), readOnly: false),
    tool("list_templates", "List treatment templates", "The treatment templates in Needed Design (e.g. Noir), their A/B/C versions and the 15 sections every treatment has, in order.", obj([:]), readOnly: true),
    tool("build_treatment", "Build a treatment", "Build a new treatment in Needed Design from a template, filled with the user's own stills and words, and open it. Sections: \(sections). For each section you can give the words and the still ids; sections you leave out are filled from the pool (by default the project's stills, matched to the template's look). Read the user's voice with get_my_voice first and write in it.",
         obj(["project": ["type": "string", "description": "The project it belongs to (from list_projects)."],
              "template": ["type": "string", "description": "Template name or id, e.g. 'Noir'."],
              "variant": ["type": "string", "enum": ["a", "b", "c"], "description": "a: calm grids and splits. b: led by the design. c: arranges the pictures for you. Default a."],
              "name": ["type": "string", "description": "The design's name, e.g. 'Lexus RZ — Quiet Power'."],
              "pool": ["type": "array", "items": ["type": "string"], "description": "Still ids to fill the other pages from."],
              "pool_tags": ["type": "array", "items": ["type": "string"], "description": "Or: fill the other pages from the project's stills with any of these tags."],
              "pool_colours": ["type": "array", "items": ["type": "string", "enum": colourNames], "description": "Or: from stills with these colours."],
              "pages": ["type": "array", "items": obj((["section": ["type": "string", "description": "Section name, or its number 1–15."]] as [String: Any]).merging(pageWords) { a, _ in a }, ["section"])]],
             ["project", "template"]), readOnly: false),
    tool("list_designs", "List designs", "The mood boards and treatments in a project, newest first, with the id to read or change each.",
         obj(["project": ["type": "string", "description": "Leave out for the project open in Needed Tools."]]), readOnly: true),
    tool("read_design", "Read a design", "Every page of a design: its words (by role: head, body, kick, sign) and its still ids ('sample:' marks a template's sample picture).",
         obj(["design": ["type": "string", "description": "The design id from list_designs or build_treatment."]], ["design"]), readOnly: true),
    tool("write_page", "Rewrite a page", "Change one page of a design: its words and/or its stills. It opens in Needed Design; the user can undo with ⌘Z.",
         obj((["design": ["type": "string"], "page": ["type": "integer", "minimum": 1, "description": "Page number, from 1."]] as [String: Any]).merging(pageWords) { a, _ in a }, ["design", "page"]), readOnly: false),
    tool("get_my_voice", "Read my voice", "The user's own writing — past treatments, pitches and notes from the folder they chose (often in Obsidian). Read it before writing, and match its tone, rhythm and words.", obj([:]), readOnly: true),
]

let instructions = """
Needed Tools is a Mac app for film directors: a vault of reference stills (by project), and Needed Design for treatments and mood boards. \
To write a treatment: get_my_voice first; list_projects / project_summary; search_stills and view_stills to choose pictures; then build_treatment with each section's words (in the user's voice) and stills. \
To tag a project: search_stills with project and untagged:true, view_stills 8 at a time, then tag_stills. Tags are short lowercase words. \
Later changes: read_design, then write_page. Nothing is ever deleted through these tools.
"""

// MARK: Talking to Needed Tools

struct Link { let port: Int; let token: String }
let infoURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NeededTools/claude-link.json")

func readLink() -> Link? {
    guard let d = try? Data(contentsOf: infoURL), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
          let p = j["port"] as? Int, p > 0, let t = j["token"] as? String else { return nil }
    return Link(port: p, token: t)
}
/// This helper lives in Needed Tools.app/Contents/MacOS — so the app is three folders up.
func appURL() -> URL {
    URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
func openApp() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-g", appURL().path]
    try? p.run(); p.waitUntilExit()
}

enum Answer { case ok([String: Any]), unreachable, failed(String) }

func post(_ link: Link, _ body: Data, timeout: TimeInterval) -> Answer {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(link.port)/tool")!, timeoutInterval: timeout)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(link.token)", forHTTPHeaderField: "Authorization")
    req.httpBody = body
    let sem = DispatchSemaphore(value: 0)
    var out: Answer = .unreachable
    URLSession.shared.dataTask(with: req) { d, r, e in
        defer { sem.signal() }
        if e != nil { out = .unreachable; return }
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        let j = d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        if code == 200 { out = .ok(j) } else { out = .failed((j["error"] as? String) ?? "Needed Tools answered \(code)") }
    }.resume()
    sem.wait()
    return out
}

func callApp(_ name: String, _ args: [String: Any]) -> [String: Any] {
    let body = (try? JSONSerialization.data(withJSONObject: ["name": name, "arguments": args])) ?? Data()
    let problem = { (s: String) -> [String: Any] in ["content": [["type": "text", "text": s]], "isError": true] }
    if let l = readLink(), case .ok(let j) = post(l, body, timeout: 240) { return j }
    // Not open (or just restarted): open it, then try again for a little while.
    openApp()
    for _ in 0..<40 {
        Thread.sleep(forTimeInterval: 0.5)
        guard let l = readLink() else { continue }
        switch post(l, body, timeout: 240) {
        case .ok(let j): return j
        case .failed(let s): return problem(s)
        case .unreachable: continue
        }
    }
    return problem("Couldn't reach Needed Tools. Open Needed Tools on this Mac, then ask again.")
}

// MARK: MCP over stdio — one JSON-RPC message per line

let out = FileHandle.standardOutput
func send(_ o: [String: Any]) {
    guard var d = try? JSONSerialization.data(withJSONObject: o) else { return }
    d.append(0x0A)
    out.write(d)
}
func result(_ id: Any, _ r: [String: Any]) { send(["jsonrpc": "2.0", "id": id, "result": r]) }
func error(_ id: Any, _ code: Int, _ msg: String) { send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": msg]]) }

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let d = line.data(using: .utf8), let msg = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
    let method = msg["method"] as? String ?? ""
    guard let id = msg["id"], !(id is NSNull) else { continue }          // notifications (initialized, cancelled): nothing to answer
    let params = msg["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        // Round 45: tell Needed Tools which app started us ("Claude is using Needed Tools") — quietly, only if it's open.
        let client = ((params["clientInfo"] as? [String: Any])?["name"] as? String) ?? "an AI app"
        DispatchQueue.global().async {
            if let l = readLink(), let b = try? JSONSerialization.data(withJSONObject: ["name": "_hello", "arguments": ["client": client]]) { _ = post(l, b, timeout: 3) }
        }
        result(id, ["protocolVersion": (params["protocolVersion"] as? String) ?? "2025-06-18",
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "needed-tools", "title": "Needed Tools", "version": serverVersion],
                    "instructions": instructions])
    case "ping": result(id, [:])
    case "tools/list": result(id, ["tools": tools])
    case "tools/call":
        let name = params["name"] as? String ?? ""
        guard tools.contains(where: { ($0["name"] as? String) == name }) else { error(id, -32602, "Unknown tool: \(name)"); continue }
        result(id, callApp(name, params["arguments"] as? [String: Any] ?? [:]))
    case "resources/list": result(id, ["resources": [Any]()])
    case "resources/templates/list": result(id, ["resourceTemplates": [Any]()])
    case "prompts/list": result(id, ["prompts": [Any]()])
    default: error(id, -32601, "Method not found: \(method)")
    }
}

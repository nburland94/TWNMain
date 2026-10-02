import Foundation

enum SortPremiere {
    static let labels = ["Violet", "Iris", "Caribbean", "Lavender", "Cerulean", "Forest", "Rose", "Mango", "Purple", "Blue", "Teal", "Magenta", "Tan", "Green", "Brown", "Yellow"]
    static func write(name: String, scenes: [[String: Any]], root: URL, template: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["name": name, "scenes": scenes], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("_PREMIERE_SCENES.json"), options: .atomic)
        let literal = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        try template.replacingOccurrences(of: "__NEEDED_SORT_DATA__", with: literal).write(to: root.appendingPathComponent("_IMPORT_IN_PREMIERE.jsx"), atomically: true, encoding: .utf8)
        let instructions = """
        NEEDED SORT — PREMIERE SCENE LABELS

        Folder colours do not transfer just by dragging folders into Premiere.
        The included _IMPORT_IN_PREMIERE.jsx imports scene bins, separate Video/Audio bins,
        and applies your scene label to each imported clip using Premiere's scripting API.

        1. Keep the import script beside the sorted media folders.
        2. Open your destination project in Premiere.
        3. Run _IMPORT_IN_PREMIERE.jsx in Premiere using an installed ExtendScript script
           runner, or Adobe's ExtendScript Debugger for Visual Studio Code targeting Premiere.
           It cannot be run by File > Import or by double-clicking the script in Finder.
        4. Confirm the import, then add the new labelled clips to your timeline.

        This requires a Premiere version supporting ExtendScript. A one-click UXP panel
        is not included. Custom Premiere label preferences can change the displayed colours.
        Existing timeline clips are not recoloured. Running again creates another import bin.
        The JSON file also records labels and sorted paths for other integrations.
        This export has automated checks but has not been verified inside your Premiere version.
        """
        try instructions.write(to: root.appendingPathComponent("_PREMIERE_READ_ME.txt"), atomically: true, encoding: .utf8)
    }
}

import AppKit

/// Words Whisper is primed with. On a mixed Turkish/English test set a generic dev list cut WER from 20.6% to 14.8%;
/// each word costs ~25 ms latency.
enum Vocabulary {
    static let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Vello/words.txt")

    private static var defaults: String {
        String(localized: "# Vello word list: one word per line. Add technical terms, project and people names you use often.") + "\n"
            + String(localized: "# Over ~40 words noticeably slows typing. Lines starting with '#' are ignored.") + "\n" + words
    }

    private static let words = """
    Claude Code
    PR
    commit
    push
    merge
    branch
    deploy
    bug
    fix
    test
    API
    frontend
    backend
    Swift
    Xcode
    build
    release
    issue
    """

    /// Read on every dictation so edits apply without a restart.
    static func prompt() -> String {
        ensureFile()
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .joined(separator: ", ")
    }

    static func open() {
        ensureFile()
        NSWorkspace.shared.open(url)
    }

    private static func ensureFile() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let old = url.deletingLastPathComponent().appendingPathComponent("kelimeler.txt") // pre-0.1 name
        if (try? FileManager.default.moveItem(at: old, to: url)) != nil { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? defaults.write(to: url, atomically: true, encoding: .utf8)
    }
}

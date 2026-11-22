import AppKit
import WhisperKit

/// Talk key choices: only keys that don't type anything, so holding them never blocks writing.
enum TalkKey: String, CaseIterable, Identifiable {
    case rightOption, rightCommand, fn, rightControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rightOption: String(localized: "Right Option")
        case .rightCommand: String(localized: "Right Command")
        case .fn: "Fn"
        case .rightControl: String(localized: "Right Control (external keyboard)")
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .fn: 63
        case .rightControl: 62
        }
    }

    /// Device-dependent modifier bits (IOLLEvent NX_DEVICE*KEYMASK) tell right keys apart from left ones.
    func isDown(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .rightOption: flags.rawValue & 0x40 != 0
        case .rightCommand: flags.rawValue & 0x10 != 0
        case .fn: flags.contains(.function)
        case .rightControl: flags.rawValue & 0x2000 != 0
        }
    }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var talkKey: TalkKey {
        get { TalkKey(rawValue: defaults.string(forKey: "talkKey") ?? "") ?? .rightOption }
        set { defaults.set(newValue.rawValue, forKey: "talkKey") }
    }

    /// Speaking language as a Whisper language code; nil until chosen in setup. Never auto-detected:
    /// Whisper often guesses wrong on short clips and on Turkish mixed with English terms.
    static var language: String? {
        get { defaults.string(forKey: "language") }
        set { defaults.set(newValue, forKey: "language") }
    }

    static var micMode: MicMode {
        get { MicMode(rawValue: defaults.string(forKey: "micMode") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "micMode") }
    }

    static var setupDone: Bool {
        get { defaults.bool(forKey: "setupDone") }
        set { defaults.set(newValue, forKey: "setupDone") }
    }

    /// Turkish and English first (Vello's audience), then every other Whisper language alphabetically.
    static let languages: [(code: String, name: String)] = {
        let name = { (code: String) in Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code }
        let rest = Constants.languageCodes.subtracting(["tr", "en"]).map { ($0, name($0)) }
            .sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
        return [("tr", name("tr")), ("en", name("en"))] + rest
    }()
}

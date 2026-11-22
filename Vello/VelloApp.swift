import ServiceManagement
import Sparkle
import SwiftUI

@main
struct VelloApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            Menu(dictation: appDelegate.dictation, updater: appDelegate.updater.updater)
        } label: {
            MenuIcon(dictation: appDelegate.dictation)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor lazy var dictation = Dictation()
    /// Daily check against the GitHub Releases appcast; asks before installing.
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        if !Settings.setupDone || !dictation.canDictate { SettingsWindow.show(dictation) }
    }

    /// Launching Vello again (Launchpad, Finder, Spotlight) opens its settings: there's no Dock icon to click.
    @MainActor func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.show(dictation)
        return false
    }
}

private struct MenuIcon: View {
    @ObservedObject var dictation: Dictation
    var body: some View { Image(systemName: dictation.icon) }
}

private struct Menu: View {
    @ObservedObject var dictation: Dictation
    let updater: SPUUpdater

    var body: some View {
        if let status = dictation.menuStatus {
            Text(status)
            Divider()
        }
        Button(dictation.paused ? String(localized: "Resume") : String(localized: "Pause")) { dictation.paused.toggle() }
        Button("Copy Last Text") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(dictation.lastText ?? "", forType: .string)
        }
        .disabled(dictation.lastText == nil)
        Button("Settings…") { SettingsWindow.show(dictation) }
        Button("Check for Updates…") {
            NSApp.activate(ignoringOtherApps: true) // agent app: Sparkle's window would open behind others
            updater.checkForUpdates()
        }
        Button("Send Feedback…") { NSWorkspace.shared.open(Feedback.url) }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}

enum Feedback {
    /// GitHub issue form with the versions prefilled, so reports are actionable without asking.
    static var url: URL {
        var c = URLComponents(string: "https://github.com/alimuratkuslu/vello/issues/new")!
        let os = ProcessInfo.processInfo.operatingSystemVersion
        c.queryItems = [
            URLQueryItem(name: "template", value: "feedback.yml"),
            URLQueryItem(name: "vello-version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String),
            URLQueryItem(name: "macos-version", value: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"),
        ]
        return c.url!
    }
}

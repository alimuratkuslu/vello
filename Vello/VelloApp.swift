import ServiceManagement
import SwiftUI

@main
struct VelloApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            Menu(dictation: appDelegate.dictation)
        } label: {
            MenuIcon(dictation: appDelegate.dictation)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor lazy var dictation = Dictation()

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

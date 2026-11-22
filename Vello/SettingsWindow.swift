import AppKit
import SwiftUI

/// One window for both setup (first run) and later changes: opened from the menu or by launching Vello again.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(_ dictation: Dictation) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 10),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Vello"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(dictation: dictation))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true) // agent apps don't come to front on their own
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless() // macOS 14+ may refuse activation when launched from another app
    }

    static func close() { window?.close() }

    /// Only if it's open: a grant shouldn't pop the window up after setup.
    static func bringToFront() {
        guard let window, window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
    }
}

private struct SettingsView: View {
    @ObservedObject var dictation: Dictation
    @State private var language = Settings.language
    @State private var talkKey = Settings.talkKey
    @State private var micMode = Settings.micMode
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var setupDone = Settings.setupDone

    // The model can finish in the background after Start; waiting minutes on it is the slowest part of setup.
    private var ready: Bool { language != nil && dictation.micGranted && dictation.axTrusted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !setupDone {
                Text("Set up Vello")
                    .font(.system(size: 20, weight: .semibold))
                Text("Hold the key, speak, let go: what you said is typed where your cursor is. Everything runs on this Mac, for free.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4).padding(.bottom, 16)
            }

            Row(title: String(localized: "Speaking language"), detail: String(localized: "Which language will you dictate in?"), done: language != nil) {
                Picker("", selection: $language) {
                    if language == nil { Text("Choose").tag(String?.none) }
                    ForEach(Settings.languages, id: \.code) { Text($0.name).tag(Optional($0.code)) }
                }
                .labelsHidden().frame(width: 150)
                .onChange(of: language) { _, new in Settings.language = new; dictation.objectWillChange.send() }
            }

            Row(title: String(localized: "Talk key"), detail: talkKey == .fn ? String(localized: "So Fn doesn’t open anything else: System Settings > Keyboard > Press fn key to: Do Nothing") : String(localized: "Listens while held, types when released."), done: true) {
                Picker("", selection: $talkKey) {
                    ForEach(TalkKey.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 150)
                .onChange(of: talkKey) { _, new in Settings.talkKey = new }
            }

            Row(title: String(localized: "Microphone"), detail: micMode == .auto ? String(localized: "Listens only while the key is held. Uses the MacBook mic when AirPods are in, so your music isn’t degraded.") : String(localized: "Listens only while the key is held."), done: dictation.micGranted) {
                if dictation.micGranted {
                    Picker("", selection: $micMode) {
                        ForEach(MicMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 150)
                    .onChange(of: micMode) { _, new in Settings.micMode = new }
                } else {
                    Button("Allow") { dictation.requestMic() }
                }
            }

            Row(title: String(localized: "Accessibility"), detail: dictation.axRequested && !dictation.axTrusted ? String(localized: "In System Settings, turn on the switch next to Vello. This window comes back on its own.") : String(localized: "Needed to detect the key and type the text."), done: dictation.axTrusted) {
                if !dictation.axTrusted { Button("Open Settings") { dictation.requestAccessibility() } }
            }

            Row(title: String(localized: "Speech model"), detail: dictation.modelReady ? String(localized: "Ready") : dictation.modelStatus, done: dictation.modelReady) {
                if !dictation.modelReady {
                    if let progress = dictation.modelProgress {
                        ProgressView(value: progress).frame(width: 120)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            if setupDone {
                Row(title: String(localized: "Open at login"), detail: String(localized: "Start Vello when your Mac starts."), done: nil) {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, on in LoginItem.set(on) }
                }
                Row(title: String(localized: "Word list"), detail: String(localized: "Add terms and names you use often for more accurate text."), done: nil) {
                    Button("Edit") { Vocabulary.open() }
                }
            } else {
                HStack {
                    Spacer()
                    Button("Start") {
                        Settings.setupDone = true
                        setupDone = true
                        LoginItem.set(true) // on by default
                        launchAtLogin = LoginItem.isEnabled
                        SettingsWindow.close()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
                }
                .padding(.top, 16)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct Row<Control: View>: View {
    let title: String
    let detail: String
    let done: Bool?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let done {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(done ? Color.green : Color.secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }
}

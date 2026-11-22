import AppKit
import SwiftUI

/// Listening indicator: a solid capsule at the bottom center of the screen under the mouse.
@MainActor
final class Indicator {
    private let panel: NSPanel

    init(dictation: Dictation) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true // never steals focus or clicks from the field we paste into
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: IndicatorView(dictation: dictation))
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.minY + 16))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct IndicatorView: View {
    @ObservedObject var dictation: Dictation

    var body: some View {
        content
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(Color(white: 0.11)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        if let error = dictation.flashError {
            Text(error)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 1, green: 0.38, blue: 0.35))
                .lineLimit(1)
        } else if dictation.state == .transcribing {
            Dots()
        } else {
            Bars(levels: dictation.levels)
        }
    }
}

private struct Bars: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: 4 + CGFloat(levels[i]) * 18)
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.08), value: levels)
    }
}

private struct Dots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                        .opacity(0.3 + 0.7 * (0.5 + 0.5 * sin(t * 6 - Double(i) * 0.9)))
                }
            }
            .frame(width: 69) // same footprint as the bars so the capsule doesn't jump
        }
    }
}

/// One-time "ready" card under the menu bar after the first model download, so nobody has to watch it prepare.
/// Our own panel instead of a system notification: no extra permission to ask for during setup.
@MainActor
enum ReadyToast {
    private static var panel: NSPanel?

    static func show(talkKey: String) {
        let view = NSHostingView(rootView: ReadyCard(talkKey: talkKey))
        let size = view.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = view
        if let area = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: area.maxX - size.width - 12, y: area.maxY - size.height - 8))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; p.animator().alphaValue = 0 }) {
                p.orderOut(nil)
                if panel === p { panel = nil }
            }
        }
    }
}

private struct ReadyCard: View {
    let talkKey: String

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vello is ready").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text("Hold \(talkKey) to talk").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08)))
    }
}

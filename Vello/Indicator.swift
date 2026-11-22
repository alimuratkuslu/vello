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

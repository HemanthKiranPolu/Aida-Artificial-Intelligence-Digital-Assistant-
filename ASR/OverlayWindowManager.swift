import SwiftUI
import AppKit

/// Manages showing/hiding the main overlay window and a tiny icon window so toggling is spam-safe.
@MainActor
final class OverlayWindowManager {
    static let shared = OverlayWindowManager()

    private let overlayIdentifier = NSUserInterfaceItemIdentifier("ASROverlayWindow")
    private let iconIdentifier = NSUserInterfaceItemIdentifier("ASRIconWindow")

    private weak var overlayWindow: NSWindow?
    private var iconWindow: NSWindow?
    private var pendingIconReposition: DispatchWorkItem?

    var overlayScreen: NSScreen? {
        overlayWindow?.screen ?? NSApplication.shared.windows.first(where: { $0.identifier == overlayIdentifier })?.screen
    }

    var isOverlayVisible: Bool {
        overlayWindow?.isVisible ?? false
    }

    @discardableResult
    func registerOverlayWindowIfNeeded(_ candidate: NSWindow?) -> NSWindow? {
        if let overlayWindow {
            return overlayWindow
        }
        guard let candidate else { return nil }
        candidate.identifier = overlayIdentifier
        candidate.isReleasedWhenClosed = false
        overlayWindow = candidate
        return candidate
    }

    func toggleOverlayVisibility() {
        if isOverlayVisible {
            hideToIcon()
        } else {
            showOverlay()
        }
    }

    func showOverlay() {
        pendingIconReposition?.cancel()
        iconWindow?.orderOut(nil)

        if overlayWindow == nil {
            overlayWindow = NSApplication.shared.windows.first(where: { $0.identifier == overlayIdentifier }) ?? NSApplication.shared.windows.first
        }
        guard let window = overlayWindow else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func hideToIcon() {
        overlayWindow?.orderOut(nil)
        ensureIconWindow()
        iconWindow?.makeKeyAndOrderFront(nil)
        scheduleIconReposition()
    }

    private func ensureIconWindow() {
        guard iconWindow == nil else { return }

        let size: CGFloat = 56
        let rect = defaultIconFrame(size: size)

        let hosting = NSHostingView(rootView: MiniIconView())
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: size, height: size))

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.identifier = iconIdentifier
        window.contentView = hosting

        iconWindow = window
    }

    private func scheduleIconReposition() {
        guard let iconWindow else { return }
        pendingIconReposition?.cancel()

        let workItem = DispatchWorkItem { [weak iconWindow] in
            guard let iconWindow else { return }
            let size = iconWindow.frame.size
            let frame = self.defaultIconFrame(size: size.width)
            iconWindow.setFrame(frame, display: true, animate: false)
        }

        pendingIconReposition = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func defaultIconFrame(size: CGFloat) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 400, height: 300)
        let origin = NSPoint(
            x: screen.maxX - size - 20,
            y: screen.minY + 80
        )
        return NSRect(origin: origin, size: NSSize(width: size, height: size))
    }
}

struct MiniIconView: View {
    var body: some View {
        Button {
            OverlayWindowManager.shared.showOverlay()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .frame(width: 56, height: 56)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

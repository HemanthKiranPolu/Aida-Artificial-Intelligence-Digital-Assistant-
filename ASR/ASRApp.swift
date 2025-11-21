//
//  ASRApp.swift
//  ASR
//
//  Created by hemanth kiran Polu on 11/15/25.
//

import SwiftUI
import AppKit

@main
struct ASRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let privacyGuard = WindowPrivacyGuard()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.processName = "P module"
        NSApplication.shared.setActivationPolicy(.accessory)
        privacyGuard.start()

        Task {
            do {
                try await BackendServiceController.shared.ensureBackendRunning()
            } catch {
                NSLog("Failed to auto-start Parakeet backend: \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        privacyGuard.stop()
        Task {
            await BackendServiceController.shared.stopBackendIfNeeded()
        }
    }
}

final class WindowPrivacyGuard {
    private var visibilityObserver: NSObjectProtocol?

    func start() {
        applyToExistingWindows()
        visibilityObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let window = note.object as? NSWindow {
                self?.harden(window)
            } else {
                self?.applyToExistingWindows()
            }
        }
    }

    func stop() {
        if let observer = visibilityObserver {
            NotificationCenter.default.removeObserver(observer)
            visibilityObserver = nil
        }
    }

    private func applyToExistingWindows() {
        for window in NSApplication.shared.windows {
            harden(window)
        }
    }

    private func harden(_ window: NSWindow) {
        window.sharingType = .none
        if let contentView = window.contentView {
            if contentView.layer == nil {
                contentView.wantsLayer = true
            }
            contentView.layer?.isOpaque = false
        }
    }
}

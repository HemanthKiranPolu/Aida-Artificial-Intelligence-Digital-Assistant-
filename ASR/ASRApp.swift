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
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                try await BackendServiceController.shared.ensureBackendRunning()
            } catch {
                NSLog("Failed to auto-start Parakeet backend: \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await BackendServiceController.shared.stopBackendIfNeeded()
        }
    }
}

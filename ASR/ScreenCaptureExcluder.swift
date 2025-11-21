import Foundation
import ScreenCaptureKit
import Darwin

@MainActor
enum ScreenCaptureExcluder {
    enum Error: Swift.Error {
        case noDisplayAvailable
    }

    /// Builds an `SCContentFilter` that excludes all windows owned by this app (overlay, icon, any others).
    /// Use this when creating `SCStream`/`SCStreamConfiguration` so our UI is never present in captures.
    static func makeFilter(excluding extraWindowIDs: [CGWindowID] = [],
                           for display: SCDisplay? = nil) async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        let targetDisplay: SCDisplay
        if let display {
            targetDisplay = display
        } else if let first = content.displays.first {
            targetDisplay = first
        } else {
            throw Error.noDisplayAvailable
        }

        let ownWindowIDs = Set(Self.collectOwnWindowIDs())
        let pid = getpid()

        let excludedWindows = content.windows.filter { window in
            let windowIDMatch = ownWindowIDs.contains(window.windowID) || extraWindowIDs.contains(window.windowID)
            let pidMatch = Int(window.owningApplication?.processID ?? 0) == pid
            let title = window.title?.lowercased() ?? ""
            let titleMatch = title.contains("parakeet") || title.contains("asr")
            return windowIDMatch || pidMatch || titleMatch
        }

        return SCContentFilter(
            display: targetDisplay,
            excludingApplications: [],
            exceptingWindows: excludedWindows
        )
    }

    private static func collectOwnWindowIDs() -> [CGWindowID] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let pid = Int(getpid())
        return infoList.compactMap { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == pid,
                  let windowNumber = info[kCGWindowNumber as String] as? UInt32 else {
                return nil
            }
            return CGWindowID(windowNumber)
        }
    }
}

import Foundation
import Darwin

actor BackendServiceController {
    static let shared = BackendServiceController()

    private let serviceLabel = "com.hemanth.parakeet"
    private let plistPath: String
    private let serviceTarget: String
    private let domainTarget: String
    private let healthURL = URL(string: "http://127.0.0.1:8000/healthz")!
    private var shouldStopOnExit = false

    init() {
        plistPath = ("~/Library/LaunchAgents/com.hemanth.parakeet.plist" as NSString).expandingTildeInPath
        let uid = getuid()
        serviceTarget = "gui/\(uid)/\(serviceLabel)"
        domainTarget = "gui/\(uid)"
    }

    func ensureBackendRunning() async throws {
        if await isHealthy() {
            shouldStopOnExit = false
            return
        }

        try await startService()
        try await waitUntilHealthy()
        shouldStopOnExit = true
    }

    func stopBackendIfNeeded() async {
        guard shouldStopOnExit else { return }
        try? await stopService()
        shouldStopOnExit = false
    }

    private func startService() async throws {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw BackendServiceError.launchAgentMissing
        }

        _ = try? await runLaunchctl(["bootout", serviceTarget])
        _ = try await runLaunchctl(["bootstrap", domainTarget, plistPath])
        _ = try await runLaunchctl(["kickstart", "-k", serviceTarget])
    }

    private func stopService() async throws {
        _ = try await runLaunchctl(["bootout", serviceTarget])
    }

    private func waitUntilHealthy() async throws {
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 500_000_000)
            if await isHealthy() {
                return
            }
        }
        throw BackendServiceError.healthCheckTimedOut
    }

    private func isHealthy() async -> Bool {
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func runLaunchctl(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else if output.contains("No such process") {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: BackendServiceError.launchctlFailed(command: arguments.joined(separator: " "), output: output))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum BackendServiceError: LocalizedError {
    case launchAgentMissing
    case launchctlFailed(command: String, output: String)
    case healthCheckTimedOut

    var errorDescription: String? {
        switch self {
        case .launchAgentMissing:
            return "Launch agent not installed. Run ./scripts/manage_parakeet_service.sh install."
        case .launchctlFailed(let command, let output):
            return "launchctl failed for '\(command)': \(output)"
        case .healthCheckTimedOut:
            return "Timed out waiting for the Parakeet backend to become healthy."
        }
    }
}

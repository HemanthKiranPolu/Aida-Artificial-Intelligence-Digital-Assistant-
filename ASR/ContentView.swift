import SwiftUI
import AVFoundation
import AppKit
import Combine
@preconcurrency import Vision
import ScreenCaptureKit

struct ContentView: View {
    @StateObject private var viewModel = ASRViewModel()
    @State private var showAdvancedSettings = false
    @State private var showDeploymentNotes = false
    @State private var keyboardShortcutMonitor: Any?
    @State private var globalKeyboardShortcutMonitor: Any?
    @State private var screenShareMonitor = ScreenShareMonitor()
    @State private var layout = CoachOverlayLayout.preferred(for: NSScreen.main)

    var body: some View {
        let targetSize = layout.size
        expandedOverlay
            .frame(width: targetSize.width, height: targetSize.height)
            .background(Color.clear)
            .onAppear {
                configureWindow()
                registerKeyboardShortcuts()
                refreshLayout()
                screenShareMonitor.startMonitoring { isSharing in
                    OverlayWindowManager.shared.suppressForCapture(isSharing)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                refreshLayout()
            }
            .onDisappear {
                removeKeyboardShortcuts()
                screenShareMonitor.stopMonitoring()
            }
            .sheet(isPresented: $showAdvancedSettings) {
                AdvancedSettingsView(viewModel: viewModel, showDeploymentNotes: $showDeploymentNotes)
                    .frame(minWidth: 520, minHeight: 480)
            }
            .task {
                await viewModel.prepareMicrophonePermissionIfNeeded()
            }
    }

    private var expandedOverlay: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 40, x: 0, y: 24)

            VStack(spacing: 18) {
                header

                if viewModel.needsMicrophonePermission {
                    PermissionBanner(
                        requestAction: { Task { await viewModel.prepareMicrophonePermissionIfNeeded() } },
                        settingsAction: viewModel.openMicrophoneSettings
                    )
                }

                controlRow
                workspaceStack
            }
            .padding(layout.padding)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            statusBadge
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                toggleOverlayVisibility()
            } label: {
                Label("Hide", systemImage: "eye.slash")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        VisualEffectBlur(material: .menu, blendingMode: .behindWindow)
                            .clipShape(Capsule())
                    )
            }
            .keyboardShortcut("h", modifiers: [.command])
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if viewModel.isRecording {
            StatusBadge(text: "Listening", color: .red)
        } else if viewModel.isProcessing {
            StatusBadge(text: "Processing", color: .orange)
        } else {
            StatusBadge(text: "Idle", color: .green)
        }
    }

    private var providerPicker: some View {
        Menu {
            ForEach(LLMProvider.allCases) { provider in
                Button {
                    viewModel.llmProvider = provider
                } label: {
                    Label(provider.rawValue, systemImage: viewModel.llmProvider == provider ? "checkmark" : "")
                }
            }
        } label: {
            Label(viewModel.llmProvider.shortName, systemImage: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            VisualEffectBlur(material: .menu, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            providerPicker
            Button(action: viewModel.toggleRecording) {
                Label(viewModel.isRecording ? "Stop" : "Start",
                      systemImage: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
            }
            .keyboardShortcut(.space)
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRecording ? .red : .green)
            .controlSize(.small)

            Button {
                Task { await viewModel.askAIManually() }
            } label: {
                Label("Ask AI", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isProcessing)

            Button {
                viewModel.scanScreenAndAsk()
            } label: {
                Label("Scan Screen", systemImage: "macwindow.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.small)
            .disabled(viewModel.isProcessing)

            Button(role: .destructive, action: viewModel.clearWorkspace) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                showAdvancedSettings = true
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workspaceStack: some View {
        ResponsiveStack(spacing: 18) {
            transcriptCard
            answerCard
        }
    }

    private var transcriptCard: some View {
        OverlayCard(title: "Live Transcript", systemImage: "waveform") {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.transcript)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(height: 24)
                    .padding(.top, 6)
                    .padding(.horizontal, 6)
                    .scrollContentBackground(.hidden)

                if viewModel.transcript.isEmpty {
                    Text("Start speaking or type here...")
                        .foregroundStyle(Color.white.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
        } footer: {
            HStack {
                Text("\(viewModel.transcript.count) characters")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.transcript, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.transcript.isEmpty)
            }
        }
    }

    private var answerCard: some View {
        OverlayCard(title: "Answer Workspace", systemImage: "sparkles") {
            ScrollView {
                if viewModel.aiResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AnswerPlaceholderView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(CodeFormattedAnswerParser.sections(from: viewModel.aiResponse)) { section in
                            switch section.kind {
                            case .text:
                                AnswerTextSectionView(text: section.content)
                            case let .code(language):
                                AnswerCodeSectionView(code: section.content, language: language)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: layout.answerMinHeight, maxHeight: layout.answerMinHeight)
        } footer: {
            HStack {
                Text(viewModel.answerMetadata.isEmpty ? "No metadata yet." : viewModel.answerMetadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.aiResponse, forType: .string)
                } label: {
                    Label("Copy Answer", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.aiResponse.isEmpty)
            }
        }
    }

}

struct CoachOverlayLayout {
    let size: CGSize
    let cornerRadius: CGFloat = 28
    let padding: CGFloat = 24

    var answerMinHeight: CGFloat {
        max(260, size.height * 0.45)
    }

    static func preferred(for screen: NSScreen?) -> CoachOverlayLayout {
        let visibleSize = screen?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        let width = clamp(visibleSize.width * 0.5, min: 600, max: min(visibleSize.width - 80, 980))
        let height = clamp(visibleSize.height * 0.7, min: 520, max: min(visibleSize.height - 100, 860))
        return CoachOverlayLayout(size: CGSize(width: width, height: height))
    }

    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        guard max >= min else { return value }
        return Swift.max(min, Swift.min(max, value))
    }
}

struct OverlayCard<Content: View, Footer: View>: View {
    let title: String
    let systemImage: String
    private let contentBuilder: () -> Content
    private let footerBuilder: () -> Footer

    init(title: String,
         systemImage: String,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder footer: @escaping () -> Footer) {
        self.title = title
        self.systemImage = systemImage
        self.contentBuilder = content
        self.footerBuilder = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            contentBuilder()
            footerBuilder()
        }
        .padding(18)
        .background(
            VisualEffectBlur(material: .contentBackground, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
    }
}

private struct AnswerPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Answer text will render as soon as AI responds.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AnswerTextSectionView: View {
    let text: String

    var body: some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
    }
}

private struct AnswerCodeSectionView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(languageLabel, systemImage: "chevron.left.slash.chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private var languageLabel: String {
        if let language, !language.isEmpty {
            return language.lowercased()
        }
        return "code"
    }
}

private struct AnswerSection: Identifiable {
    let id = UUID()
    let content: String
    let kind: AnswerSectionKind
}

final class ScreenShareMonitor {
    private var timer: Timer?
    private let interval: TimeInterval = 2.0

    func startMonitoring(changeHandler: @escaping (Bool) -> Void) {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let active = ScreenShareMonitor.isScreenSharingLikely()
            DispatchQueue.main.async {
                changeHandler(active)
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private static func isScreenSharingLikely() -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let ownerKeywords: [String] = [
            "zoom", "zoom.us", "webex", "microsoft teams", "teams", "google chrome", "safari", "firefox", "meet"
        ]
        let windowKeywords: [String] = [
            "sharing", "screen share", "you're sharing", "is sharing your", "previewing"
        ]

        for info in infoList {
            guard let owner = (info[kCGWindowOwnerName as String] as? String)?.lowercased() else { continue }
            let name = (info[kCGWindowName as String] as? String)?.lowercased() ?? ""
            let ownerHit = ownerKeywords.contains(where: { owner.contains($0) })
            let windowHit = windowKeywords.contains(where: { name.contains($0) })
            if ownerHit && windowHit {
                return true
            }
        }
        return false
    }
}

private enum AnswerSectionKind {
    case text
    case code(language: String?)
}

private enum CodeFormattedAnswerParser {
    static func sections(from text: String) -> [AnswerSection] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let parts = trimmed.components(separatedBy: "```")
        var sections: [AnswerSection] = []

        for (index, part) in parts.enumerated() {
            let segment = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.isEmpty else { continue }
            if index % 2 == 0 {
                sections.append(AnswerSection(content: segment, kind: .text))
            } else {
                var lines = segment.components(separatedBy: .newlines)
                let first = lines.first ?? ""
                var language: String? = first.trimmingCharacters(in: .whitespacesAndNewlines)
                if language?.isEmpty ?? true {
                    language = nil
                } else {
                    lines.removeFirst()
                }
                let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                sections.append(AnswerSection(content: body, kind: .code(language: language)))
            }
        }

        if sections.isEmpty {
            return [AnswerSection(content: trimmed, kind: .text)]
        }
        return sections
    }
}

// MARK: - View Model

@MainActor
final class ASRViewModel: ObservableObject {
    private static let defaultServerURL = "http://127.0.0.1:8000/transcribe"
    private static let defaultLocalLLMEndpoint = "http://127.0.0.1:11434/v1/chat/completions"
    private static let defaultOpenAIModel = "gpt-4o-mini"
    private static let defaultLocalModel = "llama3"
    private static let serverDefaultsKey = "ASR.serverURL"
    private static let defaultOCRSystemPrompt = """
You will receive raw OCR screen text that may include noise like UI buttons, menus, inbox, timestamps, browser elements, ads, or incomplete fragments.

Your job:
1) Assume the scan likely contains a coding problem, even if partially captured.
2) Extract any text that looks like a coding prompt: title (e.g., “125. Valid Palindrome”), description, input/output format, examples, constraints, function signature hints.
3) Clean and reconstruct the problem — even if fragmented. If parts are missing, infer the most likely LeetCode-style details. Never say “No problem found”; always reconstruct and proceed.
4) Solve it in coding interview format:
   • Spoken intuition (2–4 sentences; key idea like two pointers/hash map/recursion/DP; no analogies).
   • Why this approach (briefly contrast with brute force; focus on performance).
   • Clean Python code (unless another language is specified) with minimal reasoning comments.
   • Time & Space Complexity (Big O) + short runtime/scalability note.
   • Edge cases (1–2 relevant cases).

Rules:
• Ignore UI noise (Inbox, Settings, Start, Submit, Ask AI, ads, nav bars, timestamps).
• Never ask the user to re-enter the question.
• Do not output “I can’t detect a problem.”
• If the scan seems incomplete, still infer and answer.

Final goal:
Act like a smart interview assistant that extracts, understands, and solves coding problems from noisy OCR screenshots.
"""
    private static let openAIKeyEnvVariable = "OPENAI_API_KEY"
    private static let envOverridePathKey = "ASR_ENV_FILE"
    private static let envFileName = ".env"

    private let defaults = UserDefaults.standard

    @Published var isRecording = false
    @Published var shouldAutoAsk = true
    @Published var autoStopOnSilence = true
    @Published var transcript: String = ""
    @Published var aiResponse: String = ""
    @Published var statusMessage: String = "Idle"
    @Published var answerMetadata: String = ""
    @Published var isProcessing = false
    @Published var needsMicrophonePermission = false
    @Published var recordingStartedAt: Date?

    @Published var serverURLString: String = ASRViewModel.defaultServerURL {
        didSet {
            defaults.set(serverURLString, forKey: Self.serverDefaultsKey)
        }
    }
    @Published var llmProvider: LLMProvider = .openAI {
        didSet {
            syncCurrentModelWithProvider()
            if llmProvider == .local {
                Task { await autoDetectLocalModelsIfNeeded() }
            }
        }
    }
    @Published var openAIKey: String = ""
    @Published var localLLMURLString: String = ASRViewModel.defaultLocalLLMEndpoint
    @Published var systemPrompt: String = """
You are an interview co-pilot. You answer questions exactly like a real candidate speaking in a live technical interview.

🎯 First detect the question type:

1️⃣ If the question is asking for a basic concept or definition
(ex: What is REST? What is async vs sync? What is a class?),
→ Give a clear, simple, spoken explanation in plain language.
→ No analogies, no textbook tone, no long theory.
→ Answer naturally, conversationally, like you're explaining to another developer.
→ 2–4 sentences is enough.

2️⃣ If the question asks about usage, implementation, experience, differences, or “how have you used it?”,
→ Then answer with practical, real or realistic experience.
→ Explain what you built, decisions you made, challenges you solved, and impact.
→ Use “I” and keep it real, specific, and conversational.

🚫 Do NOT:
• Do not use analogies (no waiter/restaurant/car examples).
• Do not explain concepts academically or like a teacher.
• Do not list bullet points or theoretical principles.
• Do not start with “X stands for…” or “At a high level…”

🗣 Tone:
• Natural spoken English, real interview style.
• Confident, conversational, and clear.
• 45–75 sec for experience-based answers.
• Short and clear for basic definition questions (15–30 sec).

🎤 Goal:
Sound like a real engineer — sometimes explaining simply, sometimes sharing experience — based on what the question is actually asking.
"""
    @Published var ocrSystemPrompt: String = ASRViewModel.defaultOCRSystemPrompt
    @Published var currentModel: String = ASRViewModel.defaultOpenAIModel {
        didSet { storeCurrentModelForProvider() }
    }
    @Published var isDetectingLocalModels = false
    @Published var localDetectionMessage: String = ""
    @Published var availableLocalModels: [String] = []

    private let recorder = AudioRecorder()
    private let asrService = ASRService()
    private let llmService = LLMService()
    private var openAIModelValue: String = ASRViewModel.defaultOpenAIModel
    private var localModelValue: String = ASRViewModel.defaultLocalModel
    private let maxPromptCharacters = 300

    init() {
        defaults.register(defaults: [Self.serverDefaultsKey: Self.defaultServerURL])
        serverURLString = defaults.string(forKey: Self.serverDefaultsKey) ?? Self.defaultServerURL
        if let envKey = Self.loadOpenAIKeyFromEnvironment() {
            openAIKey = envKey
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func askAIManually() async {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            statusMessage = "No transcript to send to AI."
            return
        }
        await runLLM(with: cleaned, manageProcessingFlag: true)
    }

    func clearWorkspace() {
        transcript = ""
        aiResponse = ""
        answerMetadata = ""
        statusMessage = "Cleared."
        recordingStartedAt = nil
    }

    func scanScreenAndAsk() {
        statusMessage = "Scanning the screen..."
        Task {
            do {
                let recognized = try await ScreenTextScanner.captureFullScreenText()
                let cleaned = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else {
                    statusMessage = "No readable text detected on the screen."
                    return
                }
                transcript = cleaned
                await runLLM(
                    with: cleaned,
                    manageProcessingFlag: true,
                    systemPromptOverride: ocrSystemPrompt
                )
            } catch {
                statusMessage = "Screen scan failed: \(error.localizedDescription)"
            }
        }
    }

    func recordingDuration(until referenceDate: Date = Date()) -> String {
        guard let start = recordingStartedAt else {
            return "00:00"
        }
        let interval = max(0, referenceDate.timeIntervalSince(start))
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func startRecording() {
        do {
            try recorder.startRecording(autoStopHandler: autoStopOnSilence ? { [weak self] url in
                self?.handleAutoStoppedRecording(fileURL: url)
            } : nil)
            transcript = ""
            aiResponse = ""
            answerMetadata = ""
            isRecording = true
            statusMessage = "Recording... Tap stop to send to ASR."
            needsMicrophonePermission = false
            recordingStartedAt = Date()
        } catch {
            statusMessage = "Recording failed: \(error.localizedDescription)"
            if error is AudioRecorderError {
                needsMicrophonePermission = true
            }
        }
    }

    private func stopRecording() {
        guard let fileURL = recorder.stopRecording() else {
            statusMessage = "No audio file produced."
            isRecording = false
            recordingStartedAt = nil
            return
        }
        isRecording = false
        recordingStartedAt = nil
        statusMessage = "Uploading audio to ASR..."
        Task {
            await transcribeAndAnswer(using: fileURL)
        }
    }

    private func handleAutoStoppedRecording(fileURL: URL?) {
        guard let fileURL = fileURL else {
            statusMessage = "Silence detected but no audio captured."
            isRecording = false
            recordingStartedAt = nil
            return
        }
        guard isRecording else { return }
        isRecording = false
        recordingStartedAt = nil
        statusMessage = "Silence detected. Uploading audio..."
        Task {
            await transcribeAndAnswer(using: fileURL)
        }
    }

    private func transcribeAndAnswer(using url: URL) async {
        let trimmed = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEndpointString: String
        if trimmed.isEmpty {
            resolvedEndpointString = ASRViewModel.defaultServerURL
            serverURLString = resolvedEndpointString
        } else {
            resolvedEndpointString = trimmed
        }

        guard let endpoint = URL(string: resolvedEndpointString) else {
            statusMessage = "Invalid ASR endpoint URL."
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let text = try await asrService.transcribe(audioURL: url, endpoint: endpoint)
            transcript = text
            statusMessage = "Transcript ready at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))."

            if shouldAutoAsk {
                await runLLM(with: text, manageProcessingFlag: false)
            }
        } catch {
            statusMessage = "ASR failed: \(error.localizedDescription)"
        }
    }

    private func runLLM(
        with prompt: String,
        manageProcessingFlag: Bool,
        systemPromptOverride: String? = nil
    ) async {
        if manageProcessingFlag {
            isProcessing = true
        }
        defer {
            if manageProcessingFlag {
                isProcessing = false
            }
        }

        do {
            let trimmedPrompt = prompt.count > maxPromptCharacters
            ? String(prompt.suffix(maxPromptCharacters))
            : prompt

            let settings = LLMSettings(
                openAIKey: openAIKey,
                model: currentModel,
                localEndpoint: URL(string: localLLMURLString),
                systemPrompt: systemPromptOverride ?? systemPrompt
            )
            let answer = try await llmService.respond(
                to: trimmedPrompt,
                provider: llmProvider,
                settings: settings
            )
            aiResponse = answer
            answerMetadata = "Answered at \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)) via \(llmProvider.shortName)."
            statusMessage = "Response ready."
        } catch {
            statusMessage = "AI failed: \(error.localizedDescription)"
        }
    }

    func prepareMicrophonePermissionIfNeeded() async {
        do {
            try await recorder.prepareMicrophonePermission()
            needsMicrophonePermission = false
        } catch {
            if let audioError = error as? AudioRecorderError {
                needsMicrophonePermission = true
                statusMessage = audioError.localizedDescription
            } else {
                statusMessage = "Microphone error: \(error.localizedDescription)"
            }
        }
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func detectLocalModels() async {
        guard let endpoint = URL(string: localLLMURLString) else {
            localDetectionMessage = "Invalid local LLM endpoint URL."
            return
        }
        isDetectingLocalModels = true
        localDetectionMessage = "Detecting local models..."
        defer { isDetectingLocalModels = false }

        do {
            let tagsURL = try makeOllamaTagsURL(from: endpoint)
            var request = URLRequest(url: tagsURL)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LLMServiceError.server(message)
            }
            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            availableLocalModels = decoded.models.map { $0.name }
            if availableLocalModels.isEmpty {
                localDetectionMessage = "Ollama responded but no models are installed."
            } else {
                localDetectionMessage = "Detected \(availableLocalModels.count) model\(availableLocalModels.count == 1 ? "" : "s")."
                if llmProvider == .local && !availableLocalModels.contains(localModelValue) {
                    currentModel = availableLocalModels[0]
                }
            }
        } catch {
            localDetectionMessage = "Detection failed: \(error.localizedDescription)"
        }
    }

    private func makeOllamaTagsURL(from endpoint: URL) throws -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.path = "/api/tags"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }

    private func autoDetectLocalModelsIfNeeded() async {
        guard availableLocalModels.isEmpty else { return }
        await detectLocalModels()
    }

    private func syncCurrentModelWithProvider() {
        switch llmProvider {
        case .openAI:
            currentModel = openAIModelValue
        case .local:
            currentModel = localModelValue
        }
    }

    private func storeCurrentModelForProvider() {
        switch llmProvider {
        case .openAI:
            openAIModelValue = currentModel
        case .local:
            localModelValue = currentModel
        }
    }

    private static func loadOpenAIKeyFromEnvironment() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let envValue = environment[openAIKeyEnvVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envValue.isEmpty {
            return envValue
        }

        var candidateFiles: [URL] = []
        if let customPath = environment[envOverridePathKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customPath.isEmpty {
            candidateFiles.append(URL(fileURLWithPath: customPath))
        }

        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(envFileName)
        candidateFiles.append(cwd)

        if let pwd = environment["PWD"] {
            candidateFiles.append(URL(fileURLWithPath: pwd).appendingPathComponent(envFileName))
        }

        if let resources = Bundle.main.resourceURL {
            candidateFiles.append(resources.appendingPathComponent(envFileName))
            candidateFiles.append(resources.deletingLastPathComponent().appendingPathComponent(envFileName))
            candidateFiles.append(resources.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(envFileName))
        }

        candidateFiles.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent(envFileName))

        for file in candidateFiles {
            if let value = parseEnv(fileURL: file, key: openAIKeyEnvVariable) {
                return value
            }
        }
        return nil
    }

    private static func parseEnv(fileURL: URL, key: String) -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }
        let commentPrefixes = ["#", "//"]
        let allowedPrefixes = ["export ", "let ", "var ", "const "]
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if commentPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
                continue
            }
            var cleaned = trimmed
            for prefix in allowedPrefixes where cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                break
            }
            let parts = cleaned.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name == key else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            guard !value.isEmpty else { continue }
            return value
        }
        return nil
    }
}

// MARK: - Services & Support Types

struct LLMSettings {
    let openAIKey: String
    let model: String
    let localEndpoint: URL?
    let systemPrompt: String
}

enum LLMProvider: String, CaseIterable, Identifiable {
    case openAI = "OpenAI GPT-4o"
    case local = "Local LLM"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .local: return "Local"
        }
    }
}

final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var silenceTimer: Timer?
    private var silenceStart: Date?
    private var autoStopHandler: ((URL?) -> Void)?
    private let silenceThreshold: Float = -45
    private let silenceMargin: Float = 10
    private let requiredSilenceDuration: TimeInterval = 1.5
    private var noiseFloor: Float?

    func prepareMicrophonePermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw AudioRecorderError.permissionDenied
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            guard granted else { throw AudioRecorderError.permissionDenied }
        @unknown default:
            throw AudioRecorderError.permissionDenied
        }
    }

    func startRecording(autoStopHandler: ((URL?) -> Void)? = nil) throws {
        try configureSession()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = autoStopHandler != nil
        recorder?.prepareToRecord()
        recorder?.record()
        currentURL = url
        self.autoStopHandler = autoStopHandler
        if autoStopHandler != nil {
            noiseFloor = nil
            silenceStart = nil
            startMonitoringSilence()
        }
    }

    func stopRecording() -> URL? {
        invalidateSilenceMonitoring()
        recorder?.stop()
        let url = currentURL
        recorder = nil
        currentURL = nil
        autoStopHandler = nil
        return url
    }

    private func configureSession() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .denied, .restricted:
            throw AudioRecorderError.permissionDenied
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                granted = allowed
                semaphore.signal()
            }
            semaphore.wait()
            guard granted else { throw AudioRecorderError.permissionDenied }
        @unknown default:
            throw AudioRecorderError.permissionDenied
        }
    }

    private func startMonitoringSilence() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.evaluateSilence()
        }
        if let timer = silenceTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func evaluateSilence() {
        guard let recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)

        if power < -25 {
            if let existingFloor = noiseFloor {
                noiseFloor = min(existingFloor, (existingFloor * 0.8) + (power * 0.2))
            } else {
                noiseFloor = power
            }
        }

        let dynamicThreshold: Float
        if let floor = noiseFloor {
            dynamicThreshold = max(silenceThreshold, floor + silenceMargin)
        } else {
            dynamicThreshold = silenceThreshold
        }

        if power < dynamicThreshold {
            if silenceStart == nil {
                silenceStart = Date()
            } else if let start = silenceStart, Date().timeIntervalSince(start) >= requiredSilenceDuration {
                triggerAutoStop()
            }
        } else {
            silenceStart = nil
        }
    }

    private func triggerAutoStop() {
        let handler = autoStopHandler
        let url = stopRecording()
        DispatchQueue.main.async {
            handler?(url)
        }
    }

    private func invalidateSilenceMonitoring() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        silenceStart = nil
        noiseFloor = nil
    }
}

struct ASRService {
    func transcribe(audioURL: URL, endpoint: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        var body = Data()
        body.appendFormField(named: "audio_file", filename: audioURL.lastPathComponent, mimeType: "audio/wav", data: audioData, boundary: boundary)
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ASRServiceError.server(message: serverMessage)
        }
        let decoded = try? JSONDecoder().decode(ASRTranscriptResponse.self, from: data)
        if let text = decoded?.bestText, !text.isEmpty {
            return text
        }
        if let fallback = String(data: data, encoding: .utf8), !fallback.isEmpty {
            return fallback
        }
        throw ASRServiceError.empty
    }
}

struct LLMService {
    func respond(to prompt: String, provider: LLMProvider, settings: LLMSettings) async throws -> String {
        switch provider {
        case .openAI:
            return try await callOpenAI(prompt: prompt, settings: settings)
        case .local:
            return try await callLocal(prompt: prompt, settings: settings)
        }
    }

    private func callOpenAI(prompt: String, settings: LLMSettings) async throws -> String {
        guard !settings.openAIKey.isEmpty else {
            throw LLMServiceError.configuration("Missing OpenAI API key")
        }
        guard !settings.model.isEmpty else {
            throw LLMServiceError.configuration("Missing OpenAI model name")
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ChatCompletionRequest(
            model: settings.model,
            messages: [
                .init(role: "system", content: settings.systemPrompt),
                .init(role: "user", content: prompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = completion.choices.first?.message.content else {
            throw LLMServiceError.empty
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callLocal(prompt: String, settings: LLMSettings) async throws -> String {
        guard let endpoint = settings.localEndpoint else {
            throw LLMServiceError.configuration("Missing local LLM endpoint")
        }
        guard !settings.model.isEmpty else {
            throw LLMServiceError.configuration("Missing local model name")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ChatCompletionRequest(
            model: settings.model,
            messages: [
                .init(role: "system", content: settings.systemPrompt),
                .init(role: "user", content: prompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let text = completion.choices.first?.message.content else {
            throw LLMServiceError.empty
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown"
            throw LLMServiceError.server(message)
        }
    }
}

struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
}

struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }
        let index: Int
        let message: Message
    }

    let choices: [Choice]
}

struct ASRTranscriptResponse: Decodable {
    let text: String?
    let transcript: String?
    let result: String?
    let message: String?
    let detail: String?

    var bestText: String? {
        return text ?? transcript ?? result ?? detail ?? message
    }
}

struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }
    let models: [Model]
}

extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendFormField(named name: String,
                                  filename: String,
                                  mimeType: String,
                                  data: Data,
                                  boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}

enum ASRServiceError: LocalizedError {
    case server(message: String)
    case empty

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return "ASR server error: \(message)"
        case .empty:
            return "ASR server returned no transcript."
        }
    }
}

enum LLMServiceError: LocalizedError {
    case server(String)
    case configuration(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return "LLM server error: \(message)"
        case .configuration(let detail):
            return detail
        case .empty:
            return "LLM response did not include any text."
        }
    }
}

enum AudioRecorderError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied. Enable it in System Settings ▸ Privacy & Security ▸ Microphone."
        }
    }
}

enum ScreenTextScannerError: LocalizedError {
    case captureFailed
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "Unable to capture the screen. Ensure screen recording permissions are granted."
        case .recognitionFailed:
            return "No text could be recognized from the captured screen area."
        }
    }
}

private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}

@MainActor
struct ScreenTextScanner {
    static func captureFullScreenText() async throws -> String {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw ScreenTextScannerError.captureFailed
        }

        var aggregated: [String] = []
        for screen in screens {
            let image = try await captureImage(for: screen)
            let text = try await recognizeText(in: image)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                aggregated.append(trimmed)
            }
        }

        guard !aggregated.isEmpty else {
            throw ScreenTextScannerError.recognitionFailed
        }
        return aggregated.joined(separator: "\n")
    }

    private static func captureImage(for screen: NSScreen) async throws -> CGImage {
        let captureRect = CGRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: screen.frame.height
        )

        return try await withCheckedThrowingContinuation { continuation in
            if #available(macOS 15.2, *) {
                SCScreenshotManager.captureImage(in: captureRect) { image, error in
                    if let image = image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: error ?? ScreenTextScannerError.captureFailed)
                    }
                }
            } else {
                continuation.resume(throwing: ScreenTextScannerError.captureFailed)
            }
        }
    }

    private static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: ScreenTextScannerError.recognitionFailed)
                    return
                }
                let recognizedStrings = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !recognizedStrings.isEmpty else {
                    continuation.resume(throwing: ScreenTextScannerError.recognitionFailed)
                    return
                }
                continuation.resume(returning: recognizedStrings.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.01

            let handler = UncheckedSendableBox(value: VNImageRequestHandler(cgImage: image, options: [:]))
            let requestBox = UncheckedSendableBox(value: request)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.value.perform([requestBox.value])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

struct PermissionBanner: View {
    let requestAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Microphone access is required before recording.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            HStack {
                Button("Request Permission Again", action: requestAction)
                Button("Open Settings", action: settingsAction)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct SettingField<Content: View>: View {
    let label: String
    @ViewBuilder var field: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.field = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            field()
        }
    }
}

struct SectionDivider: View {
    var body: some View {
        Divider()
            .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
            .foregroundStyle(color)
    }
}

struct ResponsiveStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(spacing: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        ViewThatFits {
            HStack(alignment: .top, spacing: spacing) {
                content()
            }
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
        }
    }
}

extension ContentView {
    private func registerKeyboardShortcuts() {
        guard keyboardShortcutMonitor == nil, globalKeyboardShortcutMonitor == nil else { return }

        keyboardShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyboardShortcut(event) ? nil : event
        }

        globalKeyboardShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            DispatchQueue.main.async {
                _ = handleKeyboardShortcut(event)
            }
        }
    }

    private func removeKeyboardShortcuts() {
        if let monitor = keyboardShortcutMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardShortcutMonitor = nil
        }
        if let monitor = globalKeyboardShortcutMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyboardShortcutMonitor = nil
        }
    }

    private func handleKeyboardShortcut(_ event: NSEvent) -> Bool {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifierFlags.contains(.command),
              !event.isARepeat,
              let character = event.charactersIgnoringModifiers?.lowercased().first else {
            return false
        }
        switch character {
        case "d":
            viewModel.toggleRecording()
            return true
        case "h":
            toggleOverlayVisibility()
            return true
        default:
            return false
        }
    }

    private func refreshLayout() {
        let screen = OverlayWindowManager.shared.overlayScreen ?? NSScreen.main
        layout = CoachOverlayLayout.preferred(for: screen)
    }

    private func toggleOverlayVisibility() {
        OverlayWindowManager.shared.toggleOverlayVisibility()
    }

    private func configureWindow() {
        guard let window = OverlayWindowManager.shared.registerOverlayWindowIfNeeded(NSApplication.shared.windows.first) else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.sharingType = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        OverlayWindowManager.shared.registerOverlayWindowIfNeeded(window)
    }
}

#Preview {
    ContentView()
        .frame(width: 1024, height: 768)
}

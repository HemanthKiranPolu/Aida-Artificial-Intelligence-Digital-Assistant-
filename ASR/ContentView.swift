import SwiftUI
import AVFoundation
import AppKit
import Combine

struct ContentView: View {
    @StateObject private var viewModel = ASRViewModel()
    @State private var showAdvancedSettings = false
    @State private var showDeploymentNotes = false
    @State private var transcriptEditorHeight: CGFloat = 140
    @State private var commandDShortcutMonitor: Any?

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 12) {
                heroBar
                if viewModel.needsMicrophonePermission {
                    PermissionBanner(
                        requestAction: { Task { await viewModel.prepareMicrophonePermissionIfNeeded() } },
                        settingsAction: viewModel.openMicrophoneSettings
                    )
                }
                commandBar
                transcriptPanel
                answerPanel
            }
            .padding(16)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .shadow(color: Color.black.opacity(0.45), radius: 40, x: 0, y: 18)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .fixedSize()
        }
        .background(Color.clear)
        .onAppear {
            configureWindow()
            registerCommandDShortcut()
        }
        .onDisappear(perform: removeCommandDShortcut)
        .sheet(isPresented: $showAdvancedSettings) {
            AdvancedSettingsView(viewModel: viewModel, showDeploymentNotes: $showDeploymentNotes)
                .frame(minWidth: 520, minHeight: 480)
        }
        .task {
            await viewModel.prepareMicrophonePermissionIfNeeded()
        }
    }

    private var heroBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("AIDA", systemImage: "sparkles.tv")
                    .font(.title3.weight(.semibold))
                    .padding(.trailing, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.isRecording ? "Listening…" : "Ready")
                        .font(.subheadline.weight(.semibold))
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(viewModel.recordingDuration(until: context.date))
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.black.opacity(0.2))
                        )
                }

                if viewModel.isRecording {
                    StatusBadge(text: "Listening", color: .red)
                } else if viewModel.isProcessing {
                    StatusBadge(text: "Processing", color: .orange)
                } else {
                    StatusBadge(text: "Idle", color: .green)
                }
            }

            HStack(spacing: 6) {
                Picker("LLM Provider", selection: $viewModel.llmProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.shortName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                TextField(viewModel.llmProvider == .openAI ? "Model (e.g. gpt-4o-mini)" : "Local model (e.g. llama3)", text: $viewModel.currentModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity)

                Button {
                    showAdvancedSettings = true
                } label: {
                    Label("Models & Settings", systemImage: "slider.horizontal.3")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
    }

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: viewModel.toggleRecording) {
                    Label(viewModel.isRecording ? "Stop Listening" : "Start Listening",
                          systemImage: viewModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .fontWeight(.semibold)
                }
                .keyboardShortcut(.space)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Button(action: { Task { await viewModel.askAIManually() } }) {
                    Label("Answer Question", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isProcessing)

                Button(action: viewModel.clearWorkspace) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.06))
        )
    }

    private var transcriptPanel: some View {
        SectionBox(title: "Live Transcript (editable)") {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.transcript)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(height: transcriptEditorHeight)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

                    if viewModel.transcript.isEmpty {
                        Text("Start speaking or type here...")
                            .foregroundStyle(Color.white.opacity(0.4))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    AutoHeightReader(text: viewModel.transcript,
                                     font: .system(.body, design: .monospaced),
                                     minHeight: 38,
                                     maxHeight: 70,
                                     height: $transcriptEditorHeight)
                )

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
                }
            }
        }
    }

    private var answerPanel: some View {
        SectionBox(title: "Answer Workspace") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(viewModel.aiResponse.isEmpty ? "Answer text will render here as soon as AI responds." : viewModel.aiResponse)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
                }
                .frame(height: min(180, max(120, dynamicHeight(for: viewModel.aiResponse))))

                HStack {
                    Text(viewModel.answerMetadata)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.aiResponse, forType: .string)
                    } label: {
                        Label("Copy Answer", systemImage: "doc.on.doc")
                    }
                    .disabled(viewModel.aiResponse.isEmpty)
                }
            }
        }
    }

    private var settingsDrawer: some View {
        EmptyView()
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
    @Published var systemPrompt: String = "You are an expert AI that answers clearly and concisely."
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

    init() {
        defaults.register(defaults: [Self.serverDefaultsKey: Self.defaultServerURL])
        serverURLString = defaults.string(forKey: Self.serverDefaultsKey) ?? Self.defaultServerURL
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

    private func runLLM(with prompt: String, manageProcessingFlag: Bool) async {
        if manageProcessingFlag {
            isProcessing = true
        }
        defer {
            if manageProcessingFlag {
                isProcessing = false
            }
        }

        do {
            let settings = LLMSettings(
                openAIKey: openAIKey,
                model: currentModel,
                localEndpoint: URL(string: localLLMURLString),
                systemPrompt: systemPrompt
            )
            let answer = try await llmService.respond(
                to: prompt,
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
    private let requiredSilenceDuration: TimeInterval = 1.5

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
        if power < silenceThreshold {
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

struct SectionBox<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 8)
        )
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

struct AutoHeightReader: View {
    let text: String
    let font: Font
    let minHeight: CGFloat
    let maxHeight: CGFloat
    @Binding var height: CGFloat

    var body: some View {
        Text(text.isEmpty ? " " : text + "\n")
            .font(font)
            .foregroundColor(.clear)
            .padding(.horizontal, 12)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            height = clampHeight(proxy.size.height)
                        }
                        .onChange(of: proxy.size.height) { _, newValue in
                            height = clampHeight(newValue)
                        }
                }
            )
    }

    private func clampHeight(_ raw: CGFloat) -> CGFloat {
        min(maxHeight, max(minHeight, raw + 24))
    }
}

private func dynamicHeight(for text: String) -> CGFloat {
    let charactersPerLine: Double = 70
    let lines = max(1, ceil(Double(max(1, text.count)) / charactersPerLine))
    let height = lines * 28
    return CGFloat(min(320, max(120, height)))
}

extension ContentView {
    private func registerCommandDShortcut() {
        guard commandDShortcutMonitor == nil else { return }
        commandDShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifierFlags.contains(.command),
                  !event.isARepeat,
                  event.charactersIgnoringModifiers?.lowercased() == "d" else {
                return event
            }
            viewModel.toggleRecording()
            return nil
        }
    }

    private func removeCommandDShortcut() {
        guard let monitor = commandDShortcutMonitor else { return }
        NSEvent.removeMonitor(monitor)
        commandDShortcutMonitor = nil
    }

    private func configureWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}

#Preview {
    ContentView()
        .frame(width: 1024, height: 768)
}

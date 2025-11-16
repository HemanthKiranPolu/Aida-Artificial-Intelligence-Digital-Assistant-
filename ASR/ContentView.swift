import SwiftUI
import AVFoundation
import AppKit
import Combine

struct ContentView: View {
    @StateObject private var viewModel = ASRViewModel()

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .top, spacing: 24) {
                captureSection
                settingsSection
            }
            resultsSection
            architectureSection
        }
        .padding(24)
        .frame(minWidth: 960, minHeight: 680)
        .task {
            await viewModel.prepareMicrophonePermissionIfNeeded()
        }
    }

    private var captureSection: some View {
        SectionBox(title: "Capture & Transcribe") {
            if viewModel.needsMicrophonePermission {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Microphone access is required before recording.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    HStack {
                        Button("Request Permission Again") {
                            Task { await viewModel.prepareMicrophonePermissionIfNeeded() }
                        }
                        Button("Open Settings") {
                            viewModel.openMicrophoneSettings()
                        }
                    }
                }
            }

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: viewModel.toggleRecording) {
                    Label(viewModel.isRecording ? "Stop Recording" : "Start Recording",
                          systemImage: viewModel.isRecording ? "stop.circle" : "mic.circle")
                }
                .keyboardShortcut(.space)
                .buttonStyle(.borderedProminent)

                Button(action: {
                    Task { await viewModel.askAIManually() }
                }) {
                    Label("Ask AI Again", systemImage: "bolt.horizontal.circle")
                }
                .disabled(viewModel.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isProcessing)
            }

            Toggle("Ask AI automatically after every transcription", isOn: $viewModel.shouldAutoAsk)

            if viewModel.isProcessing {
                ProgressView("Processing audio / AI...")
            }
        }
    }

    private var settingsSection: some View {
        SectionBox(title: "Backend Settings") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Parakeet / ASR endpoint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("http://127.0.0.1:8000/transcribe", text: $viewModel.serverURLString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Picker("LLM Provider", selection: $viewModel.llmProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(viewModel.llmProvider == .openAI ? "gpt-4o-mini" : "llama3", text: $viewModel.currentModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                if viewModel.llmProvider == .openAI {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenAI API key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("sk-...", text: $viewModel.openAIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local LLM endpoint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("http://127.0.0.1:11434/v1/chat/completions", text: $viewModel.localLLMURLString)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack(spacing: 12) {
                        Button {
                            Task { await viewModel.detectLocalModels() }
                        } label: {
                            Label("Detect Local Models", systemImage: "waveform.badge.mic")
                        }
                        .disabled(viewModel.isDetectingLocalModels)

                        if viewModel.isDetectingLocalModels {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if viewModel.llmProvider == .local && !viewModel.availableLocalModels.isEmpty {
                            Menu("Choose detected model") {
                                ForEach(viewModel.availableLocalModels, id: \.self) { model in
                                    Button(model) { viewModel.currentModel = model }
                                }
                            }
                        }
                    }
                    if !viewModel.localDetectionMessage.isEmpty {
                        Text(viewModel.localDetectionMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("System prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $viewModel.systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 90)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).stroke(.tertiary, lineWidth: 1))
                }
            }
        }
    }

    private var resultsSection: some View {
        HStack(alignment: .top, spacing: 24) {
            SectionBox(title: "Latest Transcript") {
                TextEditor(text: $viewModel.transcript)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quinary, lineWidth: 1))
                HStack {
                    Text("Characters: \(viewModel.transcript.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.transcript, forType: .string)
                    }
                    .disabled(viewModel.transcript.isEmpty)
                }
            }

            SectionBox(title: "AI Answer") {
                TextEditor(text: $viewModel.aiResponse)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quinary, lineWidth: 1))
                HStack {
                    Text(viewModel.answerMetadata)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.aiResponse, forType: .string)
                    }
                    .disabled(viewModel.aiResponse.isEmpty)
                }
            }
        }
    }

    private var architectureSection: some View {
        SectionBox(title: "Deployment Notes") {
            VStack(alignment: .leading, spacing: 12) {
                Label("Run NVIDIA Parakeet locally with \"parakeet-tdt-0.6b-v2\" for < 1 s latency.", systemImage: "waveform")
                    .font(.callout)
                Text("Example: `uvicorn parakeet_fastapi.server:app --reload --host 0.0.0.0 --port 8000` after downloading model checkpoints.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("Configure a GPU-backed box or your Mac's AVFoundation pipeline for recording.", systemImage: "display.and.arrow.down")
                    .font(.callout)

                Label("Forward transcripts to GPT-4o or a local llama.cpp / Ollama endpoint.", systemImage: "brain.head.profile")
                    .font(.callout)

                Label("Optional: swap the ASR endpoint with FluidAudio/CoreML for a fully on-device Apple Silicon path.", systemImage: "cpu")
                    .font(.callout)

                Text("Set the endpoints above according to where your ASR FastAPI + LLM services run. This app never leaves your machine unless you point it to a remote host.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
    @Published var transcript: String = ""
    @Published var aiResponse: String = ""
    @Published var statusMessage: String = "Idle"
    @Published var answerMetadata: String = ""
    @Published var isProcessing = false
    @Published var needsMicrophonePermission = false

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

    private func startRecording() {
        do {
            try recorder.startRecording()
            transcript = ""
            aiResponse = ""
            answerMetadata = ""
            isRecording = true
            statusMessage = "Recording... Tap stop to send to ASR."
            needsMicrophonePermission = false
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
            return
        }
        isRecording = false
        statusMessage = "Uploading audio to ASR..."
        Task {
            await transcribeAndAnswer(using: fileURL)
        }
    }

    private func transcribeAndAnswer(using url: URL) async {
        guard let endpoint = URL(string: serverURLString) else {
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

    func startRecording() throws {
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
        recorder?.prepareToRecord()
        recorder?.record()
        currentURL = url
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        let url = currentURL
        recorder = nil
        currentURL = nil
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
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
        )
    }
}

#Preview {
    ContentView()
        .frame(width: 1024, height: 768)
}

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var viewModel: ASRViewModel
    @Binding var showDeploymentNotes: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Models & Backend Settings")
                .font(.title2.weight(.semibold))

            Picker("LLM Provider", selection: $viewModel.llmProvider) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Auto ask AI", isOn: $viewModel.shouldAutoAsk)
                .toggleStyle(.switch)

            Toggle("Auto stop on silence", isOn: $viewModel.autoStopOnSilence)
                .toggleStyle(.switch)
                .tint(.orange)

            SectionDivider()

            SettingField("Parakeet endpoint") {
                TextField("http://127.0.0.1:8000/transcribe", text: $viewModel.serverURLString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            if viewModel.llmProvider == .openAI {
                SettingField("OpenAI API key") {
                    SecureField("sk-...", text: $viewModel.openAIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            } else {
                SettingField("Local LLM endpoint") {
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
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isDetectingLocalModels)

                    if viewModel.isDetectingLocalModels {
                        ProgressView().scaleEffect(0.8)
                    } else if !viewModel.availableLocalModels.isEmpty {
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

            SectionDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("System prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $viewModel.systemPrompt)
                    .frame(height: 140)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(.tertiary, lineWidth: 1))
                    .font(.system(.body, design: .monospaced))
            }

            SectionDivider()

            DisclosureGroup(isExpanded: $showDeploymentNotes) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Run NVIDIA Parakeet locally with \"parakeet-tdt-0.6b-v2\" for < 1 s latency.", systemImage: "waveform")
                    Text("Example: uvicorn parakeet_fastapi.server:app --host 0.0.0.0 --port 8000 --reload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("Configure a GPU-backed box or your Mac's AVFoundation pipeline for recording.", systemImage: "display.and.arrow.down")
                    Label("Forward transcripts to GPT-4o or a local llama.cpp / Ollama endpoint.", systemImage: "brain.head.profile")
                    Label("Optional: swap the ASR endpoint with FluidAudio/CoreML for a fully on-device Apple Silicon path.", systemImage: "cpu")
                }
                .padding(.top, 8)
            } label: {
                Text("Deployment Tips")
                    .font(.headline)
            }

            Spacer()
        }
        .padding(24)
    }
}

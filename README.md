# ASR macOS Client

A SwiftUI macOS desktop companion that captures microphone audio with `AVAudioRecorder`, posts it to an ultra-fast local NVIDIA Parakeet server (parakeet-tdt-0.6b-v2 FastAPI), and immediately routes transcripts into GPT-4o or a local llama.cpp / Ollama endpoint for full AI answers. The entire loop can run on your Mac with <1 s ASR latency when the backend is hosted on a modern NVIDIA GPU.

## Architecture

```
┌──────────────┐      WAV upload        ┌─────────────────────────────────────────────┐
│ SwiftUI App │ ──────────────────────▶ │ FastAPI + Parakeet TDT 0.6B v2 (GPU server) │
└─────┬────────┘                       └─────────────────────────────────────────────┘
      │ transcript JSON                                     │
      │                                                     ▼
      │                               ┌─────────────────────────────────────────────┐
      └──────────────────────────────▶│ GPT-4o API (OpenAI) or Local Llama/Ollama   │
                                      └─────────────────────────────────────────────┘
```
- Audio capture uses 16 kHz mono PCM for minimal upload size.
- ASR requests are standard multipart/form-data posts for easy FastAPI integration.
- LLM calls share the OpenAI Chat Completions schema so GPT-4o and local runtimes can be swapped freely.

## Backend: NVIDIA Parakeet FastAPI

1. **Environment** – Use a Linux/macOS host with an RTX 30/40 series or newer NVIDIA GPU. Install CUDA 12+, Python 3.10+, and FFmpeg.
2. **Create a Python env + install NeMo + API deps**
   ```bash
   python3 -m venv nemo-env
   source nemo-env/bin/activate
   python -m pip install --upgrade pip
   pip install "nemo-toolkit[asr]" fastapi "uvicorn[standard]"
   ```
3. **Download the Parakeet weights (2.3 GB)**
   ```bash
   mkdir -p models/parakeet
   curl -L https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2/resolve/main/parakeet-tdt-0.6b-v2.nemo \
        -o models/parakeet/parakeet-tdt-0.6b-v2.nemo
   ```
4. **Launch the FastAPI bridge**
   ```bash
   ./scripts/run_parakeet_server.sh
   ```
   - The script activates `nemo-env`, exports `MODEL_PATH` (override with your own path if desired), and starts uvicorn on `0.0.0.0:8000`. Override `HOST`/`PORT`/`MODEL_PATH` via env vars.
5. **Verify connectivity**
   ```bash
   curl http://127.0.0.1:8000/healthz
   curl -F "audio_file=@sample.wav" http://127.0.0.1:8000/transcribe
   ```
   A healthy server responds with `{"status":"ready","device":"cuda"}` (or `cpu` if you’re running without a GPU). The `/transcribe` endpoint returns JSON with a `text` field for your clip.

### Keep the backend running automatically

Install the provided launch agent once and macOS will boot the FastAPI server at login:

```bash
./scripts/manage_parakeet_service.sh install   # start now + on future logins
./scripts/manage_parakeet_service.sh status    # view launchctl state
./scripts/manage_parakeet_service.sh restart   # reload after edits
./scripts/manage_parakeet_service.sh uninstall # stop + remove the agent
```

The generated plist lives at `~/Library/LaunchAgents/com.hemanth.parakeet.plist` and logs stream into `/tmp/parakeet.log`.

> Tip: Want everything on the laptop? Swap the endpoint with FluidAudio/CoreML for an Apple-Silicon-only pipeline—just expose the same `/transcribe` contract.

## AI Question Answering

- **OpenAI GPT-4o** – Provide an `sk-` key, keep the default `gpt-4o-mini` model, and let the client stream requests to https://api.openai.com/v1/chat/completions.
- **Local LLM** – Point to Ollama (`http://127.0.0.1:11434/v1/chat/completions`) or llama.cpp's OpenAI-compatible server. Set the model name (`llama3`, `mistral`, etc.) in the UI. Hit **Detect Local Models** in the app to auto-fill any installed Ollama tags.
- **System Prompt** – Tune tone/behavior per workflow; the default keeps answers concise.

## macOS Client Setup

1. Open `ASR.xcodeproj` in Xcode 15+ on macOS 15 (Sequoia) or newer.
2. Ensure your signing team is selected so the hardened runtime build succeeds.
3. Build & run (`Cmd+R`). The first run will prompt for microphone permission (declared via `NSMicrophoneUsageDescription`).
4. Configure endpoints in the **Backend Settings** panel:
   - Parakeet URL (e.g., `http://192.168.1.10:8000/transcribe`).
   - Choose `OpenAI GPT-4o` or `Local LLM`, enter model names, keys, and local endpoints as needed.
5. Hit **Start Recording**. When you stop, the audio uploads to Parakeet, the transcript populates, and (optionally) the AI answer shows instantly.

## Optional Enhancements

- Enable "Ask AI automatically…" to keep meetings summarized in real time.
- Use the copy buttons to drop transcripts/answers into notes or ticketing tools.
- Extend `LLMService` with streaming if you need token-by-token UI updates.
- Wire the AI response to macOS TTS (AVSpeechSynthesizer) for a hands-free experience.

## Troubleshooting

- **Recording fails immediately** – Confirm macOS granted microphone access (`System Settings > Privacy & Security > Microphone`).
- **ASR errors** – Inspect the FastAPI logs. The client displays the raw server error string when HTTP status ≥400.
- **LLM errors** – Double-check the API key, endpoint URL, and model name; all are validated before calls.
- **High latency** – Run the Parakeet server as close to the client as possible (same machine via eGPU or LAN with >1 Gbps links). Reduce sample rate/duration as needed.

With Parakeet delivering ultra-fast transcripts and GPT/local LLMs supplying contextual answers, this macOS client becomes a powerful cockpit for meetings, dictation, and on-prem privacy-sensitive workflows.

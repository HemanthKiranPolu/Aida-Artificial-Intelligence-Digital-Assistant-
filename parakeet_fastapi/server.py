import os
import tempfile
from typing import Any, Optional

import torch
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from nemo.collections.asr.models import ASRModel

_model: Optional[ASRModel] = None
_device: str = "cpu"


def _load_model() -> None:
    """Lazily load the Parakeet ASR model from MODEL_PATH."""
    global _model, _device
    if _model is not None:
        return

    model_path = os.environ.get("MODEL_PATH")
    if not model_path:
        raise RuntimeError("MODEL_PATH environment variable is not set.")
    if not os.path.exists(model_path):
        raise RuntimeError(f"MODEL_PATH does not exist: {model_path}")

    _device = "cuda" if torch.cuda.is_available() else "cpu"
    _model = ASRModel.restore_from(restore_path=model_path, map_location=_device)
    _model.eval()
    if _device == "cuda":
        _model = _model.to(_device)


async def _transcribe(upload: UploadFile) -> str:
    if upload.content_type and not upload.content_type.startswith("audio"):
        raise HTTPException(status_code=400, detail="Invalid content type. Expected audio/*.")

    payload = await upload.read()
    if not payload:
        raise HTTPException(status_code=400, detail="Uploaded file is empty.")

    suffix = os.path.splitext(upload.filename or "audio.wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(payload)
        tmp.flush()
        temp_path = tmp.name

    try:
        assert _model is not None
        predictions = _model.transcribe([temp_path])
    finally:
        try:
            os.remove(temp_path)
        except FileNotFoundError:
            pass

    if not predictions:
        raise HTTPException(status_code=500, detail="ASR model returned no predictions.")

    return _coerce_prediction(predictions[0])


def _coerce_prediction(prediction: Any) -> str:
    """Convert NeMo prediction objects (Hypothesis/dicts/etc.) into plain text."""
    if isinstance(prediction, str):
        return prediction.strip()

    if isinstance(prediction, (list, tuple)):
        for item in prediction:
            text = _coerce_prediction(item)
            if text:
                return text
        return ""

    if isinstance(prediction, dict):
        for key in ("text", "transcript", "transcription", "result", "message", "detail"):
            value = prediction.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()

    text_attr = getattr(prediction, "text", None)
    if isinstance(text_attr, str):
        return text_attr.strip()

    return str(prediction).strip()


def create_app() -> FastAPI:
    app = FastAPI(
        title="Parakeet FastAPI Bridge",
        description="Multipart upload endpoint exposing NVIDIA Parakeet ASR.",
        version="1.0.0",
    )

    @app.on_event("startup")
    async def startup_event() -> None:  # noqa: D401
        _load_model()

    @app.get("/healthz")
    async def health_check() -> JSONResponse:
        status = "ready" if _model is not None else "loading"
        return JSONResponse({"status": status, "device": _device})

    @app.post("/transcribe")
    async def transcribe(audio_file: UploadFile = File(...)) -> JSONResponse:
        if _model is None:
            _load_model()
        text = await _transcribe(audio_file)
        return JSONResponse({"text": text})

    return app


# Allow running without --factory for convenience.
app = create_app()

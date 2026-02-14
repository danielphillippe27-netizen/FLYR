"""
FastAPI server for fast transcription using faster-whisper.
POST /v1/transcribe: multipart audio, returns transcript (optional segments).
GET /health: liveness.
"""
import os
import tempfile
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from pydantic import BaseModel

from app.transcribe import ALLOWED_MODELS, get_model, transcribe_file

app = FastAPI(title="Transcription API", version="1.0.0")


@app.on_event("startup")
def startup():
    """Load default model once at startup so first request is fast."""
    try:
        get_model(model_size="small")
        print("Whisper model loaded (small, default)")
    except Exception as e:
        print(f"Startup model load failed (will load on first request): {e}")

TRANSCRIBE_API_KEY = os.environ.get("TRANSCRIBE_API_KEY", "")
MAX_UPLOAD_BYTES = int(os.environ.get("MAX_UPLOAD_BYTES", 50 * 1024 * 1024))  # 50MB


class TranscribeResponse(BaseModel):
    language: str
    duration_sec: float
    text: str
    segments: list[dict]  # [{"start": float, "end": float, "text": str}]


def _require_api_key(x_api_key: str | None = Header(None, alias="X-API-Key")) -> None:
    if not TRANSCRIBE_API_KEY:
        raise HTTPException(status_code=500, detail="Server missing TRANSCRIBE_API_KEY")
    if not x_api_key or x_api_key != TRANSCRIBE_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing X-API-Key")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/v1/transcribe", response_model=TranscribeResponse)
async def transcribe(
    file: UploadFile = File(..., description="Audio file (m4a/mp3/wav)"),
    language: str | None = Form(None, description="Language code e.g. en, or auto"),
    model: str = Form("small", description="base|small|medium|large-v3"),
    timestamps: bool = Form(False, description="Include segment timestamps"),
    x_api_key: str | None = Header(None, alias="X-API-Key"),
):
    _require_api_key(x_api_key)

    if model not in ALLOWED_MODELS:
        raise HTTPException(
            status_code=400,
            detail=f"model must be one of {list(ALLOWED_MODELS)}",
        )

    request_id = str(uuid.uuid4())[:8]
    filename = file.filename or "audio"
    start = time.perf_counter()

    try:
        content = await file.read()
    except Exception as e:
        print(f"[{request_id}] read error: {e}")
        raise HTTPException(status_code=400, detail="Failed to read upload")

    size = len(content)
    if size > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"File too large (max {MAX_UPLOAD_BYTES // (1024*1024)}MB)",
        )

    suffix = Path(filename).suffix or ".bin"
    if suffix not in (".m4a", ".mp3", ".wav", ".webm", ".ogg", ".flac", ".bin"):
        suffix = ".bin"

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix, dir="/tmp") as f:
            f.write(content)
            tmp_path = f.name

        lang_param = (language or "").strip() or None
        text, detected_lang, duration_sec, segments = transcribe_file(
            tmp_path,
            language=lang_param,
            model_size=model,
            include_timestamps=timestamps,
        )
        elapsed = time.perf_counter() - start
        # Log request id, filename, size, model, elapsed
        print(
            f"[{request_id}] filename={filename!r} size={size} model={model} "
            f"elapsed_sec={elapsed:.2f} duration_sec={duration_sec:.2f}"
        )
        return {
            "language": detected_lang or "en",
            "duration_sec": round(duration_sec, 2),
            "text": text,
            "segments": segments,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        print(f"[{request_id}] transcribe error: {e}")
        raise HTTPException(status_code=500, detail="Transcription failed")
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

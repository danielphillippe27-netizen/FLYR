"""
faster-whisper wrapper with singleton model loading.
Load model once at startup, reuse across requests with a lock.
"""
import os
import threading
from typing import Optional

from faster_whisper import WhisperModel

ALLOWED_MODELS = ("base", "small", "medium", "large-v2", "large-v3")

_model: Optional[WhisperModel] = None
_model_lock = threading.Lock()
_loaded_model_name: Optional[str] = None
_loaded_device: Optional[str] = None
_loaded_compute_type: Optional[str] = None


def get_model(
    model_size: str = "small",
    device: Optional[str] = None,
    compute_type: Optional[str] = None,
) -> WhisperModel:
    """Return singleton WhisperModel. Load once, reuse. Thread-safe."""
    global _model, _loaded_model_name, _loaded_device, _loaded_compute_type

    if model_size not in ALLOWED_MODELS:
        raise ValueError(f"model must be one of {ALLOWED_MODELS}, got {model_size!r}")

    device = device or os.environ.get("WHISPER_DEVICE", "cpu")
    if device == "cuda":
        compute_type = compute_type or os.environ.get("WHISPER_COMPUTE_TYPE", "float16")
    else:
        compute_type = compute_type or os.environ.get("WHISPER_COMPUTE_TYPE", "int8")

    with _model_lock:
        if (
            _model is None
            or _loaded_model_name != model_size
            or _loaded_device != device
            or _loaded_compute_type != compute_type
        ):
            _model = WhisperModel(
                model_size,
                device=device,
                compute_type=compute_type,
            )
            _loaded_model_name = model_size
            _loaded_device = device
            _loaded_compute_type = compute_type
        return _model


def transcribe_file(
    path: str,
    language: Optional[str] = None,
    model_size: str = "small",
    include_timestamps: bool = False,
) -> tuple[str, Optional[str], float, list[dict]]:
    """
    Transcribe audio file. Returns (text, detected_language, duration_sec, segments).
    segments are [{"start": float, "end": float, "text": str}] if include_timestamps else [].
    """
    model = get_model(model_size=model_size)
    segments_iter, info = model.transcribe(
        path,
        language=language,
        vad_filter=True,
        vad_parameters=dict(min_silence_duration_ms=300, speech_pad_ms=100),
    )
    segments_list = list(segments_iter)
    text = " ".join(s.text for s in segments_list).strip()
    duration_sec = getattr(info, "duration", None)
    if duration_sec is None and segments_list:
        duration_sec = segments_list[-1].end
    duration_sec = float(duration_sec or 0.0)
    detected = info.language
    if include_timestamps:
        segments = [
            {"start": s.start, "end": s.end, "text": (s.text or "").strip()}
            for s in segments_list
        ]
    else:
        segments = []
    return text, detected, duration_sec, segments

# Transcription API: faster-whisper + FastAPI
# CPU by default. For GPU, see README (nvidia/cuda base + runtime).
FROM python:3.11-slim

WORKDIR /app

# Install system deps for audio (optional but useful)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

# Transcription API (faster-whisper)

FastAPI server that transcribes audio using [faster-whisper](https://github.com/SYSTRAN/faster-whisper). Single model loaded at startup, VAD to skip silence. Supports CPU (int8) and GPU (float16).

## Run locally

```bash
cd backend
cp .env.example .env
# Edit .env and set TRANSCRIBE_API_KEY=your-secret

python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- Health: [http://localhost:8000/health](http://localhost:8000/health)
- Transcribe: `POST http://localhost:8000/v1/transcribe` (multipart, see below)

## Run with Docker (CPU)

```bash
cd backend
cp .env.example .env
# Set TRANSCRIBE_API_KEY in .env

docker build -t transcription-api .
docker run --env-file .env -p 8000:8000 transcription-api
```

## Run with Docker Compose (local dev)

```bash
cd backend
cp .env.example .env
# Set TRANSCRIBE_API_KEY in .env

docker-compose up --build
```

## GPU (CUDA)

The Dockerfile above is CPU-only. For GPU:

1. Use a CUDA base image and install Python + deps, e.g.:
   - `nvidia/cuda:12.2.0-runtime-ubuntu22.04` and install python3.11, pip, ffmpeg, then pip install -r requirements.txt (and ensure faster-whisper can see CUDA).
   - Or use an image that already has Python + CUDA (e.g. `nvidia/cuda:12.2.0-runtime-ubuntu22.04` with python installed).

2. Run with NVIDIA runtime:
   ```bash
   docker run --gpus all --env-file .env -e WHISPER_DEVICE=cuda -e WHISPER_COMPUTE_TYPE=float16 -p 8000:8000 your-image
   ```

3. Set in env: `WHISPER_DEVICE=cuda`, `WHISPER_COMPUTE_TYPE=float16`.

No Dockerfile change is required for CPU; for GPU you can add a second stage or a separate Dockerfile.gpu if you prefer.

## API

### POST /v1/transcribe

- **Headers:** `X-API-Key: <TRANSCRIBE_API_KEY>`
- **Body:** multipart/form-data
  - `file` (required): audio file (m4a, mp3, wav, etc.)
  - `language` (optional): e.g. `en`; omit for auto-detect
  - `model` (optional): `base` | `small` | `medium` | `large-v3`, default `small`
  - `timestamps` (optional): `true` | `false`, default `false`

**Response (200):**

```json
{
  "language": "en",
  "duration_sec": 12.34,
  "text": "full transcript...",
  "segments": [{"start": 0.0, "end": 2.3, "text": "..."}]
}
```

`segments` is only present when `timestamps=true`. Max upload size default 50MB (configurable via `MAX_UPLOAD_BYTES`).

### GET /health

Returns 200 and `{"status": "ok"}`.

## iOS: upload audio and get transcript

```swift
import Foundation

func transcribeAudio(url: URL, apiBaseURL: String, apiKey: String) async throws -> String {
    let endpoint = URL(string: "\(apiBaseURL)/v1/transcribe")!
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

    let boundary = "Boundary-\(UUID().uuidString)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    let data = try Data(contentsOf: url)
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
    body.append(data)
    body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    request.httpBody = body

    let (responseData, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw NSError(domain: "Transcribe", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: String(data: responseData, encoding: .utf8) ?? "Unknown error"])
    }

    struct Transcript: Decodable { let text: String }
    let decoded = try JSONDecoder().decode(Transcript.self, from: responseData)
    return decoded.text
}

// Usage (e.g. from a recording URL):
// let text = try await transcribeAudio(url: audioFileURL, apiBaseURL: "http://localhost:8000", apiKey: "your-secret-key")
// print(text)
```

Use your backend URL (e.g. `https://your-api.example.com`) and the same value as `TRANSCRIBE_API_KEY` for `apiKey`.

# Transcription API (OpenAI Whisper + gpt-4o-mini)

Node proxy that transcribes audio via OpenAI Whisper and summarizes via gpt-4o-mini. **OPENAI_API_KEY stays on the server; iOS never sees it.**

**Auth:** Every request must send `Authorization: Bearer <ID_TOKEN>`. The backend accepts **Apple** or **Google** identity tokens only. No shared secrets; no `X-APP-SECRET`.

## Environment

```bash
cd backend-openai
cp .env.example .env
# Edit .env: set OPENAI_API_KEY, APPLE_AUDIENCE, GOOGLE_AUDIENCE
```

| Variable | Description |
|----------|-------------|
| `OPENAI_API_KEY` | OpenAI API key (required for transcribe/summarize) |
| `PORT` | Server port (default 3000) |
| `APPLE_AUDIENCE` | Apple bundle id or service id; must match the `aud` claim in Apple ID tokens |
| `GOOGLE_AUDIENCE` | Google OAuth 2.0 client ID (iOS); must match the audience of the Google ID token |
| `RATE_LIMIT_MAX` | Max requests per user per window (default 60) |
| `RATE_LIMIT_WINDOW_SEC` | Window in seconds (default 900 = 15 min) |

### Setting APPLE_AUDIENCE and GOOGLE_AUDIENCE

- **APPLE_AUDIENCE:** Use your app’s **bundle identifier** (e.g. `com.danielphillippe.FLYR`) or the **Services ID** if you use Sign in with Apple with a web service.
- **GOOGLE_AUDIENCE:** Use the **iOS client ID** from Google Cloud Console (e.g. `309925212737-xxxx.apps.googleusercontent.com`). This must match the audience of the ID token your iOS app sends.

### Getting a real token for testing

1. **Apple:** After Sign in with Apple in the app, the ID token is stored in the keychain. You can log it in Xcode (e.g. in `KeychainIdentityTokenProvider` or after sign-in) and copy it for curl. Tokens expire (usually 10 minutes).
2. **Google:** After Google Sign-In, get the ID token from `GIDSignIn.sharedInstance.currentUser?.idToken?.tokenString` and log it in Xcode, or expose it temporarily in a debug screen. Use it in the `Authorization: Bearer <token>` header.

Run the backend locally (or over HTTPS in production) and call the endpoints with that token.

## Run locally

```bash
npm install
npm run dev
```

Server runs at `http://localhost:3000` (or `PORT` from env). **Production:** Run behind HTTPS (reverse proxy or platform like Railway, Render, Fly.io). Do not expose the server over plain HTTP in production.

## Endpoints

### GET /health

Returns `{ "status": "ok" }`. No auth.

### POST /v1/transcribe

- **Headers:** `Authorization: Bearer <ID_TOKEN>` (Apple or Google ID token)
- **Body:** multipart/form-data  
  - `file` (required): audio file (m4a, mp3, wav)  
  - `language` (optional): e.g. `en`
- **Response:** `{ "text": "...", "language": "en", "summary": { "title": "...", "keyPoints": [], "actionItems": [], "followUps": [] } }`
- Max upload: 25MB (413 if exceeded)

**curl example (transcribe):**

```bash
curl -X POST http://localhost:3000/v1/transcribe \
  -H "Authorization: Bearer YOUR_APPLE_OR_GOOGLE_ID_TOKEN" \
  -F "file=@/path/to/audio.m4a" \
  -F "language=en"
```

### POST /v1/summarize

- **Headers:** `Content-Type: application/json`, `Authorization: Bearer <ID_TOKEN>`
- **Body:** `{ "text": "transcript...", "context": "optional" }`
- **Response:** `{ "summary": { "title": "...", "keyPoints": [], "actionItems": [], "followUps": [] } }`
- Max text length: 200,000 characters (413 if exceeded)

**curl example (summarize):**

```bash
curl -X POST http://localhost:3000/v1/summarize \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_APPLE_OR_GOOGLE_ID_TOKEN" \
  -d '{"text":"Meeting notes: John will send the quote by Friday. Sarah asked about solar options."}'
```

## Test from iOS

1. Deploy this backend (or run locally and use ngrok/LAN URL with HTTPS if required).
2. In the app, set `TRANSCRIPTION_API_URL` in Info.plist (or build setting) to your API base URL (e.g. `https://your-api.example.com`). For local dev, you can use `http://localhost:3000` in the simulator or your machine’s LAN IP for a device (e.g. `http://192.168.1.10:3000`); production should use HTTPS.
3. Sign in with Apple or Google in the app. The app sends the current ID token in `Authorization: Bearer <token>` for “Improve accuracy” and “Generate summary”.
4. Open the voice note screen: record → on-device transcript appears. Tap “Improve accuracy” to upload and get Whisper + summary; tap “Generate summary” to summarize the current transcript only.

## Docker

See `Dockerfile`. Build and run:

```bash
docker build -t transcription-api .
docker run -p 3000:3000 --env-file .env transcription-api
```

Production: run behind a reverse proxy (e.g. nginx, Caddy) or a platform that terminates HTTPS.

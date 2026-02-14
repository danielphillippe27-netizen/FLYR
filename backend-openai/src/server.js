import express from "express";
import cors from "cors";
import multer from "multer";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import crypto from "crypto";
import rateLimit from "express-rate-limit";
import OpenAI from "openai";
import { requireAuth } from "./auth.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = express();

const allowedOrigins = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(",").map((o) => o.trim())
  : ["http://localhost:3000"];

app.use(
  cors({
    origin: function (origin, callback) {
      if (!origin) return callback(null, true);
      if (allowedOrigins.indexOf(origin) === -1) {
        return callback(new Error("CORS policy violation"), false);
      }
      return callback(null, true);
    },
    methods: ["POST", "GET", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"],
    credentials: true,
  })
);
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const MAX_UPLOAD_BYTES = 25 * 1024 * 1024; // 25MB
const MAX_SUMMARY_CHARS = 200_000;

const RATE_LIMIT_MAX = parseInt(process.env.RATE_LIMIT_MAX, 10) || 60;
const RATE_LIMIT_WINDOW_MS =
  (parseInt(process.env.RATE_LIMIT_WINDOW_SEC, 10) || 900) * 1000;

if (!OPENAI_API_KEY) {
  console.warn(
    "OPENAI_API_KEY not set; /v1/transcribe and /v1/summarize will fail."
  );
}

const openai = OPENAI_API_KEY ? new OpenAI({ apiKey: OPENAI_API_KEY }) : null;

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, "/tmp"),
  filename: (req, file, cb) =>
    cb(
      null,
      `upload-${Date.now()}-${Math.random().toString(36).slice(2)}`
    ),
});
const upload = multer({
  storage,
  limits: { fileSize: MAX_UPLOAD_BYTES },
});

// Request id and logging (user key filled after requireAuth on protected routes)
app.use((req, res, next) => {
  req.id = crypto.randomUUID();
  req.startTime = Date.now();
  res.on("finish", () => {
    const userKey = req.user ? `${req.user.provider}:${req.user.sub}` : "-";
    const elapsed = Date.now() - req.startTime;
    let extra = "";
    if (req.file) extra = `fileSize=${req.file.size}`;
    else if (req.body && typeof req.body.text === "string")
      extra = `chars=${req.body.text.length}`;
    console.log(
      `[req] id=${req.id} user=${userKey} ${req.method} ${req.path} ${res.statusCode} ${elapsed}ms ${extra}`.trim()
    );
  });
  next();
});

// Rate limiter for authenticated routes (key = provider:sub)
const apiLimiter = rateLimit({
  windowMs: RATE_LIMIT_WINDOW_MS,
  max: RATE_LIMIT_MAX,
  keyGenerator: (req) => {
    if (req.user) return `${req.user.provider}:${req.user.sub}`;
    return req.ip;
  },
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many requests" },
});

app.use(express.json({ limit: "1mb" }));

app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});

// POST /v1/transcribe: multipart audio -> Whisper -> gpt-4o-mini summary
app.post(
  "/v1/transcribe",
  requireAuth,
  apiLimiter,
  upload.single("file"),
  async (req, res) => {
    const start = Date.now();
    const file = req.file;
    if (!file) {
      return res.status(400).json({ error: "Missing file" });
    }
    const language = (req.body && req.body.language) || undefined;
    const fileSize = file.size;

    let transcript = "";
    let detectedLanguage = "en";

    try {
      if (!openai) {
        return res.status(503).json({ error: "OpenAI API not configured" });
      }

      const transcriptRes = await openai.audio.transcriptions.create({
        file: fs.createReadStream(file.path),
        model: "whisper-1",
        language: language || undefined,
      });
      transcript = transcriptRes.text || "";
      if (transcriptRes.language) detectedLanguage = transcriptRes.language;
    } catch (err) {
      fs.promises.unlink(file.path).catch(() => {});
      console.error("[transcribe] Whisper error:", err.message);
      return res
        .status(500)
        .json({ error: "Transcription failed", detail: err.message });
    }

    let summary = {
      title: "",
      keyPoints: [],
      actionItems: [],
      followUps: [],
    };
    if (transcript.trim()) {
      try {
        summary = await summarizeWithGPT(transcript, null);
      } catch (err) {
        console.error("[transcribe] Summary error:", err.message);
      }
    }

    fs.promises.unlink(file.path).catch(() => {});
    const elapsed = Date.now() - start;
    console.log(
      `[transcribe] id=${req.id} size=${fileSize} elapsed_ms=${elapsed} lang=${detectedLanguage}`
    );

    res.json({
      text: transcript,
      language: detectedLanguage,
      summary,
    });
  }
);

// POST /v1/summarize: JSON { text, context? } -> gpt-4o-mini summary
app.post(
  "/v1/summarize",
  requireAuth,
  apiLimiter,
  async (req, res) => {
    const start = Date.now();
    const { text, context } = req.body || {};
    if (typeof text !== "string") {
      return res.status(400).json({ error: "Missing or invalid text" });
    }
    if (text.length > MAX_SUMMARY_CHARS) {
      return res
        .status(413)
        .json({ error: `Text exceeds ${MAX_SUMMARY_CHARS} characters` });
    }

    try {
      if (!openai) {
        return res.status(503).json({ error: "OpenAI API not configured" });
      }
      const summary = await summarizeWithGPT(text, context || undefined);
      const elapsed = Date.now() - start;
      console.log(
        `[summarize] id=${req.id} chars=${text.length} elapsed_ms=${elapsed}`
      );
      res.json({ summary });
    } catch (err) {
      console.error("[summarize] error:", err.message);
      res
        .status(500)
        .json({ error: "Summarization failed", detail: err.message });
    }
  }
);

const SUMMARY_SYSTEM = `You summarize transcripts into structured JSON only. Output valid JSON with no markdown or extra text.
Keys: title (short string), keyPoints (array of strings), actionItems (array of strings), followUps (array of strings for follow-ups and names mentioned).
Keep each list short and useful.`;

async function summarizeWithGPT(text, context) {
  const userContent = context
    ? `Context: ${context}\n\nTranscript:\n${text}`
    : `Transcript:\n${text}`;

  const completion = await openai.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: SUMMARY_SYSTEM },
      { role: "user", content: userContent },
    ],
    temperature: 0.3,
  });

  const raw = completion.choices?.[0]?.message?.content?.trim() || "{}";
  let parsed;
  try {
    const cleaned = raw
      .replace(/^```json\s*/i, "")
      .replace(/\s*```\s*$/i, "")
      .trim();
    parsed = JSON.parse(cleaned);
  } catch {
    parsed = {};
  }
  return {
    title: parsed.title ?? "",
    keyPoints: Array.isArray(parsed.keyPoints) ? parsed.keyPoints : [],
    actionItems: Array.isArray(parsed.actionItems) ? parsed.actionItems : [],
    followUps: Array.isArray(parsed.followUps) ? parsed.followUps : [],
  };
}

// Multer file size (413), CORS, and other errors
app.use((err, req, res, next) => {
  if (err.code === "LIMIT_FILE_SIZE") {
    return res.status(413).json({ error: "File too large (max 25MB)" });
  }
  if (err.message === "CORS policy violation") {
    return res.status(403).json({ error: "Origin not allowed" });
  }
  console.error("[server] error:", err.message);
  res.status(500).json({ error: "Internal server error" });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Transcription API listening on port ${PORT}`);
});

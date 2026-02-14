import { createRemoteJWKSet, jwtVerify } from "jose";
import { OAuth2Client } from "google-auth-library";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";

const APPLE_AUDIENCE = process.env.APPLE_AUDIENCE || "";
const GOOGLE_AUDIENCE = process.env.GOOGLE_AUDIENCE || "";

let appleJwks;
function getAppleJwks() {
  if (!appleJwks) {
    appleJwks = createRemoteJWKSet(new URL(APPLE_JWKS_URL), {
      timeoutDuration: 10000,
    });
  }
  return appleJwks;
}

const googleClient = new OAuth2Client();

/**
 * Decode JWT payload without verifying (to detect issuer).
 * @param {string} token
 * @returns {{ iss?: string, aud?: string, sub?: string } | null }
 */
function decodeUnsafe(token) {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf8")
    );
    return payload;
  } catch {
    return null;
  }
}

/**
 * Validate Apple ID token with Apple JWKS.
 * @param {string} token
 * @returns {Promise<{ provider: 'apple', sub: string, email?: string }>}
 */
async function verifyAppleToken(token) {
  const audience = APPLE_AUDIENCE.trim();
  if (!audience) {
    const err = new Error("APPLE_AUDIENCE not configured");
    err.code = "CONFIG";
    throw err;
  }
  const jwks = getAppleJwks();
  const { payload } = await jwtVerify(token, jwks, {
    issuer: APPLE_ISSUER,
    audience: audience,
  });
  const sub = payload.sub;
  if (!sub || typeof sub !== "string") {
    throw new Error("Invalid Apple token: missing sub");
  }
  return {
    provider: "apple",
    sub: String(sub),
    email: payload.email ? String(payload.email) : undefined,
  };
}

/**
 * Validate Google ID token.
 * @param {string} token
 * @returns {Promise<{ provider: 'google', sub: string, email?: string }>}
 */
async function verifyGoogleToken(token) {
  const audience = GOOGLE_AUDIENCE.trim();
  if (!audience) {
    const err = new Error("GOOGLE_AUDIENCE not configured");
    err.code = "CONFIG";
    throw err;
  }
  const ticket = await googleClient.verifyIdToken({
    idToken: token,
    audience: audience,
  });
  const payload = ticket.getPayload();
  if (!payload || !payload.sub) {
    throw new Error("Invalid Google token: missing sub");
  }
  return {
    provider: "google",
    sub: String(payload.sub),
    email: payload.email ? String(payload.email) : undefined,
  };
}

/**
 * Require valid Apple or Google ID token.
 * Sets req.user = { provider, sub, email? }.
 * Returns 401 on missing/invalid/expired token.
 */
export function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  const token =
    authHeader && authHeader.startsWith("Bearer ")
      ? authHeader.slice(7).trim()
      : null;

  if (!token) {
    return res.status(401).json({ error: "Missing Authorization: Bearer <token>" });
  }

  const payload = decodeUnsafe(token);
  if (!payload || !payload.iss) {
    return res.status(401).json({ error: "Invalid token" });
  }

  const iss = payload.iss;
  const isApple =
    iss === "https://appleid.apple.com" || iss === "appleid.apple.com";
  const isGoogle =
    typeof iss === "string" &&
    (iss.includes("accounts.google.com") || iss === "https://accounts.google.com");

  const run = async () => {
    try {
      if (isApple) {
        req.user = await verifyAppleToken(token);
        return next();
      }
      if (isGoogle) {
        req.user = await verifyGoogleToken(token);
        return next();
      }
      return res.status(401).json({ error: "Unsupported token issuer" });
    } catch (err) {
      if (err.code === "CONFIG") {
        console.error("[auth] config:", err.message);
        return res.status(503).json({ error: "Auth not configured" });
      }
      console.error("[auth] verify failed:", err.message);
      return res.status(401).json({ error: "Invalid or expired token" });
    }
  };

  run();
}

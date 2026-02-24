import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { createSign } from "node:crypto";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const APP_STORE_CONNECT_ISSUER_ID = process.env.APP_STORE_CONNECT_ISSUER_ID;
const APP_STORE_CONNECT_KEY_ID = process.env.APP_STORE_CONNECT_KEY_ID;
const APP_STORE_CONNECT_PRIVATE_KEY = process.env.APP_STORE_CONNECT_PRIVATE_KEY;
const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID;

const APPLE_PROD_TRANSACTIONS_URL = "https://api.storekit.itunes.apple.com/inApps/v1/transactions";
const APPLE_SANDBOX_TRANSACTIONS_URL = "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions";

type VerifyBody = { transactionId: string; productId: string };
type AppleTransactionLookupResponse = { signedTransactionInfo?: string };
type AppleTransactionPayload = {
  transactionId?: string | number;
  originalTransactionId?: string | number;
  productId?: string;
  bundleId?: string;
  purchaseDate?: string | number;
  expiresDate?: string | number;
  revocationDate?: string | number;
  environment?: string;
};

function toBase64Url(input: Buffer | string): string {
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(input, "utf8");
  return buf
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function fromBase64Url(value: string): Buffer {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(padded, "base64");
}

function toDate(value: string | number | undefined): Date | null {
  if (value === undefined || value === null) return null;
  const num = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(num)) return null;
  const ms = num > 1e12 ? num : num * 1000;
  const date = new Date(ms);
  return Number.isNaN(date.getTime()) ? null : date;
}

function isYearlyProduct(productId: string): boolean {
  const normalized = productId.toLowerCase();
  return normalized.includes("yearly") || normalized.includes("annual");
}

function createAppStoreConnectToken(): string {
  if (!APP_STORE_CONNECT_ISSUER_ID || !APP_STORE_CONNECT_KEY_ID || !APP_STORE_CONNECT_PRIVATE_KEY) {
    throw new Error("Missing App Store Connect credentials in environment.");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: APP_STORE_CONNECT_KEY_ID, typ: "JWT" };
  const payload = {
    iss: APP_STORE_CONNECT_ISSUER_ID,
    iat: now,
    exp: now + 60 * 10,
    aud: "appstoreconnect-v1",
  };

  const encodedHeader = toBase64Url(JSON.stringify(header));
  const encodedPayload = toBase64Url(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const privateKey = APP_STORE_CONNECT_PRIVATE_KEY.replace(/\\n/g, "\n");

  const signer = createSign("SHA256");
  signer.update(signingInput);
  signer.end();
  const signature = signer.sign(privateKey);
  return `${signingInput}.${toBase64Url(signature)}`;
}

async function fetchAppleTransaction(transactionId: string, bearerToken: string): Promise<{
  payload: AppleTransactionPayload;
  environment: "production" | "sandbox";
}> {
  const urls: Array<{ base: string; environment: "production" | "sandbox" }> = [
    { base: APPLE_PROD_TRANSACTIONS_URL, environment: "production" },
    { base: APPLE_SANDBOX_TRANSACTIONS_URL, environment: "sandbox" },
  ];

  for (const candidate of urls) {
    const response = await fetch(`${candidate.base}/${encodeURIComponent(transactionId)}`, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${bearerToken}`,
      },
    });

    if (!response.ok) {
      if (response.status === 404 || response.status === 400) {
        continue;
      }
      const detail = await response.text().catch(() => "");
      throw new Error(`Apple transaction lookup failed (${response.status}): ${detail}`);
    }

    const json = (await response.json()) as AppleTransactionLookupResponse;
    if (!json.signedTransactionInfo) {
      throw new Error("Apple response missing signedTransactionInfo.");
    }

    const parts = json.signedTransactionInfo.split(".");
    if (parts.length < 2) {
      throw new Error("Invalid signedTransactionInfo format.");
    }

    const payloadRaw = fromBase64Url(parts[1]).toString("utf8");
    const payload = JSON.parse(payloadRaw) as AppleTransactionPayload;
    return { payload, environment: candidate.environment };
  }

  throw new Error("Transaction not found in production or sandbox.");
}

/**
 * POST /api/billing/apple/verify
 * Validates JWT, verifies transaction against App Store Server API, and upserts entitlement state.
 */
export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json({ error: "Missing or invalid authorization" }, { status: 401 });
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const {
      data: { user },
      error: userError,
    } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json({ error: "Invalid or expired token" }, { status: 401 });
    }

    const body = (await request.json()) as VerifyBody;
    const transactionId =
      typeof body.transactionId === "string" ? body.transactionId.trim() : String(body.transactionId ?? "");
    const productId = typeof body.productId === "string" ? body.productId.trim() : "";
    if (!transactionId || !productId) {
      return NextResponse.json(
        { error: "Missing transactionId or productId" },
        { status: 400 }
      );
    }

    const appStoreToken = createAppStoreConnectToken();
    const { payload, environment } = await fetchAppleTransaction(transactionId, appStoreToken);

    const appleTransactionId = String(payload.transactionId ?? "");
    const appleProductId = (payload.productId ?? "").trim();
    if (!appleTransactionId || !appleProductId) {
      return NextResponse.json({ error: "Apple payload missing transactionId or productId" }, { status: 400 });
    }

    if (appleTransactionId !== transactionId) {
      return NextResponse.json({ error: "Apple transaction ID mismatch" }, { status: 400 });
    }
    if (appleProductId !== productId) {
      return NextResponse.json({ error: "Apple product ID mismatch" }, { status: 400 });
    }
    if (APPLE_BUNDLE_ID && payload.bundleId && payload.bundleId !== APPLE_BUNDLE_ID) {
      return NextResponse.json({ error: "Apple bundle ID mismatch" }, { status: 400 });
    }

    const now = new Date();
    const expiresAt = toDate(payload.expiresDate);
    const revokedAt = toDate(payload.revocationDate);
    let currentPeriodEnd = expiresAt;

    // Fallback when Apple payload omits expiresDate (defensive; subscriptions typically include it).
    if (!currentPeriodEnd) {
      currentPeriodEnd = new Date(now);
      if (isYearlyProduct(appleProductId)) {
        currentPeriodEnd.setFullYear(currentPeriodEnd.getFullYear() + 1);
      } else {
        currentPeriodEnd.setMonth(currentPeriodEnd.getMonth() + 1);
      }
    }

    const isActive = revokedAt == null && currentPeriodEnd.getTime() > Date.now();

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { error: upsertError } = await supabaseAdmin.from("entitlements").upsert(
      {
        user_id: user.id,
        plan: "pro",
        is_active: isActive,
        source: "apple",
        current_period_end: currentPeriodEnd.toISOString(),
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id" }
    );

    if (upsertError) {
      console.error("[billing/apple/verify] upsert error:", upsertError);
      return NextResponse.json({ error: "Failed to update entitlement" }, { status: 500 });
    }

    return NextResponse.json({
      ok: true,
      isActive,
      currentPeriodEnd: currentPeriodEnd.toISOString(),
      environment,
    });
  } catch (err) {
    console.error("[billing/apple/verify]", err);
    return NextResponse.json({ error: "Server error" }, { status: 500 });
  }
}

import { createClient } from "@supabase/supabase-js";
import { NextResponse } from "next/server";
import { createCipheriv, randomBytes } from "crypto";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const CRM_ENCRYPTION_KEY = process.env.CRM_ENCRYPTION_KEY!; // 32 bytes hex or base64
const CRM_ENCRYPTION_KEY_VERSION = parseInt(process.env.CRM_ENCRYPTION_KEY_VERSION ?? "1", 10);

const FUB_API_BASE = "https://api.followupboss.com/v1";

type ConnectBody = { api_key: string };
type FUBMeResponse = { id?: number; name?: string; email?: string; [k: string]: unknown };

function getEncryptionKey(): Buffer {
  if (!CRM_ENCRYPTION_KEY || CRM_ENCRYPTION_KEY.length < 32) {
    throw new Error("CRM_ENCRYPTION_KEY must be at least 32 chars (hex or raw)");
  }
  const buf = Buffer.from(CRM_ENCRYPTION_KEY, "hex");
  if (buf.length === 32) return buf;
  return Buffer.from(CRM_ENCRYPTION_KEY.slice(0, 32), "utf8");
}

function encrypt(plaintext: string): string {
  const key = getEncryptionKey();
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv, { authTagLength: 16 });
  const enc = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  const blob = {
    v: 1,
    key_version: CRM_ENCRYPTION_KEY_VERSION,
    iv: iv.toString("base64"),
    tag: tag.toString("base64"),
    ciphertext: enc.toString("base64"),
  };
  return Buffer.from(JSON.stringify(blob)).toString("base64");
}

async function verifyFUBKey(apiKey: string): Promise<{ name?: string; company?: string }> {
  const auth = Buffer.from(`${apiKey}:`).toString("base64");
  const res = await fetch(`${FUB_API_BASE}/me`, {
    headers: { Authorization: `Basic ${auth}` },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(text || `FUB returned ${res.status}`);
  }
  const data = (await res.json()) as FUBMeResponse;
  return {
    name: data.name ?? undefined,
    company: (data as { company?: string }).company ?? undefined,
  };
}

export async function POST(request: Request) {
  try {
    const authHeader = request.headers.get("authorization");
    const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return NextResponse.json(
        { connected: false, error: "Missing or invalid authorization" },
        { status: 401 }
      );
    }

    const supabaseAnon = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
    const { data: { user }, error: userError } = await supabaseAnon.auth.getUser(token);
    if (userError || !user) {
      return NextResponse.json(
        { connected: false, error: "Invalid or expired token" },
        { status: 401 }
      );
    }
    const userId = user.id;

    const body = (await request.json()) as ConnectBody;
    const rawKey = typeof body.api_key === "string" ? body.api_key.trim() : "";
    if (rawKey.length < 20) {
      return NextResponse.json(
        { connected: false, error: "API key is too short" },
        { status: 400 }
      );
    }

    let account: { name?: string; company?: string };
    try {
      account = await verifyFUBKey(rawKey);
    } catch (_e) {
      return NextResponse.json(
        { connected: false, error: "That key isn't valid." },
        { status: 401 }
      );
    }

    const encrypted = encrypt(rawKey);
    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: existing } = await supabaseAdmin
      .from("crm_connections")
      .select("id")
      .eq("user_id", userId)
      .eq("provider", "fub")
      .maybeSingle();

    let connectionId: string;
    if (existing?.id) {
      connectionId = existing.id;
      await supabaseAdmin
        .from("crm_connections")
        .update({
          status: "connected",
          connected_at: new Date().toISOString(),
          last_sync_at: null,
          metadata: { name: account.name ?? null, company: account.company ?? null },
          error_reason: null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", connectionId);
    } else {
      const { data: inserted, error: insertErr } = await supabaseAdmin
        .from("crm_connections")
        .insert({
          user_id: userId,
          provider: "fub",
          status: "connected",
          connected_at: new Date().toISOString(),
          metadata: { name: account.name ?? null, company: account.company ?? null },
          updated_at: new Date().toISOString(),
        })
        .select("id")
        .single();
      if (insertErr || !inserted?.id) {
        return NextResponse.json(
          { connected: false, error: "Failed to save connection" },
          { status: 500 }
        );
      }
      connectionId = inserted.id;
    }

    await supabaseAdmin.from("crm_connection_secrets").upsert(
      {
        connection_id: connectionId,
        encrypted_api_key: encrypted,
      },
      { onConflict: "connection_id" }
    );

    return NextResponse.json({
      connected: true,
      account: {
        name: account.name ?? null,
        company: account.company ?? null,
      },
    });
  } catch (err) {
    console.error("[fub/connect]", err);
    return NextResponse.json(
      { connected: false, error: "Something went wrong" },
      { status: 500 }
    );
  }
}

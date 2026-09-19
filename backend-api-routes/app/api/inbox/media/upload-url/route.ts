import { randomUUID } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/server";
import { resolveDialerWorkspace } from "../../../dialer/_utils";

const BUCKET = "message-media";
const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/heic", "image/webp", "video/mp4", "video/quicktime"]);
const MAX_BYTES = 10 * 1024 * 1024;

export async function POST(request: NextRequest) {
  const { response, context } = await resolveDialerWorkspace(request);
  if (response) return response;

  const body = await request.json().catch(() => ({}));
  const mimeType = String(body.mimeType || "").trim().toLowerCase();
  const byteSize = Number(body.byteSize || 0);
  const originalName = String(body.fileName || "attachment").slice(0, 255);
  if (!ALLOWED_TYPES.has(mimeType)) {
    return NextResponse.json({ error: "Choose a JPEG, PNG, HEIC, WebP, MP4, or QuickTime file." }, { status: 415 });
  }
  if (!Number.isFinite(byteSize) || byteSize <= 0 || byteSize > MAX_BYTES) {
    return NextResponse.json({ error: "Photos and videos must be smaller than 10 MB." }, { status: 413 });
  }

  const extension = originalName.includes(".")
    ? originalName.split(".").pop()?.replace(/[^a-z0-9]/gi, "").toLowerCase()
    : mimeType.startsWith("video/") ? "mov" : "jpg";
  const workspaceId = context!.workspace!.id;
  const storagePath = `${workspaceId}/${context!.user.id}/${new Date().toISOString().slice(0, 10)}/${randomUUID()}.${extension || "bin"}`;
  const { data, error } = await createAdminClient().storage.from(BUCKET).createSignedUploadUrl(storagePath);
  if (error || !data) {
    return NextResponse.json({ error: error?.message || "Could not prepare the media upload." }, { status: 500 });
  }
  return NextResponse.json({ upload: { signedUrl: data.signedUrl, storagePath } });
}

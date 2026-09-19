import { NextResponse, type NextRequest } from "next/server";
import { createAdminClient } from "@/lib/supabase/server";
import { resolveDialerWorkspace } from "../../../dialer/_utils";

const BUCKET = "message-media";
const PROVIDER_URL_TTL_SECONDS = 7 * 24 * 60 * 60;

export async function POST(request: NextRequest) {
  const { response, context } = await resolveDialerWorkspace(request);
  if (response) return response;

  const body = await request.json().catch(() => ({}));
  const storagePath = String(body.storagePath || "");
  const mimeType = String(body.mimeType || "application/octet-stream");
  const fileName = String(body.fileName || "attachment").slice(0, 255);
  const requiredPrefix = `${context!.workspace!.id}/${context!.user.id}/`;
  if (!storagePath.startsWith(requiredPrefix)) {
    return NextResponse.json({ error: "Invalid upload receipt." }, { status: 400 });
  }

  const admin = createAdminClient();
  const { data: signed, error } = await admin.storage.from(BUCKET).createSignedUrl(storagePath, PROVIDER_URL_TTL_SECONDS);
  if (error || !signed?.signedUrl) {
    return NextResponse.json({ error: error?.message || "Uploaded media was not found." }, { status: 404 });
  }
  const probe = await fetch(signed.signedUrl, { headers: { Range: "bytes=0-0" } });
  if (!probe.ok) {
    return NextResponse.json({ error: "Uploaded media was not found." }, { status: 404 });
  }

  return NextResponse.json({
    attachment: {
      url: signed.signedUrl,
      mimeType,
      fileName,
      storagePath,
    },
  });
}

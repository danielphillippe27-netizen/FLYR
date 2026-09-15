import { NextRequest, NextResponse } from 'next/server';
import { createAdminClient } from '@/lib/supabase/server';
import { postingFingerprint } from '@/lib/hiring/postings';
import { parseTheirStackJob, sourceDate, theirStackEventSchema, validTheirStackSignature } from '@/lib/hiring/theirstack';

export const runtime = 'nodejs';
export const maxDuration = 30;

export async function POST(request: NextRequest) {
  const secret = process.env.THEIRSTACK_WEBHOOK_SECRET;
  if (!secret || secret.length < 16) return NextResponse.json({ error: 'Webhook not configured.' }, { status: 503 });
  // Bound both declared and streamed sizes before parsing a third-party body.
  if (Number(request.headers.get('content-length') ?? 0) > 1048576) return new NextResponse(null, { status: 413 });
  const reader = request.body?.getReader();
  if (!reader) return new NextResponse(null, { status: 400 });
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  let validated = false;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > 1048576) { await reader.cancel(); return new NextResponse(null, { status: 413 }); }
      chunks.push(value);
    }
    const raw = Buffer.concat(chunks);
    if (!validTheirStackSignature(raw, request.headers.get('x-theirstack-signature-256'), secret)) {
      return NextResponse.json({ error: 'Invalid signature.' }, { status: 403 });
    }
    const event = theirStackEventSchema.safeParse(JSON.parse(raw.toString('utf8')));
    if (!event.success) return NextResponse.json({ error: 'Unsupported or invalid hiring event.' }, { status: 422 });
    if (event.data.type === 'job.closed') {
      const closedAt = sourceDate(event.data.payload.closed_at);
      if (!closedAt) return new NextResponse(null, { status: 422 });
      if (request.nextUrl.searchParams.get('validate_only') === '1') return NextResponse.json({ validated: true });
      validated = true;
      const { error } = await createAdminClient().rpc('close_hiring_posting', {
        p_external_id: String(event.data.payload.id), p_closed_at: closedAt,
      });
      if (error) return NextResponse.json({ error: 'Could not record closed posting.' }, { status: 500 });
      return NextResponse.json({ received: true });
    }
    const postings = parseTheirStackJob(event.data.payload);
    if (request.nextUrl.searchParams.get('validate_only') === '1') return NextResponse.json({ validated: true, countries: postings.map(p => p.country) });
    if (!postings.length) return NextResponse.json({ received: true, ignored: 'Outside Canada and USA.' });
    validated = true;
    const { error } = await createAdminClient().rpc('ingest_hiring_postings', {
      p_postings: postings.map(posting => ({ ...posting, fingerprint: postingFingerprint(posting) })),
    });
    if (error) return NextResponse.json({ error: 'Could not save hiring event.' }, { status: 500 });
    return NextResponse.json({ received: true, postings: postings.length });
  } catch {
    return NextResponse.json({ error: validated ? 'Could not save hiring event.' : 'Invalid hiring event.' }, { status: validated ? 500 : 422 });
  }
}

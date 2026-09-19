import { NextRequest, NextResponse } from 'next/server';
import { requireSocialUser } from '@/lib/social/auth';

export const runtime = 'nodejs';

export async function POST(request: NextRequest) {
  const context = await requireSocialUser(request);
  if (!context) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const openAIKey = process.env.OPENAI_API_KEY;
  const geminiKey = process.env.GEMINI_API_KEY;
  if (!openAIKey && !geminiKey) return NextResponse.json({ error: 'Wolfey is not configured' }, { status: 503 });
  const body = await request.json().catch(() => ({}));
  const task = body.task === 'suggest_reply' ? 'suggest_reply' : 'caption_variants';
  const source = String(body.source || body.caption || '').trim().slice(0, 8000);
  if (!source) return NextResponse.json({ error: 'Add source content first' }, { status: 400 });
  const instruction = task === 'suggest_reply'
    ? 'Suggest three concise, helpful replies to the customer message. Do not claim the replies were sent.'
    : 'Write three distinct social caption variants. Keep facts grounded in the source. Do not claim anything was published.';
  const prompt = `You are Wolfey, an assist-only social writing partner. ${instruction} Return JSON: {"suggestions":["...","...","..."]}. Every suggestion requires human approval.\n\nSource:\n${source}`;
  const response = openAIKey
    ? await fetch('https://api.openai.com/v1/chat/completions', { method: 'POST', headers: { Authorization: `Bearer ${openAIKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ model: process.env.WOLFEY_MODEL || 'gpt-4.1-mini', temperature: 0.7, response_format: { type: 'json_object' }, messages: [{ role: 'user', content: prompt }] }) })
    : await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${process.env.WOLFEY_GEMINI_MODEL || 'gemini-2.5-flash'}:generateContent?key=${encodeURIComponent(geminiKey!)}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: prompt }] }], generationConfig: { temperature: 0.7, responseMimeType: 'application/json' } }) });
  const payload = await response.json();
  if (!response.ok) return NextResponse.json({ error: payload.error?.message || 'Wolfey could not create suggestions' }, { status: 502 });
  try {
    const content = openAIKey ? payload.choices?.[0]?.message?.content : payload.candidates?.[0]?.content?.parts?.[0]?.text;
    const result = JSON.parse(content || '{}');
    return NextResponse.json({ suggestions: Array.isArray(result.suggestions) ? result.suggestions.slice(0, 3) : [], requiresApproval: true });
  } catch { return NextResponse.json({ error: 'Wolfey returned an invalid response' }, { status: 502 }); }
}

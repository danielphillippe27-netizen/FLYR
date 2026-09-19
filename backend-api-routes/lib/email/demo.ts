export const SALES_DEMO_URL = 'https://wolfgrid.app/demo100';

function escapeHtml(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
}

export function demoEmailContent(input: {
  recipientName?: string | null;
  senderName?: string | null;
  senderEmail: string;
}) {
  const name = input.senderName?.trim() || 'WolfGrid Sales';
  const greeting = input.recipientName?.trim() ? `Hi ${input.recipientName.trim()},` : 'Hi there,';
  const intro = 'Here’s the WolfGrid demo. Take a look at how you can plan your territory, organize leads, and keep your team’s follow-up in one place.';
  const closing = 'Have a question or want to talk through how WolfGrid could fit your business? Just reply to this email — I’m happy to help.';
  const text = [greeting, intro, `Watch the demo: ${SALES_DEMO_URL}`, closing, `Thanks,\n${name}\nWolfGrid\n${input.senderEmail}\nhttps://wolfgrid.app`].join('\n\n');
  const html = `<!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width, initial-scale=1"><meta charset="utf-8"><title>Your WolfGrid demo</title></head>
<body style="margin:0;background:#f4f4f5;font-family:Arial,sans-serif;color:#18181b">
<div style="display:none;max-height:0;overflow:hidden">Your WolfGrid demo is ready. See it in action.</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td style="padding:32px 16px">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:580px;margin:auto;background:#fff;border:1px solid #e4e4e7;border-radius:12px">
<tr><td style="padding:28px 28px 22px;border-bottom:1px solid #eee;font-size:22px;font-weight:800">WOLF<span style="color:#e50914">GRID</span></td></tr>
<tr><td style="padding:28px;font-size:16px;line-height:1.65">
<h1 style="font-size:26px;line-height:1.2;margin:0 0 24px">See WolfGrid in action.</h1>
<p>${escapeHtml(greeting)}</p><p>${escapeHtml(intro)}</p>
<table role="presentation" cellspacing="0" cellpadding="0" style="margin:26px 0"><tr><td bgcolor="#df0011" style="border-radius:7px;text-align:center"><a href="${SALES_DEMO_URL}" style="display:inline-block;padding:15px 26px;border:1px solid #df0011;border-radius:7px;color:#fff;font-size:16px;font-weight:700;text-decoration:none">Watch the demo &rarr;</a></td></tr></table>
<p>${escapeHtml(closing)}</p><p style="margin-bottom:8px">Thanks,</p>
<table role="presentation" cellspacing="0" cellpadding="0"><tr><td style="border-left:3px solid #df0011;padding-left:14px"><strong>${escapeHtml(name)}</strong><br><span style="font-size:14px;color:#52525b">WolfGrid</span><br><a href="mailto:${escapeHtml(input.senderEmail)}" style="font-size:14px;color:#52525b;text-decoration:none">${escapeHtml(input.senderEmail)}</a><br><a href="https://wolfgrid.app" style="font-size:14px;color:#df0011;text-decoration:none">wolfgrid.app</a></td></tr></table>
</td></tr><tr><td style="padding:18px 28px;border-top:1px solid #eee;font-size:12px;line-height:1.6;color:#71717a">You can also open the demo here:<br><a href="${SALES_DEMO_URL}" style="color:#52525b;word-break:break-all">${SALES_DEMO_URL}</a></td></tr></table>
</td></tr></table></body></html>`;
  return { subject: 'Your WolfGrid demo', text, html };
}

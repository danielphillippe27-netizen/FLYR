const DANIEL_EMAIL = 'daniel@wolfgrid.app';

type SocialLink = {
  name: string;
  url: string;
  iconUrl: string;
};

export type BrandedEmailContent = {
  text: string;
  html: string;
};

function cleanEnv(name: string, fallback: string): string {
  return process.env[name]?.trim() || fallback;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function socialLinks(): SocialLink[] {
  return [
    {
      name: 'Instagram',
      url: cleanEnv('EMAIL_SIGNATURE_INSTAGRAM_URL', 'https://www.instagram.com/'),
      iconUrl: 'https://www.google.com/s2/favicons?domain=instagram.com&sz=64',
    },
    {
      name: 'YouTube',
      url: cleanEnv('EMAIL_SIGNATURE_YOUTUBE_URL', 'https://www.youtube.com/'),
      iconUrl: 'https://www.google.com/s2/favicons?domain=youtube.com&sz=64',
    },
    {
      name: 'LinkedIn',
      url: cleanEnv('EMAIL_SIGNATURE_LINKEDIN_URL', 'https://www.linkedin.com/'),
      iconUrl: 'https://www.google.com/s2/favicons?domain=linkedin.com&sz=64',
    },
    {
      name: 'Facebook',
      url: cleanEnv('EMAIL_SIGNATURE_FACEBOOK_URL', 'https://www.facebook.com/'),
      iconUrl: 'https://www.google.com/s2/favicons?domain=facebook.com&sz=64',
    },
  ];
}

function isDanielSender(fromAddress: string | null | undefined): boolean {
  const normalized = fromAddress?.trim().toLowerCase();
  return normalized === DANIEL_EMAIL || normalized?.endsWith(`<${DANIEL_EMAIL}>`) === true;
}

function websiteLabel(value: string): string {
  try {
    return new URL(value).hostname.replace(/^www\./, '');
  } catch {
    return value.replace(/^https?:\/\//, '').replace(/\/$/, '');
  }
}

export function brandedEmailContent(
  body: string,
  fromAddress: string | null | undefined,
): BrandedEmailContent {
  const trimmedBody = body.trim();
  const escapedBody = escapeHtml(trimmedBody).replaceAll(/\r?\n/g, '<br>');

  if (!isDanielSender(fromAddress)) {
    return {
      text: trimmedBody,
      html: `<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:15px;line-height:1.55;color:#18181b">${escapedBody}</div>`,
    };
  }

  const websiteUrl = cleanEnv('EMAIL_SIGNATURE_WEBSITE_URL', 'https://wolfgrid.app');
  const website = websiteLabel(websiteUrl);
  const socials = socialLinks();
  const socialText = socials.map((social) => `${social.name}: ${social.url}`).join('\n');
  const textSignature = [
    'Daniel Phillippe',
    'Founder · WolfGrid',
    `${website} | ${DANIEL_EMAIL}`,
    socialText,
  ].join('\n');
  const socialIcons = socials.map((social) => `
    <a href="${escapeHtml(social.url)}" aria-label="${social.name}" style="display:inline-block;margin-right:7px;text-decoration:none">
      <img src="${escapeHtml(social.iconUrl)}" width="18" height="18" alt="${social.name}" style="display:block;width:18px;height:18px;border:0;border-radius:4px" />
    </a>`).join('');

  return {
    text: `${trimmedBody}\n\n${textSignature}`,
    html: `
      <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:15px;line-height:1.55;color:#18181b">
        <div>${escapedBody}</div>
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin-top:22px;border-collapse:collapse">
          <tr>
            <td width="3" bgcolor="#ef2b2d" style="width:3px;background-color:#ef2b2d;font-size:0;line-height:0">&nbsp;</td>
            <td style="padding-left:13px">
              <div style="font-size:15px;line-height:20px;font-weight:700;color:#18181b">Daniel Phillippe</div>
              <div style="font-size:12px;line-height:18px;color:#52525b">
                Founder <span style="color:#a1a1aa">&middot;</span>
                <a href="${escapeHtml(websiteUrl)}" style="font-weight:600;color:#ef2b2d;text-decoration:none">WolfGrid</a>
              </div>
              <div style="font-size:12px;line-height:18px;color:#52525b">
                <a href="${escapeHtml(websiteUrl)}" style="color:#52525b;text-decoration:none">${escapeHtml(website)}</a>
                <span style="color:#a1a1aa">&nbsp;|&nbsp;</span>
                <a href="mailto:${DANIEL_EMAIL}" style="color:#52525b;text-decoration:none">${DANIEL_EMAIL}</a>
              </div>
              <div style="margin-top:9px;line-height:18px;white-space:nowrap">${socialIcons}</div>
            </td>
          </tr>
        </table>
      </div>`,
  };
}

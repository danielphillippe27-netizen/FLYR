import { LegalPage } from '@/components/social/LegalPage';

export const metadata = { title: 'WolfSocial Support', description: 'Contact WolfSocial for account, publishing, privacy and provider-connection support.' };

export default function SupportPage() {
  return <LegalPage title="WolfSocial Support" updated="We normally respond within two business days." sections={[
    ['Contact', <p key="contact">Email <a className="text-red-600 underline" href="mailto:support@wolfgrid.app">support@wolfgrid.app</a> for account access, provider connections, publishing failures, privacy requests or data deletion.</p>],
    ['Include these details', 'Tell us the connected platform, account name, approximate time of the issue and the WolfSocial screen you were using. Never send provider access tokens, passwords or authentication codes.'],
    ['TikTok draft uploads', 'After WolfSocial delivers a TikTok draft, open the TikTok inbox notification to review, edit and complete the post. Draft delivery does not make the post public automatically.'],
    ['Provider limitations', 'TikTok and LinkedIn inboxes are unavailable through their standard posting APIs. YouTube supports comments and replies but has no direct messages. Facebook publishing supports Pages, Instagram requires a professional account, and LinkedIn Company Pages require Community Management approval.'],
  ]}/>;
}

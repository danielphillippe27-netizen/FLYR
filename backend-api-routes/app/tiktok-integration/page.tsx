import type { Metadata } from 'next';
import { WolfSocialPublicPage } from '@/components/social/WolfSocialPublicSite';

export const metadata: Metadata = {
  title: 'TikTok integration | WolfSocial',
  description: 'How WolfSocial uses TikTok Login Kit and the Content Posting API.',
  alternates: { canonical: 'https://social.wolfgrid.app/tiktok-integration' },
};

const sections = [
  ['Account connection', 'The user chooses Connect TikTok in WolfSocial and is sent to TikTok’s authorization screen. After consent, TikTok returns the user to social.wolfgrid.app. WolfSocial displays the connected account identity so the user can confirm the correct destination.'],
  ['Content preparation', 'The user uploads a video they control, previews it inside WolfSocial, writes a caption and selects their connected TikTok account. WolfSocial does not scrape TikTok or request the user’s TikTok password.'],
  ['Creator settings', 'Before Direct Post, WolfSocial retrieves TikTok’s current creator information and requires the user to select the available privacy and interaction settings. The user must also make the applicable music-rights and commercial-content declarations.'],
  ['Explicit publishing approval', 'The user reviews the exact video, caption, destination and settings and then presses the final publish action. WolfSocial does not automatically publish TikTok posts or silently choose a privacy value.'],
  ['Status and control', 'WolfSocial displays the publishing result returned by TikTok. Users can disconnect TikTok from WolfSocial, revoke authorization through TikTok and request deletion using the public data-deletion instructions.'],
] as const;

export default function TikTokIntegrationPage() {
  return (
    <WolfSocialPublicPage eyebrow="TikTok integration" title="How TikTok works inside WolfSocial." summary="WolfSocial uses TikTok’s official Login Kit and Content Posting API to provide account connection and creator-controlled Direct Post. Every action begins with and remains controlled by the user.">
      <div className="grid gap-5 md:grid-cols-2">
        {sections.map(([title, copy], index) => <section key={title} className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm"><p className="text-xs font-black uppercase tracking-[0.18em] text-red-600">Step {index + 1}</p><h2 className="mt-3 text-xl font-bold">{title}</h2><p className="mt-3 text-sm leading-7 text-slate-600">{copy}</p></section>)}
      </div>
      <section className="mt-12 rounded-2xl border border-emerald-200 bg-emerald-50 p-7"><h2 className="text-xl font-bold text-emerald-950">User protections</h2><p className="mt-3 leading-7 text-emerald-900">WolfSocial never asks for a TikTok password, does not sell connected-account data, does not publish without an explicit action and provides public Terms of Service, Privacy Policy, support and data-deletion instructions.</p></section>
    </WolfSocialPublicPage>
  );
}

import type { Metadata } from 'next';
import Link from 'next/link';
import { BarChart3, CalendarDays, CheckCircle2, FolderOpen, MessageCircle, Send, ShieldCheck } from 'lucide-react';
import { WolfSocialPublicPage } from '@/components/social/WolfSocialPublicSite';

export const metadata: Metadata = {
  title: 'Product overview | WolfSocial',
  description: 'Detailed information about the WolfSocial web and iOS social publishing service.',
  alternates: { canonical: 'https://social.wolfgrid.app/product' },
};

const capabilities = [
  [Send, 'Create and publish', 'Upload user-owned photos or videos, write captions, choose exact destination accounts and review each platform-specific version before publishing.'],
  [CalendarDays, 'Schedule and track', 'Keep drafts, scheduled posts, publishing progress and completed posts in one calendar with a status for every destination.'],
  [MessageCircle, 'Manage engagement', 'Review supported comments and messages from connected professional accounts and approve replies from a shared inbox.'],
  [BarChart3, 'Review performance', 'See available account and post metrics returned by connected platforms without selling or using that data for advertising.'],
  [FolderOpen, 'Media library', 'Store media supplied by the user for use in drafts and scheduled posts, with deletion controls in the workspace.'],
  [ShieldCheck, 'User-controlled connections', 'Every platform is connected through its official authorization flow and can be disconnected by the account owner.'],
] as const;

export default function ProductPage() {
  return (
    <WolfSocialPublicPage eyebrow="Product overview" title="A complete, user-controlled social publishing workspace." summary="WolfSocial is a production web and iOS service for creators, businesses and teams. It centralizes content preparation, account connections, publishing, scheduling, supported engagement and performance reporting.">
      <section>
        <h2 className="text-3xl font-black tracking-tight">What the service does</h2>
        <div className="mt-8 grid gap-5 md:grid-cols-2 lg:grid-cols-3">
          {capabilities.map(([Icon, title, copy]) => <article key={title} className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm"><Icon className="h-6 w-6 text-red-600" /><h3 className="mt-5 text-lg font-bold">{title}</h3><p className="mt-2 text-sm leading-6 text-slate-600">{copy}</p></article>)}
        </div>
      </section>

      <section className="mt-16 grid gap-8 lg:grid-cols-[.8fr_1.2fr]">
        <div><p className="text-sm font-bold uppercase tracking-wider text-red-600">Publishing workflow</p><h2 className="mt-3 text-3xl font-black tracking-tight">Nothing is posted without approval.</h2><p className="mt-4 leading-7 text-slate-600">WolfSocial prepares content in the cloud but keeps publishing decisions with the account owner. Platform permissions are requested only when a user connects that platform.</p></div>
        <ol className="space-y-3">
          {['Connect an account using the platform’s official authorization screen.', 'Upload media and select the exact connected destination account.', 'Review the media preview, caption and platform-required settings.', 'Explicitly approve immediate publishing, scheduling or draft delivery.', 'Track the platform response and publishing status in WolfSocial.'].map((step, index) => <li key={step} className="flex gap-4 rounded-xl border border-slate-200 bg-white p-4"><span className="font-black text-red-600">{index + 1}</span><span className="text-sm leading-6 text-slate-700">{step}</span></li>)}
        </ol>
      </section>

      <section className="mt-16 rounded-3xl bg-slate-950 p-8 text-white sm:p-10">
        <h2 className="text-3xl font-black tracking-tight">Supported surfaces and controls</h2>
        <div className="mt-7 grid gap-4 md:grid-cols-2">
          {['Web application at social.wolfgrid.app', 'WolfGrid Sales experience for iOS', 'Explicit connection and disconnection controls', 'Per-post account and privacy selection', 'Terms, privacy and deletion instructions available publicly', 'Support at support@wolfgrid.app'].map((item) => <p key={item} className="flex gap-3 text-sm leading-6 text-slate-300"><CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-400" />{item}</p>)}
        </div>
        <div className="mt-8 flex flex-wrap gap-4 text-sm font-bold"><Link href="/tiktok-integration" className="rounded-full bg-white px-5 py-3 text-slate-950">TikTok integration details</Link><Link href="/support" className="rounded-full border border-white/20 px-5 py-3">Contact support</Link></div>
      </section>
    </WolfSocialPublicPage>
  );
}

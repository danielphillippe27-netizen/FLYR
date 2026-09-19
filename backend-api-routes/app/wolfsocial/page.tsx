import Link from 'next/link';
import Image from 'next/image';
import {
  ArrowRight,
  BarChart3,
  CalendarDays,
  Check,
  ChevronRight,
  Clock3,
  Instagram,
  Linkedin,
  MessageCircle,
  Play,
  Send,
  ShieldCheck,
  Sparkles,
  Youtube,
} from 'lucide-react';

export const metadata = {
  title: 'WolfSocial | Social media publishing and engagement',
  description: 'WolfSocial is a social media management application for planning, publishing, scheduling, replying and measuring across connected social accounts.',
  icons: {
    icon: [{ url: '/wolfsocial-icon.svg', type: 'image/svg+xml' }],
    shortcut: '/wolfsocial-icon.svg',
    apple: '/wolfsocial-icon-1024.png',
  },
  alternates: { canonical: 'https://social.wolfgrid.app/wolfsocial' },
  openGraph: {
    title: 'WolfSocial | Social media publishing and engagement',
    description: 'Plan, publish, schedule, reply and measure across connected social accounts from one user-controlled workspace.',
    url: 'https://social.wolfgrid.app/wolfsocial',
    siteName: 'WolfSocial',
    images: [{ url: 'https://social.wolfgrid.app/og.png', width: 1200, height: 630, alt: 'WolfSocial social publishing workspace' }],
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'WolfSocial — Your whole social presence. One workspace.',
    description: 'Plan, publish, reply and measure across every connected social account.',
    images: ['https://social.wolfgrid.app/og.png'],
  },
};

const platforms = [
  { name: 'Facebook', mark: 'f', tone: 'bg-[#1877f2]' },
  { name: 'Instagram', icon: Instagram, tone: 'bg-gradient-to-br from-purple-600 via-pink-500 to-orange-400' },
  { name: 'TikTok', mark: '♪', tone: 'bg-black ring-1 ring-white/20' },
  { name: 'YouTube Shorts', icon: Youtube, tone: 'bg-[#ff0000]' },
  { name: 'LinkedIn', icon: Linkedin, tone: 'bg-[#0a66c2]' },
];

const features = [
  {
    icon: Send,
    title: 'Publish everywhere',
    copy: 'Create once, tailor the caption and settings for each account, then publish with final approval.',
  },
  {
    icon: CalendarDays,
    title: 'Plan without chaos',
    copy: 'Keep drafts, scheduled posts and your whole content calendar together across web and iOS.',
  },
  {
    icon: MessageCircle,
    title: 'Stay in the conversation',
    copy: 'Bring supported comments and messages into one inbox so important replies do not disappear.',
  },
  {
    icon: BarChart3,
    title: 'Know what is working',
    copy: 'Compare account and post performance without rebuilding the story in a spreadsheet.',
  },
];

export default function WolfSocialLandingPage() {
  return (
    <main className="min-h-screen overflow-hidden bg-[#08090c] text-white">
      <div className="pointer-events-none absolute inset-x-0 top-0 h-[760px] bg-[radial-gradient(circle_at_75%_20%,rgba(239,68,68,.18),transparent_28%),radial-gradient(circle_at_25%_5%,rgba(255,255,255,.08),transparent_24%)]" />

      <nav className="relative z-20 mx-auto flex max-w-7xl items-center justify-between px-5 py-5 sm:px-8">
        <Link href="/" className="flex items-center gap-2.5 text-xl font-black tracking-[-0.04em]" aria-label="WolfSocial home">
          <Image src="/wolfsocial-icon.svg" alt="" width={36} height={36} priority />
          <span>WOLF<span className="text-red-500">SOCIAL</span></span>
        </Link>
        <div className="hidden items-center gap-8 text-sm font-medium text-slate-300 md:flex">
          <Link href="/product" className="transition hover:text-white">Product</Link>
          <Link href="/tiktok-integration" className="transition hover:text-white">TikTok integration</Link>
          <Link href="/about" className="transition hover:text-white">About</Link>
          <Link href="/support" className="transition hover:text-white">Support</Link>
        </div>
        <div className="flex items-center gap-2 sm:gap-3">
          <Link href="/login?next=/app" className="px-3 py-2 text-sm font-semibold text-slate-300 transition hover:text-white">
            Sign in
          </Link>
          <Link href="/signup" className="rounded-full bg-white px-4 py-2.5 text-sm font-bold text-black transition hover:bg-red-500 hover:text-white sm:px-5">
            Start free
          </Link>
        </div>
      </nav>

      <section className="relative mx-auto grid max-w-7xl gap-14 px-5 pb-20 pt-16 sm:px-8 sm:pt-24 lg:grid-cols-[1.02fr_.98fr] lg:items-center lg:pb-28">
        <div>
          <div className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[.06] px-3 py-1.5 text-xs font-semibold text-slate-200">
            <Sparkles className="h-3.5 w-3.5 text-red-400" />
            WolfSocial social media management platform
          </div>
          <h1 className="mt-7 max-w-3xl text-5xl font-black leading-[.97] tracking-[-0.055em] sm:text-6xl lg:text-7xl">
            WolfSocial puts your whole social presence in <span className="text-red-500">one workspace.</span>
          </h1>
          <p className="mt-7 max-w-xl text-lg leading-8 text-slate-300">
            WolfSocial is a social media management application operated by WolfGrid. Creators, businesses and teams use it to plan, create, schedule and publish content, manage supported comments and messages, and review performance across accounts they explicitly connect.
          </p>
          <div className="mt-9 flex flex-col gap-3 sm:flex-row">
            <Link href="/signup" className="group inline-flex items-center justify-center gap-2 rounded-full bg-red-600 px-6 py-3.5 font-bold transition hover:bg-red-500">
              Create your free workspace
              <ArrowRight className="h-4 w-4 transition group-hover:translate-x-1" />
            </Link>
            <a href="#how-it-works" className="inline-flex items-center justify-center gap-2 rounded-full border border-white/15 bg-white/[.03] px-6 py-3.5 font-bold transition hover:bg-white/[.08]">
              <Play className="h-4 w-4 fill-current" /> See how it works
            </a>
          </div>
          <div className="mt-7 flex flex-wrap gap-x-5 gap-y-2 text-xs text-slate-400">
            {['No credit card required', 'Final approval stays with you', 'Web + iOS'].map((item) => (
              <span key={item} className="flex items-center gap-1.5"><Check className="h-3.5 w-3.5 text-emerald-400" />{item}</span>
            ))}
          </div>
        </div>

        <ProductPreview />
      </section>

      <section id="platforms" className="relative border-y border-white/10 bg-white/[.025]">
        <div className="mx-auto max-w-7xl px-5 py-12 sm:px-8">
          <p className="text-center text-xs font-bold uppercase tracking-[.24em] text-slate-500">Connect the channels your audience already uses</p>
          <div className="mt-8 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
            {platforms.map(({ name, icon: Icon, mark, tone }) => (
              <div key={name} className="flex items-center gap-3 rounded-2xl border border-white/10 bg-black/20 px-4 py-4">
                <span className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-lg font-black text-white ${tone}`}>
                  {Icon ? <Icon className="h-5 w-5" /> : mark}
                </span>
                <span className="text-sm font-semibold">{name}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="features" className="mx-auto max-w-7xl px-5 py-24 sm:px-8">
        <div className="max-w-2xl">
          <p className="text-sm font-bold uppercase tracking-[.22em] text-red-500">Everything in one flow</p>
          <h2 className="mt-4 text-4xl font-black tracking-[-0.04em] sm:text-5xl">What WolfSocial does</h2>
          <p className="mt-5 text-lg leading-8 text-slate-400">WolfSocial gives users a calm, organized workflow to connect accounts they manage, upload their own media, customize each post, choose its audience and privacy settings, and explicitly approve publishing. It does not publish or reply without the user’s action.</p>
        </div>
        <div className="mt-12 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {features.map(({ icon: Icon, title, copy }) => (
            <article key={title} className="group rounded-3xl border border-white/10 bg-[#101217] p-6 transition hover:-translate-y-1 hover:border-red-500/40">
              <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-red-500/10 text-red-400"><Icon className="h-5 w-5" /></span>
              <h3 className="mt-6 text-lg font-bold">{title}</h3>
              <p className="mt-3 text-sm leading-6 text-slate-400">{copy}</p>
            </article>
          ))}
        </div>
      </section>

      <section id="how-it-works" className="border-y border-white/10 bg-[#0d0f13]">
        <div className="mx-auto grid max-w-7xl gap-12 px-5 py-24 sm:px-8 lg:grid-cols-[.85fr_1.15fr] lg:items-center">
          <div>
            <p className="text-sm font-bold uppercase tracking-[.22em] text-red-500">From idea to audience</p>
            <h2 className="mt-4 text-4xl font-black tracking-[-0.04em]">A workflow you can trust.</h2>
            <p className="mt-5 text-lg leading-8 text-slate-400">Wolfey can help with words and replies, but nothing is published without your approval.</p>
            <Link href="/signup" className="mt-8 inline-flex items-center gap-2 font-bold text-white">Start creating <ChevronRight className="h-4 w-4 text-red-500" /></Link>
          </div>
          <div className="grid gap-4 sm:grid-cols-3">
            {[
              ['01', 'Connect', 'Link the social accounts you manage.'],
              ['02', 'Create', 'Upload media and tailor each version.'],
              ['03', 'Approve', 'Publish now or schedule for later.'],
            ].map(([step, title, copy]) => (
              <div key={step} className="rounded-3xl border border-white/10 bg-white/[.035] p-6">
                <span className="text-xs font-black tracking-[.2em] text-red-500">{step}</span>
                <h3 className="mt-10 text-xl font-bold">{title}</h3>
                <p className="mt-3 text-sm leading-6 text-slate-400">{copy}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-5xl px-5 py-24 text-center sm:px-8">
        <ShieldCheck className="mx-auto h-8 w-8 text-emerald-400" />
        <h2 className="mt-5 text-4xl font-black tracking-[-0.04em] sm:text-5xl">Ready to make social feel manageable?</h2>
        <p className="mx-auto mt-5 max-w-2xl text-lg leading-8 text-slate-400">Create a workspace for yourself, your business or your team. You can connect accounts when you are ready.</p>
        <Link href="/signup" className="mt-8 inline-flex items-center gap-2 rounded-full bg-white px-7 py-3.5 font-bold text-black transition hover:bg-red-500 hover:text-white">Create your workspace <ArrowRight className="h-4 w-4" /></Link>
      </section>

      <footer className="border-t border-white/10">
        <div className="mx-auto flex max-w-7xl flex-col gap-6 px-5 py-10 text-sm text-slate-500 sm:px-8 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <div className="flex items-center gap-2 font-black text-white"><Image src="/wolfsocial-icon.svg" alt="" width={28} height={28} /><span>WOLF<span className="text-red-500">SOCIAL</span></span></div>
            <p className="mt-2">A WolfGrid product for everyone.</p>
          </div>
          <div className="flex flex-wrap gap-x-6 gap-y-3"><Link href="/product">Product</Link><Link href="/about">About</Link><Link href="/privacy">Privacy</Link><Link href="/terms">Terms</Link><Link href="/data-deletion">Data deletion</Link><Link href="/support">Support</Link></div>
          <p>© 2026 WolfGrid Inc.</p>
        </div>
      </footer>
    </main>
  );
}

function ProductPreview() {
  return (
    <div className="relative">
      <div className="absolute -inset-8 rounded-full bg-red-500/10 blur-3xl" />
      <div className="relative overflow-hidden rounded-[2rem] border border-white/15 bg-[#11141a] p-3 shadow-2xl shadow-black/60">
        <div className="flex items-center gap-2 border-b border-white/10 px-3 pb-3 pt-1">
          <span className="h-2.5 w-2.5 rounded-full bg-red-500" /><span className="h-2.5 w-2.5 rounded-full bg-amber-400" /><span className="h-2.5 w-2.5 rounded-full bg-emerald-400" />
          <span className="ml-auto text-[10px] font-semibold text-slate-500">WOLFSOCIAL WORKSPACE</span>
        </div>
        <div className="grid min-h-[420px] grid-cols-[58px_1fr] sm:grid-cols-[150px_1fr]">
          <aside className="border-r border-white/10 p-3">
            <p className="hidden text-xs font-black sm:block">WOLF<span className="text-red-500">SOCIAL</span></p>
            <div className="mt-8 space-y-2">
              {['Overview', 'Create', 'Calendar', 'Inbox', 'Analytics'].map((item, index) => (
                <div key={item} className={`flex items-center gap-2 rounded-lg px-2 py-2 text-[11px] ${index === 1 ? 'bg-red-500 text-white' : 'text-slate-500'}`}>
                  <span className="h-1.5 w-1.5 rounded-full bg-current" /><span className="hidden sm:inline">{item}</span>
                </div>
              ))}
            </div>
          </aside>
          <div className="p-4 sm:p-5">
            <div className="flex items-start justify-between"><div><p className="text-xs text-slate-500">Composer</p><h3 className="mt-1 text-lg font-bold">Create a post</h3></div><span className="rounded-full bg-emerald-500/10 px-2 py-1 text-[10px] font-bold text-emerald-400">5 connected</span></div>
            <div className="mt-5 grid gap-3 sm:grid-cols-[1fr_.8fr]">
              <div className="rounded-2xl border border-white/10 bg-black/20 p-4">
                <p className="text-[10px] font-semibold uppercase tracking-wider text-slate-500">Caption</p>
                <p className="mt-3 text-xs leading-5 text-slate-300">Your next idea deserves more than one feed. Create it once, then make every version feel native.</p>
                <div className="mt-5 flex flex-wrap gap-2">{platforms.map(({ name }) => <span key={name} className="rounded-full border border-white/10 px-2 py-1 text-[9px] text-slate-400">{name === 'YouTube Shorts' ? 'YouTube' : name}</span>)}</div>
                <div className="mt-5 rounded-xl border border-dashed border-white/15 bg-white/[.025] p-4 text-center text-[10px] text-slate-500">Drop photo or video</div>
              </div>
              <div className="rounded-2xl bg-gradient-to-br from-red-500 via-red-700 to-slate-950 p-4">
                <div className="flex justify-between"><span className="rounded-full bg-black/25 px-2 py-1 text-[9px]">Preview</span><span className="text-xs">•••</span></div>
                <div className="mt-20 rounded-xl bg-black/25 p-3 backdrop-blur"><p className="text-xs font-bold">Create once.</p><p className="mt-1 text-[10px] text-white/70">Publish everywhere.</p></div>
              </div>
            </div>
            <div className="mt-3 flex items-center justify-between rounded-xl border border-white/10 bg-white/[.03] px-3 py-3"><span className="flex items-center gap-2 text-[10px] text-slate-400"><Clock3 className="h-3.5 w-3.5" />Schedule for Thursday · 9:00 AM</span><span className="rounded-lg bg-white px-3 py-1.5 text-[10px] font-bold text-black">Review post</span></div>
          </div>
        </div>
      </div>
    </div>
  );
}

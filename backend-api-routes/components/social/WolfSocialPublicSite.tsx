import Image from 'next/image';
import Link from 'next/link';
import type { ReactNode } from 'react';

const navigation = [
  { href: '/product', label: 'Product' },
  { href: '/tiktok-integration', label: 'TikTok integration' },
  { href: '/about', label: 'About' },
  { href: '/support', label: 'Support' },
];

export function WolfSocialPublicHeader() {
  return (
    <header className="border-b border-white/10 bg-[#08090c] text-white">
      <div className="mx-auto flex max-w-6xl flex-col gap-4 px-5 py-5 sm:px-8 md:flex-row md:items-center md:justify-between">
        <Link href="/" className="flex items-center gap-2.5 text-xl font-black tracking-[-0.04em]" aria-label="WolfSocial home">
          <Image src="/wolfsocial-icon.svg" alt="" width={36} height={36} priority />
          <span>WOLF<span className="text-red-500">SOCIAL</span></span>
        </Link>
        <nav aria-label="Public website" className="flex flex-wrap gap-x-5 gap-y-2 text-sm font-semibold text-slate-300">
          {navigation.map((item) => <Link key={item.href} href={item.href} className="hover:text-white">{item.label}</Link>)}
        </nav>
      </div>
    </header>
  );
}

export function WolfSocialPublicFooter() {
  return (
    <footer className="border-t border-slate-200 bg-white">
      <div className="mx-auto flex max-w-6xl flex-col gap-5 px-5 py-8 text-sm text-slate-600 sm:px-8 lg:flex-row lg:items-center lg:justify-between">
        <div><p className="font-black text-slate-950">WOLF<span className="text-red-600">SOCIAL</span></p><p className="mt-1">A social publishing service operated by WolfGrid.</p></div>
        <div className="flex flex-wrap gap-x-6 gap-y-2">
          <Link href="/product">Product</Link><Link href="/about">About</Link><Link href="/support">Support</Link><Link href="/terms">Terms of Service</Link><Link href="/privacy">Privacy Policy</Link><Link href="/data-deletion">Data deletion</Link>
        </div>
        <p>© 2026 WolfGrid Inc.</p>
      </div>
    </footer>
  );
}

export function WolfSocialPublicPage({ eyebrow, title, summary, children }: { eyebrow: string; title: string; summary: string; children: ReactNode }) {
  return (
    <div className="min-h-screen bg-slate-50 text-slate-950">
      <WolfSocialPublicHeader />
      <main>
        <section className="border-b border-slate-200 bg-white">
          <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
            <p className="text-sm font-black uppercase tracking-[0.2em] text-red-600">{eyebrow}</p>
            <h1 className="mt-4 max-w-4xl text-4xl font-black tracking-[-0.04em] sm:text-6xl">{title}</h1>
            <p className="mt-6 max-w-3xl text-lg leading-8 text-slate-600">{summary}</p>
          </div>
        </section>
        <div className="mx-auto max-w-6xl px-5 py-14 sm:px-8">{children}</div>
      </main>
      <WolfSocialPublicFooter />
    </div>
  );
}

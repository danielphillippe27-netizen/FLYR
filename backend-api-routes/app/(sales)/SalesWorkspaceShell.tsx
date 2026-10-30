'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState, type ReactNode } from 'react';
import {
  BarChart3,
  CalendarDays,
  CalendarPlus,
  FileText,
  Home,
  Inbox,
  KanbanSquare,
  Library,
  ListChecks,
  Menu,
  MoreHorizontal,
  MessageCircleMore,
  PhoneCall,
  PlayCircle,
  Plus,
  Settings,
  Users,
  X,
} from 'lucide-react';
import { WorkspaceProvider, useWorkspace } from '@/lib/workspace-context';
import { formatPhoneDisplay } from '@/lib/dialer/phone';
import { DialerRuntimeProvider } from '@/components/dialer/DialerRuntimeProvider';
import { cn } from '@/lib/utils';

const navigation = [
  { href: '/inbox', label: 'Inbox', icon: Inbox },
  { href: '/follow-up', label: 'Follow Up', icon: ListChecks },
  { href: '/dialer', label: 'Dialler', icon: PhoneCall },
  { href: '/leads', label: 'Contacts', icon: Users },
  { href: '/scraper', label: 'Add Leads', icon: Plus },
];

const moreNavigation = [
  { href: '/home', label: 'Home', icon: Home },
  { href: '/sales/pipeline', label: 'Pipeline', icon: KanbanSquare },
  { href: '/social', label: 'Social', icon: MessageCircleMore },
  { href: '/meetings', label: 'Meetings', icon: CalendarDays },
  { href: '/booking', label: 'Booking', icon: CalendarPlus },
  { href: '/saved-content', label: 'Saved Content', icon: Library },
  { href: '/scripts', label: 'Scripts', icon: FileText },
  { href: '/demo-center', label: 'Demo', icon: PlayCircle },
  { href: '/stats', label: 'Performance', icon: BarChart3 },
  { href: '/settings', label: 'Settings', icon: Settings },
];

function WorkspaceChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);
  const { currentWorkspaceId } = useWorkspace();
  const [identity, setIdentity] = useState<{ firstName: string; phone: string | null } | null>(null);

  useEffect(() => {
    setIdentity(null);
    if (!currentWorkspaceId) return;
    const controller = new AbortController();
    void fetch(`/api/dialer/settings?workspaceId=${encodeURIComponent(currentWorkspaceId)}`, {
      credentials: 'include',
      signal: controller.signal,
    }).then(async (response) => {
      if (!response.ok) return;
      const data = await response.json() as {
        salesperson?: { fullName?: string | null; assignedPhoneNumber?: string | null };
        settings?: { defaultFromNumber?: string | null } | null;
      };
      if (controller.signal.aborted) return;
      setIdentity({
        firstName: data.salesperson?.fullName?.trim().split(/\s+/)[0] || '',
        phone: data.salesperson?.assignedPhoneNumber || data.settings?.defaultFromNumber || null,
      });
    }).catch(() => undefined);
    return () => controller.abort();
  }, [currentWorkspaceId]);
  const isInbox = pathname === '/inbox' || pathname.startsWith('/inbox/');

  const isActive = (href: string) => pathname === href || pathname.startsWith(`${href}/`);
  const sidebar = (compact: boolean) => (
    <>
      <div className={cn('flex h-20 shrink-0 items-center border-b border-white/10', compact ? 'justify-center' : 'px-5')}>
        <Link href="/home" aria-label="WolfGrid Sales home" className="text-xl font-black tracking-[-0.06em] text-white">
          {compact ? <>W<span className="text-red-500">G</span></> : <>WOLF<span className="text-red-500">GRID</span></>}
        </Link>
        {!compact && <>
          <span className="ml-3 rounded-full bg-white/10 px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-white/60">Sales</span>
          <button type="button" className="ml-auto rounded-md p-2 text-white/70" onClick={() => setMobileOpen(false)} aria-label="Close navigation">
            <X className="h-5 w-5" />
          </button>
        </>}
      </div>
      <nav aria-label="Sales navigation" className="flex flex-1 flex-col gap-2 px-3 py-5">
        <div className="flex flex-col gap-2">
        {navigation.map(({ href, label, icon: Icon }) => (
          <Link
            key={href}
            href={href}
            aria-label={label}
            aria-current={isActive(href) ? 'page' : undefined}
            onClick={() => setMobileOpen(false)}
            className={cn('group relative flex min-h-11 shrink-0 items-center rounded-xl text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500', compact ? 'justify-center' : 'gap-3 px-3', isActive(href) ? 'bg-white/10 text-white' : 'text-white/55 hover:bg-white/[0.06] hover:text-white')}
          >
            <Icon aria-hidden="true" className={cn('h-5 w-5', isActive(href) && 'text-red-500')} />
            {compact ? <span aria-hidden="true" className="pointer-events-none absolute left-full z-50 ml-3 whitespace-nowrap rounded-lg bg-[#292a2e] px-3 py-2 text-sm text-white shadow-lg opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100">{label}</span> : label}
          </Link>
        ))}
        </div>
        <details
          className="group/more relative mt-auto"
          onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget)) event.currentTarget.open = false; }}
          onKeyDown={(event) => { if (event.key === 'Escape') { event.currentTarget.open = false; event.currentTarget.querySelector('summary')?.focus(); } }}
        >
          <summary aria-label="More" className={cn('group relative flex min-h-11 cursor-pointer list-none items-center rounded-xl text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500 [&::-webkit-details-marker]:hidden', compact ? 'justify-center' : 'gap-3 px-3', moreNavigation.some(({ href }) => isActive(href)) ? 'bg-white/10 text-white' : 'text-white/55 hover:bg-white/[0.06] hover:text-white')}>
            <MoreHorizontal aria-hidden="true" className="h-5 w-5" />
            {compact ? <span aria-hidden="true" className="pointer-events-none absolute left-full z-50 ml-3 whitespace-nowrap rounded-lg bg-[#292a2e] px-3 py-2 text-white shadow-lg opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100 group-open/more:hidden">More</span> : 'More'}
          </summary>
          <div className={cn('absolute bottom-0 z-50 w-56 rounded-xl border border-white/10 bg-[#1c1d21] p-2 shadow-xl', compact ? 'left-full ml-3' : 'left-0 mb-14')}>
            <p className="px-3 py-2 text-xs font-semibold uppercase tracking-wider text-white/40">More</p>
            {moreNavigation.map(({ href, label, icon: Icon }) => (
              <Link key={href} href={href} aria-current={isActive(href) ? 'page' : undefined} onClick={(event) => { event.currentTarget.closest('details')?.removeAttribute('open'); setMobileOpen(false); }} className={cn('flex min-h-10 items-center gap-3 rounded-lg px-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500', isActive(href) ? 'bg-white/10 text-white' : 'text-white/70 hover:bg-white/10 hover:text-white')}>
                <Icon aria-hidden="true" className={cn('h-[18px] w-[18px]', isActive(href) && 'text-red-500')} />{label}
              </Link>
            ))}
          </div>
        </details>
      </nav>
    </>
  );

  return (
    <div className={cn('bg-gray-50 text-foreground dark:bg-background', isInbox ? 'h-dvh overflow-hidden' : 'min-h-screen')}>
      {mobileOpen ? (
        <>
          <button
            type="button"
            className="fixed inset-0 z-40 bg-black/50 md:hidden"
            onClick={() => setMobileOpen(false)}
            aria-label="Close navigation"
          />
          <aside className="fixed inset-y-0 left-0 z-50 flex w-72 flex-col bg-[#101115] md:hidden">
            {sidebar(false)}
          </aside>
        </>
      ) : null}
      <div className={isInbox ? 'flex h-full min-h-0 flex-col' : 'min-h-screen'}>
        <header className="sticky top-0 z-30 flex min-h-16 shrink-0 items-center gap-3 border-b border-border bg-white/95 px-4 backdrop-blur md:px-6 dark:bg-card/95">
          <button
            type="button"
            className="mr-3 rounded-md border border-border p-2 md:hidden"
            onClick={() => setMobileOpen(true)}
            aria-label="Open navigation"
          >
            <Menu className="h-5 w-5" />
          </button>
          <div aria-label="Salesperson identity" className="flex min-w-0 flex-1 flex-wrap items-center gap-x-2 gap-y-1 py-3 text-sm leading-5 sm:gap-x-3">
            <span className="font-bold text-foreground">WolfGrid</span>
            <span aria-hidden="true" className="text-muted-foreground/50">/</span>
            <span className="font-medium text-muted-foreground">Salesperson</span>
            {identity?.firstName && <>
              <span aria-hidden="true" className="text-muted-foreground/50">/</span>
              <span className="font-semibold text-foreground">{identity.firstName}</span>
            </>}
            {identity?.phone && <span className="inline-flex items-center gap-2 sm:gap-3">
              <span aria-hidden="true" className="text-muted-foreground/50">/</span>
              <span className="whitespace-nowrap font-medium tabular-nums text-foreground">{formatPhoneDisplay(identity.phone)}</span>
            </span>}
          </div>
          <nav aria-label="Sales navigation" className="ml-auto hidden shrink-0 items-center gap-1 md:flex">
            {navigation.map(({ href, label, icon: Icon }) => (
              <Link key={href} href={href} aria-label={label} aria-current={isActive(href) ? 'page' : undefined}
                title={label} className={cn('flex h-10 items-center gap-2 rounded-lg px-3 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500', isActive(href) ? 'bg-red-50 text-red-600' : 'text-muted-foreground hover:bg-muted hover:text-foreground')}>
                <Icon aria-hidden="true" className="h-4 w-4" /><span className="hidden lg:inline">{label}</span>
              </Link>
            ))}
            <details className="relative"
              onBlur={(event) => { if (!event.currentTarget.contains(event.relatedTarget)) event.currentTarget.open = false; }}
              onKeyDown={(event) => { if (event.key === 'Escape') { event.currentTarget.open = false; event.currentTarget.querySelector('summary')?.focus(); } }}>
              <summary aria-label="More navigation" className="flex h-10 cursor-pointer list-none items-center gap-2 rounded-lg px-3 text-sm text-muted-foreground hover:bg-muted focus-visible:ring-2 focus-visible:ring-red-500 [&::-webkit-details-marker]:hidden"><MoreHorizontal className="h-5 w-5" /><span className="hidden lg:inline">More</span></summary>
              <div className="absolute right-0 top-full z-50 mt-2 w-56 rounded-xl border bg-popover p-2 text-popover-foreground shadow-xl">
                {moreNavigation.map(({ href, label, icon: Icon }) => (
                  <Link key={href} href={href} aria-current={isActive(href) ? 'page' : undefined}
                    onClick={(event) => event.currentTarget.closest('details')?.removeAttribute('open')}
                    className={cn('flex min-h-10 items-center gap-3 rounded-lg px-3 text-sm hover:bg-muted', isActive(href) && 'bg-red-50 text-red-600')}>
                    <Icon className="h-4 w-4" aria-hidden="true" />{label}
                  </Link>
                ))}
              </div>
            </details>
          </nav>
        </header>
        <main data-sales-workspace-content className={cn('min-w-0', isInbox ? 'min-h-0 flex-1 overflow-hidden' : 'min-h-[calc(100vh-4rem)]')}>{children}</main>
      </div>
    </div>
  );
}

export function SalesWorkspaceShell({ children }: { children: ReactNode }) {
  return (
    <WorkspaceProvider>
      <DialerRuntimeProvider>
        <WorkspaceChrome>{children}</WorkspaceChrome>
      </DialerRuntimeProvider>
    </WorkspaceProvider>
  );
}

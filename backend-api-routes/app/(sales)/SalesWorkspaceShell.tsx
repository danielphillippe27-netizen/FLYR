'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState, type ReactNode } from 'react';
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
  MessageCircleMore,
  PhoneCall,
  PlayCircle,
  Plus,
  Settings,
  Users,
  X,
} from 'lucide-react';
import { WorkspaceProvider } from '@/lib/workspace-context';
import { DialerRuntimeProvider } from '@/components/dialer/DialerRuntimeProvider';
import { cn } from '@/lib/utils';

const navigation = [
  { href: '/home', label: 'Home', icon: Home },
  { href: '/inbox', label: 'Inbox', icon: Inbox },
  { href: '/sales/pipeline', label: 'Pipeline', icon: KanbanSquare },
  { href: '/follow-up', label: 'Follow Up', icon: ListChecks },
  { href: '/meetings', label: 'Meetings', icon: CalendarDays },
  { href: '/booking', label: 'Booking', icon: CalendarPlus },
  { href: '/dialer', label: 'Dialler', icon: PhoneCall },
  { href: '/saved-content', label: 'Saved Content', icon: Library },
  { href: '/scripts', label: 'Scripts', icon: FileText },
  { href: '/leads', label: 'Contacts', icon: Users },
  { href: '/scraper', label: 'Add Leads', icon: Plus },
  { href: '/demo-center', label: 'Demo', icon: PlayCircle },
  { href: '/stats', label: 'Performance', icon: BarChart3 },
  { href: '/social', label: 'Social', icon: MessageCircleMore },
  { href: '/settings', label: 'Settings', icon: Settings },
];

function WorkspaceChrome({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);

  const sidebar = (
    <>
      <div className="flex h-20 items-center border-b border-white/10 px-5">
        <Link href="/home" className="text-xl font-black tracking-[-0.06em] text-white">
          WOLF<span className="text-red-500">GRID</span>
        </Link>
        <span className="ml-3 rounded-full bg-white/10 px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-white/60">
          Sales
        </span>
        <button
          type="button"
          className="ml-auto rounded-md p-2 text-white/70 md:hidden"
          onClick={() => setMobileOpen(false)}
          aria-label="Close navigation"
        >
          <X className="h-5 w-5" />
        </button>
      </div>
      <nav className="flex flex-1 flex-col gap-1 overflow-y-auto px-3 py-5">
        {navigation.map(({ href, label, icon: Icon }) => {
          const active = pathname === href || pathname.startsWith(`${href}/`);
          return (
            <Link
              key={href}
              href={href}
              onClick={() => setMobileOpen(false)}
              className={cn(
                'flex min-h-11 items-center gap-3 rounded-lg px-3 text-sm font-medium transition-colors',
                active
                  ? 'bg-white/10 text-white'
                  : 'text-white/55 hover:bg-white/[0.06] hover:text-white'
              )}
            >
              <Icon className={cn('h-[18px] w-[18px]', active && 'text-red-500')} />
              {label}
            </Link>
          );
        })}
      </nav>
      <div className="border-t border-white/10 px-5 py-4 text-[11px] text-white/35">
        sales.wolfgrid.app
      </div>
    </>
  );

  return (
    <div className="min-h-screen bg-gray-50 text-foreground">
      <aside className="fixed inset-y-0 left-0 z-40 hidden w-56 flex-col bg-[#101115] md:flex">
        {sidebar}
      </aside>
      {mobileOpen ? (
        <>
          <button
            type="button"
            className="fixed inset-0 z-40 bg-black/50 md:hidden"
            onClick={() => setMobileOpen(false)}
            aria-label="Close navigation"
          />
          <aside className="fixed inset-y-0 left-0 z-50 flex w-72 flex-col bg-[#101115] md:hidden">
            {sidebar}
          </aside>
        </>
      ) : null}
      <div className="min-h-screen md:pl-56">
        <header className="sticky top-0 z-30 flex h-16 items-center border-b border-border bg-white/95 px-4 backdrop-blur md:px-6">
          <button
            type="button"
            className="mr-3 rounded-md border border-border p-2 md:hidden"
            onClick={() => setMobileOpen(true)}
            aria-label="Open navigation"
          >
            <Menu className="h-5 w-5" />
          </button>
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">WolfGrid</p>
            <p className="text-sm font-semibold">Salesperson workspace</p>
          </div>
          <div className="ml-auto flex items-center gap-2 rounded-full border border-border bg-white px-3 py-1.5 text-xs text-muted-foreground">
            <span className="h-2 w-2 rounded-full bg-emerald-500" /> Live
          </div>
        </header>
        <main className="min-h-[calc(100vh-4rem)]">{children}</main>
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

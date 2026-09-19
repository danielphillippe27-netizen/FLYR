'use client';

import { useEffect, useRef, useState } from 'react';
import { Monitor, Smartphone } from 'lucide-react';
import { getClientAsync } from '@/lib/supabase/client';
import { useWorkspace } from '@/lib/workspace-context';
import { useDialerRuntime } from './DialerRuntimeProvider';
import type { SharedActiveCall } from '@/lib/dialer/active-call';
import { normalizePhoneNumber } from '@/lib/dialer/phone';

/** Display-only companion: never replaces the local SDK's call or controls. */
export function SharedActiveCallBar() {
  const { currentWorkspaceId } = useWorkspace();
  const { device, activeLeadSnapshot } = useDialerRuntime();
  const [deviceId] = useState(() => crypto.randomUUID());
  const [userId, setUserId] = useState<string | null>(null);
  const [result, setResult] = useState<{ scope: string; calls: SharedActiveCall[]; unavailable: boolean } | null>(null);
  const [now, setNow] = useState(Date.now);
  const local = useRef({ device, activeLeadSnapshot });
  const callScope = useRef<{ id: string; scope: string } | null>(null);
  const scope = `${userId}:${currentWorkspaceId}`;

  useEffect(() => {
    local.current = { device, activeLeadSnapshot };
    if (userId && device.callIdentity && callScope.current?.id !== device.callIdentity.id) {
      callScope.current = { id: device.callIdentity.id, scope };
    }
  }, [device, activeLeadSnapshot, userId, scope]);
  useEffect(() => {
    let disposed = false;
    let unsubscribe: (() => void) | undefined;
    void getClientAsync().then(client => {
      if (disposed) return;
      const { data } = client.auth.onAuthStateChange((_event, session) => {
        setUserId(session?.user.id ?? null);
        setResult(null);
      });
      unsubscribe = () => data.subscription.unsubscribe();
    }).catch(() => setUserId(null));
    return () => { disposed = true; unsubscribe?.(); };
  }, []);

  useEffect(() => {
    if (!userId || !currentWorkspaceId) return;
    let disposed = false;
    let timer: ReturnType<typeof setTimeout>;
    let controller: AbortController | undefined;
    let timing: { id: string; startedAt: string; connectedAt: string | null } | null = null;
    let hadLocalCall = false;
    const sync = async () => {
      const { device: current, activeLeadSnapshot: lead } = local.current;
      // Hidden idle tabs need no polling; an active call keeps renewing its lease.
      if (document.hidden && !current.isInCall && !current.hasIncomingCall && !hadLocalCall) {
        timer = setTimeout(sync, 3000);
        return;
      }
      const identity = current.callIdentity;
      let call = null;
      if ((current.isInCall || current.hasIncomingCall) && identity && callScope.current?.scope === scope) {
        if (timing?.id !== identity.id) timing = { id: identity.id, startedAt: new Date().toISOString(), connectedAt: null };
        if (current.callPhase === 'connected' && !timing.connectedAt) timing.connectedAt = new Date().toISOString();
        const leadPhone = normalizePhoneNumber(lead?.phone).e164;
        const matchingLead = Boolean(leadPhone && leadPhone === normalizePhoneNumber(identity.phone).e164);
        call = {
          ...timing,
          name: (identity.name || (matchingLead ? lead?.name : null) || identity.phone || 'Call').slice(0, 300),
          phone: identity.phone,
          phase: current.callPhase === 'connected' ? 'connected' : 'connecting',
        };
      } else timing = null;
      controller = new AbortController();
      const timeout = setTimeout(() => controller?.abort(), 10_000);
      try {
        const response = await fetch('/api/dialer/active-call', {
          method: 'PUT', credentials: 'include', cache: 'no-store', signal: controller.signal,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ workspaceId: currentWorkspaceId, deviceId, platform: 'web', call }),
        });
        if (!response.ok) throw new Error('Call sync unavailable');
        const data = await response.json() as { calls: SharedActiveCall[] };
        hadLocalCall = call !== null;
        if (!disposed) setResult({ scope, calls: data.calls, unavailable: false });
      } catch {
        if (!disposed) setResult(previous => ({ scope, calls: previous?.scope === scope ? previous.calls : [], unavailable: true }));
      } finally {
        clearTimeout(timeout);
        if (!disposed) timer = setTimeout(sync, 3000);
      }
    };
    void sync();
    const clock = setInterval(() => setNow(Date.now()), 1000);
    return () => { disposed = true; clearTimeout(timer); clearInterval(clock); controller?.abort(); };
  }, [currentWorkspaceId, userId, deviceId, scope]);

  const calls = result?.scope === scope ? result.calls.filter(call => Date.parse(call.expiresAt) > now) : [];
  const unavailable = result?.scope === scope && result.unavailable;
  if (!calls.length && !(unavailable && device.isInCall)) return null;
  return (
    <aside aria-label="Calls on your other devices" className="fixed bottom-20 right-4 z-[65] w-[min(calc(100vw-2rem),22rem)] rounded-lg border border-neutral-200 bg-white p-4 text-neutral-950 shadow-lg sm:bottom-4">
      {unavailable ? <p role="status" className="text-sm">Call sync unavailable. Your call can continue.</p> : calls.map(call => (
        <div key={call.deviceId} className="flex items-start gap-3 py-1">
          {call.platform === 'ios' ? <Smartphone aria-hidden="true" className="mt-1 h-5 w-5 shrink-0" /> : <Monitor aria-hidden="true" className="mt-1 h-5 w-5 shrink-0" />}
          <div className="min-w-0">
            <p className="text-xs text-neutral-500">Calling on {call.platform === 'ios' ? 'iPhone' : 'web'}</p>
            <p className="truncate font-semibold">{call.name}</p>
            {call.phone && call.phone !== call.name ? <p className="text-sm">{call.phone}</p> : null}
            <p className="text-xs text-neutral-500">{call.phase === 'connected' ? 'Connected' : 'Connecting'}{call.connectedAt ? ` · ${Math.floor(Math.max(0, now - Date.parse(call.connectedAt)) / 60000)}:${String(Math.floor(Math.max(0, now - Date.parse(call.connectedAt)) / 1000) % 60).padStart(2, '0')}` : ''}</p>
          </div>
        </div>
      ))}
    </aside>
  );
}

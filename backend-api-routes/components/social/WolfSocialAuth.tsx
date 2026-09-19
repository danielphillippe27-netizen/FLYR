'use client';

import Link from 'next/link';
import type { ReactNode } from 'react';
import { FormEvent, useEffect, useState } from 'react';
import { ArrowRight, Check, Eye, EyeOff, ShieldCheck, Sparkles } from 'lucide-react';
import { createClient } from '@/lib/supabase/client';

type AuthMode = 'sign-in' | 'create-account';

export function WolfSocialAuth({ initialMode = 'sign-in' }: { initialMode?: AuthMode }) {
  const [mode, setMode] = useState<AuthMode>(initialMode);
  const [showPassword, setShowPassword] = useState(false);
  const [accepted, setAccepted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [isWolfSocial, setIsWolfSocial] = useState(initialMode === 'create-account');
  const [message, setMessage] = useState<{ kind: 'error' | 'success'; text: string } | null>(null);

  useEffect(() => {
    const socialHost = window.location.hostname === 'social.wolfgrid.app' || window.location.hostname.startsWith('social.');
    const search = new URLSearchParams(window.location.search);
    const requestedMode = search.get('mode');
    const accessError = search.get('error');
    setIsWolfSocial(socialHost || initialMode === 'create-account');
    if (requestedMode === 'create-account') setMode('create-account');
    if (accessError === 'not_salesperson') {
      setMessage({
        kind: 'error',
        text: 'That account does not have access to the sales workspace. Sign in with your salesperson email.',
      });
    }
  }, [initialMode]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (loading) return;
    if (mode === 'create-account' && !accepted) {
      setMessage({ kind: 'error', text: 'Please agree to the Terms and Privacy Policy to create your workspace.' });
      return;
    }
    setLoading(true);
    setMessage(null);
    const formData = new FormData(event.currentTarget);
    const normalizedEmail = String(formData.get('email') ?? '').trim().toLowerCase();
    const password = String(formData.get('password') ?? '');
    const fullName = String(formData.get('fullName') ?? '').trim();
    const supabase = createClient();

    try {
      const destination = isWolfSocial ? '/app' : '/home';
      if (mode === 'sign-in') {
        const { data, error } = await supabase.auth.signInWithPassword({ email: normalizedEmail, password });
        if (error) throw error;
        if (data.session) window.location.assign(destination);
        return;
      }

      const { data, error } = await supabase.auth.signUp({
        email: normalizedEmail,
        password,
        options: {
          data: { full_name: fullName || normalizedEmail.split('@')[0], product: 'wolfsocial' },
          emailRedirectTo: `${window.location.origin}/login?next=${encodeURIComponent(destination)}`,
        },
      });
      if (error) throw error;
      if (data.session) {
        window.location.assign(destination);
        return;
      }
      setMessage({ kind: 'success', text: 'Check your email to confirm your WolfSocial account. Then come back here to sign in.' });
      setMode('sign-in');
    } catch (error) {
      setMessage({ kind: 'error', text: error instanceof Error ? error.message : 'Authentication failed. Please try again.' });
    } finally {
      setLoading(false);
    }
  }

  const social = isWolfSocial || initialMode === 'create-account';

  return (
    <main className="min-h-screen bg-[#08090c] text-white">
      <div className="grid min-h-screen lg:grid-cols-[.92fr_1.08fr]">
        <section className="relative hidden overflow-hidden border-r border-white/10 bg-[#0e1015] p-12 lg:flex lg:flex-col lg:justify-between">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_20%_10%,rgba(239,68,68,.22),transparent_30%),radial-gradient(circle_at_80%_90%,rgba(255,255,255,.06),transparent_25%)]" />
          <Link href={social ? '/' : '/home'} className="relative text-xl font-black tracking-[-0.04em]">WOLF<span className="text-red-500">{social ? 'SOCIAL' : 'GRID'}</span></Link>
          <div className="relative max-w-lg">
            <span className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[.05] px-3 py-1.5 text-xs font-semibold text-slate-300"><Sparkles className="h-3.5 w-3.5 text-red-400" />One workspace for every channel</span>
            <h1 className="mt-7 text-5xl font-black leading-[1.02] tracking-[-0.05em]">Create your next post. <span className="text-red-500">Reach every audience.</span></h1>
            <div className="mt-8 space-y-4 text-sm text-slate-300">
              {['Publish to Facebook, Instagram, TikTok, YouTube and LinkedIn', 'Schedule and manage every connected account', 'Keep final approval in your hands'].map((item) => <p key={item} className="flex items-start gap-3"><span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-emerald-500/15 text-emerald-400"><Check className="h-3 w-3" /></span>{item}</p>)}
            </div>
          </div>
          <p className="relative text-xs text-slate-600">A WolfGrid product · Built for creators, businesses and teams</p>
        </section>

        <section className="flex min-h-screen items-center justify-center px-5 py-10 sm:px-8">
          <div className="w-full max-w-md">
            <div className="mb-8 flex items-center justify-between lg:hidden"><Link href="/" className="text-xl font-black">WOLF<span className="text-red-500">SOCIAL</span></Link><Link href="/" className="text-sm text-slate-400">Back home</Link></div>
            <p className="text-sm font-bold uppercase tracking-[.2em] text-red-500">{mode === 'sign-in' ? 'Welcome back' : 'Open to everyone'}</p>
            <h1 className="mt-3 text-4xl font-black tracking-[-0.04em]">{mode === 'sign-in' ? `Sign in to ${social ? 'WolfSocial' : 'WolfGrid'}` : 'Create your workspace'}</h1>
            <p className="mt-3 leading-7 text-slate-400">{mode === 'sign-in' ? 'Pick up where you left off.' : 'Start with one workspace. Connect your social accounts when you are ready.'}</p>

            <div className="mt-8 grid grid-cols-2 rounded-2xl border border-white/10 bg-white/[.035] p-1">
              {(['sign-in', 'create-account'] as const).map((value) => (
                <button key={value} type="button" onClick={() => { setMode(value); setMessage(null); }} className={`rounded-xl px-3 py-2.5 text-sm font-semibold transition ${mode === value ? 'bg-white text-black' : 'text-slate-400 hover:text-white'}`}>
                  {value === 'sign-in' ? 'Sign in' : 'Create account'}
                </button>
              ))}
            </div>

            <form onSubmit={submit} className="mt-6 space-y-4">
              {mode === 'create-account' ? <Field label="Full name"><input name="fullName" required autoComplete="name" placeholder="Your name" className="auth-input" /></Field> : null}
              <Field label="Email"><input name="email" type="email" required autoComplete="email" placeholder="you@example.com" className="auth-input" /></Field>
              <Field label="Password">
                <div className="relative"><input name="password" type={showPassword ? 'text' : 'password'} required minLength={8} autoComplete={mode === 'sign-in' ? 'current-password' : 'new-password'} placeholder="At least 8 characters" className="auth-input pr-12" /><button type="button" onClick={() => setShowPassword((value) => !value)} aria-label={showPassword ? 'Hide password' : 'Show password'} className="absolute inset-y-0 right-0 flex w-12 items-center justify-center text-slate-500 hover:text-white">{showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}</button></div>
              </Field>

              {mode === 'create-account' ? (
                <label className="flex cursor-pointer items-start gap-3 text-xs leading-5 text-slate-400">
                  <input type="checkbox" checked={accepted} onChange={(event) => setAccepted(event.target.checked)} className="mt-1 h-4 w-4 rounded border-white/20 bg-black accent-red-600" />
                  <span>I agree to the <Link href="/terms" target="_blank" className="text-white underline">Terms of Service</Link> and acknowledge the <Link href="/privacy" target="_blank" className="text-white underline">Privacy Policy</Link>.</span>
                </label>
              ) : null}

              {message ? <p role="alert" className={`rounded-xl border px-4 py-3 text-sm ${message.kind === 'error' ? 'border-red-500/30 bg-red-500/10 text-red-300' : 'border-emerald-500/30 bg-emerald-500/10 text-emerald-300'}`}>{message.text}</p> : null}

              <button type="submit" disabled={loading} className="group flex h-12 w-full items-center justify-center gap-2 rounded-xl bg-red-600 font-bold text-white transition hover:bg-red-500 disabled:cursor-not-allowed disabled:opacity-60">
                {loading ? 'Please wait…' : mode === 'sign-in' ? `Open ${social ? 'WolfSocial' : 'sales workspace'}` : 'Create free workspace'}
                {!loading ? <ArrowRight className="h-4 w-4 transition group-hover:translate-x-1" /> : null}
              </button>
            </form>
            <p className="mt-6 flex items-center justify-center gap-2 text-xs text-slate-600"><ShieldCheck className="h-3.5 w-3.5" />Your connected account tokens are encrypted.</p>
          </div>
        </section>
      </div>
    </main>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return <label className="block text-sm font-medium text-slate-300">{label}<span className="mt-2 block">{children}</span></label>;
}

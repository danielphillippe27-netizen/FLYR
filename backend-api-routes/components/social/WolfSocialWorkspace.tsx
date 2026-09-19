'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Image from 'next/image';
import { BarChart3, CalendarDays, Check, Facebook, FolderOpen, Home, Instagram, Linkedin, Loader2, MessageCircle, Play, Plug, Send, Settings, Sparkles, Trash2, Upload, Youtube } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';

type Platform = 'facebook' | 'instagram' | 'tiktok' | 'youtube' | 'linkedin';
type Section = 'overview' | 'create' | 'calendar' | 'inbox' | 'library' | 'analytics' | 'connections' | 'settings';
type Connection = { id: string; platform: Platform; account_name: string | null; account_avatar_url?: string | null; account_type?: string | null; page_role?: string | null; status: string; last_error?: string | null };
type ProviderAvailability = Record<Platform, { configured: boolean; message?: string | null }>;
type Asset = { id: string; original_name: string; mime_type: string; byte_size?: number; duration_seconds?: number | null; preview_url?: string };
type TargetSettings = { privacyLevel?: string; allowComments?: boolean; allowDuet?: boolean; allowStitch?: boolean; musicUsageConfirmed?: boolean; explicitConsent?: boolean; commercialContent?: boolean; yourBrand?: boolean; brandContent?: boolean; aiGeneratedContent?: boolean; privacyStatus?: string; madeForKids?: boolean; visibility?: string; disableReshare?: boolean };
type SocialPost = { id: string; caption: string; title: string | null; status: string; scheduled_for: string | null; content_type: string; social_post_targets?: Array<{ id: string; connection_id: string; platform: Platform; status: string; external_url?: string | null; last_error?: string | null }> };
type Thread = { id: string; platform: Platform; kind: 'comment' | 'message'; subject?: string | null; last_message_at?: string | null; needs_reply: boolean; social_contacts?: { id: string; display_name?: string | null; username?: string | null; sales_lead_id?: string | null } | null; social_interactions?: Array<{ id: string; body: string; direction: string; occurred_at: string; sender_name?: string | null }> };
type Analytics = { totals?: Record<string, number>; posts?: { total: number; published: number; scheduled: number; failed: number } };
type TikTokCreatorInfo = { username: string | null; nickname: string | null; avatarUrl: string | null; privacyLevelOptions: string[]; commentsDisabled: boolean; duetDisabled: boolean; stitchDisabled: boolean; maxVideoDurationSeconds: number };
type TikTokCreatorState = { loading: boolean; data?: TikTokCreatorInfo; error?: string };

const platformDetails: Record<Platform, { label: string; description: string; color: string; icon: typeof Instagram }> = {
  facebook: { label: 'Facebook Pages', description: 'Posts, Reels, comments & Messenger', color: 'from-blue-700 to-blue-500', icon: Facebook },
  instagram: { label: 'Instagram', description: 'Feed, carousel, Reels, Stories & inbox', color: 'from-fuchsia-600 via-pink-500 to-orange-400', icon: Instagram },
  tiktok: { label: 'TikTok', description: 'Video and photo posting; inbox unavailable', color: 'from-slate-950 to-slate-700', icon: Play },
  youtube: { label: 'YouTube Shorts', description: 'Uploads, statistics, comments & replies', color: 'from-red-600 to-red-500', icon: Youtube },
  linkedin: { label: 'LinkedIn', description: 'Personal profiles and approved Company Pages', color: 'from-sky-800 to-sky-600', icon: Linkedin },
};

const sections: Array<{ id: Section; label: string; icon: typeof Home }> = [
  { id: 'overview', label: 'Overview', icon: Home }, { id: 'create', label: 'Create', icon: Sparkles },
  { id: 'calendar', label: 'Calendar', icon: CalendarDays }, { id: 'inbox', label: 'Inbox', icon: MessageCircle },
  { id: 'library', label: 'Library', icon: FolderOpen }, { id: 'analytics', label: 'Analytics', icon: BarChart3 },
  { id: 'connections', label: 'Connections', icon: Plug }, { id: 'settings', label: 'Settings', icon: Settings },
];

export function WolfSocialWorkspace({ surface = 'sales_web' }: { surface?: 'sales_web' | 'standalone' }) {
  const [section, setSection] = useState<Section>('overview');
  const [connections, setConnections] = useState<Connection[]>([]);
  const [providerAvailability, setProviderAvailability] = useState<Partial<ProviderAvailability>>({});
  const [posts, setPosts] = useState<SocialPost[]>([]);
  const [library, setLibrary] = useState<Asset[]>([]);
  const [threads, setThreads] = useState<Thread[]>([]);
  const [analytics, setAnalytics] = useState<Analytics>({});
  const [workspace, setWorkspace] = useState<{ id: string; name: string; slug: string } | null>(null);
  const [selected, setSelected] = useState<string[]>([]);
  const [assets, setAssets] = useState<Asset[]>([]);
  const [caption, setCaption] = useState('');
  const [title, setTitle] = useState('');
  const [captionByConnection, setCaptionByConnection] = useState<Record<string, string>>({});
  const [workspaceName, setWorkspaceName] = useState('');
  const [wolfeySuggestions, setWolfeySuggestions] = useState<string[]>([]);
  const [format, setFormat] = useState('reel');
  const [scheduledFor, setScheduledFor] = useState('');
  const [settingsByConnection, setSettingsByConnection] = useState<Record<string, TargetSettings>>({});
  const [tiktokCreatorByConnection, setTikTokCreatorByConnection] = useState<Record<string, TikTokCreatorState>>({});
  const [replyByThread, setReplyByThread] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [uploadProgress, setUploadProgress] = useState('');
  const [notice, setNotice] = useState('');
  const [disconnectingConnectionId, setDisconnectingConnectionId] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const responses = await Promise.all(['/api/social/connections', '/api/social/posts', '/api/social/media', '/api/social/inbox', '/api/social/analytics', '/api/social/workspace'].map((url) => fetch(url, { credentials: 'include' })));
    const payloads = await Promise.all(responses.map((response) => response.json().catch(() => ({}))));
    setConnections(payloads[0].connections || []); setProviderAvailability(payloads[0].providerAvailability || {}); setPosts(payloads[1].posts || []); setLibrary(payloads[2].assets || []);
    setThreads(payloads[3].threads || []); setAnalytics(payloads[4]);
    const nextWorkspace = payloads[5].workspace || payloads[0].socialWorkspace || null;
    setWorkspace(nextWorkspace); setWorkspaceName(nextWorkspace?.name || '');
    setLoading(false);
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => { const value = new URLSearchParams(window.location.search).get('section') as Section | null; if (value && sections.some((item) => item.id === value)) setSection(value); }, []);
  useEffect(() => { if (!notice) return; const timer = window.setTimeout(() => setNotice(''), 5000); return () => window.clearTimeout(timer); }, [notice]);

  const refreshPosts = useCallback(async () => {
    const response = await fetch('/api/social/posts', { credentials: 'include', cache: 'no-store' });
    const payload = await response.json().catch(() => ({}));
    if (response.ok) setPosts(payload.posts || []);
  }, []);

  useEffect(() => {
    if (!posts.some((post) => post.status === 'publishing')) return;
    const timer = window.setInterval(() => { void refreshPosts(); }, 5_000);
    return () => window.clearInterval(timer);
  }, [posts, refreshPosts]);

  const activeConnections = useMemo(() => connections.filter((connection) => connection.status === 'active'), [connections]);
  const selectedConnections = useMemo(() => activeConnections.filter((connection) => selected.includes(connection.id)), [activeConnections, selected]);
  const duePosts = useMemo(() => posts.filter((post) => ['scheduled', 'publishing', 'partial_failed', 'failed'].includes(post.status)), [posts]);
  const previewAsset = assets[0] || null;

  async function loadTikTokCreatorInfo(connectionId: string) {
    setTikTokCreatorByConnection((current) => ({ ...current, [connectionId]: { loading: true } }));
    try {
      const response = await fetch(`/api/social/connections/${connectionId}/creator-info`, { credentials: 'include', cache: 'no-store' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || 'TikTok creator information is unavailable');
      setTikTokCreatorByConnection((current) => ({ ...current, [connectionId]: { loading: false, data: payload.creatorInfo } }));
    } catch (error) {
      setTikTokCreatorByConnection((current) => ({ ...current, [connectionId]: { loading: false, error: error instanceof Error ? error.message : 'TikTok creator information is unavailable' } }));
    }
  }

  function toggleConnection(connection: Connection) {
    const willSelect = !selected.includes(connection.id);
    setSelected((current) => current.includes(connection.id) ? current.filter((value) => value !== connection.id) : [...current, connection.id]);
    if (willSelect && connection.platform === 'tiktok') void loadTikTokCreatorInfo(connection.id);
  }
  function updateTargetSettings(id: string, patch: TargetSettings) { setSettingsByConnection((current) => ({ ...current, [id]: { ...(current[id] || {}), ...patch } })); }

  async function disconnectConnection(connection: Connection) {
    const accountName = connection.account_name || platformDetails[connection.platform].label;
    if (!window.confirm(`Disconnect ${accountName}? WolfSocial will no longer publish to or sync this account.`)) return;
    setDisconnectingConnectionId(connection.id);
    try {
      const response = await fetch(`/api/social/connections/${connection.id}`, { method: 'DELETE', credentials: 'include' });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || 'Could not disconnect this account');
      setConnections((current) => current.filter((item) => item.id !== connection.id));
      setSelected((current) => current.filter((id) => id !== connection.id));
      setSettingsByConnection((current) => { const next = { ...current }; delete next[connection.id]; return next; });
      setTikTokCreatorByConnection((current) => { const next = { ...current }; delete next[connection.id]; return next; });
      setNotice(`${accountName} disconnected.`);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : 'Could not disconnect this account');
    } finally {
      setDisconnectingConnectionId(null);
    }
  }

  async function upload(files: FileList | null) {
    if (!files?.length) return;
    setBusy(true);
    try {
      const uploaded: Asset[] = [];
      for (const [index, file] of Array.from(files).entries()) {
        setUploadProgress(`Uploading ${index + 1} of ${files.length}: ${file.name}`);
        const durationSeconds = file.type.startsWith('video/') ? await readVideoDuration(file) : undefined;
        const presign = await fetch('/api/social/media/upload-url', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ fileName: file.name, mimeType: file.type, byteSize: file.size }) });
        const presignPayload = await presign.json(); if (!presign.ok) throw new Error(presignPayload.error || 'Could not prepare upload');
        const receipt = presignPayload.upload;
        const transfer = await fetch(receipt.signedUrl, { method: 'PUT', headers: { 'Content-Type': file.type, 'x-upsert': 'false' }, body: file });
        if (!transfer.ok) throw new Error(`Could not upload ${file.name}`);
        const complete = await fetch('/api/social/media/complete', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ storagePath: receipt.storagePath, mimeType: file.type, byteSize: file.size, originalName: file.name, durationSeconds }) });
        const completePayload = await complete.json(); if (!complete.ok) throw new Error(completePayload.error || 'Could not finish upload');
        uploaded.push(completePayload.asset);
      }
      setAssets((current) => [...current, ...uploaded]); setLibrary((current) => [...uploaded, ...current]);
    } catch (error) { setNotice(error instanceof Error ? error.message : 'Upload failed'); }
    finally { setBusy(false); setUploadProgress(''); }
  }

  function targetFor(connection: Connection) {
    const platformFormat = connection.platform === 'youtube' ? 'short' : connection.platform === 'tiktok' ? (assets.every((asset) => asset.mime_type.startsWith('image/')) ? 'tiktok_photo' : 'tiktok_video') : format;
    return { connectionId: connection.id, format: platformFormat, caption: captionByConnection[connection.id] || caption, title: connection.platform === 'youtube' ? title : undefined, settings: settingsByConnection[connection.id] || {} };
  }

  async function askWolfey(source: string, task: 'caption_variants' | 'suggest_reply' = 'caption_variants', threadId?: string) {
    if (!source.trim()) return setNotice(task === 'caption_variants' ? 'Add a starting idea first.' : 'There is no message to answer yet.');
    setBusy(true);
    try {
      const response = await fetch('/api/social/wolfey', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ task, source }) });
      const payload = await response.json(); if (!response.ok) throw new Error(payload.error || 'Wolfey could not create suggestions');
      const suggestions = (payload.suggestions || []) as string[];
      if (task === 'suggest_reply' && threadId && suggestions[0]) setReplyByThread((current) => ({ ...current, [threadId]: suggestions[0] }));
      else setWolfeySuggestions(suggestions);
      setNotice('Wolfey drafted suggestions. Review and approve one before using it.');
    } catch (error) { setNotice(error instanceof Error ? error.message : 'Wolfey could not create suggestions'); }
    finally { setBusy(false); }
  }

  async function save(mode: 'draft' | 'schedule' | 'publish') {
    if (!selectedConnections.length) return setNotice('Select at least one connected account.');
    if (!assets.length && selectedConnections.some((connection) => !['facebook', 'linkedin'].includes(connection.platform))) return setNotice('Add the media required by the selected platform.');
    if (format === 'story' && selectedConnections.some((connection) => connection.platform === 'facebook')) return setNotice('Facebook Page connections support posts and Reels, but not Stories.');
    if (assets.length > 10 && selectedConnections.some((connection) => ['facebook', 'instagram'].includes(connection.platform))) return setNotice('Facebook and Instagram support at most ten media items per post.');
    if (selectedConnections.some((connection) => connection.platform === 'linkedin')) {
      const linkedinVideos = assets.filter((asset) => asset.mime_type.startsWith('video/'));
      const linkedinImages = assets.filter((asset) => asset.mime_type.startsWith('image/'));
      if (linkedinVideos.length > 1) return setNotice('LinkedIn supports one video per post.');
      if (linkedinVideos.length && linkedinImages.length) return setNotice('LinkedIn posts cannot mix images and video.');
    }
    if (selectedConnections.some((connection) => connection.platform === 'youtube') && !title.trim()) return setNotice('YouTube Shorts needs a title.');
    if (mode !== 'draft' && selectedConnections.some((connection) => connection.platform === 'youtube' && typeof settingsByConnection[connection.id]?.madeForKids !== 'boolean')) return setNotice('Choose whether each YouTube video is made for kids.');
    for (const connection of selectedConnections.filter((item) => item.platform === 'tiktok')) {
      if (mode === 'draft') continue;
      const creator = tiktokCreatorByConnection[connection.id];
      const settings = settingsByConnection[connection.id] || {};
      if (!creator?.data) return setNotice(creator?.error || 'Wait for TikTok creator settings to load before publishing.');
      if (!settings.privacyLevel || !creator.data.privacyLevelOptions.includes(settings.privacyLevel)) return setNotice('Choose one of the privacy options provided by TikTok.');
      if (settings.musicUsageConfirmed !== true) return setNotice("Accept TikTok's Music Usage Confirmation before publishing.");
      if (settings.explicitConsent !== true) return setNotice('Approve the exact TikTok post and settings before publishing.');
      if (settings.allowComments && creator.data.commentsDisabled) return setNotice('Comments are unavailable for this TikTok account.');
      if (settings.allowDuet && creator.data.duetDisabled) return setNotice('Duet is unavailable for this TikTok account.');
      if (settings.allowStitch && creator.data.stitchDisabled) return setNotice('Stitch is unavailable for this TikTok account.');
      if (settings.commercialContent && !settings.yourBrand && !settings.brandContent) return setNotice('Indicate whether the TikTok post promotes your brand, another brand, or both.');
      if (!settings.commercialContent && (settings.yourBrand || settings.brandContent)) return setNotice('Turn on TikTok commercial content disclosure before choosing a brand type.');
      if (settings.brandContent && !['PUBLIC_TO_EVERYONE', 'MUTUAL_FOLLOW_FRIENDS'].includes(settings.privacyLevel)) return setNotice('TikTok branded content visibility cannot be private.');
      const video = assets.find((asset) => asset.mime_type.startsWith('video/'));
      if (video && creator.data.maxVideoDurationSeconds > 0 && (!video.duration_seconds || video.duration_seconds > creator.data.maxVideoDurationSeconds)) {
        return setNotice(video.duration_seconds
          ? `TikTok limits this account to videos of ${creator.data.maxVideoDurationSeconds} seconds or less.`
          : 'Video duration is unavailable. Upload the TikTok video again before publishing.');
      }
    }
    setBusy(true);
    try {
      const response = await fetch('/api/social/posts', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ socialWorkspaceId: workspace?.id, assetIds: assets.map((asset) => asset.id), mode, scheduledFor: mode === 'schedule' ? scheduledFor : undefined, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone, caption, title, contentType: format, targets: selectedConnections.map(targetFor) }) });
      const payload = await response.json(); if (!response.ok) throw new Error(payload.error || 'Could not save post');
      setNotice(mode === 'draft' ? 'Draft saved.' : mode === 'schedule' ? 'Post scheduled.' : 'Post approved and queued. TikTok may take a few minutes to process and appear on your profile.');
      setCaption(''); setTitle(''); setAssets([]); setScheduledFor(''); setSelected([]); setSettingsByConnection({}); setCaptionByConnection({}); setWolfeySuggestions([]);
      await refresh(); setSection(mode === 'draft' ? 'library' : 'calendar');
    } catch (error) { setNotice(error instanceof Error ? error.message : 'Could not save post'); }
    finally { setBusy(false); }
  }

  async function sendReply(thread: Thread) {
    const body = (replyByThread[thread.id] || '').trim(); if (!body) return;
    setBusy(true);
    try { const response = await fetch(`/api/social/inbox/${thread.id}/reply`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ body }) }); const payload = await response.json(); if (!response.ok) throw new Error(payload.error || 'Reply failed'); setReplyByThread((current) => ({ ...current, [thread.id]: '' })); await refresh(); }
    catch (error) { setNotice(error instanceof Error ? error.message : 'Reply failed'); } finally { setBusy(false); }
  }

  async function createLead(thread: Thread) {
    const contact = thread.social_contacts; if (!contact?.id) return;
    const response = await fetch(`/api/social/contacts/${contact.id}/create-lead`, { method: 'POST' }); const payload = await response.json();
    if (!response.ok) return setNotice(payload.error || 'Could not create lead'); setNotice('Lead created in WolfGrid Sales.'); await refresh();
  }

  async function calendarAction(post: SocialPost, action: 'cancel' | 'retry') {
    setBusy(true);
    try {
      const response = await fetch(`/api/social/posts/${post.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action }) });
      const payload = await response.json(); if (!response.ok) throw new Error(payload.error || 'Could not update the post');
      setNotice(action === 'retry' ? 'Retry queued.' : 'Post cancelled.'); await refresh();
    } catch (error) { setNotice(error instanceof Error ? error.message : 'Could not update the post'); }
    finally { setBusy(false); }
  }

  if (loading) return <div className="grid min-h-[60vh] place-items-center"><Loader2 className="h-7 w-7 animate-spin text-red-500" /></div>;

  return <div className="mx-auto w-full max-w-[1600px] px-4 py-6 md:px-7">
    <header className="mb-6 flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between"><div><p className="text-xs font-bold uppercase tracking-[0.18em] text-red-500">WolfSocial</p><h1 className="mt-1 text-3xl font-black tracking-tight">{workspace?.name || 'Your social command centre'}</h1><p className="mt-2 text-sm text-muted-foreground">Create, schedule, publish, reply and measure from one workspace.</p></div><Button onClick={() => setSection('create')}><Sparkles className="h-4 w-4" />Create a post</Button></header>
    <nav className="mb-6 flex gap-1 overflow-x-auto rounded-xl border bg-white p-1.5">{sections.map(({ id, label, icon: Icon }) => <button key={id} onClick={() => setSection(id)} className={`flex shrink-0 items-center gap-2 rounded-lg px-3 py-2 text-sm font-semibold ${section === id ? 'bg-slate-950 text-white' : 'text-muted-foreground hover:bg-muted'}`}><Icon className="h-4 w-4" />{label}</button>)}</nav>

    {section === 'overview' ? <div className="space-y-5"><div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><Metric label="Connected accounts" value={activeConnections.length} /><Metric label="Scheduled" value={duePosts.filter((post) => post.status === 'scheduled').length} /><Metric label="Needs reply" value={threads.filter((thread) => thread.needs_reply).length} /><Metric label="30-day views" value={analytics.totals?.views || 0} /></div><div className="grid gap-5 xl:grid-cols-2"><ConnectionCards connections={connections} providerAvailability={providerAvailability} surface={surface} onDisconnect={disconnectConnection} disconnectingConnectionId={disconnectingConnectionId} /><Queue posts={duePosts.slice(0, 5)} /></div></div> : null}

      {section === 'create' ? <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_420px]"><Card><CardHeader><CardTitle>New post</CardTitle></CardHeader><CardContent className="space-y-5"><div><label className="mb-2 block text-sm font-semibold">Publish to exact accounts</label><div className="flex flex-wrap gap-2">{activeConnections.map((connection) => { const detail = platformDetails[connection.platform]; const Icon = detail.icon; return <button key={connection.id} onClick={() => toggleConnection(connection)} className={`flex items-center gap-2 rounded-lg border px-3 py-2 text-sm ${selected.includes(connection.id) ? 'border-red-300 bg-red-50 text-red-700' : ''}`}><Icon className="h-4 w-4" />{connection.account_name || detail.label}{selected.includes(connection.id) ? <Check className="h-4 w-4" /> : null}</button>; })}{!activeConnections.length ? <button onClick={() => setSection('connections')} className="rounded-lg border px-3 py-2 text-sm font-semibold">Connect an account</button> : null}</div></div>
      {selectedConnections.some((connection) => connection.platform === 'youtube') ? <div><label className="mb-2 block text-sm font-semibold">YouTube title</label><Input value={title} maxLength={100} onChange={(event) => setTitle(event.target.value)} /></div> : null}
      <div><label className="mb-2 flex justify-between text-sm font-semibold"><span>Base caption</span><span className="font-normal text-muted-foreground">{caption.length} / 2,200</span></label><Textarea value={caption} onChange={(event) => setCaption(event.target.value)} maxLength={2200} className="min-h-40" placeholder="Write for your audience…" /><Button className="mt-2" type="button" variant="outline" disabled={busy || !caption.trim()} onClick={() => void askWolfey(caption)}><Sparkles className="h-4 w-4" />Ask Wolfey for variants</Button></div>
      {wolfeySuggestions.length ? <div className="space-y-2 rounded-xl border border-violet-200 bg-violet-50 p-4"><p className="text-sm font-semibold">Wolfey suggestions — choose one to approve</p>{wolfeySuggestions.map((suggestion) => <button type="button" key={suggestion} onClick={() => setCaption(suggestion)} className="block w-full rounded-lg bg-white p-3 text-left text-sm hover:ring-2 hover:ring-violet-300">{suggestion}</button>)}</div> : null}
      {selectedConnections.map((connection) => <details key={`override-${connection.id}`} className="rounded-xl border p-4"><summary className="cursor-pointer text-sm font-semibold">Override caption for {connection.account_name || platformDetails[connection.platform].label}</summary><Textarea className="mt-3 min-h-24" placeholder="Leave blank to use the base caption" value={captionByConnection[connection.id] || ''} onChange={(event) => setCaptionByConnection((current) => ({ ...current, [connection.id]: event.target.value }))} /></details>)}
      <div><label className="mb-2 block text-sm font-semibold">Format</label><select className="h-10 w-full rounded-md border bg-white px-3 text-sm" value={format} onChange={(event) => setFormat(event.target.value)}><option value="feed">Feed post</option><option value="carousel">Carousel</option><option value="reel">Reel / short video</option><option value="story">Story</option></select></div>
      <label className="flex min-h-28 cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed bg-muted/30 p-5"><Upload className="mb-2 h-6 w-6 text-red-500" /><span className="text-sm font-semibold">{uploadProgress || 'Add images or video'}</span><input className="sr-only" type="file" multiple accept="image/jpeg,image/png,image/webp,video/mp4,video/quicktime,video/webm" onChange={(event) => void upload(event.target.files)} disabled={busy} /></label>
      {assets.map((asset) => <div key={asset.id} className="flex items-center rounded-lg border px-3 py-2 text-sm"><span className="truncate">{asset.original_name}</span><button className="ml-auto" onClick={() => setAssets((current) => current.filter((item) => item.id !== asset.id))}><Trash2 className="h-4 w-4" /></button></div>)}
      {selectedConnections.filter((connection) => connection.platform === 'tiktok').map((connection) => <TikTokControls key={connection.id} connection={connection} creatorState={tiktokCreatorByConnection[connection.id]} settings={settingsByConnection[connection.id] || {}} isPhoto={assets.length > 0 && assets.every((asset) => asset.mime_type.startsWith('image/'))} update={(value) => updateTargetSettings(connection.id, value)} retry={() => void loadTikTokCreatorInfo(connection.id)} />)}
      {selectedConnections.filter((connection) => connection.platform === 'youtube').map((connection) => <div key={connection.id} className="space-y-3 rounded-xl border p-4"><label className="text-sm font-semibold">YouTube options for {connection.account_name}</label><div><span className="text-xs font-medium text-muted-foreground">Privacy</span><select className="mt-1 h-10 w-full rounded-md border bg-white px-3 text-sm" value={settingsByConnection[connection.id]?.privacyStatus || 'private'} onChange={(event) => updateTargetSettings(connection.id, { privacyStatus: event.target.value })}><option value="private">Private</option><option value="unlisted">Unlisted</option><option value="public">Public</option></select></div><div><span className="text-xs font-medium text-muted-foreground">Audience</span><select className="mt-1 h-10 w-full rounded-md border bg-white px-3 text-sm" value={typeof settingsByConnection[connection.id]?.madeForKids === 'boolean' ? String(settingsByConnection[connection.id]?.madeForKids) : ''} onChange={(event) => updateTargetSettings(connection.id, { madeForKids: event.target.value === 'true' })}><option value="" disabled>Choose—no default</option><option value="false">No, it is not made for kids</option><option value="true">Yes, it is made for kids</option></select></div></div>)}
      {selectedConnections.filter((connection) => connection.platform === 'linkedin').map((connection) => <div key={connection.id} className="space-y-3 rounded-xl border p-4"><label className="text-sm font-semibold">LinkedIn options for {connection.account_name}</label>{connection.account_type === 'organization' ? <p className="text-xs font-medium text-emerald-700">Company Page · {connection.page_role === 'CONTENT_ADMIN' ? 'Content admin' : 'Administrator'} verified</p> : <select className="h-10 w-full rounded-md border bg-white px-3 text-sm" value={settingsByConnection[connection.id]?.visibility || 'PUBLIC'} onChange={(event) => updateTargetSettings(connection.id, { visibility: event.target.value })}><option value="PUBLIC">Anyone</option><option value="CONNECTIONS">Connections</option></select>}<label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={settingsByConnection[connection.id]?.disableReshare === true} onChange={(event) => updateTargetSettings(connection.id, { disableReshare: event.target.checked })} />Disable resharing</label><p className="text-xs text-muted-foreground">LinkedIn supports text, up to twenty images, or one video per post. Company Pages require LinkedIn Community Management approval.</p></div>)}
      <div className="grid gap-3 rounded-xl border bg-muted/30 p-4 md:grid-cols-[1fr_auto]"><Input type="datetime-local" value={scheduledFor} onChange={(event) => setScheduledFor(event.target.value)} /><div className="flex flex-wrap gap-2"><Button variant="outline" disabled={busy} onClick={() => void save('draft')}>Save draft</Button><Button variant="outline" disabled={busy || !scheduledFor} onClick={() => void save('schedule')}>Schedule</Button><Button disabled={busy} onClick={() => void save('publish')}><Send className="h-4 w-4" />Approve & publish</Button></div></div>
    </CardContent></Card><Card className="h-fit xl:sticky xl:top-24"><CardHeader><CardTitle className="text-base">Preview</CardTitle></CardHeader><CardContent><div className="relative aspect-[9/16] max-h-[570px] overflow-hidden rounded-2xl bg-gradient-to-br from-slate-950 via-slate-900 to-red-950 text-white">
      {previewAsset?.preview_url && previewAsset.mime_type.startsWith('video/') ? <video key={previewAsset.preview_url} src={previewAsset.preview_url} aria-label={`Preview of ${previewAsset.original_name}`} className="absolute inset-0 h-full w-full bg-black object-contain" autoPlay muted loop playsInline controls preload="metadata" /> : null}
      {previewAsset?.preview_url && previewAsset.mime_type.startsWith('image/') ? <Image src={previewAsset.preview_url} alt={`Preview of ${previewAsset.original_name}`} fill unoptimized sizes="420px" className="object-cover" /> : null}
      <div className="pointer-events-none absolute inset-x-0 top-0 bg-gradient-to-b from-black/75 to-transparent px-6 pb-12 pt-6"><div className="text-xs font-semibold">WolfSocial preview</div>{previewAsset ? <div className="mt-1 truncate text-[11px] text-white/75">{previewAsset.original_name}</div> : null}</div>
      <div className="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/90 via-black/55 to-transparent px-6 pb-14 pt-20"><p className="whitespace-pre-wrap text-lg font-semibold drop-shadow">{caption || (previewAsset ? 'Add a caption for this post.' : 'Your approved content preview appears here.')}</p><div className="mt-4 flex gap-3"><MessageCircle /><Send /></div></div>
    </div></CardContent></Card></div> : null}

    {section === 'calendar' ? <Queue posts={posts} onAction={calendarAction} /> : null}
    {section === 'library' ? <Card><CardHeader><CardTitle>Media library</CardTitle></CardHeader><CardContent><div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{library.map((asset) => <button key={asset.id} onClick={() => setAssets((current) => current.some((item) => item.id === asset.id) ? current : [...current, asset])} className="rounded-xl border p-4 text-left hover:bg-muted"><FolderOpen className="mb-3 h-6 w-6 text-red-500" /><p className="truncate text-sm font-semibold">{asset.original_name}</p><p className="mt-1 text-xs text-muted-foreground">{asset.mime_type}</p></button>)}</div></CardContent></Card> : null}
    {section === 'inbox' ? <div className="space-y-4">{threads.length ? threads.map((thread) => <Card key={thread.id}><CardContent className="p-5"><div className="flex items-start gap-3"><div className="grid h-10 w-10 place-items-center rounded-full bg-muted font-bold">{platformDetails[thread.platform].label.slice(0, 1)}</div><div className="min-w-0 flex-1"><div className="flex flex-wrap items-center gap-2"><p className="font-semibold">{thread.social_contacts?.display_name || thread.social_contacts?.username || 'Social contact'}</p><span className="rounded-full bg-muted px-2 py-1 text-[10px] font-bold uppercase">{thread.platform} {thread.kind}</span></div>{thread.social_interactions?.map((interaction) => <p key={interaction.id} className={`mt-2 rounded-lg p-3 text-sm ${interaction.direction === 'outbound' ? 'ml-8 bg-slate-950 text-white' : 'bg-muted'}`}>{interaction.body}</p>)}<div className="mt-3 flex flex-wrap gap-2"><Input className="min-w-52 flex-1" value={replyByThread[thread.id] || ''} onChange={(event) => setReplyByThread((current) => ({ ...current, [thread.id]: event.target.value }))} placeholder={['tiktok', 'linkedin'].includes(thread.platform) ? `${platformDetails[thread.platform].label} inbox unavailable` : 'Write an approved reply…'} disabled={['tiktok', 'linkedin'].includes(thread.platform)} /><Button onClick={() => void sendReply(thread)} disabled={busy || ['tiktok', 'linkedin'].includes(thread.platform)}>Reply</Button><Button variant="outline" disabled={busy || ['tiktok', 'linkedin'].includes(thread.platform)} onClick={() => void askWolfey(thread.social_interactions?.filter((item) => item.direction === 'inbound').at(-1)?.body || '', 'suggest_reply', thread.id)}><Sparkles className="h-4 w-4" />Wolfey</Button>{surface === 'sales_web' && thread.social_contacts && !thread.social_contacts.sales_lead_id ? <Button variant="outline" onClick={() => void createLead(thread)}>Create lead</Button> : null}</div></div></div></CardContent></Card>) : <Card><CardContent className="grid min-h-64 place-items-center text-center text-sm text-muted-foreground">Supported Facebook, Instagram and YouTube conversations will appear here. TikTok and LinkedIn inboxes and YouTube DMs are unavailable.</CardContent></Card>}</div> : null}
    {section === 'analytics' ? <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">{Object.entries(analytics.totals || { views: 0, reach: 0, likes: 0, comments: 0 }).map(([label, value]) => <Metric key={label} label={label.replaceAll('_', ' ')} value={value} />)}</div> : null}
    {section === 'connections' ? <ConnectionCards connections={connections} providerAvailability={providerAvailability} surface={surface} onDisconnect={disconnectConnection} disconnectingConnectionId={disconnectingConnectionId} /> : null}
    {section === 'settings' ? <Card><CardHeader><CardTitle>Workspace settings</CardTitle></CardHeader><CardContent><label className="mb-2 block text-sm font-semibold">Workspace name</label><div className="flex max-w-xl gap-2"><Input value={workspaceName} onChange={(event) => setWorkspaceName(event.target.value)} /><Button disabled={!workspaceName.trim()} onClick={async () => { const response = await fetch('/api/social/workspace', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: workspaceName }) }); if (response.ok) { setNotice('Workspace updated.'); await refresh(); } }}>Save</Button></div><p className="mt-6 text-sm text-muted-foreground">Wolfey suggestions never publish or reply automatically. Every action requires your approval.</p></CardContent></Card> : null}
    {notice ? <div className="fixed bottom-6 right-6 z-50 max-w-sm rounded-xl bg-slate-950 px-4 py-3 text-sm text-white shadow-2xl">{notice}</div> : null}
  </div>;
}

function Metric({ label, value }: { label: string; value: number }) { return <Card><CardContent className="p-5"><p className="text-xs font-bold uppercase tracking-wider text-muted-foreground">{label}</p><p className="mt-2 text-3xl font-black">{value.toLocaleString()}</p></CardContent></Card>; }
function Queue({ posts, onAction }: { posts: SocialPost[]; onAction?: (post: SocialPost, action: 'cancel' | 'retry') => void }) { return <Card><CardHeader><CardTitle>Publishing calendar</CardTitle></CardHeader><CardContent>{posts.length ? <div className="divide-y">{posts.map((post) => <div key={post.id} className="py-4"><div className="flex items-center gap-2"><span className="rounded-full bg-muted px-2 py-1 text-[10px] font-bold uppercase">{post.status}</span><span className="text-xs text-muted-foreground">{post.scheduled_for ? new Date(post.scheduled_for).toLocaleString() : 'Draft / immediate'}</span></div><p className="mt-2 line-clamp-2 text-sm font-semibold">{post.title || post.caption || 'Untitled post'}</p><div className="mt-2 flex flex-wrap gap-1">{post.social_post_targets?.map((target) => <span key={target.id} title={target.last_error || target.status} className={`rounded-md px-2 py-1 text-xs ${target.status === 'published' ? 'bg-emerald-50 text-emerald-700' : target.status === 'failed' ? 'bg-red-50 text-red-700' : 'bg-muted'}`}>{platformDetails[target.platform].label}: {target.status}</span>)}</div>{post.social_post_targets?.map((target) => target.last_error ? <p key={`error-${target.id}`} className="mt-2 max-w-3xl rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-700"><strong>{platformDetails[target.platform].label}:</strong> {target.last_error}</p> : null)}{onAction ? <div className="mt-3 flex gap-2">{['failed', 'partial_failed'].includes(post.status) ? <Button size="sm" variant="outline" onClick={() => onAction(post, 'retry')}>Retry failed</Button> : null}{['draft', 'scheduled', 'publishing', 'partial_failed', 'failed'].includes(post.status) ? <Button size="sm" variant="outline" onClick={() => onAction(post, 'cancel')}>Cancel</Button> : null}</div> : null}</div>)}</div> : <div className="grid min-h-48 place-items-center text-sm text-muted-foreground">Nothing here yet.</div>}</CardContent></Card>; }
function ConnectionCards({ connections, providerAvailability, surface, onDisconnect, disconnectingConnectionId }: { connections: Connection[]; providerAvailability: Partial<ProviderAvailability>; surface: 'sales_web' | 'standalone'; onDisconnect: (connection: Connection) => void; disconnectingConnectionId: string | null }) {
  return <Card><CardHeader><CardTitle>Connected accounts</CardTitle></CardHeader><CardContent><div className="grid gap-3 sm:grid-cols-2">{(Object.keys(platformDetails) as Platform[]).map((platform) => {
    const detail = platformDetails[platform]; const Icon = detail.icon;
    const accounts = connections.filter((connection) => connection.platform === platform);
    return <div key={platform} className="rounded-xl border p-4"><div className="flex items-center gap-3"><span className={`grid h-10 w-10 place-items-center rounded-xl bg-gradient-to-br text-white ${detail.color}`}><Icon className="h-5 w-5" /></span><div><p className="font-semibold">{detail.label}</p><p className="text-xs text-muted-foreground">{accounts.length ? `${accounts.length} connected` : detail.description}</p></div></div>
      {accounts.map((account) => <div key={account.id} className="mt-3 rounded-lg bg-muted px-3 py-2 text-sm"><div className="flex items-center gap-2"><AccountAvatar connection={account} /><span className="min-w-0 flex-1 truncate font-medium">{account.account_name || detail.label}</span><span className="text-[10px] font-bold uppercase text-emerald-700">Connected</span><Button type="button" size="sm" variant="ghost" className="h-8 px-2 text-xs text-red-600 hover:bg-red-50 hover:text-red-700" disabled={disconnectingConnectionId === account.id} onClick={() => onDisconnect(account)} aria-label={`Disconnect ${account.account_name || detail.label}`}>{disconnectingConnectionId === account.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Trash2 className="h-3.5 w-3.5" />}Disconnect</Button></div>{platform === 'linkedin' ? <p className="mt-1 text-xs text-muted-foreground">{account.account_type === 'organization' ? `Company Page · ${account.page_role === 'CONTENT_ADMIN' ? 'Content admin verified' : 'Administrator verified'}` : 'Personal profile · Share on LinkedIn'}</p> : null}{account.last_error ? <p className="mt-2 text-xs text-amber-700">Connection warning: {account.last_error}</p> : null}</div>)}
      {providerAvailability[platform]?.configured === false
        ? <p className="mt-3 text-xs font-medium text-amber-700">Setup required: {providerAvailability[platform]?.message}</p>
        : <a href={`/api/social/oauth/${platform}/start?surface=${surface}`} className="mt-3 inline-flex text-sm font-semibold text-red-600">+ Connect {accounts.length ? 'another' : detail.label}</a>}
    </div>;
  })}</div></CardContent></Card>;
}

function AccountAvatar({ connection, overrideUrl }: { connection: Connection; overrideUrl?: string | null }) {
  const avatarUrl = overrideUrl || connection.account_avatar_url;
  return avatarUrl
    ? <span role="img" aria-label={`${connection.account_name || 'Connected account'} avatar`} className="h-8 w-8 shrink-0 rounded-full bg-cover bg-center ring-1 ring-black/10" style={{ backgroundImage: `url(${JSON.stringify(avatarUrl)})` }} />
    : <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-slate-900 text-xs font-bold text-white">{(connection.account_name || 'T').slice(0, 1).toUpperCase()}</span>;
}

function TikTokControls({ connection, creatorState, settings, isPhoto, update, retry }: { connection: Connection; creatorState?: TikTokCreatorState; settings: TargetSettings; isPhoto: boolean; update: (value: TargetSettings) => void; retry: () => void }) {
  const creator = creatorState?.data;
  const interactionControls = [
    { key: 'allowComments' as const, label: 'Allow comments', disabled: creator?.commentsDisabled === true },
    { key: 'allowDuet' as const, label: 'Allow Duet', disabled: creator?.duetDisabled === true },
    { key: 'allowStitch' as const, label: 'Allow Stitch', disabled: creator?.stitchDisabled === true },
  ].filter(({ key }) => !isPhoto || key === 'allowComments');
  const brandedVisibilityAllowed = (value: string) => ['PUBLIC_TO_EVERYONE', 'MUTUAL_FOLLOW_FRIENDS'].includes(value);
  const disclosureLabel = settings.brandContent ? "Your photo/video will be labeled as 'Paid partnership'." : settings.yourBrand ? "Your photo/video will be labeled as 'Promotional content'." : '';
  return <div className="space-y-4 rounded-xl border border-slate-300 p-4">
    <div className="flex items-center gap-3"><AccountAvatar connection={connection} overrideUrl={creator?.avatarUrl} /><div><p className="font-semibold">TikTok approval · {creator?.nickname || connection.account_name}</p><p className="text-xs text-muted-foreground">{creator?.username ? `@${creator.username} · ` : ''}Live creator settings from TikTok</p></div></div>
    {creatorState?.loading ? <div className="flex items-center gap-2 rounded-lg bg-muted px-3 py-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" />Loading current TikTok publishing options…</div> : null}
    {creatorState?.error ? <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700"><p>{creatorState.error}</p><button type="button" onClick={retry} className="mt-2 font-semibold underline">Try again</button></div> : null}
    <div><label className="mb-2 block text-sm font-semibold">Who can view this post?</label><select disabled={!creator || creatorState?.loading} className="h-10 w-full rounded-md border bg-white px-3 text-sm disabled:bg-muted" value={settings.privacyLevel || ''} onChange={(event) => update({ privacyLevel: event.target.value })}><option value="" disabled>Choose privacy—no default</option>{(creator?.privacyLevelOptions || []).map((option) => <option key={option} value={option} disabled={settings.brandContent === true && !brandedVisibilityAllowed(option)}>{privacyLabel(option)}{settings.brandContent === true && !brandedVisibilityAllowed(option) ? ' (unavailable for branded content)' : ''}</option>)}</select>{settings.brandContent === true && settings.privacyLevel && !brandedVisibilityAllowed(settings.privacyLevel) ? <p className="mt-1 text-xs text-red-600">Branded content visibility cannot be set to private.</p> : null}</div>
    <div className="space-y-2"><p className="text-sm font-semibold">Interaction settings</p><div className="flex flex-wrap gap-4 text-sm">{interactionControls.map(({ key, label, disabled }) => <label key={key} className={`flex items-center gap-2 ${disabled ? 'text-muted-foreground' : ''}`}><input type="checkbox" disabled={!creator || disabled} checked={!disabled && settings[key] === true} onChange={(event) => update({ [key]: event.target.checked })} />{label}{disabled ? ' (unavailable)' : ''}</label>)}</div></div>
    <div className="space-y-2 rounded-lg border bg-muted/30 p-3"><p className="text-sm font-semibold">Content disclosure</p><label className="flex items-start gap-2 text-sm"><input className="mt-1" type="checkbox" checked={settings.commercialContent === true} onChange={(event) => update(event.target.checked ? { commercialContent: true } : { commercialContent: false, yourBrand: false, brandContent: false })} /><span><strong>Commercial content</strong><span className="block text-xs text-muted-foreground">This content promotes yourself, a brand, product, or service.</span></span></label>{settings.commercialContent === true ? <div className="ml-6 space-y-2"><label className="flex items-start gap-2 text-sm"><input className="mt-1" type="checkbox" checked={settings.yourBrand === true} onChange={(event) => update({ yourBrand: event.target.checked })} /><span><strong>Your brand</strong><span className="block text-xs text-muted-foreground">You are promoting yourself or your own business.</span></span></label><label className="flex items-start gap-2 text-sm"><input className="mt-1" type="checkbox" checked={settings.brandContent === true} onChange={(event) => update({ brandContent: event.target.checked })} /><span><strong>Branded content</strong><span className="block text-xs text-muted-foreground">You are promoting another brand or a third party.</span></span></label>{!settings.yourBrand && !settings.brandContent ? <p className="text-xs text-red-600">You need to indicate if your content promotes yourself, a third party, or both.</p> : null}{disclosureLabel ? <p className="text-xs font-medium">{disclosureLabel}</p> : null}</div> : null}<label className="flex items-start gap-2 text-sm"><input className="mt-1" type="checkbox" checked={settings.aiGeneratedContent === true} onChange={(event) => update({ aiGeneratedContent: event.target.checked })} /><span><strong>AI-generated content</strong><span className="block text-xs text-muted-foreground">Ask TikTok to label this post as AI-generated.</span></span></label></div>
    {creator?.maxVideoDurationSeconds ? <p className="text-xs text-muted-foreground">This account currently supports videos up to {Math.floor(creator.maxVideoDurationSeconds / 60)} minutes {creator.maxVideoDurationSeconds % 60 ? `${creator.maxVideoDurationSeconds % 60} seconds` : ''}.</p> : null}
    <label className="flex items-start gap-2 text-sm"><input className="mt-1" type="checkbox" checked={settings.musicUsageConfirmed === true} onChange={(event) => update({ musicUsageConfirmed: event.target.checked })} /><span>By posting, you agree to TikTok&apos;s {settings.brandContent ? <><a className="underline" href="https://www.tiktok.com/legal/page/global/bc-policy/en" target="_blank" rel="noreferrer">Branded Content Policy</a> and </> : null}<a className="underline" href="https://www.tiktok.com/legal/page/global/music-usage-confirmation/en" target="_blank" rel="noreferrer">Music Usage Confirmation</a>.</span></label>
    <label className="flex items-start gap-2 text-sm font-medium"><input className="mt-1" type="checkbox" checked={settings.explicitConsent === true} onChange={(event) => update({ explicitConsent: event.target.checked })} />I approve this exact post and its selected TikTok settings.</label>
  </div>;
}

function readVideoDuration(file: File): Promise<number | undefined> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const video = document.createElement('video');
    const finish = (value?: number) => { URL.revokeObjectURL(url); video.remove(); resolve(value); };
    video.preload = 'metadata';
    video.onloadedmetadata = () => finish(Number.isFinite(video.duration) && video.duration > 0 ? video.duration : undefined);
    video.onerror = () => finish();
    video.src = url;
  });
}

function privacyLabel(value: string) {
  if (value === 'PUBLIC_TO_EVERYONE') return 'Everyone';
  if (value === 'MUTUAL_FOLLOW_FRIENDS') return 'Friends';
  if (value === 'FOLLOWER_OF_CREATOR') return 'Followers';
  if (value === 'SELF_ONLY') return 'Only me';
  return value.toLowerCase().replaceAll('_', ' ').replace(/^./, (letter) => letter.toUpperCase());
}

'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { AudioWaveform, Download, Loader2, RefreshCw, Star } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { useWorkspace } from '@/lib/workspace-context';

type SavedRecording = {
  callId: string;
  createdAt: string;
  answeredAt: string | null;
  endedAt: string | null;
  durationSeconds: number | null;
  downloadUrl: string;
  playbackUrl: string;
};

type SavedRecordingGroup = {
  leadId: string;
  leadName: string;
  company: string | null;
  phone: string | null;
  recordings: SavedRecording[];
};

function formatDuration(seconds: number | null): string {
  if (seconds == null) return 'Duration unavailable';
  const total = Math.max(0, Math.round(seconds));
  const minutes = Math.floor(total / 60);
  const remainder = total % 60;
  return minutes ? `${minutes}m ${remainder.toString().padStart(2, '0')}s` : `${remainder}s`;
}

function RecordingPlayer({ recording, leadName, onPlay }: {
  recording: SavedRecording;
  leadName: string;
  onPlay: (audio: HTMLAudioElement) => void;
}) {
  const [failed, setFailed] = useState(false);
  const audioRef = useRef<HTMLAudioElement | null>(null);

  return (
    <div className="w-full min-w-0 sm:w-80">
      <audio
        ref={audioRef}
        controls
        preload="none"
        src={recording.playbackUrl}
        aria-label={`Recording of ${leadName} from ${new Date(recording.createdAt).toLocaleString()}`}
        className="h-10 w-full"
        onPlay={(event) => onPlay(event.currentTarget)}
        onLoadStart={() => setFailed(false)}
        onError={() => setFailed(true)}
      />
      {failed ? (
        <p role="alert" className="mt-2 text-sm text-red-600">
          Unable to play this recording.
          <button type="button" className="ml-1 underline" onClick={() => audioRef.current?.load()}>Retry</button>
        </p>
      ) : null}
    </div>
  );
}

export function SavedContentLibrary() {
  const { currentWorkspaceId, isLoading: workspaceLoading } = useWorkspace();
  const [groups, setGroups] = useState<SavedRecordingGroup[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const activeAudio = useRef<HTMLAudioElement | null>(null);

  const load = useCallback(async () => {
    if (workspaceLoading) return;
    setLoading(true);
    setError(null);
    try {
      const params = new URLSearchParams();
      if (currentWorkspaceId) params.set('workspaceId', currentWorkspaceId);
      const response = await fetch(`/api/dialer/recordings?${params.toString()}`, {
        credentials: 'include',
        cache: 'no-store',
      });
      const data = await response.json().catch(() => null) as { groups?: SavedRecordingGroup[]; error?: string } | null;
      if (!response.ok) throw new Error(data?.error ?? 'Failed to load saved content');
      setGroups(data?.groups ?? []);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Failed to load saved content');
    } finally {
      setLoading(false);
    }
  }, [currentWorkspaceId, workspaceLoading]);

  useEffect(() => {
    void load();
  }, [load]);

  const recordingCount = groups.reduce((count, group) => count + group.recordings.length, 0);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6 md:px-6">
      <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="mb-2 flex items-center gap-2 text-red-600">
            <Star className="h-5 w-5 fill-current" />
            <span className="text-xs font-bold uppercase tracking-[0.18em]">Content library</span>
          </div>
          <h1 className="text-3xl font-black tracking-tight">Saved Content</h1>
          <p className="mt-2 max-w-2xl text-sm text-muted-foreground">
            Only conversations where you pressed Content are kept here. Press play to listen, or download the MP3 for editing or publishing.
          </p>
        </div>
        <Button variant="outline" onClick={() => void load()} disabled={loading}>
          {loading ? <Loader2 className="animate-spin" /> : <RefreshCw />}
          Refresh
        </Button>
      </div>

      {error ? (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="text-sm text-red-700">{error}</CardContent>
        </Card>
      ) : null}

      {!loading && !error && recordingCount === 0 ? (
        <Card>
          <CardContent className="flex min-h-64 flex-col items-center justify-center text-center">
            <AudioWaveform className="mb-4 h-10 w-10 text-muted-foreground" />
            <p className="font-semibold">No saved conversations yet</p>
            <p className="mt-1 max-w-md text-sm text-muted-foreground">
              Press Content during a call or before moving to the next contact. The MP3 will appear here after processing.
            </p>
          </CardContent>
        </Card>
      ) : null}

      {loading && groups.length === 0 ? (
        <div className="flex min-h-64 items-center justify-center"><Loader2 className="h-7 w-7 animate-spin text-red-600" /></div>
      ) : (
        <div className="space-y-4">
          {groups.map((group) => (
            <Card key={group.leadId}>
              <CardHeader>
                <CardTitle>{group.leadName}</CardTitle>
                <CardDescription>
                  {[group.company, group.phone].filter(Boolean).join(' · ') || 'Contact details unavailable'}
                </CardDescription>
              </CardHeader>
              <CardContent className="divide-y">
                {group.recordings.map((recording) => (
                  <div key={recording.callId} className="flex flex-col gap-3 py-4 first:pt-0 last:pb-0 sm:flex-row sm:flex-wrap sm:items-center">
                    <div className="min-w-0 flex-1">
                      <p className="font-semibold">
                        {new Date(recording.createdAt).toLocaleString(undefined, {
                          dateStyle: 'medium',
                          timeStyle: 'short',
                        })}
                      </p>
                      <p className="mt-1 text-sm text-muted-foreground">{formatDuration(recording.durationSeconds)}</p>
                    </div>
                    <RecordingPlayer recording={recording} leadName={group.leadName} onPlay={(audio) => {
                      if (activeAudio.current && activeAudio.current !== audio) activeAudio.current.pause();
                      activeAudio.current = audio;
                    }} />
                    <Button asChild className="bg-red-600 text-white hover:bg-red-700">
                      <a href={recording.downloadUrl} download>
                        <Download /> Download MP3
                      </a>
                    </Button>
                  </div>
                ))}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}

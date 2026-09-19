import type { DialerCall, DialerCallRecordingSummary } from '@/types/database';

export type DialerCallRecording = {
  recordingSid: string;
  recordingUrl: string;
  mp3Url: string;
  provider: string | null;
  status: string;
  durationSeconds: number | null;
  channels: number | null;
  updatedAt: string | null;
  errorCode: string | null;
  callControlId: string | null;
  callLegId: string | null;
  callSessionId: string | null;
};

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function object(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? value as Record<string, unknown> : {};
}

function numeric(value: unknown): number | null {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function dialerCallContentRetention(
  call: Pick<DialerCall, 'status_payload'>
): 'pending' | 'saved' | 'discard' | null {
  const payload = object(call.status_payload);
  const explicit = text(payload.contentRetention ?? payload.content_retention)?.toLowerCase();
  if (explicit === 'pending' || explicit === 'saved' || explicit === 'discard') {
    return explicit;
  }
  if (payload.contentSaved === true || payload.content_saved === true) return 'saved';
  if (payload.contentDiscarded === true || payload.content_discarded === true) return 'discard';
  return null;
}

export function isDialerCallContentSaved(call: Pick<DialerCall, 'status_payload'>): boolean {
  return dialerCallContentRetention(call) === 'saved';
}

export function getDialerCallRecording(call: Pick<DialerCall, 'status_payload' | 'telecom_provider'>): DialerCallRecording | null {
  const recording = call.status_payload?.recording;
  if (!recording || typeof recording !== 'object') {
    return null;
  }

  const candidate = recording as Record<string, unknown>;
  const recordingUrls = object(candidate.recording_urls ?? candidate.recordingUrls);
  const publicRecordingUrls = object(candidate.public_recording_urls ?? candidate.publicRecordingUrls);
  const recordingSid = text(candidate.recordingSid) ?? text(candidate.recording_id) ?? text(candidate.id);
  const mp3Url = text(candidate.mp3Url) ?? text(recordingUrls.mp3) ?? text(publicRecordingUrls.mp3);
  const recordingUrl = text(candidate.recordingUrl) ?? mp3Url ?? text(recordingUrls.wav) ?? text(publicRecordingUrls.wav);

  if (!recordingSid || !recordingUrl || !mp3Url) {
    return null;
  }

  return {
    recordingSid,
    recordingUrl,
    mp3Url,
    provider: text(candidate.provider) ?? call.telecom_provider ?? null,
    status: text(candidate.status) ?? 'pending',
    durationSeconds: numeric(candidate.durationSeconds ?? candidate.duration_seconds),
    channels: candidate.channels === 'dual' ? 2 : candidate.channels === 'single' ? 1 : numeric(candidate.channels),
    updatedAt: text(candidate.updatedAt) ?? text(candidate.updated_at),
    errorCode: text(candidate.errorCode) ?? text(candidate.error_code),
    callControlId: text(candidate.callControlId) ?? text(candidate.call_control_id),
    callLegId: text(candidate.callLegId) ?? text(candidate.call_leg_id),
    callSessionId: text(candidate.callSessionId) ?? text(candidate.call_session_id),
  };
}

export function getDialerCallRecordingSummary(
  call: Pick<DialerCall, 'status_payload' | 'telecom_provider'>
): DialerCallRecordingSummary | null {
  const recording = call.status_payload?.recording;
  if (!recording || typeof recording !== 'object') {
    return null;
  }

  const parsed = getDialerCallRecording(call);
  if (!parsed) return null;

  return {
    status: parsed.status,
    available: Boolean(parsed.recordingSid && parsed.mp3Url && parsed.status === 'completed'),
    duration_seconds: parsed.durationSeconds,
    channels: parsed.channels,
    updated_at: parsed.updatedAt,
    error_code: parsed.errorCode,
  };
}

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  dialerCallContentRetention,
  getDialerCallRecording,
  getDialerCallRecordingSummary,
  isDialerCallContentSaved,
} from '../recordings';

describe('dialler recording helpers', () => {
  it('reads Telnyx recording.saved metadata', () => {
    const call = {
      telecom_provider: 'telnyx' as const,
      status_payload: {
        recording: {
          recording_id: 'recording-123',
          recording_urls: { mp3: 'https://example.com/call.mp3' },
          status: 'completed',
          channels: 'dual',
          duration_seconds: '42',
          updated_at: '2026-08-29T22:00:00.000Z',
        },
      },
    };

    const recording = getDialerCallRecording(call);
    assert.equal(recording?.recordingSid, 'recording-123');
    assert.equal(recording?.mp3Url, 'https://example.com/call.mp3');
    assert.equal(recording?.channels, 2);
    assert.equal(recording?.durationSeconds, 42);
    assert.equal(getDialerCallRecordingSummary(call)?.available, true);
  });

  it('continues to read legacy recording metadata', () => {
    const recording = getDialerCallRecording({
      telecom_provider: 'twilio' as const,
      status_payload: {
        recording: {
          recordingSid: 'RE123',
          recordingUrl: 'https://example.com/recording',
          mp3Url: 'https://example.com/recording.mp3',
          status: 'completed',
        },
      },
    });

    assert.equal(recording?.recordingSid, 'RE123');
    assert.equal(recording?.provider, 'twilio');
  });

  it('uses per-call content retention instead of the lead favourite state', () => {
    assert.equal(dialerCallContentRetention({ status_payload: { contentRetention: 'pending' } }), 'pending');
    assert.equal(dialerCallContentRetention({ status_payload: { contentRetention: 'discard' } }), 'discard');
    assert.equal(dialerCallContentRetention({ status_payload: { contentSaved: true } }), 'saved');
    assert.equal(isDialerCallContentSaved({ status_payload: { contentRetention: 'saved' } }), true);
    assert.equal(isDialerCallContentSaved({ status_payload: { contentRetention: 'pending' } }), false);
  });
});

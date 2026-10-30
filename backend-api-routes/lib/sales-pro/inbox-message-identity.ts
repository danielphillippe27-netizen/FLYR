type CanonicalMessageIdentity = {
  channel: string;
  provider?: unknown;
  provider_event_id?: unknown;
};

type DialerMessageIdentity = {
  provider?: unknown;
  provider_message_id?: unknown;
};

function providerMessageKey(provider: unknown, messageId: unknown): string | null {
  if (typeof provider !== 'string' || typeof messageId !== 'string') return null;
  const name = provider.trim().toLowerCase();
  const id = messageId.trim();
  return name && id ? JSON.stringify([name, id]) : null;
}

/** Keep legacy history only when the same provider message is absent from the visible canonical inbox. */
export function unmatchedDialerMessages<T extends DialerMessageIdentity>(
  messages: T[],
  canonicalEvents: CanonicalMessageIdentity[],
): T[] {
  const canonicalIds = new Set(canonicalEvents
    .filter((event) => event.channel === 'sms')
    .map((event) => providerMessageKey(event.provider, event.provider_event_id))
    .filter((key): key is string => key !== null));

  return messages.filter((message) => {
    const key = providerMessageKey(message.provider, message.provider_message_id);
    return key === null || !canonicalIds.has(key);
  });
}

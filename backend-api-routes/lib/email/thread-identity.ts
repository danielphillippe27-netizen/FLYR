export type DirectionalEmailEvent = {
  direction?: string | null;
  fromEmail?: string | null;
  toEmail?: string | null;
};

function cleanEmail(value: string | null | undefined): string | null {
  return value?.trim() || null;
}

export function counterpartyEmail(event: DirectionalEmailEvent): string | null {
  if (event.direction === 'outbound') return cleanEmail(event.toEmail);
  if (event.direction === 'inbound') return cleanEmail(event.fromEmail);
  return cleanEmail(event.fromEmail) ?? cleanEmail(event.toEmail);
}

export function replyEmailForEvents(events: DirectionalEmailEvent[]): string | null {
  for (const event of [...events].reverse()) {
    const email = counterpartyEmail(event);
    if (email) return email;
  }
  return null;
}

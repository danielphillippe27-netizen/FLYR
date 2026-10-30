export const STORMS_DEMO_URL = 'https://wolfgrid.app/features/storms';
export const STORMS_DEMO_TITLE = 'Storm';
export const STORMS_DEMO_SUBJECT = 'Your WolfGrid Storms demo';

export function stormsDemoBody(recipientName?: string | null): string {
  const name = recipientName?.trim() || 'there';
  return `Hey ${name}, thought this could be useful for your team.

WolfGrid Storms helps you see hail and wind activity, choose an area to work, and turn it into a campaign—with addresses, conversations, and follow-ups in one place.

Here’s the demo: ${STORMS_DEMO_URL}

Any questions? Happy to walk you through it!`;
}

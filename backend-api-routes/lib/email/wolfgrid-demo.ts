export const WOLFGRID_DEMO_URL = 'https://wolfgrid.app';
export const WOLFGRID_DEMO_TITLE = 'Demo';
export const WOLFGRID_DEMO_SUBJECT = 'Your WolfGrid demo';

export function wolfgridDemoBody(): string {
  return `Hey there,\n\nClick this link for the WolfGrid demo: ${WOLFGRID_DEMO_URL}\n\nTake a look and let me know what you think. Happy to answer any questions!`;
}

export const RECEPTION_TEMPLATE_TITLE = 'Reception';
export const RECEPTION_TEMPLATE_SUBJECT = 'WolfGrid — following up from reception';

export function receptionBody(): string {
  return `Hey there,

I spoke with your receptionist, who directed me to you.

I’m reaching out about WolfGrid, an advanced field sales tracker. Does your company currently do any door-to-door sales, or have plans to in the future?

If so, here’s a demo so you can see how it could be useful for you and your company: ${WOLFGRID_DEMO_URL}

I’d be happy to discuss it further and answer any questions!`;
}

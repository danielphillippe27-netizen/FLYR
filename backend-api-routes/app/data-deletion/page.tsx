import Link from 'next/link';
import { LegalPage } from '@/components/social/LegalPage';

export const metadata = { title: 'WolfSocial Data Deletion Instructions', description: 'How to disconnect providers and delete WolfSocial account data.' };

export default function DataDeletionPage() {
  return <LegalPage title="Data Deletion Instructions" updated="Last updated August 5, 2026" sections={[
    ['Disconnect a connected platform', <div key="disconnect" className="space-y-2"><p>Open WolfSocial → Connections, select the connected Facebook, Instagram, TikTok, YouTube or LinkedIn account and choose Disconnect. This removes WolfSocial’s stored provider tokens and stops future access for that connection.</p><p>You may also revoke WolfSocial directly in the connected provider’s account security or application settings. Revoking access does not automatically delete content previously published to that provider.</p></div>],
    ['Delete your WolfSocial workspace', <p key="workspace">Email <a className="text-red-600 underline" href="mailto:support@wolfgrid.app?subject=WolfSocial%20data%20deletion">support@wolfgrid.app</a> from the email associated with your account using the subject “WolfSocial data deletion.” Include the workspace name. We will verify ownership before processing the request.</p>],
    ['What will be deleted', <p key="scope">We delete the active WolfSocial workspace, memberships, connected-account tokens and identifiers, uploaded media, drafts, schedules, publishing records, imported interactions, social contacts and workspace analytics associated with the verified request.</p>],
    ['Timing and confirmation', <p key="timing">We acknowledge verified requests as soon as reasonably possible and normally complete deletion within 30 days. We send confirmation to the requesting account email when active data has been deleted.</p>],
    ['Limited retention', <p key="retention">We may retain the minimum information required for security, fraud prevention, legal compliance or dispute resolution. Residual backup copies are isolated from normal use and age out through normal backup rotation. De-identified aggregate information that cannot identify you may remain.</p>],
    ['Need help', <span key="help">Visit <Link className="text-red-600 underline" href="/support">Support</Link> or review the <Link className="text-red-600 underline" href="/privacy">Privacy Policy</Link>.</span>],
  ]}/>;
}

import type { Metadata } from 'next';
import { WolfSocialPublicPage } from '@/components/social/WolfSocialPublicSite';

export const metadata: Metadata = {
  title: 'About | WolfSocial',
  description: 'About WolfSocial and WolfGrid, the company operating the service.',
  alternates: { canonical: 'https://social.wolfgrid.app/about' },
};

export default function AboutPage() {
  return (
    <WolfSocialPublicPage eyebrow="About WolfSocial" title="Social publishing software operated by WolfGrid." summary="WolfSocial is a web and iOS social media management service built for people who manage their own or their organization’s social accounts.">
      <div className="grid gap-8 lg:grid-cols-2">
        <section className="rounded-2xl border border-slate-200 bg-white p-7"><h2 className="text-2xl font-bold">The service</h2><p className="mt-4 leading-7 text-slate-600">WolfSocial helps creators, businesses and teams prepare media, tailor posts, schedule publication, manage supported engagement and understand available performance data from accounts they deliberately connect.</p><p className="mt-4 leading-7 text-slate-600">Users retain control of their content and approve publishing actions. Connected platforms remain independent services governed by their own terms and account controls.</p></section>
        <section className="rounded-2xl border border-slate-200 bg-white p-7"><h2 className="text-2xl font-bold">Operator and contact</h2><dl className="mt-5 space-y-4 text-sm"><div><dt className="font-bold">Operator</dt><dd className="mt-1 text-slate-600">WolfGrid Inc.</dd></div><div><dt className="font-bold">Service</dt><dd className="mt-1 text-slate-600">WolfSocial</dd></div><div><dt className="font-bold">Website</dt><dd className="mt-1 text-slate-600">social.wolfgrid.app</dd></div><div><dt className="font-bold">Support</dt><dd className="mt-1"><a className="text-red-600 underline" href="mailto:support@wolfgrid.app">support@wolfgrid.app</a></dd></div></dl></section>
      </div>
    </WolfSocialPublicPage>
  );
}

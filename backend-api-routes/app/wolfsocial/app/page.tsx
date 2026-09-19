import { redirect } from 'next/navigation';
import { getSupabaseServerClient } from '@/lib/supabase/server';
import { WolfSocialWorkspace } from '@/components/social/WolfSocialWorkspace';

export const metadata = { title: 'Workspace · WolfSocial' };

export default async function WolfSocialAppPage() {
  const supabase = await getSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/login?next=/app');
  return <main className="min-h-screen bg-slate-50"><div className="border-b bg-[#07090d] px-5 py-4 text-white"><div className="mx-auto flex max-w-[1600px] items-center justify-between"><a href="/app" className="font-black">WOLF<span className="text-red-500">SOCIAL</span></a><span className="text-xs text-slate-400">Powered by WolfGrid</span></div></div><WolfSocialWorkspace surface="standalone" /></main>;
}


import { WolfSocialAuth } from '@/components/social/WolfSocialAuth';

export const metadata = {
  title: 'Create your free workspace · WolfSocial',
  description: 'Create a WolfSocial workspace for yourself, your business or your team.',
};

export default function SignupPage() {
  return <WolfSocialAuth initialMode="create-account" />;
}

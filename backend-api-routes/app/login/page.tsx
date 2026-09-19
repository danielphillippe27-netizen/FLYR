import { WolfSocialAuth } from '@/components/social/WolfSocialAuth';

export const metadata = { title: 'Sign in · WolfSocial' };

export default function LoginPage() {
  return <WolfSocialAuth initialMode="sign-in" />;
}

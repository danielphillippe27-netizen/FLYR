import { PowerDialerSettingsCard } from '@/components/settings/PowerDialerSettingsCard';

export default function SettingsPage() {
  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-8 md:px-6">
      <div className="mb-6"><h1 className="text-3xl font-bold tracking-tight">Settings</h1><p className="mt-1 text-sm text-muted-foreground">Manage your salesperson calling and workspace preferences.</p></div>
      <PowerDialerSettingsCard />
    </div>
  );
}

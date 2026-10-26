'use client';

import { Moon, Sun } from 'lucide-react';
import { useTheme } from '@/lib/theme-provider';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

export function AppearanceSettingsCard() {
  const { theme, setTheme } = useTheme();

  return (
    <Card>
      <CardHeader>
        <CardTitle>Appearance</CardTitle>
        <CardDescription>Choose how your workspace looks. Your preference is saved on this device.</CardDescription>
      </CardHeader>
      <CardContent className="flex flex-wrap items-center justify-between gap-4">
        <p className="text-sm font-medium">Theme</p>
        <div role="group" aria-label="Workspace theme" className="flex gap-2">
          <Button type="button" variant={theme === 'light' ? 'default' : 'outline'} aria-pressed={theme === 'light'} onClick={() => setTheme('light')}>
            <Sun aria-hidden="true" /> Light
          </Button>
          <Button type="button" variant={theme === 'dark' ? 'default' : 'outline'} aria-pressed={theme === 'dark'} onClick={() => setTheme('dark')}>
            <Moon aria-hidden="true" /> Dark
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

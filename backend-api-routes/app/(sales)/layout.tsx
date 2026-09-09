import type { ReactNode } from 'react';
import { requireSalesperson } from '@/lib/auth/requireSalesperson';
import { SalesWorkspaceShell } from './SalesWorkspaceShell';

export default async function SalesLayout({ children }: { children: ReactNode }) {
  await requireSalesperson();
  return <SalesWorkspaceShell>{children}</SalesWorkspaceShell>;
}


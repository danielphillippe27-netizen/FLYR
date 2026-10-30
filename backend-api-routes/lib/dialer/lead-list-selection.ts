// Keep saved list membership intact when more than one Places page is imported.
export function parseFocusedLeadIds(value: string | null): string[] {
  return [...new Set((value ?? '').split(',').map((id) => id.trim()).filter(Boolean))].slice(0, 2000);
}

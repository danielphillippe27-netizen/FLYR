import { Plus } from 'lucide-react';
import { SalespersonPlacesLeadFinder } from '@/components/scraper/SalespersonPlacesLeadFinder';

export default function ScraperPage() {
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="border-b border-border bg-white px-6 py-5">
        <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 items-center justify-center rounded-lg bg-red-50 text-red-500"><Plus /></span>
          <div><h1 className="text-2xl font-bold">Add Leads</h1><p className="text-sm text-muted-foreground">Lead finder modes for sales outreach</p></div>
        </div>
      </header>
      <div className="px-4 py-6 md:px-6"><SalespersonPlacesLeadFinder /></div>
    </div>
  );
}


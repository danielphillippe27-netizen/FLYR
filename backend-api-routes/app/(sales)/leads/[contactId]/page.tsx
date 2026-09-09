import { LeadRecordPageView } from '@/components/crm/LeadRecordPageView';

export default async function LeadPage({ params }: { params: Promise<{ contactId: string }> }) {
  const { contactId } = await params;
  return <LeadRecordPageView contactId={contactId} />;
}


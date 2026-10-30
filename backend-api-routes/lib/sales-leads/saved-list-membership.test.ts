import test from 'node:test';
import assert from 'node:assert/strict';
import type { SalesLead } from '@/types/database';
import { mergeSavedListMembership } from './saved-list-membership';

const lead = (id: string, extra = {}) => ({ id, created_at: '2026-10-27T17:00:00Z', ...extra }) as SalesLead;
const saved = (id: string, leadIds: string[]) => ({ id, name: id, createdAt: '2026-10-27T17:00:00Z', leadIds });

test('a saved 150-member list keeps its membership when only two retain their current list tag', () => {
  const leads = Array.from({ length: 150 }, (_, i) => lead(`lead-${i}`, { list_id: i < 2 ? 'Barrie' : 'newer-search' }));
  const groups = mergeSavedListMembership([{ id: 'Barrie', title: 'Barrie', newestAt: '', leads: leads.slice(0, 2) }], [saved('Barrie', leads.map(l => l.id))], leads);
  assert.equal(groups[0].leads.length, 150);
});

test('converted contacts and archived queue entries remain members of their original saved list', () => {
  const leads = [lead('contact', { sales_contact_id: 'contact-1' }), lead('archived', { lead_state: 'archived' })];
  assert.equal(mergeSavedListMembership([], [saved('Barrie', ['contact', 'archived'])], leads)[0].leads.length, 2);
});

test('multiple lists can share the same business without losing older membership', () => {
  const leads = [lead('one')];
  const result = mergeSavedListMembership([], [saved('Barrie', ['one']), saved('Roofers', ['one'])], leads);
  assert.equal(result.length, 2);
  assert.ok(result.every(list => list.leads.length === 1));
});

test('missing or inaccessible lead records cannot be manufactured into saved lists', () => {
  const groups = mergeSavedListMembership([], [saved('Barrie', ['mine', 'other-owner'])], [lead('mine')]);
  assert.deepEqual(groups[0].leads.map(l => l.id), ['mine']);
});

test('empty saved lists retain their identity', () => {
  assert.equal(mergeSavedListMembership([], [saved('Empty', [])], [])[0].title, 'Empty');
});

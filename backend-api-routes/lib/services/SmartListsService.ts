import { createClient } from '@/lib/supabase/client';
import type { SmartListBaseKind, SmartListCriteria, WorkspaceSmartList } from '@/types/smart-lists';

type SmartListRow = {
  id: string;
  workspace_id: string;
  created_by_user_id: string;
  name: string;
  criteria?: unknown;
  created_at: string;
  updated_at: string;
};

type CreateWorkspaceSmartListPayload = {
  workspaceId: string;
  createdByUserId: string;
  name: string;
  criteria: SmartListCriteria;
};

export class SmartListsService {
  private static client = createClient();
  private static localIdPrefix = 'local-smart-list:';
  private static localStorageKeyPrefix = 'flyr:crm:local-smart-lists:';

  private static isBrowser(): boolean {
    return typeof window !== 'undefined';
  }

  private static localStorageKey(workspaceId: string, userId: string): string {
    return `${this.localStorageKeyPrefix}${workspaceId}:${userId}`;
  }

  private static canFallbackToLocal(error: unknown): boolean {
    const message =
      error && typeof error === 'object' && 'message' in error
        ? String((error as { message?: unknown }).message ?? '').toLowerCase()
        : '';

    return (
      message.includes('smart_lists') ||
      message.includes('smart lists') ||
      message.includes('relation') ||
      message.includes('does not exist') ||
      message.includes('could not find the table') ||
      message.includes('permission denied')
    );
  }

  private static readLocalWorkspaceSmartLists(workspaceId: string, userId: string): WorkspaceSmartList[] {
    if (!this.isBrowser()) return [];

    try {
      const raw = window.localStorage.getItem(this.localStorageKey(workspaceId,userId)) ?? window.localStorage.getItem(`${this.localStorageKeyPrefix}${workspaceId}`);
      if (!raw) return [];
      const parsed = JSON.parse(raw) as SmartListRow[];
      if (!Array.isArray(parsed)) return [];
      return parsed.filter(row => row.created_by_user_id === userId).map((row) => this.normalizeRow(row));
    } catch {
      return [];
    }
  }

  private static writeLocalWorkspaceSmartLists(workspaceId: string, userId: string, lists: WorkspaceSmartList[]): void {
    if (!this.isBrowser()) return;

    try {
      window.localStorage.setItem(this.localStorageKey(workspaceId,userId), JSON.stringify(lists));
    } catch {
      // Ignore localStorage write failures and preserve app flow.
    }
  }

  static async createLocalWorkspaceSmartList(payload: {
    workspaceId: string;
    name: string;
    criteria: SmartListCriteria;
    createdByUserId?: string;
  }): Promise<WorkspaceSmartList> {
    const userId = await this.currentUserId();
    const existing = this.readLocalWorkspaceSmartLists(payload.workspaceId,userId);
    const now = new Date().toISOString();
    const created: WorkspaceSmartList = {
      id: `${this.localIdPrefix}${crypto.randomUUID()}`,
      workspace_id: payload.workspaceId,
      created_by_user_id: userId,
      name: payload.name.trim(),
      criteria: this.normalizeCriteria(payload.criteria),
      created_at: now,
      updated_at: now,
    };

    this.writeLocalWorkspaceSmartLists(payload.workspaceId,userId, [created, ...existing]);
    return created;
  }

  private static normalizeCriteria(value: unknown): SmartListCriteria {
    const record = value && typeof value === 'object' ? (value as Partial<SmartListCriteria>) : {};
    const baseKind = record.baseKind;
    const validBaseKind: SmartListBaseKind =
      baseKind === 'campaign' || baseKind === 'farm' || baseKind === 'networking' || baseKind === 'custom'
        ? baseKind
        : 'custom';
    const tags = Array.isArray(record.tags)
      ? record.tags.map((tag) => String(tag).trim()).filter(Boolean)
      : [];
    const source = typeof record.source === 'string' ? record.source.trim() : '';
    const campaignIds = Array.isArray(record.campaignIds)
      ? record.campaignIds.map((id) => String(id).trim()).filter(Boolean)
      : [];
    const farmIds = Array.isArray(record.farmIds)
      ? record.farmIds.map((id) => String(id).trim()).filter(Boolean)
      : [];
    const contactIds = Array.isArray(record.contactIds)
      ? record.contactIds.map((id) => String(id).trim()).filter(Boolean)
      : [];
    const masterLeadIds = Array.isArray(record.masterLeadIds)
      ? record.masterLeadIds.map((id) => String(id).trim()).filter(Boolean)
      : [];

    return {
      baseKind: validBaseKind,
      tags,
      source,
      campaignIds,
      farmIds,
      contactIds,
      masterLeadIds,
    };
  }

  private static normalizeRow(row: SmartListRow): WorkspaceSmartList {
    return {
      id: row.id,
      workspace_id: row.workspace_id,
      created_by_user_id: row.created_by_user_id,
      name: row.name,
      criteria: this.normalizeCriteria(row.criteria),
      created_at: row.created_at,
      updated_at: row.updated_at,
    };
  }

  static async fetchWorkspaceSmartLists(workspaceId: string): Promise<WorkspaceSmartList[]> {
    return this.fetchUserWorkspaceSmartLists(workspaceId,await this.currentUserId());
  }

  private static async currentUserId(): Promise<string> {
    const {data,error}=await this.client.auth.getSession();
    if (error || !data.session?.user.id) throw new Error('Sign in to access your lists.');
    return data.session.user.id;
  }

  static async fetchUserWorkspaceSmartLists(workspaceId: string, userId: string): Promise<WorkspaceSmartList[]> {
    if (await this.currentUserId() !== userId) throw new Error('List owner does not match the signed-in user.');
    const localLists = this.readLocalWorkspaceSmartLists(workspaceId,userId);
    const { data, error } = await this.client
      .from('smart_lists')
      .select('*')
      .eq('workspace_id', workspaceId)
      .eq('created_by_user_id', userId)
      .order('created_at', { ascending: false });

    if (error) {
      if (this.canFallbackToLocal(error)) {
        return localLists;
      }
      throw error;
    }

    const remoteLists = (data ?? []).map((row) => this.normalizeRow(row as SmartListRow));
    const seenIds = new Set(remoteLists.map((list) => list.id));
    const merged = [...remoteLists, ...localLists.filter((list) => !seenIds.has(list.id))];
    return merged.sort((a, b) => b.created_at.localeCompare(a.created_at));
  }

  static async createWorkspaceSmartList(payload: CreateWorkspaceSmartListPayload): Promise<WorkspaceSmartList> {
    const userId = await this.currentUserId();
    const { data, error } = await this.client
      .from('smart_lists')
      .insert({
        workspace_id: payload.workspaceId,
        created_by_user_id: userId,
        name: payload.name.trim(),
        criteria: payload.criteria,
      })
      .select('*')
      .single();

    if (error) {
      if (this.canFallbackToLocal(error)) {
        return this.createLocalWorkspaceSmartList(payload);
      }
      throw error;
    }
    return this.normalizeRow(data as SmartListRow);
  }

  static async deleteWorkspaceSmartList(id: string, workspaceId?: string): Promise<void> {
    const userId = await this.currentUserId();
    if (id.startsWith(this.localIdPrefix)) {
      if (!workspaceId) return;
      const existing = this.readLocalWorkspaceSmartLists(workspaceId,userId);
      this.writeLocalWorkspaceSmartLists(
        workspaceId,userId,
        existing.filter((list) => list.id !== id)
      );
      return;
    }

    const { error } = await this.client.from('smart_lists').delete().eq('id', id).eq('created_by_user_id',userId);
    if (error) {
      if (workspaceId && this.canFallbackToLocal(error)) {
        const existing = this.readLocalWorkspaceSmartLists(workspaceId,userId);
        this.writeLocalWorkspaceSmartLists(
          workspaceId,userId,
          existing.filter((list) => list.id !== id)
        );
        return;
      }
      throw error;
    }
  }
}


import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import * as wolfgridDemo from '../../email/wolfgrid-demo';
import * as stormsDemo from '../../email/storms-demo';
const require = createRequire(import.meta.url);

function find(tree: any, predicate: (node: any) => boolean): any {
  if (!tree || typeof tree !== 'object') return undefined;
  if (predicate(tree)) return tree;
  for (const child of [tree.props?.children].flat(Infinity)) {
    const result = find(child, predicate);
    if (result) return result;
  }
}

function harness({ fail = false } = {}) {
  let index = 0;
  const state: any[] = [];
  const refs: any[] = [];
  let refIndex = 0;
  const requests: any[] = [];
  let closes = 0;
  let sent = '';
  const source = readFileSync(new URL('../../../components/sales-pro/TextComposer.tsx', import.meta.url), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2022 } }).outputText;
  const overrides: Record<string, any> = {
    react: {
      useState: (initial: any) => {
        const i = index++;
        if (!(i in state)) state[i] = typeof initial === 'function' ? initial() : initial;
        return [state[i], (value: any) => { state[i] = typeof value === 'function' ? value(state[i]) : value; }];
      },
      useRef: (initial: any) => refs[refIndex++] ?? (refs[refIndex - 1] = { current: initial }),
    },
    '@/lib/email/wolfgrid-demo': wolfgridDemo,
    '@/lib/email/storms-demo': stormsDemo,
    '@/lib/dialer/phone': { formatPhoneDisplay: (value: string) => value },
    '@/components/ui/button': { Button: 'button' },
    '@/components/ui/input': { Input: 'input' },
    '@/components/ui/textarea': { Textarea: 'textarea' },
    '@/components/ui/dialog': { Dialog: 'dialog', DialogContent: 'content', DialogHeader: 'header', DialogTitle: 'title', DialogDescription: 'description' },
  };
  const module = { exports: {} as any };
  vm.runInNewContext(output, {
    module, exports: module.exports, require: (id: string) => overrides[id] ?? require(id),
    fetch: async (url: string, options: any) => {
      requests.push({ url, body: JSON.parse(options.body) });
      return { ok: !fail, json: async () => fail ? { error: 'Unable to send' } : {} };
    },
  });
  const render = () => {
    index = 0; refIndex = 0;
    return module.exports.TextComposer({ recipient: { leadId: 'lead-one', workspaceId: 'workspace-one', phone: '+14165550101', name: 'Business' },
      onClose: () => closes++, onSent: (message: string) => sent = message });
  };
  return { render, requests, state, closes: () => closes, sent: () => sent };
}

test('opening a text draft and cancelling never sends a message', () => {
  const h = harness();
  assert.ok(find(h.render(), n => n.type === 'textarea').props.value.includes('https://wolfgrid.app'));
  assert.equal(h.requests.length, 0);
  find(h.render(), n => n.type === 'button' && n.props.children === 'Cancel').props.onClick();
  assert.equal(h.closes(), 1);
  assert.equal(h.requests.length, 0);
});

test('Send text submits the edited draft once to the captured recipient', async () => {
  const h = harness();
  find(h.render(), n => n.type === 'textarea').props.onChange({ target: { value: 'Custom edited message' } });
  const form = find(h.render(), n => n.type === 'form');
  await Promise.all([form.props.onSubmit({ preventDefault() {} }), form.props.onSubmit({ preventDefault() {} })]);
  assert.deepEqual(h.requests, [{ url: '/api/dialer/leads/lead-one/sms', body: {
    workspaceId: 'workspace-one', phone: '+14165550101', body: 'Custom edited message',
  } }]);
  assert.equal(h.closes(), 1);
  assert.equal(h.sent(), 'Text sent.');
});

test('failed sends keep the edited draft open for review', async () => {
  const h = harness({ fail: true });
  find(h.render(), n => n.type === 'textarea').props.onChange({ target: { value: 'Keep this draft' } });
  await find(h.render(), n => n.type === 'form').props.onSubmit({ preventDefault() {} });
  assert.equal(h.closes(), 0);
  assert.equal(find(h.render(), n => n.type === 'textarea').props.value, 'Keep this draft');
  assert.equal(find(h.render(), n => n.props?.role === 'alert').props.children, 'Unable to send');
});

test('templates select the correct homepage and storms links without sending', () => {
  const h = harness();
  find(h.render(), n => n.type === 'button' && n.props.children === 'Storm').props.onClick();
  assert.ok(find(h.render(), n => n.type === 'textarea').props.value.includes(stormsDemo.STORMS_DEMO_URL));
  find(h.render(), n => n.type === 'button' && n.props.children === 'Demo').props.onClick();
  assert.equal(find(h.render(), n => n.type === 'textarea').props.value, wolfgridDemo.wolfgridDemoBody());
  assert.equal(h.requests.length, 0);
});

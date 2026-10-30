import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import ts from 'typescript';
import { sendCallDigit } from '../dtmf';
const require = createRequire(import.meta.url);

test('keypad routes all twelve keys through the correct active provider', () => {
  for (const provider of ['telnyx', 'twilio'] as const) {
    const sent: string[] = [];
    const call = provider === 'telnyx' ? { dtmf: (digit: string) => sent.push(digit) }
      : { sendDigits: (digit: string) => sent.push(digit) };
    for (const digit of '123456789*0#') sendCallDigit(provider, call, digit);
    assert.equal(sent.join(''), '123456789*0#');
  }
});

test('keypad rejects invalid keys and missing or unsupported calls', () => {
  const sent: string[] = [];
  for (const digit of ['', '12', 'A', 'w', 'Enter']) {
    assert.throws(() => sendCallDigit('telnyx', { dtmf: (value) => sent.push(value) }, digit));
  }
  assert.throws(() => sendCallDigit('telnyx', null, '1'));
  assert.throws(() => sendCallDigit('twilio', {}, '1'));
  assert.deepEqual(sent, []);
});

function keypadHarness(connected = true) {
  let index = 0;
  const state: unknown[] = [false, '', ''];
  const sent: string[] = [];
  const source = readFileSync(new URL('../../../components/dialer/CallKeypad.tsx', import.meta.url), 'utf8');
  const output = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX, target: ts.ScriptTarget.ES2022,
  } }).outputText;
  const module = { exports: {} as any };
  const overrides: Record<string, unknown> = {
    react: {
      useEffect: () => {},
      useState: () => {
        const i = index++;
        return [state[i], (value: any) => { state[i] = typeof value === 'function' ? value(state[i]) : value; }];
      },
    },
    '@/components/ui/button': { Button: 'button' },
    '@/components/ui/dialog': { Dialog: 'dialog', DialogContent: 'content', DialogHeader: 'header', DialogTitle: 'title', DialogDescription: 'description' },
  };
  vm.runInNewContext(output, { module, exports: module.exports, require: (id: string) => overrides[id] ?? require(id) });
  const render = () => {
    index = 0;
    return module.exports.CallKeypad({ connected, callKey: 'call', onDigit: (digit: string) => { sent.push(digit); return true; } });
  };
  return { render, sent, state };
}

function find(tree: any, predicate: (node: any) => boolean): any {
  if (!tree || typeof tree !== 'object') return undefined;
  if (predicate(tree)) return tree;
  for (const child of [tree.props?.children].flat(Infinity)) {
    const result = find(child, predicate);
    if (result) return result;
  }
}

test('clicking and typing keypad digits each sends one tone; held keys do not repeat', () => {
  const h = keypadHarness();
  find(h.render(), n => n.props?.['aria-haspopup'] === 'dialog').props.onClick();
  assert.equal(find(h.render(), n => n.type === 'dialog').props.open, true);
  find(h.render(), n => n.props?.['aria-label'] === '1').props.onClick();
  const content = find(h.render(), n => n.type === 'content');
  const event = { key: '#', repeat: false, preventDefault() {}, stopPropagation() {} };
  content.props.onKeyDown(event);
  content.props.onKeyDown({ ...event, repeat: true });
  content.props.onKeyDown({ ...event, key: '2', metaKey: true });
  assert.deepEqual(h.sent, ['1', '#']);
  assert.equal(h.state[1], '1#');
});

test('keypad is disabled and sends no tones while disconnected', () => {
  const h = keypadHarness(false);
  assert.equal(find(h.render(), n => n.props?.['aria-haspopup'] === 'dialog').props.disabled, true);
  find(h.render(), n => n.props?.['aria-label'] === '1').props.onClick();
  assert.deepEqual(h.sent, []);
});

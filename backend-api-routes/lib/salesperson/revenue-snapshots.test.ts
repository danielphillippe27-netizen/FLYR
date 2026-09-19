import assert from 'node:assert/strict';
import test from 'node:test';
import type Stripe from 'stripe';
import { stripe } from '../stripe';
import { loadSalespersonStripeRevenue, monthlyRecurringCents } from './revenue-snapshots';

function item(
  unitAmount: number,
  interval: Stripe.Price.Recurring.Interval,
  intervalCount = 1,
  quantity = 1
): Stripe.SubscriptionItem {
  return {
    quantity,
    price: {
      unit_amount: unitAmount,
      recurring: { interval, interval_count: intervalCount },
    },
  } as Stripe.SubscriptionItem;
}

test('normalizes monthly and annual prices to monthly cents', () => {
  assert.equal(monthlyRecurringCents(item(2_500, 'month')), 2_500);
  assert.equal(monthlyRecurringCents(item(12_000, 'year')), 1_000);
  assert.equal(monthlyRecurringCents(item(12_000, 'year', 1, 3)), 3_000);
});

test('normalizes multi-month billing and ignores non-recurring prices', () => {
  assert.equal(monthlyRecurringCents(item(9_000, 'month', 3)), 3_000);
  const oneTime = item(5_000, 'month');
  oneTime.price.recurring = null;
  assert.equal(monthlyRecurringCents(oneTime), 0);
});

test('a failed subscription lookup rejects the total instead of understating personal MRR', async (t) => {
  const mode=process.env.STRIPE_MODE, key=process.env.STRIPE_SECRET_KEY_TEST;
  process.env.STRIPE_MODE='test'; process.env.STRIPE_SECRET_KEY_TEST='sk_test_local_fixture';
  t.after(() => {
    if(mode===undefined) delete process.env.STRIPE_MODE; else process.env.STRIPE_MODE=mode;
    if(key===undefined) delete process.env.STRIPE_SECRET_KEY_TEST; else process.env.STRIPE_SECRET_KEY_TEST=key;
  });
  const requested:string[]=[];
  t.mock.method(stripe.subscriptions,'retrieve',async (id:string) => {
    requested.push(id);
    if(id==='sub_failed') throw new Error('Provider unavailable');
    return {status:'active',items:{data:[{...item(2500,'month'),price:{...item(2500,'month').price,currency:'cad'}}]}};
  });
  const admin={from(table:string) {
    const q:any={select:()=>q,eq:()=>q,not:()=>q,
      maybeSingle:async()=>({data:{id:'own-salesperson'},error:null}),
      then:(resolve:any,reject:any)=>Promise.resolve({data:[{stripe_subscription_id:'sub_ok'},{stripe_subscription_id:'sub_failed'}],error:null}).then(resolve,reject)};
    return q;
  }} as any;
  await assert.rejects(loadSalespersonStripeRevenue(admin,'own-salesperson','own-user'),/Provider unavailable/);
  assert.deepEqual(requested,['sub_ok','sub_failed']);
});

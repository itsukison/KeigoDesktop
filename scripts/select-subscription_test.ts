// §3.2's selection, unit-tested against the REAL module the webhook imports.
//
//   deno test --allow-read --allow-env scripts/select-subscription_test.ts
//
// This is the half of §3.2 that lives in TypeScript rather than SQL. The SQL
// validates product membership again (`desktop.pro_products`), so a mistake here
// cannot grant Pro to an unrelated product — but it *can* pick the wrong
// subscription, drop the billing period, or miss a duplicate, and none of those
// are caught downstream.

import { assertEquals } from "jsr:@std/assert@1";
import { selectSubscription } from "../supabase/functions/_shared/billing.ts";

const PRO = new Set(["prod_V274Ok8sSwkjuZ"]);

function sub(over: Record<string, unknown> = {}) {
  return {
    id: "sub_1",
    status: "active",
    created: 1000,
    cancel_at_period_end: false,
    cancel_at: null,
    schedule: null,
    items: {
      data: [{
        current_period_start: 1_700_000_000,
        current_period_end: 1_702_000_000,
        price: {
          id: "price_1",
          lookup_key: "pro_monthly_jpy",
          product: "prod_V274Ok8sSwkjuZ",
          recurring: { interval: "month" },
        },
      }],
    },
    ...over,
  };
}

Deno.test("absence of any subscription is a valid state, never an error", () => {
  const { selected, duplicates } = selectSubscription([], PRO);
  assertEquals(selected, null);
  assertEquals(duplicates, 0);
});

Deno.test("§3.2: an unrelated product is not ours", () => {
  const other = sub({
    items: { data: [{ ...sub().items.data[0], price: { ...sub().items.data[0].price, product: "prod_OTHER" } }] },
  });
  assertEquals(selectSubscription([other], PRO).selected, null);
});

Deno.test("§3.2: a subscription with more than one item is not ours", () => {
  const two = sub();
  two.items.data.push(two.items.data[0]);
  assertEquals(selectSubscription([two], PRO).selected, null);
});

Deno.test("§3.2: a week/day interval is not ours", () => {
  const weekly = sub();
  weekly.items.data[0].price.recurring.interval = "week";
  assertEquals(selectSubscription([weekly], PRO).selected, null);
});

Deno.test("§7: the period comes off items.data[0], not the subscription", () => {
  // A subscription object carrying its own (deprecated, now absent) period must be
  // ignored in favour of the item's — reading the wrong one writes a null period
  // and silently breaks the 解約予定 display.
  const s = sub({ current_period_end: 999 });
  const { selected } = selectSubscription([s], PRO);
  assertEquals(selected?.currentPeriodEnd, new Date(1_702_000_000_000).toISOString());
  assertEquals(selected?.currentPeriodStart, new Date(1_700_000_000_000).toISOString());
});

Deno.test("§3.1: canceled and unpaid still reach the reconciler", () => {
  // They map to `free`, but they must be PASSED ON — otherwise the row keeps
  // reporting whatever status last happened to qualify.
  for (const status of ["canceled", "unpaid", "incomplete", "past_due"]) {
    const { selected } = selectSubscription([sub({ status })], PRO);
    assertEquals(selected?.status, status);
  }
});

Deno.test("§9 row 40: two qualifying subscriptions — latest created wins, and it is flagged", () => {
  const older = sub({ id: "sub_old", created: 1000 });
  const newer = sub({ id: "sub_new", created: 2000 });
  const { selected, duplicates } = selectSubscription([older, newer], PRO);
  assertEquals(selected?.id, "sub_new");
  assertEquals(duplicates, 2, "a duplicate alert must be raised, never summed");
});

Deno.test("a live subscription beats a canceled one regardless of created", () => {
  // `canceled` is terminal and immutable, so a newer canceled row must not
  // displace the active subscription the user is actually paying for.
  const canceledNewer = sub({ id: "sub_dead", status: "canceled", created: 9000 });
  const activeOlder = sub({ id: "sub_live", status: "active", created: 1000 });
  const { selected, duplicates } = selectSubscription([canceledNewer, activeOlder], PRO);
  assertEquals(selected?.id, "sub_live");
  assertEquals(duplicates, 0, "one live subscription is not a duplicate");
});

Deno.test("cancel_at_period_end is carried as display state", () => {
  const { selected } = selectSubscription([sub({ cancel_at_period_end: true })], PRO);
  assertEquals(selected?.cancelAtPeriodEnd, true);
  assertEquals(selected?.status, "active", "scheduled to cancel is still active (§3.1)");
});

Deno.test("an expanded product object resolves the same as a product id string", () => {
  const expanded = sub();
  // deno-lint-ignore no-explicit-any
  (expanded.items.data[0].price as any).product = { id: "prod_V274Ok8sSwkjuZ" };
  assertEquals(selectSubscription([expanded], PRO).selected?.productId, "prod_V274Ok8sSwkjuZ");
});

/* Pins the slide numbers. Run: npm test */
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const E = require("../mock/engine/engine");

const M = 1e6;
const base = () => E.build(E.demoInput());
const run = (sim) => E.build(E.demoInput(), sim);

test("position matches the base data", () => {
  const { brief: b } = base();
  assert.equal(b.CashToday, 22 * M);
  assert.equal(b.RunTotal, 12 * M);
  assert.equal(b.RunInvoiceCount, 180);
  assert.equal(b.RunVendorCount, 47);
  assert.equal(b.CashAfterRun, 10 * M);
  assert.equal(b.LowPoint, 9.5 * M);
  assert.equal(b.LowPointDay, 9);
  assert.equal(b.StressedLowPoint, 5.5 * M);
  assert.equal(b.FloorBreach, true);
  assert.equal(b.RunHoldsFloor, true);
  assert.equal(b.ArTotal, 85 * M);
  assert.equal(b.ArOverdue, 9 * M);
  assert.equal(b.ApTotal, 100 * M);
  assert.equal(b.ApDueWindow, 18 * M);
  assert.equal(b.ArOverdueChangePct, 11.9);
  assert.equal(b.ApOverdueChangePct, -5);
  assert.equal(b.Headline, "This week's run holds above floor — 3 items to review");
});

test("risks are ranked by exposure x probability x floor weight", () => {
  const { risks } = base();
  assert.deepEqual(risks.map((r) => r.RiskType), ["AR_LATE", "AP_OFFPATTERN", "SPEND_SPIKE", "AP_BLOCKED"]);
  assert.equal(risks[0].Score, 6 * M);
  assert.equal(risks[0].Probability, 0.75);
  assert.equal(risks[0].DueBy, "2026-08-10"); // Mon 10 Aug
  assert.equal(risks[1].Probability, 0.86);
});

test("advice: defer, prioritise, deposit, early pay", () => {
  const t = Object.fromEntries(base().tradeoffs.map((x) => [x.Kind, x]));
  assert.equal(t.DEFER.DeferItem, "AP-SPR-0001");
  assert.equal(t.DEFER.PayItem, "AP-RAW-0001");
  assert.equal(t.DEFER.ShortfallBefore, 2.5 * M);
  assert.equal(t.PRIORITIZE.ActionDate, "2026-08-07"); // Fri 7 Aug (slide says 8 Aug)
  assert.equal(t.DEPOSIT.Amount, 3 * M);
  assert.equal(t.DEPOSIT.Income, 1726.03);
  assert.equal(t.DEPOSIT.Status, "HELD");
  assert.equal(t.EARLYPAY.AnnualizedPct, 37.2);
});

test("what-if: ABC late breaches, factoring recovers, holding XYZ lifts the week", () => {
  assert.equal(run({ lateIds: ["AR-ABC-0001"] }).brief.LowPoint, 5.5 * M);
  const f = run({ factorIds: ["AR-ABC-0001"] }).brief;
  assert.equal(f.LowPoint, 9.4 * M);
  assert.equal(f.StressedLowPoint, 9.4 * M);
  assert.equal(f.FloorBreach, false);
  const h = run({ heldIds: ["AP-XYZ-0001"] }).days;
  assert.equal(h[3].ClosingScheduled, 12.8 * M);
  assert.equal(h[9].ClosingScheduled, 9.5 * M);
  assert.equal(run({ floorOverride: 10 * M }).brief.ScheduledBreach, true);
});

test("drafts carry the computed figures", () => {
  const r = base();
  const n = E.draft("COLLECTION_NOTICE", { brief: r.brief, risk: r.risks[0] });
  assert.match(n.Subject, /ABC Industries — overdue balance \$4\.0M/);
  assert.doesNotMatch(n.Body, /factor/i);
  const x = E.draft("RUN_EXCEPTIONS", { brief: r.brief, risks: r.risks });
  assert.match(x.Body, /Release the remaining \$7\.5M/);
});

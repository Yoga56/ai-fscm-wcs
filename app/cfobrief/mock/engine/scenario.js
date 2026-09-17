/*
 * Demo scenario — the slide story ("as of Tue 4 Aug, USD, illustrative").
 *
 * This file mirrors ZCL_CFO_DEMO_SEED row for row. Offsets are calendar days
 * relative to the anchor date; the anchor must be a Tuesday so that the weekly
 * payment run falls on Thursday (anchor + 2), as on the slides.
 */
"use strict";

const M = 1000000;

const config = {
  companyCode: "1000",
  currency: "USD",
  floor: 8 * M,
  horizonDays: 30,
  runWeekday: 4, // 1 = Monday ... 7 = Sunday
  proposalLeadBd: 1, // proposal is built one business day before the run
  approvalLeadBd: 3, // approvals needed three business days before the proposal
  factoringLeadBd: 3,
  factoringAdvancePct: 97.5,
  depositRatePct: 4.2,
  depositDays: 5,
  lateFeeRatePct: 3.0,
  apWindowDays: 14,
  stressThreshold: 0.5,
  collectionLagBd: 2,
  minHistory: 5,
  zScoreThreshold: 3,
  spendThresholdPct: 10,
  deferralDays: 7
};

const customers = {
  C100001: "ABC Industries",
  C100002: "Northwind Traders",
  C100003: "Contoso Retail",
  C100004: "Fabrikam Inc",
  C100005: "Globex Corp",
  C199999: "Other customers"
};

const suppliers = {
  V200001: "XYZ Components",
  V200002: "Acme Metals",
  V200003: "Beta Plastics",
  V200004: "Kappa Chemicals",
  V200005: "Sigma Spares",
  V200006: "Theta Freight",
  V200007: "Iota Packaging",
  V200008: "Lambda Energy",
  V200009: "Delta Chemicals",
  V200010: "Omega Logistics",
  V200011: "Epsilon Steel",
  V200012: "Zeta Services",
  V200013: "Eta Tooling",
  V299999: "Other suppliers"
};

// acct: D = customer, K = supplier. due / promised / cleared / discDate are day offsets.
function openItems() {
  const items = [
    // ---- receivables -----------------------------------------------------
    { id: "AR-ABC-0001", acct: "D", partner: "C100001", amount: 4.0 * M, due: -12, promised: 6 },
    { id: "AR-NWT-0001", acct: "D", partner: "C100002", amount: 2.0 * M, due: -5, promised: 14 },
    { id: "AR-CON-0001", acct: "D", partner: "C100003", amount: 1.5 * M, due: -3, promised: 10 },
    { id: "AR-FAB-0001", acct: "D", partner: "C100004", amount: 1.5 * M, due: -4, promised: 13 },
    { id: "AR-GLX-0001", acct: "D", partner: "C100005", amount: 2.5 * M, due: 9 }
  ];
  const various = [
    [1, 0.6], [2, 0.5], [3, 0.4], [6, 0.5], [7, 0.6], [8, 0.5], [9, 1.5], [10, 0.3],
    [13, 0.2], [14, 2.0], [15, 0.8], [16, 0.9], [17, 1.2], [20, 2.0], [21, 1.1],
    [22, 0.7], [23, 0.8], [24, 1.5], [27, 2.2], [28, 0.9], [29, 1.0], [30, 1.2]
  ];
  various.forEach(([d, a], i) => items.push({
    id: `AR-OTH-${String(i + 1).padStart(4, "0")}`, acct: "D", partner: "C199999",
    amount: Math.round(a * M), due: d
  }));

  // ---- payables in this week's run (Thursday, anchor + 2) ----------------
  items.push(
    { id: "AP-XYZ-0001", acct: "K", partner: "V200001", amount: 3.0 * M, due: 5 },
    { id: "AP-ACM-0001", acct: "K", partner: "V200002", amount: 0.9 * M, due: 3, block: "R", blockReason: "Price variance" },
    { id: "AP-BTP-0001", acct: "K", partner: "V200003", amount: 0.6 * M, due: 4, block: "R", blockReason: "Price variance" }
  );
  for (let i = 1; i <= 177; i++) {
    items.push({
      id: `AP-RUN-${String(i).padStart(4, "0")}`, acct: "K",
      partner: `V21${String((i % 44) + 1).padStart(4, "0")}`,
      amount: i === 177 ? 42880 : 42370,
      due: i % 10
    });
  }

  // ---- payables in later runs ------------------------------------------
  items.push(
    { id: "AP-RAW-0001", acct: "K", partner: "V200004", amount: 6.0 * M, due: 12, po: "4500001001", plant: "1000", text: "Raw material - resin for Line 2" },
    { id: "AP-SPR-0001", acct: "K", partner: "V200005", amount: 2.0 * M, due: 15, po: "4500001002", plant: "1000", text: "Spare-part restock" },
    { id: "AP-THF-0001", acct: "K", partner: "V200006", amount: 2.0 * M, due: 17 },
    { id: "AP-IOP-0001", acct: "K", partner: "V200007", amount: 1.5 * M, due: 20 },
    { id: "AP-LAE-0001", acct: "K", partner: "V200008", amount: 1.0 * M, due: 22 },
    { id: "AP-DLT-0001", acct: "K", partner: "V200009", amount: 1.0 * M, due: 28, discPct: 2, discDate: 8, text: "Terms 2/10 net 30" },
    { id: "AP-EPS-0001", acct: "K", partner: "V200011", amount: 2.5 * M, due: 25 },
    { id: "AP-ZET-0001", acct: "K", partner: "V200012", amount: 1.5 * M, due: 29 },
    { id: "AP-ETA-0001", acct: "K", partner: "V200013", amount: 2.0 * M, due: 31 },
    { id: "AP-ETA-0002", acct: "K", partner: "V200013", amount: 2.0 * M, due: 35 },
    // held on purpose (dispute) -> overdue, not in any run
    { id: "AP-OMG-0001", acct: "K", partner: "V200010", amount: 1.9 * M, due: -20, block: "A", blockReason: "Dispute - held" }
  );

  // ---- balancing rows beyond the horizon so totals match the base data ----
  const sum = (acct) => items.filter((x) => x.acct === acct).reduce((s, x) => s + x.amount, 0);
  items.push({ id: "AR-OTH-9999", acct: "D", partner: "C199999", amount: 85 * M - sum("D"), due: 45 });
  items.push({ id: "AP-OTH-9999", acct: "K", partner: "V299999", amount: 100 * M - sum("K"), due: 60 });
  return items;
}

// Cleared history: [partner, acct, amount, due offset, days late]
function history() {
  const rows = [];
  const add = (partner, acct, amounts, lates) => amounts.forEach((a, i) =>
    rows.push({ partner, acct, amount: Math.round(a * M), due: -200 + i * 22, daysLate: lates[i] }));
  add("C100001", "D", [1.0, 2.0, 1.5, 3.0, 2.5, 1.2, 2.2, 1.8], [12, 0, 8, 10, 0, 7, 9, 8]);
  add("C100002", "D", [1, 1, 1, 1, 1, 1, 1, 1], [0, 0, 5, 0, 0, 18, 0, 0]);
  add("C100003", "D", [1, 1, 1, 1, 1], [0, 0, 4, 0, 0]);
  add("C100004", "D", [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], [0, 3, 0, 0, 6, 0, 0, 2, 0, 0]);
  add("C100005", "D", [2, 2, 2, 2, 2, 2, 2, 2, 2, 2], [0, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
  add("C199999", "D", Array(20).fill(0.5), [0, 0, 2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0]);
  add("V200001", "K", [0.2, 0.3, 0.4, 0.5, 0.6, 0.4], [0, 0, 0, 0, 0, 0]);
  add("V200004", "K", [5.5, 6.0, 6.5, 6.0, 5.8, 6.2], [0, 0, 0, 0, 0, 0]);
  add("V200005", "K", [1.8, 2.2, 2.0, 1.9, 2.1, 2.0], [0, 0, 0, 0, 0, 0]);
  return rows;
}

// Planned non-AR/AP flows (payroll, tax, fees): [day, amount]
const plannedFlows = [
  [1, -0.6], [2, -0.5], [3, -0.6], [6, -0.8], [7, -0.6], [8, -0.5], [10, -0.3],
  [13, -0.5], [14, -0.2], [15, -0.4], [17, -0.4], [20, -0.6], [21, -0.5],
  [22, -0.3], [24, -0.4], [27, -0.6], [28, -1.0], [29, -0.3]
].map(([day, a]) => ({ day, amount: Math.round(a * M), description: "Payroll / tax / fees" }));

// PO spend by plant: window 0 = last 30 days, 1..3 = the three before
const spend = [
  { plant: "1000", window: 0, amount: 13.1 * M }, { plant: "1000", window: 1, amount: 11.4 * M },
  { plant: "1000", window: 2, amount: 10.8 * M }, { plant: "1000", window: 3, amount: 11.1 * M },
  { plant: "2000", window: 0, amount: 6.2 * M }, { plant: "2000", window: 1, amount: 6.0 * M },
  { plant: "2000", window: 2, amount: 6.3 * M }, { plant: "2000", window: 3, amount: 6.3 * M }
];

// ZTCFO_CRIT
const criticality = [
  { objectType: "PO", objectId: "4500001001", level: "H", prodLine: "LINE 2", revenueAtRisk: 30 * M, note: "Feeds Line 2 - non-payment risks a production stop" },
  { objectType: "PO", objectId: "4500001002", level: "L", prodLine: "", revenueAtRisk: 0, note: "Routine restock; a few days late costs a small fee" }
];

const openingCash = 22 * M;
const previousKpi = { arOverdue: 8040000, apOverdue: 2000000 };

module.exports = {
  M, config, customers, suppliers, openItems, history, plannedFlows, spend,
  criticality, openingCash, previousKpi, anchor: "2026-08-04"
};

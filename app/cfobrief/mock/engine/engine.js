/*
 * Reference implementation of the CFO brief engine (E-P-R-A-D, rule path).
 *
 * The ABAP classes ZCL_CFO_RUNWAY, ZCL_CFO_PAYDATE_PREDICTOR, ZCL_CFO_VARIANCE,
 * ZCL_CFO_RISK_RANKER, ZCL_CFO_TRADEOFF and ZCL_CFO_DRAFTER follow the same
 * rules. The mock server uses this file, and test/engine.test.js pins the
 * slide numbers, so a change to a rule has to be made in both places.
 */
"use strict";

const S = require("./scenario");

// ---------------------------------------------------------------- dates ----
const DAY = 86400000;
const toDate = (iso) => new Date(iso + "T00:00:00Z");
const iso = (d) => d.toISOString().slice(0, 10);
const addDays = (d, n) => new Date(d.getTime() + n * DAY);
const diffDays = (a, b) => Math.round((a.getTime() - b.getTime()) / DAY);
const isoWeekday = (d) => ((d.getUTCDay() + 6) % 7) + 1; // 1 = Mon ... 7 = Sun
const isWeekend = (d) => isoWeekday(d) >= 6;
const nextBd = (d) => { let x = d; while (isWeekend(x)) x = addDays(x, 1); return x; };
function addBd(d, n) {
  let x = d;
  const step = n < 0 ? -1 : 1;
  for (let i = 0; i < Math.abs(n); i++) {
    do { x = addDays(x, step); } while (isWeekend(x));
  }
  return x;
}
const WD = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const MO = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const fmtDate = (d) => `${WD[isoWeekday(d) - 1]} ${d.getUTCDate()} ${MO[d.getUTCMonth()]}`;

// --------------------------------------------------------------- format ----
const round = (x, n) => Math.round(x * 10 ** n) / 10 ** n;
function fmtMoney(x) {
  const a = Math.abs(x);
  const sign = x < 0 ? "-" : "";
  if (a >= 1e5) return `${sign}$${(a / 1e6).toFixed(1)}M`;
  return `${sign}$${Math.round(a).toLocaleString("en-US")}`;
}
const WORDS = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"];
const poss = (name) => (name.endsWith("s") ? `${name}'` : `${name}'s`);
const countWord = (n) => (n <= 10 ? WORDS[n] : String(n));

// ---------------------------------------------------------------- input ----
function demoInput(anchorIso = S.anchor) {
  const k = toDate(anchorIso);
  const at = (off) => (off === undefined || off === null ? null : addDays(k, off));
  const names = { ...S.customers, ...S.suppliers };
  const nameOf = (p) => names[p] || (p.startsWith("V21") ? `Supplier ${p}` : p);
  return {
    keyDate: k,
    config: S.config,
    openingCash: S.openingCash,
    previous: S.previousKpi,
    items: S.openItems().map((x) => ({
      ...x, partnerName: nameOf(x.partner), dueDate: at(x.due), promisedDate: at(x.promised),
      discDate: at(x.discDate)
    })),
    history: S.history(),
    planned: S.plannedFlows.map((p) => ({ ...p, date: at(p.day) })),
    spend: S.spend,
    criticality: S.criticality
  };
}

// ------------------------------------------------------------ P: predict ---
function paymentBehaviour(history, cfg) {
  const by = {};
  const all = { n: 0, late: 0, lateDays: 0 };
  for (const h of history.filter((r) => r.acct === "D")) {
    const s = (by[h.partner] = by[h.partner] || { n: 0, late: 0, lateDays: 0 });
    for (const t of [s, all]) {
      t.n += 1;
      if (h.daysLate > 0) { t.late += 1; t.lateDays += h.daysLate; }
    }
  }
  const stat = (s) => ({
    n: s.n,
    pLate: s.n ? round(s.late / s.n, 2) : 0,
    meanLate: s.late ? Math.ceil(s.lateDays / s.late) : 0
  });
  const portfolio = stat(all);
  return (partner) => {
    const s = by[partner];
    return s && s.n >= cfg.minHistory ? stat(s) : { ...portfolio, n: s ? s.n : 0, fallback: true };
  };
}

function supplierPattern(history, cfg) {
  const by = {};
  for (const h of history.filter((r) => r.acct === "K")) (by[h.partner] = by[h.partner] || []).push(h.amount);
  return (partner, amount) => {
    const v = by[partner];
    if (!v || v.length < cfg.minHistory) return null;
    const mean = v.reduce((a, b) => a + b, 0) / v.length;
    const sd = Math.sqrt(v.reduce((a, b) => a + (b - mean) ** 2, 0) / (v.length - 1));
    if (sd === 0) return null;
    return { mean, sd, z: (amount - mean) / sd };
  };
}

function runDates(k, cfg) {
  let r0 = k;
  while (isoWeekday(r0) !== cfg.runWeekday) r0 = addDays(r0, 1);
  const runs = [];
  for (let r = r0; diffDays(r, k) <= cfg.horizonDays + 60; r = addDays(r, 7)) runs.push(r);
  return runs;
}

/**
 * Turns open items into dated cash flows.
 * sim: { lateIds:[], heldIds:[], factorIds:[], runDelayDays, floorOverride }
 */
function cashFlows(input, sim = {}) {
  const { keyDate: k, config: cfg } = input;
  const behaviour = paymentBehaviour(input.history, cfg);
  const runs = runDates(k, cfg);
  const flows = [];
  const lateIds = new Set(sim.lateIds || []);
  const heldIds = new Set(sim.heldIds || []);
  const factorIds = new Set(sim.factorIds || []);
  const runDelay = sim.runDelayDays || 0;

  for (const it of input.items) {
    if (it.acct === "D") {
      const b = behaviour(it.partner);
      let sched = it.promisedDate
        ? it.promisedDate
        : diffDays(it.dueDate, k) >= 0 ? nextBd(it.dueDate) : addBd(k, cfg.collectionLagBd);
      const forcedLate = lateIds.has(it.id);
      const shiftDays = Math.max(b.meanLate, forcedLate ? 1 : 0);
      const stressed = b.pLate >= cfg.stressThreshold || forcedLate;
      let stress = stressed ? nextBd(addDays(sched, shiftDays)) : sched;
      if (forcedLate) sched = stress;
      if (factorIds.has(it.id)) {
        const funds = addBd(k, cfg.factoringLeadBd);
        const adv = round(it.amount * cfg.factoringAdvancePct / 100, 2);
        flows.push({ ...it, kind: "FAC", amount: adv, sched: funds, stress: funds, pLate: 0, stressed: false });
        continue;
      }
      flows.push({ ...it, kind: "AR", sched, stress, pLate: b.pLate, meanLate: b.meanLate, stressed, history: b });
    } else {
      if (it.block && it.block !== "R") {
        flows.push({ ...it, kind: "AP", held: true, sched: null, stress: null });
        continue;
      }
      let idx = runs.findIndex((r) => diffDays(addDays(r, 7), it.dueDate) >= 0);
      if (heldIds.has(it.id) && idx >= 0) idx += 1;
      let pay = idx >= 0 ? runs[idx] : null;
      const inCurrentRun = idx === 0;
      if (pay && inCurrentRun && runDelay) pay = nextBd(addDays(pay, runDelay));
      flows.push({ ...it, kind: "AP", amount: -it.amount, sched: pay, stress: pay, runDate: runs[idx] || null, inCurrentRun });
    }
  }
  for (const p of input.planned) flows.push({ id: `PLAN-${p.day}`, kind: "OTH", amount: p.amount, sched: p.date, stress: p.date, description: p.description });
  return { flows, runs, behaviour };
}

function runway(input, flows, floor) {
  const { keyDate: k, config: cfg } = input;
  const days = [];
  let cs = input.openingCash, cx = input.openingCash, ce = input.openingCash;
  for (let d = 0; d <= cfg.horizonDays; d++) {
    const date = addDays(k, d);
    let inflow = 0, outflow = 0, netStress = 0, netExp = 0;
    for (const f of flows) {
      if (!f.sched) continue;
      if (diffDays(f.sched, date) === 0) {
        if (f.amount >= 0) inflow += f.amount; else outflow += f.amount;
        netExp += f.stressed ? f.amount * (1 - f.pLate) : f.amount;
      }
      if (diffDays(f.stress, date) === 0) {
        netStress += f.amount;
        if (f.stressed) netExp += f.amount * f.pLate;
      }
    }
    cs += inflow + outflow; cx += netStress; ce += netExp;
    days.push({
      DayIndex: d, CalendarDate: iso(date), Inflow: round(inflow, 2), Outflow: round(outflow, 2),
      ClosingScheduled: round(cs, 2), ClosingStressed: round(cx, 2), ClosingExpected: round(ce, 2),
      FloorAmount: floor, FloorDelta: round(cs - floor, 2), IsWeekend: isWeekend(date), IsRunDay: false, IsLowPoint: false
    });
  }
  return days;
}

const lowOf = (days, key, from = 0, to = Infinity) => days
  .filter((d) => d.DayIndex >= from && d.DayIndex <= to)
  .reduce((m, d) => (d[key] < m[key] ? d : m));

// --------------------------------------------------------------- build ----
function build(input, sim = {}) {
  const { keyDate: k, config: cfg } = input;
  const floor = sim.floorOverride || cfg.floor;
  const { flows, runs } = cashFlows(input, sim);
  const days = runway(input, flows, floor);
  const off = (d) => diffDays(d, k);

  const r0 = runs[0], r1 = runs[1];
  days.forEach((d) => { d.IsRunDay = runs.some((r) => off(r) === d.DayIndex); });
  const low = lowOf(days, "ClosingScheduled");
  const lowStress = lowOf(days, "ClosingStressed");
  low.IsLowPoint = true;
  const lowDate = addDays(k, low.DayIndex);

  const ap = flows.filter((f) => f.kind === "AP");
  const ar = flows.filter((f) => f.kind === "AR");
  const runItems = ap.filter((f) => f.inCurrentRun);
  const runTotal = -runItems.reduce((s, f) => s + f.amount, 0);
  const runHolds = lowOf(days, "ClosingScheduled", off(r0), off(r1) - 1).ClosingScheduled >= floor;
  const byItem = input.items;
  const sum = (arr) => arr.reduce((s, x) => s + x.amount, 0);
  const arTotal = sum(byItem.filter((x) => x.acct === "D"));
  const apTotal = sum(byItem.filter((x) => x.acct === "K"));
  const arOverdueItems = byItem.filter((x) => x.acct === "D" && off(x.dueDate) < 0);
  const apOverdueItems = byItem.filter((x) => x.acct === "K" && off(x.dueDate) < 0);
  const arOverdue = sum(arOverdueItems);
  const apOverdue = sum(apOverdueItems);
  const apDueWindow = sum(byItem.filter((x) => x.acct === "K" && off(x.dueDate) >= 0 &&
    off(x.dueDate) <= cfg.apWindowDays && (!x.block || x.block === "R")));
  const pct = (now, prev) => (prev ? round((now - prev) / prev * 100, 1) : 0);

  // ---------------------------------------------------------- E: explain --
  const topOverdue = [...arOverdueItems].sort((a, b) => b.amount - a.amount)[0];
  const heldShare = apOverdue ? sum(apOverdueItems.filter((x) => x.block && x.block !== "R")) / apOverdue : 0;
  const explains = [];
  const arChg = pct(arOverdue, input.previous.arOverdue);
  const apChg = pct(apOverdue, input.previous.apOverdue);
  explains.push({
    code: "AR_OVERDUE", changePct: arChg,
    text: `AR overdue ${arChg >= 0 ? "up" : "down"} ${Math.abs(arChg).toFixed(1)}%` +
      (topOverdue ? `, mostly ${topOverdue.partnerName} (${fmtMoney(topOverdue.amount)})` : "")
  });
  explains.push({
    code: "AP_OVERDUE", changePct: apChg,
    text: `AP overdue ${apChg >= 0 ? "up" : "down"} ${Math.abs(apChg).toFixed(1)}%` +
      (heldShare >= 0.5 ? " (held deliberately)" : "")
  });

  // ------------------------------------------------------------- R: rank --
  const risks = [];
  const fundsBy = addBd(lowDate, -cfg.factoringLeadBd);
  const decideBy = off(fundsBy) >= 0 ? fundsBy : k;
  for (const f of ar.filter((x) => x.stressed && x.sched && off(x.sched) <= cfg.horizonDays)) {
    const weight = low.ClosingScheduled - f.amount < floor ? 2 : 1;
    risks.push({
      RiskType: "AR_LATE", Epard: "PR", Reference: f.id, PartnerName: f.partnerName,
      Exposure: f.amount, Probability: f.pLate, FloorWeight: weight,
      Title: `${f.partnerName} ${fmtMoney(f.amount)} likely to pay late` +
        (weight === 2 ? " — would drop below floor" : ""),
      Detail: `Paid late in ${Math.round(f.pLate * f.history.n)} of ${f.history.n} past invoices, ` +
        `${f.meanLate} days on average. Late → ${fmtMoney(f.amount)} arrives ${fmtDate(f.stress)} instead of ${fmtDate(f.sched)}.`,
      Recommendation: "CHASE_OR_FACTOR",
      RecommendationText: `Decide by ${fmtDate(decideBy)}: chase or factor (funds ~${cfg.factoringLeadBd} days, before Day ${low.DayIndex}).`,
      DueBy: iso(decideBy)
    });
  }
  const pattern = supplierPattern(input.history, cfg);
  const proposalDate = addBd(r0, -cfg.proposalLeadBd);
  for (const f of runItems) {
    const p = pattern(f.partner, -f.amount);
    if (p && p.z >= cfg.zScoreThreshold) {
      const prob = round(p.z / (p.z + cfg.zScoreThreshold), 2);
      risks.push({
        RiskType: "AP_OFFPATTERN", Epard: "ER", Reference: f.id, PartnerName: f.partnerName,
        Exposure: -f.amount, Probability: prob, FloorWeight: 1,
        Title: `${f.partnerName} ${fmtMoney(-f.amount)} — off-pattern (large for this vendor)`,
        Detail: `Typical invoice ${fmtMoney(p.mean)}; this one is ${p.z.toFixed(1)} standard deviations above.`,
        Recommendation: "VERIFY_BEFORE_RELEASE",
        RecommendationText: "Verify before release.",
        DueBy: iso(proposalDate)
      });
    }
  }
  const blocked = runItems.filter((f) => f.block === "R");
  if (blocked.length) {
    const amt = -sum(blocked);
    risks.push({
      RiskType: "AP_BLOCKED", Epard: "ER", Reference: blocked.map((b) => b.id).join(","),
      PartnerName: blocked.map((b) => b.partnerName).join(", "),
      Exposure: amt, Probability: 1, FloorWeight: 0.5,
      Title: `${blocked.length} invoice${blocked.length > 1 ? "s" : ""} blocked (price variance) ${fmtMoney(amt)}`,
      Detail: "Blocked for payment in invoice verification.",
      Recommendation: "CLEAR_OR_DROP",
      RecommendationText: "Clear, or they drop from the run.",
      DueBy: iso(proposalDate)
    });
  }
  const plants = [...new Set(input.spend.map((s) => s.plant))];
  for (const plant of plants) {
    const rows = input.spend.filter((s) => s.plant === plant);
    const cur = rows.find((s) => s.window === 0)?.amount || 0;
    const prior = rows.filter((s) => s.window > 0);
    if (!prior.length) continue;
    const avg = sum(prior) / prior.length;
    const chg = round((cur - avg) / avg * 100, 1);
    if (chg >= cfg.spendThresholdPct) {
      const delta = round(cur - avg, 2);
      explains.push({ code: "SPEND", changePct: chg, text: `Plant ${plant} spend up ${chg.toFixed(1)}% (${fmtMoney(delta)})` });
      risks.push({
        RiskType: "SPEND_SPIKE", Epard: "ER", Reference: `PLANT-${plant}`, PartnerName: `Plant ${plant}`,
        Exposure: delta, Probability: 0.5, FloorWeight: 1,
        Title: `Plant ${plant} spend up ${chg.toFixed(1)}% (${fmtMoney(delta)}) — check if real demand`,
        Detail: `Last 30 days ${fmtMoney(cur)} vs ${fmtMoney(avg)} average of the three windows before.`,
        Recommendation: "REVIEW_DEMAND", RecommendationText: "Check if real demand.", DueBy: null
      });
    }
  }
  risks.forEach((r) => { r.Score = round(r.Exposure * r.Probability * r.FloorWeight, 2); });
  risks.sort((a, b) => b.Score - a.Score);
  risks.forEach((r, i) => {
    r.RiskRank = i + 1;
    r.Criticality = r.FloorWeight >= 2 ? 1 : r.Score >= 1e6 ? 2 : 3;
    r.Status = "OPEN";
  });

  // ----------------------------------------------------------- A: advise --
  const crit = (f) => input.criticality.find((c) => c.objectType === "PO" && c.objectId === f.po);
  const tradeoffs = [];
  const shortfall = floor - lowStress.ClosingStressed;
  const factorable = risks.find((r) => r.RiskType === "AR_LATE");
  if (shortfall > 0) {
    const lowStressDate = addDays(k, lowStress.DayIndex);
    const run = [...runs].reverse().find((r) => off(r) <= off(lowStressDate));
    const inRun = ap.filter((f) => f.runDate && off(f.runDate) === off(run));
    const scored = inRun.map((f) => {
      const c = crit(f);
      const amount = -f.amount;
      const fee = round(amount * cfg.lateFeeRatePct / 100 * cfg.deferralDays / 365, 2);
      const op = !c ? 0 : c.level === "H" ? c.revenueAtRisk : c.level === "M" ? c.revenueAtRisk * 0.1 : 0;
      return { f, c, amount, fee, cost: fee + op };
    });
    const deferrable = scored.filter((s) => !s.c || s.c.level !== "H").sort((a, b) => a.cost / a.amount - b.cost / b.amount)[0];
    const protectedItem = scored.filter((s) => s.c && s.c.level === "H").sort((a, b) => b.c.revenueAtRisk - a.c.revenueAtRisk)[0];
    if (deferrable) {
      const after = Math.max(0, round(shortfall - deferrable.amount, 2));
      const confidence = deferrable.c && protectedItem ? "HIGH" : "LOW";
      tradeoffs.push({
        Kind: "DEFER", Epard: "A",
        Title: "Trade-off: which do I pay?",
        Question: `The ${fmtDate(run)} run would breach the floor if ${factorable ? factorable.PartnerName : "the at-risk receipt"} pays late — which item do you defer?`,
        DeferItem: deferrable.f.id, DeferName: `${deferrable.f.text || deferrable.f.partnerName}`, DeferPartner: deferrable.f.partnerName, DeferAmount: deferrable.amount,
        DeferNote: deferrable.c ? deferrable.c.note : "No criticality recorded",
        PayItem: protectedItem ? protectedItem.f.id : "", PayName: protectedItem ? protectedItem.f.text || protectedItem.f.partnerName : "",
        PayPartner: protectedItem ? protectedItem.f.partnerName : "",
        PayAmount: protectedItem ? protectedItem.amount : 0,
        PayNote: protectedItem ? `${protectedItem.c.note}; ${fmtMoney(protectedItem.c.revenueAtRisk)} of orders this quarter on ${protectedItem.c.prodLine}` : "",
        DeferCost: deferrable.fee, ShortfallBefore: round(shortfall, 2), ShortfallAfter: after,
        Recommendation: protectedItem
          ? `Pay ${(protectedItem.f.text || "").toLowerCase().includes("raw") ? "raw material" : protectedItem.f.partnerName}. A small late fee (${fmtMoney(deferrable.fee)}) ≪ a stopped production line.`
          : `Defer ${deferrable.f.partnerName}.`,
        Detail: after > 0 && factorable
          ? `Deferring cuts the shortfall from ${fmtMoney(shortfall)} to ${fmtMoney(after)}; factoring ${factorable.PartnerName} (${fmtMoney(factorable.Exposure * cfg.factoringAdvancePct / 100)}) closes the rest.`
          : `Deferring cuts the shortfall from ${fmtMoney(shortfall)} to ${fmtMoney(after)}.`,
        Caveat: "Exception: if the spare part runs the machine making that product — pay it.",
        Confidence: confidence,
        ConfidenceNote: confidence === "HIGH"
          ? "Based on recorded PP/MM criticality."
          : "Reliable only with PP schedule + MM criticality — AI flags it, you decide.",
        Amount: deferrable.amount, Income: 0, AnnualizedPct: 0, Status: "READY", ActionDate: iso(run)
      });
    }
  }

  for (const f of ap.filter((x) => !x.inCurrentRun && x.runDate && x.dueDate && off(x.dueDate) <= cfg.apWindowDays)) {
    const c = crit(f);
    if (!c || c.level !== "H") continue;
    const deadline = addBd(addBd(f.runDate, -cfg.proposalLeadBd), -cfg.approvalLeadBd);
    tradeoffs.push({
      Kind: "PRIORITIZE", Epard: "A",
      Title: `${f.text || f.partnerName} ${fmtMoney(-f.amount)} (due Day ${off(f.dueDate)})`,
      Question: "Part of AP due, not scheduled yet.",
      PayItem: f.id, PayName: f.partnerName, PayPartner: f.partnerName, PayAmount: -f.amount,
      Recommendation: `Approve for next run by ${fmtDate(deadline)} (${cfg.approvalLeadBd}-day lead) to protect ${c.prodLine}.`,
      Detail: `Next run ${fmtDate(f.runDate)}; proposal is built ${fmtDate(addBd(f.runDate, -cfg.proposalLeadBd))}.`,
      Amount: -f.amount, Income: 0, AnnualizedPct: 0, Confidence: "HIGH", Status: "READY", ActionDate: iso(deadline)
    });
  }

  const depStart = nextBd(addDays(lowDate, 1));
  const s0 = off(depStart), s1 = s0 + cfg.depositDays - 1;
  if (s1 <= cfg.horizonDays) {
    const freeSched = lowOf(days, "ClosingScheduled", s0, s1).ClosingScheduled - floor;
    const freeStress = lowOf(days, "ClosingStressed", s0, s1).ClosingStressed - floor;
    const amount = Math.floor(freeSched / 500000) * 500000;
    if (amount > 0) {
      const income = round(amount * cfg.depositRatePct / 100 * cfg.depositDays / 365, 2);
      const held = freeStress < amount;
      tradeoffs.push({
        Kind: "DEPOSIT", Epard: "A",
        Title: "Opportunity: idle cash to work",
        Question: held && factorable
          ? `This week is tight — but if ${poss(factorable.PartnerName)} ${fmtMoney(factorable.Exposure)} lands on time, a surplus opens.`
          : "A surplus opens after the low point.",
        Recommendation: `${held && factorable ? `If ${factorable.PartnerName} pays: place` : "Place"} ~${fmtMoney(amount)} · ${cfg.depositDays}-day deposit @ ${cfg.depositRatePct}% p.a. from ${fmtDate(depStart)}`,
        Detail: held
          ? `Potential income — held pending ${factorable ? factorable.PartnerName : "the at-risk receipt"}; revisit once it clears.`
          : "Potential income — ready to place.",
        Caveat: `Only lock cash the forecast shows as free after the Day ${low.DayIndex} low-point.`,
        Amount: amount, Income: income, AnnualizedPct: cfg.depositRatePct,
        Confidence: held ? "LOW" : "HIGH", Status: held ? "HELD" : "READY", ActionDate: iso(depStart)
      });
    }
  }

  for (const f of ap.filter((x) => x.discPct && x.discDate && off(x.discDate) >= 0)) {
    const amount = -f.amount;
    const termDays = diffDays(f.dueDate, f.discDate);
    const annual = round(f.discPct / (100 - f.discPct) * 365 / termDays * 100, 1);
    const payFrom = off(f.discDate), payTo = off(f.sched) - 1;
    const okSched = lowOf(days, "ClosingScheduled", payFrom, payTo).ClosingScheduled - amount >= floor;
    const okStress = lowOf(days, "ClosingStressed", payFrom, payTo).ClosingStressed - amount >= floor;
    tradeoffs.push({
      Kind: "EARLYPAY", Epard: "A",
      Title: `Early-payment discount: ${f.partnerName} ${fmtMoney(amount)}`,
      Question: `${f.discPct}% if paid by ${fmtDate(f.discDate)}, net ${fmtDate(f.dueDate)}.`,
      PayItem: f.id, PayName: f.partnerName, PayPartner: f.partnerName, PayAmount: amount,
      Recommendation: `Or capture the early-payment discount when cash allows → ≈ ${annual}% p.a., ${annual > cfg.depositRatePct ? "beats" : "does not beat"} a ${cfg.depositRatePct}% deposit.`,
      Detail: okStress ? "Affordable even if the at-risk receipt is late." : okSched ? "Affordable only if the at-risk receipt lands on time." : "Not affordable before the low point.",
      Amount: amount, Income: round(amount * f.discPct / 100, 2), AnnualizedPct: annual,
      Confidence: okStress ? "HIGH" : "LOW", Status: okStress ? "READY" : okSched ? "HELD" : "BLOCKED", ActionDate: iso(f.discDate)
    });
  }

  tradeoffs.forEach((t, i) => { t.Seq = i + 1; });

  // --------------------------------------------------------- headline -----
  const reviewCount = risks.filter((r) => r.RiskType === "AP_OFFPATTERN" || r.RiskType === "AP_BLOCKED").length +
    tradeoffs.filter((t) => t.Kind === "PRIORITIZE").length;
  const headline = `This week's run ${runHolds ? "holds above" : "breaches the"} floor — ${reviewCount} item${reviewCount === 1 ? "" : "s"} to review`;
  const lead = factorable;
  const narrative =
    `This week's proposal (${fmtMoney(runTotal)}) is built and ${runHolds ? "clears" : "breaks"} the floor — ` +
    `${countWord(reviewCount)} item${reviewCount === 1 ? " needs" : "s need"} you; the rest flows through. ` +
    `Cash ${fmtMoney(input.openingCash)} today → ${fmtMoney(days[off(r0)].ClosingScheduled)} after ${fmtDate(r0)}'s run. ` +
    `Low point ${fmtMoney(low.ClosingScheduled)} on Day ${low.DayIndex} (floor ${fmtMoney(floor)})` +
    (lead ? `. If ${poss(lead.PartnerName)} ${fmtMoney(lead.Exposure)} pays late (~${Math.round(lead.Probability * 100)}%) → ${fmtMoney(lowStress.ClosingStressed)}${lowStress.ClosingStressed < floor ? " — below floor" : ""}.` : ".");

  const brief = {
    CompanyCode: cfg.companyCode, BriefDate: iso(k), Currency: cfg.currency,
    CashToday: input.openingCash, LiquidityFloor: floor,
    RunDate: iso(r0), RunTotal: round(runTotal, 2), RunInvoiceCount: runItems.length,
    RunVendorCount: new Set(runItems.map((f) => f.partner)).size,
    CashAfterRun: days[off(r0)].ClosingScheduled, RunHoldsFloor: runHolds,
    NextRunDate: iso(r1),
    LowPoint: low.ClosingScheduled, LowPointDay: low.DayIndex, LowPointDate: iso(lowDate),
    StressedLowPoint: lowStress.ClosingStressed, StressedLowDay: lowStress.DayIndex,
    Headroom: round(low.ClosingScheduled - floor, 2),
    FloorBreach: lowStress.ClosingStressed < floor, ScheduledBreach: low.ClosingScheduled < floor,
    ArTotal: arTotal, ArOverdue: arOverdue, ArOverdueChangePct: arChg,
    ApTotal: apTotal, ApDueWindow: apDueWindow, ApOverdue: apOverdue, ApOverdueChangePct: apChg,
    ReviewCount: reviewCount,
    Headline: headline,
    Narrative: narrative,
    ExplainText: explains.map((e) => e.text).join("\n"),
    Engine: "RULE", ModelUsed: "", ErrorText: "",
    HorizonDays: cfg.horizonDays, DataMode: "DEMO"
  };
  return { brief, days, risks, tradeoffs, explains, flows, runs };
}

// ------------------------------------------------------------ D: draft ----
function draft(kind, ctx) {
  const { brief } = ctx;
  const d = (s) => fmtDate(toDate(s));
  switch (kind) {
    case "COLLECTION_NOTICE": {
      const r = ctx.risk;
      return {
        ActionType: kind, Recipient: `Chief Financial Officer, ${r.PartnerName}`,
        Subject: `${r.PartnerName} — overdue balance ${fmtMoney(r.Exposure)}`,
        Body:
          `Dear CFO,\n\nOur records show ${fmtMoney(r.Exposure)} (reference ${r.Reference}) is past its due date. ` +
          `We value the relationship and would like to settle this without escalation.\n\n` +
          `Please confirm the payment date by ${d(r.DueBy)}, or let us know of anything that is holding the payment so we can resolve it together.\n\n` +
          `Kind regards,\nChief Financial Officer`,
        InternalNote: `Decide by ${d(r.DueBy)}: chase or factor. Do not mention factoring to the customer.`,
        Amount: r.Exposure
      };
    }
    case "RUN_EXCEPTIONS": {
      const ex = ctx.risks.filter((x) => x.RiskType === "AP_OFFPATTERN" || x.RiskType === "AP_BLOCKED");
      const exAmt = ex.reduce((s, x) => s + x.Exposure, 0);
      const lines = ex.map((x, i) => `${i + 1}. ${x.Title} — ${x.RecommendationText}`).join("\n");
      return {
        ActionType: kind, Recipient: "Payment run owner (Accounts Payable)",
        Subject: `Payment run ${d(brief.RunDate)} — ${ex.length} exception${ex.length === 1 ? "" : "s"} before release`,
        Body:
          `The proposal (${fmtMoney(brief.RunTotal)}, ${brief.RunInvoiceCount} invoices / ${brief.RunVendorCount} vendors) clears the floor.\n\n` +
          `Please resolve before the proposal is released:\n${lines}\n\n` +
          `Release the remaining ${fmtMoney(brief.RunTotal - exAmt)} as proposed.`,
        InternalNote: "Exception list only — the payment run itself is not changed by this app.",
        Amount: exAmt
      };
    }
    case "DEFER":
      return {
        ActionType: kind, Recipient: "Treasury / AP lead",
        Subject: `Run ${d(ctx.tradeoff.ActionDate)}: pay ${ctx.tradeoff.PayName}, defer ${ctx.tradeoff.DeferName}`,
        Body:
          `If the at-risk receipt is late, the ${d(ctx.tradeoff.ActionDate)} run breaches the floor by ${fmtMoney(ctx.tradeoff.ShortfallBefore)}.\n\n` +
          `Please approve: pay ${ctx.tradeoff.PayName} (${fmtMoney(ctx.tradeoff.PayAmount)}); defer ${ctx.tradeoff.DeferName} (${fmtMoney(ctx.tradeoff.DeferAmount)}) by ${ctx.config.deferralDays} days ` +
          `(estimated fee ${fmtMoney(ctx.tradeoff.DeferCost)}).\n\n${ctx.tradeoff.Detail}\n${ctx.tradeoff.Caveat}`,
        InternalNote: ctx.tradeoff.ConfidenceNote, Amount: ctx.tradeoff.DeferAmount
      };
    case "PRIORITIZE":
      return {
        ActionType: kind, Recipient: "AP lead",
        Subject: `Approve ${ctx.tradeoff.PayName} ${fmtMoney(ctx.tradeoff.PayAmount)} for the next run`,
        Body: `${ctx.tradeoff.Title}.\n\n${ctx.tradeoff.Recommendation}\n${ctx.tradeoff.Detail}`,
        InternalNote: "", Amount: ctx.tradeoff.PayAmount
      };
    case "DEPOSIT":
      return {
        ActionType: kind, Recipient: "Group Treasury",
        Subject: `Deposit proposal ${fmtMoney(ctx.tradeoff.Amount)} · ${ctx.config.depositDays} days @ ${ctx.config.depositRatePct}%`,
        Body: `${ctx.tradeoff.Recommendation} ≈ ${fmtMoney(ctx.tradeoff.Income)} income.\n\n${ctx.tradeoff.Detail}\n${ctx.tradeoff.Caveat}`,
        InternalNote: ctx.tradeoff.Status === "HELD" ? "Held — do not place until the at-risk receipt clears." : "",
        Amount: ctx.tradeoff.Amount
      };
    case "EARLYPAY":
      return {
        ActionType: kind, Recipient: "AP lead",
        Subject: `Early-payment discount — ${ctx.tradeoff.PayName} ${fmtMoney(ctx.tradeoff.PayAmount)}`,
        Body: `${ctx.tradeoff.Question}\n${ctx.tradeoff.Recommendation}\nSaving ${fmtMoney(ctx.tradeoff.Income)}. ${ctx.tradeoff.Detail}`,
        InternalNote: "", Amount: ctx.tradeoff.PayAmount
      };
    default:
      throw new Error(`Unknown draft kind ${kind}`);
  }
}

module.exports = { demoInput, build, draft, fmtMoney, fmtDate, toDate, addBd, iso, poss };

/*
 * Maps engine results onto the OData entity shapes of metadata.xml.
 * Unknown properties are dropped so the mock behaves like the RAP service.
 */
"use strict";

const fs = require("fs");
const path = require("path");
const E = require("./engine");
const S = require("./scenario");

const metadata = fs.readFileSync(path.join(__dirname, "..", "..", "webapp", "localService", "metadata.xml"), "utf8");

function properties(typeName) {
  const block = metadata.split(`<EntityType Name="${typeName}">`)[1] ||
    metadata.split(`<ComplexType Name="${typeName}">`)[1];
  const body = block.split(/<\/(EntityType|ComplexType)>/)[0];
  return [...body.matchAll(/<Property Name="(\w+)"/g)].map((m) => m[1]);
}

const PROPS = {
  Brief: properties("BriefType"),
  RunwayDay: properties("RunwayDayType"),
  RankedRisk: properties("RankedRiskType"),
  TradeOff: properties("TradeOffType"),
  ActionDraft: properties("ActionDraftType"),
  SimDay: properties("ZD_CFO_SimDay")
};

const pick = (set, obj) => Object.fromEntries(PROPS[set].map((p) => [p, obj[p] === undefined ? null : obj[p]]));

let counter = 0;
function uuid(prefix) {
  counter += 1;
  const tail = `${Date.now().toString(16)}${counter.toString(16).padStart(4, "0")}`.slice(-12).padStart(12, "0");
  return `${prefix}-0000-4000-8000-${tail}`;
}

const now = () => new Date().toISOString();
const statusCriticality = { READY: 3, HELD: 2, BLOCKED: 1, APPROVED: 3, ROUTED: 2, REJECTED: 1 };

/** Engine result -> { Brief, RunwayDay[], RankedRisk[], TradeOff[] } rows */
function snapshot(result, briefUuid = uuid("b0000001")) {
  const b = result.brief;
  const cur = b.Currency;
  const ts = now();
  const brief = pick("Brief", {
    ...b,
    BriefUuid: briefUuid,
    LiquidityCriticality: b.ScheduledBreach ? 1 : b.FloorBreach ? 2 : 3,
    GeneratedAt: ts, CreatedAt: ts, LastChangedAt: ts, LocalLastChangedAt: ts,
    CreatedBy: "CFO_DEMO", LastChangedBy: "CFO_DEMO",
    ErrorText: "Mock server — rule-based text (no Gemini call)"
  });
  return {
    Brief: brief,
    RunwayDay: result.days.map((d) => pick("RunwayDay", { ...d, RunwayUuid: uuid("d0000001"), BriefUuid: briefUuid, Currency: cur, LocalLastChangedAt: ts })),
    RankedRisk: result.risks.map((r) => pick("RankedRisk", { ...r, RiskUuid: uuid("r0000001"), BriefUuid: briefUuid, Currency: cur, HasDraft: false, AiNote: "", LocalLastChangedAt: ts })),
    TradeOff: result.tradeoffs.map((t) => pick("TradeOff", {
      ...t, TradeoffUuid: uuid("a0000001"), BriefUuid: briefUuid, Currency: cur, HasDraft: false, AiNote: "",
      StatusCriticality: statusCriticality[t.Status] || 0, LocalLastChangedAt: ts
    }))
  };
}

function actionDraft(briefUuid, sourceKind, sourceUuid, draft, currency) {
  const ts = now();
  return pick("ActionDraft", {
    ...draft,
    ActionUuid: uuid("c0000001"), BriefUuid: briefUuid, SourceKind: sourceKind, SourceUuid: sourceUuid,
    Currency: currency, Status: "DRAFT", StatusCriticality: 0, Engine: "RULE",
    CreatedBy: "CFO_DEMO", CreatedAt: ts, LastChangedBy: "CFO_DEMO", LastChangedAt: ts, LocalLastChangedAt: ts
  });
}

function simDays(result, baseline) {
  const b = result.brief;
  const money = (x) => E.fmtMoney(x);
  const summary = `Scenario low ${money(b.LowPoint)} on Day ${b.LowPointDay} — ${b.ScheduledBreach ? "below" : "above"} ` +
    `the ${money(b.LiquidityFloor)} floor; if the at-risk receipts are late: ${money(b.StressedLowPoint)}.`;
  return result.days.map((d) => pick("SimDay", {
    DayIndex: d.DayIndex, CalendarDate: d.CalendarDate, Currency: b.Currency,
    Baseline: baseline[d.DayIndex] !== undefined ? baseline[d.DayIndex] : d.ClosingScheduled,
    Scenario: d.ClosingScheduled, Stressed: d.ClosingStressed, FloorAmount: d.FloorAmount,
    IsRunDay: d.IsRunDay, IsLowPoint: d.IsLowPoint,
    ScenarioLow: b.LowPoint, ScenarioLowDay: b.LowPointDay,
    StressedLow: b.StressedLowPoint, StressedLowDay: b.StressedLowDay,
    ScenarioBreach: b.ScheduledBreach, StressedBreach: b.FloorBreach, Summary: summary
  }));
}

const num = (x) => (x === null || x === undefined || x === "" ? 0 : Number(x));
const ids = (s) => String(s || "").split(",").map((x) => x.trim()).filter(Boolean);

module.exports = { snapshot, actionDraft, simDays, pick, num, ids, config: S.config, E };

/* Brief actions for the mock server - same rules as the RAP behavior pool. */
"use strict";

const O = require("../engine/odata");
const { E } = O;

async function children(base, set, briefUuid, req) {
  const api = await base.getEntityInterface(set);
  return { api, rows: (await api.getAllEntries(req)).filter((r) => r.BriefUuid === briefUuid) };
}

function copilotAnswer(brief, risks, question) {
  const q = question.toLowerCase();
  const lead = risks.find((r) => r.RiskType === "AR_LATE");
  if (/delay|shift|move|postpone/.test(q)) {
    return "That needs a new calculation — use the What-if panel: set “Delay run (days)” and watch the low point. " +
      `Today the run of ${E.fmtMoney(O.num(brief.RunTotal))} leaves ${E.fmtMoney(O.num(brief.CashAfterRun))}.`;
  }
  if (lead && (q.includes(lead.PartnerName.toLowerCase().split(" ")[0]) || /late|overdue|collect|chase|receivable|customer/.test(q))) {
    return `${lead.Title}. ${lead.Detail} ${lead.RecommendationText}`;
  }
  if (/deposit|surplus|idle|yield/.test(q)) {
    return "A surplus opens only after the low point, and only if the at-risk receipt lands — see the deposit card in Advice.";
  }
  return brief.Narrative;
}

module.exports = {
  getInitialDataSet: () => require("./generated/Brief.json"),

  async executeAction(action, data, keys, req) {
    const base = this.base;
    switch (action.name) {

      case "generateBrief": {
        const anchor = data && data.BriefDate ? String(data.BriefDate) : undefined;
        const rows = O.snapshot(E.build(E.demoInput(anchor)));
        await base.addEntry(rows.Brief, req);
        for (const set of ["RunwayDay", "RankedRisk", "TradeOff"]) {
          const api = await base.getEntityInterface(set);
          for (const row of rows[set]) await api.addEntry(row, req);
        }
        return rows.Brief;
      }

      case "refreshAi": {
        const [brief] = await base.fetchEntries(keys, req);
        return { ...brief, Engine: "RULE", ErrorText: "Mock server — AI is not called; rule-based text kept" };
      }

      case "simulate": {
        const [brief] = await base.fetchEntries(keys, req);
        const { rows: days } = await children(base, "RunwayDay", brief.BriefUuid, req);
        const baseline = Object.fromEntries(days.map((d) => [d.DayIndex, O.num(d.ClosingScheduled)]));
        const result = E.build(E.demoInput(brief.BriefDate), {
          lateIds: O.ids(data.LateItems), heldIds: O.ids(data.HeldItems), factorIds: O.ids(data.FactorItems),
          runDelayDays: O.num(data.RunDelayDays), floorOverride: O.num(data.FloorOverride)
        });
        return O.simDays(result, baseline);
      }

      case "askCopilot": {
        const [brief] = await base.fetchEntries(keys, req);
        const { rows: risks } = await children(base, "Risk", brief.BriefUuid, req);
        return {
          Answer: copilotAnswer(brief, risks, String(data.Question || "")),
          FollowUps: "Show the stressed runway\nWhich item would you defer?\nWhat if we factor the receivable?",
          Engine: "RULE", ModelUsed: "",
          ErrorText: "Mock server — answers are rule-based"
        };
      }

      case "proposeRunExceptions": {
        const [brief] = await base.fetchEntries(keys, req);
        const { rows: risks } = await children(base, "Risk", brief.BriefUuid, req);
        const typed = risks.map((r) => ({ ...r, Exposure: O.num(r.Exposure) }));
        const briefNum = { ...brief, RunTotal: O.num(brief.RunTotal) };
        const draft = E.draft("RUN_EXCEPTIONS", { brief: briefNum, risks: typed });
        const api = await base.getEntityInterface("ActionDraft");
        await api.addEntry(O.actionDraft(brief.BriefUuid, "BRIEF", brief.BriefUuid, draft, brief.Currency), req);
        return brief;
      }

      default:
        return undefined;
    }
  }
};

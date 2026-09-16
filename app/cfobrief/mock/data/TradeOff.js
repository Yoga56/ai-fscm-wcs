"use strict";

const O = require("../engine/odata");
const { E } = O;

const NUMERIC = ["DeferAmount", "DeferCost", "PayAmount", "ShortfallBefore", "ShortfallAfter", "Amount", "Income", "AnnualizedPct"];

module.exports = {
  getInitialDataSet: () => require("./generated/TradeOff.json"),

  async executeAction(action, data, keys, req) {
    if (action.name !== "proposeDecision") {
      return undefined;
    }
    const [row] = await this.base.fetchEntries(keys, req);
    if (row.HasDraft) {
      this.throwError("A draft already exists for this advice", 400);
    }
    const tradeoff = { ...row };
    NUMERIC.forEach((k) => { tradeoff[k] = O.num(row[k]); });
    const draft = E.draft(row.Kind, { tradeoff, config: O.config });
    const api = await this.base.getEntityInterface("ActionDraft");
    await api.addEntry(O.actionDraft(row.BriefUuid, "TRADEOFF", row.TradeoffUuid, draft, row.Currency), req);
    await this.base.updateEntry(keys, { ...row, HasDraft: true }, req);
    return { ...row, HasDraft: true };
  }
};

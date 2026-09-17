"use strict";

const O = require("../engine/odata");
const { E } = O;

module.exports = {
  getInitialDataSet: () => require("./generated/RankedRisk.json"),

  async executeAction(action, data, keys, req) {
    if (action.name !== "draftCollectionNotice") {
      return undefined;
    }
    const [risk] = await this.base.fetchEntries(keys, req);
    if (risk.RiskType !== "AR_LATE" || risk.HasDraft) {
      this.throwError("A collection notice is only available for late receivables without a draft", 400);
    }
    const draft = E.draft("COLLECTION_NOTICE", { risk: { ...risk, Exposure: O.num(risk.Exposure) } });
    const api = await this.base.getEntityInterface("ActionDraft");
    await api.addEntry(O.actionDraft(risk.BriefUuid, "RISK", risk.RiskUuid, draft, risk.Currency), req);
    await this.base.updateEntry(keys, { ...risk, HasDraft: true }, req);
    return { ...risk, HasDraft: true };
  }
};

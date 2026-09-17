"use strict";

const TRANSITIONS = {
  submitForApproval: { from: "DRAFT", to: "ROUTED", criticality: 2 },
  approve: { from: "ROUTED", to: "APPROVED", criticality: 3 },
  reject: { from: "ROUTED", to: "REJECTED", criticality: 1 }
};

module.exports = {
  getInitialDataSet: () => require("./generated/ActionDraft.json"),

  async executeAction(action, data, keys, req) {
    const step = TRANSITIONS[action.name];
    if (!step) {
      return undefined;
    }
    const [row] = await this.base.fetchEntries(keys, req);
    if (row.Status !== step.from) {
      this.throwError(`Not possible in status ${row.Status}`, 400);
    }
    const ts = new Date().toISOString();
    const update = action.name === "submitForApproval"
      ? { RoutedTo: "approver@company.example", RoutedAt: ts }
      : { DecidedBy: "CFO_DEMO", DecidedAt: ts, DecisionNote: (data && data.Note) || "" };
    const next = { ...row, ...update, Status: step.to, StatusCriticality: step.criticality, LastChangedAt: ts, LocalLastChangedAt: ts };
    await this.base.updateEntry(keys, next, req);
    return next;
  }
};

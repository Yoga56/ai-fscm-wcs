sap.ui.define([
  "./BaseController",
  "../model/BriefService",
  "../model/formatter",
  "sap/m/MessageToast",
  "sap/m/Dialog",
  "sap/m/TextArea",
  "sap/m/Button",
  "sap/ui/core/Fragment"
], (BaseController, BriefService, formatter, MessageToast, Dialog, TextArea, Button, Fragment) => {
  "use strict";

  const UPDATE_GROUP = "drafts";
  const DEFAULT_PROMPTS = [
    "What drives the Day 9 low point?",
    "What if we delay this week's run by 2 days?",
    "Which receivable should we chase first?"
  ];

  return BaseController.extend("cfo.brief.controller.Cockpit", {

    onInit() {
      this._simTimer = null;
      this._floorM = null;
      this.router().getRoute("cockpit").attachPatternMatched(this._onRouteMatched, this);
      this.app().setProperty("/followUps", DEFAULT_PROMPTS.map((text) => ({ text })));
      this._styleChart();
    },

    // ------------------------------------------------------------ loading --

    async _onRouteMatched() {
      const path = this.app().getProperty("/briefPath");
      if (path) {
        this._bindBrief(path);
        return;
      }
      await this._loadLatest();
    },

    async _loadLatest() {
      const company = this.app().getProperty("/companyCode");
      const path = await this.busy(() => BriefService.latestBriefPath(this.odata(), company));
      if (path) {
        this._bindBrief(path);
      } else if (path === "") {
        await this.onGenerate();
      }
    },

    _bindBrief(path) {
      this.app().setProperty("/briefPath", path);
      this.getView().bindElement({
        path,
        parameters: { $$updateGroupId: UPDATE_GROUP }
      });
      this._afterBriefLoaded();
    },

    _briefContext() {
      const binding = this.getView().getElementBinding();
      return binding && binding.getBoundContext();
    },

    async _afterBriefLoaded() {
      const context = this._briefContext();
      if (!context) {
        return;
      }
      try {
        const [brief] = await Promise.all([
          context.requestProperty(["LiquidityFloor", "Currency"]),
          this._loadRunway(context),
          this._buildToggles(context)
        ]);
        this._floorM = brief && brief[0] !== undefined ? formatter.num(brief[0]) / 1e6 : null;
        this.app().setProperty("/floorOverrideM", this._floorM);
        this._applyFloorLine(this._floorM);
      } catch (error) {
        // the element binding reports its own errors
      }
    },

    async _loadRunway(context) {
      const days = await BriefService.rows(context, "_RunwayDay", "DayIndex",
        "DayIndex,CalendarDate,ClosingScheduled,ClosingStressed,FloorAmount,IsRunDay,IsLowPoint");
      this._baseline = days;
      this._setChart(days.map((d) => ({
        day: d.DayIndex,
        date: d.CalendarDate,
        scenario: d.ClosingScheduled,
        stressed: d.ClosingStressed,
        baseline: d.ClosingScheduled,
        runDay: d.IsRunDay
      })));
      this.app().setProperty("/scenario", { active: false, summary: "", breach: false });
    },

    _setChart(points) {
      const m = (v) => Math.round(formatter.num(v) / 1e4) / 100;
      this.app().setProperty("/chart", points.map((p) => ({
        Label: `D${p.day} ${formatter.shortDate(p.date)}${p.runDay ? " · run" : ""}`,
        Scenario: m(p.scenario),
        Stressed: m(p.stressed),
        Baseline: m(p.baseline)
      })));
    },

    async _buildToggles(context) {
      const risks = await BriefService.rows(context, "_Risk", "RiskRank",
        "RiskUuid,RiskType,Reference,PartnerName,Exposure,Currency");
      const toggles = [];
      risks.forEach((r) => {
        const money = formatter.money(r.Exposure, r.Currency);
        if (r.RiskType === "AR_LATE") {
          toggles.push({ kind: "late", id: r.Reference, label: `${r.PartnerName} ${money} pays late`, on: false });
          toggles.push({ kind: "factor", id: r.Reference, label: `Factor ${r.PartnerName} today`, on: false });
        } else if (r.RiskType === "AP_OFFPATTERN") {
          toggles.push({ kind: "held", id: r.Reference, label: `Hold ${r.PartnerName} ${money} to the next run`, on: false });
        }
      });
      this.app().setProperty("/toggles", toggles);
    },

    // -------------------------------------------------------------- chart --

    _styleChart() {
      const chart = this.byId("runwayChart");
      chart.setVizProperties({
        title: { visible: false },
        legend: { visible: true },
        legendGroup: { layout: { position: "bottom" } },
        interaction: { selectability: { mode: "NONE" } },
        valueAxis: { title: { visible: false }, label: { formatString: "0.0" } },
        categoryAxis: { title: { visible: false } },
        plotArea: {
          colorPalette: ["#1a1f4d", "#b3261e", "#9aa0b4"],
          dataLabel: { visible: false },
          marker: { visible: true, size: 4 },
          window: { start: "firstDataPoint", end: "lastDataPoint" }
        }
      });
    },

    _applyFloorLine(floorM) {
      if (floorM === null || floorM === undefined) {
        return;
      }
      this.byId("runwayChart").setVizProperties({
        plotArea: {
          referenceLine: {
            line: {
              valueAxis: [{
                value: floorM,
                visible: true,
                size: 2,
                type: "dotted",
                color: "#b3261e",
                label: { text: `Floor $${floorM.toFixed(1)}M`, visible: true, background: "#b3261e" }
              }]
            }
          }
        }
      });
    },

    // ------------------------------------------------------------ what-if --

    onWhatIf() {
      clearTimeout(this._simTimer);
      this._simTimer = setTimeout(() => this._simulate(), 350);
    },

    onResetWhatIf() {
      const app = this.app();
      app.setProperty("/toggles", app.getProperty("/toggles").map((t) => ({ ...t, on: false })));
      app.setProperty("/runDelay", 0);
      app.setProperty("/floorOverrideM", this._floorM);
      this._simulate();
    },

    onTryWhatIf(event) {
      const context = event.getSource().getBindingContext();
      const type = context.getProperty("RiskType");
      const reference = context.getProperty("Reference");
      const app = this.app();
      const kind = type === "AR_LATE" ? "late" : "held";
      app.setProperty("/toggles", app.getProperty("/toggles").map((t) => (
        t.id === reference && t.kind === kind ? { ...t, on: true } : t)));
      this._simulate();
      this.byId("runwayChart").getDomRef()?.scrollIntoView({ behavior: "smooth", block: "center" });
    },

    async _simulate() {
      const context = this._briefContext();
      if (!context) {
        return;
      }
      const app = this.app();
      const toggles = app.getProperty("/toggles");
      const pick = (kind) => toggles.filter((t) => t.on && t.kind === kind).map((t) => t.id).join(",");
      const delay = formatter.num(app.getProperty("/runDelay"));
      const floorM = app.getProperty("/floorOverrideM");
      const floorChanged = floorM !== null && floorM !== undefined && Math.abs(floorM - this._floorM) > 1e-9;
      this._applyFloorLine(floorChanged ? floorM : this._floorM);

      const params = {
        LateItems: pick("late"),
        HeldItems: pick("held"),
        FactorItems: pick("factor"),
        RunDelayDays: delay,
        FloorOverride: floorChanged ? String(Math.round(floorM * 1e6)) : "0"
      };

      if (!params.LateItems && !params.HeldItems && !params.FactorItems && !delay && !floorChanged) {
        await this._loadRunway(context);
        return;
      }

      const result = await this.busy(() => BriefService.call(context, "simulate", params));
      const days = (result && result.value) || [];
      if (!days.length) {
        return;
      }
      this._setChart(days.map((d) => ({
        day: d.DayIndex, date: d.CalendarDate, scenario: d.Scenario, stressed: d.Stressed,
        baseline: d.Baseline, runDay: d.IsRunDay
      })));
      app.setProperty("/scenario", {
        active: true,
        summary: days[0].Summary,
        breach: !!days[0].ScenarioBreach
      });
    },

    // ------------------------------------------------------------ actions --

    async onGenerate() {
      const company = this.app().getProperty("/companyCode");
      const path = await this.busy(() => BriefService.generate(this.odata(), company));
      if (path) {
        this._bindBrief(path);
        MessageToast.show(this.text("generated"));
      }
    },

    async onCompanyChange() {
      this.app().setProperty("/briefPath", "");
      this.app().setProperty("/chat", []);
      await this._loadLatest();
    },

    async onRefreshAi() {
      const context = this._briefContext();
      if (!context) {
        return;
      }
      await this.busy(async () => {
        await BriefService.call(context, "refreshAi");
        await BriefService.refreshParts(context, ["_Risk", "_TradeOff"]);
        this.getView().getElementBinding().refresh();
      });
    },

    onInbox() {
      this.router().navTo("inbox");
    },

    async onDraftNotice(event) {
      await this._draftFrom(event.getSource().getBindingContext(), "draftCollectionNotice", ["_ActionDraft", "_Risk"]);
    },

    async onProposeDecision(event) {
      await this._draftFrom(event.getSource().getBindingContext(), "proposeDecision", ["_ActionDraft", "_TradeOff"]);
    },

    async onRunExceptions() {
      await this._draftFrom(this._briefContext(), "proposeRunExceptions", ["_ActionDraft"]);
    },

    async onTopNotice() {
      const risks = this.byId("riskTable").getItems().map((item) => item.getBindingContext());
      const top = risks.find((c) => c.getProperty("RiskType") === "AR_LATE" && !c.getProperty("HasDraft"));
      if (!top) {
        MessageToast.show("No late receivable without a draft");
        return;
      }
      await this._draftFrom(top, "draftCollectionNotice", ["_ActionDraft", "_Risk"]);
    },

    async onDraftAllAdvice() {
      const open = this.byId("adviceList").getItems().map((item) => item.getBindingContext())
        .filter((c) => !c.getProperty("HasDraft"));
      if (!open.length) {
        MessageToast.show("All advice is drafted already");
        return;
      }
      await this.busy(async () => {
        for (const context of open) {
          await BriefService.call(context, "proposeDecision");
        }
        await BriefService.refreshParts(this._briefContext(), ["_ActionDraft", "_TradeOff"]);
      });
      MessageToast.show(`${open.length} drafts created`);
    },

    async _draftFrom(context, action, refresh) {
      if (!context) {
        return;
      }
      const done = await this.busy(async () => {
        await BriefService.call(context, action);
        await BriefService.refreshParts(this._briefContext(), refresh);
        return true;
      });
      if (done) {
        MessageToast.show("Draft created - see Action drafts");
      }
    },

    // ------------------------------------------------------ action drafts --

    async onOpenDraft(event) {
      const context = event.getSource().getBindingContext();
      if (!this._draftDialog) {
        this._draftDialog = await Fragment.load({
          id: this.getView().getId(),
          name: "cfo.brief.fragment.ActionDraft",
          controller: this
        });
        this.getView().addDependent(this._draftDialog);
      }
      this._draftDialog.setBindingContext(context);
      this._draftDialog.open();
    },

    async onDraftSave() {
      await this.busy(() => this.odata().submitBatch(UPDATE_GROUP));
      if (!this.odata().hasPendingChanges(UPDATE_GROUP)) {
        MessageToast.show("Draft saved");
        this._draftDialog.close();
      }
    },

    onDraftClose() {
      this.odata().resetChanges(UPDATE_GROUP);
      this._draftDialog.close();
    },

    async onSubmitDraft(event) {
      const context = event.getSource().getBindingContext();
      if (this.odata().hasPendingChanges(UPDATE_GROUP)) {
        await this.busy(() => this.odata().submitBatch(UPDATE_GROUP));
      }
      const done = await this.busy(async () => {
        await BriefService.call(context, "submitForApproval");
        await BriefService.refreshParts(this._briefContext(), ["_ActionDraft"]);
        return true;
      });
      if (done) {
        MessageToast.show(this.text("routed"));
        this._draftDialog?.close();
      }
    },

    onApproveDraft(event) {
      this._decide(event.getSource().getBindingContext(), "approve");
    },

    onRejectDraft(event) {
      this._decide(event.getSource().getBindingContext(), "reject");
    },

    _decide(context, action) {
      const note = new TextArea({ width: "100%", rows: 3, placeholder: this.text("decisionNote") });
      const dialog = new Dialog({
        title: action === "approve" ? this.text("approve") : this.text("reject"),
        contentWidth: "24rem",
        content: [note],
        beginButton: new Button({
          text: action === "approve" ? this.text("approve") : this.text("reject"),
          type: action === "approve" ? "Accept" : "Reject",
          press: async () => {
            dialog.close();
            await this.busy(async () => {
              await BriefService.call(context, action, { Note: note.getValue() });
              await BriefService.refreshParts(this._briefContext(), ["_ActionDraft"]);
            });
            this._draftDialog?.close();
          }
        }),
        endButton: new Button({ text: this.text("cancel"), press: () => dialog.close() }),
        afterClose: () => dialog.destroy()
      });
      this.getView().addDependent(dialog);
      dialog.open();
    },

    // ------------------------------------------------------------ copilot --

    onQuickPrompt(event) {
      this.app().setProperty("/question", event.getSource().getText());
      this.onAsk();
    },

    async onAsk() {
      const app = this.app();
      const question = (app.getProperty("/question") || "").trim();
      const context = this._briefContext();
      if (!question || !context) {
        return;
      }
      const chat = app.getProperty("/chat").concat({ role: "user", text: question });
      app.setProperty("/chat", chat);
      app.setProperty("/question", "");

      const answer = await this.busy(() => BriefService.call(context, "askCopilot", { Question: question }));
      if (!answer) {
        return;
      }
      app.setProperty("/chat", app.getProperty("/chat").concat({
        role: "ai",
        text: answer.Answer,
        engine: answer.ErrorText
          ? `${formatter.engineText(answer.Engine, answer.ModelUsed)} — ${answer.ErrorText}`
          : formatter.engineText(answer.Engine, answer.ModelUsed),
        state: formatter.engineState(answer.Engine)
      }));
      const followUps = String(answer.FollowUps || "").split("\n").map((t) => t.trim()).filter(Boolean);
      if (followUps.length) {
        app.setProperty("/followUps", followUps.map((text) => ({ text })));
      }
    },

    // --------------------------------------------------------- formatters --

    subtitle(company, date, mode, horizon) {
      if (!company) {
        return "";
      }
      return `Company code ${company} · ${formatter.shortDate(date)} · ${horizon}-day horizon · ${mode === "DEMO" ? "demo data" : "live ledger"}`;
    },

    lowPointLabel(day, date) {
      return day === null || day === undefined ? this.text("kpiLow") : `${this.text("kpiLow")} · Day ${day} (${formatter.shortDate(date)})`;
    },

    adviceBadge() {
      return formatter.epardHtml("A");
    }
  });
});

sap.ui.define([
  "./BaseController",
  "../model/BriefService",
  "../model/formatter"
], (BaseController, BriefService, formatter) => {
  "use strict";

  const BRIEF_FIELDS = ["Headline", "Narrative", "Currency", "CashToday", "RunTotal", "RunDate", "RunInvoiceCount",
    "RunVendorCount", "CashAfterRun", "LowPoint", "LowPointDay", "LiquidityFloor", "StressedLowPoint", "FloorBreach",
    "ExplainText"];

  return BaseController.extend("cfo.brief.controller.Inbox", {

    onInit() {
      this.router().getRoute("inbox").attachPatternMatched(this._onRouteMatched, this);
      this.byId("inboxPage").setShowFooter(true);
    },

    async _onRouteMatched() {
      let path = this.app().getProperty("/briefPath");
      if (!path) {
        path = await this.busy(() => BriefService.latestBriefPath(this.odata(), this.app().getProperty("/companyCode")));
      }
      if (!path) {
        this.onBack();
        return;
      }
      this.getView().bindElement({ path });
      const context = this.getView().getElementBinding().getBoundContext();
      await this.busy(() => this._render(context));
    },

    async _render(context) {
      const values = await context.requestProperty(BRIEF_FIELDS);
      const b = Object.fromEntries(BRIEF_FIELDS.map((f, i) => [f, values[i]]));
      const [risks, advice] = await Promise.all([
        BriefService.rows(context, "_Risk", "RiskRank", "RiskType,Title,RecommendationText"),
        BriefService.rows(context, "_TradeOff", "Seq", "Kind,Title,Question,Recommendation,Detail,Income,Currency")
      ]);
      this.app().setProperty("/inboxHtml", this.compose(b, risks, advice));
    },

    /** Mirrors ZCL_CFO_MAILER=>BRIEF_HTML (FormattedText-safe tags only). */
    compose(b, risks, advice) {
      const e = formatter.escape;
      const m = (v) => formatter.money(v, b.Currency);
      const d = formatter.shortDate;
      const html = [];
      let n = 0;

      html.push(`<h3>${e(b.Headline)}</h3>`, `<p>${e(b.Narrative)}</p>`);

      html.push(`<p class="sec">Cash &amp; this week's run</p>`);
      html.push(`<p>Cash <strong>${m(b.CashToday)}</strong> today → proposal <strong>${m(b.RunTotal)}</strong> ` +
        `(${d(b.RunDate)} · ${b.RunInvoiceCount} inv / ${b.RunVendorCount} vendors) → <strong>${m(b.CashAfterRun)}</strong> after the run.</p>`);
      html.push(`<p>Low-point <strong>${m(b.LowPoint)} on Day ${b.LowPointDay}</strong> (floor ${m(b.LiquidityFloor)}). ` +
        `If the at-risk receipts are late → <span class="${b.FloorBreach ? "neg" : "pos"}">${m(b.StressedLowPoint)}` +
        `${b.FloorBreach ? " — below floor" : ""}</span>.</p>`);

      const exceptions = risks.filter((r) => r.RiskType === "AP_OFFPATTERN" || r.RiskType === "AP_BLOCKED");
      if (exceptions.length) {
        html.push(`<p class="sec">Review before ${d(b.RunDate)} · exceptions inside the run</p>`);
        exceptions.forEach((r) => html.push(`<p><strong>${++n}&nbsp; ${e(r.Title)}</strong> — ${e(r.RecommendationText)}</p>`));
      }

      const priorities = advice.filter((a) => a.Kind === "PRIORITIZE");
      if (priorities.length) {
        html.push(`<p class="sec">Before the next run</p>`);
        priorities.forEach((a) => html.push(`<p><strong>${++n}&nbsp; ${e(a.Title)}</strong> — ${e(a.Question)} <strong>${e(a.Recommendation)}</strong></p>`));
      }

      const cash = [
        ...risks.filter((r) => r.RiskType === "AR_LATE").map((r) => `<li>${e(r.Title)} — <strong>${e(r.RecommendationText)}</strong></li>`),
        ...advice.filter((a) => ["DEPOSIT", "EARLYPAY", "DEFER"].includes(a.Kind)).map((a) =>
          `<li>${e(a.Recommendation)} ${e(a.Detail)}${formatter.num(a.Income) > 0 ? ` <span class="pos">≈ ${m(a.Income)}</span>` : ""}</li>`)
      ];
      if (cash.length) {
        html.push(`<p class="sec">Cash &amp; collections</p>`, `<ul>${cash.join("")}</ul>`);
      }

      if (b.ExplainText) {
        html.push(`<p class="sec">What moved</p>`, `<p>${e(b.ExplainText).replace(/\n/g, "<br>")}</p>`);
      }
      return html.join("");
    },

    onBack() {
      this.router().navTo("cockpit");
    }
  });
});

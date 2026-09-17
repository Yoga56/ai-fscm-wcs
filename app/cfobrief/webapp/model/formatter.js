sap.ui.define([], () => {
  "use strict";

  const WD = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const MO = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const SYMBOL = { USD: "$", EUR: "€", GBP: "£" };

  const num = (v) => (v === null || v === undefined || v === "" ? 0 : Number(v));
  const escape = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" }[c]));

  const formatter = {
    num,
    escape,

    /** Executive money: >= 100k in millions with one decimal, else whole units. */
    money(value, currency) {
      if (value === null || value === undefined || value === "") {
        return "";
      }
      const v = num(value);
      const sym = SYMBOL[currency || "USD"] ?? `${currency} `;
      const sign = v < 0 ? "-" : "";
      const a = Math.abs(v);
      return a >= 1e5
        ? `${sign}${sym}${(a / 1e6).toFixed(1)}M`
        : `${sign}${sym}${Math.round(a).toLocaleString("en-US")}`;
    },

    shortDate(value) {
      if (!value) {
        return "";
      }
      const d = value instanceof Date ? value : new Date(`${String(value).slice(0, 10)}T00:00:00Z`);
      if (Number.isNaN(d.getTime())) {
        return "";
      }
      return `${WD[(d.getUTCDay() + 6) % 7]} ${d.getUTCDate()} ${MO[d.getUTCMonth()]}`;
    },

    dayText(day, date) {
      return day === null || day === undefined ? "" : `Day ${day} · ${formatter.shortDate(date)}`;
    },

    percent(value) {
      return `${Math.abs(num(value)).toFixed(1)}%`;
    },

    change(value) {
      return `${num(value) >= 0 ? "up" : "down"} ${formatter.percent(value)}`;
    },

    changeState(value, goodWhenDown) {
      const up = num(value) > 0;
      return (up === !goodWhenDown) ? "Error" : "Success";
    },

    probability(value) {
      return `${Math.round(num(value) * 100)}%`;
    },

    riskState(criticality) {
      return { 1: "Error", 2: "Warning", 3: "Success" }[num(criticality)] || "None";
    },

    adviceState(status) {
      return { READY: "Success", HELD: "Warning", BLOCKED: "Error" }[status] || "None";
    },

    draftState(status) {
      return { DRAFT: "Information", ROUTED: "Warning", APPROVED: "Success", REJECTED: "Error" }[status] || "None";
    },

    engineState(engine) {
      return engine === "HYBRID" ? "Success" : "Warning";
    },

    engineText(engine, model) {
      return engine === "HYBRID" ? `AI · ${model || "Gemini"}` : "Rule engine";
    },

    lowState(scheduledBreach, stressedBreach) {
      return scheduledBreach ? "Error" : stressedBreach ? "Warning" : "Success";
    },

    atRiskText(stressedLow, stressedDay, breach, currency) {
      if (stressedLow === null || stressedLow === undefined) {
        return "";
      }
      return `If receipts are late: ${formatter.money(stressedLow, currency)} on Day ${stressedDay}${breach ? " — below floor" : ""}`;
    },

    headroomText(headroom, currency) {
      const h = num(headroom);
      return h >= 0 ? `${formatter.money(h, currency)} headroom at the low point` : `${formatter.money(-h, currency)} short at the low point`;
    },

    runText(count, vendors, date) {
      return count ? `${count} invoices / ${vendors} vendors · ${formatter.shortDate(date)}` : "";
    },

    afterRunText(amount, holds, currency) {
      return amount === null || amount === undefined ? "" : `${formatter.money(amount, currency)} after the run${holds ? " — holds above floor" : " — breaks the floor"}`;
    },

    runState(holds) {
      return holds ? "Success" : "Error";
    },

    epardHtml(letters) {
      return String(letters || "").split("").filter((l) => "EPRAD".includes(l))
        .map((l) => `<span class="epard epard-${l}">${l}</span>`).join("");
    },

    kindText(kind) {
      return { DEFER: "Trade-off: which do I pay?", PRIORITIZE: "Approve in time", DEPOSIT: "Idle cash to work",
        EARLYPAY: "Early-payment discount" }[kind] || kind;
    },

    kindIcon(kind) {
      return { DEFER: "sap-icon://compare", PRIORITIZE: "sap-icon://fob-watch", DEPOSIT: "sap-icon://loan",
        EARLYPAY: "sap-icon://discussion-2" }[kind] || "sap-icon://lightbulb";
    },

    adviceClass(status) {
      return status === "READY" ? "" : "cfoAdviceHeld";
    },

    actionTypeText(type) {
      return { COLLECTION_NOTICE: "Collection notice", RUN_EXCEPTIONS: "Run exceptions", DEFER: "Deferral approval",
        PRIORITIZE: "Payment priority", DEPOSIT: "Deposit proposal", EARLYPAY: "Early-pay discount" }[type] || type;
    },

    isDraft: (status) => status === "DRAFT",
    isRouted: (status) => status === "ROUTED",
    canDraftNotice: (type, hasDraft) => type === "AR_LATE" && !hasDraft,
    canPropose: (hasDraft) => !hasDraft,
    proposeText: (hasDraft) => (hasDraft ? "Drafted" : "Draft it"),
    hasValue: (value) => value !== null && value !== undefined && value !== "" && num(value) !== 0,
    notEmpty: (value) => !!value,
    positive: (value) => num(value) > 0
  };

  return formatter;
});

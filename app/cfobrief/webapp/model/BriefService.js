sap.ui.define([
  "sap/ui/model/Filter",
  "sap/ui/model/FilterOperator",
  "sap/ui/model/Sorter"
], (Filter, FilterOperator, Sorter) => {
  "use strict";

  const NS = "com.sap.gateway.srvd.zui_cfo_brief.v0001";

  /** Thin wrapper around the RAP service: reads and actions. */
  return {
    NS,

    /** Path of the most recent brief of a company code, or "" if none. */
    async latestBriefPath(model, companyCode) {
      const binding = model.bindList("/Brief", null,
        [new Sorter("BriefDate", true), new Sorter("GeneratedAt", true)],
        [new Filter("CompanyCode", FilterOperator.EQ, companyCode)],
        { $select: "BriefUuid,Engine" });
      const [first] = await binding.requestContexts(0, 1);
      const path = first && first.getProperty("Engine") !== "SEED" ? first.getPath() : "";
      binding.destroy();
      return path;
    },

    async generate(model, companyCode) {
      const op = model.bindContext(`/Brief/${NS}.generateBrief(...)`);
      op.setParameter("CompanyCode", companyCode);
      const returned = await op.execute();
      const data = (returned || op.getBoundContext()).getObject() || {};
      return returned && returned.getPath().startsWith("/Brief(")
        ? returned.getPath()
        : `/Brief(${data.BriefUuid})`;
    },

    /** Executes a bound action; resolves with the returned data (or undefined). */
    async call(context, action, parameters = {}) {
      const op = context.getModel().bindContext(`${NS}.${action}(...)`, context);
      Object.entries(parameters).forEach(([name, value]) => op.setParameter(name, value));
      await op.execute();
      const bound = op.getBoundContext();
      return bound ? bound.getObject() : undefined;
    },

    /** Reads a child collection; $select is explicit because autoExpandSelect only selects bound fields. */
    async rows(context, navigation, sortBy, select) {
      const binding = context.getModel().bindList(navigation, context, sortBy ? [new Sorter(sortBy)] : [], [],
        select ? { $select: select } : {});
      const contexts = await binding.requestContexts(0, 500);
      const rows = contexts.map((c) => c.getObject());
      binding.destroy();
      return rows;
    },

    /** Reloads parts of the brief. "$auto" matters: the default would be the deferred "drafts" update group. */
    refreshParts(context, navigations) {
      return context.requestSideEffects(navigations.map((n) => ({ $NavigationPropertyPath: n })), "$auto");
    }
  };
});

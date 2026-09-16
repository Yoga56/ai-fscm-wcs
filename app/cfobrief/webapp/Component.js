sap.ui.define([
  "sap/ui/core/UIComponent",
  "sap/ui/model/json/JSONModel",
  "sap/ui/Device"
], (UIComponent, JSONModel, Device) => {
  "use strict";

  return UIComponent.extend("cfo.brief.Component", {
    metadata: {
      manifest: "json",
      interfaces: ["sap.ui.core.IAsyncContentCreation"]
    },

    init() {
      UIComponent.prototype.init.apply(this, arguments);

      const params = new URLSearchParams(window.location.search);
      this.setModel(new JSONModel(Device).setDefaultBindingMode("OneWay"), "device");

      // UI state shared by the views (never persisted)
      this.setModel(new JSONModel({
        companyCode: params.get("company") || "1000",
        briefPath: "",
        busy: false,
        chart: [],
        toggles: [],
        runDelay: 0,
        floorOverrideM: null,
        scenario: { active: false, summary: "", breach: false, low: 0, lowDay: 0, stressedLow: 0 },
        chat: [],
        followUps: [],
        question: "",
        inboxHtml: "",
        showSide: true
      }), "app");

      this.getRouter().initialize();
    },

    getContentDensityClass() {
      return Device.support.touch ? "sapUiSizeCozy" : "sapUiSizeCompact";
    }
  });
});

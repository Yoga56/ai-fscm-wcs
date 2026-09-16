sap.ui.define([
  "sap/ui/core/mvc/Controller",
  "sap/m/MessageBox",
  "../model/formatter"
], (Controller, MessageBox, formatter) => {
  "use strict";

  return Controller.extend("cfo.brief.controller.BaseController", {
    formatter,

    app() {
      return this.getOwnerComponent().getModel("app");
    },

    odata() {
      return this.getOwnerComponent().getModel();
    },

    text(key, args) {
      return this.getOwnerComponent().getModel("i18n").getResourceBundle().getText(key, args);
    },

    router() {
      return this.getOwnerComponent().getRouter();
    },

    /** Runs an async task with the busy indicator and a readable error. */
    async busy(task) {
      this.app().setProperty("/busy", true);
      try {
        return await task();
      } catch (error) {
        if (!error.canceled) {
          MessageBox.error(error.message || String(error));
        }
        return undefined;
      } finally {
        this.app().setProperty("/busy", false);
      }
    }
  });
});

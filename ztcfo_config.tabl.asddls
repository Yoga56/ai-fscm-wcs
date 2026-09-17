@EndUserText.label : 'CFO Brief - Configuration per company code'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #C
@AbapCatalog.dataMaintenance : #RESTRICTED
define table ztcfo_config {

  key client                : abap.clnt not null;
  key company_code          : abap.char(4) not null;

  data_mode                 : abap.char(4);      // LIVE / DEMO
  demo_anchor_date          : abap.dats;         // DEMO: the brief date the seed was built for (a Tuesday)
  currency                  : abap.cuky;
  @Semantics.amount.currencyCode : 'ztcfo_config.currency'
  liquidity_floor           : abap.curr(23,2);

  // ---- forecast ----------------------------------------------------------
  horizon_days              : abap.int4;         // 30
  run_weekday               : abap.int1;         // 1 = Monday ... 7 = Sunday (4 = Thursday)
  proposal_lead_bd          : abap.int1;         // proposal built n business days before the run
  approval_lead_bd          : abap.int1;         // approvals needed n business days before the proposal
  collection_lag_bd         : abap.int1;         // overdue AR without promise: expected in n business days
  ap_window_days            : abap.int4;         // "AP due this window"
  bank_gl_from              : abap.char(10);     // LIVE: bank G/L accounts that make up "cash today"
  bank_gl_to                : abap.char(10);

  // ---- predict / rank ----------------------------------------------------
  stress_threshold          : abap.dec(5,2);     // P(late) from which a receipt is shifted in the stressed path
  min_history               : abap.int4;         // cleared items needed before a partner's own history is used
  history_days              : abap.int4;         // look-back for clearing history
  zscore_threshold          : abap.dec(5,2);     // off-pattern supplier invoice
  spend_threshold_pct       : abap.dec(5,1);     // plant spend spike

  // ---- advise ------------------------------------------------------------
  factoring_lead_bd         : abap.int1;
  factoring_advance_pct     : abap.dec(5,2);
  deposit_rate_pct          : abap.dec(7,3);
  deposit_days              : abap.int4;
  late_fee_rate_pct         : abap.dec(7,3);
  deferral_days             : abap.int4;

  // ---- AI and mail -------------------------------------------------------
  four_eyes                 : abap_boolean;      // author of an action draft may not approve it
  ai_enabled                : abap_boolean;
  destination               : abap.char(200);    // BTP destination, default GEMINI_AI
  dest_instance             : abap.char(100);    // S/4HANA Cloud: service instance name of the SAP_COM_0276 arrangement
  model                     : abap.char(60);     // default gemini-2.5-pro
  sender_email              : abap.char(241);
  recipient_email           : abap.char(241);    // CFO - daily brief
  approver_email            : abap.char(241);    // approvals for action drafts

}

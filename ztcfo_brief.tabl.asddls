@EndUserText.label : 'CFO Daily Brief - Header (one snapshot per company and day)'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table ztcfo_brief {

  key client                : abap.clnt not null;
  key brief_uuid            : sysuuid_x16 not null;

  company_code              : abap.char(4);
  brief_date                : abap.dats;
  data_mode                 : abap.char(4);
  currency                  : abap.cuky;
  horizon_days              : abap.int4;

  // ---- position ----------------------------------------------------------
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  cash_today                : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  liquidity_floor           : abap.curr(23,2);
  run_date                  : abap.dats;
  next_run_date             : abap.dats;
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  run_total                 : abap.curr(23,2);
  run_invoice_count         : abap.int4;
  run_vendor_count          : abap.int4;
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  cash_after_run            : abap.curr(23,2);
  run_holds_floor           : abap_boolean;
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  low_point                 : abap.curr(23,2);
  low_point_day             : abap.int4;
  low_point_date            : abap.dats;
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  stressed_low_point        : abap.curr(23,2);
  stressed_low_day          : abap.int4;
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  headroom                  : abap.curr(23,2);
  floor_breach              : abap_boolean;      // stressed path goes below the floor
  scheduled_breach          : abap_boolean;      // scheduled path goes below the floor

  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  ar_total                  : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  ar_overdue                : abap.curr(23,2);
  ar_overdue_chg_pct        : abap.dec(7,1);
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  ap_total                  : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  ap_due_window             : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_brief.currency'
  ap_overdue                : abap.curr(23,2);
  ap_overdue_chg_pct        : abap.dec(7,1);

  // ---- words -------------------------------------------------------------
  review_count              : abap.int4;
  headline                  : abap.char(200);
  narrative                 : abap.string(0);
  explain_text              : abap.string(0);
  engine                    : abap.char(6);      // HYBRID / RULE / SEED
  model_used                : abap.char(60);
  error_text                : abap.char(255);
  generated_at              : timestampl;

  created_by                : abp_creation_user;
  created_at                : abp_creation_tstmpl;
  last_changed_by           : abp_lastchange_user;
  last_changed_at           : abp_lastchange_tstmpl;
  local_last_changed_at     : abp_locinst_lastchange_tstmpl;

}

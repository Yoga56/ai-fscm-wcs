@EndUserText.label : 'CFO Daily Brief - Liquidity runway day'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table ztcfo_runway {

  key client                : abap.clnt not null;
  key runway_uuid           : sysuuid_x16 not null;

  brief_uuid                : sysuuid_x16 not null;
  day_index                 : abap.int4;
  calendar_date             : abap.dats;
  currency                  : abap.cuky;
  @Semantics.amount.currencyCode : 'ztcfo_runway.currency'
  inflow                    : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_runway.currency'
  outflow                   : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_runway.currency'
  closing_scheduled         : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_runway.currency'
  closing_stressed          : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_runway.currency'
  closing_expected          : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_runway.currency'
  floor_amount              : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_runway.currency'
  floor_delta               : abap.curr(23,2);
  is_weekend                : abap_boolean;
  is_run_day                : abap_boolean;
  is_low_point              : abap_boolean;

  local_last_changed_at     : abp_locinst_lastchange_tstmpl;

}

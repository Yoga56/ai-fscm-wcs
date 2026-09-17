@EndUserText.label : 'CFO Daily Brief - Advice (trade-off / opportunity)'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table ztcfo_tradeoff {

  key client                : abap.clnt not null;
  key tradeoff_uuid         : sysuuid_x16 not null;

  brief_uuid                : sysuuid_x16 not null;
  seq                       : abap.int4;
  kind                      : abap.char(12);     // DEFER / PRIORITIZE / DEPOSIT / EARLYPAY
  title                     : abap.char(200);
  question                  : abap.char(300);
  currency                  : abap.cuky;
  defer_item                : abap.char(20);
  defer_name                : abap.char(80);
  defer_partner             : abap.char(80);
  @Semantics.amount.currencyCode : 'ztcfo_tradeoff.currency'
  defer_amount              : abap.curr(23,2);
  defer_note                : abap.char(200);
  @Semantics.amount.currencyCode : 'ztcfo_tradeoff.currency'
  defer_cost                : abap.curr(23,2);
  pay_item                  : abap.char(20);
  pay_name                  : abap.char(80);
  pay_partner               : abap.char(80);
  @Semantics.amount.currencyCode : 'ztcfo_tradeoff.currency'
  pay_amount                : abap.curr(23,2);
  pay_note                  : abap.char(200);
  @Semantics.amount.currencyCode : 'ztcfo_tradeoff.currency'
  shortfall_before          : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_tradeoff.currency'
  shortfall_after           : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_tradeoff.currency'
  amount                    : abap.curr(23,2);
  @Semantics.amount.currencyCode : 'ztcfo_tradeoff.currency'
  income                    : abap.curr(23,2);
  annualized_pct            : abap.dec(7,1);
  recommendation            : abap.char(300);
  detail                    : abap.char(400);
  caveat                    : abap.char(200);
  confidence                : abap.char(4);      // HIGH / LOW
  confidence_note           : abap.char(200);
  status                    : abap.char(10);     // READY / HELD / BLOCKED
  has_draft                 : abap_boolean;
  action_date               : abap.dats;
  ai_note                   : abap.char(400);

  local_last_changed_at     : abp_locinst_lastchange_tstmpl;

}

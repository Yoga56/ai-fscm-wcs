@EndUserText.label : 'CFO Daily Brief - Ranked risk'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table ztcfo_risk {

  key client                : abap.clnt not null;
  key risk_uuid             : sysuuid_x16 not null;

  brief_uuid                : sysuuid_x16 not null;
  risk_rank                 : abap.int4;
  risk_type                 : abap.char(20);     // AR_LATE / AP_OFFPATTERN / AP_BLOCKED / SPEND_SPIKE
  epard                     : abap.char(5);      // step badges, e.g. PR
  reference                 : abap.char(200);    // document id(s) or PLANT-xxxx
  partner_name              : abap.char(120);
  title                     : abap.char(200);
  detail                    : abap.char(400);
  currency                  : abap.cuky;
  @Semantics.amount.currencyCode : 'ztcfo_risk.currency'
  exposure                  : abap.curr(23,2);
  probability               : abap.dec(5,2);
  floor_weight              : abap.dec(5,2);
  @Semantics.amount.currencyCode : 'ztcfo_risk.currency'
  score                     : abap.curr(23,2);
  criticality               : abap.int1;         // 1 red / 2 orange / 3 green
  recommendation            : abap.char(30);
  recommendation_text       : abap.char(200);
  ai_note                   : abap.char(400);
  due_by                    : abap.dats;
  status                    : abap.char(10);     // OPEN / DONE
  has_draft                 : abap_boolean;

  local_last_changed_at     : abp_locinst_lastchange_tstmpl;

}

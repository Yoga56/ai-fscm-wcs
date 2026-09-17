@EndUserText.label : 'CFO Daily Brief - Action draft (draft + route, never posts)'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table ztcfo_action {

  key client                : abap.clnt not null;
  key action_uuid           : sysuuid_x16 not null;

  brief_uuid                : sysuuid_x16 not null;
  action_type               : abap.char(20);     // COLLECTION_NOTICE / RUN_EXCEPTIONS / DEFER / PRIORITIZE / DEPOSIT / EARLYPAY
  source_kind               : abap.char(10);     // RISK / TRADEOFF / BRIEF
  source_uuid               : sysuuid_x16;
  recipient                 : abap.char(120);
  subject                   : abap.char(200);
  body                      : abap.string(0);
  internal_note             : abap.char(400);
  currency                  : abap.cuky;
  @Semantics.amount.currencyCode : 'ztcfo_action.currency'
  amount                    : abap.curr(23,2);
  status                    : abap.char(10);     // DRAFT / ROUTED / APPROVED / REJECTED
  engine                    : abap.char(6);      // HYBRID / RULE
  routed_to                 : abap.char(241);
  routed_at                 : timestampl;
  decided_by                : abap.char(12);
  decided_at                : timestampl;
  decision_note             : abap.char(255);

  created_by                : abp_creation_user;
  created_at                : abp_creation_tstmpl;
  last_changed_by           : abp_lastchange_user;
  last_changed_at           : abp_lastchange_tstmpl;
  local_last_changed_at     : abp_locinst_lastchange_tstmpl;

}

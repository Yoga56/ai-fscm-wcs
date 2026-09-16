@EndUserText.label : 'CFO Brief - DEMO bank balance and plant spend'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table ztcfo_demo_misc {

  key client                : abap.clnt not null;
  key company_code          : abap.char(4) not null;
  key record_type           : abap.char(5) not null;    // BANK / SPEND
  key object_id             : abap.char(10) not null;   // BANK: blank, SPEND: plant
  key window_no             : abap.int1 not null;       // SPEND: 0 = last 30 days, 1..3 = the windows before

  currency                  : abap.cuky;
  @Semantics.amount.currencyCode : 'ztcfo_demo_misc.currency'
  amount                    : abap.curr(23,2);

}

@EndUserText.label : 'CFO Brief - DEMO open and cleared AR/AP items'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table ztcfo_demo_item {

  key client                : abap.clnt not null;
  key company_code          : abap.char(4) not null;
  key doc_id                : abap.char(20) not null;

  account_type              : abap.char(1);      // D customer / K supplier
  partner                   : abap.char(10);
  partner_name              : abap.char(80);
  currency                  : abap.cuky;
  @Semantics.amount.currencyCode : 'ztcfo_demo_item.currency'
  amount                    : abap.curr(23,2);   // always positive
  net_due_date              : abap.dats;
  clearing_date             : abap.dats;         // initial = open
  promised_date             : abap.dats;         // promise to pay (not in core FI - demo only)
  payment_block             : abap.char(1);
  block_reason              : abap.char(40);
  discount_pct              : abap.dec(5,2);
  discount_date             : abap.dats;
  purchase_order            : abap.char(10);
  plant                     : abap.char(4);
  item_text                 : abap.char(80);

}

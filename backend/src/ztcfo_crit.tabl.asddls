@EndUserText.label : 'CFO Brief - Operational criticality (PP/MM signal)'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #C
@AbapCatalog.dataMaintenance : #ALLOWED
define table ztcfo_crit {

  key client                : abap.clnt not null;
  key company_code          : abap.char(4) not null;
  key object_type           : abap.char(10) not null;   // PO / SUPPLIER / MATERIAL
  key object_id             : abap.char(40) not null;

  crit_level                : abap.char(1);      // H / M / L
  prod_line                 : abap.char(20);
  currency                  : abap.cuky;
  @Semantics.amount.currencyCode : 'ztcfo_crit.currency'
  revenue_at_risk           : abap.curr(23,2);   // e.g. quarterly orders fed by the line
  note                      : abap.char(120);

}

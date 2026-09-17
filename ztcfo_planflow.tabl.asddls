@EndUserText.label : 'CFO Brief - Planned non-AR/AP cash flows (payroll, tax, fees)'
@AbapCatalog.enhancement.category : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #A
@AbapCatalog.dataMaintenance : #RESTRICTED
define table ztcfo_planflow {

  key client                : abap.clnt not null;
  key company_code          : abap.char(4) not null;
  key flow_date             : abap.dats not null;
  key flow_no               : abap.numc(4) not null;

  currency                  : abap.cuky;
  @Semantics.amount.currencyCode : 'ztcfo_planflow.currency'
  amount                    : abap.curr(23,2);   // signed: + inflow, - outflow
  category                  : abap.char(10);     // PAYROLL / TAX / FEES / OTHER
  description               : abap.char(80);

}

@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'CFO Brief - Open AR/AP items (released basis)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType: { serviceQuality: #C, sizeCategory: #XL, dataClass: #TRANSACTIONAL }
/* Internal source for ZCL_CFO_SOURCE_LIVE - not exposed in any service.
   Access is controlled on the brief (ZCFO_BRF) that is built from it. */
define view entity ZI_CFO_OPENITEM
  as select from I_OperationalAcctgDocItem as Item
    left outer to one join I_Customer as Cust on Cust.Customer = Item.Customer
    left outer to one join I_Supplier as Supp on Supp.Supplier = Item.Supplier
{
  key Item.CompanyCode,
  key Item.AccountingDocument,
  key Item.FiscalYear,
  key Item.AccountingDocumentItem,

      Item.FinancialAccountType,
      case Item.FinancialAccountType
        when 'D' then Item.Customer
        else Item.Supplier
      end                                     as Partner,
      case Item.FinancialAccountType
        when 'D' then Cust.CustomerName
        else Supp.SupplierName
      end                                     as PartnerName,

      @Semantics.amount.currencyCode: 'CompanyCodeCurrency'
      Item.AmountInCompanyCodeCurrency,
      Item.CompanyCodeCurrency,

      Item.NetDueDate,
      Item.PaymentBlockingReason,
      Item.CashDiscount1Percent,
      dats_add_days( Item.DueCalculationBaseDate,
                     cast( Item.CashDiscount1Days as abap.int4 ),
                     'NULL' )                 as CashDiscount1Date,

      Item.PurchasingDocument,
      Item.Plant,
      Item.DocumentItemText
}
where
  (    Item.FinancialAccountType = 'D'
    or Item.FinancialAccountType = 'K' )
  and  Item.ClearingAccountingDocument = ''

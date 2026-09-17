@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'CFO Brief - Cleared invoices with days late'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType: { serviceQuality: #C, sizeCategory: #XL, dataClass: #TRANSACTIONAL }
/* Pay-date model input: customer invoices (debit) and supplier invoices (credit)
   that were cleared by another document. DaysLate < 0 = paid early. */
define view entity ZI_CFO_CLEARINGHIST
  as select from I_OperationalAcctgDocItem as Item
{
  key Item.CompanyCode,
  key Item.AccountingDocument,
  key Item.FiscalYear,
  key Item.AccountingDocumentItem,

      Item.FinancialAccountType,
      case Item.FinancialAccountType
        when 'D' then Item.Customer
        else Item.Supplier
      end                                              as Partner,

      @Semantics.amount.currencyCode: 'CompanyCodeCurrency'
      Item.AmountInCompanyCodeCurrency,
      Item.CompanyCodeCurrency,

      Item.NetDueDate,
      Item.ClearingDate,
      dats_days_between( Item.NetDueDate, Item.ClearingDate ) as DaysLate
}
where
  (    ( Item.FinancialAccountType = 'D' and Item.DebitCreditCode = 'S' )
    or ( Item.FinancialAccountType = 'K' and Item.DebitCreditCode = 'H' ) )
  and  Item.ClearingAccountingDocument <> ''
  and  Item.ClearingAccountingDocument <> Item.AccountingDocument
  and  Item.NetDueDate                 <> '00000000'

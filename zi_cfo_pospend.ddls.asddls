@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'CFO Brief - Purchase order spend by plant'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType: { serviceQuality: #C, sizeCategory: #L, dataClass: #TRANSACTIONAL }
define view entity ZI_CFO_PoSpend
  as select from I_PurchaseOrderItemAPI01 as Item
    inner join   I_PurchaseOrderAPI01     as Hdr on Hdr.PurchaseOrder = Item.PurchaseOrder
{
  key Item.PurchaseOrder,
  key Item.PurchaseOrderItem,

      Hdr.CompanyCode,
      Hdr.PurchaseOrderDate,
      Item.Plant,

      @Semantics.amount.currencyCode: 'DocumentCurrency'
      Item.NetAmount,
      Item.DocumentCurrency
}
where
  Item.PurchasingDocumentDeletionCode = ''

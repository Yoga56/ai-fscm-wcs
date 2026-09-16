# Data sources — clean core mapping

The engine reads core FI/MM through `ZIF_CFO_DATA_SOURCE`. `LIVE` mode uses released CDS views
only; everything that is not released is either simulated or pluggable.

## Mapping

| Framework says | Used instead | Why |
|---|---|---|
| `BSID` / `BSIK` (open items) | `I_OperationalAcctgDocItem` with `ClearingAccountingDocument = ''` → `ZI_CFO_OpenItem` | `BSID`/`BSIK` are compatibility views in S/4HANA and not released |
| `BSAD` / `BSAK` (clearing history) | `I_OperationalAcctgDocItem`, cleared by another document → `ZI_CFO_ClearingHist` (`DaysLate = ClearingDate − NetDueDate`) | same |
| `FEBAN` (bank actuals) | Sum of the bank G/L accounts in `I_JournalEntryItem` (ledger 0L, `ZTCFO_CONFIG-BANK_GL_FROM/TO`) | `FEBAN` is a transaction; `FEBKO`/`FEBEP` are not released. After bank-statement posting the G/L balance equals the bank balance. Swap in a released bank-statement view if your release has one. |
| `CDHDR` / `CDPOS` | not needed in v1: "held deliberately" is derived from the payment block on overdue items | change documents are not released for this purpose |
| `REGUH` / `REGUP` (F110 proposal) | simulated: open supplier items are assigned to the first weekly run *R* with *R* + 7 ≥ net due date (items blocked for anything but `R` are held) | not released. For the real proposal, implement `ZIF_CFO_DATA_SOURCE` in a tier-2 wrapper (classic ABAP, own software component) and register it with `ZCL_CFO_DATA_LOADER=>SET_SOURCE` |
| `EKPO` / `RESB` / `AFKO` (MM/PP signals) | `I_PurchaseOrderAPI01` + `I_PurchaseOrderItemAPI01` → `ZI_CFO_PoSpend`; criticality from `ZTCFO_CRIT` | PP criticality has no single released source; maintain `ZTCFO_CRIT` (PO / supplier → line, revenue at risk). Without it, trade-offs are flagged LOW confidence. |
| promise-to-pay dates | not available in core FI (that is FSCM Collections) | overdue receivables are expected `COLLECTION_LAG_BD` working days from today |

## Verify in your release (ADT → *Released Objects*, or ATC with `ABAP_CLOUD_READINESS`)

Field names were written against current S/4HANA Cloud documentation. Check them before activating
the `ZI_CFO_*` views:

- `I_OperationalAcctgDocItem`: `FinancialAccountType`, `Customer`, `Supplier`, `NetDueDate`,
  `ClearingDate`, `ClearingAccountingDocument`, `PaymentBlockingReason`, `CashDiscount1Percent`,
  `CashDiscount1Days`, `DueCalculationBaseDate`, `DebitCreditCode`, `PurchasingDocument`, `Plant`,
  `DocumentItemText`, `AmountInCompanyCodeCurrency`, `CompanyCodeCurrency`
- `I_JournalEntryItem`: `Ledger`, `GLAccount`, `PostingDate`, `AmountInCompanyCodeCurrency`
- `I_PurchaseOrderItemAPI01`: `NetAmount`, `DocumentCurrency`, `Plant`, `PurchasingDocumentDeletionCode`
- `I_PurchaseOrderAPI01`: `CompanyCode`, `PurchaseOrderDate`
- `I_Customer-CustomerName`, `I_Supplier-SupplierName`
- Released classes used: `CL_HTTP_DESTINATION_PROVIDER`, `CL_WEB_HTTP_CLIENT_MANAGER` (via the shared
  Gemini client), `CL_BCS_MAIL_MESSAGE`, `CL_BCS_MAIL_TEXTPART`, `CL_BALI_LOG`, `CL_BALI_HEADER_SETTER`,
  `CL_BALI_FREE_TEXT_SETTER`, `CL_BALI_LOG_DB`, `IF_APJ_DT_EXEC_OBJECT`, `IF_APJ_RT_EXEC_OBJECT`,
  `CL_ABAP_CONTEXT_INFO`, `CL_SYSTEM_UUID`

## Access

The `ZI_CFO_*` views have no access control of their own and are not exposed in any service.
Access is enforced on the brief (DCL `ZR_CFO_BRIEF` / `ZC_CFO_BRIEF`, authorization object
`ZCFO_BRF`) and by the instance authorization in the behavior pool. The released `I_*` views keep
their own DCLs when `I_JournalEntryItem` is read directly (bank balance), so the user — or the job
user — also needs G/L display authorization.

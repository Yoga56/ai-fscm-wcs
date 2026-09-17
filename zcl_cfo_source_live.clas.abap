"! <p class="shorttext synchronized">CFO Brief - LIVE data source (released CDS only)</p>
"! <p>Reads ZI_CFO_OPENITEM / ZI_CFO_CLEARINGHIST / ZI_CFO_POSPEND (built on
"! I_OperationalAcctgDocItem, I_Customer, I_Supplier, I_PurchaseOrderAPI01,
"! I_PurchaseOrderItemAPI01) and I_JournalEntryItem for the bank G/L balance.
"! See docs/data-sources.md for what to verify in your release.</p>
"! <p>Not available in core FI and therefore left initial: promise-to-pay dates.
"! The real F110 proposal (REGUH/REGUP) is not released - the run is simulated from
"! open items and the configured run weekday instead.</p>
CLASS zcl_cfo_source_live DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_cfo_data_source.

  PRIVATE SECTION.
    CONSTANTS c_leading_ledger TYPE c LENGTH 2 VALUE '0L'.
    CONSTANTS c_window_days    TYPE i VALUE 30.
    CONSTANTS c_windows        TYPE i VALUE 4.
ENDCLASS.


CLASS zcl_cfo_source_live IMPLEMENTATION.

  METHOD zif_cfo_data_source~bank_balance.

    IF is_config-bank_gl_from IS INITIAL.
      zcx_cc_error=>raise( |Bank G/L range not configured for company code { is_config-company_code }| ).
    ENDIF.

    DATA(lv_to) = COND #( WHEN is_config-bank_gl_to IS INITIAL THEN is_config-bank_gl_from
                          ELSE is_config-bank_gl_to ).

    SELECT FROM i_journalentryitem
      FIELDS SUM( amountincompanycodecurrency ) AS balance
      WHERE companycode  = @is_config-company_code
        AND ledger       = @c_leading_ledger
        AND glaccount   BETWEEN @is_config-bank_gl_from AND @lv_to
        AND postingdate <= @iv_key_date
      INTO @DATA(lv_balance).

    rv_amount = lv_balance.

  ENDMETHOD.


  METHOD zif_cfo_data_source~open_items.

    SELECT FROM zi_cfo_openitem
      FIELDS AccountingDocument, FiscalYear, AccountingDocumentItem,
             FinancialAccountType, Partner, PartnerName,
             AmountInCompanyCodeCurrency, NetDueDate, PaymentBlockingReason,
             CashDiscount1Percent, CashDiscount1Date, PurchasingDocument, Plant, DocumentItemText
      WHERE CompanyCode = @is_config-company_code
      INTO TABLE @DATA(lt_rows).

    LOOP AT lt_rows INTO DATA(ls_row).
      " supplier invoices are credit postings - turn them into positive "to pay" amounts
      DATA(lv_amount) = CONV zif_cfo_types=>amount( ls_row-AmountInCompanyCodeCurrency ).
      IF ls_row-FinancialAccountType = zif_cfo_types=>account_type-supplier.
        lv_amount = - lv_amount.
      ENDIF.

      APPEND VALUE #( doc_id         = |{ ls_row-AccountingDocument }/{ ls_row-FiscalYear }/{ ls_row-AccountingDocumentItem }|
                      account_type   = ls_row-FinancialAccountType
                      partner        = ls_row-Partner
                      partner_name   = ls_row-PartnerName
                      amount         = lv_amount
                      net_due_date   = ls_row-NetDueDate
                      payment_block  = ls_row-PaymentBlockingReason
                      discount_pct   = ls_row-CashDiscount1Percent
                      discount_date  = ls_row-CashDiscount1Date
                      purchase_order = ls_row-PurchasingDocument
                      plant          = ls_row-Plant
                      item_text      = ls_row-DocumentItemText ) TO rt_items.
    ENDLOOP.

  ENDMETHOD.


  METHOD zif_cfo_data_source~history.

    DATA(lv_from) = iv_key_date - COND i( WHEN is_config-history_days > 0 THEN is_config-history_days ELSE 365 ).

    SELECT FROM zi_cfo_clearinghist
      FIELDS FinancialAccountType, Partner, AmountInCompanyCodeCurrency, NetDueDate, ClearingDate, DaysLate
      WHERE CompanyCode  = @is_config-company_code
        AND ClearingDate BETWEEN @lv_from AND @iv_key_date
      INTO TABLE @DATA(lt_rows).

    rt_history = VALUE #( FOR ls_row IN lt_rows
                          ( account_type  = ls_row-FinancialAccountType
                            partner       = ls_row-Partner
                            amount        = abs( ls_row-AmountInCompanyCodeCurrency )
                            net_due_date  = ls_row-NetDueDate
                            clearing_date = ls_row-ClearingDate
                            days_late     = ls_row-DaysLate ) ).

  ENDMETHOD.


  METHOD zif_cfo_data_source~spend.

    DATA(lv_from) = iv_key_date - c_window_days * c_windows + 1.

    SELECT FROM zi_cfo_pospend
      FIELDS Plant, PurchaseOrderDate, NetAmount
      WHERE CompanyCode      = @is_config-company_code
        AND DocumentCurrency = @is_config-currency
        AND PurchaseOrderDate BETWEEN @lv_from AND @iv_key_date
      INTO TABLE @DATA(lt_rows).

    LOOP AT lt_rows INTO DATA(ls_row).
      DATA(lv_window) = CONV i( ( iv_key_date - ls_row-PurchaseOrderDate ) DIV c_window_days ).
      ASSIGN rt_spend[ plant = ls_row-Plant window_no = lv_window ] TO FIELD-SYMBOL(<ls_spend>).
      IF sy-subrc <> 0.
        APPEND VALUE #( plant = ls_row-Plant window_no = lv_window ) TO rt_spend ASSIGNING <ls_spend>.
      ENDIF.
      <ls_spend>-amount += ls_row-NetAmount.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

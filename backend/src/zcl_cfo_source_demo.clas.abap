"! <p class="shorttext synchronized">CFO Brief - DEMO data source (seeded tables)</p>
CLASS zcl_cfo_source_demo DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_cfo_data_source.
ENDCLASS.


CLASS zcl_cfo_source_demo IMPLEMENTATION.

  METHOD zif_cfo_data_source~bank_balance.
    SELECT SINGLE FROM ztcfo_demo_misc
      FIELDS amount
      WHERE company_code = @is_config-company_code
        AND record_type  = 'BANK'
      INTO @DATA(lv_amount).
    IF sy-subrc <> 0.
      zcx_cc_error=>raise( |No demo bank balance for company code { is_config-company_code } - run ZCL_CFO_DEMO_SEED| ).
    ENDIF.
    rv_amount = lv_amount.
  ENDMETHOD.


  METHOD zif_cfo_data_source~open_items.
    SELECT FROM ztcfo_demo_item
      FIELDS *
      WHERE company_code  = @is_config-company_code
        AND clearing_date = '00000000'
      ORDER BY doc_id
      INTO TABLE @DATA(lt_rows).

    rt_items = CORRESPONDING #( lt_rows ).
  ENDMETHOD.


  METHOD zif_cfo_data_source~history.
    SELECT FROM ztcfo_demo_item
      FIELDS account_type, partner, amount, net_due_date, clearing_date
      WHERE company_code  =  @is_config-company_code
        AND clearing_date <> '00000000'
      ORDER BY doc_id
      INTO TABLE @DATA(lt_rows).

    LOOP AT lt_rows INTO DATA(ls_row).
      APPEND VALUE #( account_type  = ls_row-account_type
                      partner       = ls_row-partner
                      amount        = ls_row-amount
                      net_due_date  = ls_row-net_due_date
                      clearing_date = ls_row-clearing_date
                      days_late     = ls_row-clearing_date - ls_row-net_due_date ) TO rt_history.
    ENDLOOP.
  ENDMETHOD.


  METHOD zif_cfo_data_source~spend.
    SELECT FROM ztcfo_demo_misc
      FIELDS object_id, window_no, amount
      WHERE company_code = @is_config-company_code
        AND record_type  = 'SPEND'
      ORDER BY object_id, window_no
      INTO TABLE @DATA(lt_rows).

    rt_spend = VALUE #( FOR ls_row IN lt_rows
                        ( plant = ls_row-object_id window_no = ls_row-window_no amount = ls_row-amount ) ).
  ENDMETHOD.

ENDCLASS.

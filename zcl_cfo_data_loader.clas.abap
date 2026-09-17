"! <p class="shorttext synchronized">CFO Brief - assembles the engine input</p>
"! <p>Configuration, ledger data (LIVE or DEMO source), planned flows, criticality
"! and the previous brief's overdue figures for the variance lines.</p>
CLASS zcl_cfo_data_loader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    CLASS-METHODS read_config
      IMPORTING iv_company_code  TYPE clike
      RETURNING VALUE(rs_config) TYPE zif_cfo_types=>ty_config
      RAISING   zcx_cc_error.

    "! Replace the data source (tier-2 wrapper, tests). Pass nothing to reset.
    CLASS-METHODS set_source
      IMPORTING io_source TYPE REF TO zif_cfo_data_source OPTIONAL.

    "! The key date defaults to today (LIVE) or the seeded anchor (DEMO).
    METHODS load
      IMPORTING iv_company_code TYPE clike
                iv_key_date     TYPE d OPTIONAL
      RETURNING VALUE(rs_input) TYPE zif_cfo_types=>ty_input
      RAISING   zcx_cc_error.

  PRIVATE SECTION.

    CLASS-DATA go_source TYPE REF TO zif_cfo_data_source.

    METHODS source
      IMPORTING is_config        TYPE zif_cfo_types=>ty_config
      RETURNING VALUE(ro_source) TYPE REF TO zif_cfo_data_source.

ENDCLASS.


CLASS zcl_cfo_data_loader IMPLEMENTATION.

  METHOD read_config.
    SELECT SINGLE FROM ztcfo_config FIELDS *
      WHERE company_code = @iv_company_code
      INTO @rs_config.
    IF sy-subrc <> 0.
      zcx_cc_error=>raise( |Company code { iv_company_code } is not configured in ZTCFO_CONFIG | &&
                           |(run ZCL_CFO_DEMO_SEED for the demo)| ).
    ENDIF.
    IF rs_config-currency IS INITIAL OR rs_config-horizon_days <= 0.
      zcx_cc_error=>raise( |Configuration for company code { iv_company_code } is incomplete| ).
    ENDIF.
  ENDMETHOD.


  METHOD set_source.
    go_source = io_source.
  ENDMETHOD.


  METHOD source.
    IF go_source IS BOUND.
      ro_source = go_source.
    ELSEIF is_config-data_mode = zif_cfo_types=>data_mode-demo.
      ro_source = NEW zcl_cfo_source_demo( ).
    ELSE.
      ro_source = NEW zcl_cfo_source_live( ).
    ENDIF.
  ENDMETHOD.


  METHOD load.

    rs_input-config = read_config( iv_company_code ).

    rs_input-key_date = COND #(
      WHEN iv_key_date IS NOT INITIAL THEN iv_key_date
      WHEN rs_input-config-data_mode = zif_cfo_types=>data_mode-demo
       AND rs_input-config-demo_anchor_date IS NOT INITIAL THEN rs_input-config-demo_anchor_date
      ELSE zcl_cfo_calendar=>today( ) ).

    DATA(lo_source) = source( rs_input-config ).
    DATA(lv_key)    = rs_input-key_date.
    DATA(lv_to)     = lv_key + rs_input-config-horizon_days.

    rs_input-opening_cash = lo_source->bank_balance( is_config = rs_input-config iv_key_date = lv_key ).
    rs_input-items        = lo_source->open_items(   is_config = rs_input-config iv_key_date = lv_key ).
    rs_input-history      = lo_source->history(      is_config = rs_input-config iv_key_date = lv_key ).
    rs_input-spend        = lo_source->spend(        is_config = rs_input-config iv_key_date = lv_key ).

    SELECT FROM ztcfo_planflow
      FIELDS flow_date, amount, description
      WHERE company_code = @rs_input-config-company_code
        AND flow_date BETWEEN @lv_key AND @lv_to
      ORDER BY flow_date, flow_no
      INTO TABLE @DATA(lt_plan).
    rs_input-planned = VALUE #( FOR ls_plan IN lt_plan
                                ( flow_date   = ls_plan-flow_date
                                  amount      = ls_plan-amount
                                  description = ls_plan-description ) ).

    SELECT FROM ztcfo_crit FIELDS *
      WHERE company_code = @rs_input-config-company_code
      INTO TABLE @rs_input-crit.

    SELECT FROM ztcfo_brief
      FIELDS ar_overdue, ap_overdue
      WHERE company_code = @rs_input-config-company_code
        AND brief_date   < @lv_key
      ORDER BY brief_date DESCENDING, created_at DESCENDING
      INTO TABLE @DATA(lt_prev)
      UP TO 1 ROWS.
    IF lt_prev IS NOT INITIAL.
      rs_input-prev_ar_overdue = lt_prev[ 1 ]-ar_overdue.
      rs_input-prev_ap_overdue = lt_prev[ 1 ]-ap_overdue.
    ENDIF.

  ENDMETHOD.

ENDCLASS.

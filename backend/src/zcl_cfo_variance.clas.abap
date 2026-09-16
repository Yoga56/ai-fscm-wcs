"! <p class="shorttext synchronized">CFO Brief - E: position, variance and patterns</p>
"! <p>Explains why a number moved: overdue AR/AP versus the previous brief,
"! whether overdue AP is held on purpose (payment block), plant spend against
"! the trailing average, and how unusual a supplier invoice is (z-score).</p>
CLASS zcl_cfo_variance DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_position,
             ar_total           TYPE zif_cfo_types=>amount,
             ar_overdue         TYPE zif_cfo_types=>amount,
             ar_overdue_chg_pct TYPE decfloat34,
             ap_total           TYPE zif_cfo_types=>amount,
             ap_overdue         TYPE zif_cfo_types=>amount,
             ap_overdue_chg_pct TYPE decfloat34,
             ap_due_window      TYPE zif_cfo_types=>amount,
             ap_held_share      TYPE decfloat34,
             top_overdue_name   TYPE c LENGTH 80,
             top_overdue_amount TYPE zif_cfo_types=>amount,
           END OF ty_position.

    TYPES: BEGIN OF ty_zscore,
             valid TYPE abap_bool,
             mean  TYPE zif_cfo_types=>amount,
             sd    TYPE decfloat34,
             z     TYPE decfloat34,
           END OF ty_zscore.

    TYPES: BEGIN OF ty_spend_signal,
             plant      TYPE c LENGTH 4,
             current    TYPE zif_cfo_types=>amount,
             average    TYPE zif_cfo_types=>amount,
             delta      TYPE zif_cfo_types=>amount,
             change_pct TYPE decfloat34,
           END OF ty_spend_signal,
           tt_spend_signal TYPE STANDARD TABLE OF ty_spend_signal WITH EMPTY KEY.

    METHODS constructor
      IMPORTING is_input TYPE zif_cfo_types=>ty_input.

    METHODS position
      RETURNING VALUE(rs_position) TYPE ty_position.

    "! Plants whose last-30-day spend is above the threshold versus the prior windows.
    METHODS spend_signals
      RETURNING VALUE(rt_signals) TYPE tt_spend_signal.

    METHODS explains
      IMPORTING is_position        TYPE ty_position
                it_signals         TYPE tt_spend_signal
      RETURNING VALUE(rt_explains) TYPE zif_cfo_types=>tt_explain.

    "! How many standard deviations the amount sits above the supplier's cleared invoices.
    METHODS supplier_zscore
      IMPORTING iv_partner       TYPE clike
                iv_amount        TYPE zif_cfo_types=>amount
      RETURNING VALUE(rs_zscore) TYPE ty_zscore.

    CLASS-METHODS change_pct
      IMPORTING iv_now        TYPE zif_cfo_types=>amount
                iv_previous   TYPE zif_cfo_types=>amount
      RETURNING VALUE(rv_pct) TYPE decfloat34.

  PRIVATE SECTION.

    DATA ms_input TYPE zif_cfo_types=>ty_input.

ENDCLASS.


CLASS zcl_cfo_variance IMPLEMENTATION.

  METHOD constructor.
    ms_input = is_input.
  ENDMETHOD.


  METHOD change_pct.
    IF iv_previous <> 0.
      rv_pct = round( val = ( iv_now - iv_previous ) / iv_previous * 100 dec = 1 ).
    ENDIF.
  ENDMETHOD.


  METHOD position.

    DATA lv_ap_held TYPE zif_cfo_types=>amount.
    DATA(lv_key)    = ms_input-key_date.
    DATA(lv_window) = ms_input-config-ap_window_days.

    LOOP AT ms_input-items INTO DATA(ls_item).
      DATA(lv_offset) = CONV i( ls_item-net_due_date - lv_key ).

      IF ls_item-account_type = zif_cfo_types=>account_type-customer.
        rs_position-ar_total += ls_item-amount.
        IF lv_offset < 0.
          rs_position-ar_overdue += ls_item-amount.
          IF ls_item-amount > rs_position-top_overdue_amount.
            rs_position-top_overdue_amount = ls_item-amount.
            rs_position-top_overdue_name   = ls_item-partner_name.
          ENDIF.
        ENDIF.
        CONTINUE.
      ENDIF.

      rs_position-ap_total += ls_item-amount.
      DATA(lv_in_runs) = xsdbool( ls_item-payment_block IS INITIAL
                               OR ls_item-payment_block = zif_cfo_types=>c_block_price_variance ).
      IF lv_offset < 0.
        rs_position-ap_overdue += ls_item-amount.
        IF lv_in_runs = abap_false.
          lv_ap_held += ls_item-amount.
        ENDIF.
      ELSEIF lv_offset <= lv_window AND lv_in_runs = abap_true.
        rs_position-ap_due_window += ls_item-amount.
      ENDIF.
    ENDLOOP.

    rs_position-ar_overdue_chg_pct = change_pct( iv_now = rs_position-ar_overdue iv_previous = ms_input-prev_ar_overdue ).
    rs_position-ap_overdue_chg_pct = change_pct( iv_now = rs_position-ap_overdue iv_previous = ms_input-prev_ap_overdue ).
    IF rs_position-ap_overdue <> 0.
      rs_position-ap_held_share = lv_ap_held / rs_position-ap_overdue.
    ENDIF.

  ENDMETHOD.


  METHOD spend_signals.

    TYPES ty_plant TYPE c LENGTH 4.
    DATA lt_plants TYPE STANDARD TABLE OF ty_plant WITH EMPTY KEY.

    LOOP AT ms_input-spend INTO DATA(ls_spend).
      IF NOT line_exists( lt_plants[ table_line = ls_spend-plant ] ).
        APPEND ls_spend-plant TO lt_plants.
      ENDIF.
    ENDLOOP.

    LOOP AT lt_plants INTO DATA(lv_plant).
      DATA(ls_signal) = VALUE ty_spend_signal( plant = lv_plant ).
      DATA(lv_prior)  = 0.
      DATA(lv_sum)    = CONV zif_cfo_types=>amount( 0 ).

      LOOP AT ms_input-spend INTO ls_spend WHERE plant = lv_plant.
        IF ls_spend-window_no = 0.
          ls_signal-current += ls_spend-amount.
        ELSE.
          lv_sum   += ls_spend-amount.
          lv_prior += 1.
        ENDIF.
      ENDLOOP.

      IF lv_prior = 0 OR lv_sum = 0.
        CONTINUE.
      ENDIF.

      ls_signal-average    = lv_sum / lv_prior.
      ls_signal-change_pct = round( val = ( ls_signal-current - ls_signal-average ) / ls_signal-average * 100 dec = 1 ).
      ls_signal-delta      = round( val = ls_signal-current - ls_signal-average dec = 2 ).

      IF ls_signal-change_pct >= ms_input-config-spend_threshold_pct.
        APPEND ls_signal TO rt_signals.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD explains.

    DATA(lv_currency) = ms_input-config-currency.
    DATA(ls_pos)      = is_position.

    APPEND VALUE #(
      code       = 'AR_OVERDUE'
      change_pct = ls_pos-ar_overdue_chg_pct
      text       = |AR overdue { COND string( WHEN ls_pos-ar_overdue_chg_pct >= 0 THEN `up` ELSE `down` ) } | &&
                   |{ zcl_cfo_format=>percent( ls_pos-ar_overdue_chg_pct ) }| &&
                   COND string( WHEN ls_pos-top_overdue_name IS NOT INITIAL
                                THEN |, mostly { condense( CONV string( ls_pos-top_overdue_name ) ) } | &&
                                     |({ zcl_cfo_format=>money( iv_amount = ls_pos-top_overdue_amount iv_currency = lv_currency ) })| ) )
      TO rt_explains.

    APPEND VALUE #(
      code       = 'AP_OVERDUE'
      change_pct = ls_pos-ap_overdue_chg_pct
      text       = |AP overdue { COND string( WHEN ls_pos-ap_overdue_chg_pct >= 0 THEN `up` ELSE `down` ) } | &&
                   |{ zcl_cfo_format=>percent( ls_pos-ap_overdue_chg_pct ) }| &&
                   COND string( WHEN ls_pos-ap_held_share >= CONV decfloat34( '0.5' ) THEN ` (held deliberately)` ) )
      TO rt_explains.

    LOOP AT it_signals INTO DATA(ls_signal).
      APPEND VALUE #(
        code       = 'SPEND'
        change_pct = ls_signal-change_pct
        text       = |Plant { ls_signal-plant } spend up { zcl_cfo_format=>percent( ls_signal-change_pct ) } | &&
                     |({ zcl_cfo_format=>money( iv_amount = ls_signal-delta iv_currency = lv_currency ) })| )
        TO rt_explains.
    ENDLOOP.

  ENDMETHOD.


  METHOD supplier_zscore.

    DATA lv_n   TYPE i.
    DATA lv_sum TYPE zif_cfo_types=>amount.
    DATA lv_var TYPE decfloat34.

    LOOP AT ms_input-history INTO DATA(ls_hist)
         WHERE account_type = zif_cfo_types=>account_type-supplier
           AND partner      = iv_partner.
      lv_n   += 1.
      lv_sum += ls_hist-amount.
    ENDLOOP.

    IF lv_n < ms_input-config-min_history OR lv_n < 2.
      RETURN.
    ENDIF.

    rs_zscore-mean = lv_sum / lv_n.
    LOOP AT ms_input-history INTO ls_hist
         WHERE account_type = zif_cfo_types=>account_type-supplier
           AND partner      = iv_partner.
      lv_var += ( ls_hist-amount - rs_zscore-mean ) ** 2.
    ENDLOOP.

    rs_zscore-sd = sqrt( lv_var / ( lv_n - 1 ) ).
    IF rs_zscore-sd = 0.
      RETURN.
    ENDIF.

    rs_zscore-z     = ( iv_amount - rs_zscore-mean ) / rs_zscore-sd.
    rs_zscore-valid = abap_true.

  ENDMETHOD.

ENDCLASS.

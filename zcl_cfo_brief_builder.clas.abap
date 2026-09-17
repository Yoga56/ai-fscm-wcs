"! <p class="shorttext synchronized">CFO Brief - orchestrator (rule path)</p>
"! <p>P -&gt; E -&gt; R -&gt; A on one input snapshot, plus the template headline and
"! narrative. Deterministic: the same input always gives the same numbers.
"! ZCL_CFO_AI_ADVISOR may rewrite the words afterwards, never the numbers.</p>
CLASS zcl_cfo_brief_builder DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS build
      IMPORTING is_input         TYPE zif_cfo_types=>ty_input
                is_sim           TYPE zif_cfo_types=>ty_sim OPTIONAL
      RETURNING VALUE(rs_result) TYPE zif_cfo_types=>ty_result
      RAISING   zcx_cfo_error.

ENDCLASS.


CLASS zcl_cfo_brief_builder IMPLEMENTATION.

  METHOD build.

    TYPES ty_partner TYPE c LENGTH 10.
    DATA lt_vendors TYPE SORTED TABLE OF ty_partner WITH UNIQUE KEY table_line.

    DATA(ls_cfg) = is_input-config.
    DATA(lv_key) = is_input-key_date.
    DATA(lv_cur) = ls_cfg-currency.

    IF ls_cfg-horizon_days <= 0 OR ls_cfg-run_weekday NOT BETWEEN 1 AND 7.
      zcx_cfo_error=>raise( |Configuration for company code { ls_cfg-company_code } is incomplete (horizon / run weekday)| ).
    ENDIF.

    DATA(lv_floor) = COND zif_cfo_types=>amount( WHEN is_sim-floor_override > 0 THEN is_sim-floor_override
                                                 ELSE ls_cfg-liquidity_floor ).

    " ---- P: flows and runway ----------------------------------------------
    DATA(lo_runway)  = NEW zcl_cfo_runway( is_input ).
    rs_result-runs   = lo_runway->run_dates( ).
    rs_result-flows  = lo_runway->cash_flows( is_sim ).
    rs_result-days   = lo_runway->project( it_flows = rs_result-flows iv_floor = lv_floor ).

    DATA(ls_low)     = zcl_cfo_runway=>low( rs_result-days ).
    DATA(ls_low_x)   = zcl_cfo_runway=>low( it_days = rs_result-days iv_path = zif_cfo_types=>path-stressed ).
    rs_result-days[ day_index = ls_low-day_index ]-is_low_point = abap_true.

    DATA(lv_run0)    = rs_result-runs[ 1 ].
    DATA(lv_run1)    = rs_result-runs[ 2 ].
    DATA(lv_off0)    = CONV i( lv_run0 - lv_key ).
    DATA(lv_off1)    = CONV i( lv_run1 - lv_key ).
    DATA(lv_holds)   = xsdbool( zcl_cfo_runway=>low( it_days = rs_result-days
                                                     iv_from = lv_off0
                                                     iv_to   = lv_off1 - 1 )-closing_scheduled >= lv_floor ).

    DATA lv_run_total TYPE zif_cfo_types=>amount.
    DATA lv_run_count TYPE i.
    LOOP AT rs_result-flows INTO DATA(ls_flow) WHERE in_current_run = abap_true.
      lv_run_total -= ls_flow-amount.
      lv_run_count += 1.
      INSERT CONV ty_partner( ls_flow-partner ) INTO TABLE lt_vendors.
    ENDLOOP.

    " ---- E: position and variance -----------------------------------------
    DATA(lo_variance)  = NEW zcl_cfo_variance( is_input ).
    DATA(ls_position)  = lo_variance->position( ).
    DATA(lt_signals)   = lo_variance->spend_signals( ).
    rs_result-explains = lo_variance->explains( is_position = ls_position it_signals = lt_signals ).

    " ---- R: rank ------------------------------------------------------------
    rs_result-risks = NEW zcl_cfo_risk_ranker( )->rank( is_input    = is_input
                                                        it_flows    = rs_result-flows
                                                        it_days     = rs_result-days
                                                        it_runs     = rs_result-runs
                                                        iv_floor    = lv_floor
                                                        io_variance = lo_variance
                                                        it_signals  = lt_signals ).

    " ---- A: advise ----------------------------------------------------------
    rs_result-advice = NEW zcl_cfo_tradeoff( )->advise( is_input = is_input
                                                        it_flows = rs_result-flows
                                                        it_days  = rs_result-days
                                                        it_runs  = rs_result-runs
                                                        it_risks = rs_result-risks
                                                        iv_floor = lv_floor ).

    " ---- header -------------------------------------------------------------
    DATA(lv_review) = 0.
    LOOP AT rs_result-risks TRANSPORTING NO FIELDS
         WHERE risk_type = zif_cfo_types=>risk_type-ap_offpattern
            OR risk_type = zif_cfo_types=>risk_type-ap_blocked.
      lv_review += 1.
    ENDLOOP.
    LOOP AT rs_result-advice TRANSPORTING NO FIELDS WHERE kind = zif_cfo_types=>advice_kind-prioritize.
      lv_review += 1.
    ENDLOOP.

    DATA(lv_after_run) = rs_result-days[ day_index = lv_off0 ]-closing_scheduled.

    rs_result-brief = VALUE #(
      company_code       = ls_cfg-company_code
      brief_date         = lv_key
      data_mode          = ls_cfg-data_mode
      currency           = lv_cur
      horizon_days       = ls_cfg-horizon_days
      cash_today         = is_input-opening_cash
      liquidity_floor    = lv_floor
      run_date           = lv_run0
      next_run_date      = lv_run1
      run_total          = lv_run_total
      run_invoice_count  = lv_run_count
      run_vendor_count   = lines( lt_vendors )
      cash_after_run     = lv_after_run
      run_holds_floor    = lv_holds
      low_point          = ls_low-closing_scheduled
      low_point_day      = ls_low-day_index
      low_point_date     = lv_key + ls_low-day_index
      stressed_low_point = ls_low_x-closing_stressed
      stressed_low_day   = ls_low_x-day_index
      headroom           = ls_low-closing_scheduled - lv_floor
      floor_breach       = xsdbool( ls_low_x-closing_stressed < lv_floor )
      scheduled_breach   = xsdbool( ls_low-closing_scheduled < lv_floor )
      ar_total           = ls_position-ar_total
      ar_overdue         = ls_position-ar_overdue
      ar_overdue_chg_pct = ls_position-ar_overdue_chg_pct
      ap_total           = ls_position-ap_total
      ap_due_window      = ls_position-ap_due_window
      ap_overdue         = ls_position-ap_overdue
      ap_overdue_chg_pct = ls_position-ap_overdue_chg_pct
      review_count       = lv_review
      engine             = zif_cfo_types=>engine-rule ).

    rs_result-brief-headline =
      |This week's run { COND string( WHEN lv_holds = abap_true THEN `holds above` ELSE `breaches the` ) } floor | &&
      |— { lv_review } item{ COND string( WHEN lv_review <> 1 THEN `s` ) } to review|.

    " template narrative - the AI may replace it, the numbers stay
    rs_result-brief-narrative =
      |This week's proposal ({ zcl_cfo_format=>money( iv_amount = lv_run_total iv_currency = lv_cur ) }) is built and | &&
      |{ COND string( WHEN lv_holds = abap_true THEN `clears` ELSE `breaks` ) } the floor — | &&
      |{ zcl_cfo_format=>count_word( lv_review ) } | &&
      |{ COND string( WHEN lv_review = 1 THEN `item needs` ELSE `items need` ) } you; the rest flows through. | &&
      |Cash { zcl_cfo_format=>money( iv_amount = is_input-opening_cash iv_currency = lv_cur ) } today → | &&
      |{ zcl_cfo_format=>money( iv_amount = lv_after_run iv_currency = lv_cur ) } after | &&
      |{ zcl_cfo_calendar=>short_text( lv_run0 ) }'s run. | &&
      |Low point { zcl_cfo_format=>money( iv_amount = ls_low-closing_scheduled iv_currency = lv_cur ) } | &&
      |on Day { ls_low-day_index } (floor { zcl_cfo_format=>money( iv_amount = lv_floor iv_currency = lv_cur ) })|.

    LOOP AT rs_result-risks INTO DATA(ls_lead) WHERE risk_type = zif_cfo_types=>risk_type-ar_late.
      rs_result-brief-narrative =
        |{ rs_result-brief-narrative }. If { zcl_cfo_format=>possessive( ls_lead-partner_name ) } | &&
        |{ zcl_cfo_format=>money( iv_amount = ls_lead-exposure iv_currency = lv_cur ) } pays late | &&
        |(~{ zcl_cfo_format=>number( iv_value = ls_lead-probability * 100 iv_max_decimals = 0 ) }%) → | &&
        |{ zcl_cfo_format=>money( iv_amount = ls_low_x-closing_stressed iv_currency = lv_cur ) }| &&
        |{ COND string( WHEN ls_low_x-closing_stressed < lv_floor THEN ` — below floor` ) }|.
      EXIT.
    ENDLOOP.
    rs_result-brief-narrative = |{ rs_result-brief-narrative }.|.

    LOOP AT rs_result-explains INTO DATA(ls_explain).
      rs_result-brief-explain_text = COND #( WHEN sy-tabix = 1 THEN ls_explain-text
                                             ELSE rs_result-brief-explain_text
                                                  && cl_abap_char_utilities=>newline && ls_explain-text ).
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

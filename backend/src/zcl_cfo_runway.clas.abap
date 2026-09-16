"! <p class="shorttext synchronized">CFO Brief - P: cash flows and liquidity runway</p>
"! <p>Three paths per day:
"! <ul><li><strong>scheduled</strong> - receipts on promise/due date, payables in their F110 run</li>
"! <li><strong>stressed</strong> - receipts with P(late) above the threshold arrive their average delay later</li>
"! <li><strong>expected</strong> - probability-weighted mix of the two</li></ul>
"! Payables are assigned to the first weekly run R with R + 7 &gt;= net due date,
"! which is how F110 picks items when the next run date is maintained.</p>
CLASS zcl_cfo_runway DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING is_input TYPE zif_cfo_types=>ty_input.

    "! Weekly run dates from the key date to 60 days past the horizon.
    METHODS run_dates
      RETURNING VALUE(rt_runs) TYPE zif_cfo_types=>tt_date.

    METHODS cash_flows
      IMPORTING is_sim          TYPE zif_cfo_types=>ty_sim OPTIONAL
      RETURNING VALUE(rt_flows) TYPE zif_cfo_types=>tt_flow.

    METHODS project
      IMPORTING it_flows       TYPE zif_cfo_types=>tt_flow
                iv_floor       TYPE zif_cfo_types=>amount
      RETURNING VALUE(rt_days) TYPE zif_cfo_types=>tt_day.

    "! First day with the lowest closing on the given path within [from, to].
    CLASS-METHODS low
      IMPORTING it_days       TYPE zif_cfo_types=>tt_day
                iv_path       TYPE c DEFAULT zif_cfo_types=>path-scheduled
                iv_from       TYPE i DEFAULT 0
                iv_to         TYPE i DEFAULT 99999
      RETURNING VALUE(rs_day) TYPE zif_cfo_types=>ty_day.

    CLASS-METHODS closing
      IMPORTING is_day           TYPE zif_cfo_types=>ty_day
                iv_path          TYPE c
      RETURNING VALUE(rv_amount) TYPE zif_cfo_types=>amount.

    METHODS predictor
      RETURNING VALUE(ro_predictor) TYPE REF TO zcl_cfo_paydate_predictor.

  PRIVATE SECTION.

    DATA ms_input     TYPE zif_cfo_types=>ty_input.
    DATA mt_runs      TYPE zif_cfo_types=>tt_date.
    DATA mo_predictor TYPE REF TO zcl_cfo_paydate_predictor.

ENDCLASS.


CLASS zcl_cfo_runway IMPLEMENTATION.

  METHOD constructor.
    ms_input     = is_input.
    mo_predictor = NEW #( it_history     = is_input-history
                          iv_min_history = CONV #( is_input-config-min_history ) ).
    mt_runs      = run_dates( ).
  ENDMETHOD.


  METHOD predictor.
    ro_predictor = mo_predictor.
  ENDMETHOD.


  METHOD run_dates.
    DATA(lv_run) = ms_input-key_date.
    WHILE zcl_cfo_calendar=>weekday( lv_run ) <> ms_input-config-run_weekday.
      lv_run = lv_run + 1.
    ENDWHILE.

    DATA(lv_last) = ms_input-key_date + ms_input-config-horizon_days + 60.
    WHILE lv_run <= lv_last.
      APPEND lv_run TO rt_runs.
      lv_run = lv_run + 7.
    ENDWHILE.
  ENDMETHOD.


  METHOD cash_flows.

    DATA ls_flow TYPE zif_cfo_types=>ty_flow.
    DATA(ls_cfg) = ms_input-config.
    DATA(lv_key) = ms_input-key_date.

    LOOP AT ms_input-items INTO DATA(ls_item).

      ls_flow = CORRESPONDING #( ls_item MAPPING due_date = net_due_date ).

      IF ls_item-account_type = zif_cfo_types=>account_type-customer.

        DATA(ls_beh) = mo_predictor->behaviour( ls_item-partner ).

        IF ls_item-promised_date IS NOT INITIAL.
          ls_flow-sched_date = ls_item-promised_date.
        ELSEIF ls_item-net_due_date >= lv_key.
          ls_flow-sched_date = zcl_cfo_calendar=>next_working_day( ls_item-net_due_date ).
        ELSE.
          ls_flow-sched_date = zcl_cfo_calendar=>add_working_days( iv_date = lv_key
                                                                   iv_days = CONV #( ls_cfg-collection_lag_bd ) ).
        ENDIF.

        IF line_exists( is_sim-factor_ids[ table_line = ls_item-doc_id ] ).
          ls_flow-kind        = zif_cfo_types=>flow_kind-factoring.
          ls_flow-amount      = round( val = ls_item-amount * ls_cfg-factoring_advance_pct / 100 dec = 2 ).
          ls_flow-sched_date  = zcl_cfo_calendar=>add_working_days( iv_date = lv_key
                                                                    iv_days = CONV #( ls_cfg-factoring_lead_bd ) ).
          ls_flow-stress_date = ls_flow-sched_date.
          APPEND ls_flow TO rt_flows.
          CONTINUE.
        ENDIF.

        DATA(lv_forced) = xsdbool( line_exists( is_sim-late_ids[ table_line = ls_item-doc_id ] ) ).
        DATA(lv_shift)  = COND i( WHEN lv_forced = abap_true THEN max( ls_beh-mean_late, 1 )
                                  ELSE ls_beh-mean_late ).

        ls_flow-kind      = zif_cfo_types=>flow_kind-receivable.
        ls_flow-p_late    = ls_beh-p_late.
        ls_flow-mean_late = ls_beh-mean_late.
        ls_flow-hist_n    = ls_beh-n.
        ls_flow-stressed  = xsdbool( ls_beh-p_late >= ls_cfg-stress_threshold OR lv_forced = abap_true ).

        IF ls_flow-stressed = abap_true.
          ls_flow-stress_date = zcl_cfo_calendar=>next_working_day( ls_flow-sched_date + lv_shift ).
        ELSE.
          ls_flow-stress_date = ls_flow-sched_date.
        ENDIF.
        IF lv_forced = abap_true.
          ls_flow-sched_date = ls_flow-stress_date.
        ENDIF.

      ELSE.

        ls_flow-kind   = zif_cfo_types=>flow_kind-payable.
        ls_flow-amount = - ls_item-amount.

        IF ls_item-payment_block IS NOT INITIAL
           AND ls_item-payment_block <> zif_cfo_types=>c_block_price_variance.
          ls_flow-held = abap_true.            " held on purpose - not in any run
          APPEND ls_flow TO rt_flows.
          CONTINUE.
        ENDIF.

        DATA(lv_index) = 0.
        LOOP AT mt_runs INTO DATA(lv_run).
          IF lv_run + 7 >= ls_item-net_due_date.
            lv_index = sy-tabix.
            EXIT.
          ENDIF.
        ENDLOOP.

        IF lv_index > 0 AND line_exists( is_sim-held_ids[ table_line = ls_item-doc_id ] ).
          lv_index += 1.
        ENDIF.

        IF lv_index > 0 AND lv_index <= lines( mt_runs ).
          ls_flow-run_date       = mt_runs[ lv_index ].
          ls_flow-sched_date     = ls_flow-run_date.
          ls_flow-in_current_run = xsdbool( lv_index = 1 ).
          IF ls_flow-in_current_run = abap_true AND is_sim-run_delay_days <> 0.
            ls_flow-sched_date = zcl_cfo_calendar=>next_working_day( ls_flow-run_date + is_sim-run_delay_days ).
          ENDIF.
          ls_flow-stress_date = ls_flow-sched_date.
        ENDIF.

      ENDIF.

      APPEND ls_flow TO rt_flows.
    ENDLOOP.

    LOOP AT ms_input-planned INTO DATA(ls_plan).
      APPEND VALUE #( doc_id       = |PLAN-{ ls_plan-flow_date }|
                      kind         = zif_cfo_types=>flow_kind-planned
                      partner_name = ls_plan-description
                      amount       = ls_plan-amount
                      due_date     = ls_plan-flow_date
                      sched_date   = ls_plan-flow_date
                      stress_date  = ls_plan-flow_date ) TO rt_flows.
    ENDLOOP.

  ENDMETHOD.


  METHOD project.

    DATA ls_day TYPE zif_cfo_types=>ty_day.

    DATA(lv_sched)  = ms_input-opening_cash.
    DATA(lv_stress) = ms_input-opening_cash.
    DATA(lv_exp)    = ms_input-opening_cash.
    DATA(lv_days)   = ms_input-config-horizon_days + 1.

    DO lv_days TIMES.
      CLEAR ls_day.
      ls_day-day_index     = sy-index - 1.
      ls_day-calendar_date = ms_input-key_date + ls_day-day_index.

      LOOP AT it_flows INTO DATA(ls_flow) WHERE sched_date IS NOT INITIAL.
        IF ls_flow-sched_date = ls_day-calendar_date.
          IF ls_flow-amount >= 0.
            ls_day-inflow += ls_flow-amount.
          ELSE.
            ls_day-outflow += ls_flow-amount.
          ENDIF.
          lv_exp += COND zif_cfo_types=>amount( WHEN ls_flow-stressed = abap_true
                                                 THEN ls_flow-amount * ( 1 - ls_flow-p_late )
                                                 ELSE ls_flow-amount ).
        ENDIF.
        IF ls_flow-stress_date = ls_day-calendar_date.
          lv_stress += ls_flow-amount.
          IF ls_flow-stressed = abap_true.
            lv_exp += ls_flow-amount * ls_flow-p_late.
          ENDIF.
        ENDIF.
      ENDLOOP.

      lv_sched += ls_day-inflow + ls_day-outflow.

      ls_day-closing_scheduled = lv_sched.
      ls_day-closing_stressed  = lv_stress.
      ls_day-closing_expected  = lv_exp.
      ls_day-floor_amount      = iv_floor.
      ls_day-floor_delta       = lv_sched - iv_floor.
      ls_day-is_weekend        = xsdbool( zcl_cfo_calendar=>is_working_day( ls_day-calendar_date ) = abap_false ).
      ls_day-is_run_day        = xsdbool( line_exists( mt_runs[ table_line = ls_day-calendar_date ] ) ).
      APPEND ls_day TO rt_days.
    ENDDO.

  ENDMETHOD.


  METHOD low.
    DATA lv_found TYPE abap_bool.
    LOOP AT it_days INTO DATA(ls_day) WHERE day_index >= iv_from AND day_index <= iv_to.
      IF lv_found = abap_false OR closing( is_day = ls_day iv_path = iv_path ) < closing( is_day = rs_day iv_path = iv_path ).
        rs_day   = ls_day.
        lv_found = abap_true.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD closing.
    rv_amount = SWITCH #( iv_path
                          WHEN zif_cfo_types=>path-stressed THEN is_day-closing_stressed
                          WHEN zif_cfo_types=>path-expected THEN is_day-closing_expected
                          ELSE is_day-closing_scheduled ).
  ENDMETHOD.

ENDCLASS.

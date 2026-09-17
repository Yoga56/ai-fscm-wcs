"! <p class="shorttext synchronized">CFO Brief - R: ranked exposures</p>
"! <p><code>score = exposure x probability x floor weight</code>. The floor weight is 2
"! when the item alone would take the scheduled low point below the liquidity
"! floor, 1 for ordinary exposures and 0.5 for items that only reduce outflows
"! (blocked invoices drop from the run).</p>
CLASS zcl_cfo_risk_ranker DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS rank
      IMPORTING is_input        TYPE zif_cfo_types=>ty_input
                it_flows        TYPE zif_cfo_types=>tt_flow
                it_days         TYPE zif_cfo_types=>tt_day
                it_runs         TYPE zif_cfo_types=>tt_date
                iv_floor        TYPE zif_cfo_types=>amount
                io_variance     TYPE REF TO zcl_cfo_variance
                it_signals      TYPE zcl_cfo_variance=>tt_spend_signal
      RETURNING VALUE(rt_risks) TYPE zif_cfo_types=>tt_risk.

ENDCLASS.


CLASS zcl_cfo_risk_ranker IMPLEMENTATION.

  METHOD rank.

    DATA ls_risk TYPE zif_cfo_types=>ty_risk.

    DATA(ls_cfg)      = is_input-config.
    DATA(lv_key)      = is_input-key_date.
    DATA(lv_cur)      = ls_cfg-currency.
    DATA(ls_low)      = zcl_cfo_runway=>low( it_days ).
    DATA(lv_low_date) = CONV d( lv_key + ls_low-day_index ).

    " ---- receivables likely to be late -----------------------------------
    DATA(lv_funds_by)  = zcl_cfo_calendar=>add_working_days( iv_date = lv_low_date
                                                             iv_days = - ls_cfg-factoring_lead_bd ).
    DATA(lv_decide_by) = COND d( WHEN lv_funds_by >= lv_key THEN lv_funds_by ELSE lv_key ).

    LOOP AT it_flows INTO DATA(ls_flow)
         WHERE kind     = zif_cfo_types=>flow_kind-receivable
           AND stressed = abap_true
           AND sched_date IS NOT INITIAL.

      IF ls_flow-sched_date - lv_key > ls_cfg-horizon_days.
        CONTINUE.
      ENDIF.

      CLEAR ls_risk.
      DATA(lv_name)          = condense( CONV string( ls_flow-partner_name ) ).
      ls_risk-risk_type      = zif_cfo_types=>risk_type-ar_late.
      ls_risk-epard          = 'PR'.
      ls_risk-reference      = ls_flow-doc_id.
      ls_risk-partner_name   = ls_flow-partner_name.
      ls_risk-exposure       = ls_flow-amount.
      ls_risk-probability    = ls_flow-p_late.
      ls_risk-floor_weight   = COND #( WHEN ls_low-closing_scheduled - ls_flow-amount < iv_floor THEN 2 ELSE 1 ).
      ls_risk-title          = |{ lv_name } { zcl_cfo_format=>money( iv_amount = ls_flow-amount iv_currency = lv_cur ) } | &&
                               |likely to pay late| &&
                               COND string( WHEN ls_risk-floor_weight = 2 THEN ` — would drop below floor` ).
      ls_risk-detail         = |Paid late in { zcl_cfo_format=>number( iv_value = ls_flow-p_late * ls_flow-hist_n iv_max_decimals = 0 ) } | &&
                               |of { ls_flow-hist_n } past invoices, { ls_flow-mean_late } days on average. | &&
                               |Late → { zcl_cfo_format=>money( iv_amount = ls_flow-amount iv_currency = lv_cur ) } arrives | &&
                               |{ zcl_cfo_calendar=>short_text( ls_flow-stress_date ) } instead of | &&
                               |{ zcl_cfo_calendar=>short_text( ls_flow-sched_date ) }.|.
      ls_risk-recommendation = 'CHASE_OR_FACTOR'.
      ls_risk-recommendation_text =
        |Decide by { zcl_cfo_calendar=>short_text( lv_decide_by ) }: chase or factor | &&
        |(funds ~{ ls_cfg-factoring_lead_bd } days, before Day { ls_low-day_index }).|.
      ls_risk-due_by         = lv_decide_by.
      APPEND ls_risk TO rt_risks.
    ENDLOOP.

    " ---- this week's run: off-pattern suppliers and blocked invoices -----
    DATA(lv_proposal) = zcl_cfo_calendar=>add_working_days( iv_date = it_runs[ 1 ]
                                                            iv_days = - ls_cfg-proposal_lead_bd ).
    DATA lv_blocked_amount TYPE zif_cfo_types=>amount.
    DATA lv_blocked_count  TYPE i.
    DATA lv_blocked_refs   TYPE string.
    DATA lv_blocked_names  TYPE string.

    LOOP AT it_flows INTO ls_flow
         WHERE kind           = zif_cfo_types=>flow_kind-payable
           AND in_current_run = abap_true.

      DATA(lv_amount) = - ls_flow-amount.
      DATA(ls_z)      = io_variance->supplier_zscore( iv_partner = ls_flow-partner
                                                      iv_amount  = lv_amount ).
      IF ls_z-valid = abap_true AND ls_z-z >= ls_cfg-zscore_threshold.
        CLEAR ls_risk.
        ls_risk-risk_type      = zif_cfo_types=>risk_type-ap_offpattern.
        ls_risk-epard          = 'ER'.
        ls_risk-reference      = ls_flow-doc_id.
        ls_risk-partner_name   = ls_flow-partner_name.
        ls_risk-exposure       = lv_amount.
        ls_risk-probability    = round( val = ls_z-z / ( ls_z-z + ls_cfg-zscore_threshold ) dec = 2 ).
        ls_risk-floor_weight   = 1.
        ls_risk-title          = |{ condense( CONV string( ls_flow-partner_name ) ) } | &&
                                 |{ zcl_cfo_format=>money( iv_amount = lv_amount iv_currency = lv_cur ) } | &&
                                 |— off-pattern (large for this vendor)|.
        ls_risk-detail         = |Typical invoice { zcl_cfo_format=>money( iv_amount = ls_z-mean iv_currency = lv_cur ) }; | &&
                                 |this one is { zcl_cfo_format=>number( iv_value = ls_z-z iv_max_decimals = 1 ) } | &&
                                 |standard deviations above.|.
        ls_risk-recommendation      = 'VERIFY_BEFORE_RELEASE'.
        ls_risk-recommendation_text = `Verify before release.`.
        ls_risk-due_by              = lv_proposal.
        APPEND ls_risk TO rt_risks.
      ENDIF.

      IF ls_flow-payment_block = zif_cfo_types=>c_block_price_variance.
        lv_blocked_count  += 1.
        lv_blocked_amount += lv_amount.
        lv_blocked_refs    = COND #( WHEN lv_blocked_refs IS INITIAL THEN condense( CONV string( ls_flow-doc_id ) )
                                     ELSE |{ lv_blocked_refs },{ condense( CONV string( ls_flow-doc_id ) ) }| ).
        lv_blocked_names   = COND #( WHEN lv_blocked_names IS INITIAL THEN condense( CONV string( ls_flow-partner_name ) )
                                     ELSE |{ lv_blocked_names }, { condense( CONV string( ls_flow-partner_name ) ) }| ).
      ENDIF.
    ENDLOOP.

    IF lv_blocked_count > 0.
      CLEAR ls_risk.
      ls_risk-risk_type      = zif_cfo_types=>risk_type-ap_blocked.
      ls_risk-epard          = 'ER'.
      ls_risk-reference      = lv_blocked_refs.
      ls_risk-partner_name   = lv_blocked_names.
      ls_risk-exposure       = lv_blocked_amount.
      ls_risk-probability    = 1.
      ls_risk-floor_weight   = '0.5'.
      ls_risk-title          = |{ lv_blocked_count } invoice{ COND string( WHEN lv_blocked_count > 1 THEN `s` ) } | &&
                               |blocked (price variance) { zcl_cfo_format=>money( iv_amount = lv_blocked_amount iv_currency = lv_cur ) }|.
      ls_risk-detail         = `Blocked for payment in invoice verification.`.
      ls_risk-recommendation      = 'CLEAR_OR_DROP'.
      ls_risk-recommendation_text = `Clear, or they drop from the run.`.
      ls_risk-due_by              = lv_proposal.
      APPEND ls_risk TO rt_risks.
    ENDIF.

    " ---- plant spend spikes ----------------------------------------------
    LOOP AT it_signals INTO DATA(ls_signal).
      CLEAR ls_risk.
      ls_risk-risk_type      = zif_cfo_types=>risk_type-spend_spike.
      ls_risk-epard          = 'ER'.
      ls_risk-reference      = |PLANT-{ ls_signal-plant }|.
      ls_risk-partner_name   = |Plant { ls_signal-plant }|.
      ls_risk-exposure       = ls_signal-delta.
      ls_risk-probability    = '0.5'.
      ls_risk-floor_weight   = 1.
      ls_risk-title          = |Plant { ls_signal-plant } spend up { zcl_cfo_format=>percent( ls_signal-change_pct ) } | &&
                               |({ zcl_cfo_format=>money( iv_amount = ls_signal-delta iv_currency = lv_cur ) }) | &&
                               |— check if real demand|.
      ls_risk-detail         = |Last 30 days { zcl_cfo_format=>money( iv_amount = ls_signal-current iv_currency = lv_cur ) } | &&
                               |vs { zcl_cfo_format=>money( iv_amount = ls_signal-average iv_currency = lv_cur ) } | &&
                               |average of the three windows before.|.
      ls_risk-recommendation      = 'REVIEW_DEMAND'.
      ls_risk-recommendation_text = `Check if real demand.`.
      APPEND ls_risk TO rt_risks.
    ENDLOOP.

    " ---- score and rank ---------------------------------------------------
    LOOP AT rt_risks ASSIGNING FIELD-SYMBOL(<ls_risk>).
      <ls_risk>-score = round( val = <ls_risk>-exposure * <ls_risk>-probability * <ls_risk>-floor_weight dec = 2 ).
    ENDLOOP.

    SORT rt_risks STABLE BY score DESCENDING.

    LOOP AT rt_risks ASSIGNING <ls_risk>.
      <ls_risk>-risk_rank   = sy-tabix.
      <ls_risk>-risk_id     = |R{ sy-tabix }|.
      <ls_risk>-status      = 'OPEN'.
      <ls_risk>-criticality = COND #( WHEN <ls_risk>-floor_weight >= 2     THEN 1
                                      WHEN <ls_risk>-score        >= 1000000 THEN 2
                                      ELSE 3 ).
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

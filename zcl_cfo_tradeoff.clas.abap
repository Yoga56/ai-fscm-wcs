"! <p class="shorttext synchronized">CFO Brief - A: trade-offs and opportunities</p>
"! <ul>
"! <li><strong>DEFER</strong> - the stressed path breaches the floor: which item in that run
"! costs least to delay (late fee plus revenue at risk from ZTCFO_CRIT)?</li>
"! <li><strong>PRIORITIZE</strong> - business-critical payables due in the window that are not
"! in this week's run: approve them in time for the next proposal.</li>
"! <li><strong>DEPOSIT</strong> - cash the scheduled path shows as free after the low point;
"! held while the stressed path says otherwise.</li>
"! <li><strong>EARLYPAY</strong> - cash discounts, annualised and checked against the floor.</li>
"! </ul>
"! Without criticality data the advice is flagged LOW confidence: the AI flags it, the CFO decides.
CLASS zcl_cfo_tradeoff DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS advise
      IMPORTING is_input         TYPE zif_cfo_types=>ty_input
                it_flows         TYPE zif_cfo_types=>tt_flow
                it_days          TYPE zif_cfo_types=>tt_day
                it_runs          TYPE zif_cfo_types=>tt_date
                it_risks         TYPE zif_cfo_types=>tt_risk
                iv_floor         TYPE zif_cfo_types=>amount
      RETURNING VALUE(rt_advice) TYPE zif_cfo_types=>tt_advice.

  PRIVATE SECTION.

    CONSTANTS c_deposit_lot TYPE i VALUE 500000.

    TYPES: BEGIN OF ty_scored,
             flow       TYPE zif_cfo_types=>ty_flow,
             has_crit   TYPE abap_bool,
             crit       TYPE zif_cfo_types=>ty_crit,
             amount     TYPE zif_cfo_types=>amount,
             fee        TYPE zif_cfo_types=>amount,
             cost_ratio TYPE decfloat34,
           END OF ty_scored.

    DATA ms_input TYPE zif_cfo_types=>ty_input.
    DATA mv_cur   TYPE c LENGTH 5.

    METHODS defer
      IMPORTING it_flows   TYPE zif_cfo_types=>tt_flow
                it_days    TYPE zif_cfo_types=>tt_day
                it_runs    TYPE zif_cfo_types=>tt_date
                is_lead    TYPE zif_cfo_types=>ty_risk
                iv_floor   TYPE zif_cfo_types=>amount
      CHANGING ct_advice   TYPE zif_cfo_types=>tt_advice.

    METHODS prioritize
      IMPORTING it_flows TYPE zif_cfo_types=>tt_flow
      CHANGING  ct_advice TYPE zif_cfo_types=>tt_advice.

    METHODS deposit
      IMPORTING it_days  TYPE zif_cfo_types=>tt_day
                is_lead  TYPE zif_cfo_types=>ty_risk
                iv_floor TYPE zif_cfo_types=>amount
      CHANGING  ct_advice TYPE zif_cfo_types=>tt_advice.

    METHODS early_pay
      IMPORTING it_flows TYPE zif_cfo_types=>tt_flow
                it_days  TYPE zif_cfo_types=>tt_day
                iv_floor TYPE zif_cfo_types=>amount
      CHANGING  ct_advice TYPE zif_cfo_types=>tt_advice.

    METHODS criticality
      IMPORTING is_flow        TYPE zif_cfo_types=>ty_flow
      EXPORTING es_crit        TYPE zif_cfo_types=>ty_crit
      RETURNING VALUE(rv_found) TYPE abap_bool.

    METHODS label
      IMPORTING is_flow        TYPE zif_cfo_types=>ty_flow
      RETURNING VALUE(rv_text) TYPE string.

    METHODS money
      IMPORTING iv_amount      TYPE zif_cfo_types=>amount
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS zcl_cfo_tradeoff IMPLEMENTATION.

  METHOD advise.

    ms_input = is_input.
    mv_cur   = is_input-config-currency.

    " the receivable that drives the stress (first ranked AR risk)
    DATA ls_lead TYPE zif_cfo_types=>ty_risk.
    LOOP AT it_risks INTO DATA(ls_risk) WHERE risk_type = zif_cfo_types=>risk_type-ar_late.
      ls_lead = ls_risk.
      EXIT.
    ENDLOOP.

    defer( EXPORTING it_flows = it_flows
                     it_days  = it_days
                     it_runs  = it_runs
                     is_lead  = ls_lead
                     iv_floor = iv_floor
           CHANGING  ct_advice = rt_advice ).

    prioritize( EXPORTING it_flows = it_flows
                CHANGING  ct_advice = rt_advice ).

    deposit( EXPORTING it_days  = it_days
                       is_lead  = ls_lead
                       iv_floor = iv_floor
             CHANGING  ct_advice = rt_advice ).

    early_pay( EXPORTING it_flows = it_flows
                         it_days  = it_days
                         iv_floor = iv_floor
               CHANGING  ct_advice = rt_advice ).

    LOOP AT rt_advice ASSIGNING FIELD-SYMBOL(<ls_advice>).
      <ls_advice>-seq       = sy-tabix.
      <ls_advice>-advice_id = |A{ sy-tabix }|.
    ENDLOOP.

  ENDMETHOD.


  METHOD defer.

    DATA ls_scored    TYPE ty_scored.
    DATA ls_deferable TYPE ty_scored.
    DATA ls_protected TYPE ty_scored.
    DATA lv_run       TYPE d.

    DATA(ls_cfg)       = ms_input-config.
    DATA(lv_key)       = ms_input-key_date.
    DATA(ls_low_x)     = zcl_cfo_runway=>low( it_days = it_days iv_path = zif_cfo_types=>path-stressed ).
    DATA(lv_shortfall) = iv_floor - ls_low_x-closing_stressed.

    IF lv_shortfall <= 0.
      RETURN.
    ENDIF.

    " the last run on or before the stressed low point
    LOOP AT it_runs INTO DATA(lv_candidate).
      IF lv_candidate - lv_key <= ls_low_x-day_index.
        lv_run = lv_candidate.
      ENDIF.
    ENDLOOP.
    IF lv_run IS INITIAL.
      RETURN.
    ENDIF.

    LOOP AT it_flows INTO DATA(ls_flow)
         WHERE kind = zif_cfo_types=>flow_kind-payable AND run_date = lv_run.
      CLEAR ls_scored.
      ls_scored-flow     = ls_flow.
      ls_scored-amount   = - ls_flow-amount.
      ls_scored-has_crit = criticality( EXPORTING is_flow = ls_flow IMPORTING es_crit = ls_scored-crit ).
      ls_scored-fee      = round( val = ls_scored-amount * ls_cfg-late_fee_rate_pct / 100
                                        * ls_cfg-deferral_days / 365 dec = 2 ).
      DATA(lv_op_cost)   = COND zif_cfo_types=>amount(
                             WHEN ls_scored-has_crit = abap_false  THEN 0
                             WHEN ls_scored-crit-crit_level = 'H' THEN ls_scored-crit-revenue_at_risk
                             WHEN ls_scored-crit-crit_level = 'M' THEN ls_scored-crit-revenue_at_risk / 10
                             ELSE 0 ).
      IF ls_scored-amount > 0.
        ls_scored-cost_ratio = ( ls_scored-fee + lv_op_cost ) / ls_scored-amount.
      ENDIF.

      IF ls_scored-crit-crit_level = 'H'.
        IF ls_protected IS INITIAL OR ls_scored-crit-revenue_at_risk > ls_protected-crit-revenue_at_risk.
          ls_protected = ls_scored.
        ENDIF.
      ELSEIF ls_scored-amount > 0.
        IF ls_deferable IS INITIAL OR ls_scored-cost_ratio < ls_deferable-cost_ratio.
          ls_deferable = ls_scored.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF ls_deferable IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lv_lead_name) = COND string( WHEN is_lead IS NOT INITIAL
                                      THEN condense( CONV string( is_lead-partner_name ) )
                                      ELSE `the at-risk receipt` ).
    DATA(lv_after)     = round( val = nmax( val1 = 0 val2 = lv_shortfall - ls_deferable-amount ) dec = 2 ).
    DATA(lv_high)      = xsdbool( ls_deferable-has_crit = abap_true AND ls_protected IS NOT INITIAL ).

    DATA(ls_advice) = VALUE zif_cfo_types=>ty_advice(
      kind             = zif_cfo_types=>advice_kind-defer
      title            = `Trade-off: which do I pay?`
      question         = |The { zcl_cfo_calendar=>short_text( lv_run ) } run would breach the floor if | &&
                         |{ lv_lead_name } pays late — which item do you defer?|
      defer_item       = ls_deferable-flow-doc_id
      defer_name       = label( ls_deferable-flow )
      defer_partner    = ls_deferable-flow-partner_name
      defer_amount     = ls_deferable-amount
      defer_note       = COND #( WHEN ls_deferable-has_crit = abap_true THEN ls_deferable-crit-note
                                 ELSE `No criticality recorded` )
      defer_cost       = ls_deferable-fee
      shortfall_before = round( val = lv_shortfall dec = 2 )
      shortfall_after  = lv_after
      amount           = ls_deferable-amount
      caveat           = `Exception: if the spare part runs the machine making that product — pay it.`
      confidence       = COND #( WHEN lv_high = abap_true THEN 'HIGH' ELSE 'LOW' )
      confidence_note  = COND #( WHEN lv_high = abap_true THEN `Based on recorded PP/MM criticality.`
                                 ELSE `Reliable only with PP schedule + MM criticality — AI flags it, you decide.` )
      status           = zif_cfo_types=>advice_status-ready
      action_date      = lv_run ).

    IF ls_protected IS NOT INITIAL.
      ls_advice-pay_item   = ls_protected-flow-doc_id.
      ls_advice-pay_name    = label( ls_protected-flow ).
      ls_advice-pay_partner = ls_protected-flow-partner_name.
      ls_advice-pay_amount = ls_protected-amount.
      ls_advice-pay_note   = |{ condense( CONV string( ls_protected-crit-note ) ) }; | &&
                             |{ money( CONV zif_cfo_types=>amount( ls_protected-crit-revenue_at_risk ) ) } of orders this quarter on | &&
                             |{ condense( CONV string( ls_protected-crit-prod_line ) ) }|.
      ls_advice-recommendation =
        |Pay { COND string( WHEN find( val = to_lower( ls_protected-flow-item_text ) sub = `raw` ) >= 0
                            THEN `raw material` ELSE label( ls_protected-flow ) ) }. | &&
        |A small late fee ({ money( ls_deferable-fee ) }) ≪ a stopped production line.|.
    ELSE.
      ls_advice-recommendation = |Defer { condense( CONV string( ls_deferable-flow-partner_name ) ) }.|.
    ENDIF.

    ls_advice-detail = |Deferring cuts the shortfall from { money( lv_shortfall ) } to { money( lv_after ) }|.
    IF lv_after > 0 AND is_lead IS NOT INITIAL.
      ls_advice-detail = |{ ls_advice-detail }; factoring { lv_lead_name } | &&
                         |({ money( is_lead-exposure * ls_cfg-factoring_advance_pct / 100 ) }) closes the rest.|.
    ELSE.
      ls_advice-detail = |{ ls_advice-detail }.|.
    ENDIF.

    APPEND ls_advice TO ct_advice.

  ENDMETHOD.


  METHOD prioritize.

    DATA ls_crit TYPE zif_cfo_types=>ty_crit.
    DATA(ls_cfg) = ms_input-config.
    DATA(lv_key) = ms_input-key_date.

    LOOP AT it_flows INTO DATA(ls_flow)
         WHERE kind           = zif_cfo_types=>flow_kind-payable
           AND in_current_run = abap_false
           AND run_date IS NOT INITIAL.

      IF ls_flow-due_date - lv_key > ls_cfg-ap_window_days.
        CONTINUE.
      ENDIF.
      IF criticality( EXPORTING is_flow = ls_flow IMPORTING es_crit = ls_crit ) = abap_false
         OR ls_crit-crit_level <> 'H'.
        CONTINUE.
      ENDIF.

      DATA(lv_proposal) = zcl_cfo_calendar=>add_working_days( iv_date = ls_flow-run_date
                                                              iv_days = - ls_cfg-proposal_lead_bd ).
      DATA(lv_deadline) = zcl_cfo_calendar=>add_working_days( iv_date = lv_proposal
                                                              iv_days = - ls_cfg-approval_lead_bd ).
      DATA(lv_amount)   = - ls_flow-amount.

      APPEND VALUE #(
        kind           = zif_cfo_types=>advice_kind-prioritize
        title          = |{ label( ls_flow ) } { money( lv_amount ) } (due Day { ls_flow-due_date - lv_key })|
        question       = `Part of AP due, not scheduled yet.`
        pay_item       = ls_flow-doc_id
        pay_name       = ls_flow-partner_name
        pay_partner    = ls_flow-partner_name
        pay_amount     = lv_amount
        recommendation = |Approve for next run by { zcl_cfo_calendar=>short_text( lv_deadline ) } | &&
                         |({ ls_cfg-approval_lead_bd }-day lead) to protect { condense( CONV string( ls_crit-prod_line ) ) }.|
        detail         = |Next run { zcl_cfo_calendar=>short_text( ls_flow-run_date ) }; | &&
                         |proposal is built { zcl_cfo_calendar=>short_text( lv_proposal ) }.|
        amount         = lv_amount
        confidence     = 'HIGH'
        status         = zif_cfo_types=>advice_status-ready
        action_date    = lv_deadline ) TO ct_advice.
    ENDLOOP.

  ENDMETHOD.


  METHOD deposit.

    DATA(ls_cfg)      = ms_input-config.
    DATA(lv_key)      = ms_input-key_date.
    DATA(ls_low)      = zcl_cfo_runway=>low( it_days ).
    DATA(lv_start)    = zcl_cfo_calendar=>next_working_day( CONV d( lv_key + ls_low-day_index + 1 ) ).
    DATA(lv_from)     = CONV i( lv_start - lv_key ).
    DATA(lv_to)       = lv_from + ls_cfg-deposit_days - 1.

    IF lv_to > ls_cfg-horizon_days.
      RETURN.
    ENDIF.

    DATA(lv_free_s) = zcl_cfo_runway=>low( it_days = it_days iv_path = zif_cfo_types=>path-scheduled
                                           iv_from = lv_from iv_to = lv_to )-closing_scheduled - iv_floor.
    DATA(lv_free_x) = zcl_cfo_runway=>low( it_days = it_days iv_path = zif_cfo_types=>path-stressed
                                           iv_from = lv_from iv_to = lv_to )-closing_stressed - iv_floor.
    DATA(lv_amount) = CONV zif_cfo_types=>amount( floor( lv_free_s / c_deposit_lot ) * c_deposit_lot ).

    IF lv_amount <= 0.
      RETURN.
    ENDIF.

    DATA(lv_income)  = round( val = lv_amount * ls_cfg-deposit_rate_pct / 100 * ls_cfg-deposit_days / 365 dec = 2 ).
    DATA(lv_held)    = xsdbool( lv_free_x < lv_amount ).
    DATA(lv_rate)    = zcl_cfo_format=>number( CONV #( ls_cfg-deposit_rate_pct ) ).
    DATA(lv_lead)    = condense( CONV string( is_lead-partner_name ) ).
    DATA(lv_cond)    = xsdbool( lv_held = abap_true AND is_lead IS NOT INITIAL ).

    APPEND VALUE #(
      kind           = zif_cfo_types=>advice_kind-deposit
      title          = `Opportunity: idle cash to work`
      question       = COND #( WHEN lv_cond = abap_true
                               THEN |This week is tight — but if { zcl_cfo_format=>possessive( lv_lead ) } | &&
                                    |{ money( is_lead-exposure ) } lands on time, a surplus opens.|
                               ELSE `A surplus opens after the low point.` )
      recommendation = |{ COND string( WHEN lv_cond = abap_true THEN |If { lv_lead } pays: place| ELSE `Place` ) } | &&
                       |~{ money( lv_amount ) } · { ls_cfg-deposit_days }-day deposit @ { lv_rate }% p.a. | &&
                       |from { zcl_cfo_calendar=>short_text( lv_start ) }|
      detail         = COND #( WHEN lv_held = abap_true
                               THEN |Potential income — held pending | &&
                                    |{ COND string( WHEN lv_lead IS NOT INITIAL THEN lv_lead ELSE `the at-risk receipt` ) }; | &&
                                    |revisit once it clears.|
                               ELSE `Potential income — ready to place.` )
      caveat         = |Only lock cash the forecast shows as free after the Day { ls_low-day_index } low-point.|
      amount         = lv_amount
      income         = lv_income
      annualized_pct = ls_cfg-deposit_rate_pct
      confidence     = COND #( WHEN lv_held = abap_true THEN 'LOW' ELSE 'HIGH' )
      status         = COND #( WHEN lv_held = abap_true THEN zif_cfo_types=>advice_status-held
                               ELSE zif_cfo_types=>advice_status-ready )
      action_date    = lv_start ) TO ct_advice.

  ENDMETHOD.


  METHOD early_pay.

    DATA(ls_cfg) = ms_input-config.
    DATA(lv_key) = ms_input-key_date.

    LOOP AT it_flows INTO DATA(ls_flow)
         WHERE kind = zif_cfo_types=>flow_kind-payable
           AND held = abap_false
           AND discount_pct > 0
           AND sched_date IS NOT INITIAL.

      IF ls_flow-discount_date < lv_key OR ls_flow-due_date <= ls_flow-discount_date.
        CONTINUE.
      ENDIF.

      DATA(lv_amount) = - ls_flow-amount.
      DATA(lv_term)   = CONV i( ls_flow-due_date - ls_flow-discount_date ).
      DATA(lv_annual) = round( val = ls_flow-discount_pct / ( 100 - ls_flow-discount_pct ) * 365 / lv_term * 100 dec = 1 ).
      DATA(lv_from)   = CONV i( ls_flow-discount_date - lv_key ).
      DATA(lv_to)     = CONV i( ls_flow-sched_date - lv_key ) - 1.

      DATA(lv_ok_s) = xsdbool( zcl_cfo_runway=>low( it_days = it_days iv_path = zif_cfo_types=>path-scheduled
                                                    iv_from = lv_from iv_to = lv_to )-closing_scheduled
                               - lv_amount >= iv_floor ).
      DATA(lv_ok_x) = xsdbool( zcl_cfo_runway=>low( it_days = it_days iv_path = zif_cfo_types=>path-stressed
                                                    iv_from = lv_from iv_to = lv_to )-closing_stressed
                               - lv_amount >= iv_floor ).
      DATA(lv_pct)  = zcl_cfo_format=>number( ls_flow-discount_pct ).
      DATA(lv_rate) = zcl_cfo_format=>number( CONV #( ls_cfg-deposit_rate_pct ) ).

      APPEND VALUE #(
        kind           = zif_cfo_types=>advice_kind-early_pay
        title          = |Early-payment discount: { condense( CONV string( ls_flow-partner_name ) ) } { money( lv_amount ) }|
        question       = |{ lv_pct }% if paid by { zcl_cfo_calendar=>short_text( ls_flow-discount_date ) }, | &&
                         |net { zcl_cfo_calendar=>short_text( ls_flow-due_date ) }.|
        pay_item       = ls_flow-doc_id
        pay_name       = ls_flow-partner_name
        pay_partner    = ls_flow-partner_name
        pay_amount     = lv_amount
        recommendation = |Or capture the early-payment discount when cash allows → ≈ | &&
                         |{ zcl_cfo_format=>number( iv_value = lv_annual iv_max_decimals = 1 ) }% p.a., | &&
                         |{ COND string( WHEN lv_annual > ls_cfg-deposit_rate_pct THEN `beats` ELSE `does not beat` ) } | &&
                         |a { lv_rate }% deposit.|
        detail         = COND #( WHEN lv_ok_x = abap_true THEN `Affordable even if the at-risk receipt is late.`
                                 WHEN lv_ok_s = abap_true THEN `Affordable only if the at-risk receipt lands on time.`
                                 ELSE `Not affordable before the low point.` )
        amount         = lv_amount
        income         = round( val = lv_amount * ls_flow-discount_pct / 100 dec = 2 )
        annualized_pct = lv_annual
        confidence     = COND #( WHEN lv_ok_x = abap_true THEN 'HIGH' ELSE 'LOW' )
        status         = COND #( WHEN lv_ok_x = abap_true THEN zif_cfo_types=>advice_status-ready
                                 WHEN lv_ok_s = abap_true THEN zif_cfo_types=>advice_status-held
                                 ELSE zif_cfo_types=>advice_status-blocked )
        action_date    = ls_flow-discount_date ) TO ct_advice.
    ENDLOOP.

  ENDMETHOD.


  METHOD criticality.
    CLEAR es_crit.
    IF is_flow-purchase_order IS NOT INITIAL.
      ASSIGN ms_input-crit[ object_type = 'PO' object_id = is_flow-purchase_order ] TO FIELD-SYMBOL(<ls_crit>).
    ENDIF.
    IF <ls_crit> IS NOT ASSIGNED AND is_flow-partner IS NOT INITIAL.
      ASSIGN ms_input-crit[ object_type = 'SUPPLIER' object_id = is_flow-partner ] TO <ls_crit>.
    ENDIF.
    IF <ls_crit> IS ASSIGNED.
      es_crit  = <ls_crit>.
      rv_found = abap_true.
    ENDIF.
  ENDMETHOD.


  METHOD label.
    rv_text = condense( CONV string( COND #( WHEN is_flow-item_text IS NOT INITIAL THEN is_flow-item_text
                                             ELSE is_flow-partner_name ) ) ).
  ENDMETHOD.


  METHOD money.
    rv_text = zcl_cfo_format=>money( iv_amount = iv_amount iv_currency = mv_cur ).
  ENDMETHOD.

ENDCLASS.

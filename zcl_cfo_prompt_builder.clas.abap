"! <p class="shorttext synchronized">CFO Brief - facts JSON and prompts for the model</p>
"! <p>The facts carry every figure pre-formatted ($9.5M, Thu 6 Aug, 75%), so the
"! model can quote but never has to compute. Partner names are pseudonymised.</p>
CLASS zcl_cfo_prompt_builder DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING io_pseudo TYPE REF TO zcl_cfo_pseudonymizer.

    CLASS-METHODS system_instruction
      RETURNING VALUE(rv_text) TYPE string.

    METHODS facts
      IMPORTING is_result      TYPE zif_cfo_types=>ty_result
      RETURNING VALUE(rv_json) TYPE string.

    METHODS brief_prompt
      IMPORTING iv_facts       TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    METHODS copilot_prompt
      IMPORTING iv_facts       TYPE string
                iv_question    TYPE clike
      RETURNING VALUE(rv_text) TYPE string.

    METHODS draft_prompt
      IMPORTING iv_facts       TYPE string
                is_draft       TYPE zif_cfo_types=>ty_draft
      RETURNING VALUE(rv_text) TYPE string.

  PRIVATE SECTION.

    DATA mo_pseudo   TYPE REF TO zcl_cfo_pseudonymizer.
    DATA mv_currency TYPE c LENGTH 5.

    "! "masked, escaped text" as JSON string literal
    METHODS str
      IMPORTING iv_text        TYPE clike
      RETURNING VALUE(rv_json) TYPE string.

    METHODS money
      IMPORTING iv_amount      TYPE zif_cfo_types=>amount
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS bool
      IMPORTING iv_flag        TYPE abap_bool
      RETURNING VALUE(rv_json) TYPE string.

    CLASS-METHODS date
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_json) TYPE string.

ENDCLASS.


CLASS zcl_cfo_prompt_builder IMPLEMENTATION.

  METHOD constructor.
    mo_pseudo = io_pseudo.
  ENDMETHOD.


  METHOD system_instruction.
    rv_text =
      `You are the finance executive assistant for a CFO. You turn pre-computed ledger facts into ` &&
      `short, ranked, decision-ready language. Rules: ` &&
      `(1) Use only the facts provided. Never calculate, estimate or invent a figure; quote amounts, ` &&
      `dates and percentages exactly as they are written in the facts. ` &&
      `(2) Partner names are tokens such as CUSTOMER_1 or SUPPLIER_2 - keep them exactly as written. ` &&
      `(3) Lead with the decision, then the reason. No filler, no generic advice. ` &&
      `(4) Never suggest telling a customer about factoring, and never promise that a payment will be made. ` &&
      `(5) Answer with a single JSON object that follows the requested schema - no markdown.`.
  ENDMETHOD.


  METHOD facts.

    DATA(ls_b) = is_result-brief.
    mv_currency = ls_b-currency.
    DATA lv_items TYPE string.

    " names first, so that every text below is masked consistently
    LOOP AT is_result-risks INTO DATA(ls_risk).
      mo_pseudo->register( iv_name = ls_risk-partner_name
                           iv_kind = COND #( WHEN ls_risk-risk_type = zif_cfo_types=>risk_type-ar_late
                                             THEN zcl_cfo_pseudonymizer=>kind-customer
                                             ELSE zcl_cfo_pseudonymizer=>kind-supplier ) ).
    ENDLOOP.
    LOOP AT is_result-flows INTO DATA(ls_flow) WHERE partner_name IS NOT INITIAL
                                                 AND kind <> zif_cfo_types=>flow_kind-planned.
      mo_pseudo->register( iv_name = ls_flow-partner_name
                           iv_kind = COND #( WHEN ls_flow-kind = zif_cfo_types=>flow_kind-payable
                                             THEN zcl_cfo_pseudonymizer=>kind-supplier
                                             ELSE zcl_cfo_pseudonymizer=>kind-customer ) ).
    ENDLOOP.
    LOOP AT is_result-advice INTO DATA(ls_adv).
      mo_pseudo->register( iv_name = ls_adv-pay_partner   iv_kind = zcl_cfo_pseudonymizer=>kind-supplier ).
      mo_pseudo->register( iv_name = ls_adv-defer_partner iv_kind = zcl_cfo_pseudonymizer=>kind-supplier ).
    ENDLOOP.

    rv_json =
      |\{"briefDate":{ date( ls_b-brief_date ) },"currency":{ str( ls_b-currency ) },| &&
      |"horizonDays":{ ls_b-horizon_days },"position":\{| &&
      |"cashToday":{ money( ls_b-cash_today ) },"liquidityFloor":{ money( ls_b-liquidity_floor ) },| &&
      |"thisWeeksRun":\{"date":{ date( ls_b-run_date ) },"total":{ money( ls_b-run_total ) },| &&
      |"invoices":{ ls_b-run_invoice_count },"vendors":{ ls_b-run_vendor_count },| &&
      |"cashAfterRun":{ money( ls_b-cash_after_run ) },"holdsAboveFloor":{ bool( ls_b-run_holds_floor ) }\},| &&
      |"nextRunDate":{ date( ls_b-next_run_date ) },| &&
      |"lowPoint":\{"amount":{ money( ls_b-low_point ) },"day":{ ls_b-low_point_day },"date":{ date( ls_b-low_point_date ) },| &&
      |"headroomAboveFloor":{ money( ls_b-headroom ) }\},| &&
      |"stressedLowPoint":\{"amount":{ money( ls_b-stressed_low_point ) },"day":{ ls_b-stressed_low_day },| &&
      |"belowFloor":{ bool( ls_b-floor_breach ) }\},| &&
      |"accountsReceivable":\{"total":{ money( ls_b-ar_total ) },"overdue":{ money( ls_b-ar_overdue ) }\},| &&
      |"accountsPayable":\{"total":{ money( ls_b-ap_total ) },"dueInWindow":{ money( ls_b-ap_due_window ) },| &&
      |"overdue":{ money( ls_b-ap_overdue ) }\}\},|.

    CLEAR lv_items.
    LOOP AT is_result-explains INTO DATA(ls_explain).
      lv_items = |{ lv_items }{ COND string( WHEN lv_items IS NOT INITIAL THEN `,` ) }{ str( ls_explain-text ) }|.
    ENDLOOP.
    rv_json = |{ rv_json }"explain":[{ lv_items }],|.

    CLEAR lv_items.
    LOOP AT is_result-risks INTO ls_risk.
      lv_items = |{ lv_items }{ COND string( WHEN lv_items IS NOT INITIAL THEN `,` ) }| &&
                 |\{"id":{ str( ls_risk-risk_id ) },"rank":{ ls_risk-risk_rank },"type":{ str( ls_risk-risk_type ) },| &&
                 |"title":{ str( ls_risk-title ) },"detail":{ str( ls_risk-detail ) },| &&
                 |"probability":"{ zcl_cfo_format=>number( iv_value = ls_risk-probability * 100 iv_max_decimals = 0 ) }%",| &&
                 |"exposure":{ money( ls_risk-exposure ) },"score":{ money( ls_risk-score ) },| &&
                 |"decideBy":{ date( ls_risk-due_by ) },"recommendation":{ str( ls_risk-recommendation_text ) }\}|.
    ENDLOOP.
    rv_json = |{ rv_json }"risks":[{ lv_items }],|.

    CLEAR lv_items.
    LOOP AT is_result-advice INTO ls_adv.
      lv_items = |{ lv_items }{ COND string( WHEN lv_items IS NOT INITIAL THEN `,` ) }| &&
                 |\{"id":{ str( ls_adv-advice_id ) },"kind":{ str( ls_adv-kind ) },"title":{ str( ls_adv-title ) },| &&
                 |"question":{ str( ls_adv-question ) },"recommendation":{ str( ls_adv-recommendation ) },| &&
                 |"detail":{ str( ls_adv-detail ) },"caveat":{ str( ls_adv-caveat ) },| &&
                 |"amount":{ money( ls_adv-amount ) },"income":{ money( ls_adv-income ) },| &&
                 |"annualizedPct":"{ zcl_cfo_format=>number( iv_value = ls_adv-annualized_pct iv_max_decimals = 1 ) }%",| &&
                 |"confidence":{ str( ls_adv-confidence ) },"status":{ str( ls_adv-status ) },| &&
                 |"actionDate":{ date( ls_adv-action_date ) }\}|.
    ENDLOOP.
    rv_json = |{ rv_json }"advice":[{ lv_items }],| &&
              |"ruleHeadline":{ str( ls_b-headline ) },"ruleNarrative":{ str( ls_b-narrative ) }\}|.

  ENDMETHOD.


  METHOD brief_prompt.
    rv_text =
      |Write today's CFO daily brief from these facts.{ cl_abap_char_utilities=>newline }| &&
      |FACTS: { iv_facts }{ cl_abap_char_utilities=>newline }| &&
      |Return JSON: \{"headline": string (max 90 characters, says whether this week's run holds above the floor | &&
      |and how many items need review), "narrative": string (max 90 words: position, the low point, the biggest | &&
      |risk and what to decide by when), "riskNotes": [\{"id": risk id, "note": string (max 30 words, why it | &&
      |matters and the next step)\}], "adviceNotes": [\{"id": advice id, "note": string (max 30 words)\}]\}.|.
  ENDMETHOD.


  METHOD copilot_prompt.
    rv_text =
      |Answer the CFO's question using only these facts.{ cl_abap_char_utilities=>newline }| &&
      |FACTS: { iv_facts }{ cl_abap_char_utilities=>newline }| &&
      |QUESTION: { zcl_cc_json=>escape( mo_pseudo->mask( iv_question ) ) }{ cl_abap_char_utilities=>newline }| &&
      |If the question needs a new calculation (a what-if), do not compute it: say which What-if toggle | &&
      |answers it (customer pays late, hold a supplier, factor a receivable, delay the run, change the floor). | &&
      |If the facts do not contain the answer, say so. | &&
      |Return JSON: \{"answer": string (max 120 words), "followUps": [string] (max 3 short questions)\}.|.
  ENDMETHOD.


  METHOD draft_prompt.
    rv_text =
      |Polish this draft so it reads like a CFO wrote it. Keep every figure, date and token exactly; | &&
      |do not add figures; keep it short.{ cl_abap_char_utilities=>newline }| &&
      |FACTS: { iv_facts }{ cl_abap_char_utilities=>newline }| &&
      |DRAFT: \{"type":{ str( is_draft-action_type ) },"recipient":{ str( is_draft-recipient ) },| &&
      |"subject":{ str( is_draft-subject ) },"body":{ str( is_draft-body ) }\}{ cl_abap_char_utilities=>newline }| &&
      |Return JSON: \{"subject": string, "body": string\}.|.
  ENDMETHOD.


  METHOD str.
    rv_json = |"{ zcl_cc_json=>escape( mo_pseudo->mask( iv_text ) ) }"|.
  ENDMETHOD.


  METHOD money.
    rv_json = |"{ zcl_cfo_format=>money( iv_amount = iv_amount iv_currency = mv_currency ) }"|.
  ENDMETHOD.


  METHOD bool.
    rv_json = COND #( WHEN iv_flag = abap_true THEN `true` ELSE `false` ).
  ENDMETHOD.


  METHOD date.
    rv_json = COND #( WHEN iv_date IS INITIAL THEN `null`
                      ELSE |"{ zcl_cfo_calendar=>short_text( iv_date ) } ({ zcl_cfo_calendar=>iso( iv_date ) })"| ).
  ENDMETHOD.

ENDCLASS.

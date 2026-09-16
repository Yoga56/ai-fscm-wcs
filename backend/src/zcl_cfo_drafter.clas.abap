"! <p class="shorttext synchronized">CFO Brief - D: template drafts (letters, approvals, exception lists)</p>
"! <p>Drafts are proposals only: this app never posts, blocks or releases anything.
"! A person edits, routes and approves them; the owning team executes in its own app.</p>
CLASS zcl_cfo_drafter DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING is_config TYPE zif_cfo_types=>ty_config.

    METHODS collection_notice
      IMPORTING is_risk         TYPE zif_cfo_types=>ty_risk
      RETURNING VALUE(rs_draft) TYPE zif_cfo_types=>ty_draft.

    METHODS run_exceptions
      IMPORTING is_brief        TYPE zif_cfo_types=>ty_brief
                it_risks        TYPE zif_cfo_types=>tt_risk
      RETURNING VALUE(rs_draft) TYPE zif_cfo_types=>ty_draft.

    METHODS for_advice
      IMPORTING is_advice       TYPE zif_cfo_types=>ty_advice
      RETURNING VALUE(rs_draft) TYPE zif_cfo_types=>ty_draft.

  PRIVATE SECTION.

    DATA ms_config TYPE zif_cfo_types=>ty_config.
    DATA mv_nl     TYPE string.

    METHODS money
      IMPORTING iv_amount      TYPE zif_cfo_types=>amount
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS day
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS name
      IMPORTING iv_text        TYPE clike
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS zcl_cfo_drafter IMPLEMENTATION.

  METHOD constructor.
    ms_config = is_config.
    mv_nl     = cl_abap_char_utilities=>newline.
  ENDMETHOD.


  METHOD collection_notice.
    DATA(lv_partner) = name( is_risk-partner_name ).
    rs_draft = VALUE #(
      action_type   = zif_cfo_types=>action_type-collection_notice
      recipient     = |Chief Financial Officer, { lv_partner }|
      subject       = |{ lv_partner } — overdue balance { money( is_risk-exposure ) }|
      body          = |Dear CFO,{ mv_nl }{ mv_nl }| &&
                      |Our records show { money( is_risk-exposure ) } (reference { name( is_risk-reference ) }) | &&
                      |is past its due date. We value the relationship and would like to settle this without escalation.| &&
                      |{ mv_nl }{ mv_nl }| &&
                      |Please confirm the payment date by { day( is_risk-due_by ) }, or let us know of anything | &&
                      |that is holding the payment so we can resolve it together.{ mv_nl }{ mv_nl }| &&
                      |Kind regards,{ mv_nl }Chief Financial Officer|
      internal_note = |Decide by { day( is_risk-due_by ) }: chase or factor. Do not mention factoring to the customer.|
      amount        = is_risk-exposure
      engine        = zif_cfo_types=>engine-rule ).
  ENDMETHOD.


  METHOD run_exceptions.

    DATA lv_lines  TYPE string.
    DATA lv_amount TYPE zif_cfo_types=>amount.
    DATA lv_count  TYPE i.

    LOOP AT it_risks INTO DATA(ls_risk)
         WHERE risk_type = zif_cfo_types=>risk_type-ap_offpattern
            OR risk_type = zif_cfo_types=>risk_type-ap_blocked.
      lv_count  += 1.
      lv_amount += ls_risk-exposure.
      lv_lines   = |{ lv_lines }{ lv_count }. { ls_risk-title } — { ls_risk-recommendation_text }{ mv_nl }|.
    ENDLOOP.

    rs_draft = VALUE #(
      action_type   = zif_cfo_types=>action_type-run_exceptions
      recipient     = `Payment run owner (Accounts Payable)`
      subject       = |Payment run { day( is_brief-run_date ) } — { lv_count } exception| &&
                      |{ COND string( WHEN lv_count <> 1 THEN `s` ) } before release|
      body          = |The proposal ({ money( is_brief-run_total ) }, { is_brief-run_invoice_count } invoices / | &&
                      |{ is_brief-run_vendor_count } vendors) | &&
                      |{ COND string( WHEN is_brief-run_holds_floor = abap_true THEN `clears` ELSE `does not clear` ) } | &&
                      |the floor.{ mv_nl }{ mv_nl }| &&
                      |Please resolve before the proposal is released:{ mv_nl }{ lv_lines }{ mv_nl }| &&
                      |Release the remaining { money( is_brief-run_total - lv_amount ) } as proposed.|
      internal_note = `Exception list only — the payment run itself is not changed by this app.`
      amount        = lv_amount
      engine        = zif_cfo_types=>engine-rule ).

  ENDMETHOD.


  METHOD for_advice.

    DATA(ls_a) = is_advice.
    rs_draft-engine = zif_cfo_types=>engine-rule.

    CASE ls_a-kind.

      WHEN zif_cfo_types=>advice_kind-defer.
        rs_draft-action_type   = zif_cfo_types=>action_type-defer.
        rs_draft-recipient     = `Treasury / AP lead`.
        rs_draft-subject       = |Run { day( ls_a-action_date ) }: pay { name( ls_a-pay_name ) }, | &&
                                 |defer { name( ls_a-defer_name ) }|.
        rs_draft-body          = |If the at-risk receipt is late, the { day( ls_a-action_date ) } run breaches the floor | &&
                                 |by { money( ls_a-shortfall_before ) }.{ mv_nl }{ mv_nl }| &&
                                 |Please approve: pay { name( ls_a-pay_name ) } ({ money( ls_a-pay_amount ) }); | &&
                                 |defer { name( ls_a-defer_name ) } ({ money( ls_a-defer_amount ) }) by | &&
                                 |{ ms_config-deferral_days } days (estimated fee { money( ls_a-defer_cost ) }).| &&
                                 |{ mv_nl }{ mv_nl }{ ls_a-detail }{ mv_nl }{ ls_a-caveat }|.
        rs_draft-internal_note = ls_a-confidence_note.
        rs_draft-amount        = ls_a-defer_amount.

      WHEN zif_cfo_types=>advice_kind-prioritize.
        rs_draft-action_type   = zif_cfo_types=>action_type-prioritize.
        rs_draft-recipient     = `AP lead`.
        rs_draft-subject       = |Approve { name( ls_a-pay_name ) } { money( ls_a-pay_amount ) } for the next run|.
        rs_draft-body          = |{ ls_a-title }.{ mv_nl }{ mv_nl }{ ls_a-recommendation }{ mv_nl }{ ls_a-detail }|.
        rs_draft-amount        = ls_a-pay_amount.

      WHEN zif_cfo_types=>advice_kind-deposit.
        rs_draft-action_type   = zif_cfo_types=>action_type-deposit.
        rs_draft-recipient     = `Group Treasury`.
        rs_draft-subject       = |Deposit proposal { money( ls_a-amount ) } · { ms_config-deposit_days } days @ | &&
                                 |{ zcl_cfo_format=>number( CONV #( ms_config-deposit_rate_pct ) ) }%|.
        rs_draft-body          = |{ ls_a-recommendation } ≈ { money( ls_a-income ) } income.{ mv_nl }{ mv_nl }| &&
                                 |{ ls_a-detail }{ mv_nl }{ ls_a-caveat }|.
        rs_draft-internal_note = COND #( WHEN ls_a-status = zif_cfo_types=>advice_status-held
                                         THEN `Held — do not place until the at-risk receipt clears.` ).
        rs_draft-amount        = ls_a-amount.

      WHEN zif_cfo_types=>advice_kind-early_pay.
        rs_draft-action_type   = zif_cfo_types=>action_type-early_pay.
        rs_draft-recipient     = `AP lead`.
        rs_draft-subject       = |Early-payment discount — { name( ls_a-pay_name ) } { money( ls_a-pay_amount ) }|.
        rs_draft-body          = |{ ls_a-question }{ mv_nl }{ ls_a-recommendation }{ mv_nl }| &&
                                 |Saving { money( ls_a-income ) }. { ls_a-detail }|.
        rs_draft-amount        = ls_a-pay_amount.

    ENDCASE.

  ENDMETHOD.


  METHOD money.
    rv_text = zcl_cfo_format=>money( iv_amount = iv_amount iv_currency = ms_config-currency ).
  ENDMETHOD.


  METHOD day.
    rv_text = zcl_cfo_calendar=>short_text( iv_date ).
  ENDMETHOD.


  METHOD name.
    rv_text = condense( CONV string( iv_text ) ).
  ENDMETHOD.

ENDCLASS.

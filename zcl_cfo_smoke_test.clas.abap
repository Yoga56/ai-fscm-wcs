"! <p class="shorttext synchronized">CFO Brief - console smoke test (F9)</p>
"! <p>1) Runs the engine on the in-memory slide scenario - no tables needed.
"! 2) If company code 1000 is configured: loads its data, builds the brief and asks
"! Gemini for the words (nothing is saved). "Engine : HYBRID" means the destination works.</p>
CLASS zcl_cfo_smoke_test DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CLASS-METHODS print
      IMPORTING is_result TYPE zif_cfo_types=>ty_result
                io_out    TYPE REF TO if_oo_adt_classrun_out.
ENDCLASS.


CLASS zcl_cfo_smoke_test IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    out->write( `--- 1. Rule engine on the slide scenario (Tue 4 Aug 2026) ---` ).
    TRY.
        print( is_result = NEW zcl_cfo_brief_builder( )->build( zcl_cfo_demo_seed=>scenario( ) )
               io_out    = out ).
      CATCH zcx_cfo_error INTO DATA(lx_error).
        out->write( |FAILED: { lx_error->text }| ).
        RETURN.
    ENDTRY.

    out->write( `` ).
    out->write( |--- 2. Company code { zcl_cfo_demo_seed=>c_company } from the database, with AI ---| ).
    TRY.
        DATA(ls_input)  = NEW zcl_cfo_data_loader( )->load( zcl_cfo_demo_seed=>c_company ).
        DATA(ls_result) = NEW zcl_cfo_brief_builder( )->build( ls_input ).
        NEW zcl_cfo_ai_advisor( ls_input-config )->enrich( CHANGING cs_result = ls_result ).
        print( is_result = ls_result io_out = out ).
        out->write( |Engine        : { ls_result-brief-engine } { ls_result-brief-model_used }| ).
        IF ls_result-brief-error_text IS NOT INITIAL.
          out->write( |Warning       : { ls_result-brief-error_text }| ).
        ENDIF.
      CATCH zcx_cfo_error INTO lx_error.
        out->write( |Skipped: { lx_error->text }| ).
    ENDTRY.

  ENDMETHOD.


  METHOD print.
    DATA(ls_b) = is_result-brief.
    DATA(lv_c) = ls_b-currency.

    io_out->write( |Mode          : { ls_b-data_mode }, brief date { zcl_cfo_calendar=>short_text( ls_b-brief_date ) }| ).
    io_out->write( |Headline      : { ls_b-headline }| ).
    io_out->write( |Cash / run    : { zcl_cfo_format=>money( iv_amount = ls_b-cash_today iv_currency = lv_c ) } -> | &&
                   |{ zcl_cfo_format=>money( iv_amount = ls_b-run_total iv_currency = lv_c ) } on | &&
                   |{ zcl_cfo_calendar=>short_text( ls_b-run_date ) } ({ ls_b-run_invoice_count } inv / | &&
                   |{ ls_b-run_vendor_count } vendors) -> { zcl_cfo_format=>money( iv_amount = ls_b-cash_after_run iv_currency = lv_c ) }| ).
    io_out->write( |Low point     : { zcl_cfo_format=>money( iv_amount = ls_b-low_point iv_currency = lv_c ) } on Day { ls_b-low_point_day }, | &&
                   |stressed { zcl_cfo_format=>money( iv_amount = ls_b-stressed_low_point iv_currency = lv_c ) } | &&
                   |(floor { zcl_cfo_format=>money( iv_amount = ls_b-liquidity_floor iv_currency = lv_c ) })| ).
    io_out->write( |Narrative     : { ls_b-narrative }| ).
    LOOP AT is_result-explains INTO DATA(ls_explain).
      io_out->write( |Explain       : { ls_explain-text }| ).
    ENDLOOP.
    LOOP AT is_result-risks INTO DATA(ls_risk).
      io_out->write( |Risk { ls_risk-risk_rank }        : { ls_risk-title } | &&
                     |[score { zcl_cfo_format=>money( iv_amount = ls_risk-score iv_currency = lv_c ) }] { ls_risk-recommendation_text }| ).
    ENDLOOP.
    LOOP AT is_result-advice INTO DATA(ls_advice).
      io_out->write( |Advice { ls_advice-kind WIDTH = 10 }: { ls_advice-recommendation } ({ ls_advice-status })| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

*"* The AI path offline: a test double stands in for Gemini.

CLASS ltd_llm DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_cfo_llm.
    DATA answer      TYPE string.
    DATA fail        TYPE abap_bool.
    DATA last_prompt TYPE string.
ENDCLASS.

CLASS ltd_llm IMPLEMENTATION.
  METHOD zif_cfo_llm~generate.
    last_prompt = iv_prompt.
    IF fail = abap_true.
      zcx_cfo_error=>raise( `Destination GEMINI_AI cannot be resolved` ).
    ENDIF.
    rv_text = answer.
  ENDMETHOD.

  METHOD zif_cfo_llm~model.
    rv_model = `test-double`.
  ENDMETHOD.
ENDCLASS.


CLASS ltcl_advisor DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA mo_llm    TYPE REF TO ltd_llm.
    DATA mo_cut    TYPE REF TO zcl_cfo_ai_advisor.
    DATA ms_result TYPE zif_cfo_types=>ty_result.

    METHODS setup.
    METHODS accepted_answer       FOR TESTING.
    METHODS names_never_leave     FOR TESTING.
    METHODS invented_figure       FOR TESTING.
    METHODS rounding_is_allowed   FOR TESTING.
    METHODS destination_down      FOR TESTING.
    METHODS not_json              FOR TESTING.
    METHODS copilot_fallback      FOR TESTING.
ENDCLASS.


CLASS ltcl_advisor IMPLEMENTATION.

  METHOD setup.
    DATA(ls_input) = zcl_cfo_demo_seed=>scenario( ).
    ls_input-config-ai_enabled = abap_true.
    TRY.
        ms_result = NEW zcl_cfo_brief_builder( )->build( ls_input ).
      CATCH zcx_cfo_error INTO DATA(lx_error).
        cl_abap_unit_assert=>fail( lx_error->text ).
    ENDTRY.
    mo_llm = NEW #( ).
    mo_cut = NEW #( is_config = ls_input-config io_llm = mo_llm ).
  ENDMETHOD.


  METHOD accepted_answer.
    mo_llm->answer =
      `{"headline":"Run holds above the $8.0M floor - 3 items to review",` &&
      `"narrative":"Cash $22.0M falls to $9.5M on Day 9. If CUSTOMER_1 pays late (75%) it is $5.5M.",` &&
      `"riskNotes":[{"id":"R1","note":"CUSTOMER_1 decides the week: chase today."}],` &&
      `"adviceNotes":[{"id":"A3","note":"Hold the deposit until the receipt clears."}]}`.

    mo_cut->enrich( CHANGING cs_result = ms_result ).

    cl_abap_unit_assert=>assert_equals( act = ms_result-brief-engine exp = zif_cfo_types=>engine-hybrid ).
    cl_abap_unit_assert=>assert_char_cp( act = ms_result-brief-narrative exp = `*If ABC Industries pays late*` ).
    cl_abap_unit_assert=>assert_equals( act = ms_result-risks[ risk_id = 'R1' ]-ai_note
                                        exp = `ABC Industries decides the week: chase today.` ).
    cl_abap_unit_assert=>assert_not_initial( ms_result-advice[ advice_id = 'A3' ]-ai_note ).
  ENDMETHOD.


  METHOD names_never_leave.
    mo_llm->answer = `{"headline":"x","narrative":"y"}`.
    mo_cut->enrich( CHANGING cs_result = ms_result ).
    cl_abap_unit_assert=>assert_equals( act = find( val = mo_llm->last_prompt sub = `ABC Industries` ) exp = -1 ).
    cl_abap_unit_assert=>assert_equals( act = find( val = mo_llm->last_prompt sub = `Kappa Chemicals` ) exp = -1 ).
    cl_abap_unit_assert=>assert_differs( act = find( val = mo_llm->last_prompt sub = `CUSTOMER_1` ) exp = -1 ).
  ENDMETHOD.


  METHOD invented_figure.
    DATA(lv_rule_text) = ms_result-brief-narrative.
    mo_llm->answer = `{"headline":"Run holds","narrative":"Cash is $31.4M and the low point is $9.5M."}`.

    mo_cut->enrich( CHANGING cs_result = ms_result ).

    cl_abap_unit_assert=>assert_equals( act = ms_result-brief-engine    exp = zif_cfo_types=>engine-rule ).
    cl_abap_unit_assert=>assert_equals( act = ms_result-brief-narrative exp = lv_rule_text ).
    cl_abap_unit_assert=>assert_char_cp( act = ms_result-brief-error_text exp = `*$31.4M*` ).
  ENDMETHOD.


  METHOD rounding_is_allowed.
    mo_llm->answer = `{"headline":"Run holds","narrative":"A 5-day deposit earns about $1,700 (~$1.7K), 37% early pay beats 4.2%."}`.
    mo_cut->enrich( CHANGING cs_result = ms_result ).
    cl_abap_unit_assert=>assert_equals( act = ms_result-brief-engine exp = zif_cfo_types=>engine-hybrid ).
  ENDMETHOD.


  METHOD destination_down.
    mo_llm->fail = abap_true.
    mo_cut->enrich( CHANGING cs_result = ms_result ).
    cl_abap_unit_assert=>assert_equals( act = ms_result-brief-engine exp = zif_cfo_types=>engine-rule ).
    cl_abap_unit_assert=>assert_char_cp( act = ms_result-brief-error_text exp = `*GEMINI_AI*` ).
    cl_abap_unit_assert=>assert_char_cp( act = ms_result-brief-headline exp = `This week's run holds above floor*` ).
  ENDMETHOD.


  METHOD not_json.
    mo_llm->answer = `Sure! Here is your brief.`.
    mo_cut->enrich( CHANGING cs_result = ms_result ).
    cl_abap_unit_assert=>assert_equals( act = ms_result-brief-engine exp = zif_cfo_types=>engine-rule ).
  ENDMETHOD.


  METHOD copilot_fallback.
    mo_llm->fail = abap_true.
    DATA(ls_answer) = mo_cut->answer( is_result = ms_result iv_question = `What if ABC Industries pays late?` ).
    cl_abap_unit_assert=>assert_equals( act = ls_answer-engine exp = zif_cfo_types=>engine-rule ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_answer-answer exp = `*From today's brief:*` ).
  ENDMETHOD.

ENDCLASS.

"! <p class="shorttext synchronized">CFO Brief - E/A/D with Gemini, guarded, with rule fallback</p>
"! <p>The model only rewrites words. Its answer is accepted when it parses, uses
"! only figures from the facts (ZCL_CFO_FACT_GUARD) and has the requested fields;
"! otherwise the rule-based text stays and ENGINE = RULE with the reason in ERROR_TEXT.</p>
CLASS zcl_cfo_ai_advisor DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_answer,
             answer     TYPE string,
             follow_ups TYPE string,     " newline separated
             engine     TYPE c LENGTH 6,
             model_used TYPE c LENGTH 60,
             error_text TYPE string,
           END OF ty_answer.

    CONSTANTS c_max_headline TYPE i VALUE 200.

    METHODS constructor
      IMPORTING is_config TYPE zif_cfo_types=>ty_config
                io_llm    TYPE REF TO zif_cfo_llm OPTIONAL.

    "! Headline, narrative and per-item notes.
    METHODS enrich
      CHANGING cs_result TYPE zif_cfo_types=>ty_result.

    "! Copilot answer grounded in one brief.
    METHODS answer
      IMPORTING is_result        TYPE zif_cfo_types=>ty_result
                iv_question      TYPE clike
      RETURNING VALUE(rs_answer) TYPE ty_answer.

    "! Rewrites subject and body of a template draft.
    METHODS polish
      IMPORTING is_result TYPE zif_cfo_types=>ty_result
      CHANGING  cs_draft  TYPE zif_cfo_types=>ty_draft.

  PRIVATE SECTION.

    DATA ms_config TYPE zif_cfo_types=>ty_config.
    DATA mo_llm    TYPE REF TO zif_cfo_llm.

    METHODS ask
      IMPORTING iv_prompt       TYPE string
                io_guard        TYPE REF TO zcl_cfo_fact_guard
      RETURNING VALUE(rt_nodes) TYPE zcl_cc_json=>ty_nodes
      RAISING   zcx_cc_error.

    METHODS check_enabled
      RAISING zcx_cc_error.

ENDCLASS.


CLASS zcl_cfo_ai_advisor IMPLEMENTATION.

  METHOD constructor.
    ms_config = is_config.
    mo_llm    = io_llm.
    IF mo_llm IS NOT BOUND AND is_config-ai_enabled = abap_true.
      mo_llm = NEW zcl_cfo_gemini_adapter( is_config ).
    ENDIF.
  ENDMETHOD.


  METHOD check_enabled.
    IF ms_config-ai_enabled = abap_false OR mo_llm IS NOT BOUND.
      zcx_cc_error=>raise( `AI is switched off in ZTCFO_CONFIG - rule-based text shown` ).
    ENDIF.
  ENDMETHOD.


  METHOD ask.
    DATA(lv_answer) = mo_llm->generate( iv_system = zcl_cfo_prompt_builder=>system_instruction( )
                                        iv_prompt = iv_prompt ).
    rt_nodes = zcl_cc_json=>parse( lv_answer ).
    IF rt_nodes IS INITIAL.
      zcx_cc_error=>raise( `The model answer could not be parsed as JSON` ).
    ENDIF.

    " every string the model wrote has to stick to the facts
    LOOP AT rt_nodes INTO DATA(ls_node) WHERE kind = `str`.
      DATA(lv_bad) = io_guard->unsupported( ls_node-value ).
      IF lv_bad IS NOT INITIAL.
        zcx_cc_error=>raise( |The model quoted { lv_bad }, which is not in the facts - rule-based text kept| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD enrich.

    DATA lv_i     TYPE i.
    DATA lv_count TYPE i.

    cs_result-brief-engine = zif_cfo_types=>engine-rule.
    CLEAR: cs_result-brief-model_used, cs_result-brief-error_text.

    TRY.
        check_enabled( ).

        DATA(lo_pseudo)  = NEW zcl_cfo_pseudonymizer( ).
        DATA(lo_builder) = NEW zcl_cfo_prompt_builder( lo_pseudo ).
        DATA(lv_facts)   = lo_builder->facts( cs_result ).
        DATA(lo_guard)   = NEW zcl_cfo_fact_guard( lv_facts ).
        DATA(lt_nodes)   = ask( iv_prompt = lo_builder->brief_prompt( lv_facts ) io_guard = lo_guard ).

        DATA(lv_headline)  = zcl_cc_json=>value( it_nodes = lt_nodes iv_path = `headline` ).
        DATA(lv_narrative) = zcl_cc_json=>value( it_nodes = lt_nodes iv_path = `narrative` ).
        IF lv_headline IS INITIAL OR lv_narrative IS INITIAL.
          zcx_cc_error=>raise( `The model answer had no headline or narrative - rule-based text kept` ).
        ENDIF.

        lv_headline = lo_pseudo->unmask( lv_headline ).
        IF strlen( lv_headline ) > c_max_headline.
          lv_headline = substring( val = lv_headline len = c_max_headline ).
        ENDIF.
        cs_result-brief-headline  = lv_headline.
        cs_result-brief-narrative = lo_pseudo->unmask( lv_narrative ).

        lv_i     = 0.
        lv_count = zcl_cc_json=>count( it_nodes = lt_nodes iv_path = `riskNotes` ).
        DO lv_count TIMES.
          DATA(lv_id)   = to_upper( zcl_cc_json=>value( it_nodes = lt_nodes iv_path = |riskNotes[{ lv_i }].id| ) ).
          DATA(lv_note) = zcl_cc_json=>value( it_nodes = lt_nodes iv_path = |riskNotes[{ lv_i }].note| ).
          ASSIGN cs_result-risks[ risk_id = lv_id ] TO FIELD-SYMBOL(<ls_risk>).
          IF sy-subrc = 0.
            <ls_risk>-ai_note = lo_pseudo->unmask( lv_note ).
          ENDIF.
          UNASSIGN <ls_risk>.
          lv_i += 1.
        ENDDO.

        lv_i     = 0.
        lv_count = zcl_cc_json=>count( it_nodes = lt_nodes iv_path = `adviceNotes` ).
        DO lv_count TIMES.
          lv_id   = to_upper( zcl_cc_json=>value( it_nodes = lt_nodes iv_path = |adviceNotes[{ lv_i }].id| ) ).
          lv_note = zcl_cc_json=>value( it_nodes = lt_nodes iv_path = |adviceNotes[{ lv_i }].note| ).
          ASSIGN cs_result-advice[ advice_id = lv_id ] TO FIELD-SYMBOL(<ls_advice>).
          IF sy-subrc = 0.
            <ls_advice>-ai_note = lo_pseudo->unmask( lv_note ).
          ENDIF.
          UNASSIGN <ls_advice>.
          lv_i += 1.
        ENDDO.

        cs_result-brief-engine     = zif_cfo_types=>engine-hybrid.
        cs_result-brief-model_used = mo_llm->model( ).

      CATCH zcx_cc_error INTO DATA(lx_error).
        cs_result-brief-error_text = lx_error->text.
    ENDTRY.

  ENDMETHOD.


  METHOD answer.

    rs_answer-engine = zif_cfo_types=>engine-rule.

    TRY.
        check_enabled( ).

        DATA(lo_pseudo)  = NEW zcl_cfo_pseudonymizer( ).
        DATA(lo_builder) = NEW zcl_cfo_prompt_builder( lo_pseudo ).
        DATA(lv_facts)   = lo_builder->facts( is_result ).
        DATA(lo_guard)   = NEW zcl_cfo_fact_guard( lv_facts ).
        DATA(lt_nodes)   = ask( iv_prompt = lo_builder->copilot_prompt( iv_facts = lv_facts iv_question = iv_question )
                                io_guard  = lo_guard ).

        rs_answer-answer = lo_pseudo->unmask( zcl_cc_json=>value( it_nodes = lt_nodes iv_path = `answer` ) ).
        IF rs_answer-answer IS INITIAL.
          zcx_cc_error=>raise( `The model returned no answer` ).
        ENDIF.

        DATA(lv_i)     = 0.
        DATA(lv_count) = zcl_cc_json=>count( it_nodes = lt_nodes iv_path = `followUps` ).
        DO lv_count TIMES.
          DATA(lv_follow) = lo_pseudo->unmask( zcl_cc_json=>value( it_nodes = lt_nodes iv_path = |followUps[{ lv_i }]| ) ).
          rs_answer-follow_ups = COND #( WHEN rs_answer-follow_ups IS INITIAL THEN lv_follow
                                         ELSE rs_answer-follow_ups && cl_abap_char_utilities=>newline && lv_follow ).
          lv_i += 1.
        ENDDO.

        rs_answer-engine     = zif_cfo_types=>engine-hybrid.
        rs_answer-model_used = mo_llm->model( ).

      CATCH zcx_cc_error INTO DATA(lx_error).
        rs_answer-error_text = lx_error->text.
        rs_answer-answer     = |The assistant is not available ({ lx_error->text }). | &&
                               |From today's brief: { is_result-brief-narrative }|.
    ENDTRY.

  ENDMETHOD.


  METHOD polish.

    cs_draft-engine = zif_cfo_types=>engine-rule.

    TRY.
        check_enabled( ).

        DATA(lo_pseudo)  = NEW zcl_cfo_pseudonymizer( ).
        DATA(lo_builder) = NEW zcl_cfo_prompt_builder( lo_pseudo ).
        DATA(lv_facts)   = lo_builder->facts( is_result ).
        " the draft's own template figures are facts too
        DATA(lo_guard)   = NEW zcl_cfo_fact_guard( |{ lv_facts } { cs_draft-subject } { cs_draft-body }| ).
        DATA(lt_nodes)   = ask( iv_prompt = lo_builder->draft_prompt( iv_facts = lv_facts is_draft = cs_draft )
                                io_guard  = lo_guard ).

        DATA(lv_subject) = zcl_cc_json=>value( it_nodes = lt_nodes iv_path = `subject` ).
        DATA(lv_body)    = zcl_cc_json=>value( it_nodes = lt_nodes iv_path = `body` ).
        IF lv_subject IS INITIAL OR lv_body IS INITIAL.
          RETURN.
        ENDIF.

        cs_draft-subject = lo_pseudo->unmask( lv_subject ).
        cs_draft-body    = lo_pseudo->unmask( lv_body ).
        cs_draft-engine  = zif_cfo_types=>engine-hybrid.

      CATCH zcx_cc_error INTO DATA(lx_error).
        cs_draft-internal_note = COND #( WHEN cs_draft-internal_note IS INITIAL
                                         THEN |Template text ({ lx_error->text })|
                                         ELSE |{ cs_draft-internal_note } - template text ({ lx_error->text })| ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.

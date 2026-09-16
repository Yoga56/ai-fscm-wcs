"! <p class="shorttext synchronized">CFO Brief - Gemini through the shared BTP destination client</p>
"! <p>Reuses ZCL_CC_GEMINI_CLIENT from the Clean Core Analyzer package (same
"! destination set-up, key never in ABAP). Destination and model come from ZTCFO_CONFIG.</p>
CLASS zcl_cfo_gemini_adapter DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_cfo_llm.

    METHODS constructor
      IMPORTING is_config TYPE zif_cfo_types=>ty_config.

  PRIVATE SECTION.
    DATA mo_client TYPE REF TO zcl_cc_gemini_client.
ENDCLASS.


CLASS zcl_cfo_gemini_adapter IMPLEMENTATION.

  METHOD constructor.
    DATA(lv_destination) = condense( CONV string( is_config-destination ) ).
    DATA(lv_model)       = condense( CONV string( is_config-model ) ).
    IF lv_destination IS INITIAL.
      lv_destination = zcl_cc_gemini_client=>c_default_destination.
    ENDIF.
    IF lv_model IS INITIAL.
      lv_model = zcl_cc_gemini_client=>c_default_model.
    ENDIF.
    mo_client = NEW #( iv_destination = lv_destination
                       iv_model       = lv_model ).
  ENDMETHOD.


  METHOD zif_cfo_llm~generate.
    rv_text = mo_client->generate( iv_system = iv_system iv_prompt = iv_prompt ).
  ENDMETHOD.


  METHOD zif_cfo_llm~model.
    rv_model = mo_client->model( ).
  ENDMETHOD.

ENDCLASS.

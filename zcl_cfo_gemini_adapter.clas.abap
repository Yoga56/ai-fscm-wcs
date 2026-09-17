"! <p class="shorttext synchronized">CFO Brief - Gemini through the shared communication arrangement client</p>
"! <p>Reuses ZCL_CFO_GEMINI_CLIENT (vendored from the Clean Core Analyzer
"! package). The model fallback chain and the communication arrangement to use
"! come from ZTCFO_CONFIG, defaulting to the arrangement the Clean Core
"! Analyzer already set up (same GEMINI_AI communication system, same
"! endpoint).</p>
CLASS zcl_cfo_gemini_adapter DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_cfo_llm.

    METHODS constructor
      IMPORTING is_config TYPE zif_cfo_types=>ty_config.

  PRIVATE SECTION.
    DATA mo_client TYPE REF TO zcl_cfo_gemini_client.
ENDCLASS.


CLASS zcl_cfo_gemini_adapter IMPLEMENTATION.

  METHOD constructor.
    DATA(lv_models)        = condense( CONV string( is_config-models ) ).
    DATA(lv_comm_scenario) = condense( CONV string( is_config-comm_scenario ) ).
    DATA(lv_comm_service)  = condense( CONV string( is_config-comm_service ) ).
    IF lv_models IS INITIAL.
      lv_models = zcl_cfo_gemini_client=>c_default_models.
    ENDIF.
    IF lv_comm_scenario IS INITIAL.
      lv_comm_scenario = zcl_cfo_gemini_client=>c_default_comm_scenario.
    ENDIF.
    IF lv_comm_service IS INITIAL.
      lv_comm_service = zcl_cfo_gemini_client=>c_default_comm_service.
    ENDIF.
    mo_client = NEW #( iv_comm_scenario = lv_comm_scenario
                       iv_comm_service  = lv_comm_service
                       iv_models        = lv_models
                       iv_api_key       = condense( CONV string( is_config-ai_api_key ) ) ).
  ENDMETHOD.


  METHOD zif_cfo_llm~generate.
    rv_text = mo_client->generate( iv_system = iv_system iv_prompt = iv_prompt ).
  ENDMETHOD.


  METHOD zif_cfo_llm~model.
    rv_model = mo_client->model( ).
  ENDMETHOD.

ENDCLASS.

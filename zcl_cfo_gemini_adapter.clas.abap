"! <p class="shorttext synchronized">CFO Brief - Gemini through the shared communication arrangement client</p>
"! <p>Reuses ZCL_CFO_GEMINI_CLIENT (vendored from the Clean Core Analyzer
"! package). Model and the communication arrangement to use come from
"! ZTCFO_CONFIG, defaulting to the arrangement the Clean Core Analyzer already
"! set up (same GEMINI_AI communication system, same endpoint).</p>
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
    DATA(lv_model)         = condense( CONV string( is_config-model ) ).
    DATA(lv_comm_scenario) = condense( CONV string( is_config-comm_scenario ) ).
    DATA(lv_comm_service)  = condense( CONV string( is_config-comm_service ) ).
    IF lv_model IS INITIAL.
      lv_model = zcl_cfo_gemini_client=>c_default_model.
    ENDIF.
    IF lv_comm_scenario IS INITIAL.
      lv_comm_scenario = zcl_cfo_gemini_client=>c_default_comm_scenario.
    ENDIF.
    IF lv_comm_service IS INITIAL.
      lv_comm_service = zcl_cfo_gemini_client=>c_default_comm_service.
    ENDIF.
    mo_client = NEW #( iv_comm_scenario = lv_comm_scenario
                       iv_comm_service  = lv_comm_service
                       iv_model         = lv_model ).
  ENDMETHOD.


  METHOD zif_cfo_llm~generate.
    rv_text = mo_client->generate( iv_system = iv_system iv_prompt = iv_prompt ).
  ENDMETHOD.


  METHOD zif_cfo_llm~model.
    rv_model = mo_client->model( ).
  ENDMETHOD.

ENDCLASS.

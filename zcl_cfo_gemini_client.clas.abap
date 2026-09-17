"! <p class="shorttext synchronized">Calls Gemini through a communication arrangement</p>
"! <p>Outbound communication uses the released ABAP Cloud stack:
"! CL_HTTP_DESTINATION_PROVIDER + CL_WEB_HTTP_CLIENT_MANAGER. The API key never
"! lives in ABAP source - it is read from ZTCFO_CONFIG at runtime (see
"! docs/setup.md).</p>
"! <p>Three connection modes. COMM is the default: a communication arrangement,
"! which is how S/4HANA Cloud (and on-stack ABAP Cloud) do outbound HTTP.
"! S/4HANA Cloud Public Edition has no BTP destination service, so DEST (a plain
"! BTP destination) only works on SAP BTP ABAP Environment. URL is for sandbox
"! testing and keeps the key in ABAP memory - do not ship it.</p>
"! <p>The client walks a comma-separated chain of models in order and returns
"! the first answer it gets. It only moves on when the failure is one another
"! model could survive - an unknown model id, a per-model quota, an overloaded
"! backend. A blocked prompt or a malformed response fails immediately instead
"! of burning the whole chain.</p>
"! <p>Loosely copied from ZCL_CC_GEMINI_CLIENT (Clean Core Analyzer package) so
"! this repository has no cross-package dependency. That package's own client,
"! ZCL_CA_CC_GEMINI_CLIENT, is the richer reference implementation (a settings
"! table, per-setting overrides) - this one stays deliberately simpler.</p>
CLASS zcl_cfo_gemini_client DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS c_default_destination   TYPE string VALUE `GEMINI_AI`.
    CONSTANTS c_default_path          TYPE string VALUE `/v1beta`.

    "! Comma separated, tried strictly left to right.
    CONSTANTS c_default_models TYPE string
      VALUE `gemini-3.8-flash,gemini-3.7-flash,gemini-3.6-flash,gemini-3.5-flash`.

    " Reuses the communication arrangement already set up for the Clean Core
    " Analyzer package (same GEMINI_AI communication system, same endpoint).
    CONSTANTS c_default_comm_scenario TYPE string VALUE `ZCA_CCORE_OUT`.
    CONSTANTS c_default_comm_service  TYPE string VALUE `ZCA_CCORE_REST`.

    CONSTANTS: BEGIN OF mode,
                 "! Communication arrangement - S/4HANA Cloud, on-stack ABAP Cloud
                 comm_arrangement TYPE string VALUE `COMM`,
                 "! BTP destination service - SAP BTP ABAP Environment only
                 destination      TYPE string VALUE `DEST`,
                 "! Plain URL - sandbox testing only, puts the key in ABAP memory
                 url              TYPE string VALUE `URL`,
               END OF mode.

    METHODS constructor
      IMPORTING iv_mode          TYPE string DEFAULT `COMM`
                iv_comm_scenario TYPE string DEFAULT c_default_comm_scenario
                iv_comm_service  TYPE string DEFAULT c_default_comm_service
                iv_destination   TYPE string DEFAULT c_default_destination
                iv_models        TYPE string DEFAULT c_default_models
                iv_path_prefix   TYPE string DEFAULT c_default_path
                iv_base_url      TYPE string OPTIONAL
                iv_api_key       TYPE string OPTIONAL.

    "! Sends one generateContent request per model until one answers.
    METHODS generate
      IMPORTING iv_system      TYPE string OPTIONAL
                iv_prompt      TYPE string
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_cfo_error.

    "! The model that actually answered the last generate( ) call, or the
    "! first configured model before any call has been made.
    METHODS model
      RETURNING VALUE(rv_model) TYPE string.

  PRIVATE SECTION.

    DATA mv_mode          TYPE string.
    DATA mv_comm_scenario TYPE string.
    DATA mv_comm_service  TYPE string.
    DATA mv_destination   TYPE string.
    DATA mv_models        TYPE string.
    DATA mv_path_prefix   TYPE string.
    DATA mv_base_url      TYPE string.
    DATA mv_api_key       TYPE string.
    DATA mv_model_used     TYPE string.

    METHODS models
      RETURNING VALUE(rt_models) TYPE string_table.

    METHODS destination
      RETURNING VALUE(ro_destination) TYPE REF TO if_http_destination
      RAISING   zcx_cfo_error.

    METHODS call_model
      IMPORTING iv_model       TYPE string
                iv_system      TYPE string
                iv_prompt      TYPE string
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_cfo_error.

    METHODS build_body
      IMPORTING iv_system      TYPE string
                iv_prompt      TYPE string
      RETURNING VALUE(rv_body) TYPE string.

    "! Pulls candidates[0].content.parts[*].text out of the Gemini envelope.
    METHODS unwrap
      IMPORTING iv_payload     TYPE string
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_cfo_error.

    "! 404 unknown model, 429 quota for this model, 5xx overloaded - the next
    "! model may still work. 400/401/403 are key, project or request problems.
    CLASS-METHODS is_retryable
      IMPORTING iv_code         TYPE i
      RETURNING VALUE(rv_retry) TYPE abap_bool.

ENDCLASS.


CLASS zcl_cfo_gemini_client IMPLEMENTATION.

  METHOD constructor.
    mv_mode          = iv_mode.
    mv_comm_scenario = iv_comm_scenario.
    mv_comm_service  = iv_comm_service.
    mv_destination   = iv_destination.
    mv_models        = iv_models.
    mv_path_prefix   = iv_path_prefix.
    mv_base_url      = iv_base_url.
    mv_api_key       = iv_api_key.
  ENDMETHOD.


  METHOD models.
    SPLIT mv_models AT `,` INTO TABLE rt_models.
    LOOP AT rt_models ASSIGNING FIELD-SYMBOL(<lv_model>).
      <lv_model> = condense( <lv_model> ).
    ENDLOOP.
    DELETE rt_models WHERE table_line IS INITIAL.
  ENDMETHOD.


  METHOD model.
    rv_model = mv_model_used.
    IF rv_model IS INITIAL.
      DATA(lt_models) = models( ).
      IF lt_models IS NOT INITIAL.
        rv_model = lt_models[ 1 ].
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD is_retryable.
    rv_retry = xsdbool( iv_code = 404 OR iv_code = 429 OR iv_code >= 500 ).
  ENDMETHOD.


  METHOD destination.

    DATA lv_what TYPE string.

    TRY.
        CASE mv_mode.

          WHEN mode-url.
            lv_what = |URL { mv_base_url }|.
            IF mv_base_url IS INITIAL.
              zcx_cfo_error=>raise( `URL mode requires a base URL` ).
            ENDIF.
            ro_destination = cl_http_destination_provider=>create_by_url( i_url = mv_base_url ).

          WHEN mode-destination.
            lv_what = |BTP destination { mv_destination }|.
            ro_destination = cl_http_destination_provider=>create_by_cloud_destination(
                               i_name = CONV #( mv_destination ) ).

          WHEN OTHERS.
            lv_what = |communication arrangement { mv_comm_scenario } / { mv_comm_service }|.
            ro_destination = cl_http_destination_provider=>create_by_comm_arrangement(
                               comm_scenario = CONV #( mv_comm_scenario )
                               service_id    = CONV #( mv_comm_service ) ).

        ENDCASE.

      CATCH cx_http_dest_provider_error INTO DATA(lx_dest).
        " not model related - never retry another model over this
        zcx_cfo_error=>raise(
          text     = |Cannot resolve { lv_what }: { lx_dest->get_text( ) }|
          previous = lx_dest ).
    ENDTRY.

  ENDMETHOD.


  METHOD generate.

    CLEAR mv_model_used.

    DATA(lt_models) = models( ).
    IF lt_models IS INITIAL.
      zcx_cfo_error=>raise( `No Gemini model is configured` ).
    ENDIF.

    DATA lt_skipped TYPE string_table.

    LOOP AT lt_models INTO DATA(lv_model).

      TRY.
          rv_text     = call_model( iv_model  = lv_model
                                    iv_system = iv_system
                                    iv_prompt = iv_prompt ).
          mv_model_used = lv_model.
          RETURN.

        CATCH zcx_cfo_error INTO DATA(lx_call).
          IF lx_call->retryable = abap_false.
            " a key, project or content problem repeats on every model - stop now
            RAISE EXCEPTION lx_call.
          ENDIF.
          APPEND |{ lv_model } ({ lx_call->text })| TO lt_skipped.
      ENDTRY.

    ENDLOOP.

    zcx_cfo_error=>raise(
      |All { lines( lt_models ) } configured models failed - | &&
      |{ concat_lines_of( table = lt_skipped sep = ` | ` ) }| ).

  ENDMETHOD.


  METHOD call_model.

    DATA(lo_destination) = destination( ).

    DATA lo_client TYPE REF TO if_web_http_client.

    TRY.
        lo_client = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        DATA(lo_request) = lo_client->get_http_request( ).
        lo_request->set_uri_path( i_uri_path = |{ mv_path_prefix }/models/{ iv_model }:generateContent| ).
        lo_request->set_header_field( i_name = `Content-Type` i_value = `application/json` ).
        lo_request->set_header_field( i_name = `Accept`       i_value = `application/json` ).

        " Only set when the key is not configured on the destination itself.
        IF mv_api_key IS NOT INITIAL.
          lo_request->set_header_field( i_name = `x-goog-api-key` i_value = mv_api_key ).
        ENDIF.

        lo_request->set_text( build_body( iv_system = iv_system iv_prompt = iv_prompt ) ).

        DATA(lo_response) = lo_client->execute( i_method = if_web_http_client=>post ).
        DATA(lv_status)   = lo_response->get_status( ).
        DATA(lv_payload)  = lo_response->get_text( ).

        lo_client->close( ).

      CATCH cx_web_http_client_error cx_web_message_error INTO DATA(lx_http).
        " transport level - the same host fails for every model
        zcx_cfo_error=>raise( text     = |Call to Gemini failed: { lx_http->get_text( ) }|
                              previous = lx_http ).
    ENDTRY.

    IF lv_status-code >= 300.
      DATA(lv_detail) = lv_payload.
      TRY.
          DATA(lt_err) = zcl_cfo_json=>parse( lv_payload ).
          DATA(lv_msg) = zcl_cfo_json=>value( it_nodes = lt_err iv_path = `error.message` ).
          IF lv_msg IS NOT INITIAL.
            lv_detail = lv_msg.
          ENDIF.
        CATCH zcx_cfo_error.
      ENDTRY.
      zcx_cfo_error=>raise( text      = |HTTP { lv_status-code } { lv_status-reason }: { lv_detail }|
                            retryable = is_retryable( lv_status-code ) ).
    ENDIF.

    rv_text = unwrap( lv_payload ).

  ENDMETHOD.


  METHOD build_body.

    DATA lv_system_part TYPE string.

    IF iv_system IS NOT INITIAL.
      lv_system_part = |"systemInstruction":\{"parts":[\{"text":"{ zcl_cfo_json=>escape( iv_system ) }"\}]\},|.
    ENDIF.

    rv_body =
      |\{|                                                                            &&
      lv_system_part                                                                  &&
      |"contents":[\{"role":"user","parts":[\{"text":"|                               &&
      zcl_cfo_json=>escape( iv_prompt )                                               &&
      |"\}]\}],|                                                                      &&
      |"generationConfig":\{"temperature":0.1,"topP":0.9,|                            &&
      |"maxOutputTokens":16384,"responseMimeType":"application/json"\}|               &&
      |\}|.

  ENDMETHOD.


  METHOD unwrap.

    DATA(lt_nodes) = zcl_cfo_json=>parse( iv_payload ).

    DATA(lv_block) = zcl_cfo_json=>value( it_nodes = lt_nodes iv_path = `promptFeedback.blockReason` ).
    IF lv_block IS NOT INITIAL.
      " a safety filter reacts to the content, not to the model - do not retry
      zcx_cfo_error=>raise( |Gemini blocked the request: { lv_block }| ).
    ENDIF.

    IF zcl_cfo_json=>count( it_nodes = lt_nodes iv_path = `candidates` ) = 0.
      zcx_cfo_error=>raise( text = `Gemini returned no candidate` retryable = abap_true ).
    ENDIF.

    DATA(lv_parts) = zcl_cfo_json=>count( it_nodes = lt_nodes
                                          iv_path  = `candidates[0].content.parts` ).
    DATA lv_index TYPE i VALUE 0.
    WHILE lv_index < lv_parts.
      rv_text = rv_text && zcl_cfo_json=>value(
                             it_nodes = lt_nodes
                             iv_path  = |candidates[0].content.parts[{ lv_index }].text| ).
      lv_index = lv_index + 1.
    ENDWHILE.

    IF rv_text IS INITIAL.
      DATA(lv_reason) = zcl_cfo_json=>value( it_nodes = lt_nodes
                                             iv_path  = `candidates[0].finishReason` ).
      zcx_cfo_error=>raise( text      = |Gemini returned an empty answer (finishReason { lv_reason })|
                            retryable = abap_true ).
    ENDIF.

    rv_text = zcl_cfo_json=>strip_code_fence( rv_text ).

  ENDMETHOD.

ENDCLASS.

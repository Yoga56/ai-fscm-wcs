"! <p class="shorttext synchronized">Calls Gemini through a BTP destination</p>
"! <p>Outbound communication uses the released ABAP Cloud stack:
"! CL_HTTP_DESTINATION_PROVIDER + CL_WEB_HTTP_CLIENT_MANAGER. The API key never
"! lives in ABAP - it is configured on the destination (see docs/setup.md).</p>
"! <p>Copied from ZCL_CC_GEMINI_CLIENT (Clean Core Analyzer package) so this
"! repository has no cross-package dependency. Keep the two in sync if either
"! changes.</p>
CLASS zcl_cfo_gemini_client DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS c_default_destination TYPE string VALUE `GEMINI_AI`.
    CONSTANTS c_default_model       TYPE string VALUE `gemini-2.5-pro`.
    CONSTANTS c_default_path        TYPE string VALUE `/v1beta`.

    CONSTANTS: BEGIN OF mode,
                 destination TYPE string VALUE `DEST`,
                 url         TYPE string VALUE `URL`,
               END OF mode.

    METHODS constructor
      IMPORTING iv_destination TYPE string DEFAULT c_default_destination
                iv_model       TYPE string DEFAULT c_default_model
                iv_path_prefix TYPE string DEFAULT c_default_path
                iv_mode        TYPE string DEFAULT `DEST`
                iv_base_url    TYPE string OPTIONAL
                iv_api_key     TYPE string OPTIONAL.

    "! Sends one generateContent request and returns the model's answer text.
    METHODS generate
      IMPORTING iv_system      TYPE string OPTIONAL
                iv_prompt      TYPE string
      RETURNING VALUE(rv_text) TYPE string
      RAISING   zcx_cfo_error.

    METHODS model
      RETURNING VALUE(rv_model) TYPE string.

  PRIVATE SECTION.

    DATA mv_destination TYPE string.
    DATA mv_model       TYPE string.
    DATA mv_path_prefix TYPE string.
    DATA mv_mode        TYPE string.
    DATA mv_base_url    TYPE string.
    DATA mv_api_key     TYPE string.

    METHODS destination
      RETURNING VALUE(ro_destination) TYPE REF TO if_http_destination
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

ENDCLASS.


CLASS zcl_cfo_gemini_client IMPLEMENTATION.

  METHOD constructor.
    mv_destination = iv_destination.
    mv_model       = iv_model.
    mv_path_prefix = iv_path_prefix.
    mv_mode        = iv_mode.
    mv_base_url    = iv_base_url.
    mv_api_key     = iv_api_key.
  ENDMETHOD.


  METHOD model.
    rv_model = mv_model.
  ENDMETHOD.


  METHOD destination.

    TRY.
        IF mv_mode = mode-url.
          IF mv_base_url IS INITIAL.
            zcx_cfo_error=>raise( `URL mode requires a base URL` ).
          ENDIF.
          ro_destination = cl_http_destination_provider=>create_by_url( i_url = mv_base_url ).
        ELSE.
          ro_destination = cl_http_destination_provider=>create_by_cloud_destination(
                             i_name = CONV #( mv_destination ) ).
        ENDIF.

      CATCH cx_http_dest_provider_error INTO DATA(lx_dest).
        zcx_cfo_error=>raise(
          text     = |Destination { mv_destination } cannot be resolved: { lx_dest->get_text( ) }|
          previous = lx_dest ).
    ENDTRY.

  ENDMETHOD.


  METHOD generate.

    DATA(lo_destination) = destination( ).

    DATA lo_client TYPE REF TO if_web_http_client.

    TRY.
        lo_client = cl_web_http_client_manager=>create_by_http_destination( lo_destination ).

        DATA(lo_request) = lo_client->get_http_request( ).
        lo_request->set_uri_path( i_uri_path = |{ mv_path_prefix }/models/{ mv_model }:generateContent| ).
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
      zcx_cfo_error=>raise( |Gemini returned HTTP { lv_status-code } { lv_status-reason }: { lv_detail }| ).
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
      zcx_cfo_error=>raise( |Gemini blocked the request: { lv_block }| ).
    ENDIF.

    IF zcl_cfo_json=>count( it_nodes = lt_nodes iv_path = `candidates` ) = 0.
      zcx_cfo_error=>raise( `Gemini returned no candidate` ).
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
      zcx_cfo_error=>raise( |Gemini returned an empty answer (finishReason { lv_reason })| ).
    ENDIF.

    rv_text = zcl_cfo_json=>strip_code_fence( rv_text ).

  ENDMETHOD.

ENDCLASS.

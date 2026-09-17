"! <p class="shorttext synchronized">Minimal, released-API-only JSON reader/writer helper</p>
"! <p>Uses the sXML reader (released for ABAP Cloud) to flatten any JSON document
"! into a list of (path, value) pairs, e.g.
"! <em>candidates[0].content.parts[0].text</em>. That keeps the consumer free of
"! generated DDIC structures and tolerant against additional payload fields.</p>
"! <p>Copied from ZCL_CC_JSON (Clean Core Analyzer package) so this repository
"! has no cross-package dependency. Keep the two in sync if either changes.</p>
CLASS zcl_cfo_json DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_node,
             path  TYPE string,
             kind  TYPE string,   "! object / array / str / num / bool / null
             value TYPE string,
           END OF ty_node,
           ty_nodes TYPE STANDARD TABLE OF ty_node WITH EMPTY KEY.

    "! Flattens a JSON document.
    CLASS-METHODS parse
      IMPORTING iv_json         TYPE string
      RETURNING VALUE(rt_nodes) TYPE ty_nodes
      RAISING   zcx_cfo_error.

    "! Value of a single path, empty when the path does not exist.
    CLASS-METHODS value
      IMPORTING it_nodes     TYPE ty_nodes
                iv_path      TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    CLASS-METHODS value_int
      IMPORTING it_nodes     TYPE ty_nodes
                iv_path      TYPE string
      RETURNING VALUE(rv_value) TYPE i.

    CLASS-METHODS value_dec
      IMPORTING it_nodes        TYPE ty_nodes
                iv_path         TYPE string
      RETURNING VALUE(rv_value) TYPE decfloat34.

    "! Number of entries in the array at iv_path.
    CLASS-METHODS count
      IMPORTING it_nodes        TYPE ty_nodes
                iv_path         TYPE string
      RETURNING VALUE(rv_count) TYPE i.

    "! Escapes a string so it can be embedded in a JSON string literal.
    CLASS-METHODS escape
      IMPORTING iv_text         TYPE string
      RETURNING VALUE(rv_text)  TYPE string.

    "! Removes a leading ```json / trailing ``` fence some models add.
    CLASS-METHODS strip_code_fence
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

  PRIVATE SECTION.

    TYPES: BEGIN OF ty_ctx,
             path     TYPE string,
             is_array TYPE abap_bool,
             idx      TYPE i,
           END OF ty_ctx.

ENDCLASS.


CLASS zcl_cfo_json IMPLEMENTATION.

  METHOD parse.

    DATA lt_stack     TYPE STANDARD TABLE OF ty_ctx WITH EMPTY KEY.
    DATA lv_cur_path  TYPE string.
    DATA lv_cur_kind  TYPE string.
    DATA lv_cur_value TYPE string.
    DATA lv_pending   TYPE abap_bool.

    IF iv_json IS INITIAL.
      RETURN.
    ENDIF.

    DATA lv_xjson TYPE xstring.
    TRY.
        lv_xjson = cl_abap_conv_codepage=>create_out( codepage = `UTF-8` )->convert( source = iv_json ).
      CATCH cx_root INTO DATA(lx_conv).
        zcx_cfo_error=>raise( text = |Cannot encode JSON payload: { lx_conv->get_text( ) }| previous = lx_conv ).
    ENDTRY.

    TRY.
        DATA(lo_reader) = cl_sxml_string_reader=>create( lv_xjson ).
        DATA(lo_node)   = lo_reader->read_next_node( ).

        WHILE lo_node IS BOUND.

          CASE lo_node->type.

            WHEN if_sxml_node=>co_nt_element_open.
              DATA(lo_open) = CAST if_sxml_open_element( lo_node ).
              DATA(lv_elem) = to_lower( CONV string( lo_open->qname-name ) ).

              DATA lv_member TYPE string.
              CLEAR lv_member.
              LOOP AT lo_open->get_attributes( ) INTO DATA(lo_attr).
                IF to_lower( CONV string( lo_attr->qname-name ) ) = `name`.
                  lv_member = lo_attr->get_value( ).
                ENDIF.
              ENDLOOP.

              DATA lv_path TYPE string.
              CLEAR lv_path.
              IF lt_stack IS NOT INITIAL.
                FIELD-SYMBOLS <ls_top> TYPE ty_ctx.
                READ TABLE lt_stack ASSIGNING <ls_top> INDEX lines( lt_stack ).
                IF <ls_top>-is_array = abap_true.
                  lv_path       = |{ <ls_top>-path }[{ <ls_top>-idx }]|.
                  <ls_top>-idx  = <ls_top>-idx + 1.
                ELSEIF <ls_top>-path IS INITIAL.
                  lv_path = lv_member.
                ELSE.
                  lv_path = |{ <ls_top>-path }.{ lv_member }|.
                ENDIF.
              ENDIF.

              IF lv_elem = `object` OR lv_elem = `array`.
                APPEND VALUE #( path = lv_path kind = lv_elem ) TO rt_nodes.
                APPEND VALUE #( path     = lv_path
                                is_array = COND #( WHEN lv_elem = `array` THEN abap_true ELSE abap_false )
                                idx      = 0 ) TO lt_stack.
              ELSE.
                lv_cur_path  = lv_path.
                lv_cur_kind  = lv_elem.
                lv_pending   = abap_true.
                CLEAR lv_cur_value.
              ENDIF.

            WHEN if_sxml_node=>co_nt_value.
              lv_cur_value = CAST if_sxml_value_node( lo_node )->get_value( ).

            WHEN if_sxml_node=>co_nt_element_close.
              DATA(lo_close) = CAST if_sxml_close_element( lo_node ).
              DATA(lv_celem) = to_lower( CONV string( lo_close->qname-name ) ).
              IF lv_celem = `object` OR lv_celem = `array`.
                IF lt_stack IS NOT INITIAL.
                  DELETE lt_stack INDEX lines( lt_stack ).
                ENDIF.
              ELSEIF lv_pending = abap_true.
                APPEND VALUE #( path  = lv_cur_path
                                kind  = lv_cur_kind
                                value = lv_cur_value ) TO rt_nodes.
                CLEAR: lv_pending, lv_cur_path, lv_cur_kind, lv_cur_value.
              ENDIF.

            WHEN OTHERS.
              " attributes and other node types are irrelevant for JSON

          ENDCASE.

          lo_node = lo_reader->read_next_node( ).

        ENDWHILE.

      CATCH cx_root INTO DATA(lx_sxml).
        zcx_cfo_error=>raise( text     = |Malformed JSON response: { lx_sxml->get_text( ) }|
                              previous = lx_sxml ).
    ENDTRY.

  ENDMETHOD.


  METHOD value.
    READ TABLE it_nodes INTO DATA(ls_node) WITH KEY path = iv_path.
    IF sy-subrc = 0.
      rv_value = ls_node-value.
    ENDIF.
  ENDMETHOD.


  METHOD value_int.
    DATA(lv_raw) = value( it_nodes = it_nodes iv_path = iv_path ).
    IF lv_raw IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        rv_value = round( val = CONV decfloat34( lv_raw ) dec = 0 ).
      CATCH cx_sy_conversion_error.
        CLEAR rv_value.
    ENDTRY.
  ENDMETHOD.


  METHOD value_dec.
    DATA(lv_raw) = value( it_nodes = it_nodes iv_path = iv_path ).
    IF lv_raw IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        rv_value = CONV decfloat34( lv_raw ).
      CATCH cx_sy_conversion_error.
        CLEAR rv_value.
    ENDTRY.
  ENDMETHOD.


  METHOD count.

    DATA lv_max TYPE i VALUE -1.

    DATA(lv_prefix) = |{ iv_path }[|.
    DATA(lv_len)    = strlen( lv_prefix ).

    LOOP AT it_nodes INTO DATA(ls_node).
      IF strlen( ls_node-path ) <= lv_len.
        CONTINUE.
      ENDIF.
      IF substring( val = ls_node-path len = lv_len ) <> lv_prefix.
        CONTINUE.
      ENDIF.
      DATA(lv_rest) = substring( val = ls_node-path off = lv_len ).
      SPLIT lv_rest AT `]` INTO DATA(lv_index) DATA(lv_tail).
      TRY.
          DATA(lv_idx) = CONV i( lv_index ).
        CATCH cx_sy_conversion_error.
          CONTINUE.
      ENDTRY.
      IF lv_idx > lv_max.
        lv_max = lv_idx.
      ENDIF.
    ENDLOOP.

    rv_count = lv_max + 1.

  ENDMETHOD.


  METHOD escape.
    rv_text = iv_text.
    rv_text = replace( val = rv_text sub = `\` with = `\\` occ = 0 ).
    rv_text = replace( val = rv_text sub = `"`  with = `\"` occ = 0 ).
    rv_text = replace( val = rv_text sub = cl_abap_char_utilities=>cr_lf
                       with = `\n` occ = 0 ).
    rv_text = replace( val = rv_text sub = cl_abap_char_utilities=>newline
                       with = `\n` occ = 0 ).
    rv_text = replace( val = rv_text sub = cl_abap_char_utilities=>horizontal_tab
                       with = `\t` occ = 0 ).
    " strip any remaining control characters that JSON does not allow raw
    rv_text = replace( val = rv_text pcre = `[\x00-\x1F]` with = ` ` occ = 0 ).
  ENDMETHOD.


  METHOD strip_code_fence.
    rv_text = condense( iv_text ).
    IF rv_text CP '```*'.
      rv_text = replace( val = rv_text pcre = `^\x60\x60\x60[A-Za-z]*\s*` with = `` occ = 1 ).
      rv_text = replace( val = rv_text pcre = `\s*\x60\x60\x60\s*$`      with = `` occ = 1 ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

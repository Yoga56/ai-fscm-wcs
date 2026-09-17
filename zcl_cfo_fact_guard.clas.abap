"! <p class="shorttext synchronized">CFO Brief - rejects AI text that quotes figures not in the facts</p>
"! <p>Every money amount ($22.0M, $1,726, €3M) and percentage in the model's answer
"! must match a figure that was in the facts sent to the model - within the rounding
"! the model is allowed ($9.5M may be written as $9.5M or $9,500,000; $1,726 as $1.7K
"! or $1,700). Anything else means the model computed or invented a number, and the
"! caller falls back to the template text.</p>
CLASS zcl_cfo_fact_guard DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_figure,
             kind  TYPE c LENGTH 1,        " M money / P percent / N plain number
             value TYPE decfloat34,
             unit  TYPE decfloat34,        " 1, 1000 or 1000000 as written
             text  TYPE string,
           END OF ty_figure,
           tt_figure TYPE STANDARD TABLE OF ty_figure WITH EMPTY KEY.

    "! All figures of the facts text become allowed.
    METHODS constructor
      IMPORTING iv_facts TYPE string.

    "! Returns the first figure that is not supported, empty if all are.
    METHODS unsupported
      IMPORTING iv_text          TYPE clike
      RETURNING VALUE(rv_figure) TYPE string.

    CLASS-METHODS figures
      IMPORTING iv_text           TYPE clike
                iv_with_plain     TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(rt_figures) TYPE tt_figure.

  PRIVATE SECTION.

    CONSTANTS c_money_pcre   TYPE string VALUE `[$€£]\s?\d[\d,]*(?:\.\d+)?\s?(?:[MmKk](?![a-z]))?`.
    CONSTANTS c_percent_pcre TYPE string VALUE `\d+(?:\.\d+)?\s?%`.
    CONSTANTS c_plain_pcre   TYPE string VALUE `\d+(?:\.\d+)?`.
    CONSTANTS c_pct_abs      TYPE decfloat34 VALUE '0.5'.
    CONSTANTS c_rel          TYPE decfloat34 VALUE '0.02'.

    DATA mt_amounts  TYPE STANDARD TABLE OF decfloat34 WITH EMPTY KEY.
    DATA mt_percents TYPE STANDARD TABLE OF decfloat34 WITH EMPTY KEY.

    CLASS-METHODS to_number
      IMPORTING iv_text         TYPE string
      EXPORTING ev_unit         TYPE decfloat34
      RETURNING VALUE(rv_value) TYPE decfloat34.

    CLASS-METHODS scan
      IMPORTING iv_text    TYPE string
                iv_pcre    TYPE string
                iv_kind    TYPE c
      CHANGING  ct_figures TYPE tt_figure.

ENDCLASS.


CLASS zcl_cfo_fact_guard IMPLEMENTATION.

  METHOD constructor.
    DATA(lt_figures) = figures( iv_text = iv_facts iv_with_plain = abap_true ).
    LOOP AT lt_figures INTO DATA(ls_figure).
      CASE ls_figure-kind.
        WHEN 'P'.
          APPEND ls_figure-value TO mt_percents.
        WHEN OTHERS.
          APPEND ls_figure-value TO mt_amounts.
          IF ls_figure-kind = 'N' AND ls_figure-value <= 1.
            APPEND ls_figure-value * 100 TO mt_percents.  " probability 0.75 -> 75%
          ENDIF.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.


  METHOD unsupported.

    DATA(lt_figures) = figures( iv_text ).
    LOOP AT lt_figures INTO DATA(ls_figure).
      DATA(lv_ok) = abap_false.

      IF ls_figure-kind = 'P'.
        LOOP AT mt_percents INTO DATA(lv_pct).
          IF abs( ls_figure-value - lv_pct ) <= c_pct_abs OR abs( ls_figure-value - lv_pct ) <= abs( lv_pct ) / 100.
            lv_ok = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ELSE.
        " allowed rounding: half of the unit the model wrote, or 2 % of the fact
        DATA(lv_half) = ls_figure-unit / 2.
        IF ls_figure-unit >= 1000.
          lv_half = ls_figure-unit / 10 / 2 * COND decfloat34( WHEN find( val = ls_figure-text sub = `.` ) >= 0 THEN 1 ELSE 10 ).
        ENDIF.
        LOOP AT mt_amounts INTO DATA(lv_amount).
          DATA(lv_diff) = abs( ls_figure-value - abs( lv_amount ) ).
          IF lv_diff <= lv_half OR lv_diff <= abs( lv_amount ) * c_rel.
            lv_ok = abap_true.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.

      IF lv_ok = abap_false.
        rv_figure = ls_figure-text.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD figures.
    DATA(lv_text) = CONV string( iv_text ).
    scan( EXPORTING iv_text = lv_text iv_pcre = c_money_pcre   iv_kind = 'M' CHANGING ct_figures = rt_figures ).
    scan( EXPORTING iv_text = lv_text iv_pcre = c_percent_pcre iv_kind = 'P' CHANGING ct_figures = rt_figures ).
    IF iv_with_plain = abap_true.
      scan( EXPORTING iv_text = lv_text iv_pcre = c_plain_pcre iv_kind = 'N' CHANGING ct_figures = rt_figures ).
    ENDIF.
  ENDMETHOD.


  METHOD scan.
    FIND ALL OCCURRENCES OF PCRE iv_pcre IN iv_text RESULTS DATA(lt_hits).
    DATA lv_unit  TYPE decfloat34.
    DATA lv_value TYPE decfloat34.
    LOOP AT lt_hits INTO DATA(ls_hit).
      DATA(lv_token) = substring( val = iv_text off = ls_hit-offset len = ls_hit-length ).
      TRY.
          lv_value = to_number( EXPORTING iv_text = lv_token IMPORTING ev_unit = lv_unit ).
          APPEND VALUE #( kind = iv_kind value = lv_value unit = lv_unit text = lv_token ) TO ct_figures.
        CATCH cx_sy_conversion_error.
          " not a number after all - ignore
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.


  METHOD to_number.
    DATA(lv_text) = to_upper( iv_text ).
    ev_unit = 1.
    IF find( val = lv_text sub = `M` ) >= 0.
      ev_unit = 1000000.
    ELSEIF find( val = lv_text sub = `K` ) >= 0.
      ev_unit = 1000.
    ENDIF.
    lv_text = replace( val = lv_text pcre = `[^0-9.]` with = `` occ = 0 ).
    rv_value = CONV decfloat34( lv_text ) * ev_unit.
  ENDMETHOD.

ENDCLASS.

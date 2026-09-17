"! <p class="shorttext synchronized">CFO Brief - executive number formatting</p>
"! <p>Always uses a period as decimal separator so that the same strings can be
"! checked by ZCL_CFO_FACT_GUARD against what the model writes.</p>
CLASS zcl_cfo_format DEFINITION
  PUBLIC
  FINAL
  ABSTRACT.

  PUBLIC SECTION.

    "! >= 100 000 -> "$22.0M", below -> "$1,726"
    CLASS-METHODS money
      IMPORTING iv_amount      TYPE numeric
                iv_currency    TYPE clike DEFAULT 'USD'
      RETURNING VALUE(rv_text) TYPE string.

    "! "11.9%" (sign is not printed)
    CLASS-METHODS percent
      IMPORTING iv_value       TYPE numeric
      RETURNING VALUE(rv_text) TYPE string.

    "! 1 -> "one" ... 10 -> "ten"
    CLASS-METHODS count_word
      IMPORTING iv_count       TYPE i
      RETURNING VALUE(rv_text) TYPE string.

    "! "ABC Industries'" / "Globex Corp's"
    CLASS-METHODS possessive
      IMPORTING iv_name        TYPE clike
      RETURNING VALUE(rv_text) TYPE string.

    "! 4.200 -> "4.2", 2.00 -> "2", 18.385 (max 1) -> "18.4"
    CLASS-METHODS number
      IMPORTING iv_value        TYPE numeric
                iv_max_decimals TYPE i DEFAULT 3
      RETURNING VALUE(rv_text)  TYPE string.

    CLASS-METHODS symbol
      IMPORTING iv_currency    TYPE clike
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS group_thousands
      IMPORTING iv_value       TYPE int8
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.


CLASS zcl_cfo_format IMPLEMENTATION.

  METHOD money.
    DATA lv_millions TYPE p LENGTH 16 DECIMALS 1.
    DATA lv_whole    TYPE int8.

    DATA(lv_amount) = CONV decfloat34( iv_amount ).
    DATA(lv_abs)    = abs( lv_amount ).
    DATA(lv_sign)   = COND string( WHEN lv_amount < 0 THEN `-` ELSE `` ).

    IF lv_abs >= 100000.
      lv_millions = lv_abs / 1000000.
      rv_text = |{ lv_sign }{ symbol( iv_currency ) }{ lv_millions NUMBER = RAW }M|.
    ELSE.
      lv_whole = round( val = lv_abs dec = 0 ).
      rv_text = |{ lv_sign }{ symbol( iv_currency ) }{ group_thousands( lv_whole ) }|.
    ENDIF.
  ENDMETHOD.


  METHOD percent.
    DATA lv_value TYPE p LENGTH 16 DECIMALS 1.
    lv_value = abs( CONV decfloat34( iv_value ) ).
    rv_text = |{ lv_value NUMBER = RAW }%|.
  ENDMETHOD.


  METHOD count_word.
    CONSTANTS lc_words TYPE string VALUE `no,one,two,three,four,five,six,seven,eight,nine,ten`.
    IF iv_count BETWEEN 0 AND 10.
      SPLIT lc_words AT ',' INTO TABLE DATA(lt_words).
      rv_text = lt_words[ iv_count + 1 ].
    ELSE.
      rv_text = |{ iv_count }|.
    ENDIF.
  ENDMETHOD.


  METHOD possessive.
    DATA(lv_name) = condense( CONV string( iv_name ) ).
    IF lv_name IS INITIAL.
      RETURN.
    ENDIF.
    IF substring( val = lv_name off = strlen( lv_name ) - 1 len = 1 ) = `s`.
      rv_text = |{ lv_name }'|.
    ELSE.
      rv_text = |{ lv_name }'s|.
    ENDIF.
  ENDMETHOD.


  METHOD number.
    DATA lv_fixed TYPE p LENGTH 16 DECIMALS 3.
    lv_fixed = round( val = CONV decfloat34( iv_value ) dec = iv_max_decimals ).
    rv_text  = |{ lv_fixed NUMBER = RAW }|.
    IF find( val = rv_text sub = `.` ) >= 0.
      rv_text = replace( val = rv_text pcre = `0+$` with = `` ).
      rv_text = replace( val = rv_text pcre = `\.$` with = `` ).
    ENDIF.
  ENDMETHOD.


  METHOD symbol.
    CASE iv_currency.
      WHEN 'USD' OR ''.
        rv_text = `$`.
      WHEN 'EUR'.
        rv_text = `€`.
      WHEN 'GBP'.
        rv_text = `£`.
      WHEN OTHERS.
        rv_text = |{ condense( CONV string( iv_currency ) ) } |.
    ENDCASE.
  ENDMETHOD.


  METHOD group_thousands.
    DATA(lv_digits) = |{ abs( iv_value ) }|.
    DATA(lv_len)    = strlen( lv_digits ).
    WHILE lv_len > 3.
      rv_text = |,{ substring( val = lv_digits off = lv_len - 3 len = 3 ) }{ rv_text }|.
      lv_len  = lv_len - 3.
    ENDWHILE.
    rv_text = |{ substring( val = lv_digits off = 0 len = lv_len ) }{ rv_text }|.
    IF iv_value < 0.
      rv_text = |-{ rv_text }|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

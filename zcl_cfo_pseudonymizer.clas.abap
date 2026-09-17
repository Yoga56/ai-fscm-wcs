"! <p class="shorttext synchronized">CFO Brief - replaces partner names by tokens for the AI call</p>
"! <p>Customer and supplier names never leave the system: "ABC Industries" becomes
"! CUSTOMER_1 in the prompt and is put back into the answer.</p>
CLASS zcl_cfo_pseudonymizer DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS: BEGIN OF kind,
                 customer TYPE c LENGTH 1 VALUE 'C',
                 supplier TYPE c LENGTH 1 VALUE 'S',
               END OF kind.

    METHODS register
      IMPORTING iv_name         TYPE clike
                iv_kind         TYPE c
      RETURNING VALUE(rv_token) TYPE string.

    METHODS mask
      IMPORTING iv_text        TYPE clike
      RETURNING VALUE(rv_text) TYPE string.

    METHODS unmask
      IMPORTING iv_text        TYPE clike
      RETURNING VALUE(rv_text) TYPE string.

  PRIVATE SECTION.

    TYPES: BEGIN OF ty_entry,
             name   TYPE string,
             token  TYPE string,
             length TYPE i,
           END OF ty_entry,
           tt_entry TYPE STANDARD TABLE OF ty_entry WITH EMPTY KEY.

    DATA mt_entries   TYPE tt_entry.
    DATA mv_customers TYPE i.
    DATA mv_suppliers TYPE i.

ENDCLASS.


CLASS zcl_cfo_pseudonymizer IMPLEMENTATION.

  METHOD register.
    DATA(lv_name) = condense( CONV string( iv_name ) ).
    " generic buckets and very short names are not identifying - and would mask too much
    IF strlen( lv_name ) < 3 OR lv_name CP 'Other *' OR lv_name CP 'Plant *'.
      rv_token = lv_name.
      RETURN.
    ENDIF.

    ASSIGN mt_entries[ name = lv_name ] TO FIELD-SYMBOL(<ls_entry>).
    IF sy-subrc = 0.
      rv_token = <ls_entry>-token.
      RETURN.
    ENDIF.

    IF iv_kind = kind-customer.
      mv_customers += 1.
      rv_token = |CUSTOMER_{ mv_customers }|.
    ELSE.
      mv_suppliers += 1.
      rv_token = |SUPPLIER_{ mv_suppliers }|.
    ENDIF.

    APPEND VALUE #( name = lv_name token = rv_token length = strlen( lv_name ) ) TO mt_entries.
    " longest names first, so "Delta Chemicals Ltd" is replaced before "Delta Chemicals"
    SORT mt_entries BY length DESCENDING.
  ENDMETHOD.


  METHOD mask.
    rv_text = iv_text.
    LOOP AT mt_entries INTO DATA(ls_entry).
      rv_text = replace( val = rv_text sub = ls_entry-name with = ls_entry-token occ = 0 ).
    ENDLOOP.
  ENDMETHOD.


  METHOD unmask.
    DATA lt_by_token TYPE tt_entry.
    rv_text = iv_text.
    " CUSTOMER_10 before CUSTOMER_1
    lt_by_token = mt_entries.
    LOOP AT lt_by_token ASSIGNING FIELD-SYMBOL(<ls_entry>).
      <ls_entry>-length = strlen( <ls_entry>-token ).
    ENDLOOP.
    SORT lt_by_token BY length DESCENDING token DESCENDING.
    LOOP AT lt_by_token INTO DATA(ls_entry).
      rv_text = replace( val = rv_text sub = ls_entry-token with = ls_entry-name occ = 0 ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

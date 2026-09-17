"! <p class="shorttext synchronized">CFO Daily Brief - application exception</p>
"! <p>Copied from ZCX_CC_ERROR (Clean Core Analyzer package) so this repository
"! has no cross-package dependency. Keep the two in sync if either changes.</p>
CLASS zcx_cfo_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    DATA text TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING text     TYPE string             OPTIONAL
                previous TYPE REF TO cx_root     OPTIONAL.

    "! Convenience factory so callers can RAISE EXCEPTION TYPE ... in one line.
    CLASS-METHODS raise
      IMPORTING text     TYPE string
                previous TYPE REF TO cx_root OPTIONAL
      RAISING   zcx_cfo_error.

ENDCLASS.

CLASS zcx_cfo_error IMPLEMENTATION.

  METHOD constructor.
    super->constructor( previous = previous ).
    me->text = text.
  ENDMETHOD.

  METHOD raise.
    RAISE EXCEPTION NEW zcx_cfo_error( text = text previous = previous ).
  ENDMETHOD.

ENDCLASS.

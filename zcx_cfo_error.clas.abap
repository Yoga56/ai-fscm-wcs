"! <p class="shorttext synchronized">CFO Daily Brief - application exception</p>
"! <p>Copied from ZCX_CC_ERROR (Clean Core Analyzer package) so this repository
"! has no cross-package dependency. Keep the two in sync if either changes.</p>
CLASS zcx_cfo_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    DATA text      TYPE string     READ-ONLY.
    "! Set by callers that try several alternatives in turn (e.g. a model
    "! fallback chain) to mean "this attempt failed, another might still work".
    DATA retryable TYPE abap_bool  READ-ONLY.

    METHODS constructor
      IMPORTING text      TYPE string             OPTIONAL
                previous  TYPE REF TO cx_root      OPTIONAL
                retryable TYPE abap_bool           DEFAULT abap_false.

    "! Convenience factory so callers can RAISE EXCEPTION TYPE ... in one line.
    CLASS-METHODS raise
      IMPORTING text      TYPE string
                previous  TYPE REF TO cx_root OPTIONAL
                retryable TYPE abap_bool      DEFAULT abap_false
      RAISING   zcx_cfo_error.

ENDCLASS.

CLASS zcx_cfo_error IMPLEMENTATION.

  METHOD constructor.
    super->constructor( previous = previous ).
    me->text      = text.
    me->retryable = retryable.
  ENDMETHOD.

  METHOD raise.
    RAISE EXCEPTION NEW zcx_cfo_error( text = text previous = previous retryable = retryable ).
  ENDMETHOD.

ENDCLASS.

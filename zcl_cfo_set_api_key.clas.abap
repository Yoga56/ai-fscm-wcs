"! <p class="shorttext synchronized">CFO Brief - one-time admin utility: writes the Gemini API key</p>
"! <p>ABAP Cloud has no selection-screen input for a class, so the key has to
"! sit in the source for one run. Do this edit only in ADT, directly on the
"! system - never in the local Git working copy:</p>
"! <ol>
"! <li>Replace C_API_KEY below with your real key.</li>
"! <li>Activate, run with F9. It prints whether the row was found and updated.</li>
"! <li>Immediately put back the placeholder text and activate again, so the key
"! never leaves this run and can never reach a future Push.</li>
"! </ol>
"! <p>Restrict change/display authority on ZTCFO_CONFIG (S_TABU_DIS / S_TABU_NAM)
"! to admins; this class does not add its own check.</p>
CLASS zcl_cfo_set_api_key DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CONSTANTS c_company_code TYPE ztcfo_config-company_code VALUE '1000'.
    " Replace only this line's value before running - see the class-level doc above.
    CONSTANTS c_api_key      TYPE string VALUE `REPLACE_WITH_YOUR_GEMINI_API_KEY`.

ENDCLASS.


CLASS zcl_cfo_set_api_key IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.

    IF c_api_key = `REPLACE_WITH_YOUR_GEMINI_API_KEY`.
      out->write( `C_API_KEY still has the placeholder value - edit it above, activate, run again.` ).
      RETURN.
    ENDIF.

    UPDATE ztcfo_config SET ai_api_key = @c_api_key WHERE company_code = @c_company_code.

    IF sy-subrc = 0.
      out->write( |API key saved for company code { c_company_code }.| ).
      out->write( `Now put the placeholder back above and activate again.` ).
    ELSE.
      out->write( |Company code { c_company_code } not found in ZTCFO_CONFIG - run ZCL_CFO_DEMO_SEED first.| ).
    ENDIF.

  ENDMETHOD.

ENDCLASS.

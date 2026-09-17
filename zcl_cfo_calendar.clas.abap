"! <p class="shorttext synchronized">CFO Brief - date helpers (Mon-Fri business days)</p>
"! <p>Weekends are the only non-working days here. To honour public holidays,
"! swap the body of IS_WORKING_DAY for the released factory calendar API
"! (CL_FHC_CALENDAR_RUNTIME) with your calendar id - every other method builds on it.</p>
CLASS zcl_cfo_calendar DEFINITION
  PUBLIC
  FINAL
  ABSTRACT.

  PUBLIC SECTION.

    "! 1 = Monday ... 7 = Sunday
    CLASS-METHODS weekday
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_day) TYPE i.

    CLASS-METHODS is_working_day
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_work) TYPE abap_bool.

    "! The date itself if it is a working day, otherwise the next one.
    CLASS-METHODS next_working_day
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_date) TYPE d.

    "! Moves n working days forward (n > 0) or backward (n < 0).
    CLASS-METHODS add_working_days
      IMPORTING iv_date        TYPE d
                iv_days        TYPE i
      RETURNING VALUE(rv_date) TYPE d.

    "! "Thu 6 Aug"
    CLASS-METHODS short_text
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_text) TYPE string.

    "! "2026-08-06"
    CLASS-METHODS iso
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS today
      RETURNING VALUE(rv_date) TYPE d.

ENDCLASS.


CLASS zcl_cfo_calendar IMPLEMENTATION.

  METHOD weekday.
    " 01.01.1900 was a Monday
    CONSTANTS lc_monday TYPE d VALUE '19000101'.
    DATA(lv_days) = CONV i( iv_date - lc_monday ).
    rv_day = ( lv_days MOD 7 ) + 1.
  ENDMETHOD.


  METHOD is_working_day.
    rv_work = xsdbool( weekday( iv_date ) <= 5 ).
  ENDMETHOD.


  METHOD next_working_day.
    rv_date = iv_date.
    WHILE is_working_day( rv_date ) = abap_false.
      rv_date = rv_date + 1.
    ENDWHILE.
  ENDMETHOD.


  METHOD add_working_days.
    DATA(lv_step)  = COND i( WHEN iv_days < 0 THEN -1 ELSE 1 ).
    DATA(lv_count) = abs( iv_days ).
    rv_date = iv_date.
    DO lv_count TIMES.
      rv_date = rv_date + lv_step.
      WHILE is_working_day( rv_date ) = abap_false.
        rv_date = rv_date + lv_step.
      ENDWHILE.
    ENDDO.
  ENDMETHOD.


  METHOD short_text.
    CONSTANTS lc_days   TYPE string VALUE `MonTueWedThuFriSatSun`.
    CONSTANTS lc_months TYPE string VALUE `JanFebMarAprMayJunJulAugSepOctNovDec`.
    IF iv_date IS INITIAL.
      RETURN.
    ENDIF.
    DATA(lv_wd)    = weekday( iv_date ).
    DATA(lv_month) = CONV i( iv_date+4(2) ).
    DATA(lv_day)   = CONV i( iv_date+6(2) ).
    rv_text = |{ substring( val = lc_days off = ( lv_wd - 1 ) * 3 len = 3 ) } { lv_day } | &&
              |{ substring( val = lc_months off = ( lv_month - 1 ) * 3 len = 3 ) }|.
  ENDMETHOD.


  METHOD iso.
    IF iv_date IS NOT INITIAL.
      rv_text = |{ iv_date+0(4) }-{ iv_date+4(2) }-{ iv_date+6(2) }|.
    ENDIF.
  ENDMETHOD.


  METHOD today.
    rv_date = cl_abap_context_info=>get_system_date( ).
  ENDMETHOD.

ENDCLASS.

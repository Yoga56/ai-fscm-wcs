*"* Pins the slide numbers - same expectations as app/cfobrief/test/engine.test.js.
*"* Uses ZCL_CFO_DEMO_SEED=>SCENARIO (in memory), no table contents needed.
CLASS ltcl_builder DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    CONSTANTS c_m TYPE i VALUE 1000000.

    CLASS-DATA gs_base TYPE zif_cfo_types=>ty_result.

    CLASS-METHODS class_setup.

    METHODS position        FOR TESTING.
    METHODS runway_days     FOR TESTING.
    METHODS ranking         FOR TESTING.
    METHODS advice          FOR TESTING.
    METHODS what_if_late    FOR TESTING.
    METHODS what_if_factor  FOR TESTING.
    METHODS what_if_hold    FOR TESTING.
    METHODS drafts          FOR TESTING.

    METHODS build
      IMPORTING is_sim           TYPE zif_cfo_types=>ty_sim OPTIONAL
      RETURNING VALUE(rs_result) TYPE zif_cfo_types=>ty_result.

    CLASS-METHODS advice_of
      IMPORTING it_advice        TYPE zif_cfo_types=>tt_advice
                iv_kind          TYPE clike
      RETURNING VALUE(rs_advice) TYPE zif_cfo_types=>ty_advice.
ENDCLASS.


CLASS ltcl_builder IMPLEMENTATION.

  METHOD class_setup.
    TRY.
        gs_base = NEW zcl_cfo_brief_builder( )->build( zcl_cfo_demo_seed=>scenario( ) ).
      CATCH zcx_cfo_error INTO DATA(lx_error).
        cl_abap_unit_assert=>fail( lx_error->text ).
    ENDTRY.
  ENDMETHOD.


  METHOD build.
    TRY.
        rs_result = NEW zcl_cfo_brief_builder( )->build( is_input = zcl_cfo_demo_seed=>scenario( ) is_sim = is_sim ).
      CATCH zcx_cfo_error INTO DATA(lx_error).
        cl_abap_unit_assert=>fail( lx_error->text ).
    ENDTRY.
  ENDMETHOD.


  METHOD advice_of.
    LOOP AT it_advice INTO rs_advice WHERE kind = iv_kind.
      RETURN.
    ENDLOOP.
    CLEAR rs_advice.
    cl_abap_unit_assert=>fail( |No advice of kind { iv_kind }| ).
  ENDMETHOD.


  METHOD position.
    DATA(ls_b) = gs_base-brief.
    cl_abap_unit_assert=>assert_equals( act = ls_b-cash_today         exp = CONV zif_cfo_types=>amount( 22 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-run_date           exp = CONV d( '20260806' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-run_total          exp = CONV zif_cfo_types=>amount( 12 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-run_invoice_count  exp = 180 ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-run_vendor_count   exp = 47 ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-cash_after_run     exp = CONV zif_cfo_types=>amount( 10 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-low_point          exp = CONV zif_cfo_types=>amount( 9500000 ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-low_point_day      exp = 9 ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-stressed_low_point exp = CONV zif_cfo_types=>amount( 5500000 ) ).
    cl_abap_unit_assert=>assert_true(  ls_b-floor_breach ).
    cl_abap_unit_assert=>assert_false( ls_b-scheduled_breach ).
    cl_abap_unit_assert=>assert_true(  ls_b-run_holds_floor ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-ar_total           exp = CONV zif_cfo_types=>amount( 85 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-ar_overdue         exp = CONV zif_cfo_types=>amount( 9 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-ap_total           exp = CONV zif_cfo_types=>amount( 100 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-ap_due_window      exp = CONV zif_cfo_types=>amount( 18 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-ar_overdue_chg_pct exp = CONV decfloat34( '11.9' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-ap_overdue_chg_pct exp = CONV decfloat34( '-5' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-review_count       exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-headline
                                        exp = `This week's run holds above floor — 3 items to review` ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_b-narrative
                                         exp = `*If ABC Industries' $4.0M pays late (~75%) → $5.5M — below floor.` ).
  ENDMETHOD.


  METHOD runway_days.
    cl_abap_unit_assert=>assert_equals( act = lines( gs_base-days ) exp = 31 ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-days[ day_index = 3 ]-closing_scheduled  exp = CONV zif_cfo_types=>amount( 9800000 ) ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-days[ day_index = 6 ]-closing_scheduled  exp = CONV zif_cfo_types=>amount( 13500000 ) ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-days[ day_index = 6 ]-closing_stressed   exp = CONV zif_cfo_types=>amount( 9500000 ) ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-days[ day_index = 14 ]-closing_scheduled exp = CONV zif_cfo_types=>amount( 16 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-days[ day_index = 30 ]-closing_scheduled exp = CONV zif_cfo_types=>amount( 12300000 ) ).
    cl_abap_unit_assert=>assert_true( gs_base-days[ day_index = 9 ]-is_low_point ).
    cl_abap_unit_assert=>assert_true( gs_base-days[ day_index = 9 ]-is_run_day ).
  ENDMETHOD.


  METHOD ranking.
    cl_abap_unit_assert=>assert_equals( act = lines( gs_base-risks ) exp = 4 ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-risks[ 1 ]-risk_type exp = zif_cfo_types=>risk_type-ar_late ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-risks[ 2 ]-risk_type exp = zif_cfo_types=>risk_type-ap_offpattern ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-risks[ 3 ]-risk_type exp = zif_cfo_types=>risk_type-spend_spike ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-risks[ 4 ]-risk_type exp = zif_cfo_types=>risk_type-ap_blocked ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-risks[ 1 ]-score       exp = CONV zif_cfo_types=>amount( 6 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-risks[ 1 ]-probability exp = CONV decfloat34( '0.75' ) ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-risks[ 1 ]-due_by      exp = CONV d( '20260810' ) ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-risks[ 2 ]-probability exp = CONV decfloat34( '0.86' ) ).
    cl_abap_unit_assert=>assert_equals( act = gs_base-risks[ 1 ]-recommendation_text
                                        exp = `Decide by Mon 10 Aug: chase or factor (funds ~3 days, before Day 9).` ).
  ENDMETHOD.


  METHOD advice.
    DATA(ls_defer) = advice_of( it_advice = gs_base-advice iv_kind = zif_cfo_types=>advice_kind-defer ).
    cl_abap_unit_assert=>assert_equals( act = ls_defer-defer_item       exp = CONV zif_cfo_types=>doc_id( 'AP-SPR-0001' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_defer-pay_item         exp = CONV zif_cfo_types=>doc_id( 'AP-RAW-0001' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_defer-shortfall_before exp = CONV zif_cfo_types=>amount( 2500000 ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_defer-confidence       exp = 'HIGH' ).

    " the slide says Fri 8 Aug - 4 Aug 2026 is a Tuesday, so the Friday is the 7th
    DATA(ls_prio) = advice_of( it_advice = gs_base-advice iv_kind = zif_cfo_types=>advice_kind-prioritize ).
    cl_abap_unit_assert=>assert_equals( act = ls_prio-action_date exp = CONV d( '20260807' ) ).

    DATA(ls_dep) = advice_of( it_advice = gs_base-advice iv_kind = zif_cfo_types=>advice_kind-deposit ).
    cl_abap_unit_assert=>assert_equals( act = ls_dep-amount exp = CONV zif_cfo_types=>amount( 3 * c_m ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_dep-income exp = CONV decfloat34( '1726.03' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_dep-status exp = zif_cfo_types=>advice_status-held ).

    DATA(ls_early) = advice_of( it_advice = gs_base-advice iv_kind = zif_cfo_types=>advice_kind-early_pay ).
    cl_abap_unit_assert=>assert_equals( act = ls_early-annualized_pct exp = CONV decfloat34( '37.2' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_early-income         exp = CONV zif_cfo_types=>amount( 20000 ) ).
  ENDMETHOD.


  METHOD what_if_late.
    DATA(ls_r) = build( VALUE #( late_ids = VALUE #( ( 'AR-ABC-0001' ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_r-brief-low_point exp = CONV zif_cfo_types=>amount( 5500000 ) ).
    cl_abap_unit_assert=>assert_true( ls_r-brief-scheduled_breach ).
  ENDMETHOD.


  METHOD what_if_factor.
    DATA(ls_r) = build( VALUE #( factor_ids = VALUE #( ( 'AR-ABC-0001' ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_r-brief-low_point          exp = CONV zif_cfo_types=>amount( 9400000 ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_r-brief-stressed_low_point exp = CONV zif_cfo_types=>amount( 9400000 ) ).
    cl_abap_unit_assert=>assert_false( ls_r-brief-floor_breach ).
  ENDMETHOD.


  METHOD what_if_hold.
    DATA(ls_r) = build( VALUE #( held_ids = VALUE #( ( 'AP-XYZ-0001' ) ) ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_r-days[ day_index = 3 ]-closing_scheduled exp = CONV zif_cfo_types=>amount( 12800000 ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_r-days[ day_index = 9 ]-closing_scheduled exp = CONV zif_cfo_types=>amount( 9500000 ) ).

    DATA(ls_f) = build( VALUE #( floor_override = 10 * c_m ) ).
    cl_abap_unit_assert=>assert_true( ls_f-brief-scheduled_breach ).
  ENDMETHOD.


  METHOD drafts.
    DATA(lo_drafter) = NEW zcl_cfo_drafter( zcl_cfo_demo_seed=>scenario( )-config ).

    DATA(ls_note) = lo_drafter->collection_notice( gs_base-risks[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( act = ls_note-subject exp = `ABC Industries — overdue balance $4.0M` ).
    cl_abap_unit_assert=>assert_equals( act = find( val = ls_note-body sub = `factor` case = abap_false ) exp = -1 ).

    DATA(ls_run) = lo_drafter->run_exceptions( is_brief = gs_base-brief it_risks = gs_base-risks ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_run-body exp = `*Release the remaining $7.5M as proposed.` ).
  ENDMETHOD.

ENDCLASS.


"! Helpers: calendar and formatting.
CLASS ltcl_helpers DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS calendar FOR TESTING.
    METHODS money    FOR TESTING.
ENDCLASS.


CLASS ltcl_helpers IMPLEMENTATION.

  METHOD calendar.
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_calendar=>weekday( '20260804' ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_calendar=>short_text( '20260807' ) exp = `Fri 7 Aug` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_calendar=>add_working_days( iv_date = '20260813' iv_days = -4 )
                                        exp = CONV d( '20260807' ) ).
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_calendar=>next_working_day( '20260808' ) exp = CONV d( '20260810' ) ).
  ENDMETHOD.


  METHOD money.
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_format=>money( 22000000 )  exp = `$22.0M` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_format=>money( 500000 )    exp = `$0.5M` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_format=>money( '1726.03' ) exp = `$1,726` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_format=>money( -1151 )     exp = `-$1,151` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_format=>number( CONV #( '4.200' ) ) exp = `4.2` ).
    cl_abap_unit_assert=>assert_equals( act = zcl_cfo_format=>possessive( `ABC Industries` ) exp = `ABC Industries'` ).
  ENDMETHOD.

ENDCLASS.

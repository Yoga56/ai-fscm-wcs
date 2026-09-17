*"* Local behaviour implementation for the CFO Daily Brief.
*"* All writes run IN LOCAL MODE: every field of the snapshot is read-only for
*"* consumers and owned by the engine. Nothing here posts to the ledger.

"! Snapshot mapping, authorization and small helpers shared by the handlers.
CLASS lcl_util DEFINITION FINAL ABSTRACT.

  PUBLIC SECTION.

    TYPES: BEGIN OF ty_uuid_map,
             id   TYPE c LENGTH 4,
             uuid TYPE sysuuid_x16,
           END OF ty_uuid_map,
           tt_uuid_map TYPE SORTED TABLE OF ty_uuid_map WITH UNIQUE KEY id.

    TYPES ty_brief_create TYPE STRUCTURE FOR CREATE zr_cfo_brief\\Brief.
    TYPES ty_brief_read   TYPE STRUCTURE FOR READ RESULT zr_cfo_brief\\Brief.
    TYPES ty_day_read     TYPE STRUCTURE FOR READ RESULT zr_cfo_brief\\RunwayDay.
    TYPES ty_risk_read    TYPE STRUCTURE FOR READ RESULT zr_cfo_brief\\Risk.
    TYPES ty_advice_read  TYPE STRUCTURE FOR READ RESULT zr_cfo_brief\\TradeOff.

    CLASS-METHODS authorized
      IMPORTING iv_company_code TYPE clike
                iv_activity     TYPE clike
      RETURNING VALUE(rv_ok)    TYPE abap_bool.

    CLASS-METHODS auth
      IMPORTING iv_ok          TYPE abap_bool
      RETURNING VALUE(rv_auth) TYPE abp_behv_auth.

    CLASS-METHODS split
      IMPORTING iv_list       TYPE clike
      RETURNING VALUE(rt_ids) TYPE zif_cfo_types=>tt_doc_id.

    CLASS-METHODS now
      RETURNING VALUE(rv_timestamp) TYPE timestampl.

    CLASS-METHODS user
      RETURNING VALUE(rv_user) TYPE string.

    "! Reads a persisted brief back into engine types (flows are not persisted).
    CLASS-METHODS snapshot
      IMPORTING iv_brief_uuid   TYPE sysuuid_x16
      EXPORTING es_result       TYPE zif_cfo_types=>ty_result
                es_config       TYPE zif_cfo_types=>ty_config
                et_risk_uuids   TYPE tt_uuid_map
                et_advice_uuids TYPE tt_uuid_map
      RAISING   zcx_cc_error.

    CLASS-METHODS brief_create
      IMPORTING is_brief        TYPE zif_cfo_types=>ty_brief
                iv_cid          TYPE clike
      RETURNING VALUE(rs_create) TYPE ty_brief_create.

    CLASS-METHODS brief_from
      IMPORTING is_row          TYPE ty_brief_read
      RETURNING VALUE(rs_brief) TYPE zif_cfo_types=>ty_brief.

    CLASS-METHODS risk_from
      IMPORTING is_row         TYPE ty_risk_read
      RETURNING VALUE(rs_risk) TYPE zif_cfo_types=>ty_risk.

    CLASS-METHODS advice_from
      IMPORTING is_row           TYPE ty_advice_read
      RETURNING VALUE(rs_advice) TYPE zif_cfo_types=>ty_advice.

ENDCLASS.


CLASS lcl_util IMPLEMENTATION.

  METHOD authorized.
    AUTHORITY-CHECK OBJECT 'ZCFO_BRF'
      ID 'BUKRS' FIELD iv_company_code
      ID 'ACTVT' FIELD iv_activity.
    rv_ok = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.


  METHOD auth.
    rv_auth = COND #( WHEN iv_ok = abap_true THEN if_abap_behv=>auth-allowed
                      ELSE if_abap_behv=>auth-unauthorized ).
  ENDMETHOD.


  METHOD split.
    SPLIT condense( CONV string( iv_list ) ) AT ',' INTO TABLE DATA(lt_parts).
    LOOP AT lt_parts INTO DATA(lv_part).
      lv_part = condense( lv_part ).
      IF lv_part IS NOT INITIAL.
        APPEND CONV zif_cfo_types=>doc_id( lv_part ) TO rt_ids.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD now.
    GET TIME STAMP FIELD rv_timestamp.
  ENDMETHOD.


  METHOD user.
    rv_user = cl_abap_context_info=>get_user_technical_name( ).
  ENDMETHOD.


  METHOD snapshot.

    CLEAR: es_result, es_config, et_risk_uuids, et_advice_uuids.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief
        ALL FIELDS WITH VALUE #( ( %key-BriefUuid = iv_brief_uuid ) )
        RESULT DATA(lt_brief)
      ENTITY Brief BY \_RunwayDay
        ALL FIELDS WITH VALUE #( ( %key-BriefUuid = iv_brief_uuid ) )
        RESULT DATA(lt_days)
      ENTITY Brief BY \_Risk
        ALL FIELDS WITH VALUE #( ( %key-BriefUuid = iv_brief_uuid ) )
        RESULT DATA(lt_risks)
      ENTITY Brief BY \_TradeOff
        ALL FIELDS WITH VALUE #( ( %key-BriefUuid = iv_brief_uuid ) )
        RESULT DATA(lt_advice).

    IF lt_brief IS INITIAL.
      zcx_cc_error=>raise( `Brief not found` ).
    ENDIF.

    es_result-brief = brief_from( lt_brief[ 1 ] ).
    es_config       = zcl_cfo_data_loader=>read_config( es_result-brief-company_code ).

    SORT lt_days   BY DayIndex.
    SORT lt_risks  BY RiskRank.
    SORT lt_advice BY Seq.

    LOOP AT lt_days INTO DATA(ls_day).
      APPEND VALUE #( day_index         = ls_day-DayIndex
                      calendar_date     = ls_day-CalendarDate
                      inflow            = ls_day-Inflow
                      outflow           = ls_day-Outflow
                      closing_scheduled = ls_day-ClosingScheduled
                      closing_stressed  = ls_day-ClosingStressed
                      closing_expected  = ls_day-ClosingExpected
                      floor_amount      = ls_day-FloorAmount
                      floor_delta       = ls_day-FloorDelta
                      is_weekend        = ls_day-IsWeekend
                      is_run_day        = ls_day-IsRunDay
                      is_low_point      = ls_day-IsLowPoint ) TO es_result-days.
    ENDLOOP.

    LOOP AT lt_risks INTO DATA(ls_risk).
      DATA(ls_engine_risk) = risk_from( ls_risk ).
      APPEND ls_engine_risk TO es_result-risks.
      INSERT VALUE #( id = ls_engine_risk-risk_id uuid = ls_risk-RiskUuid ) INTO TABLE et_risk_uuids.
    ENDLOOP.

    LOOP AT lt_advice INTO DATA(ls_advice).
      DATA(ls_engine_advice) = advice_from( ls_advice ).
      APPEND ls_engine_advice TO es_result-advice.
      INSERT VALUE #( id = ls_engine_advice-advice_id uuid = ls_advice-TradeoffUuid ) INTO TABLE et_advice_uuids.
    ENDLOOP.

    SPLIT es_result-brief-explain_text AT cl_abap_char_utilities=>newline INTO TABLE DATA(lt_lines).
    es_result-explains = VALUE #( FOR lv_line IN lt_lines ( text = lv_line ) ).

  ENDMETHOD.


  METHOD brief_create.
    rs_create = VALUE #( %cid = iv_cid
                         CompanyCode        = is_brief-company_code
                         BriefDate          = is_brief-brief_date
                         DataMode           = is_brief-data_mode
                         Currency           = is_brief-currency
                         HorizonDays        = is_brief-horizon_days
                         CashToday          = is_brief-cash_today
                         LiquidityFloor     = is_brief-liquidity_floor
                         RunDate            = is_brief-run_date
                         NextRunDate        = is_brief-next_run_date
                         RunTotal           = is_brief-run_total
                         RunInvoiceCount    = is_brief-run_invoice_count
                         RunVendorCount     = is_brief-run_vendor_count
                         CashAfterRun       = is_brief-cash_after_run
                         RunHoldsFloor      = is_brief-run_holds_floor
                         LowPoint           = is_brief-low_point
                         LowPointDay        = is_brief-low_point_day
                         LowPointDate       = is_brief-low_point_date
                         StressedLowPoint   = is_brief-stressed_low_point
                         StressedLowDay     = is_brief-stressed_low_day
                         Headroom           = is_brief-headroom
                         FloorBreach        = is_brief-floor_breach
                         ScheduledBreach    = is_brief-scheduled_breach
                         ArTotal            = is_brief-ar_total
                         ArOverdue          = is_brief-ar_overdue
                         ArOverdueChangePct = is_brief-ar_overdue_chg_pct
                         ApTotal            = is_brief-ap_total
                         ApDueWindow        = is_brief-ap_due_window
                         ApOverdue          = is_brief-ap_overdue
                         ApOverdueChangePct = is_brief-ap_overdue_chg_pct
                         ReviewCount        = is_brief-review_count
                         Headline           = is_brief-headline
                         Narrative          = is_brief-narrative
                         ExplainText        = is_brief-explain_text
                         Engine             = is_brief-engine
                         ModelUsed          = is_brief-model_used
                         ErrorText          = is_brief-error_text ).
    rs_create-GeneratedAt = now( ).
  ENDMETHOD.


  METHOD brief_from.
    rs_brief = VALUE #( company_code       = is_row-CompanyCode
                        brief_date         = is_row-BriefDate
                        data_mode          = is_row-DataMode
                        currency           = is_row-Currency
                        horizon_days       = is_row-HorizonDays
                        cash_today         = is_row-CashToday
                        liquidity_floor    = is_row-LiquidityFloor
                        run_date           = is_row-RunDate
                        next_run_date      = is_row-NextRunDate
                        run_total          = is_row-RunTotal
                        run_invoice_count  = is_row-RunInvoiceCount
                        run_vendor_count   = is_row-RunVendorCount
                        cash_after_run     = is_row-CashAfterRun
                        run_holds_floor    = is_row-RunHoldsFloor
                        low_point          = is_row-LowPoint
                        low_point_day      = is_row-LowPointDay
                        low_point_date     = is_row-LowPointDate
                        stressed_low_point = is_row-StressedLowPoint
                        stressed_low_day   = is_row-StressedLowDay
                        headroom           = is_row-Headroom
                        floor_breach       = is_row-FloorBreach
                        scheduled_breach   = is_row-ScheduledBreach
                        ar_total           = is_row-ArTotal
                        ar_overdue         = is_row-ArOverdue
                        ar_overdue_chg_pct = is_row-ArOverdueChangePct
                        ap_total           = is_row-ApTotal
                        ap_due_window      = is_row-ApDueWindow
                        ap_overdue         = is_row-ApOverdue
                        ap_overdue_chg_pct = is_row-ApOverdueChangePct
                        review_count       = is_row-ReviewCount
                        headline           = is_row-Headline
                        narrative          = is_row-Narrative
                        explain_text       = is_row-ExplainText
                        engine             = is_row-Engine
                        model_used         = is_row-ModelUsed
                        error_text         = is_row-ErrorText ).
  ENDMETHOD.


  METHOD risk_from.
    rs_risk = VALUE #( risk_rank           = is_row-RiskRank
                       risk_type           = is_row-RiskType
                       epard               = is_row-Epard
                       reference           = is_row-Reference
                       partner_name        = is_row-PartnerName
                       title               = is_row-Title
                       detail              = is_row-Detail
                       exposure            = is_row-Exposure
                       probability         = is_row-Probability
                       floor_weight        = is_row-FloorWeight
                       score               = is_row-Score
                       criticality         = is_row-Criticality
                       recommendation      = is_row-Recommendation
                       recommendation_text = is_row-RecommendationText
                       ai_note             = is_row-AiNote
                       due_by              = is_row-DueBy
                       status              = is_row-Status ).
    rs_risk-risk_id = |R{ is_row-RiskRank }|.
  ENDMETHOD.


  METHOD advice_from.
    rs_advice = VALUE #( seq              = is_row-Seq
                         kind             = is_row-Kind
                         title            = is_row-Title
                         question         = is_row-Question
                         defer_item       = is_row-DeferItem
                         defer_name       = is_row-DeferName
                         defer_partner    = is_row-DeferPartner
                         defer_amount     = is_row-DeferAmount
                         defer_note       = is_row-DeferNote
                         defer_cost       = is_row-DeferCost
                         pay_item         = is_row-PayItem
                         pay_name         = is_row-PayName
                         pay_partner      = is_row-PayPartner
                         pay_amount       = is_row-PayAmount
                         pay_note         = is_row-PayNote
                         shortfall_before = is_row-ShortfallBefore
                         shortfall_after  = is_row-ShortfallAfter
                         amount           = is_row-Amount
                         income           = is_row-Income
                         annualized_pct   = is_row-AnnualizedPct
                         recommendation   = is_row-Recommendation
                         detail           = is_row-Detail
                         caveat           = is_row-Caveat
                         confidence       = is_row-Confidence
                         confidence_note  = is_row-ConfidenceNote
                         status           = is_row-Status
                         action_date      = is_row-ActionDate
                         ai_note          = is_row-AiNote ).
    rs_advice-advice_id = |A{ is_row-Seq }|.
  ENDMETHOD.

ENDCLASS.


**********************************************************************
* Brief
**********************************************************************
CLASS lhc_brief DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Brief RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Brief RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Brief RESULT result.

    METHODS generateBrief FOR MODIFY
      IMPORTING keys FOR ACTION Brief~generateBrief RESULT result.

    METHODS refreshAi FOR MODIFY
      IMPORTING keys FOR ACTION Brief~refreshAi RESULT result.

    METHODS simulate FOR MODIFY
      IMPORTING keys FOR ACTION Brief~simulate RESULT result.

    METHODS askCopilot FOR MODIFY
      IMPORTING keys FOR ACTION Brief~askCopilot RESULT result.

    METHODS proposeRunExceptions FOR MODIFY
      IMPORTING keys FOR ACTION Brief~proposeRunExceptions RESULT result.

ENDCLASS.


CLASS lhc_brief IMPLEMENTATION.

  METHOD get_global_authorizations.
    IF requested_authorizations-%action-generateBrief = if_abap_behv=>mk-on.
      AUTHORITY-CHECK OBJECT 'ZCFO_BRF'
        ID 'BUKRS' DUMMY
        ID 'ACTVT' FIELD zif_cfo_types=>activity-generate.
      result-%action-generateBrief = lcl_util=>auth( xsdbool( sy-subrc = 0 ) ).
    ENDIF.
  ENDMETHOD.


  METHOD get_instance_authorizations.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief
        FIELDS ( CompanyCode ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_briefs)
      FAILED failed.

    LOOP AT lt_briefs INTO DATA(ls_brief).
      DATA(lv_display)  = lcl_util=>authorized( iv_company_code = ls_brief-CompanyCode iv_activity = zif_cfo_types=>activity-display ).
      DATA(lv_change)   = lcl_util=>authorized( iv_company_code = ls_brief-CompanyCode iv_activity = zif_cfo_types=>activity-change ).
      DATA(lv_generate) = lcl_util=>authorized( iv_company_code = ls_brief-CompanyCode iv_activity = zif_cfo_types=>activity-generate ).
      DATA(lv_delete)   = lcl_util=>authorized( iv_company_code = ls_brief-CompanyCode iv_activity = zif_cfo_types=>activity-delete ).

      APPEND VALUE #( %tky                          = ls_brief-%tky
                      %update                       = lcl_util=>auth( lv_change )
                      %delete                       = lcl_util=>auth( lv_delete )
                      %action-refreshAi             = lcl_util=>auth( lv_generate )
                      %action-simulate              = lcl_util=>auth( lv_display )
                      %action-askCopilot            = lcl_util=>auth( lv_display )
                      %action-proposeRunExceptions  = lcl_util=>auth( lv_change ) ) TO result.
    ENDLOOP.

  ENDMETHOD.


  METHOD get_instance_features.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief
        FIELDS ( ReviewCount ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_briefs)
      FAILED failed.

    result = VALUE #( FOR ls_brief IN lt_briefs
                      ( %tky = ls_brief-%tky
                        %action-proposeRunExceptions = COND #( WHEN ls_brief-ReviewCount > 0
                                                               THEN if_abap_behv=>fc-o-enabled
                                                               ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.


**********************************************************************
* generateBrief - P, E, R, A on live or demo data, then AI words
**********************************************************************
  METHOD generateBrief.

    TYPES: BEGIN OF ty_pending,
             action_cid TYPE abp_behv_cid,
             brief_cid  TYPE abp_behv_cid,
             engine     TYPE c LENGTH 6,
             error      TYPE string,
           END OF ty_pending.

    DATA lt_pending  TYPE STANDARD TABLE OF ty_pending WITH EMPTY KEY.
    DATA lt_root     TYPE TABLE FOR CREATE zr_cfo_brief\\Brief.
    DATA lt_cba_day  TYPE TABLE FOR CREATE zr_cfo_brief\\Brief\_RunwayDay.
    DATA lt_cba_risk TYPE TABLE FOR CREATE zr_cfo_brief\\Brief\_Risk.
    DATA lt_cba_adv  TYPE TABLE FOR CREATE zr_cfo_brief\\Brief\_TradeOff.
    DATA ls_cba_day  LIKE LINE OF lt_cba_day.
    DATA ls_cba_risk LIKE LINE OF lt_cba_risk.
    DATA ls_cba_adv  LIKE LINE OF lt_cba_adv.
    DATA ls_input    TYPE zif_cfo_types=>ty_input.
    DATA ls_result   TYPE zif_cfo_types=>ty_result.
    DATA lv_count    TYPE i.

    LOOP AT keys INTO DATA(ls_key).

      DATA(lv_company) = ls_key-%param-CompanyCode.

      IF lcl_util=>authorized( iv_company_code = lv_company
                               iv_activity     = zif_cfo_types=>activity-generate ) = abap_false.
        APPEND VALUE #( %cid = ls_key-%cid %fail-cause = if_abap_behv=>cause-unauthorized ) TO failed-brief.
        APPEND VALUE #( %cid = ls_key-%cid
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |No authorization to generate briefs for company code { lv_company }| ) )
               TO reported-brief.
        CONTINUE.
      ENDIF.

      CLEAR: ls_input, ls_result.
      TRY.
          ls_input  = NEW zcl_cfo_data_loader( )->load( iv_company_code = lv_company
                                                       iv_key_date     = ls_key-%param-BriefDate ).
          ls_result = NEW zcl_cfo_brief_builder( )->build( ls_input ).
        CATCH zcx_cc_error INTO DATA(lx_error).
          APPEND VALUE #( %cid = ls_key-%cid %fail-cause = if_abap_behv=>cause-unspecific ) TO failed-brief.
          APPEND VALUE #( %cid = ls_key-%cid
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->text ) ) TO reported-brief.
          CONTINUE.
      ENDTRY.

      " words: Gemini when available, the rule text otherwise - numbers never change
      NEW zcl_cfo_ai_advisor( ls_input-config )->enrich( CHANGING cs_result = ls_result ).

      lv_count += 1.
      DATA(lv_cid) = CONV abp_behv_cid( |BRIEF{ lv_count }| ).
      DATA(lv_cur) = ls_result-brief-currency.

      APPEND lcl_util=>brief_create( is_brief = ls_result-brief iv_cid = lv_cid ) TO lt_root.

      CLEAR ls_cba_day.
      ls_cba_day-%cid_ref = lv_cid.
      LOOP AT ls_result-days INTO DATA(ls_day).
        APPEND VALUE #( %cid     = |{ lv_cid }D{ ls_day-day_index }|
                        Currency = lv_cur
                        DayIndex         = ls_day-day_index
                        CalendarDate     = ls_day-calendar_date
                        Inflow           = ls_day-inflow
                        Outflow          = ls_day-outflow
                        ClosingScheduled = ls_day-closing_scheduled
                        ClosingStressed  = ls_day-closing_stressed
                        ClosingExpected  = ls_day-closing_expected
                        FloorAmount      = ls_day-floor_amount
                        FloorDelta       = ls_day-floor_delta
                        IsWeekend        = ls_day-is_weekend
                        IsRunDay         = ls_day-is_run_day
                        IsLowPoint       = ls_day-is_low_point ) TO ls_cba_day-%target.
      ENDLOOP.
      APPEND ls_cba_day TO lt_cba_day.

      CLEAR ls_cba_risk.
      ls_cba_risk-%cid_ref = lv_cid.
      LOOP AT ls_result-risks INTO DATA(ls_risk).
        APPEND VALUE #( %cid     = |{ lv_cid }R{ ls_risk-risk_rank }|
                        Currency = lv_cur
                        HasDraft = abap_false
                        RiskRank           = ls_risk-risk_rank
                        RiskType           = ls_risk-risk_type
                        Epard              = ls_risk-epard
                        Reference          = ls_risk-reference
                        PartnerName        = ls_risk-partner_name
                        Title              = ls_risk-title
                        Detail             = ls_risk-detail
                        Exposure           = ls_risk-exposure
                        Probability        = ls_risk-probability
                        FloorWeight        = ls_risk-floor_weight
                        Score              = ls_risk-score
                        Criticality        = ls_risk-criticality
                        Recommendation     = ls_risk-recommendation
                        RecommendationText = ls_risk-recommendation_text
                        AiNote             = ls_risk-ai_note
                        DueBy              = ls_risk-due_by
                        Status             = ls_risk-status ) TO ls_cba_risk-%target.
      ENDLOOP.
      APPEND ls_cba_risk TO lt_cba_risk.

      CLEAR ls_cba_adv.
      ls_cba_adv-%cid_ref = lv_cid.
      LOOP AT ls_result-advice INTO DATA(ls_advice).
        APPEND VALUE #( %cid     = |{ lv_cid }A{ ls_advice-seq }|
                        Currency = lv_cur
                        HasDraft = abap_false
                        Seq             = ls_advice-seq
                        Kind            = ls_advice-kind
                        Title           = ls_advice-title
                        Question        = ls_advice-question
                        DeferItem       = ls_advice-defer_item
                        DeferName       = ls_advice-defer_name
                        DeferPartner    = ls_advice-defer_partner
                        DeferAmount     = ls_advice-defer_amount
                        DeferNote       = ls_advice-defer_note
                        DeferCost       = ls_advice-defer_cost
                        PayItem         = ls_advice-pay_item
                        PayName         = ls_advice-pay_name
                        PayPartner      = ls_advice-pay_partner
                        PayAmount       = ls_advice-pay_amount
                        PayNote         = ls_advice-pay_note
                        ShortfallBefore = ls_advice-shortfall_before
                        ShortfallAfter  = ls_advice-shortfall_after
                        Amount          = ls_advice-amount
                        Income          = ls_advice-income
                        AnnualizedPct   = ls_advice-annualized_pct
                        Recommendation  = ls_advice-recommendation
                        Detail          = ls_advice-detail
                        Caveat          = ls_advice-caveat
                        Confidence      = ls_advice-confidence
                        ConfidenceNote  = ls_advice-confidence_note
                        Status          = ls_advice-status
                        ActionDate      = ls_advice-action_date
                        AiNote          = ls_advice-ai_note ) TO ls_cba_adv-%target.
      ENDLOOP.
      APPEND ls_cba_adv TO lt_cba_adv.

      APPEND VALUE #( action_cid = ls_key-%cid
                      brief_cid  = lv_cid
                      engine     = ls_result-brief-engine
                      error      = ls_result-brief-error_text ) TO lt_pending.
    ENDLOOP.

    IF lt_root IS INITIAL.
      RETURN.
    ENDIF.

    MODIFY ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief
        CREATE FIELDS ( CompanyCode BriefDate DataMode Currency HorizonDays
                            CashToday LiquidityFloor RunDate NextRunDate RunTotal
                            RunInvoiceCount RunVendorCount CashAfterRun RunHoldsFloor LowPoint
                            LowPointDay LowPointDate StressedLowPoint StressedLowDay Headroom
                            FloorBreach ScheduledBreach ArTotal ArOverdue ArOverdueChangePct
                            ApTotal ApDueWindow ApOverdue ApOverdueChangePct ReviewCount
                            Headline Narrative ExplainText Engine ModelUsed
                            ErrorText GeneratedAt )
        WITH lt_root
        CREATE BY \_RunwayDay
        FIELDS ( Currency DayIndex CalendarDate Inflow Outflow ClosingScheduled
                            ClosingStressed ClosingExpected FloorAmount FloorDelta IsWeekend
                            IsRunDay IsLowPoint )
        WITH lt_cba_day
        CREATE BY \_Risk
        FIELDS ( Currency HasDraft RiskRank RiskType Epard Reference PartnerName
                            Title Detail Exposure Probability FloorWeight
                            Score Criticality Recommendation RecommendationText AiNote
                            DueBy Status )
        WITH lt_cba_risk
        CREATE BY \_TradeOff
        FIELDS ( Currency HasDraft Seq Kind Title Question DeferItem
                            DeferName DeferPartner DeferAmount DeferNote DeferCost
                            PayItem PayName PayPartner PayAmount PayNote
                            ShortfallBefore ShortfallAfter Amount Income AnnualizedPct
                            Recommendation Detail Caveat Confidence ConfidenceNote
                            Status ActionDate AiNote )
        WITH lt_cba_adv
      MAPPED DATA(ls_mapped)
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    LOOP AT lt_pending INTO DATA(ls_pending).
      ASSIGN ls_mapped-brief[ %cid = ls_pending-brief_cid ] TO FIELD-SYMBOL(<ls_mapped>).
      IF sy-subrc <> 0.
        APPEND VALUE #( %cid = ls_pending-action_cid %fail-cause = if_abap_behv=>cause-unspecific ) TO failed-brief.
        APPEND VALUE #( %cid = ls_pending-action_cid
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `The brief could not be saved` ) ) TO reported-brief.
        CONTINUE.
      ENDIF.

      READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
        ENTITY Brief ALL FIELDS WITH VALUE #( ( %tky = <ls_mapped>-%tky ) )
        RESULT DATA(lt_new).

      IF lt_new IS NOT INITIAL.
        APPEND VALUE #( %cid = ls_pending-action_cid %param = CORRESPONDING #( lt_new[ 1 ] ) ) TO result.
        APPEND VALUE #( %cid = ls_pending-action_cid
                        %msg = new_message_with_text(
                                 severity = COND #( WHEN ls_pending-error IS INITIAL
                                                    THEN if_abap_behv_message=>severity-success
                                                    ELSE if_abap_behv_message=>severity-warning )
                                 text     = |{ lt_new[ 1 ]-Headline } ({ ls_pending-engine }| &&
                                            |{ COND string( WHEN ls_pending-error IS NOT INITIAL
                                                            THEN |: { ls_pending-error }| ) })| ) )
               TO reported-brief.
      ENDIF.
      UNASSIGN <ls_mapped>.
    ENDLOOP.

  ENDMETHOD.


**********************************************************************
* refreshAi - re-run only the words on the stored snapshot
**********************************************************************
  METHOD refreshAi.

    DATA lt_upd_brief TYPE TABLE FOR UPDATE zr_cfo_brief\\Brief.
    DATA lt_upd_risk  TYPE TABLE FOR UPDATE zr_cfo_brief\\Risk.
    DATA lt_upd_adv   TYPE TABLE FOR UPDATE zr_cfo_brief\\TradeOff.
    DATA ls_result    TYPE zif_cfo_types=>ty_result.
    DATA ls_config    TYPE zif_cfo_types=>ty_config.
    DATA lt_risk_ids  TYPE lcl_util=>tt_uuid_map.
    DATA lt_adv_ids   TYPE lcl_util=>tt_uuid_map.

    LOOP AT keys INTO DATA(ls_key).
      TRY.
          lcl_util=>snapshot( EXPORTING iv_brief_uuid   = ls_key-BriefUuid
                              IMPORTING es_result       = ls_result
                                        es_config       = ls_config
                                        et_risk_uuids   = lt_risk_ids
                                        et_advice_uuids = lt_adv_ids ).
        CATCH zcx_cc_error INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_key-%tky ) TO failed-brief.
          APPEND VALUE #( %tky = ls_key-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->text ) ) TO reported-brief.
          CONTINUE.
      ENDTRY.

      NEW zcl_cfo_ai_advisor( ls_config )->enrich( CHANGING cs_result = ls_result ).

      APPEND VALUE #( %tky      = ls_key-%tky
                      Headline  = ls_result-brief-headline
                      Narrative = ls_result-brief-narrative
                      Engine    = ls_result-brief-engine
                      ModelUsed = ls_result-brief-model_used
                      ErrorText = ls_result-brief-error_text ) TO lt_upd_brief.

      LOOP AT ls_result-risks INTO DATA(ls_risk).
        ASSIGN lt_risk_ids[ id = ls_risk-risk_id ] TO FIELD-SYMBOL(<ls_rid>).
        IF sy-subrc = 0.
          APPEND VALUE #( RiskUuid = <ls_rid>-uuid AiNote = ls_risk-ai_note ) TO lt_upd_risk.
        ENDIF.
      ENDLOOP.
      LOOP AT ls_result-advice INTO DATA(ls_advice).
        ASSIGN lt_adv_ids[ id = ls_advice-advice_id ] TO FIELD-SYMBOL(<ls_aid>).
        IF sy-subrc = 0.
          APPEND VALUE #( TradeoffUuid = <ls_aid>-uuid AiNote = ls_advice-ai_note ) TO lt_upd_adv.
        ENDIF.
      ENDLOOP.

      APPEND VALUE #( %tky = ls_key-%tky
                      %msg = new_message_with_text(
                               severity = COND #( WHEN ls_result-brief-error_text IS INITIAL
                                                  THEN if_abap_behv_message=>severity-success
                                                  ELSE if_abap_behv_message=>severity-warning )
                               text     = COND #( WHEN ls_result-brief-error_text IS INITIAL
                                                  THEN |Narrative refreshed ({ ls_result-brief-model_used })|
                                                  ELSE ls_result-brief-error_text ) ) ) TO reported-brief.
    ENDLOOP.

    MODIFY ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief    UPDATE FIELDS ( Headline Narrative Engine ModelUsed ErrorText ) WITH lt_upd_brief
      ENTITY Risk     UPDATE FIELDS ( AiNote ) WITH lt_upd_risk
      ENTITY TradeOff UPDATE FIELDS ( AiNote ) WITH lt_upd_adv
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_briefs).

    result = VALUE #( FOR ls_brief IN lt_briefs ( %tky = ls_brief-%tky %param = CORRESPONDING #( ls_brief ) ) ).

  ENDMETHOD.


**********************************************************************
* simulate - what-if toggles, nothing is stored
**********************************************************************
  METHOD simulate.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief
        FIELDS ( CompanyCode BriefDate Currency ) WITH CORRESPONDING #( keys )
        RESULT DATA(lt_briefs)
      ENTITY Brief BY \_RunwayDay
        FIELDS ( BriefUuid DayIndex ClosingScheduled ) WITH CORRESPONDING #( keys )
        RESULT DATA(lt_days)
      FAILED failed.

    LOOP AT keys INTO DATA(ls_key).

      ASSIGN lt_briefs[ KEY id %tky = ls_key-%tky ] TO FIELD-SYMBOL(<ls_brief>).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      DATA(ls_sim) = VALUE zif_cfo_types=>ty_sim(
        late_ids       = lcl_util=>split( ls_key-%param-LateItems )
        held_ids       = lcl_util=>split( ls_key-%param-HeldItems )
        factor_ids     = lcl_util=>split( ls_key-%param-FactorItems )
        run_delay_days = ls_key-%param-RunDelayDays
        floor_override = ls_key-%param-FloorOverride ).

      TRY.
          DATA(ls_input) = NEW zcl_cfo_data_loader( )->load( iv_company_code = <ls_brief>-CompanyCode
                                                            iv_key_date     = <ls_brief>-BriefDate ).
          DATA(ls_scen)  = NEW zcl_cfo_brief_builder( )->build( is_input = ls_input is_sim = ls_sim ).
        CATCH zcx_cc_error INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_key-%tky ) TO failed-brief.
          APPEND VALUE #( %tky = ls_key-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->text ) ) TO reported-brief.
          CONTINUE.
      ENDTRY.

      DATA(ls_b)       = ls_scen-brief.
      DATA(lv_summary) = |Scenario low { zcl_cfo_format=>money( iv_amount = ls_b-low_point iv_currency = ls_b-currency ) } | &&
                         |on Day { ls_b-low_point_day } — | &&
                         |{ COND string( WHEN ls_b-scheduled_breach = abap_true THEN `below` ELSE `above` ) } | &&
                         |the { zcl_cfo_format=>money( iv_amount = ls_b-liquidity_floor iv_currency = ls_b-currency ) } floor; | &&
                         |if the at-risk receipts are late: | &&
                         |{ zcl_cfo_format=>money( iv_amount = ls_b-stressed_low_point iv_currency = ls_b-currency ) }.|.

      LOOP AT ls_scen-days INTO DATA(ls_day).
        ASSIGN lt_days[ BriefUuid = ls_key-BriefUuid DayIndex = ls_day-day_index ] TO FIELD-SYMBOL(<ls_base>).
        APPEND VALUE #( %tky   = ls_key-%tky
                        %param = VALUE #( DayIndex       = ls_day-day_index
                                          CalendarDate   = ls_day-calendar_date
                                          Currency       = ls_b-currency
                                          Baseline       = COND #( WHEN <ls_base> IS ASSIGNED
                                                                   THEN <ls_base>-ClosingScheduled
                                                                   ELSE ls_day-closing_scheduled )
                                          Scenario       = ls_day-closing_scheduled
                                          Stressed       = ls_day-closing_stressed
                                          FloorAmount    = ls_day-floor_amount
                                          IsRunDay       = ls_day-is_run_day
                                          IsLowPoint     = ls_day-is_low_point
                                          ScenarioLow    = ls_b-low_point
                                          ScenarioLowDay = ls_b-low_point_day
                                          StressedLow    = ls_b-stressed_low_point
                                          StressedLowDay = ls_b-stressed_low_day
                                          ScenarioBreach = ls_b-scheduled_breach
                                          StressedBreach = ls_b-floor_breach
                                          Summary        = lv_summary ) ) TO result.
        UNASSIGN <ls_base>.
      ENDLOOP.
      UNASSIGN <ls_brief>.
    ENDLOOP.

  ENDMETHOD.


**********************************************************************
* askCopilot - grounded Q&A on one brief
**********************************************************************
  METHOD askCopilot.

    DATA ls_result TYPE zif_cfo_types=>ty_result.
    DATA ls_config TYPE zif_cfo_types=>ty_config.

    LOOP AT keys INTO DATA(ls_key).
      TRY.
          lcl_util=>snapshot( EXPORTING iv_brief_uuid = ls_key-BriefUuid
                              IMPORTING es_result     = ls_result
                                        es_config     = ls_config ).
        CATCH zcx_cc_error INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_key-%tky ) TO failed-brief.
          APPEND VALUE #( %tky = ls_key-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->text ) ) TO reported-brief.
          CONTINUE.
      ENDTRY.

      IF ls_key-%param-Question IS INITIAL.
        APPEND VALUE #( %tky = ls_key-%tky ) TO failed-brief.
        APPEND VALUE #( %tky = ls_key-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = `Please enter a question` ) ) TO reported-brief.
        CONTINUE.
      ENDIF.

      DATA(ls_answer) = NEW zcl_cfo_ai_advisor( ls_config )->answer( is_result   = ls_result
                                                                     iv_question = ls_key-%param-Question ).

      APPEND VALUE #( %tky   = ls_key-%tky
                      %param = VALUE #( Answer    = ls_answer-answer
                                        FollowUps = ls_answer-follow_ups
                                        Engine    = ls_answer-engine
                                        ModelUsed = ls_answer-model_used
                                        ErrorText = ls_answer-error_text ) ) TO result.
    ENDLOOP.

  ENDMETHOD.


**********************************************************************
* proposeRunExceptions - exception list for the payment run owner
**********************************************************************
  METHOD proposeRunExceptions.

    DATA lt_cba    TYPE TABLE FOR CREATE zr_cfo_brief\\Brief\_ActionDraft.
    DATA ls_cba    LIKE LINE OF lt_cba.
    DATA ls_result TYPE zif_cfo_types=>ty_result.
    DATA ls_config TYPE zif_cfo_types=>ty_config.
    DATA lv_count  TYPE i.

    LOOP AT keys INTO DATA(ls_key).
      TRY.
          lcl_util=>snapshot( EXPORTING iv_brief_uuid = ls_key-BriefUuid
                              IMPORTING es_result     = ls_result
                                        es_config     = ls_config ).
        CATCH zcx_cc_error INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_key-%tky ) TO failed-brief.
          APPEND VALUE #( %tky = ls_key-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->text ) ) TO reported-brief.
          CONTINUE.
      ENDTRY.

      lv_count += 1.
      DATA(ls_draft) = NEW zcl_cfo_drafter( ls_config )->run_exceptions( is_brief = ls_result-brief
                                                                         it_risks = ls_result-risks ).
      NEW zcl_cfo_ai_advisor( ls_config )->polish( EXPORTING is_result = ls_result
                                                   CHANGING  cs_draft  = ls_draft ).

      CLEAR ls_cba.
      ls_cba-%tky = ls_key-%tky.
      APPEND VALUE #( %cid         = |RUN{ lv_count }|
                      ActionType   = ls_draft-action_type
                      SourceKind   = 'BRIEF'
                      SourceUuid   = ls_key-BriefUuid
                      Recipient    = ls_draft-recipient
                      Subject      = ls_draft-subject
                      Body         = ls_draft-body
                      InternalNote = ls_draft-internal_note
                      Currency     = ls_result-brief-currency
                      Amount       = ls_draft-amount
                      Status       = zif_cfo_types=>action_status-draft
                      Engine       = ls_draft-engine ) TO ls_cba-%target.
      APPEND ls_cba TO lt_cba.
    ENDLOOP.

    MODIFY ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief
        CREATE BY \_ActionDraft
        FIELDS ( ActionType SourceKind SourceUuid Recipient Subject Body InternalNote
                 Currency Amount Status Engine )
        WITH lt_cba
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_briefs).

    result = VALUE #( FOR ls_brief IN lt_briefs ( %tky = ls_brief-%tky %param = CORRESPONDING #( ls_brief ) ) ).

  ENDMETHOD.

ENDCLASS.


**********************************************************************
* Risk
**********************************************************************
CLASS lhc_risk DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Risk RESULT result.

    METHODS draftCollectionNotice FOR MODIFY
      IMPORTING keys FOR ACTION Risk~draftCollectionNotice RESULT result.

ENDCLASS.


CLASS lhc_risk IMPLEMENTATION.

  METHOD get_instance_features.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Risk
        FIELDS ( RiskType HasDraft ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_risks)
      FAILED failed.

    result = VALUE #( FOR ls_risk IN lt_risks
                      ( %tky = ls_risk-%tky
                        %action-draftCollectionNotice =
                          COND #( WHEN ls_risk-RiskType = zif_cfo_types=>risk_type-ar_late
                                   AND ls_risk-HasDraft = abap_false
                                  THEN if_abap_behv=>fc-o-enabled
                                  ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.


  METHOD draftCollectionNotice.

    DATA lt_cba    TYPE TABLE FOR CREATE zr_cfo_brief\\Brief\_ActionDraft.
    DATA ls_cba    LIKE LINE OF lt_cba.
    DATA lt_upd    TYPE TABLE FOR UPDATE zr_cfo_brief\\Risk.
    DATA ls_result TYPE zif_cfo_types=>ty_result.
    DATA ls_config TYPE zif_cfo_types=>ty_config.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Risk ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_risks)
      FAILED failed.

    LOOP AT lt_risks INTO DATA(ls_row).
      TRY.
          lcl_util=>snapshot( EXPORTING iv_brief_uuid = ls_row-BriefUuid
                              IMPORTING es_result     = ls_result
                                        es_config     = ls_config ).
        CATCH zcx_cc_error INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_row-%tky ) TO failed-risk.
          APPEND VALUE #( %tky = ls_row-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->text ) ) TO reported-risk.
          CONTINUE.
      ENDTRY.

      DATA(ls_draft) = NEW zcl_cfo_drafter( ls_config )->collection_notice( lcl_util=>risk_from( ls_row ) ).
      NEW zcl_cfo_ai_advisor( ls_config )->polish( EXPORTING is_result = ls_result
                                                   CHANGING  cs_draft  = ls_draft ).

      CLEAR ls_cba.
      ls_cba-BriefUuid = ls_row-BriefUuid.
      APPEND VALUE #( %cid         = |NOTE{ ls_row-RiskRank }|
                      ActionType   = ls_draft-action_type
                      SourceKind   = 'RISK'
                      SourceUuid   = ls_row-RiskUuid
                      Recipient    = ls_draft-recipient
                      Subject      = ls_draft-subject
                      Body         = ls_draft-body
                      InternalNote = ls_draft-internal_note
                      Currency     = ls_row-Currency
                      Amount       = ls_draft-amount
                      Status       = zif_cfo_types=>action_status-draft
                      Engine       = ls_draft-engine ) TO ls_cba-%target.
      APPEND ls_cba TO lt_cba.
      APPEND VALUE #( %tky = ls_row-%tky HasDraft = abap_true ) TO lt_upd.
    ENDLOOP.

    MODIFY ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief
        CREATE BY \_ActionDraft
        FIELDS ( ActionType SourceKind SourceUuid Recipient Subject Body InternalNote
                 Currency Amount Status Engine )
        WITH lt_cba
      ENTITY Risk
        UPDATE FIELDS ( HasDraft ) WITH lt_upd
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Risk ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).

    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).

  ENDMETHOD.

ENDCLASS.


**********************************************************************
* TradeOff
**********************************************************************
CLASS lhc_tradeoff DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR TradeOff RESULT result.

    METHODS proposeDecision FOR MODIFY
      IMPORTING keys FOR ACTION TradeOff~proposeDecision RESULT result.

ENDCLASS.


CLASS lhc_tradeoff IMPLEMENTATION.

  METHOD get_instance_features.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY TradeOff
        FIELDS ( HasDraft ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_rows)
      FAILED failed.

    result = VALUE #( FOR ls_row IN lt_rows
                      ( %tky = ls_row-%tky
                        %action-proposeDecision = COND #( WHEN ls_row-HasDraft = abap_false
                                                          THEN if_abap_behv=>fc-o-enabled
                                                          ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.


  METHOD proposeDecision.

    DATA lt_cba    TYPE TABLE FOR CREATE zr_cfo_brief\\Brief\_ActionDraft.
    DATA ls_cba    LIKE LINE OF lt_cba.
    DATA lt_upd    TYPE TABLE FOR UPDATE zr_cfo_brief\\TradeOff.
    DATA ls_result TYPE zif_cfo_types=>ty_result.
    DATA ls_config TYPE zif_cfo_types=>ty_config.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY TradeOff ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_rows)
      FAILED failed.

    LOOP AT lt_rows INTO DATA(ls_row).
      TRY.
          lcl_util=>snapshot( EXPORTING iv_brief_uuid = ls_row-BriefUuid
                              IMPORTING es_result     = ls_result
                                        es_config     = ls_config ).
        CATCH zcx_cc_error INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_row-%tky ) TO failed-tradeoff.
          APPEND VALUE #( %tky = ls_row-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                        text     = lx_error->text ) ) TO reported-tradeoff.
          CONTINUE.
      ENDTRY.

      DATA(ls_draft) = NEW zcl_cfo_drafter( ls_config )->for_advice( lcl_util=>advice_from( ls_row ) ).
      IF ls_draft-action_type IS INITIAL.
        CONTINUE.
      ENDIF.
      NEW zcl_cfo_ai_advisor( ls_config )->polish( EXPORTING is_result = ls_result
                                                   CHANGING  cs_draft  = ls_draft ).

      CLEAR ls_cba.
      ls_cba-BriefUuid = ls_row-BriefUuid.
      APPEND VALUE #( %cid         = |ADV{ ls_row-Seq }|
                      ActionType   = ls_draft-action_type
                      SourceKind   = 'TRADEOFF'
                      SourceUuid   = ls_row-TradeoffUuid
                      Recipient    = ls_draft-recipient
                      Subject      = ls_draft-subject
                      Body         = ls_draft-body
                      InternalNote = ls_draft-internal_note
                      Currency     = ls_row-Currency
                      Amount       = ls_draft-amount
                      Status       = zif_cfo_types=>action_status-draft
                      Engine       = ls_draft-engine ) TO ls_cba-%target.
      APPEND ls_cba TO lt_cba.
      APPEND VALUE #( %tky = ls_row-%tky HasDraft = abap_true ) TO lt_upd.
    ENDLOOP.

    MODIFY ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY Brief
        CREATE BY \_ActionDraft
        FIELDS ( ActionType SourceKind SourceUuid Recipient Subject Body InternalNote
                 Currency Amount Status Engine )
        WITH lt_cba
      ENTITY TradeOff
        UPDATE FIELDS ( HasDraft ) WITH lt_upd
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY TradeOff ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).

    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).

  ENDMETHOD.

ENDCLASS.


**********************************************************************
* ActionDraft - edit, route, approve / reject (never executes)
**********************************************************************
CLASS lhc_actiondraft DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR ActionDraft RESULT result.

    METHODS validateContent FOR VALIDATE ON SAVE
      IMPORTING keys FOR ActionDraft~validateContent.

    METHODS submitForApproval FOR MODIFY
      IMPORTING keys FOR ACTION ActionDraft~submitForApproval RESULT result.

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION ActionDraft~approve RESULT result.

    METHODS reject FOR MODIFY
      IMPORTING keys FOR ACTION ActionDraft~reject RESULT result.

    TYPES: BEGIN OF ty_outcome,
             action_uuid TYPE sysuuid_x16,
             problem     TYPE string,
           END OF ty_outcome,
           tt_outcome TYPE STANDARD TABLE OF ty_outcome WITH EMPTY KEY.

    "! Shared by approve and reject: checks, updates, and returns one outcome per key.
    METHODS decide
      IMPORTING it_keys            TYPE TABLE FOR ACTION IMPORT zr_cfo_brief\\ActionDraft~approve
                iv_status          TYPE clike
      RETURNING VALUE(rt_outcomes) TYPE tt_outcome.

ENDCLASS.


CLASS lhc_actiondraft IMPLEMENTATION.

  METHOD get_instance_features.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY ActionDraft
        FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_rows)
      FAILED failed.

    LOOP AT lt_rows INTO DATA(ls_row).
      DATA(lv_draft)  = xsdbool( ls_row-Status = zif_cfo_types=>action_status-draft ).
      DATA(lv_routed) = xsdbool( ls_row-Status = zif_cfo_types=>action_status-routed ).
      APPEND VALUE #( %tky                      = ls_row-%tky
                      %update                   = COND #( WHEN lv_draft = abap_true
                                                          THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
                      %delete                   = COND #( WHEN lv_draft = abap_true
                                                          THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
                      %action-submitForApproval = COND #( WHEN lv_draft = abap_true
                                                          THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
                      %action-approve           = COND #( WHEN lv_routed = abap_true
                                                          THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled )
                      %action-reject            = COND #( WHEN lv_routed = abap_true
                                                          THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled ) )
             TO result.
    ENDLOOP.

  ENDMETHOD.


  METHOD validateContent.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY ActionDraft
        FIELDS ( Recipient Subject Body ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_rows).

    LOOP AT lt_rows INTO DATA(ls_row).
      APPEND VALUE #( %tky = ls_row-%tky %state_area = 'CONTENT' ) TO reported-actiondraft.
      IF ls_row-Recipient IS INITIAL OR ls_row-Subject IS INITIAL OR ls_row-Body IS INITIAL.
        APPEND VALUE #( %tky = ls_row-%tky ) TO failed-actiondraft.
        APPEND VALUE #( %tky        = ls_row-%tky
                        %state_area = 'CONTENT'
                        %msg        = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                             text     = `Recipient, subject and text are required` ) )
               TO reported-actiondraft.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD submitForApproval.

    DATA lt_upd TYPE TABLE FOR UPDATE zr_cfo_brief\\ActionDraft.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY ActionDraft BY \_Brief
        FIELDS ( CompanyCode ) WITH CORRESPONDING #( keys )
        RESULT DATA(lt_briefs)
        LINK DATA(lt_links).

    LOOP AT keys INTO DATA(ls_key).
      DATA(lv_to) = VALUE string( ).
      ASSIGN lt_links[ source-ActionUuid = ls_key-ActionUuid ] TO FIELD-SYMBOL(<ls_link>).
      IF sy-subrc = 0.
        ASSIGN lt_briefs[ BriefUuid = <ls_link>-target-BriefUuid ] TO FIELD-SYMBOL(<ls_brief>).
        IF sy-subrc = 0.
          TRY.
              lv_to = zcl_cfo_data_loader=>read_config( <ls_brief>-CompanyCode )-approver_email.
            CATCH zcx_cc_error.
              CLEAR lv_to.
          ENDTRY.
        ENDIF.
      ENDIF.

      APPEND VALUE #( %tky     = ls_key-%tky
                      Status   = zif_cfo_types=>action_status-routed
                      RoutedTo = COND #( WHEN lv_to IS NOT INITIAL THEN lv_to ELSE `Approver (no e-mail configured)` )
                      RoutedAt = lcl_util=>now( ) ) TO lt_upd.
      UNASSIGN: <ls_link>, <ls_brief>.
    ENDLOOP.

    MODIFY ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY ActionDraft
        UPDATE FIELDS ( Status RoutedTo RoutedAt ) WITH lt_upd
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY ActionDraft ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).

    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).

    LOOP AT lt_after INTO DATA(ls_after).
      APPEND VALUE #( %tky = ls_after-%tky
                      %msg = new_message_with_text( severity = if_abap_behv_message=>severity-success
                                                    text     = |Routed to { ls_after-RoutedTo }| ) ) TO reported-actiondraft.
    ENDLOOP.

  ENDMETHOD.


  METHOD approve.
    DATA(lt_outcomes) = decide( it_keys = keys iv_status = zif_cfo_types=>action_status-approved ).
    LOOP AT lt_outcomes INTO DATA(ls_outcome).
      IF ls_outcome-problem IS NOT INITIAL.
        APPEND VALUE #( ActionUuid = ls_outcome-action_uuid %fail-cause = if_abap_behv=>cause-unauthorized )
               TO failed-actiondraft.
      ENDIF.
      APPEND VALUE #( ActionUuid = ls_outcome-action_uuid
                      %msg = new_message_with_text(
                               severity = COND #( WHEN ls_outcome-problem IS INITIAL
                                                  THEN if_abap_behv_message=>severity-success
                                                  ELSE if_abap_behv_message=>severity-error )
                               text     = COND #( WHEN ls_outcome-problem IS INITIAL
                                                  THEN `Approved - the owning team executes it in its own app`
                                                  ELSE ls_outcome-problem ) ) ) TO reported-actiondraft.
    ENDLOOP.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY ActionDraft ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD reject.
    DATA lt_keys TYPE TABLE FOR ACTION IMPORT zr_cfo_brief\\ActionDraft~approve.
    lt_keys = CORRESPONDING #( keys ).
    DATA(lt_outcomes) = decide( it_keys = lt_keys iv_status = zif_cfo_types=>action_status-rejected ).
    LOOP AT lt_outcomes INTO DATA(ls_outcome).
      IF ls_outcome-problem IS NOT INITIAL.
        APPEND VALUE #( ActionUuid = ls_outcome-action_uuid %fail-cause = if_abap_behv=>cause-unauthorized )
               TO failed-actiondraft.
      ENDIF.
      APPEND VALUE #( ActionUuid = ls_outcome-action_uuid
                      %msg = new_message_with_text(
                               severity = COND #( WHEN ls_outcome-problem IS INITIAL
                                                  THEN if_abap_behv_message=>severity-success
                                                  ELSE if_abap_behv_message=>severity-error )
                               text     = COND #( WHEN ls_outcome-problem IS INITIAL
                                                  THEN `Rejected`
                                                  ELSE ls_outcome-problem ) ) ) TO reported-actiondraft.
    ENDLOOP.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY ActionDraft ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_after).
    result = VALUE #( FOR ls_after IN lt_after ( %tky = ls_after-%tky %param = CORRESPONDING #( ls_after ) ) ).
  ENDMETHOD.


  METHOD decide.

    DATA lt_upd TYPE TABLE FOR UPDATE zr_cfo_brief\\ActionDraft.

    READ ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY ActionDraft
        FIELDS ( CreatedBy ) WITH CORRESPONDING #( it_keys )
        RESULT DATA(lt_rows)
      ENTITY ActionDraft BY \_Brief
        FIELDS ( CompanyCode ) WITH CORRESPONDING #( it_keys )
        RESULT DATA(lt_briefs)
        LINK DATA(lt_links).

    DATA(lv_user) = lcl_util=>user( ).

    FIELD-SYMBOLS <ls_row>   LIKE LINE OF lt_rows.
    FIELD-SYMBOLS <ls_link>  LIKE LINE OF lt_links.
    FIELD-SYMBOLS <ls_brief> LIKE LINE OF lt_briefs.

    LOOP AT it_keys INTO DATA(ls_key).
      UNASSIGN: <ls_row>, <ls_link>, <ls_brief>.
      ASSIGN lt_rows[ ActionUuid = ls_key-ActionUuid ] TO <ls_row>.
      ASSIGN lt_links[ source-ActionUuid = ls_key-ActionUuid ] TO <ls_link>.
      IF <ls_row> IS NOT ASSIGNED OR <ls_link> IS NOT ASSIGNED.
        APPEND VALUE #( action_uuid = ls_key-ActionUuid problem = `Action draft not found` ) TO rt_outcomes.
        CONTINUE.
      ENDIF.
      ASSIGN lt_briefs[ BriefUuid = <ls_link>-target-BriefUuid ] TO <ls_brief>.
      IF <ls_brief> IS NOT ASSIGNED.
        APPEND VALUE #( action_uuid = ls_key-ActionUuid problem = `Brief not found` ) TO rt_outcomes.
        CONTINUE.
      ENDIF.

      DATA(lv_company) = <ls_brief>-CompanyCode.
      DATA(lv_problem) = VALUE string( ).

      IF lcl_util=>authorized( iv_company_code = lv_company
                               iv_activity     = zif_cfo_types=>activity-approve ) = abap_false.
        lv_problem = |No authorization to decide on actions for company code { lv_company }|.
      ELSE.
        TRY.
            IF zcl_cfo_data_loader=>read_config( lv_company )-four_eyes = abap_true
               AND <ls_row>-CreatedBy = lv_user.
              lv_problem = `Four-eyes principle: the author of a draft cannot decide on it`.
            ENDIF.
          CATCH zcx_cc_error INTO DATA(lx_error).
            lv_problem = lx_error->text.
        ENDTRY.
      ENDIF.

      APPEND VALUE #( action_uuid = ls_key-ActionUuid problem = lv_problem ) TO rt_outcomes.
      IF lv_problem IS INITIAL.
        APPEND VALUE #( %tky         = ls_key-%tky
                        Status       = iv_status
                        DecidedBy    = lv_user
                        DecidedAt    = lcl_util=>now( )
                        DecisionNote = ls_key-%param-Note ) TO lt_upd.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zr_cfo_brief IN LOCAL MODE
      ENTITY ActionDraft
        UPDATE FIELDS ( Status DecidedBy DecidedAt DecisionNote ) WITH lt_upd
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

  ENDMETHOD.

ENDCLASS.


**********************************************************************
* Saver - routing e-mail once the "routed" status is saved
**********************************************************************
CLASS lsc_zr_cfo_brief DEFINITION INHERITING FROM cl_abap_behavior_saver.

  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.

ENDCLASS.


CLASS lsc_zr_cfo_brief IMPLEMENTATION.

  METHOD save_modified.

    LOOP AT update-actiondraft INTO DATA(ls_action).
      IF ls_action-%control-Status <> if_abap_behv=>mk-on
         OR ls_action-Status <> zif_cfo_types=>action_status-routed.
        CONTINUE.
      ENDIF.

      SELECT SINGLE FROM ztcfo_brief
        FIELDS company_code, headline
        WHERE brief_uuid = @ls_action-BriefUuid
        INTO @DATA(ls_brief).
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      TRY.
          DATA(ls_config) = zcl_cfo_data_loader=>read_config( ls_brief-company_code ).
          zcl_cfo_mailer=>send_approval_request(
            is_config   = ls_config
            iv_headline = ls_brief-headline
            iv_type     = ls_action-ActionType
            iv_subject  = ls_action-Subject
            iv_body     = ls_action-Body
            iv_note     = ls_action-InternalNote
            iv_author   = ls_action-CreatedBy ).
        CATCH zcx_cc_error INTO DATA(lx_error).
          APPEND VALUE #( %tky = ls_action-%tky
                          %msg = new_message_with_text( severity = if_abap_behv_message=>severity-warning
                                                        text     = |Routed, but no e-mail sent: { lx_error->text }| ) )
                 TO reported-actiondraft.
      ENDTRY.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.
